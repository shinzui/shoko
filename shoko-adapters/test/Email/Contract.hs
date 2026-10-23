{-# LANGUAGE GADTs #-}
{-# LANGUAGE PackageImports #-}
{-# LANGUAGE RankNTypes #-}

module Email.Contract (tests, test, check, right, ms, limits, key, box, fixture, newCase, expectVerdict, fixtureEnvironment, options, lookupNumber) where

import Control.Concurrent (forkFinally, forkIO, killThread, threadDelay)
import Control.Concurrent.MVar
import Control.Monad (unless, void)
import Data.Aeson
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.IORef
import Data.Set qualified as Set
import Data.String (fromString)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (getCurrentTime)
import Hedgehog (evalIO, property, withTests)
import Network.HTTP.Client qualified as H
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Shoko
import Shoko.Adapter.Email qualified as E
import Shoko.Adapter.Email.Internal (newResendReaderAt)
import Shoko.Adapter.Email.Internal qualified as I
import Shoko.Clock
import Shoko.Result hiding (binding)
import Shoko.Result.Json
import System.Environment (getEnv)
import System.Timeout (timeout)
import Test.Tasty
import Test.Tasty.Hedgehog (testPropertyNamed)
import "shoko-adapters" Shoko.Adapter.Http qualified as Http

check :: Bool -> IO ()
check value = unless value (fail "email contract assertion failed")

right :: Either Text a -> IO a
right = either (fail . T.unpack) pure

ms :: Int -> Duration
ms = either (error . T.unpack) id . milliseconds

test :: String -> IO () -> TestTree
test title action = testPropertyNamed title (fromString title) (withTests 1 (property (evalIO action)))

limits :: E.EmailLimits
limits = E.EmailLimits 2 20 10 65536 1048576 65536 (ms 200) (ms 1000)

key :: BusinessKeyName
key = BusinessKeyName "testMailboxId"

box :: E.EmailLimits -> IO E.Inbox
box = right . E.inbox (SourceId "email") "approved-test-account" key "fixture.invalid" "test-"

fixture :: Text -> Text -> Maybe Value -> IO Value
fixture account route body = do
  base <- getEnv "SHOKO_TEST_EMAIL"
  request <- H.parseRequest (base ++ T.unpack route ++ T.unpack account)
  manager <- H.newManager (H.managerSetProxy H.noProxy tlsManagerSettings)
  response <- H.httpLbs request {H.method = maybe "GET" (const "POST") body, H.requestBody = H.RequestBodyLBS (maybe "" encode body)} manager
  either (const (fail "fixture response invalid")) pure (eitherDecode (H.responseBody response))

acquire :: E.Inbox -> Text -> IO E.EmailReader
acquire selected account = do
  origin <- getEnv "SHOKO_TEST_EMAIL" >>= H.parseRequest
  newResendReaderAt selected Nothing account origin

data Op a where
  Allocate :: Text -> Op Text
  Welcome :: Input Text -> [Text] -> Text -> Text -> Op ()
  Mail :: Input Text -> Op Bool

instance Vocabulary Op where
  describeOperation (Allocate _) = OperationInfo "mailbox" Set.empty [] []
  describeOperation (Welcome input _ _ _) = OperationInfo "welcome" Set.empty (inputDependencies input) []
  describeOperation (Mail input) = OperationInfo "welcome-mail" Set.empty (inputDependencies input) []

consumerBinding :: E.Inbox -> E.Inbox -> Text -> Binding Op (E.EmailReader, Http.Http)
consumerBinding declared actual account = consumerBindingWith declared account (acquire actual account)

consumerBindingWith :: E.Inbox -> Text -> IO E.EmailReader -> Binding Op (E.EmailReader, Http.Http)
consumerBindingWith declared account acquireReader = binding "email-consumer" obtain (const (pure Retained)) handlers
  where
    obtain _ = do
      resource <- acquireReader
      config <- httpConfig
      http <- Http.newHttp config
      pure (resource, http)
    httpConfig = do
      base <- T.pack <$> getEnv "SHOKO_TEST_EMAIL"
      endpoint <- right (Http.endpoint "application" (base <> "/app/welcome") Http.Post 1024 Set.empty False Nothing)
      right (Http.httpConfig [endpoint])
    -- Descriptor construction must not read environment or allocate anything.
    handlers :: forall a. OperationRole -> Op a -> Either HandlerBuildError (Maybe (Handler (E.EmailReader, Http.Http) a))
    handlers FixtureOperation (Allocate token) = Right (Just (actionHandler (requiring [SyntheticResource] noRequirements) (\_ _ -> pure (ActionObserved "allocated" token))))
    handlers ActionOperation (Welcome input others fault subject) =
      Right
        ( Just
            ( actionHandler (requiring [SendHttp, WriteState] noRequirements) $ \(_, http) call -> do
                resolved <- resolveInput call input
                case resolved of
                  Left _ -> pure (ActionUnavailable "input-unavailable")
                  Right token -> Http.httpAction http call "application" (Http.HttpPayload (BL.toStrict (encode (object ["account" .= account, "tokens" .= (token : others), "fault" .= fault, "subject" .= subject]))) "application/json" Nothing Nothing Nothing) (\status _ -> if status == 201 then Right ("created", ()) else Left Http.ResponseUndecodable)
            )
        )
    handlers ObservationOperation (Mail input) = Just . focus fst <$> E.emailObservationHandler declared input (\email -> Right (E.emailSubject email == "Welcome" && E.emailText email == Just "CONTENT-PRIVATE welcome"))
    handlers _ _ = Right Nothing

-- A fixture application is a separate producer using the existing HTTP adapter.
scenarioValue :: Text -> [Text] -> Text -> Text -> Bool -> Scenario Op
scenarioValue token others fault subject mutate = scenario "email-welcome" "Application welcome email" "1" $ do
  allocated <- given "mailbox" (accept ["allocated"] (Allocate token))
  if mutate then void (act "application" (accept ["created"] (Welcome (fromRef allocated) others fault subject))) else pure ()
  selected <- correlate (CorrelationAlias "mailbox") key (fromRef allocated)
  expect $ eventually "welcome" (correlatedBy selected (observe "welcome-content" (Mail (fromRef allocated)) id))

fixtureEnvironment :: Environment
fixtureEnvironment = Environment "fixture" False (Set.fromList [ReadState, WriteState, SendHttp, ExternalSideEffect, SyntheticResource]) (Policy (ms 2000) (ms 180) (ms 500) (ms 100))

options :: RunOptions
options = RunOptions "email-run" True "fixture" Nothing Nothing

run :: E.Inbox -> E.Inbox -> Text -> Scenario Op -> IO RunResult
run declared actual account source = do
  resolved <- either (fail . show) pure (resolveScenario fixtureEnvironment options (consumerBinding declared actual account) source)
  runScenario realClock (LogicalInput "email-fixture" []) resolved

runFake :: E.Inbox -> Text -> Scenario Op -> IO RunResult
runFake selected account source = do
  (clock, _) <- getCurrentTime >>= newFakeClock
  let env = Environment "fixture" False (Set.fromList [ReadState, WriteState, SendHttp, ExternalSideEffect, SyntheticResource]) (Policy (ms 2000) (ms 180) (ms 30) (ms 100))
  resolved <- either (fail . show) pure (resolveScenario env options (consumerBinding selected selected account) source)
  runScenario clock (LogicalInput "email-fixture" []) resolved

expectVerdict :: Verdict -> RunResult -> IO ()
expectVerdict expected result = do
  check (case result of Verification VerificationResult {verdict = actual} -> actual == expected; _ -> False)
  check (decodeRunResult (encodeRunResult result) == Right result)
  let encoded = BL.toStrict (encodeRunResult result)
  mapM_ (\sentinel -> check (not (sentinel `BS.isInfixOf` encoded))) ["CONTENT-PRIVATE", "HTML-PRIVATE", "HEADER-PRIVATE", "FILENAME-PRIVATE", "URL-PRIVATE", "ERROR-PRIVATE", "FROM-PRIVATE", "fixture.invalid", "CREDENTIAL-PRIVATE"]

newCase :: IO (E.Inbox, Text, Text)
newCase = (,,) <$> box limits <*> E.freshToken <*> E.freshToken

tests :: TestTree
tests = testGroup "email contracts" [receivingTests, boundsTests]

receivingTests :: TestTree
receivingTests =
  testGroup
    "email through actual HTTP and public runner"
    [ test "new application email passes with old and unrelated messages excluded" $ do
        (selected, account, token) <- newCase
        old <- E.addressText <$> right (E.recipient selected token)
        void (fixture account "/control/" (Just (object ["seed" .= [old, "other@fixture.invalid"]])))
        other <- E.freshToken
        run selected selected account (scenarioValue token [other] "" "Welcome" True) >>= expectVerdict Pass,
      test "pre-existing matching mail cannot pass" $ do
        (selected, account, token) <- newCase
        old <- E.addressText <$> right (E.recipient selected token)
        void (fixture account "/control/" (Just (object ["seed" .= [old]])))
        run selected selected account (scenarioValue token [] "" "Welcome" False) >>= expectVerdict Fail,
      test "unrelated fresh mail cannot satisfy another token" $ do
        (selected, account, token) <- newCase
        other <- E.freshToken
        let source = scenario "unrelated" "Another run's welcome" "1" $ do
              allocated <- given "mailbox" (accept ["allocated"] (Allocate token))
              void (act "application" (accept ["created"] (Welcome (pure other) [] "" "Welcome")))
              correlationHandle <- correlate (CorrelationAlias "mailbox") key (fromRef allocated)
              expect $ eventually "welcome" (correlatedBy correlationHandle (observe "welcome-content" (Mail (fromRef allocated)) id))
        run selected selected account source >>= expectVerdict Fail,
      test "failed baseline prevents application mutation" $ do
        (selected, account, token) <- newCase
        void (fixture account "/control/" (Just (object ["fault" .= ("401" :: Text)])))
        run selected selected account (scenarioValue token [] "" "Welcome" True) >>= expectVerdict Unknown
        metrics <- fixture account "/control/" Nothing
        check (case metrics of Object values -> lookupNumber "mutations" values == Just 0; _ -> False),
      test "acquired descriptor mismatch prevents listing" $ do
        (selected, account, token) <- newCase
        different <- right (E.inbox (SourceId "email") "different-account" key "fixture.invalid" "test-" limits)
        run selected different account (scenarioValue token [] "" "Welcome" True) >>= expectVerdict Unknown
        metrics <- fixture account "/control/" Nothing
        check (case metrics of Object values -> lookupNumber "requests" values == Just 0; _ -> False)
    ]

lookupNumber :: Key -> Object -> Maybe Int
lookupNumber field values = case KM.lookup field values of
  Just (Number n) -> Just (round n)
  _ -> Nothing

boundsTests :: TestTree
boundsTests =
  testGroup
    "bounded evidence, isolation and privacy"
    ( [ test ("incomplete " ++ T.unpack fault ++ " remains Unknown") $ do
          (selected, account, token) <- newCase
          run selected selected account (scenarioValue token [] fault "Welcome" True) >>= expectVerdict Unknown
      | fault <- ["401", "403", "429", "500", "invalid", "large", "loop", "empty", "missing-to", "missing-id", "path-id", "detail-missing", "detail-id", "detail-to", "detail-invalid"]
      ]
        ++ [ test "one unavailable poll leaves a sticky gap despite later conclusive misses" $ do
               (selected, account, token) <- newCase
               runFake selected account (scenarioValue token [] "once429" "Different" True) >>= expectVerdict Unknown
               metrics <- fixture account "/control/" Nothing
               check (case metrics of Object values -> maybe False (> 3) (lookupNumber "lists" values); _ -> False),
             test "later matching evidence can pass after a transient read failure" $ do
               (selected, account, token) <- newCase
               runFake selected account (scenarioValue token [] "once429" "Welcome" True) >>= expectVerdict Pass,
             test "duplicate provider IDs across pages and polls are one occurrence" $ do
               (selected, account, token) <- newCase
               runFake selected account (scenarioValue token [] "duplicate" "Welcome" True) >>= expectVerdict Pass
               metrics <- fixture account "/control/" Nothing
               check (case metrics of Object values -> lookupNumber "details" values == Just 1; _ -> False),
             test "nullable text and HTML are valid private values and conclusive nonmatches" $ do
               (selected, account, token) <- newCase
               run selected selected account (scenarioValue token [] "nullable" "Welcome" True) >>= expectVerdict Fail,
             test "page budget fails before mutation" $ do
               (_, account, token) <- newCase
               selected <- box limits {E.maxPages = 1}
               void (fixture account "/control/" (Just (object ["seed" .= (["one@fixture.invalid", "two@fixture.invalid", "three@fixture.invalid"] :: [Text])])))
               run selected selected account (scenarioValue token [] "" "Welcome" True) >>= expectVerdict Unknown
               metrics <- fixture account "/control/" Nothing
               check (case metrics of Object values -> lookupNumber "mutations" values == Just 0; _ -> False),
             test "detail and aggregate byte budgets cannot become misses" $ do
               (_, account, token) <- newCase
               selected <- box limits {E.maxDetails = 1}
               run selected selected account (scenarioValue token [token] "" "Welcome" True) >>= expectVerdict Unknown
               (_, account2, token2) <- newCase
               small <- box limits {E.responseBytes = 1100, E.scanBytes = 1100}
               run small small account2 (scenarioValue token2 [token2] "" "Welcome" True) >>= expectVerdict Unknown,
             test "policy and correlation preflight perform zero acquisition and requests" $ do
               (selected, account, token) <- newCase
               acquired <- newIORef (0 :: Int)
               let original = consumerBinding selected selected account
                   source = scenarioValue token [] "" "Welcome" True
                   wrapped = binding "guarded" (\_ -> modifyIORef' acquired (+ 1) >> fail "unexpected acquisition") (const (pure Retained)) (bindingHandler original)
                   denied = Environment "denied" False Set.empty defaultPolicy
                   missing = scenario "missing-correlation" "Missing" "1" $ expect $ eventually "welcome" (observe "yes" (Mail (pure token)) id)
               check (either (const True) (const False) (resolveScenario denied options wrapped source))
               check (either (const True) (const False) (resolveScenario fixtureEnvironment options wrapped missing))
               check (either (const True) (const False) (resolveScenario fixtureEnvironment (RunOptions "denied" False "fixture" Nothing Nothing) wrapped source))
               readIORef acquired >>= check . (== 0),
             test "runtime token and selected correlation must agree before poll IO" $ do
               (selected, account, token) <- newCase
               other <- E.freshToken
               let source = scenario "lost-correlation" "Lost" "1" $ do
                     correlationHandle <- correlate (CorrelationAlias "mailbox") key (pure token)
                     expect $ eventually "welcome" (correlatedBy correlationHandle (observe "yes" (Mail (pure other)) id))
               run selected selected account source >>= expectVerdict Unknown
               metrics <- fixture account "/control/" Nothing
               check (case metrics of Object values -> lookupNumber "lists" values == Just 1; _ -> False),
             test "simultaneous correlations and runs remain independent" $ do
               (selected, account, token) <- newCase
               other <- E.freshToken
               let block label value = namespace label $ do
                     allocated <- given "mailbox" (accept ["allocated"] (Allocate value))
                     void (act "application" (accept ["created"] (Welcome (fromRef allocated) [] "" "Welcome")))
                     correlationHandle <- correlate (CorrelationAlias "mailbox") key (fromRef allocated)
                     expectAfterActions $ eventually "welcome" (correlatedBy correlationHandle (observe "yes" (Mail (fromRef allocated)) id))
                   source = scenario "composed-mailboxes" "Independent mailboxes" "1" (block "a" token >> block "b" other)
               run selected selected account source >>= expectVerdict Pass
               done <- newEmptyMVar
               void $
                 forkIO $
                   ( do
                       (second, secondAccount, secondToken) <- newCase
                       run second second secondAccount (scenarioValue secondToken [] "" "Welcome" True)
                   )
                     >>= putMVar done
               run selected selected account (scenarioValue token [] "" "Welcome" True) >>= expectVerdict Pass
               takeMVar done >>= expectVerdict Pass,
             test "blocked HTTP reads are cancellable and do not poison the state lock" cancellationTest,
             test "late matching reads cannot pass the cutoff" lateReadTest
           ]
        ++ [ test ("sampled " ++ label) $ do
               (selected, account, token) <- newCase
               let source = scenario "sampled-limits" "Sampled assertions" "1" $ do
                     allocated <- given "mailbox" (accept ["allocated"] (Allocate token))
                     if count == 0 then pure () else void (act "application" (accept ["created"] (Welcome (fromRef allocated) (replicate (count - 1) token) "" "Welcome")))
                     correlationHandle <- correlate (CorrelationAlias "mailbox") key (fromRef allocated)
                     expect $ temporal "assertion" (correlatedBy correlationHandle (observe "yes" (Mail (fromRef allocated)) id))
               runFake selected account source >>= expectVerdict verdictValue
           | (label, temporal, count, verdictValue) <- [("never empty", never, 0, Unknown), ("never witness", never, 1, Fail), ("exactlyOnce empty", exactlyOnce, 0, Unknown), ("exactlyOnce one", exactlyOnce, 1, Unknown), ("exactlyOnce two", exactlyOnce, 2, Unknown)]
           ]
    )

cancellationTest :: IO ()
cancellationTest = do
  (selected, account, token) <- newCase
  -- Let capture finish normally, then block in the first poll after the action.
  done <- newEmptyMVar
  shared <- acquire selected account
  let execute source = do
        resolved <- either (fail . show) pure (resolveScenario fixtureEnvironment options (consumerBindingWith selected account (pure shared)) source)
        runScenario realClock (LogicalInput "cancel" []) resolved
  thread <- forkFinally (execute (scenarioValue token [] "slow" "Welcome" True)) (putMVar done)
  let awaitPoll = do
        metrics <- fixture account "/control/" Nothing
        if case metrics of Object values -> maybe False (>= 2) (lookupNumber "lists" values); _ -> False
          then pure ()
          else threadDelay 5000 >> awaitPoll
  ready <- timeout 1000000 awaitPoll
  check (ready == Just ())
  killThread thread
  timeout 500000 (takeMVar done) >>= check . maybe False (const True)
  threadDelay 450000
  metrics <- fixture account "/control/" Nothing
  check (case metrics of Object values -> maybe False (> 0) (lookupNumber "disconnects" values); _ -> False)
  void (fixture account "/control/" (Just (object ["fault" .= ("" :: Text)])))
  execute (scenarioValue token [] "" "Welcome" True) >>= expectVerdict Pass

lateReadTest :: IO ()
lateReadTest = do
  selected <- box limits
  token <- E.freshToken
  destination <- right (E.recipient selected token)
  (clock, advance) <- getCurrentTime >>= newFakeClock
  calls <- newIORef (0 :: Int)
  state <- newMVar (I.ReaderState mempty mempty)
  let provider =
        I.Provider
          { I.listPage = \_ _ _ -> do
              n <- atomicModifyIORef' calls (\n -> (n + 1, n))
              pure (Right (I.Page (if n == 0 then [] else [I.MessageRef "message" [destination]]) False, 10)),
            I.getDetail = \_ _ _ -> do
              advance (ms 300)
              pure (Right (I.ReceivedEmail "message" [destination] "private" "Welcome" (Just "CONTENT-PRIVATE welcome") Nothing "cid" mempty [], 10)),
            I.submit = \_ _ _ -> pure (Left "unavailable")
          }
      resource = I.EmailReader selected Nothing provider state
      handlers :: OperationRole -> Op a -> Either HandlerBuildError (Maybe (Handler E.EmailReader a))
      handlers ObservationOperation (Mail input) = Just <$> E.emailObservationHandler selected input (\_ -> Right True)
      handlers _ _ = Right Nothing
      selectedBinding = binding "late" (const (pure resource)) (const (pure Retained)) handlers
      source = scenario "late" "Late" "1" $ do
        correlationHandle <- correlate (CorrelationAlias "mailbox") key (pure token)
        expect $ eventually "welcome" (correlatedBy correlationHandle (observe "yes" (Mail (pure token)) id))
  resolved <- either (fail . show) pure (resolveScenario fixtureEnvironment options selectedBinding source)
  runScenario clock (LogicalInput "late" []) resolved >>= expectVerdict Unknown
