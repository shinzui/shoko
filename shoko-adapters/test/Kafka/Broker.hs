{-# LANGUAGE RankNTypes #-}

module Kafka.Broker (tests) where

import Control.Exception (bracket)
import Control.Monad (forM_, unless, when)
import Data.Aeson (Value (..), encode, object, (.=))
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.IORef
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (getCurrentTime)
import Kafka.Consumer qualified as C
import Kafka.Contract qualified as H
import Kafka.Fixture
import Kafka.Producer qualified as P
import Network.Socket qualified as N
import Shoko hiding (observe)
import Shoko.Adapter.Kafka
import Shoko.Adapter.Kafka.Internal qualified as Internal
import Shoko.Clock
import Shoko.Evidence (Evidence (..))
import Shoko.Observation qualified as O
import Shoko.Result
import Shoko.Result.Json (encodeRunResult)
import Test.Tasty (TestTree, testGroup)

queryFor :: C.TopicName -> Limits -> HistoryPolicy -> CorrelationMode -> (Value -> Either Text Bool) -> IO (EventQuery Bool)
queryFor (C.TopicName topic) bounded policy mode decode = do
  scope <- right (topicScope topic)
  right (eventQuery bounded scope policy mode "Happened" decode)

settingsFor :: Broker -> IO KafkaSettings
settingsFor (Broker address _) = right (kafkaSettings address Map.empty)

backend :: KafkaSettings -> EventQuery Bool -> IO H.Backend
backend settings query = kafka settings H.topicSource query >>= right >>= backendFor query

backendFor :: EventQuery Bool -> Kafka Bool -> IO H.Backend
backendFor query reader = do
  handler <- right (kafkaObservation H.topicSource query)
  let selected = focus (const reader) handler
  pure (H.Backend (H.captureForTestWith 10000 selected) (\call -> observeKafka call reader) selected)

run :: H.Backend -> IO () -> Text -> IO (RunResult, Int)
run reader action assertion = do
  result <- H.runWith 30000 3000 reader "one" action assertion
  let encoded = BL.toStrict (encodeRunResult (fst result))
  check (not ("127.0.0.1:" `BS.isInfixOf` encoded))
  pure result

send :: P.KafkaProducer -> C.TopicName -> Int -> BS.ByteString -> IO ()
send producer topic partition key = produce producer topic partition (Just key) [("event-type", "Happened")] (Just "{\"accountId\":\"one\"}")

capture :: H.Backend -> Clock -> IO Baseline
capture (H.Backend baseline _ _) clock = baseline clock H.topicSource >>= right

callFor :: Clock -> Baseline -> MonotonicTime -> MonotonicTime -> CallContext
callFor clock base deadline cutoff = detachedCallContext clock deadline cutoff (Just base) (Just (ByBusinessKey (BusinessKeyName "accountId") "one"))

observe :: H.Backend -> Baseline -> IO (ObservationOutcome (EventEvidence Bool))
observe (H.Backend _ readEvents _) base = do
  let Clock now _ _ _ = realClock
  started <- now
  readEvents (callFor realClock base (H.plusMicros started 10000000) (H.plusMicros started 10000000))

hasPublicFlag :: Text -> Bool -> (RunResult, Int) -> Bool
hasPublicFlag name wanted (Verification VerificationResult {expectations = ExpectationResult {evidence = Evidence {supportingData = details}} : _}, _) = (name, O.PublicFlag wanted) `elem` details
hasPublicFlag _ _ _ = False

tests :: Broker -> TestTree
tests broker =
  testGroup "public Kafka reader" $
    [ test "real reader descriptors and denied policy allocate no consumers" $ do
        settings <- settingsFor broker
        bounded <- right (limits 1 20 5000)
        query <- queryFor (C.TopicName "fixture-descriptor") bounded AppendOnlyDuringRun H.byKey H.decodeFixture
        handler <- right (kafkaObservation H.topicSource query)
        acquired <- newIORef (0 :: Int)
        let client = modifyIORef' acquired (+ 1) >> Internal.newKafkaConsumer settings
            allocate selected = Internal.kafkaReader (Internal.kafkaClientPortWith client) H.topicSource selected >>= right
        H.deniedBeforeAllocation handler (allocate query)
        otherLimits <- right (limits 2 20 5000)
        variants <-
          sequence
            [ queryFor (C.TopicName "fixture-descriptor") otherLimits AppendOnlyDuringRun H.byKey H.decodeFixture,
              queryFor (C.TopicName "fixture-other") bounded AppendOnlyDuringRun H.byKey H.decodeFixture,
              queryFor (C.TopicName "fixture-descriptor") bounded UnverifiedHistory H.byKey H.decodeFixture,
              queryFor (C.TopicName "fixture-descriptor") bounded AppendOnlyDuringRun (BusinessKeyHeader (BusinessKeyName "accountId") "private") H.decodeFixture,
              do scope <- right (topicScope "fixture-descriptor"); right (eventQuery bounded scope AppendOnlyDuringRun H.byKey "Other" H.decodeFixture)
            ]
        mapM_ (H.assertDescriptorMismatch handler . allocate) variants
        readIORef acquired >>= check . (== 0),
      test "produce then exactlyOnce passes across repeated one-record polls" $
        fresh 1 $ \topic reader -> withProducer broker Nothing $ \producer -> do
          result@(_, polls) <- run reader (send producer topic 0 "one") "exactly-once"
          H.expectVerdict Pass result
          check (polls > 1),
      test "two distinct records fail cardinality" $
        fresh 1 $ \topic reader -> withProducer broker Nothing $ \producer ->
          run reader (send producer topic 0 "one" >> send producer topic 0 "one") "exactly-once" >>= H.expectVerdict Fail,
      test "complete empty reads close never and eventually with two empty partitions" $
        fresh 3 $ \_ reader -> do
          run reader (pure ()) "never" >>= H.expectVerdict Pass
          run reader (pure ()) "eventually" >>= H.expectVerdict Fail,
      test "unrelated keys and pre-baseline records do not satisfy the query" $
        fresh 1 $ \topic reader -> withProducer broker Nothing $ \producer -> do
          send producer topic 0 "one"
          run reader (send producer topic 0 "other") "eventually" >>= H.expectVerdict Fail,
      test "independent readers see stable partition occurrence ids" $ do
        topic <- newTopic broker 3
        settings <- settingsFor broker
        query <- standard topic
        first <- backend settings query
        second <- backend settings query
        b1 <- capture first realClock
        b2 <- capture second realClock
        withProducer broker Nothing $ \producer -> forM_ [0, 1, 2] $ \partition -> send producer topic partition "one"
        a <- observe first b1
        b <- observe second b2
        case (a, b) of
          (ObservedWithDetails found (Coverage _ _ _ True) _, ObservedWithDetails again (Coverage _ _ _ True) _) -> do
            let ids events = Set.fromList [key | Occurrence key _ <- events]
            check (length found == 3 && ids found == ids again && Set.size (ids found) == 3)
          _ -> fail "independent readers did not finish all three partitions",
      test "declared-type records without a key are Unknown" $
        fresh 1 $ \topic reader -> withProducer broker Nothing $ \producer ->
          run reader (produce producer topic 0 Nothing [("event-type", "Happened")] (Just "{}")) "eventually" >>= H.expectVerdict Unknown,
      test "correlated decode failures cannot leak payloads or decoder messages" $ do
        topic <- newTopic broker 1
        settings <- settingsFor broker
        bounded <- right (limits 1 20 5000)
        query <- queryFor topic bounded AppendOnlyDuringRun H.byKey (const (Left "SECRET-FIXTURE-DECODER"))
        reader <- backend settings query
        withProducer broker Nothing $ \producer ->
          run reader (send producer topic 0 "one") "eventually" >>= H.expectVerdict Unknown,
      test "malformed keys and non-JSON correlated values are Unknown" $
        fresh 1 $ \topic reader -> withProducer broker Nothing $ \producer -> do
          run reader (send producer topic 0 "\255") "eventually" >>= H.expectVerdict Unknown
          run reader (produce producer topic 0 (Just "one") [("event-type", "Happened")] (Just "SECRET-FIXTURE-VALUE")) "eventually" >>= H.expectVerdict Unknown,
      test "duplicate private headers and event-type headers select their last wire value" $ do
        topic <- newTopic broker 3
        settings <- settingsFor broker
        bounded <- right (limits 1 20 5000)
        query <- queryFor topic bounded AppendOnlyDuringRun (BusinessKeyHeader (BusinessKeyName "accountId") "SECRET-FIXTURE-HEADER") H.decodeFixture
        reader <- backend settings query
        withProducer broker Nothing $ \producer -> do
          let matching = produce producer topic 1 (Just "ignored") [("event-type", "Other"), ("SECRET-FIXTURE-HEADER", "other"), ("SECRET-FIXTURE-HEADER", "one"), ("event-type", "Happened")] (Just "{}")
              unrelated = produce producer topic 2 (Just "one") [("event-type", "Happened"), ("SECRET-FIXTURE-HEADER", "one"), ("SECRET-FIXTURE-HEADER", "other")] (Just "{}")
          run reader (matching >> unrelated) "exactly-once" >>= H.expectVerdict Pass,
      test "record-key correlation selects one occurrence across partitions" $
        fresh 3 $ \topic reader -> withProducer broker Nothing $ \producer ->
          run reader (forM_ [(0, "other"), (1, "one"), (2, "third")] $ \(partition, key) -> send producer topic partition key) "exactly-once" >>= H.expectVerdict Pass,
      test "payload-field correlation is independent of record keys" $ do
        topic <- newTopic broker 1
        settings <- settingsFor broker
        bounded <- right (limits 1 20 5000)
        query <- queryFor topic bounded AppendOnlyDuringRun (BusinessKeyField (BusinessKeyName "accountId")) H.decodeFixture
        reader <- backend settings query
        withProducer broker Nothing $ \producer ->
          run reader (send producer topic 0 "ignored") "exactly-once" >>= H.expectVerdict Pass,
      test "invalid private header UTF-8 is unavailable without broadening" $ do
        topic <- newTopic broker 1
        settings <- settingsFor broker
        bounded <- right (limits 1 20 5000)
        query <- queryFor topic bounded AppendOnlyDuringRun (BusinessKeyHeader (BusinessKeyName "accountId") "SECRET-FIXTURE-HEADER") H.decodeFixture
        reader <- backend settings query
        withProducer broker Nothing $ \producer ->
          run reader (produce producer topic 0 (Just "one") [("event-type", "Happened"), ("SECRET-FIXTURE-HEADER", "\255")] (Just "{}")) "eventually" >>= H.expectVerdict Unknown,
      test "untyped and unrelated malformed records do not corrupt matching evidence" $
        fresh 1 $ \topic reader -> withProducer broker Nothing $ \producer -> do
          let action = do
                produce producer topic 0 Nothing [] Nothing
                produce producer topic 0 (Just "\255") [("event-type", "Other")] (Just "SECRET-FIXTURE-VALUE")
                send producer topic 0 "one"
          run reader action "exactly-once" >>= H.expectVerdict Pass,
      test "page exhaustion cannot prove exactly-once cardinality" $ do
        topic <- newTopic broker 1
        settings <- settingsFor broker
        bounded <- right (limits 1 1 5000)
        query <- queryFor topic bounded AppendOnlyDuringRun H.byKey H.decodeFixture
        reader <- backend settings query
        withProducer broker Nothing $ \producer ->
          run reader (send producer topic 0 "one" >> send producer topic 0 "one") "exactly-once" >>= H.expectVerdict Unknown,
      test "unverified history cannot prove absence or exactly-once" $ do
        topic <- newTopic broker 1
        settings <- settingsFor broker
        bounded <- right (limits 1 20 5000)
        query <- queryFor topic bounded UnverifiedHistory H.byKey H.decodeFixture
        reader <- backend settings query
        run reader (pure ()) "never" >>= H.expectVerdict Unknown
        withProducer broker Nothing $ \producer -> run reader (send producer topic 0 "one") "exactly-once" >>= H.expectVerdict Unknown,
      test "transactional visibility includes transactions opened before baseline" $
        forM_ [False, True] $ \openBefore -> do
          topic <- newTopic broker 1
          settings <- settingsFor broker
          reader <- standard topic >>= backend settings
          transaction <- unique
          withProducer broker (Just transaction) $ \producer -> do
            when openBefore (begin producer >> send producer topic 0 "one")
            base <- capture reader realClock
            unless openBefore (begin producer >> send producer topic 0 "one")
            withProducer broker Nothing $ \ordinary -> send ordinary topic 0 "one"
            before <- observe reader base
            check (H.occurrenceCount before == Just 0 && H.coverageComplete before == Just True)
            commit producer
            after <- observe reader base
            check (H.occurrenceCount after == Just 2 && H.coverageComplete after == Just True),
      test "aborted transactions finish an empty partition without witnesses" $
        fresh 3 $ \topic reader -> do
          transaction <- unique
          withProducer broker (Just transaction) $ \producer -> do
            let action = begin producer >> send producer topic 2 "one" >> abort producer
            run reader action "never" >>= H.expectVerdict Pass,
      test "late records are ambiguous and through stays at the host cutoff" $
        fresh 1 $ \topic reader@(H.Backend _ readEvents _) -> do
          base <- capture reader realClock
          withProducer broker Nothing $ \producer -> do
            send producer topic 0 "one"
            let Clock now _ sleep _ = realClock
            start <- now
            let cutoff = H.plusMicros start 3000000
            early <- readEvents (callFor realClock base (H.plusMicros start 10000000) cutoff)
            check (H.occurrenceCount early == Just 1 && H.coverageComplete early == Just True)
            sleep (H.plusMicros cutoff 1000)
            send producer topic 0 "one"
            late <- readEvents (callFor realClock base (H.plusMicros cutoff 10000000) cutoff)
            case late of
              ObservedWithDetails found (Coverage _ _ through False) _ -> check (length found == 1 && through == cutoff)
              _ -> fail "a late record was admitted to the finite count",
      test "a real read crossing a fake host cutoff reports conservative coverage" $
        fresh 1 $ \_ reader@(H.Backend _ readEvents _) -> do
          epoch <- getCurrentTime
          (baselineClock, _) <- newFakeClock epoch
          base <- capture reader baselineClock
          (Clock now wall sleep bound, advance) <- newFakeClock epoch
          let crossingBound :: forall a. MonotonicTime -> IO a -> IO (Maybe a)
              crossingBound deadline action = do
                answer <- bound deadline action
                advance (H.testMicros 1000)
                pure answer
              crossing = Clock now wall sleep crossingBound
          readEvents (callFor crossing base (MonotonicTime 10000000) (MonotonicTime 500)) >>= \case
            ObservedWithDetails [] (Coverage _ _ through _) _ -> check (through < MonotonicTime 500)
            _ -> fail "crossing read did not retain its conservative start bound",
      test "an 80ms adapter deadline releases the accepted silent-broker socket" $
        withSilentBroker $ \address accepted closed -> do
          topic <- newTopic broker 1
          normal <- settingsFor broker
          chosen <- newIORef normal
          query <- standard topic
          raw <- Internal.kafkaReader (Internal.kafkaClientPortWith (readIORef chosen >>= Internal.newKafkaConsumer)) H.topicSource query >>= right
          reader@(H.Backend _ readEvents _) <- backendFor query raw
          base <- capture reader realClock
          silent <- right (kafkaSettings address Map.empty)
          writeIORef chosen silent
          let Clock now _ _ _ = realClock
          start <- now
          answer <- readEvents (callFor realClock base (H.plusMicros start 80000) (H.plusMicros start 10000000))
          finished <- now
          check (differenceMicros finished start < 1000000)
          case answer of ObservationUnavailable "kafka-source-deadline" -> pure (); _ -> fail "silent broker produced evidence"
          accepted
          closed,
      test "unreachable bootstrap is Unknown before mutation" $ do
        address <- bracket (N.socket N.AF_INET N.Stream N.defaultProtocol) N.close $ \socket -> do
          N.bind socket (N.SockAddrInet 0 (N.tupleToHostAddress (127, 0, 0, 1)))
          port <- N.socketPort socket
          pure ("127.0.0.1:" <> Text.pack (show port))
        settings <- right (kafkaSettings address Map.empty)
        bounded <- right (limits 1 20 100)
        query <- queryFor (C.TopicName "fixture-unreachable") bounded AppendOnlyDuringRun H.byKey H.decodeFixture
        reader <- backend settings query
        mutations <- newIORef (0 :: Int)
        run reader (modifyIORef' mutations (+ 1)) "eventually" >>= H.expectVerdict Unknown
        readIORef mutations >>= check . (== 0),
      test "missing topics and invalid private client settings fail before mutation" $ do
        settings <- settingsFor broker
        query <- standard (C.TopicName "missing-adapter-topic")
        reader <- backend settings query
        mutations <- newIORef (0 :: Int)
        run reader (modifyIORef' mutations (+ 1)) "never" >>= H.expectVerdict Unknown
        let Broker address _ = broker
        invalid <- right (kafkaSettings address (Map.singleton "security.protocol" "SECRET-FIXTURE-INVALID"))
        invalidReader <- backend invalid query
        run invalidReader (modifyIORef' mutations (+ 1)) "never" >>= H.expectVerdict Unknown
        readIORef mutations >>= check . (== 0),
      test "partition growth during an actual partition read invalidates coverage" $ do
        topic@(C.TopicName name) <- newTopic broker 1
        settings <- settingsFor broker
        bounded <- right (limits 1 20 20000)
        query <- queryFor topic bounded AppendOnlyDuringRun H.byKey H.decodeFixture
        armed <- newIORef False
        let actual = Internal.kafkaClientPort settings
            intercepted clock deadline selected partition start limit = do
              answer <- Internal.readPartition actual clock deadline selected partition start limit
              change <- atomicModifyIORef' armed (\pending -> (False, pending))
              when change (() <$ tool broker "kafka-topics.sh" ["--alter", "--topic", Text.unpack name, "--partitions", "2"] "")
              pure answer
        raw <- Internal.kafkaReader actual {Internal.readPartition = intercepted} H.topicSource query >>= right
        reader <- backendFor query raw
        result <- run reader (writeIORef armed True) "never"
        H.expectVerdict Unknown result
        check (hasPublicFlag "partitions-stable" False result),
      test "real record deletion beyond the baseline prevents a passing never" $
        fresh 1 $ \topic@(C.TopicName name) reader -> withProducer broker Nothing $ \producer -> do
          identifier <- unique
          let Broker _ logs = broker
              path = logs <> "/delete-" <> Text.unpack identifier <> ".json"
              truncateAt offset = do
                forM_ [1 :: Int .. 3] $ \_ -> send producer topic 0 "other"
                BL.writeFile path (encode (object ["version" .= (1 :: Int), "partitions" .= [object ["topic" .= name, "partition" .= (0 :: Int), "offset" .= (offset :: Int)]]]))
                _ <- tool broker "kafka-delete-records.sh" ["--offset-json-file", path] ""
                pure ()
          base <- capture reader realClock
          truncateAt 2
          lost <- observe reader base
          check (H.coverageComplete lost == Just False && H.detail "low-watermark-intact" lost == Just (O.PublicFlag False))
          result <- run reader (truncateAt 5) "never"
          H.expectVerdict Unknown result
          check (hasPublicFlag "low-watermark-intact" False result)
    ]
  where
    standard topic = right (limits 1 20 5000) >>= \bounded -> queryFor topic bounded AppendOnlyDuringRun H.byKey H.decodeFixture
    fresh partitions action = do
      topic <- newTopic broker partitions
      settings <- settingsFor broker
      reader <- standard topic >>= backend settings
      action topic reader
