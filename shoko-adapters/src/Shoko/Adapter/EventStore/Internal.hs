{-# LANGUAGE RankNTypes #-}

module Shoko.Adapter.EventStore.Internal where

import Control.Exception (bracket)
import Data.Aeson (Value (..))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.IORef
import Data.Int (Int32, Int64)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as Text
import Data.Time (UTCTime)
import Data.UUID qualified as UUID
import Data.Unique (hashUnique, newUnique)
import Hasql.Connection qualified as Connection
import Hasql.Connection.Settings qualified as Settings
import Hasql.Decoders qualified as D
import Hasql.Encoders qualified as E
import Hasql.Session qualified as Session
import Hasql.Statement (unpreparable)
import PostgresqlConnectionString qualified as ConnectionString
import Shoko.Adapter.Postgres.Query (identifier)
import Shoko.Binding
import Shoko.Clock
import Shoko.Correlation
import Shoko.Environment (Capability (ReadEvents), milliseconds)
import Shoko.Identifier
import Shoko.Observation hiding (matches)
import Shoko.Prelude

data EventScope = StreamScope !Text | CategoryScope !Text | TopicScope !Text
  deriving stock (Eq, Show, Generic)

streamScope :: Text -> Either Text EventScope
streamScope name
  | name /= "" && Text.length name <= 255 && name /= "$all" = Right (StreamScope name)
  | otherwise = Left "invalid-event-stream-scope"

categoryScope :: Text -> Either Text EventScope
categoryScope name
  | name /= "" && Text.length name <= 255 && not (Text.any (== '-') name) && name /= "$all" = Right (CategoryScope name)
  | otherwise = Left "invalid-event-category-scope"

-- | A Kafka topic name. Names starting with @__@ are broker-internal topics.
topicScope :: Text -> Either Text EventScope
topicScope name
  | Text.length name >= 1 && Text.length name <= 249 && Text.all allowed name && name `notElem` [".", ".."] && not ("__" `Text.isPrefixOf` name) = Right (TopicScope name)
  | otherwise = Left "invalid-event-topic-scope"
  where
    allowed c = isAsciiLower c || isAsciiUpper c || isDigit c || c `elem` ['.', '_', '-']

scopeKind :: EventScope -> Text
scopeKind = \case
  StreamScope _ -> "stream"
  CategoryScope _ -> "category"
  TopicScope _ -> "topic"

data Limits = Limits !Int32 !Int !Int
  deriving stock (Eq, Show, Generic)

-- | Page size, page count, and per-request budget in milliseconds.
limits :: Int -> Int -> Int -> Either Text Limits
limits pageSize pages budget
  | pageSize > 0 && pageSize <= 1000 && pages > 0 && pages <= 1000 && pageSize * pages <= 100000 && budget > 0 && budget <= 60000 = Right (Limits (fromIntegral pageSize) pages budget)
  | otherwise = Left "invalid-event-read-limits"

-- | Business keys come from a payload field, a record key, or a named record
-- header. Record keys and headers exist only for Kafka topics.
data CorrelationMode
  = BusinessKeyField !BusinessKeyName
  | BusinessKeyRecordKey !BusinessKeyName
  | BusinessKeyHeader !BusinessKeyName !Text
  | ExecutionMetadata
  deriving stock (Eq, Show, Generic)

correlationSourceKind :: CorrelationMode -> Text
correlationSourceKind = \case
  BusinessKeyField _ -> "payload-field"
  BusinessKeyRecordKey _ -> "record-key"
  BusinessKeyHeader _ _ -> "record-header"
  ExecutionMetadata -> "execution-metadata"

-- | Complete history requires an owner-backed exclusion of deletion,
-- truncation, and rewriting of this scope for the entire finite run.
-- Unverified history still supplies witnesses, never complete negative coverage.
data HistoryPolicy = AppendOnlyDuringRun | UnverifiedHistory
  deriving stock (Eq, Show, Generic)

data EventQuery a = EventQuery !Limits !EventScope !HistoryPolicy !CorrelationMode !Text !(Value -> Either Text a)

eventQuery :: Limits -> EventScope -> HistoryPolicy -> CorrelationMode -> Text -> (Value -> Either Text a) -> Either Text (EventQuery a)
eventQuery bounded scope policy mode eventType decode = do
  _ <- case scope of StreamScope name -> streamScope name; CategoryScope name -> categoryScope name; TopicScope name -> topicScope name
  if eventType == "" || emptySource mode
    then Left "invalid-event-query"
    else Right (EventQuery bounded scope policy mode eventType decode)
  where
    emptySource = \case
      BusinessKeyField key -> businessKeyNameText key == ""
      BusinessKeyRecordKey key -> businessKeyNameText key == ""
      BusinessKeyHeader key header -> businessKeyNameText key == "" || header == ""
      ExecutionMetadata -> False

data EventEvidence a = EventEvidence
  { position :: !Int64,
    recordedAt :: !UTCTime,
    causation :: !(Maybe Text),
    value :: !a
  }
  deriving stock (Generic)

-- | A normalized record. A payload that is not JSON fails an observation only
-- when the record is a correlated candidate. The record correlation is the
-- selected record key or header text, held in memory and never rendered.
data StoreEvent = StoreEvent
  { identity :: !Text,
    eventType :: !Text,
    position :: !Int64,
    recordedAt :: !UTCTime,
    payload :: !(Either Text Value),
    recordCorrelation :: !(Maybe Text),
    correlationId :: !(Maybe Text),
    causationId :: !(Maybe Text)
  }
  deriving stock (Generic)

-- | One finite read of the whole scope. 'scannedAll' is false when a limit
-- stopped the read; 'historyIntact' is false when the source itself reported
-- deletion. Details are safe public, store-specific facts.
data Scan = Scan
  { events :: ![StoreEvent],
    scannedAll :: !Bool,
    historyIntact :: !Bool,
    details :: ![(Text, PublicValue)]
  }

-- | Store-specific finite reads under one absolute deadline. The baseline
-- returns the identities excluded as history and an opaque diagnostic token.
data Scanner = Scanner
  { baselineScan :: Clock -> MonotonicTime -> IO (Either Text (Set.Set Text, Text)),
    scan :: Clock -> MonotonicTime -> IO (Either Text Scan)
  }

type Fetch = EventScope -> Int64 -> Int32 -> Session.Session [StoreEvent]

data ReaderState = ReaderState
  { baseline :: !(Maybe Baseline),
    excluded :: !(Set.Set Text),
    seen :: !(Set.Set Text),
    timely :: !(Map.Map (Text, MonotonicTime) (Set.Set Text))
  }

-- | A fresh reader belongs to one finite run. No subscriptions are started.
data Reader a = Reader !SourceId !(EventQuery a) !Scanner !(IORef ReaderState)

newReader :: SourceId -> EventQuery a -> Scanner -> IO (Either Text (Reader a))
newReader source query scanner
  | Text.null (sourceIdText source) = pure (Left "invalid-event-reader")
  | otherwise = Right . Reader source query scanner <$> newIORef (ReaderState Nothing Set.empty Set.empty Map.empty)

-- | SQL stores read streams and categories with payload-field or execution
-- correlation; topics and record correlation are never reinterpreted.
sqlQuerySupport :: EventQuery a -> Either Text ()
sqlQuerySupport (EventQuery _ scope _ mode _ _) = case (scope, mode) of
  (TopicScope _, _) -> Left "unsupported-event-scope"
  (_, BusinessKeyRecordKey _) -> Left "unsupported-correlation-source"
  (_, BusinessKeyHeader _ _) -> Left "unsupported-correlation-source"
  _ -> Right ()

sqlHandlerSupport :: EventQuery a -> Either HandlerBuildError ()
sqlHandlerSupport (EventQuery _ scope _ mode _ _) = case (scope, mode) of
  (TopicScope _, _) -> Left (UnsupportedEventScope (scopeKind scope))
  (_, BusinessKeyRecordKey _) -> Left (UnsupportedCorrelationSource (correlationSourceKind mode))
  (_, BusinessKeyHeader _ _) -> Left (UnsupportedCorrelationSource (correlationSourceKind mode))
  _ -> Right ()

newSqlReader :: Text -> Text -> SourceId -> EventQuery a -> Fetch -> IO (Either Text (Reader a))
newSqlReader settings schema source query fetch = case (sqlQuerySupport query, identifier schema) of
  (Left err, _) -> pure (Left err)
  (_, Left _) -> pure (Left "invalid-event-schema")
  _ | Left _ <- ConnectionString.parse settings -> pure (Left "invalid-event-connection-settings")
  _
    | Text.null (Text.strip settings) -> pure (Left "invalid-event-reader")
    | otherwise -> newReader source query (sqlScanner settings schema query fetch)

queryRequirement :: EventQuery a -> CorrelationRequirement
queryRequirement (EventQuery _ _ _ mode _ _) = case mode of
  BusinessKeyField key -> RequiresBusinessKey key
  BusinessKeyRecordKey key -> RequiresBusinessKey key
  BusinessKeyHeader key _ -> RequiresBusinessKey key
  ExecutionMetadata -> RequiresExecutionId

sameQuery :: EventQuery a -> EventQuery b -> Bool
sameQuery (EventQuery limits' scope history mode tag _) (EventQuery limits2 scope2 history2 mode2 tag2 _) =
  (limits', scope, history, mode, tag) == (limits2, scope2, history2, mode2, tag2)

-- Decoder functions cannot be compared; use the same query for allocation and handler construction.
readerHandler :: SourceId -> EventQuery a -> Handler (Reader a) (EventEvidence a)
readerHandler label query = observationHandler (requiring [ReadEvents] noRequirements) (queryRequirement query) owned perform
  where
    compatible (Reader actual allocated _ _) = label == actual && sameQuery query allocated
    declared (Reader source _ scanner state) = Reader source query scanner state
    owned = newSource label DurableHistory $ \reader clock ->
      if compatible reader then capture (declared reader) clock label else pure (Left "event-descriptor-mismatch")
    perform reader context =
      if compatible reader then observeEvents context (declared reader) else pure (ObservationUnavailable "event-descriptor-mismatch")

-- | The whole read shares one deadline: the request deadline or the query budget.
scanDeadline :: EventQuery a -> MonotonicTime -> MonotonicTime -> MonotonicTime
scanDeadline (EventQuery (Limits _ _ budget) _ _ _ _ _) started end =
  min end (addDuration started (either (const (error "validated event budget")) id (milliseconds budget)))

-- | Re-scan the entire bounded scope in one repeatable-read snapshot. A global
-- high-water mark cannot skip a delayed lower-position commit in another stream.
sqlScanner :: Text -> Text -> EventQuery a -> Fetch -> Scanner
sqlScanner settings schema (EventQuery (Limits pageSize pages _) scope _ _ _ _) fetch = Scanner baselineIds finite
  where
    baselineIds clock deadline =
      snapshot clock deadline >>= \case
        Left err -> pure (Left err)
        Right (_, False) -> pure (Left "event-baseline-scan-limit")
        Right (rows, True) -> do
          token <- Text.pack . show . hashUnique <$> newUnique
          pure (Right (Set.fromList [key | StoreEvent {identity = key} <- rows], token))
    finite clock deadline =
      fmap
        ( \(rows, complete) ->
            let scannedPositions = [pos | StoreEvent {position = pos} <- rows]
                scanBounds = case scannedPositions of
                  [] -> []
                  first : _ -> [("scan-from-position", PublicCount (toInteger first)), ("scan-through-position", PublicCount (toInteger (last scannedPositions)))]
             in Scan rows complete True scanBounds
        )
        <$> snapshot clock deadline
    snapshot (Clock now _ _ bound) deadline = do
      answer <- bound deadline $
        bracket (Connection.acquire (Settings.connectionString settings)) (either (const (pure ())) Connection.release) $ \case
          Left _ -> pure (Left "event-source-unavailable")
          Right connection -> do
            current <- now
            result <- Connection.use connection $ do
              Session.script "BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY"
              _ <- Session.statement (Text.pack (show (max 1 ((differenceMicros deadline current) `div` 1000)))) (setting "statement_timeout")
              _ <- Session.statement ("\"" <> schema <> "\", pg_catalog") (setting "search_path")
              rows <- pageThrough pages (-1) []
              Session.script "COMMIT"
              pure rows
            pure (either (const (Left "event-source-unavailable")) id result)
      pure (maybe (Left "event-source-deadline") id answer)
    setting key = unpreparable ("SELECT set_config('" <> key <> "', $1, true)") (E.param (E.nonNullable E.text)) (D.singleRow (D.column (D.nonNullable D.text)))
    pageThrough remaining cursor acc = do
      rows <- fetch scope cursor pageSize
      let positions = [pos | StoreEvent {position = pos} <- rows]
          progress = and (zipWith (<) (cursor : positions) positions)
      if not progress
        then pure (Left "event-cursor-did-not-advance")
        else case reverse positions of
          [] -> pure (Right (concat (reverse acc), True))
          latest : _
            | length rows < fromIntegral pageSize -> pure (Right (concat (reverse (rows : acc)), True))
            | remaining <= 1 || latest == maxBound -> pure (Right (concat (reverse (rows : acc)), False))
            | otherwise -> pageThrough (remaining - 1) latest (rows : acc)

capture :: Reader a -> Clock -> SourceId -> IO (Either Text Baseline)
capture (Reader source query scanner state) clock@(Clock now _ _ _) requested
  | source /= requested = pure (Left "event-baseline-source-mismatch")
  | otherwise = do
      start <- now
      -- The baseline has a constant budget independent of the request deadline.
      baselineScan scanner clock (scanDeadline query start (addDuration start (either (const (error "constant event budget")) id (milliseconds 60000)))) >>= \case
        Left err -> pure (Left err)
        Right (ids, token) -> do
          tick <- now
          let captured = Baseline source tick (Just token)
          writeIORef state (ReaderState (Just captured) ids ids Map.empty)
          pure (Right captured)

observeEvents :: CallContext -> Reader a -> IO (ObservationOutcome (EventEvidence a))
observeEvents context (Reader source query@(EventQuery (Limits pageSize pageLimit _) scope historyPolicy mode wanted decode) scanner state) = do
  let end = requestDeadline context
      supplied = sourceBaseline context
      selected = correlation context
      cutoff = evidenceUntil context
      clock@(Clock now _ _ _) = callClock context
  ReaderState captured excluded seen timely <- readIORef state
  case (captured, supplied, selected) of
    (Just expected@(Baseline _ from _), Just actual, Just selectedCorrelation)
      | expected == actual && supports mode selectedCorrelation -> do
          -- A response finishing after the cutoff does not prove its source
          -- snapshot was taken after it. This request start is a conservative
          -- lower bound for snapshot visibility, including connection setup.
          started <- now
          scan scanner clock (scanDeadline query started end) >>= \case
            Left err -> pure (ObservationUnavailable err)
            Right (Scan rows scannedAll historyIntact storeDetails) -> do
              finished <- now
              let ids = Set.fromList [key | StoreEvent {identity = key} <- rows]
                  fresh = [event | event@StoreEvent {identity = key} <- rows, Set.notMember key excluded]
                  decoded = traverse (select selectedCorrelation) fresh
                  cacheKey = (Text.pack (show selectedCorrelation), cutoff)
                  known = Map.findWithDefault Set.empty cacheKey timely
              case decoded of
                Left _ -> pure (ObservationUnavailable "event-payload-or-correlation-undecodable")
                Right candidates -> do
                  let matches = concat candidates
                      matchingIds = Set.fromList (map fst matches)
                      timelyIds = if finished <= cutoff then Set.union known matchingIds else known
                      ambiguous = not (Set.isSubsetOf matchingIds timelyIds)
                      intact = Set.isSubsetOf seen ids
                      complete = historyPolicy == AppendOnlyDuringRun && scannedAll && intact && historyIntact && not ambiguous
                      through = min started cutoff
                      occurrences = [Occurrence (Just (sourceIdText source <> ":" <> key)) value | (key, value) <- matches, Set.member key timelyIds]
                      coordinates =
                        concat
                          [ [("event-" <> key <> "-position", PublicCount (toInteger pos)), ("event-" <> key <> "-recorded-at", PublicChoice (Text.pack (show timestamp)))]
                              ++ maybe [] (\cause -> [("event-" <> key <> "-causation", PublicChoice cause)]) causation
                          | (key, EventEvidence pos timestamp causation _) <- matches,
                            Set.member key timelyIds
                          ]
                      filters =
                        [ ("scope-kind", PublicChoice (scopeKind scope)),
                          ("event-type", PublicChoice wanted),
                          ("correlation-filter", PublicChoice (correlationFilter mode)),
                          ("page-size", PublicCount (toInteger pageSize)),
                          ("page-limit", PublicCount (toInteger pageLimit))
                        ]
                  atomicModifyIORef' state $ \(ReaderState base oldExcluded oldSeen oldTimely) ->
                    (ReaderState base oldExcluded (if scannedAll then Set.union oldSeen ids else oldSeen) (Map.insertWith Set.union cacheKey timelyIds oldTimely), ())
                  pure
                    ( ObservedWithDetails
                        occurrences
                        (Coverage DurableHistory from through complete)
                        ([("scan-complete", PublicFlag scannedAll), ("history-intact", PublicFlag (intact && historyIntact)), ("append-only-assured", PublicFlag (historyPolicy == AppendOnlyDuringRun)), ("ambiguous-cutoff", PublicFlag ambiguous), ("scanned-count", PublicCount (toInteger (length rows)))] ++ filters ++ storeDetails ++ coordinates)
                    )
    _ -> pure (ObservationUnavailable "event-correlation-or-baseline-mismatch")
  where
    select selectedCorrelation (StoreEvent key eventType pos timestamp body recorded execution causation)
      | eventType /= wanted = Right []
      | otherwise = do
          actual <- case mode of
            BusinessKeyField field -> case body of
              Right (Object fields) -> case KeyMap.lookup (Key.fromText (businessKeyNameText field)) fields of
                Just (String value) -> Right value
                _ -> Left "missing-business-key"
              _ -> Left "missing-business-key"
            BusinessKeyRecordKey _ -> maybe (Left "missing-business-key") Right recorded
            BusinessKeyHeader _ _ -> maybe (Left "missing-business-key") Right recorded
            ExecutionMetadata -> maybe (Left "missing-execution-id") Right execution
          let expected = case selectedCorrelation of ByBusinessKey _ value -> value; ByExecutionId value -> maybe value UUID.toText (UUID.fromText value)
          if actual /= expected
            then Right []
            else do
              value <- body >>= decode
              pure [(key, EventEvidence pos timestamp causation value)]
    -- Header names are configuration that may be private; only the source kind is public.
    correlationFilter = \case
      BusinessKeyField field -> "business-key:" <> businessKeyNameText field
      BusinessKeyRecordKey field -> "record-key:" <> businessKeyNameText field
      BusinessKeyHeader field _ -> "record-header:" <> businessKeyNameText field
      ExecutionMetadata -> "exact-execution-metadata"
    supports (BusinessKeyField field) (ByBusinessKey key value) = field == key && value /= ""
    supports (BusinessKeyRecordKey field) (ByBusinessKey key value) = field == key && value /= ""
    supports (BusinessKeyHeader field _) (ByBusinessKey key value) = field == key && value /= ""
    supports ExecutionMetadata (ByExecutionId value) = case UUID.fromText value of Just _ -> True; Nothing -> False
    supports _ _ = False
