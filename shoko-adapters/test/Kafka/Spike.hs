module Kafka.Spike (tests) where

import Control.Exception (bracket)
import Control.Monad (unless)
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import GHC.Clock (getMonotonicTimeNSec)
import Kafka.Consumer qualified as C
import Kafka.Fixture
import Kafka.Metadata qualified as M
import System.Timeout (timeout)
import Test.Tasty (TestTree, testGroup)

tests :: Broker -> TestTree
tests broker =
  testGroup
    "released client spike"
    [ test "assign-only records, attributed EOF for two empty partitions and a busy partition, and origin-free timeout" $ do
        topic <- newTopic broker 3
        withProducer broker Nothing $ \producer -> produce producer topic 2 (Just "key") [("event-type", "Happened"), ("header", "value")] (Just "{}")
        withObserver broker $ \consumer -> do
          C.assign consumer [C.TopicPartition topic (C.PartitionId partition) (C.PartitionOffset 0) | partition <- [0, 1, 2]] >>= check . (== Nothing)
          let loop ends records
                | Map.size ends == 3 = pure (ends, records)
                | otherwise =
                    C.pollMessageAttributed consumer (C.Timeout 100) >>= \case
                      Right record -> loop ends (record : records)
                      Left (C.ConsumerMessageError (C.KafkaResponseError C.RdKafkaRespErrTimedOut) Nothing Nothing Nothing) -> loop ends records
                      Left (C.ConsumerMessageError (C.KafkaResponseError C.RdKafkaRespErrPartitionEof) (Just actual) (Just partition) (Just offset)) -> do
                        check (actual == topic && Map.notMember partition ends)
                        loop (Map.insert partition offset ends) records
                      _ -> fail "unexpected attributed message error"
          (ends, records) <- timeout 10000000 (loop Map.empty []) >>= maybe (fail "EOF missing") pure
          check (Map.elems ends == [C.Offset 0, C.Offset 0, C.Offset 1])
          case records of
            [C.ConsumerRecord actual (C.PartitionId 2) (C.Offset 0) timestamp headers key value] -> do
              check (actual == topic && key == Just "key" && value == Just "{}")
              check (lookup "event-type" (C.headersToList headers) == Just "Happened" && lookup "header" (C.headersToList headers) == Just "value")
              case timestamp of C.CreateTime _ -> pure (); C.LogAppendTime _ -> pure (); _ -> fail "missing timestamp"
            _ -> fail "unexpected record count"
          C.pollMessageAttributed consumer (C.Timeout 10) >>= \case
            Left (C.ConsumerMessageError (C.KafkaResponseError C.RdKafkaRespErrTimedOut) Nothing Nothing Nothing) -> pure ()
            _ -> fail "a poll timeout was treated as EOF"
          mapM_
            ( \partition -> do
                M.WatermarkOffsets _ _ low high <- M.partitionWatermarkOffsets consumer (C.Timeout 2000) topic partition >>= right
                check (low == C.Offset 0 && Just high == Map.lookup partition ends)
            )
            (Map.keys ends),
      test "wire header order preserves last duplicate selection" $ do
        topic <- newTopic broker 1
        let headers = [("event-type", "Other"), ("account", "two"), ("account", "one"), ("event-type", "Happened")]
        withProducer broker Nothing $ \producer -> produce producer topic 0 (Just "key") headers (Just "{}")
        withObserver broker $ \consumer -> do
          C.assign consumer [C.TopicPartition topic (C.PartitionId 0) (C.PartitionOffset 0)] >>= check . (== Nothing)
          records <- readEnd consumer
          case records of
            [C.ConsumerRecord _ _ _ _ actual _ _] ->
              unless (C.headersToList actual == headers) (fail "mori://shinzui/rdkafka-hs/okf/improvement-requests/concepts/IR-3: decoded headers reverse wire order; last-duplicate correlation is unsafe")
            _ -> fail "duplicate-header fixture record missing",
      test "committed-visible watermarks and EOF stop behind an open transaction, then include both records" $ do
        topic <- newTopic broker 1
        transaction <- unique
        withProducer broker (Just transaction) $ \producer -> do
          begin producer
          produce producer topic 0 (Just "key") [] (Just "pending")
          withProducer broker Nothing $ \ordinary -> produce ordinary topic 0 Nothing [] (Just "committed")
          withObserver broker $ \consumer -> do
            M.WatermarkOffsets _ _ low high <- M.partitionWatermarkOffsets consumer (C.Timeout 5000) topic (C.PartitionId 0) >>= right
            check (low == C.Offset 0 && high == C.Offset 0)
            C.assign consumer [C.TopicPartition topic (C.PartitionId 0) (C.PartitionOffset 0)] >>= check . (== Nothing)
            before <- readEnd consumer
            check (null before)
            commit producer
            after <- readEnd consumer
            check (map C.crOffset after == [C.Offset 0, C.Offset 1])
            M.WatermarkOffsets _ _ _ visible <- M.partitionWatermarkOffsets consumer (C.Timeout 5000) topic (C.PartitionId 0) >>= right
            check (visible > C.Offset 1),
      test "aborted transactions and control records reach attributed EOF" $ do
        topic <- newTopic broker 1
        transaction <- unique
        withProducer broker (Just transaction) $ \producer -> do
          begin producer
          produce producer topic 0 Nothing [] (Just "aborted")
          abort producer
        withObserver broker $ \consumer -> do
          C.assign consumer [C.TopicPartition topic (C.PartitionId 0) (C.PartitionOffset 0)] >>= check . (== Nothing)
          readEnd consumer >>= check . null,
      test "a nonexistent topic assignment returns an error without creation" $ do
        name <- ("missing-" <>) <$> unique
        withObserver broker $ \consumer -> do
          C.assign consumer [C.TopicPartition (C.TopicName name) (C.PartitionId 0) (C.PartitionOffset 0)] >>= check . (== Nothing)
          -- Assignment is local and can succeed before metadata arrives. Probe
          -- metadata explicitly, as the adapter must, rather than interpreting
          -- a poll timeout or waiting for asynchronous error propagation.
          M.topicMetadata consumer (C.Timeout 2000) (C.TopicName name) >>= \case
            Left _ -> pure ()
            Right (M.KafkaMetadata _ topics _) -> check (null topics || any (\(M.TopicMetadata _ _ err) -> err /= Nothing) topics)
        listed <- tool broker "kafka-topics.sh" ["--list"] ""
        check (Text.unpack name `notElem` lines listed),
      test "80ms silent-broker request releases its accepted socket within one second" $
        withSilentBroker $ \address accepted closed -> do
          started <- getMonotonicTimeNSec
          outcome <- timeout 80000 $
            bracket (observerProperties address >>= C.newAssignedConsumer >>= right) C.destroyConsumer $ \consumer -> do
              M.topicMetadata consumer (C.Timeout 70) (C.TopicName "missing")
          finished <- getMonotonicTimeNSec
          check (finished - started < 1000000000)
          accepted
          closed
          -- Both the native timeout and asynchronous cancellation are valid;
          -- neither supplies evidence of a partition end.
          check (case outcome of Just (Right _) -> False; _ -> True)
    ]

readEnd :: C.KafkaConsumer -> IO [C.ConsumerRecord (Maybe BS.ByteString) (Maybe BS.ByteString)]
readEnd consumer = timeout 10000000 (loop []) >>= maybe (fail "partition did not finish") pure
  where
    loop found =
      C.pollMessageAttributed consumer (C.Timeout 100) >>= \case
        Right record -> loop (record : found)
        Left (C.ConsumerMessageError (C.KafkaResponseError C.RdKafkaRespErrTimedOut) _ _ _) -> loop found
        Left (C.ConsumerMessageError (C.KafkaResponseError C.RdKafkaRespErrPartitionEof) (Just _) (Just (C.PartitionId 0)) (Just _)) -> pure (reverse found)
        _ -> fail "unexpected poll failure"
