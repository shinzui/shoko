{-# LANGUAGE CPP #-}
{-# LANGUAGE RankNTypes #-}

module EventStore.Contract (tests) where

import Control.Concurrent (forkIO, killThread, newEmptyMVar, putMVar, takeMVar, threadDelay)
import Control.Exception (bracket, finally)
import Control.Monad (replicateM_, unless, when)
import Data.Aeson (Value (..), object, (.=))
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Functor.Contravariant ((>$<))
import Data.IORef
import Data.Set qualified as Set
import Data.String (fromString)
import Data.Text qualified as Text
import Data.Time (getCurrentTime)
import Data.UUID qualified as UUID
import Data.Unique (hashUnique, newUnique)
import Data.Vector qualified as Vector
import Hasql.Connection qualified as C
import Hasql.Connection.Settings qualified as CS
import Hasql.Decoders qualified as D
import Hasql.Encoders qualified as E
import Hasql.Session qualified as S
import Hasql.Statement (preparable)
import Hedgehog (evalIO, property, withTests)
import Kiroku.Store.SQL qualified as K
import Shoko hiding (observe)
import Shoko.Adapter.EventStore
import Shoko.Adapter.Kiroku qualified as Kiroku
import Shoko.Adapter.MessageDb qualified as MessageDb
import Shoko.Clock
import Shoko.Observation qualified as Observation
import Shoko.Result
import Shoko.Result.Json
import System.Environment (getEnv)
import System.Timeout (timeout)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

data Backend
  = Backend
      !(Clock -> Text.Text -> IO (Either Text.Text Baseline))
      !(CallContext -> IO (ObservationOutcome (EventEvidence Bool)))
      !BindingContract

data Store = KirokuStore | MessageDbStore deriving stock (Eq, Show)

check :: Bool -> IO ()
check value = unless value (fail "event-store contract assertion failed")

test :: String -> IO () -> TestTree
test title action = testPropertyNamed title (fromString title) (withTests 1 (property (evalIO bounded)))
  where
    bounded = timeout 15000000 action >>= maybe (fail "event-store test deadline") pure

right :: Either Text.Text a -> IO a
right = either (fail . Text.unpack) pure

freshScope :: IO Text.Text
freshScope = ("fixture" <>) . Text.pack . show . hashUnique <$> newUnique

open :: Store -> Text.Text -> EventScope -> Limits -> CorrelationMode -> IO Backend
open store settings scope bounded mode = do
  query <- right (eventQuery bounded scope AppendOnlyDuringRun mode "Happened" (\case Object _ -> Right True; _ -> Left "invalid-fixture-event"))
  openQuery store settings query

openQuery :: Store -> Text.Text -> EventQuery Bool -> IO Backend
openQuery store settings query = case store of
  KirokuStore -> do
    resource <- Kiroku.kiroku settings "kiroku" "event-fixture" query >>= right
    pure (Backend (Kiroku.kirokuBaseline resource) (\call -> Kiroku.observeKiroku call resource) (Kiroku.kirokuContract "event-fixture" query))
  MessageDbStore -> do
    resource <- MessageDb.messageDb settings "event-fixture" query >>= right
    metadata <- maybe (fail "unsupported fixture contract") pure (MessageDb.messageDbContract "event-fixture" query)
    pure (Backend (MessageDb.messageDbBaseline resource) (\call -> MessageDb.observeMessageDb call resource) metadata)

withConnection :: Text.Text -> (C.Connection -> IO a) -> IO a
withConnection settings action = bracket (C.acquire (CS.connectionString settings)) (either (const (pure ())) C.release) $ \case
  Left _ -> fail "fixture connection failed"
  Right connection -> action connection

session :: C.Connection -> S.Session a -> IO a
session connection operation = C.use connection operation >>= either (const (fail "fixture session failed")) pure

append :: Store -> C.Connection -> Text.Text -> Value -> IO ()
append store connection stream body = appendWithExecution store connection stream body Nothing

appendWithExecution :: Store -> C.Connection -> Text.Text -> Value -> Maybe UUID.UUID -> IO ()
appendWithExecution store connection stream body execution = do
  unique <- hashUnique <$> newUnique
  let key = UUID.fromWords 0 0 0 (fromIntegral unique)
  timestamp <- getCurrentTime
  wrote <- session connection $ case store of
    KirokuStore -> do
      S.script "SET search_path TO kiroku, pg_catalog"
      result <- S.statement (K.AppendParams (Vector.singleton key) (Vector.singleton "Happened") (Vector.singleton execution) (Vector.singleton execution) (Vector.singleton body) (Vector.singleton Nothing) (Vector.singleton timestamp) stream) K.appendAnyVersion
      pure (case result of Nothing -> False; Just _ -> True)
    MessageDbStore -> do
      S.script "SET search_path TO message_store, pg_catalog"
      _ <- S.statement (UUID.toText key, stream, body) writeMessage
      pure True
  check wrote
  where
    writeMessage =
      preparable
        "SELECT write_message($1::varchar, $2::varchar, 'Happened'::varchar, $3, NULL, NULL)"
        ( ((\(key, _, _) -> key) >$< E.param (E.nonNullable E.text))
            <> ((\(_, streamName, _) -> streamName) >$< E.param (E.nonNullable E.text))
            <> ((\(_, _, value) -> value) >$< E.param (E.nonNullable E.jsonb))
        )
        (D.singleRow (D.column (D.nonNullable D.int8)))

eventBody :: Text.Text -> Value
eventBody key = object ["accountId" .= key]

write :: Store -> Text.Text -> Text.Text -> Text.Text -> Int -> IO ()
write store settings category key count = withConnection settings $ \connection ->
  replicateM_ count (append store connection (category <> "-one") (eventBody key))

data Op a where
  Produce :: Op Text.Text
  Events :: Op (EventEvidence Bool)

instance Vocabulary Op where
  describeOperation Produce = OperationInfo "fixture.append" (Set.fromList [WriteState, SyntheticResource]) [] []
  describeOperation Events = OperationInfo "fixture.read" (Set.singleton ReadEvents) [] []

run :: Backend -> Text.Text -> IO () -> Text.Text -> IO (RunResult, Int)
run backend selected emit assertion = do
  polls <- newIORef (0 :: Int)
  budget <- right (milliseconds 4000)
  window <- right (milliseconds 200)
  poll <- right (milliseconds 20)
  let Backend capture observe contract = backend
      binding =
        Binding
          "event-fixture"
          Set.empty
          lookupContract
          (\_ -> pure ())
          (\_ -> pure Retained)
          (\_ -> capture)
          (\_ _ -> \case Produce -> emit >> pure (ActionObserved "appended" selected); _ -> pure (ActionUnavailable "unsupported"))
          (\_ call -> \case Events -> modifyIORef' polls (+ 1) >> observe call; _ -> pure (ObservationUnavailable "unsupported"))
      lookupContract :: OperationRole -> Op a -> Maybe BindingContract
      lookupContract ObservationOperation Events = Just contract
      lookupContract ActionOperation Produce = Just (BindingContract Set.empty Set.empty (Set.singleton BusinessKey) Nothing SampledState)
      lookupContract _ _ = Nothing
      scenarioValue = scenario "event-store-contract" "Real store evidence" "1" $ do
        _ <- act "produce" (accept ["appended"] Produce)
        let observation = Observation.observe "event-matches" Events (\(EventEvidence _ _ _ value) -> value)
        expect $ within window $ case assertion of
          "never" -> never "absent" observation
          "eventually" -> eventually "present" observation
          _ -> exactlyOnce "one-event" observation
      environment = Environment "local-event-fixture" False (Set.fromList [ReadEvents, WriteState, SyntheticResource]) (Policy budget window poll budget)
  resolved <-
    either
      (const (fail "fixture preflight failed"))
      pure
      (resolveScenario environment (RunOptions "event-run" True "fixture-build" Nothing Nothing) (BusinessKeyFrom "accountId" (pure selected)) binding scenarioValue)
  result <- runScenario realClock (LogicalInput "fixture-v1" []) resolved
  count <- readIORef polls
  check (decodeRunResult (encodeRunResult result) == Right result)
  check (not ("SECRET-FIXTURE" `BS.isInfixOf` BL.toStrict (encodeRunResult result)))
  pure (result, count)

expectVerdict :: Verdict -> (RunResult, Int) -> IO ()
expectVerdict wanted (Verification (VerificationResult _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ actual _ _ _), _) = check (actual == wanted)
expectVerdict _ _ = fail "unexpected fixture runner fault"

makeCall :: Baseline -> Integer -> IO CallContext
makeCall base cutoff = do
  let Clock now _ _ _ = realClock
  current <- now
  pure (CallContext (const (Left "unused")) (current + 2000000) (Just base) (Just (ByBusinessKey "accountId" "one")) (\_ _ -> pure (Left "unused")) cutoff realClock)

deniedBeforeAllocation :: BindingContract -> IO resource -> (resource -> Clock -> Text.Text -> IO (Either Text.Text Baseline)) -> (CallContext -> resource -> IO (ObservationOutcome (EventEvidence Bool))) -> IO ()
deniedBeforeAllocation metadata allocate capture observe = do
  allocations <- newIORef (0 :: Int)
  let lookupContract :: OperationRole -> Op a -> Maybe BindingContract
      lookupContract ObservationOperation Events = Just metadata
      lookupContract _ _ = Nothing
      binding =
        Binding
          "pure-event-contract"
          Set.empty
          lookupContract
          (\_ -> modifyIORef' allocations (+ 1) >> allocate)
          (const (pure Retained))
          capture
          (\_ _ _ -> pure (ActionUnavailable "unsupported"))
          (\resource context -> \case Events -> observe context resource; _ -> pure (ObservationUnavailable "unsupported"))
      selected =
        scenario "policy-only" "Reader contract preflight" "1" $
          expect (eventually "event" (Observation.observe "matches" Events (\(EventEvidence _ _ _ value) -> value)))
      environment = Environment "denied" False Set.empty defaultPolicy
  case resolveScenario environment (RunOptions "denied-run" False "fixture-build" Nothing Nothing) (BusinessKeyFrom "accountId" (pure "one")) binding selected of
    Left errors -> check (errors == [CapabilitiesDenied (Set.singleton ReadEvents)])
    Right _ -> fail "event-reader policy unexpectedly permitted allocation"
  readIORef allocations >>= check . (== 0)

tests :: IO TestTree
tests = do
  selected <- getEnv "SHOKO_EVENT_STORE"
  store <- case selected of "kiroku" -> pure KirokuStore; "message-db" -> pure MessageDbStore; _ -> fail "selected real store is required"
  readSettings <- Text.pack <$> getEnv "SHOKO_EVENT_READ"
  writeSettings <- Text.pack <$> getEnv "SHOKO_EVENT_WRITE"
  putStrLn ("Compiled kiroku-store " <> VERSION_kiroku_store <> "; actual selected store: " <> selected)
  bounded <- right (limits 1 20 2000)
  let setup = do
        category <- freshScope
        scope <- right (categoryScope category)
        reader <- open store readSettings scope bounded (BusinessKeyField "accountId")
        pure (category, reader)
  pure $
    testGroup
      ("real " <> selected)
      [ test "pure contracts reject policy before allocating a reader" $ do
          category <- freshScope
          scope <- right (categoryScope category)
          query <- right (eventQuery bounded scope AppendOnlyDuringRun (BusinessKeyField "accountId") "Happened" (const (Right True)))
          case store of
            KirokuStore -> deniedBeforeAllocation (Kiroku.kirokuContract "event-fixture" query) (Kiroku.kiroku readSettings "kiroku" "event-fixture" query >>= right) Kiroku.kirokuBaseline Kiroku.observeKiroku
            MessageDbStore -> do
              metadata <- maybe (fail "missing pure legacy contract") pure (MessageDb.messageDbContract "event-fixture" query)
              deniedBeforeAllocation metadata (MessageDb.messageDb readSettings "event-fixture" query >>= right) MessageDb.messageDbBaseline MessageDb.observeMessageDb,
        test "append then exactlyOnce passes across repeated one-row pages" $ do
          (category, reader) <- setup
          result@(_, polls) <- run reader "one" (write store writeSettings category "one" 1) "exactly-once"
          expectVerdict Pass result
          check (polls > 1),
        test "two distinct occurrence IDs fail cardinality" $ do
          (category, reader) <- setup
          run reader "one" (write store writeSettings category "one" 2) "exactly-once" >>= expectVerdict Fail,
        test "complete empty scan passes never and fails eventually" $ do
          (_, reader) <- setup
          run reader "one" (pure ()) "never" >>= expectVerdict Pass
          run reader "one" (pure ()) "eventually" >>= expectVerdict Fail,
        test "unrelated business keys cannot satisfy the query" $ do
          (category, reader) <- setup
          run reader "one" (write store writeSettings category "other" 2) "eventually" >>= expectVerdict Fail,
        test "pre-action baseline excludes historical matching events" $ do
          (category, reader) <- setup
          write store writeSettings category "one" 1
          run reader "one" (pure ()) "eventually" >>= expectVerdict Fail,
        test "selected stream and a second independent reader see identical occurrences" $ do
          category <- freshScope
          scope <- right (streamScope (category <> "-one"))
          first@(Backend base1 read1 _) <- open store readSettings scope bounded (BusinessKeyField "accountId")
          Backend base2 read2 _ <- open store readSettings scope bounded (BusinessKeyField "accountId")
          b1 <- base1 realClock "event-fixture" >>= right
          b2 <- base2 realClock "event-fixture" >>= right
          write store writeSettings category "one" 1
          let Clock now _ _ _ = realClock
          cutoff <- (+ 2000000) <$> now
          a <- makeCall b1 cutoff >>= read1
          b <- makeCall b2 cutoff >>= read2
          case (a, b) of
            (ObservedWithDetails [Occurrence id1 _] _ _, ObservedWithDetails [Occurrence id2 _] _ _) -> check (id1 == id2 && id1 /= Nothing)
            _ -> fail "independent reader did not see the committed event"
          run first "one" (pure ()) "eventually" >>= expectVerdict Fail,
        test "missing correlation is Unknown and never broadens its query" $ do
          (category, reader) <- setup
          run reader "one" (withConnection writeSettings (\connection -> append store connection (category <> "-one") (object []))) "eventually" >>= expectVerdict Unknown,
        test "undecodable correlated payload is Unknown" $ do
          (category, _) <- setup
          scope <- right (categoryScope category)
          query <- right (eventQuery bounded scope AppendOnlyDuringRun (BusinessKeyField "accountId") "Happened" (const (Left "SECRET-FIXTURE-PAYLOAD")))
          reader <- case store of
            KirokuStore -> do
              r <- Kiroku.kiroku readSettings "kiroku" "event-fixture" query >>= right
              pure (Backend (Kiroku.kirokuBaseline r) (\c -> Kiroku.observeKiroku c r) (Kiroku.kirokuContract "event-fixture" query))
            MessageDbStore -> do
              r <- MessageDb.messageDb readSettings "event-fixture" query >>= right
              metadata <- maybe (fail "unsupported fixture contract") pure (MessageDb.messageDbContract "event-fixture" query)
              pure (Backend (MessageDb.messageDbBaseline r) (\c -> MessageDb.observeMessageDb c r) metadata)
          run reader "one" (write store writeSettings category "one" 1) "eventually" >>= expectVerdict Unknown,
        test "scan exhaustion is Unknown rather than complete history" $ do
          category <- freshScope
          scope <- right (categoryScope category)
          small <- right (limits 1 1 2000)
          reader <- open store readSettings scope small (BusinessKeyField "accountId")
          run reader "one" (write store writeSettings category "one" 1) "exactly-once" >>= expectVerdict Unknown,
        test "events first seen after the cutoff cannot produce accepted cardinality" $ do
          (category, Backend capture observe _) <- setup
          base <- capture realClock "event-fixture" >>= right
          write store writeSettings category "one" 1
          let Clock now _ sleep _ = realClock
          cutoff <- (+ 150000) <$> now
          early <- makeCall base cutoff >>= observe
          case early of ObservedWithDetails [Occurrence _ _] (Coverage _ _ _ True) _ -> pure (); _ -> fail "early event missing"
          sleep (cutoff + 1000)
          write store writeSettings category "one" 1
          late <- makeCall base cutoff >>= observe
          case late of ObservedWithDetails [Occurrence _ _] (Coverage _ _ through False) _ -> check (through == cutoff); _ -> fail "late event was counted inside the finite window",
        test "a read spanning the cutoff cannot claim its unseen closing interval" $ do
          (_, Backend capture observe _) <- setup
          epoch <- getCurrentTime
          (clock@(Clock now wall sleep bound), advance) <- newFakeClock epoch
          base <- capture clock "event-fixture" >>= right
          let closingBound :: forall a. Integer -> IO a -> IO (Maybe a)
              closingBound deadline action = do
                result <- bound deadline action
                advance 1000
                pure result
              crossingClock = Clock now wall sleep closingBound
              context = CallContext (const (Left "unused")) 2000000 (Just base) (Just (ByBusinessKey "accountId" "one")) (\_ _ -> pure (Left "unused")) 500 crossingClock
          result <- observe context
          case result of
            ObservedWithDetails [] (Coverage _ _ through _) _ -> check (through < 500)
            _ -> fail "crossing read did not retain conservative source bounds",
        test "unverified history cannot prove a negative or exactly-once result" $ do
          category <- freshScope
          scope <- right (categoryScope category)
          query <- right (eventQuery bounded scope UnverifiedHistory (BusinessKeyField "accountId") "Happened" (const (Right True)))
          reader <- openQuery store readSettings query
          run reader "one" (pure ()) "never" >>= expectVerdict Unknown
          run reader "one" (write store writeSettings category "one" 1) "exactly-once" >>= expectVerdict Unknown,
        test "exact execution metadata is scoped and unsupported legacy correlation is rejected" $ do
          category <- freshScope
          scope <- right (categoryScope category)
          query <- right (eventQuery bounded scope AppendOnlyDuringRun ExecutionMetadata "Happened" (const (Right True)))
          case store of
            MessageDbStore -> MessageDb.messageDb readSettings "event-fixture" query >>= check . either (const True) (const False)
            KirokuStore -> do
              Backend capture observe _ <- openQuery store readSettings query
              base <- capture realClock "event-fixture" >>= right
              let selectedId = UUID.fromWords 0 0 1 42
                  otherId = UUID.fromWords 0 0 1 43
              withConnection writeSettings $ \connection -> do
                appendWithExecution store connection (category <> "-one") (eventBody "one") (Just selectedId)
                appendWithExecution store connection (category <> "-one") (eventBody "other") (Just otherId)
              let Clock now _ _ _ = realClock
              end <- (+ 2000000) <$> now
              let context = CallContext (const (Left "unused")) end (Just base) (Just (ByExecutionId (UUID.toText selectedId))) (\_ _ -> pure (Left "unused")) end realClock
              result <- observe context
              case result of
                ObservedWithDetails [Occurrence _ (EventEvidence _ _ cause _)] (Coverage _ _ _ True) _ -> check (cause == Just (UUID.toText selectedId))
                _ -> fail "exact execution metadata did not select one occurrence",
        test "real blocked read respects the host deadline and releases its connection" $ do
          (_, Backend capture observe _) <- setup
          base <- capture realClock "event-fixture" >>= right
          locked <- newEmptyMVar
          release <- newEmptyMVar
          let table = case store of KirokuStore -> "kiroku.events"; MessageDbStore -> "message_store.messages"
              locker = withConnection writeSettings $ \connection -> do
                session connection (S.script ("BEGIN; LOCK TABLE " <> table <> " IN ACCESS EXCLUSIVE MODE"))
                putMVar locked ()
                takeMVar release
                session connection (S.script "ROLLBACK")
          bracket (forkIO locker) killThread $ \_ -> do
            takeMVar locked
            let Clock now _ _ _ = realClock
            start <- now
            let context = CallContext (const (Left "unused")) (start + 80000) (Just base) (Just (ByBusinessKey "accountId" "one")) (\_ _ -> pure (Left "unused")) (start + 2000000) realClock
            result <- observe context
            end <- now
            check (end - start < 1000000)
            case result of ObservationUnavailable _ -> pure (); _ -> fail "blocked source reported complete evidence"
            let activeReaders = preparable "SELECT count(*) FROM pg_stat_activity WHERE usename = 'shoko_event_reader' AND datname = current_database()" mempty (D.singleRow (D.column (D.nonNullable D.int8)))
                released attempts = do
                  count <- withConnection writeSettings (\connection -> session connection (S.statement () activeReaders))
                  if count == 0 then pure () else if attempts <= (0 :: Int) then fail "observer connection was not released" else threadDelay 20000 >> released (attempts - 1)
            released 10
            putMVar release (),
        test "outage is Unknown before action mutation" $ do
          category <- freshScope
          scope <- right (categoryScope category)
          reader <- open store "host=/tmp/shoko-no-event-source dbname=missing connect_timeout=1" scope bounded (BusinessKeyField "accountId")
          mutations <- newIORef (0 :: Int)
          run reader "one" (modifyIORef' mutations (+ 1)) "eventually" >>= expectVerdict Unknown
          readIORef mutations >>= check . (== 0),
        test "read credential cannot mutate application events" $ withConnection readSettings $ \connection -> do
          let sql = case store of KirokuStore -> "DELETE FROM kiroku.events"; MessageDbStore -> "DELETE FROM message_store.messages"
          C.use connection (S.script sql) >>= check . either (const True) (const False),
        test "transaction visibility and delayed lower-position commits are not skipped" $ do
          category <- freshScope
          scope <- right (categoryScope category)
          reader@(Backend capture observe _) <- open store readSettings scope bounded (BusinessKeyField "accountId")
          appended <- newEmptyMVar
          commit <- newEmptyMVar
          finished <- newEmptyMVar
          let pending = withConnection writeSettings $ \connection -> do
                session connection (S.script "BEGIN")
                append store connection (category <> "-one") (eventBody "one")
                putMVar appended ()
                takeMVar commit
                session connection (S.script "COMMIT")
          bracket (forkIO (pending `finally` putMVar finished ())) killThread $ \_ -> do
            takeMVar appended
            when (store == MessageDbStore) (write store writeSettings (category <> "other") "other" 1)
            base <- capture realClock "event-fixture" >>= right
            let Clock now _ _ _ = realClock
            cutoff <- (+ 2000000) <$> now
            before <- makeCall base cutoff >>= observe
            case before of ObservedWithDetails [] (Coverage _ _ _ True) _ -> pure (); _ -> fail "uncommitted event was visible"
            putMVar commit ()
            takeMVar finished
            after <- makeCall base cutoff >>= observe
            case after of ObservedWithDetails [Occurrence _ _] (Coverage _ _ _ True) _ -> pure (); _ -> fail "delayed commit was skipped"
          run reader "one" (pure ()) "eventually" >>= expectVerdict Fail
      ]
