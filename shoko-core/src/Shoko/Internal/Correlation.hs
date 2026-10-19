module Shoko.Internal.Correlation where

import Shoko.Identifier
import Shoko.Internal.Reference (Input, inputDependencies)
import Shoko.Prelude

data CorrelationStrategy = BusinessKey | ExecutionId deriving stock (Eq, Ord, Show, Generic)

data Correlation = ByBusinessKey !BusinessKeyName !Text | ByExecutionId !Text deriving stock (Eq, Show, Generic)

newtype CorrelationRef = CorrelationRef CorrelationId deriving stock (Eq, Show)

correlationRefId :: CorrelationRef -> CorrelationId
correlationRefId (CorrelationRef key) = key

data CorrelationDeclaration = BusinessDeclaration !CorrelationId !BusinessKeyName !(Input Text) | ExecutionDeclaration

declarationId :: CorrelationDeclaration -> CorrelationId
declarationId (BusinessDeclaration key _ _) = key
declarationId ExecutionDeclaration = CorrelationId "execution-id"

declarationKey :: CorrelationDeclaration -> BusinessKeyName
declarationKey (BusinessDeclaration _ key _) = key
declarationKey ExecutionDeclaration = BusinessKeyName "execution-id"

declarationStrategy :: CorrelationDeclaration -> CorrelationStrategy
declarationStrategy (BusinessDeclaration _ _ _) = BusinessKey
declarationStrategy ExecutionDeclaration = ExecutionId

declarationDependencies :: CorrelationDeclaration -> [Text]
declarationDependencies (BusinessDeclaration _ _ input) = inputDependencies input
declarationDependencies ExecutionDeclaration = []

data ResolvedCorrelation = ResolvedCorrelation
  { correlationId :: !CorrelationId,
    resolvedCorrelation :: !Correlation
  }
  deriving stock (Eq, Show, Generic)
