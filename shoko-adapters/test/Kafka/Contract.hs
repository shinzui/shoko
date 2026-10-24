{-# LANGUAGE RankNTypes #-}

module Kafka.Contract where

import Control.Monad (unless, when)
import Data.Aeson (Value (..), encode, object, (.=))
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.IORef
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.String (fromString)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Data.Time (getCurrentTime)
import Data.Unique (hashUnique, newUnique)
import Hedgehog (evalIO, property, withTests)
import Kafka.Controlled
import Shoko hiding (binding, observe)
import Shoko qualified
import Shoko.Adapter.EventStore
import Shoko.Adapter.Kafka.Internal
import Shoko.Adapter.Kiroku qualified as Kiroku
import Shoko.Adapter.MessageDb qualified as MessageDb
import Shoko.Clock
import Shoko.Evidence (Evidence (..))
import Shoko.Observation qualified as Observation
import Shoko.Result
import Shoko.Result.Json
import System.Environment (getEnvironment, lookupEnv)
import System.Exit (ExitCode (..))
import System.Process (CreateProcess (..), proc, readCreateProcessWithExitCode)
import System.Timeout (timeout)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

data Backend
  = Backend
      !(Clock -> SourceId -> IO (Either Text.Text Baseline))
      !(CallContext -> IO (ObservationOutcome (EventEvidence Bool)))
      !(Handler () (EventEvidence Bool))

check :: Bool -> IO ()
check value = unless value (fail "kafka contract assertion failed")

test :: String -> IO () -> TestTree
test title action = testPropertyNamed title (fromString title) (withTests 1 (property (evalIO bounded)))
  where
    bounded = timeout 15000000 action >>= maybe (fail "kafka test deadline") pure

right :: Either Text.Text a -> IO a
right = either (fail . Text.unpack) pure

topicSource :: SourceId
topicSource = SourceId "topic-fixture"

byKey :: CorrelationMode
byKey = BusinessKeyRecordKey (BusinessKeyName "accountId")

decodeFixture :: Value -> Either Text.Text Bool
decodeFixture = \case Object _ -> Right True; _ -> Left "invalid-fixture-event"

topicQuery :: Limits -> HistoryPolicy -> CorrelationMode -> (Value -> Either Text.Text Bool) -> IO (EventQuery Bool)
topicQuery bounded policy mode decode = do
  scope <- right (topicScope "fixture.events")
  right (eventQuery bounded scope policy mode "Happened" decode)

openQuery :: Controlled -> EventQuery Bool -> IO Backend
openQuery controlled query = do
  Kafka reader <- kafkaReader (port controlled) topicSource query >>= right
  handler <- either (fail . show) (pure . focus (const (Kafka reader))) (kafkaObservation topicSource query)
  pure (Backend (captureForTest handler) (\call -> observeKafka call (Kafka reader)) handler)

open :: Controlled -> Limits -> CorrelationMode -> IO Backend
open controlled bounded mode = topicQuery bounded AppendOnlyDuringRun mode decodeFixture >>= openQuery controlled

-- | A typed record keyed by the business key, as the registration publisher writes it.
event :: Text.Text -> IO KafkaRecord
event key = do
  now <- getCurrentTime
  pure (record now (Just (Text.encodeUtf8 key)) [("event-type", "Happened")] (Just (BL.toStrict (encode (object ["accountId" .= key])))))

emit :: Controlled -> Text.Text -> Int -> IO ()
emit controlled key count = mapM_ (\_ -> event key >>= produce controlled) [1 .. count]

data Op a where
  Produce :: Op Text.Text
  Events :: Op (EventEvidence Bool)

instance Vocabulary Op where
  describeOperation Produce = OperationInfo "fixture.produce" (Set.fromList [WriteState, SyntheticResource]) [] []
  describeOperation Events = OperationInfo "fixture.read" (Set.singleton ReadEvents) [] []

captureForTest :: Handler () (EventEvidence Bool) -> Clock -> SourceId -> IO (Either Text.Text Baseline)
captureForTest = captureForTestWith 2000

captureForTestWith :: Int -> Handler () (EventEvidence Bool) -> Clock -> SourceId -> IO (Either Text.Text Baseline)
captureForTestWith budget handler clock label
  | fmap sourceId (handlerSource handler) /= Just label = pure (Left "source-mismatch")
  | otherwise = do
      let handlers :: OperationRole -> Op a -> Either HandlerBuildError (Maybe (Handler () a))
          handlers ObservationOperation Events = Right (Just handler)
          handlers _ _ = Right Nothing
          selectedBinding = Shoko.binding "capture-probe" (const (pure ())) (const (pure Retained)) handlers
          selectedScenario = scenario "capture-probe" "Capture public baseline" "1" $ do
            selectedCorrelation <- correlate (CorrelationAlias "probe") (BusinessKeyName "accountId") (pure "one")
            expect $ within (duration 1) $ never "probe" (correlatedBy selectedCorrelation $ Observation.observe "false" Events (const False))
          duration n = either (error . Text.unpack) id (milliseconds n)
          environment = Environment "local" False (Set.singleton ReadEvents) (Policy (duration budget) (duration 1) (duration 1) (duration 100))
          options = RunOptions "00000000-0000-0000-0000-000000000001" False "fixture" Nothing Nothing
      resolved <- either (fail . show) pure (resolveScenario environment options selectedBinding selectedScenario)
      result <- runScenario clock (LogicalInput "capture" []) resolved
      pure $ case result of
        Verification VerificationResult {expectations = ExpectationResult {evidence = ObservationEvidence (Evidence {baseline = Just base})} : _} -> Right base
        _ -> Left "capture-unavailable"

run :: Backend -> Text.Text -> IO () -> Text.Text -> IO (RunResult, Int)
run = runWith 4000 200

runWith :: Int -> Int -> Backend -> Text.Text -> IO () -> Text.Text -> IO (RunResult, Int)
runWith budgetMillis windowMillis backend selected produceAction assertion = do
  polls <- newIORef (0 :: Int)
  budget <- right (milliseconds budgetMillis)
  window <- right (milliseconds windowMillis)
  poll <- right (milliseconds 20)
  let Backend capture observe metadata = backend
      binding = Shoko.binding "topic-fixture" (\_ -> pure ()) (\_ -> pure Retained) handlers
      handlers :: OperationRole -> Op a -> Either HandlerBuildError (Maybe (Handler () a))
      handlers ActionOperation Produce = Right $ Just $ actionHandler noRequirements $ \_ _ -> produceAction >> pure (ActionObserved "produced" selected)
      handlers ObservationOperation Events = Right $ Just $ observationHandler (handlerContract metadata) (RequiresBusinessKey (BusinessKeyName "accountId")) (newSource topicSource DurableHistory (\_ clock -> capture clock topicSource)) $ \_ call -> modifyIORef' polls (+ 1) >> observe call
      handlers _ _ = Right Nothing
      scenarioValue = scenario "kafka-contract" "Topic evidence" "1" $ do
        _ <- act "produce" (accept ["produced"] Produce)
        selectedCorrelation <- correlate (CorrelationAlias "account") (BusinessKeyName "accountId") (pure selected)
        let observation = correlatedBy selectedCorrelation $ Observation.observe "event-matches" Events (\(EventEvidence _ _ _ value) -> value)
        expect $ within window $ case assertion of
          "never" -> never "absent" observation
          "eventually" -> eventually "present" observation
          _ -> exactlyOnce "one-event" observation
      environment = Environment "local-topic-fixture" False (Set.fromList [ReadEvents, WriteState, SyntheticResource]) (Policy budget window poll budget)
  resolved <-
    either
      (const (fail "fixture preflight failed"))
      pure
      (resolveScenario environment (RunOptions "topic-run" True "fixture-build" Nothing Nothing) binding scenarioValue)
  result <- runScenario realClock (LogicalInput "fixture-v1" []) resolved
  count <- readIORef polls
  let encoded = BL.toStrict (encodeRunResult result)
  check (decodeRunResult (encodeRunResult result) == Right result)
  check (not ("SECRET-FIXTURE" `BS.isInfixOf` encoded))
  pure (result, count)

expectVerdict :: Verdict -> (RunResult, Int) -> IO ()
expectVerdict wanted (Verification (VerificationResult _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ actual _ _ _), _) = check (actual == wanted)
expectVerdict _ _ = fail "unexpected fixture runner fault"

makeCall :: Baseline -> MonotonicTime -> IO CallContext
makeCall base cutoff = do
  let Clock now _ _ _ = realClock
  current <- now
  pure (detachedCallContext realClock (plusMicros current 2000000) cutoff (Just base) (Just (ByBusinessKey (BusinessKeyName "accountId") "one")))

-- | Capture, then observe once with a far cutoff.
probe :: Backend -> IO () -> IO (ObservationOutcome (EventEvidence Bool))
probe (Backend capture observe _) between = do
  base <- capture realClock topicSource >>= right
  between
  let Clock now _ _ _ = realClock
  cutoff <- (\tick -> plusMicros tick 2000000) <$> now
  makeCall base cutoff >>= observe

observeAgain :: Backend -> Baseline -> IO (ObservationOutcome (EventEvidence Bool))
observeAgain (Backend _ observe _) base = do
  let Clock now _ _ _ = realClock
  cutoff <- (\tick -> plusMicros tick 2000000) <$> now
  makeCall base cutoff >>= observe

detail :: Text.Text -> ObservationOutcome a -> Maybe Observation.PublicValue
detail key = \case
  ObservedWithDetails _ _ details -> lookup key details
  _ -> Nothing

coverageComplete :: ObservationOutcome a -> Maybe Bool
coverageComplete = \case
  ObservedWithDetails _ (Coverage _ _ _ whole) _ -> Just whole
  _ -> Nothing

occurrenceCount :: ObservationOutcome a -> Maybe Int
occurrenceCount = \case
  ObservedWithDetails found _ _ -> Just (length found)
  _ -> Nothing

deniedBeforeAllocation :: forall resource. Handler resource (EventEvidence Bool) -> IO resource -> IO ()
deniedBeforeAllocation handler allocate = do
  allocations <- newIORef (0 :: Int)
  let handlers :: OperationRole -> Op a -> Either HandlerBuildError (Maybe (Handler resource a))
      handlers ObservationOperation Events = Right (Just handler)
      handlers _ _ = Right Nothing
      selectedBinding = Shoko.binding "pure-topic-contract" (\_ -> modifyIORef' allocations (+ 1) >> allocate) (const (pure Retained)) handlers
      selected = scenario "policy-only" "Reader contract preflight" "1" $ do
        selectedCorrelation <- correlate (CorrelationAlias "account") (BusinessKeyName "accountId") (pure "one")
        expect (eventually "event" (correlatedBy selectedCorrelation $ Observation.observe "matches" Events (\(EventEvidence _ _ _ value) -> value)))
      environment = Environment "denied" False Set.empty defaultPolicy
  case resolveScenario environment (RunOptions "denied-run" False "fixture-build" Nothing Nothing) selectedBinding selected of
    Left errors -> check (errors == [CapabilitiesDenied (Set.singleton ReadEvents)])
    Right _ -> fail "topic-reader policy unexpectedly permitted allocation"
  readIORef allocations >>= check . (== 0)

assertDescriptorMismatch :: forall resource. Handler resource (EventEvidence Bool) -> IO resource -> IO ()
assertDescriptorMismatch handler allocate = do
  mutations <- newIORef (0 :: Int)
  let handlers :: OperationRole -> Op a -> Either HandlerBuildError (Maybe (Handler resource a))
      handlers ActionOperation Produce = Right $ Just $ actionHandler noRequirements $ \_ _ -> modifyIORef' mutations (+ 1) >> pure (ActionObserved "ready" "one")
      handlers ObservationOperation Events = Right (Just handler)
      handlers _ _ = Right Nothing
      selectedBinding = Shoko.binding "descriptor-mismatch" (const allocate) (const (pure Retained)) handlers
      selected = scenario "descriptor-mismatch" "Reader descriptor must match" "1" $ do
        _ <- act "produce" (accept ["ready"] Produce)
        selectedCorrelation <- correlate (CorrelationAlias "account") (BusinessKeyName "accountId") (pure "one")
        expect $ eventually "check" (correlatedBy selectedCorrelation $ Observation.observe "yes" Events (const True))
      environment = Environment "local" False (Set.fromList [ReadEvents, WriteState, SyntheticResource]) defaultPolicy
  resolved <- either (fail . show) pure (resolveScenario environment (RunOptions "mismatch" True "fixture" Nothing Nothing) selectedBinding selected)
  result <- runScenario realClock (LogicalInput "descriptor" []) resolved
  readIORef mutations >>= check . (== 0)
  case result of
    Verification VerificationResult {actions = [], verdict = Unknown} -> pure ()
    _ -> fail "mismatched reader did not suppress actions"

controlledTests :: Limits -> [TestTree]
controlledTests bounded =
  [ test "topic scopes, correlation sources, and settings are validated" $ do
      mapM_ (check . either (const True) (const False) . topicScope) ["", ".", "..", "__consumer_offsets", "has space", "slash/name", Text.replicate 250 "a"]
      mapM_ (check . either (const False) (const True) . topicScope) ["registration.completed.v1", "a_b-c", Text.replicate 249 "a"]
      scope <- right (topicScope "fixture.events")
      check (either (const True) (const False) (eventQuery bounded scope AppendOnlyDuringRun (BusinessKeyRecordKey (BusinessKeyName "")) "Happened" decodeFixture))
      check (either (const True) (const False) (eventQuery bounded scope AppendOnlyDuringRun (BusinessKeyHeader (BusinessKeyName "accountId") "") "Happened" decodeFixture))
      let accepted servers properties = either (const False) (const True) (kafkaSettings servers properties)
      check (accepted "127.0.0.1:9092" Map.empty)
      check (accepted "broker-1.example.invalid:9092, [::1]:9093" (Map.fromList [("security.protocol", "SASL_SSL"), ("sasl.mechanism", "PLAIN"), ("ssl.ca.location", "/etc/ca.pem")]))
      mapM_ (\servers -> check (not (accepted servers Map.empty))) ["", "kafka://broker:9092", "user:secret@broker:9092", "broker", "broker:0", "broker:65536", "broker:x", "broker:9092,"]
      mapM_
        (\key -> check (not (accepted "broker:9092" (Map.singleton key "value"))))
        ["group.id", "client.id", "enable.auto.commit", "enable.auto.offset.store", "enable.partition.eof", "isolation.level", "allow.auto.create.topics", "bootstrap.servers"],
    test "kafka handlers and readers reject non-topic scopes and execution metadata" $ do
      controlled <- newControlled 1
      category <- right (categoryScope "fixture")
      streamQuery <- right (eventQuery bounded category AppendOnlyDuringRun byKey "Happened" decodeFixture)
      executionQuery <- topicQuery bounded AppendOnlyDuringRun ExecutionMetadata decodeFixture
      check (either (== UnsupportedEventScope "category") (const False) (kafkaObservation topicSource streamQuery))
      check (either (== ExecutionMetadataUnsupported) (const False) (kafkaObservation topicSource executionQuery))
      kafkaReader (port controlled) topicSource streamQuery >>= check . either (== "unsupported-event-scope") (const False)
      kafkaReader (port controlled) topicSource executionQuery >>= check . either (const True) (const False),
    test "SQL readers reject topic scopes and record correlation before allocation" $ do
      topicKeyed <- topicQuery bounded AppendOnlyDuringRun (BusinessKeyField (BusinessKeyName "accountId")) decodeFixture
      category <- right (categoryScope "fixture")
      recordKeyed <- right (eventQuery bounded category AppendOnlyDuringRun byKey "Happened" decodeFixture)
      headerKeyed <- right (eventQuery bounded category AppendOnlyDuringRun (BusinessKeyHeader (BusinessKeyName "accountId") "account") "Happened" decodeFixture)
      check (either (== UnsupportedEventScope "topic") (const False) (Kiroku.kirokuObservation topicSource topicKeyed))
      check (either (== UnsupportedCorrelationSource "record-key") (const False) (Kiroku.kirokuObservation topicSource recordKeyed))
      check (either (== UnsupportedEventScope "topic") (const False) (MessageDb.messageDbObservation topicSource topicKeyed))
      check (either (== UnsupportedCorrelationSource "record-header") (const False) (MessageDb.messageDbObservation topicSource headerKeyed))
      let settings = "host=/tmp/shoko-no-event-source dbname=missing"
      Kiroku.kiroku settings "kiroku" topicSource topicKeyed >>= check . either (== "unsupported-event-scope") (const False)
      MessageDb.messageDb settings topicSource recordKeyed >>= check . either (== "unsupported-correlation-source") (const False),
    test "event handler descriptor mismatches reject before fixtures" $ do
      controlled <- newControlled 1
      original <- topicQuery bounded AppendOnlyDuringRun byKey decodeFixture
      otherLimits <- right (limits 2 20 2000)
      otherScope <- right (topicScope "fixture.other")
      variants <-
        sequence
          [ topicQuery otherLimits AppendOnlyDuringRun byKey decodeFixture,
            right (eventQuery bounded otherScope AppendOnlyDuringRun byKey "Happened" decodeFixture),
            topicQuery bounded UnverifiedHistory byKey decodeFixture,
            topicQuery bounded AppendOnlyDuringRun (BusinessKeyHeader (BusinessKeyName "accountId") "account") decodeFixture,
            topicQuery bounded AppendOnlyDuringRun (BusinessKeyField (BusinessKeyName "accountId")) decodeFixture,
            do
              scope <- right (topicScope "fixture.events")
              right (eventQuery bounded scope AppendOnlyDuringRun byKey "Other" decodeFixture)
          ]
      handler <- either (fail . show) pure (kafkaObservation topicSource original)
      mapM_ (\allocated -> assertDescriptorMismatch handler (kafkaReader (port controlled) topicSource allocated >>= right)) variants
      readCalls controlled >>= check . (== 0),
    test "pure contracts reject policy before allocating a reader" $ do
      controlled <- newControlled 1
      query <- topicQuery bounded AppendOnlyDuringRun byKey decodeFixture
      handler <- either (fail . show) pure (kafkaObservation topicSource query)
      deniedBeforeAllocation handler (kafkaReader (port controlled) topicSource query >>= right)
      readCalls controlled >>= check . (== 0),
    test "produce then exactlyOnce passes across repeated polls" $ do
      controlled <- newControlled 1
      reader <- open controlled bounded byKey
      result@(_, polls) <- run reader "one" (emit controlled "one" 1) "exactly-once"
      expectVerdict Pass result
      check (polls > 1),
    test "two distinct records fail cardinality" $ do
      controlled <- newControlled 1
      reader <- open controlled bounded byKey
      run reader "one" (emit controlled "one" 2) "exactly-once" >>= expectVerdict Fail,
    test "complete empty read passes never and fails eventually" $ do
      controlled <- newControlled 3
      reader <- open controlled bounded byKey
      run reader "one" (pure ()) "never" >>= expectVerdict Pass
      run reader "one" (pure ()) "eventually" >>= expectVerdict Fail,
    test "unrelated keys cannot satisfy the query" $ do
      controlled <- newControlled 1
      reader <- open controlled bounded byKey
      run reader "one" (emit controlled "other" 2) "eventually" >>= expectVerdict Fail,
    test "a record produced before capture is excluded" $ do
      controlled <- newControlled 1
      emit controlled "one" 1
      reader <- open controlled bounded byKey
      run reader "one" (pure ()) "eventually" >>= expectVerdict Fail,
    test "a second independent reader sees identical occurrence ids" $ do
      controlled <- newControlled 2
      first <- open controlled bounded byKey
      second <- open controlled bounded byKey
      let Backend base1 _ _ = first
          Backend base2 _ _ = second
      b1 <- base1 realClock topicSource >>= right
      b2 <- base2 realClock topicSource >>= right
      event "one" >>= produceTo controlled 1 >>= check . (== 0)
      a <- observeAgain first b1
      b <- observeAgain second b2
      case (a, b) of
        (ObservedWithDetails [Occurrence id1 _] _ _, ObservedWithDetails [Occurrence id2 _] _ _) -> check (id1 == id2 && id1 == Just "topic-fixture:1/0")
        _ -> fail "independent reader did not see the committed record",
    test "one matching record per partition yields three distinct occurrences" $ do
      controlled <- newControlled 3
      reader <- open controlled bounded byKey
      outcome <- probe reader (mapM_ (\partition -> event "one" >>= produceTo controlled partition) [0, 1, 2])
      case outcome of
        ObservedWithDetails found (Coverage _ _ _ True) _ -> check (Set.size (Set.fromList [key | Occurrence key _ <- found]) == 3)
        _ -> fail "three partitions did not yield three occurrences"
      run reader "one" (mapM_ (\partition -> event "one" >>= produceTo controlled partition) [0, 1, 2]) "exactly-once" >>= expectVerdict Fail,
    test "a declared-type record without a key is Unknown and never broadens the query" $ do
      controlled <- newControlled 1
      reader <- open controlled bounded byKey
      now <- getCurrentTime
      run reader "one" (() <$ produce controlled (record now Nothing [("event-type", "Happened")] (Just "{}"))) "eventually" >>= expectVerdict Unknown,
    test "records of other types are ignored even when malformed" $ do
      controlled <- newControlled 1
      reader <- open controlled bounded byKey
      now <- getCurrentTime
      let noise = do
            _ <- produce controlled (record now (Just "\255") [("event-type", "Other")] (Just "not json"))
            _ <- produce controlled (record now Nothing [] Nothing)
            emit controlled "one" 1
      outcome <- probe reader noise
      check (detail "records-without-event-type" outcome == Just (Observation.PublicCount 1))
      check (occurrenceCount outcome == Just 1 && coverageComplete outcome == Just True),
    test "an undecodable correlated payload is Unknown without leaking the decoder message" $ do
      controlled <- newControlled 1
      reader <- topicQuery bounded AppendOnlyDuringRun byKey (const (Left "SECRET-FIXTURE-PAYLOAD")) >>= openQuery controlled
      run reader "one" (emit controlled "one" 1) "eventually" >>= expectVerdict Unknown
      notJson <- open controlled bounded byKey
      now <- getCurrentTime
      run notJson "one" (() <$ produce controlled (record now (Just "one") [("event-type", "Happened")] (Just "SECRET-FIXTURE-VALUE"))) "eventually" >>= expectVerdict Unknown,
    test "malformed UTF-8 keys and duplicate headers obey the declared correlation rules" $ do
      controlled <- newControlled 1
      keyed <- open controlled bounded byKey
      now <- getCurrentTime
      run keyed "one" (() <$ produce controlled (record now (Just "\255\254") [("event-type", "Happened")] (Just "{}"))) "eventually" >>= expectVerdict Unknown
      headers <- newControlled 1
      reader <- open headers bounded (BusinessKeyHeader (BusinessKeyName "accountId") "SECRET-FIXTURE-HEADER-NAME")
      let duplicate = do
            _ <- produce headers (record now (Just "ignored") [("event-type", "Other"), ("SECRET-FIXTURE-HEADER-NAME", "two"), ("SECRET-FIXTURE-HEADER-NAME", "one"), ("event-type", "Happened")] (Just "{}"))
            _ <- produce headers (record now (Just "ignored") [("SECRET-FIXTURE-HEADER-NAME", "one"), ("event-type", "Happened"), ("SECRET-FIXTURE-HEADER-NAME", "two")] (Just "{}"))
            pure ()
      run reader "one" duplicate "exactly-once" >>= expectVerdict Pass,
    test "record-key and header correlation each select one record across partitions" $ do
      now <- getCurrentTime
      let keyed partitionKey headerKey = record now (Just partitionKey) [("event-type", "Happened"), ("account", headerKey)] (Just "{}")
          produceAll controlled = mapM_ (\(partition, key, header) -> produceTo controlled partition (keyed key header)) [(0, "one", "other"), (1, "other", "one"), (2, "third", "third")]
      byRecordKey <- newControlled 3
      keyReader <- open byRecordKey bounded byKey
      run keyReader "one" (produceAll byRecordKey) "exactly-once" >>= expectVerdict Pass
      byHeader <- newControlled 3
      headerReader <- open byHeader bounded (BusinessKeyHeader (BusinessKeyName "accountId") "account")
      outcome <- probe headerReader (produceAll byHeader)
      case outcome of
        ObservedWithDetails [Occurrence key _] (Coverage _ _ _ True) _ -> check (key == Just "topic-fixture:1/0")
        _ -> fail "header correlation did not select exactly one record"
      check (detail "correlation-filter" outcome == Just (Observation.PublicChoice "record-header:accountId")),
    test "per-partition record limits are Unknown rather than complete history" $ do
      controlled <- newControlled 1
      small <- right (limits 1 1 2000)
      reader <- open controlled small byKey
      run reader "one" (emit controlled "one" 2) "exactly-once" >>= expectVerdict Unknown,
    test "records first seen after the cutoff cannot produce accepted cardinality" $ do
      controlled <- newControlled 1
      Backend capture observe _ <- open controlled bounded byKey
      base <- capture realClock topicSource >>= right
      emit controlled "one" 1
      let Clock now _ sleep _ = realClock
      cutoff <- (\tick -> plusMicros tick 150000) <$> now
      early <- makeCall base cutoff >>= observe
      case early of ObservedWithDetails [Occurrence _ _] (Coverage _ _ _ True) _ -> pure (); _ -> fail "early record missing"
      sleep (plusMicros cutoff 1000)
      emit controlled "one" 1
      late <- makeCall base cutoff >>= observe
      case late of ObservedWithDetails [Occurrence _ _] (Coverage _ _ through False) _ -> check (through == cutoff); _ -> fail "late record was counted inside the finite window",
    test "a read spanning the cutoff cannot claim its unseen closing interval" $ do
      controlled <- newControlled 1
      Backend capture observe _ <- open controlled bounded byKey
      epoch <- getCurrentTime
      (captureClock, _) <- newFakeClock epoch
      base <- capture captureClock topicSource >>= right
      (Clock now wall sleep bound, advance) <- newFakeClock epoch
      let closingBound :: forall a. MonotonicTime -> IO a -> IO (Maybe a)
          closingBound deadline action = do
            result <- bound deadline action
            advance (testMicros 1000)
            pure result
          crossingClock = Clock now wall sleep closingBound
          context = detachedCallContext crossingClock (MonotonicTime 2000000) (MonotonicTime 500) (Just base) (Just (ByBusinessKey (BusinessKeyName "accountId") "one"))
      result <- observe context
      case result of
        ObservedWithDetails [] (Coverage _ _ through _) _ -> check (through < MonotonicTime 500)
        _ -> fail "crossing read did not retain conservative topicSource bounds",
    test "unverified history cannot prove a negative or exactly-once result" $ do
      controlled <- newControlled 1
      reader <- topicQuery bounded UnverifiedHistory byKey decodeFixture >>= openQuery controlled
      run reader "one" (pure ()) "never" >>= expectVerdict Unknown
      run reader "one" (emit controlled "one" 1) "exactly-once" >>= expectVerdict Unknown,
    test "a stalled client returns unavailable within the deadline" $ do
      controlled <- newControlled 1
      Backend capture observe _ <- open controlled bounded byKey
      base <- capture realClock topicSource >>= right
      blockReads controlled
      let Clock now _ _ _ = realClock
      start <- now
      result <- observe (detachedCallContext realClock (plusMicros start 80000) (plusMicros start 2000000) (Just base) (Just (ByBusinessKey (BusinessKeyName "accountId") "one")))
      end <- now
      check (differenceMicros end start < 1000000)
      case result of ObservationUnavailable "kafka-source-deadline" -> pure (); _ -> fail "stalled client reported evidence",
    test "an unreachable broker is Unknown before any action mutation" $ do
      controlled <- newControlled 1
      failWith controlled (Just KafkaUnavailable)
      reader <- open controlled bounded byKey
      mutations <- newIORef (0 :: Int)
      run reader "one" (modifyIORef' mutations (+ 1)) "eventually" >>= expectVerdict Unknown
      readIORef mutations >>= check . (== 0),
    test "missing topics, oversized topics, and missing timestamps are unavailable" $ do
      missing <- newControlled 1
      reader@(Backend capture _ _) <- open missing bounded byKey
      base <- capture realClock topicSource >>= right
      removeTopic missing
      observeAgain reader base >>= \case
        ObservationUnavailable "kafka-topic-missing" -> pure ()
        _ -> fail "missing topic was not reported"
      oversized <- newControlled 65
      Backend captureLarge _ _ <- open oversized bounded byKey
      captureLarge realClock topicSource >>= check . either (const True) (const False)
      untimed <- newControlled 1
      untimedReader <- open untimed bounded byKey
      outcome <- probe untimedReader (() <$ produce untimed (KafkaRecord 0 Nothing (Just "one") [("event-type", "Happened")] (Just "{}")))
      case outcome of ObservationUnavailable "kafka-record-timestamp-missing" -> pure (); _ -> fail "missing timestamp was accepted",
    test "transactional records stay invisible until commit and are never skipped" $ do
      mapM_
        ( \openBeforeCapture -> do
            controlled <- newControlled 1
            reader@(Backend capture _ _) <- open controlled bounded byKey
            when openBeforeCapture (() <$ (event "one" >>= begin controlled 0))
            base <- capture realClock topicSource >>= right
            unless openBeforeCapture (() <$ (event "one" >>= begin controlled 0))
            emit controlled "one" 1
            before <- observeAgain reader base
            case before of ObservedWithDetails [] (Coverage _ _ _ True) _ -> pure (); _ -> fail "uncommitted record was visible"
            commit controlled 0
            after <- observeAgain reader base
            case after of ObservedWithDetails found (Coverage _ _ _ True) _ -> check (length found == 2); _ -> fail "a committed record was skipped"
        )
        [False, True],
    test "aborted transactions and control records end partitions cleanly" $ do
      controlled <- newControlled 3
      reader <- open controlled bounded byKey
      let aborted = do
            _ <- event "one" >>= begin controlled 2
            abort controlled 2
            emit controlled "other" 1
      outcome <- probe reader aborted
      check (occurrenceCount outcome == Just 0 && coverageComplete outcome == Just True),
    test "two empty partitions and one busy partition cannot report complete until all finish" $ do
      controlled <- newControlled 3
      neverEnds controlled 2
      reader <- open controlled bounded byKey
      outcome <- probe reader (emit controlled "one" 1)
      check (occurrenceCount outcome == Just 1 && coverageComplete outcome == Just False)
      check (detail "scan-complete" outcome == Just (Observation.PublicFlag False)),
    test "a partition added during a read invalidates completeness" $ do
      controlled <- newControlled 2
      reader@(Backend capture _ _) <- open controlled bounded byKey
      base <- capture realClock topicSource >>= right
      duringRead controlled (addPartition controlled)
      outcome <- observeAgain reader base
      check (coverageComplete outcome == Just False && detail "partitions-stable" outcome == Just (Observation.PublicFlag False))
      later <- observeAgain reader base
      check (coverageComplete later == Just False)
      changing <- newControlled 2
      grown <- open changing bounded byKey
      run grown "one" (addPartition changing) "never" >>= expectVerdict Unknown,
    test "truncation past the baseline offset is sticky history loss" $ do
      controlled <- newControlled 1
      emit controlled "other" 3
      reader@(Backend capture _ _) <- open controlled bounded byKey
      base <- capture realClock topicSource >>= right
      truncateBefore controlled 0 4
      lost <- observeAgain reader base
      check (coverageComplete lost == Just False && detail "low-watermark-intact" lost == Just (Observation.PublicFlag False))
      -- An apparent recovery of the reported offsets cannot clear the observed loss.
      overrideWatermarks controlled 0 (Just (Watermarks 0 4))
      again <- observeAgain reader base
      check (coverageComplete again == Just False && detail "history-intact" again == Just (Observation.PublicFlag False) && detail "low-watermark-intact" again == Just (Observation.PublicFlag False))
      retained <- newControlled 1
      emit retained "other" 3
      truncating <- open retained bounded byKey
      run truncating "one" (truncateBefore retained 0 4) "never" >>= expectVerdict Unknown,
    test "a loss observed before a failing read remains sticky after recovery" $ do
      controlled <- newControlled 1
      reader@(Backend capture _ _) <- open controlled bounded byKey
      base <- capture realClock topicSource >>= right
      overrideWatermarks controlled 0 (Just (Watermarks 2 2))
      duringRead controlled (failWith controlled (Just KafkaUnavailable))
      observeAgain reader base >>= \case
        ObservationUnavailable _ -> pure ()
        _ -> fail "injected trailing watermark failure was not observed"
      failWith controlled Nothing
      overrideWatermarks controlled 0 (Just (Watermarks 0 0))
      recovered <- observeAgain reader base
      check (coverageComplete recovered == Just False && detail "low-watermark-intact" recovered == Just (Observation.PublicFlag False)),
    test "a read-committed end below one already observed is history loss" $ do
      controlled <- newControlled 1
      reader@(Backend capture _ _) <- open controlled bounded byKey
      base <- capture realClock topicSource >>= right
      emit controlled "other" 2
      first <- observeAgain reader base
      check (coverageComplete first == Just True)
      overrideWatermarks controlled 0 (Just (Watermarks 0 1))
      rewound <- observeAgain reader base
      check (coverageComplete rewound == Just False && detail "history-intact" rewound == Just (Observation.PublicFlag False))
  ]

-- | Plumbing checks against the owned broker; the client-backed reader groups
-- wait for a released client passing the spike named in docs/plans/10.
brokerTests :: String -> String -> [TestTree]
brokerTests bootstrap logDir =
  [ test "the owned broker accepts fixture topics through the managed tools" $ do
      topic <- ("fixture-" <>) . show . hashUnique <$> newUnique
      inherited <- getEnvironment
      let tool arguments = (proc "kafka-topics.sh" (["--bootstrap-server", bootstrap] ++ arguments)) {env = Just (("LOG_DIR", logDir) : filter ((/= "LOG_DIR") . fst) inherited)}
      (created, _, _) <- readCreateProcessWithExitCode (tool ["--create", "--topic", topic, "--partitions", "3", "--replication-factor", "1"]) ""
      check (created == ExitSuccess)
      (listed, out, _) <- readCreateProcessWithExitCode (tool ["--list"]) ""
      check (listed == ExitSuccess && topic `elem` lines out)
  ]

tests :: IO TestTree
tests = do
  bounded <- right (limits 1 20 2000)
  broker <- lookupEnv "SHOKO_KAFKA_BOOTSTRAP"
  logDir <- lookupEnv "SHOKO_KAFKA_LOG_DIR"
  let real = case (broker, logDir) of
        (Just bootstrap, Just logs) -> [testGroup ("owned broker at " <> bootstrap) (brokerTests bootstrap logs)]
        _ -> []
  pure (testGroup "kafka" (testGroup "controlled topic port" (controlledTests bounded) : real))

testMicros :: Int -> Duration
testMicros micros = either (const (error "test advance requires whole milliseconds")) id (milliseconds (max 1 ((micros + 999) `div` 1000)))

plusMicros :: MonotonicTime -> Integer -> MonotonicTime
plusMicros tick delta = MonotonicTime (monotonicMicros tick + delta)
