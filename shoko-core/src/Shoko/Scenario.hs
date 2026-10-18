module Shoko.Scenario
  ( Scenario,
    ScenarioBuilder,
    scenario,
    given,
    act,
    expect,
    Description (..),
    NodeDescription (..),
    ExpectationDescription (..),
    DefinitionError (..),
    inspectScenario,
    Step (..),
    scenarioParts,
  )
where

import Data.Dynamic (Typeable)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text qualified as Text
import Shoko.Action
import Shoko.Environment
import Shoko.Expectation
import Shoko.Internal.Reference (Ref (..))
import Shoko.Observation
import Shoko.Prelude

data Step op where
  Step :: (Typeable a) => !Text -> !Bool -> !(Action op a) -> Step op

data ScenarioBuilder op a where
  Pure :: a -> ScenarioBuilder op a
  Bind :: ScenarioBuilder op a -> (a -> ScenarioBuilder op b) -> ScenarioBuilder op b
  AddStep :: (Typeable a) => Text -> Bool -> Action op a -> ScenarioBuilder op (Ref a)
  AddExpectations :: Expectations op () -> ScenarioBuilder op ()

instance Functor (ScenarioBuilder op) where
  fmap f a = Bind a (Pure . f)

instance Applicative (ScenarioBuilder op) where
  pure = Pure
  f <*> a = Bind f (\g -> fmap g a)

instance Monad (ScenarioBuilder op) where
  (>>=) = Bind

data Scenario op = Scenario !Text !Text !Text !(ScenarioBuilder op ())

-- | The revision identifies domain predicate/recipe semantics, including code
-- that cannot be represented in the effect-free description.
scenario :: Text -> Text -> Text -> ScenarioBuilder op () -> Scenario op
scenario = Scenario

given :: (Typeable a) => Text -> Action op a -> ScenarioBuilder op (Ref a)
given key = AddStep key True

act :: (Typeable a) => Text -> Action op a -> ScenarioBuilder op (Ref a)
act key = AddStep key False

expect :: Expectations op () -> ScenarioBuilder op ()
expect = AddExpectations

data NodeDescription = NodeDescription
  { nodeId :: !Text,
    fixture :: !Bool,
    operation :: !OperationInfo,
    acceptedOutcomes :: !(Set Text)
  }
  deriving stock (Eq, Show, Generic)

data ExpectationDescription = ExpectationDescription
  { expectationId :: !Text,
    temporal :: !Temporal,
    windows :: ![Duration],
    operation :: !OperationInfo,
    predicate :: !Text
  }
  deriving stock (Eq, Show, Generic)

data Description = Description
  { scenarioId :: !Text,
    title :: !Text,
    revision :: !Text,
    nodes :: ![NodeDescription],
    expectations :: ![ExpectationDescription]
  }
  deriving stock (Eq, Show, Generic)

data DefinitionError
  = InvalidIdentifier
  | DuplicateIdentifier !Text
  | UnresolvedReference !Text
  | ActionAfterExpectations
  | EmptyOutcomeContract !Text
  | EmptyExpectations
  deriving stock (Eq, Show, Generic)

-- Internal traversal assigns only symbolic references. It never invokes IO.
collect :: ScenarioBuilder op a -> (a, [Either (Step op) (Expectation op)])
collect (Pure a) = (a, [])
collect (Bind program f) =
  let (a, first) = collect program
      (b, second) = collect (f a)
   in (b, first ++ second)
collect (AddStep key fixture action) = (Ref key, [Left (Step key fixture action)])
collect (AddExpectations es) = ((), map Right (expectationList es))

scenarioParts :: (Vocabulary op) => Scenario op -> Either [DefinitionError] (Description, [Step op], [Expectation op])
scenarioParts (Scenario key title revision program) =
  let (_, entries) = collect program
      steps = [step | Left step <- entries]
      expectations = [e | Right e <- entries]
      nodeDescriptions = map describeStep steps
      expectationDescriptions = map describeExpectation expectations
      identifiers = key : map nodeKey nodeDescriptions ++ map expectationKey expectationDescriptions
      errors =
        validateEntries Set.empty False entries
          ++ duplicateErrors identifiers
          ++ [InvalidIdentifier | any Text.null (title : revision : identifiers)]
          ++ [EmptyExpectations | null expectations]
   in if null errors
        then Right (Description key title revision nodeDescriptions expectationDescriptions, steps, expectations)
        else Left errors
  where
    nodeKey (NodeDescription k _ _ _) = k
    expectationKey (ExpectationDescription k _ _ _ _) = k
    describeStep (Step k fixture action) =
      NodeDescription
        k
        fixture
        (describeOperation (actionOperation action))
        (acceptedTags action)
    describeExpectation (Expectation k t windows observation) =
      ExpectationDescription
        k
        t
        windows
        (describeOperation (observationOperation observation))
        (predicateId observation)
    validateEntries _ _ [] = []
    validateEntries known afterExpect (entry : rest) = case entry of
      Left (Step k _ action) ->
        let info@(OperationInfo _ _ deps _) = describeOperation (actionOperation action)
         in [ActionAfterExpectations | afterExpect]
              ++ validateOperation info
              ++ [InvalidIdentifier | any Text.null (Set.toList (acceptedTags action))]
              ++ [EmptyOutcomeContract k | Set.null (acceptedTags action)]
              ++ [UnresolvedReference dep | dep <- deps, Set.notMember dep known]
              ++ validateEntries (Set.insert k known) afterExpect rest
      Right (Expectation _ _ _ observation) ->
        let info@(OperationInfo _ _ deps _) = describeOperation (observationOperation observation)
         in validateOperation info
              ++ [InvalidIdentifier | Text.null (predicateId observation)]
              ++ [UnresolvedReference dep | dep <- deps, Set.notMember dep known]
              ++ validateEntries known True rest
    validateOperation (OperationInfo opKey _ _ substeps) =
      [InvalidIdentifier | any Text.null (opKey : map fst substeps)] ++ duplicateErrors (map fst substeps)
    duplicateErrors = go Set.empty
      where
        go _ [] = []
        go seen (k : ks) = [DuplicateIdentifier k | Set.member k seen] ++ go (Set.insert k seen) ks

inspectScenario :: (Vocabulary op) => Scenario op -> Either [DefinitionError] Description
inspectScenario descriptionSource = case scenarioParts descriptionSource of
  Left errors -> Left errors
  Right (description, _, _) -> Right description
