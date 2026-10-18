module Shoko.Correlation
  ( CorrelationStrategy (..),
    CorrelationPlan (..),
    Correlation (..),
    correlationStrategy,
    correlationDependencies,
  )
where

import Shoko.Action
import Shoko.Prelude

data CorrelationStrategy = BusinessKey | ExecutionId
  deriving stock (Eq, Ord, Show, Generic)

data CorrelationPlan = BusinessKeyFrom !Text !(Input Text) | PropagatedExecutionId

data Correlation = ByBusinessKey !Text !Text | ByExecutionId !Text
  deriving stock (Eq, Show, Generic)

correlationStrategy :: CorrelationPlan -> CorrelationStrategy
correlationStrategy (BusinessKeyFrom _ _) = BusinessKey
correlationStrategy PropagatedExecutionId = ExecutionId

correlationDependencies :: CorrelationPlan -> [Text]
correlationDependencies (BusinessKeyFrom _ value) = inputDependencies value
correlationDependencies PropagatedExecutionId = []
