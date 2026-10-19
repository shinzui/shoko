module Shoko.Action
  ( Ref,
    refId,
    Input,
    fromRef,
    inputDependencies,
    Vocabulary (..),
    OperationRole (..),
    OperationInfo (..),
    declareOperation,
    dependsOn,
    withSubstep,
    Action,
    accept,
    acceptedTags,
    actionOperation,
    ActionOutcome (..),
  )
where

import Data.Dynamic (Typeable)
import Data.Set (Set)
import Data.Set qualified as Set
import Shoko.Environment
import Shoko.Internal.Reference
import Shoko.Observation (PublicValue)
import Shoko.Prelude

fromRef :: (Typeable a) => Ref a -> Input a
fromRef = Reference

-- | Descriptions contain only public identifiers, never fixture/request values.
data OperationInfo = OperationInfo
  { operationId :: !Text,
    capabilities :: !(Set Capability),
    dependencies :: ![Text],
    substeps :: ![(Text, Set Capability)]
  }
  deriving stock (Eq, Show, Generic)

data OperationRole = FixtureOperation | ActionOperation | ObservationOperation
  deriving stock (Eq, Ord, Show, Enum, Bounded, Generic)

class Vocabulary op where
  describeOperation :: op a -> OperationInfo

data Action op a = Action !(Set Text) !(op a)

accept :: [Text] -> op a -> Action op a
accept tags = Action (Set.fromList tags)

acceptedTags :: Action op a -> Set Text
acceptedTags (Action tags _) = tags

actionOperation :: Action op a -> op a
actionOperation (Action _ op) = op

-- | A documented rejection is an ordinary typed value with an outcome tag.
-- Transport/decoding failures must use ActionUnavailable instead.
data ActionOutcome a
  = ActionObserved !Text !a
  | ActionObservedWithDetails !Text !a ![(Text, PublicValue)]
  | ActionUnavailable !Text

-- | Start an operation inventory and derive dependencies from its typed inputs.
declareOperation :: Text -> [Capability] -> OperationInfo
declareOperation key caps = OperationInfo key (Set.fromList caps) [] []

dependsOn :: Input a -> OperationInfo -> OperationInfo
dependsOn input (OperationInfo key caps deps steps) =
  OperationInfo key caps (deps ++ inputDependencies input) steps

withSubstep :: Text -> [Capability] -> OperationInfo -> OperationInfo
withSubstep key caps (OperationInfo name required deps steps) =
  OperationInfo name required deps (steps ++ [(key, Set.fromList caps)])
