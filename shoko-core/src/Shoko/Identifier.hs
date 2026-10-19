module Shoko.Identifier
  ( CorrelationAlias (..),
    BusinessKeyName (..),
    CorrelationId (..),
    SourceId (..),
    correlationAliasText,
    businessKeyNameText,
    correlationIdText,
    sourceIdText,
  )
where

import Shoko.Prelude

newtype CorrelationAlias = CorrelationAlias Text deriving stock (Eq, Ord, Show, Generic)

newtype BusinessKeyName = BusinessKeyName Text deriving stock (Eq, Ord, Show, Generic)

newtype CorrelationId = CorrelationId Text deriving stock (Eq, Ord, Show, Generic)

newtype SourceId = SourceId Text deriving stock (Eq, Ord, Show, Generic)

correlationAliasText :: CorrelationAlias -> Text
correlationAliasText (CorrelationAlias value) = value

businessKeyNameText :: BusinessKeyName -> Text
businessKeyNameText (BusinessKeyName value) = value

correlationIdText :: CorrelationId -> Text
correlationIdText (CorrelationId value) = value

sourceIdText :: SourceId -> Text
sourceIdText (SourceId value) = value
