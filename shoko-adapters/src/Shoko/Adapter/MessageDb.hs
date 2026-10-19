{-# LANGUAGE MultilineStrings #-}

module Shoko.Adapter.MessageDb
  ( MessageDb,
    messageDb,
    messageDbObservation,
    observeMessageDb,
    module Shoko.Adapter.MessageDb.Evidence,
  )
where

import Data.Aeson (Value (..))
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Functor.Contravariant (contramap)
import Data.UUID qualified as UUID
import Hasql.Decoders qualified as D
import Hasql.Encoders qualified as E
import Hasql.Session qualified as Session
import Hasql.Statement (preparable)
import Shoko.Adapter.EventStore.Internal
import Shoko.Adapter.MessageDb.Evidence
import Shoko.Binding
import Shoko.Identifier
import Shoko.Observation (ObservationOutcome)
import Shoko.Prelude

newtype MessageDb a = MessageDb (Reader a)

-- | Thin read-only bridge to Message DB 1.3.0's public server functions.
-- Correlation is checked against decoded business keys, never the server's
-- category-only correlationStreamName filter. sql_condition is never enabled.
messageDb :: Text -> SourceId -> EventQuery a -> IO (Either Text (MessageDb a))
messageDb settings source query@(EventQuery _ _ _ mode _ _)
  | mode == ExecutionMetadata = pure (Left "message-db-requires-business-key-correlation")
  | otherwise = fmap MessageDb <$> newReader settings "message_store" source query fetch
  where
    fetch scope cursor size = Session.statement (scopeName scope, cursor + 1, fromIntegral size) (statement scope)
    scopeName (StreamScope name) = name
    scopeName (CategoryScope name) = name
    statement scope = preparable (sql scope) params (D.rowList row)
    params =
      contramap (\(name, _, _) -> name) (E.param (E.nonNullable E.text))
        <> contramap (\(_, cursor, _) -> cursor) (E.param (E.nonNullable E.int8))
        <> contramap (\(_, _, size) -> size) (E.param (E.nonNullable E.int8))
    sql scope =
      "SELECT id::text, type::text, "
        <> (case scope of StreamScope _ -> "position"; CategoryScope _ -> "global_position")
        <> "::bigint, time AT TIME ZONE 'UTC', data::jsonb, metadata::jsonb FROM "
        <> (case scope of StreamScope _ -> "get_stream_messages($1::varchar, $2, $3, NULL)"; CategoryScope _ -> "get_category_messages($1::varchar, $2, $3, NULL, NULL, NULL, NULL)")
    row =
      make
        <$> D.column (D.nonNullable D.text)
        <*> D.column (D.nonNullable D.text)
        <*> D.column (D.nonNullable D.int8)
        <*> D.column (D.nonNullable D.timestamptz)
        <*> D.column (D.nonNullable D.jsonb)
        <*> D.column (D.nullable D.jsonb)
    make key tag pos timestamp body metadata = StoreEvent key tag pos timestamp body Nothing (metadata >>= cause)
    cause (Object fields) = case KeyMap.lookup "causationMessageId" fields of
      Just (String value) -> UUID.toText <$> UUID.fromText value
      _ -> Nothing
    cause _ = Nothing

messageDbObservation :: SourceId -> EventQuery a -> Either HandlerBuildError (Handler (MessageDb a) (EventEvidence a))
messageDbObservation label query@(EventQuery _ _ _ mode _ _)
  | mode == ExecutionMetadata = Left ExecutionMetadataUnsupported
  | otherwise = Right (focus (\(MessageDb reader) -> reader) (readerHandler label query))

observeMessageDb :: CallContext -> MessageDb a -> IO (ObservationOutcome (EventEvidence a))
observeMessageDb call (MessageDb reader) = observeEvents call reader
