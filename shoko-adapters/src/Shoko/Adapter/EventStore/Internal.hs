{-# LANGUAGE RankNTypes #-}

module Shoko.Adapter.EventStore.Internal where

import Control.Exception (bracket)
import Data.Aeson (Value (..))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
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

data EventScope = StreamScope !Text | CategoryScope !Text
  deriving stock (Eq, Show, Generic)

streamScope :: Text -> Either Text EventScope
streamScope name
  | name /= "" && Text.length name <= 255 && name /= "$all" = Right (StreamScope name)
  | otherwise = Left "invalid-event-stream-scope"

categoryScope :: Text -> Either Text EventScope
categoryScope name
  | name /= "" && Text.length name <= 255 && not (Text.any (== '-') name) && name /= "$all" = Right (CategoryScope name)
  | otherwise = Left "invalid-event-category-scope"

data Limits = Limits !Int32 !Int !Int
  deriving stock (Eq, Show, Generic)

-- | Page size, page count, and per-request budget in milliseconds.
limits :: Int -> Int -> Int -> Either Text Limits
limits pageSize pages budget
  | pageSize > 0 && pageSize <= 1000 && pages > 0 && pages <= 1000 && pageSize * pages <= 100000 && budget > 0 && budget <= 60000 = Right (Limits (fromIntegral pageSize) pages budget)
  | otherwise = Left "invalid-event-read-limits"

data CorrelationMode = BusinessKeyField !BusinessKeyName | ExecutionMetadata
  deriving stock (Eq, Show, Generic)

-- | Complete history requires an owner-backed exclusion of deletion,
-- truncation, and rewriting of this scope for the entire finite run.
-- Unverified history still supplies witnesses, never complete negative coverage.
data HistoryPolicy = AppendOnlyDuringRun | UnverifiedHistory
  deriving stock (Eq, Show, Generic)

data EventQuery a = EventQuery !Limits !EventScope !HistoryPolicy !CorrelationMode !Text !(Value -> Either Text a)

eventQuery :: Limits -> EventScope -> HistoryPolicy -> CorrelationMode -> Text -> (Value -> Either Text a) -> Either Text (EventQuery a)
eventQuery bounded scope policy mode eventType decode = do
  _ <- case scope of StreamScope name -> streamScope name; CategoryScope name -> categoryScope name
  if eventType == "" || mode == BusinessKeyField (BusinessKeyName "")
    then Left "invalid-event-query"
    else Right (EventQuery bounded scope policy mode eventType decode)

data EventEvidence a = EventEvidence
  { position :: !Int64,
    recordedAt :: !UTCTime,
    causation :: !(Maybe Text),
    value :: !a
  }
  deriving stock (Generic)

data StoreEvent = StoreEvent
  { identity :: !Text,
    eventType :: !Text,
    position :: !Int64,
    recordedAt :: !UTCTime,
    payload :: !Value,
    correlationId :: !(Maybe Text),
    causationId :: !(Maybe Text)
  }
  deriving stock (Generic)

type Fetch = EventScope -> Int64 -> Int32 -> Session.Session [StoreEvent]

data ReaderState = ReaderState
  { baseline :: !(Maybe Baseline),
    excluded :: !(Set.Set Text),
    seen :: !(Set.Set Text),
    timely :: !(Map.Map (Text, MonotonicTime) (Set.Set Text))
  }

-- | A fresh reader belongs to one finite run. No subscriptions are started.
data Reader a = Reader !Text !Text !SourceId !(EventQuery a) !Fetch !(IORef ReaderState)

newReader :: Text -> Text -> SourceId -> EventQuery a -> Fetch -> IO (Either Text (Reader a))
newReader settings schema source query fetch = case identifier schema of
  Left _ -> pure (Left "invalid-event-schema")
  Right _ | Left _ <- ConnectionString.parse settings -> pure (Left "invalid-event-connection-settings")
  Right _
    | Text.null (Text.strip settings) || Text.null (sourceIdText source) -> pure (Left "invalid-event-reader")
    | otherwise -> Right . Reader settings schema source query fetch <$> newIORef (ReaderState Nothing Set.empty Set.empty Map.empty)

queryRequirement :: EventQuery a -> CorrelationRequirement
queryRequirement (EventQuery _ _ _ mode _ _) = case mode of
  BusinessKeyField key -> RequiresBusinessKey key
  ExecutionMetadata -> RequiresExecutionId

sameQuery :: EventQuery a -> EventQuery b -> Bool
sameQuery (EventQuery limits' scope history mode tag _) (EventQuery limits2 scope2 history2 mode2 tag2 _) =
  (limits', scope, history, mode, tag) == (limits2, scope2, history2, mode2, tag2)

-- Decoder functions cannot be compared; use the same query for allocation and handler construction.
readerHandler :: SourceId -> EventQuery a -> Handler (Reader a) (EventEvidence a)
readerHandler label query = observationHandler (requiring [ReadEvents] noRequirements) (queryRequirement query) owned perform
  where
    compatible (Reader _ _ actual allocated _ _) = label == actual && sameQuery query allocated
    owned = newSource label DurableHistory $ \reader clock ->
      if compatible reader then capture reader clock label else pure (Left "event-descriptor-mismatch")
    perform reader context =
      if compatible reader then observeEvents context reader else pure (ObservationUnavailable "event-descriptor-mismatch")

-- | Re-scan the entire bounded scope in one repeatable-read snapshot. A global
-- high-water mark cannot skip a delayed lower-position commit in another stream.
snapshot :: Reader a -> Clock -> MonotonicTime -> IO (Either Text ([StoreEvent], Bool))
snapshot (Reader settings schema _ (EventQuery (Limits pageSize pages budget) scope _ _ _ _) fetch _) (Clock now _ _ bound) end = do
  started <- now
  let deadline = min end (addDuration started (either (const (error "validated event budget")) id (milliseconds budget)))
  answer <- bound deadline $
    bracket (Connection.acquire (Settings.connectionString settings)) (either (const (pure ())) Connection.release) $ \case
      Left _ -> pure (Left "event-source-unavailable")
      Right connection -> do
        current <- now
        result <- Connection.use connection $ do
          Session.script "BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY"
          _ <- Session.statement (Text.pack (show (max 1 ((differenceMicros deadline current) `div` 1000)))) (setting "statement_timeout")
          _ <- Session.statement ("\"" <> schema <> "\", pg_catalog") (setting "search_path")
          events <- scan pages (-1) []
          Session.script "COMMIT"
          pure events
        pure (either (const (Left "event-source-unavailable")) id result)
  pure (maybe (Left "event-source-deadline") id answer)
  where
    setting key = unpreparable ("SELECT set_config('" <> key <> "', $1, true)") (E.param (E.nonNullable E.text)) (D.singleRow (D.column (D.nonNullable D.text)))
    scan remaining cursor acc = do
      rows <- fetch scope cursor pageSize
      let positions = [pos | StoreEvent _ _ pos _ _ _ _ <- rows]
          progress = and (zipWith (<) (cursor : positions) positions)
      if not progress
        then pure (Left "event-cursor-did-not-advance")
        else case reverse positions of
          [] -> pure (Right (concat (reverse acc), True))
          latest : _
            | length rows < fromIntegral pageSize -> pure (Right (concat (reverse (rows : acc)), True))
            | remaining <= 1 || latest == maxBound -> pure (Right (concat (reverse (rows : acc)), False))
            | otherwise -> scan (remaining - 1) latest (rows : acc)

capture :: Reader a -> Clock -> SourceId -> IO (Either Text Baseline)
capture reader@(Reader _ _ source _ _ state) clock@(Clock now _ _ _) requested
  | source /= requested = pure (Left "event-baseline-source-mismatch")
  | otherwise = do
      start <- now
      snapshot reader clock (addDuration start (either (const (error "constant event budget")) id (milliseconds 60000))) >>= \case
        Left err -> pure (Left err)
        Right (_, False) -> pure (Left "event-baseline-scan-limit")
        Right (events, True) -> do
          tick <- now
          token <- Text.pack . show . hashUnique <$> newUnique
          let captured = Baseline source tick (Just token)
              ids = Set.fromList [key | StoreEvent key _ _ _ _ _ _ <- events]
          writeIORef state (ReaderState (Just captured) ids ids Map.empty)
          pure (Right captured)

observeEvents :: CallContext -> Reader a -> IO (ObservationOutcome (EventEvidence a))
observeEvents context reader@(Reader _ _ source (EventQuery (Limits pageSize pageLimit _) scope historyPolicy mode wanted decode) _ state) = do
  let end = requestDeadline context
      supplied = sourceBaseline context
      selected = correlation context
      cutoff = evidenceUntil context
      clock@(Clock now _ _ _) = callClock context
  ReaderState captured excluded seen timely <- readIORef state
  case (captured, supplied, selected) of
    (Just expected@(Baseline _ from _), Just actual, Just selectedCorrelation)
      | expected == actual && supports mode selectedCorrelation -> do
          -- A response finishing after the cutoff does not prove its database
          -- snapshot was taken after it. This request start is a conservative
          -- lower bound for snapshot visibility, including connection setup.
          started <- now
          snapshot reader clock end >>= \case
            Left err -> pure (ObservationUnavailable err)
            Right (events, scannedAll) -> do
              finished <- now
              let ids = Set.fromList [key | StoreEvent key _ _ _ _ _ _ <- events]
                  fresh = [event | event@(StoreEvent key _ _ _ _ _ _) <- events, Set.notMember key excluded]
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
                      complete = historyPolicy == AppendOnlyDuringRun && scannedAll && intact && not ambiguous
                      through = min started cutoff
                      occurrences = [Occurrence (Just (sourceIdText source <> ":" <> key)) value | (key, value) <- matches, Set.member key timelyIds]
                      coordinates =
                        concat
                          [ [("event-" <> key <> "-position", PublicCount (toInteger pos)), ("event-" <> key <> "-recorded-at", PublicChoice (Text.pack (show timestamp)))]
                              ++ maybe [] (\cause -> [("event-" <> key <> "-causation", PublicChoice cause)]) causation
                          | (key, EventEvidence pos timestamp causation _) <- matches,
                            Set.member key timelyIds
                          ]
                      scannedPositions = [pos | StoreEvent _ _ pos _ _ _ _ <- events]
                      scanBounds = case scannedPositions of
                        [] -> []
                        first : _ -> [("scan-from-position", PublicCount (toInteger first)), ("scan-through-position", PublicCount (toInteger (last scannedPositions)))]
                      filters =
                        [ ("scope-kind", PublicChoice (case scope of StreamScope _ -> "stream"; CategoryScope _ -> "category")),
                          ("event-type", PublicChoice wanted),
                          ("correlation-filter", PublicChoice (case mode of BusinessKeyField field -> "business-key:" <> businessKeyNameText field; ExecutionMetadata -> "exact-execution-metadata")),
                          ("page-size", PublicCount (toInteger pageSize)),
                          ("page-limit", PublicCount (toInteger pageLimit))
                        ]
                  atomicModifyIORef' state $ \(ReaderState base oldExcluded oldSeen oldTimely) ->
                    (ReaderState base oldExcluded (if scannedAll then Set.union oldSeen ids else oldSeen) (Map.insertWith Set.union cacheKey timelyIds oldTimely), ())
                  pure
                    ( ObservedWithDetails
                        occurrences
                        (Coverage DurableHistory from through complete)
                        ([("scan-complete", PublicFlag scannedAll), ("history-intact", PublicFlag intact), ("append-only-assured", PublicFlag (historyPolicy == AppendOnlyDuringRun)), ("ambiguous-cutoff", PublicFlag ambiguous), ("scanned-count", PublicCount (toInteger (length events)))] ++ filters ++ scanBounds ++ coordinates)
                    )
    _ -> pure (ObservationUnavailable "event-correlation-or-baseline-mismatch")
  where
    select selectedCorrelation (StoreEvent key eventType pos timestamp body execution causation)
      | eventType /= wanted = Right []
      | otherwise = do
          actual <- case (mode, body) of
            (BusinessKeyField field, Object fields) -> case KeyMap.lookup (Key.fromText (businessKeyNameText field)) fields of
              Just (String value) -> Right value
              _ -> Left "missing-business-key"
            (ExecutionMetadata, _) -> maybe (Left "missing-execution-id") Right execution
            _ -> Left "missing-business-key"
          let expected = case selectedCorrelation of ByBusinessKey _ value -> value; ByExecutionId value -> maybe value UUID.toText (UUID.fromText value)
          if actual /= expected
            then Right []
            else do
              value <- decode body
              pure [(key, EventEvidence pos timestamp causation value)]
    supports (BusinessKeyField field) (ByBusinessKey key value) = field == key && value /= ""
    supports ExecutionMetadata (ByExecutionId value) = case UUID.fromText value of Just _ -> True; Nothing -> False
    supports _ _ = False
