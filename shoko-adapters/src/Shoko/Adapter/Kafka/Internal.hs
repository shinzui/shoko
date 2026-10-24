-- | Kafka topic scans over a client port. Hosts use "Shoko.Adapter.Kafka";
-- this module is exposed so tests can supply a controlled port and so the
-- client binding can be verified separately. It has no stability promise.
module Shoko.Adapter.Kafka.Internal where

import Control.Exception (bracket, try)
import Data.Aeson qualified as Aeson
import Data.ByteString (ByteString)
import Data.Char (isAsciiLower, isAsciiUpper, isDigit, isHexDigit)
import Data.IORef
import Data.Int (Int32, Int64)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (listToMaybe)
import Data.Set qualified as Set
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Data.Time (UTCTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Data.UUID qualified as UUID
import Data.UUID.V4 qualified as UUID
import Data.Unique (hashUnique, newUnique)
import Kafka.Consumer qualified as C
import Kafka.Metadata qualified as M
import Shoko.Adapter.EventStore.Internal
import Shoko.Binding
import Shoko.Clock
import Shoko.Identifier
import Shoko.Observation (ObservationOutcome, PublicValue (..))
import Shoko.Prelude

-- | Bootstrap servers and opaque security properties. There is deliberately no
-- rendering instance: addresses and credentials never reach reports or logs.
data KafkaSettings = KafkaSettings
  { bootstrapServers :: ![Text],
    securityProperties :: !(Map Text Text)
  }

-- | A comma-separated @host:port@ list without scheme or credentials, and only
-- @security.protocol@, @sasl.*@, or @ssl.*@ client properties. Every other
-- property, including group, commit, EOF, isolation, and topic-creation
-- settings, belongs to the observer and is rejected.
kafkaSettings :: Text -> Map Text Text -> Either Text KafkaSettings
kafkaSettings servers properties = do
  hosts <- traverse endpoint (Text.splitOn "," servers)
  if all permitted (Map.keys properties)
    then Right (KafkaSettings hosts properties)
    else Left "unsupported-kafka-property"
  where
    endpoint raw = case Text.breakOnEnd ":" (Text.strip raw) of
      (prefix, port)
        | Just host <- Text.stripSuffix ":" prefix,
          validHost host && validPort port ->
            Right (host <> ":" <> port)
      _ -> Left "invalid-kafka-bootstrap"
    validHost host = case Text.stripPrefix "[" host >>= Text.stripSuffix "]" of
      Just address -> not (Text.null address) && Text.all (\c -> isHexDigit c || c `elem` [':', '.']) address
      Nothing -> not (Text.null host) && Text.length host <= 253 && Text.all (\c -> isAsciiLower c || isAsciiUpper c || isDigit c || c `elem` ['.', '-', '_']) host
    validPort port = not (Text.null port) && Text.length port <= 5 && Text.all isDigit port && inRange (read (Text.unpack port) :: Int)
    inRange port = port >= 1 && port <= 65535
    permitted key = key == "security.protocol" || "sasl." `Text.isPrefixOf` key || "ssl." `Text.isPrefixOf` key

-- | One record as delivered by the client, in partition offset order.
data KafkaRecord = KafkaRecord
  { recordOffset :: !Int64,
    recordTimestamp :: !(Maybe UTCTime),
    recordKey :: !(Maybe ByteString),
    recordHeaders :: ![(ByteString, ByteString)],
    recordValue :: !(Maybe ByteString)
  }

-- | The first retained offset and the read-committed end (last stable offset).
data Watermarks = Watermarks
  { lowOffset :: !Int64,
    visibleEndOffset :: !Int64
  }
  deriving stock (Eq, Show)

-- | 'reachedEnd' is true only when the client observed partition EOF for this
-- partition; a timeout or a record limit is never an end.
data PartitionRead = PartitionRead
  { partitionRecords :: ![KafkaRecord],
    reachedEnd :: !Bool
  }

data KafkaFailure = KafkaTopicMissing | KafkaUnavailable | KafkaDeadline
  deriving stock (Eq, Show)

-- | Read-only client operations under an absolute deadline. An implementation
-- must use read-committed isolation, never join a consumer group, never
-- commit offsets or create topics, release every client before returning, and
-- return 'KafkaDeadline' rather than block past the deadline.
data KafkaPort = KafkaPort
  { topicPartitions :: Clock -> MonotonicTime -> Text -> IO (Either KafkaFailure [Int32]),
    partitionWatermarks :: Clock -> MonotonicTime -> Text -> Int32 -> IO (Either KafkaFailure Watermarks),
    -- | Topic, partition, first offset, and the maximum number of records.
    readPartition :: Clock -> MonotonicTime -> Text -> Int32 -> Int64 -> Int -> IO (Either KafkaFailure PartitionRead)
  }

newtype Kafka a = Kafka (Reader a)

-- | Allocate run-local bookkeeping only. Broker connections are acquired by
-- baseline capture and observations, after the runner's policy preflight.
kafka :: KafkaSettings -> SourceId -> EventQuery a -> IO (Either Text (Kafka a))
kafka settings = kafkaReader (kafkaClientPort settings)

newKafkaConsumer :: KafkaSettings -> IO (Either C.KafkaError C.KafkaConsumer)
newKafkaConsumer (KafkaSettings servers properties) = do
  unique <- UUID.toText <$> UUID.nextRandom
  C.newAssignedConsumer $
    C.extraProps properties
      <> C.brokersList (map C.BrokerAddress servers)
      <> C.groupId (C.ConsumerGroupId ("shoko-observer-" <> unique))
      <> C.clientId (C.ClientId "shoko-topic-observer")
      <> C.noAutoCommit
      <> C.noAutoOffsetStore
      <> C.extraProp "enable.partition.eof" "true"
      <> C.extraProp "allow.auto.create.topics" "false"
      <> C.extraProp "isolation.level" "read_committed"
      <> C.extraProp "fetch.wait.max.ms" "10"
      <> C.callbackPollMode C.CallbackPollModeSync
      <> C.setCallback (C.errorCallback (\_ _ -> pure ()))
      <> C.setCallback (C.logCallback (\_ _ _ -> pure ()))

kafkaClientPort :: KafkaSettings -> KafkaPort
kafkaClientPort = kafkaClientPortWith . newKafkaConsumer

-- | Acquisition seam for lifecycle/preflight tests. Every successful client
-- belongs to one operation and is synchronously destroyed before it returns.
kafkaClientPortWith :: IO (Either C.KafkaError C.KafkaConsumer) -> KafkaPort
kafkaClientPortWith acquire = KafkaPort metadata marks readOne
  where
    withClient :: Clock -> MonotonicTime -> (C.KafkaConsumer -> IO (Either KafkaFailure a)) -> IO (Either KafkaFailure a)
    withClient clock@(Clock _ _ _ bound) deadline action = do
      remainingMillis clock deadline >>= \case
        Left err -> pure (Left err)
        Right _ -> do
          answer <- bound deadline $
            try @C.KafkaError $
              bracket acquire (either (const (pure ())) C.destroyConsumer) $ \case
                Left _ -> pure (Left KafkaUnavailable)
                Right client -> action client
          pure $ case answer of
            Nothing -> Left KafkaDeadline
            Just (Left _) -> Left KafkaUnavailable
            Just (Right result) -> result
    timed :: Clock -> MonotonicTime -> (C.Timeout -> IO (Either C.KafkaError a)) -> IO (Either KafkaFailure a)
    timed clock deadline action =
      remainingMillis clock deadline >>= either (pure . Left) (\millis -> either (Left . clientFailure) Right <$> action (C.Timeout millis))
    metadata clock deadline topic = withClient clock deadline $ \client ->
      timed clock deadline (\budget -> M.topicMetadata client budget (C.TopicName topic)) `andThen` \(M.KafkaMetadata _ topics _) ->
        pure $ case [entry | entry@(M.TopicMetadata actual _ _) <- topics, actual == C.TopicName topic] of
          [] -> Left KafkaTopicMissing
          [M.TopicMetadata _ partitions Nothing] -> do
            ids <- traverse partitionId partitions
            if null ids || length ids /= Set.size (Set.fromList ids) then Left KafkaUnavailable else Right ids
          [M.TopicMetadata _ _ (Just err)] -> Left (clientFailure err)
          _ -> Left KafkaUnavailable
    partitionId (M.PartitionMetadata (C.PartitionId partition) Nothing _ _ _)
      | partition >= 0 && toInteger partition <= toInteger (maxBound :: Int32) = Right (fromIntegral partition)
    partitionId _ = Left KafkaUnavailable
    marks clock deadline topic partition = withClient clock deadline $ \client ->
      timed clock deadline (\budget -> M.partitionWatermarkOffsets client budget (C.TopicName topic) (C.PartitionId (fromIntegral partition))) `andThen` \case
        M.WatermarkOffsets actual selected (C.Offset low) (C.Offset high)
          | actual == C.TopicName topic && selected == C.PartitionId (fromIntegral partition) && low >= 0 && high >= low -> pure (Right (Watermarks low high))
        _ -> pure (Left KafkaUnavailable)
    readOne clock deadline topic partition start limit = withClient clock deadline $ \client -> do
      let selected = C.PartitionId (fromIntegral partition)
          named = C.TopicName topic
          poll records count =
            remainingMillis clock deadline >>= \case
              Left err -> pure (Left err)
              Right millis ->
                C.pollMessageAttributed client (C.Timeout (min 100 millis)) >>= \case
                  Right (C.ConsumerRecord actual found (C.Offset offset) timestamp headers key value)
                    | actual == named && found == selected -> do
                        let record = KafkaRecord offset (recordTime timestamp) key (C.headersToList headers) value
                            accumulated = record : records
                        if count + 1 >= limit
                          then pure (Right (PartitionRead (reverse accumulated) False))
                          else poll accumulated (count + 1)
                  Left (C.ConsumerMessageError (C.KafkaResponseError C.RdKafkaRespErrPartitionEof) (Just actual) (Just found) (Just (C.Offset offset)))
                    | actual == named && found == selected && offset >= start -> pure (Right (PartitionRead (reverse records) True))
                  Left (C.ConsumerMessageError (C.KafkaResponseError C.RdKafkaRespErrTimedOut) Nothing Nothing Nothing) -> poll records count
                  Left (C.ConsumerMessageError err _ _ _) -> pure (Left (clientFailure err))
                  _ -> pure (Left KafkaUnavailable)
      remainingMillis clock deadline >>= \case
        Left err -> pure (Left err)
        Right _ ->
          C.assign client [C.TopicPartition named selected (C.PartitionOffset start)] >>= \case
            Just err -> pure (Left (clientFailure err))
            Nothing -> poll [] 0

-- Every timed native call receives only the remaining whole milliseconds.
remainingMillis :: Clock -> MonotonicTime -> IO (Either KafkaFailure Int)
remainingMillis (Clock now _ _ _) deadline = do
  current <- now
  let remaining = differenceMicros deadline current `div` 1000
  pure $ if remaining <= 0 then Left KafkaDeadline else Right (fromInteger (min remaining (toInteger (maxBound :: Int))))

clientFailure :: C.KafkaError -> KafkaFailure
clientFailure = \case
  C.KafkaResponseError C.RdKafkaRespErrTimedOut -> KafkaDeadline
  C.KafkaResponseError C.RdKafkaRespErrUnknownTopicOrPart -> KafkaTopicMissing
  C.KafkaResponseError C.RdKafkaRespErrUnknownTopic -> KafkaTopicMissing
  _ -> KafkaUnavailable

recordTime :: C.Timestamp -> Maybe UTCTime
recordTime = \case
  C.CreateTime (C.Millis millis) -> Just (posixSecondsToUTCTime (fromIntegral millis / 1000))
  C.LogAppendTime (C.Millis millis) -> Just (posixSecondsToUTCTime (fromIntegral millis / 1000))
  C.NoTimestamp -> Nothing

-- | Run-local scan state. Offsets are typed here; the baseline token is only
-- a diagnostic rendering and is never parsed back. Losses are sticky.
data TopicState = TopicState
  { startOffsets :: !(Map Int32 Int64),
    observedEnds :: !(Map Int32 Int64),
    historyLost :: !Bool,
    lowWatermarkLost :: !Bool
  }

maxPartitions :: Int
maxPartitions = 64

kafkaReader :: KafkaPort -> SourceId -> EventQuery a -> IO (Either Text (Kafka a))
kafkaReader port source query@(EventQuery _ scope _ mode _ _) = case (scope, mode) of
  (TopicScope topic, _)
    | mode == ExecutionMetadata -> pure (Left "kafka-requires-business-key-correlation")
    | otherwise -> do
        state <- newIORef Nothing
        fmap Kafka <$> newReader source query (kafkaScanner port topic query state)
  _ -> pure (Left "unsupported-event-scope")

kafkaObservation :: SourceId -> EventQuery a -> Either HandlerBuildError (Handler (Kafka a) (EventEvidence a))
kafkaObservation label query@(EventQuery _ scope _ mode _ _) = case scope of
  TopicScope _
    | mode == ExecutionMetadata -> Left ExecutionMetadataUnsupported
    | otherwise -> Right (focus (\(Kafka reader) -> reader) (readerHandler label query))
  _ -> Left (UnsupportedEventScope (scopeKind scope))

observeKafka :: CallContext -> Kafka a -> IO (ObservationOutcome (EventEvidence a))
observeKafka call (Kafka reader) = observeEvents call reader

-- | One fresh read per partition from its baseline offset to its end on every
-- poll. Membership starts at the committed-visible baseline offsets, so no
-- identities are excluded and producer timestamps never decide membership.
kafkaScanner :: KafkaPort -> Text -> EventQuery a -> IORef (Maybe TopicState) -> Scanner
kafkaScanner port topic (EventQuery (Limits pageSize pages _) _ _ mode _ _) state = Scanner baselineOffsets finite
  where
    perPartition = fromIntegral pageSize * pages
    guarded (Clock _ _ _ bound) deadline action = maybe (Left "kafka-source-deadline") id <$> bound deadline action
    failure = \case
      KafkaTopicMissing -> "kafka-topic-missing"
      KafkaUnavailable -> "kafka-source-unavailable"
      KafkaDeadline -> "kafka-source-deadline"
    partitionsOf clock deadline =
      topicPartitions port clock deadline topic >>= \case
        Left err -> pure (Left (failure err))
        Right found -> do
          let selected = Set.fromList found
          modifyIORef' state (fmap (\current@(TopicState starts _ lost _) -> current {historyLost = lost || selected /= Map.keysSet starts}))
          pure $ if Set.size selected > maxPartitions then Left "kafka-partition-limit" else Right selected
    watermarks clock deadline partition =
      (either (Left . failure) Right <$> partitionWatermarks port clock deadline topic partition) `andThen` \mark -> do
        -- Persist a loss as soon as its watermark is observed, even when a
        -- later partition read fails or exhausts its deadline.
        modifyIORef' state . fmap $ \current@(TopicState starts ends lost lowLost) ->
          let start = Map.findWithDefault 0 partition starts
              lowGone = lowOffset mark > start
              rewound = visibleEndOffset mark < Map.findWithDefault start partition ends
           in current
                { historyLost = lost || lowGone || rewound,
                  lowWatermarkLost = lowLost || lowGone,
                  observedEnds = Map.insertWith max partition (visibleEndOffset mark) ends
                }
        pure (Right mark)
    baselineOffsets clock deadline =
      guarded clock deadline $
        partitionsOf clock deadline `andThen` \found ->
          collect (Set.toList found) (\partition -> fmap (partition,) <$> watermarks clock deadline partition) `andThen` \marks ->
            partitionsOf clock deadline `andThen` \again ->
              if again /= found
                then pure (Left "kafka-partitions-unstable")
                else do
                  let starts = Map.fromList [(partition, visibleEndOffset mark) | (partition, mark) <- marks]
                  writeIORef state (Just (TopicState starts starts False False))
                  token <- Text.pack . show . hashUnique <$> newUnique
                  pure (Right (Set.empty, token <> ":" <> Text.intercalate "," [Text.pack (show partition <> "@" <> show offset) | (partition, offset) <- Map.toList starts]))
    finite clock deadline =
      readIORef state >>= \case
        Nothing -> pure (Left "event-correlation-or-baseline-mismatch")
        Just (TopicState starts ends lost lowLost) ->
          guarded clock deadline $
            partitionsOf clock deadline `andThen` \before ->
              collect (Map.toList (Map.restrictKeys starts before)) (readOne clock deadline) `andThen` \partitionScans ->
                partitionsOf clock deadline `andThen` \after -> do
                  let expected = Map.keysSet starts
                      stable = before == expected && after == expected
                      lowIntact = and [lowOffset mark <= start | (_, start, marks, _) <- partitionScans, mark <- marks]
                      endsIntact = and [visibleEndOffset mark >= Map.findWithDefault start partition ends | (partition, start, marks, _) <- partitionScans, mark <- marks] && and [visibleEndOffset second >= visibleEndOffset first | (_, _, [first, second], _) <- partitionScans]
                      lost' = lost || not stable || not lowIntact || not endsIntact
                      lowLost' = lowLost || not lowIntact
                      ends' = Map.unionWith max ends (Map.fromList [(partition, maximum (map visibleEndOffset marks)) | (partition, _, marks, _) <- partitionScans])
                      finished = stable && all (\(_, _, _, PartitionRead _ ended) -> ended) partitionScans
                  writeIORef state (Just (TopicState starts ends' lost' lowLost'))
                  pure $ do
                    normalized <- traverse (\(partition, _, _, PartitionRead records _) -> traverse (normalize partition) records) partitionScans
                    let rows = concat normalized
                        untyped = length [() | StoreEvent {eventType = ""} <- rows]
                        offsets = concat [[("partition-" <> number partition <> "-baseline-offset", PublicCount (toInteger start)), ("partition-" <> number partition <> "-end-offset", PublicCount (toInteger (Map.findWithDefault start partition ends')))] | (partition, start) <- Map.toList starts]
                    pure
                      ( Scan
                          rows
                          finished
                          (not lost')
                          ( [ ("partition-count", PublicCount (toInteger (Set.size after))),
                              ("records-scanned", PublicCount (toInteger (length rows))),
                              ("records-without-event-type", PublicCount (toInteger untyped)),
                              ("records-per-partition-limit", PublicCount (toInteger perPartition)),
                              ("partitions-stable", PublicFlag stable),
                              ("low-watermark-intact", PublicFlag (not lowLost'))
                            ]
                              ++ offsets
                          )
                      )
    readOne clock deadline (partition, start) =
      watermarks clock deadline partition `andThen` \first ->
        (either (Left . failure) Right <$> readPartition port clock deadline topic partition start perPartition) `andThen` \result ->
          watermarks clock deadline partition `andThen` \second ->
            pure $
              if ordered start result
                then Right (partition, start, [first, second], result)
                else Left "kafka-offsets-invalid"
    ordered start (PartitionRead records _) =
      let offsets = map recordOffset records
       in length records <= perPartition && and (zipWith (<) (start - 1 : offsets) offsets)
    number partition = Text.pack (show partition)
    normalize partition (KafkaRecord offset timestamp key headers body) = case timestamp of
      Nothing -> Left "kafka-record-timestamp-missing"
      Just recorded ->
        Right
          StoreEvent
            { identity = number partition <> "/" <> Text.pack (show offset),
              eventType = maybe "" id (lastHeader "event-type" headers >>= utf8),
              position = offset,
              recordedAt = recorded,
              payload = maybe (Left "kafka-value-missing") (maybe (Left "kafka-value-not-json") Right . Aeson.decodeStrict) body,
              recordCorrelation = case mode of
                BusinessKeyRecordKey _ -> key >>= utf8
                BusinessKeyHeader _ name -> lastHeader (Text.encodeUtf8 name) headers >>= utf8
                _ -> Nothing,
              correlationId = Nothing,
              causationId = Nothing
            }
    utf8 bytes = either (const Nothing) Just (Text.decodeUtf8' bytes)

-- | Kafka permits duplicate header names; the last occurrence wins.
lastHeader :: ByteString -> [(ByteString, ByteString)] -> Maybe ByteString
lastHeader name headers = listToMaybe (reverse [content | (key, content) <- headers, key == name])

andThen :: IO (Either e a) -> (a -> IO (Either e b)) -> IO (Either e b)
andThen action next = action >>= either (pure . Left) next

-- | Sequence in order, stopping at the first failure.
collect :: [a] -> (a -> IO (Either e b)) -> IO (Either e [b])
collect [] _ = pure (Right [])
collect (item : rest) step = step item `andThen` \first -> fmap (first :) <$> collect rest step
