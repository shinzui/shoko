module Shoko.Adapter.Kiroku
  ( Kiroku,
    kiroku,
    kirokuObservation,
    observeKiroku,
    module Shoko.Adapter.Kiroku.Evidence,
  )
where

import Data.UUID qualified as UUID
import Data.Vector qualified as Vector
import Hasql.Session qualified as Session
import Kiroku.Store.SQL qualified as SQL
import Kiroku.Store.Types qualified as K
import Shoko.Adapter.EventStore.Internal
import Shoko.Adapter.Kiroku.Evidence
import Shoko.Binding
import Shoko.Identifier
import Shoko.Observation (ObservationOutcome)
import Shoko.Prelude

newtype Kiroku a = Kiroku (Reader a)

-- | Credentials, schema, public source identity, and a bounded scope/codec.
kiroku :: Text -> Text -> SourceId -> EventQuery a -> IO (Either Text (Kiroku a))
kiroku settings schema source query = fmap Kiroku <$> newSqlReader settings schema source query fetch
  where
    fetch scope cursor size = do
      events <- case scope of
        StreamScope name -> Session.statement (name, max 0 cursor, size) SQL.readStreamForwardStmt
        CategoryScope name -> Session.statement (max 0 cursor, name, size) SQL.readCategoryForwardStmt
        -- Unreachable: newSqlReader rejects topic scopes before any connection.
        TopicScope _ -> pure Vector.empty
      pure (map (convert scope) (Vector.toList events))
    convert scope (K.RecordedEvent (K.EventId key) (K.EventType tag) (K.StreamVersion version) (K.GlobalPosition global) _ _ body _ causation execution timestamp) =
      StoreEvent (UUID.toText key) tag (case scope of StreamScope _ -> version; _ -> global) timestamp (Right body) Nothing (UUID.toText <$> execution) (UUID.toText <$> causation)

kirokuObservation :: SourceId -> EventQuery a -> Either HandlerBuildError (Handler (Kiroku a) (EventEvidence a))
kirokuObservation label query = focus (\(Kiroku reader) -> reader) (readerHandler label query) <$ sqlHandlerSupport query

observeKiroku :: CallContext -> Kiroku a -> IO (ObservationOutcome (EventEvidence a))
observeKiroku call (Kiroku reader) = observeEvents call reader
