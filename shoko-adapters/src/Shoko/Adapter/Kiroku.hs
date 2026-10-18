module Shoko.Adapter.Kiroku
  ( Kiroku,
    kiroku,
    kirokuContract,
    kirokuBaseline,
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
import Shoko.Binding (BindingContract, CallContext)
import Shoko.Clock (Clock)
import Shoko.Observation (Baseline, ObservationOutcome)
import Shoko.Prelude

newtype Kiroku a = Kiroku (Reader a)

-- | Credentials, schema, public source identity, and a bounded scope/codec.
kiroku :: Text -> Text -> Text -> EventQuery a -> IO (Either Text (Kiroku a))
kiroku settings schema source query = fmap Kiroku <$> newReader settings schema source query fetch
  where
    fetch scope cursor size = do
      events <- case scope of
        StreamScope name -> Session.statement (name, max 0 cursor, size) SQL.readStreamForwardStmt
        CategoryScope name -> Session.statement (max 0 cursor, name, size) SQL.readCategoryForwardStmt
      pure (map (convert scope) (Vector.toList events))
    convert scope (K.RecordedEvent (K.EventId key) (K.EventType tag) (K.StreamVersion version) (K.GlobalPosition global) _ _ body _ causation execution timestamp) =
      StoreEvent (UUID.toText key) tag (case scope of StreamScope _ -> version; CategoryScope _ -> global) timestamp body (UUID.toText <$> execution) (UUID.toText <$> causation)

-- | Pure metadata for inspection/policy resolution, before reader allocation.
kirokuContract :: Text -> EventQuery a -> BindingContract
kirokuContract = queryContract

kirokuBaseline :: Kiroku a -> Clock -> Text -> IO (Either Text Baseline)
kirokuBaseline (Kiroku reader) = capture reader

observeKiroku :: CallContext -> Kiroku a -> IO (ObservationOutcome (EventEvidence a))
observeKiroku call (Kiroku reader) = observeEvents call reader
