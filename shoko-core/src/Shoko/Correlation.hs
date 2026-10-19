module Shoko.Correlation
  ( CorrelationStrategy (..),
    CorrelationPlan (..),
    Correlation (..),
    correlationStrategy,
    correlationDependencies,
    businessKeyFromResult,
  )
where

import Shoko.Action
import Shoko.Identifier
import Shoko.Internal.Reference (Input (Reference), Ref (Ref))
import Shoko.Prelude

data CorrelationStrategy = BusinessKey | ExecutionId
  deriving stock (Eq, Ord, Show, Generic)

data CorrelationPlan = BusinessKeyFrom !BusinessKeyName !(Input Text) | PropagatedExecutionId

data Correlation = ByBusinessKey !BusinessKeyName !Text | ByExecutionId !Text
  deriving stock (Eq, Show, Generic)

correlationStrategy :: CorrelationPlan -> CorrelationStrategy
correlationStrategy (BusinessKeyFrom _ _) = BusinessKey
correlationStrategy PropagatedExecutionId = ExecutionId

correlationDependencies :: CorrelationPlan -> [Text]
correlationDependencies (BusinessKeyFrom _ value) = inputDependencies value
correlationDependencies PropagatedExecutionId = []

-- | Select a named action's Text identity. Resolution validates the node exists;
-- runtime lookup is checked by Typeable and never broadens a failed query.
businessKeyFromResult :: BusinessKeyName -> Text -> CorrelationPlan
businessKeyFromResult key node = BusinessKeyFrom key (Reference (Ref node))
