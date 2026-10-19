{-# LANGUAGE RankNTypes #-}

module Shoko.Scenario
  ( Scenario,
    ScenarioBuilder,
    scenario,
    given,
    act,
    expect,
    namespace,
    expectAfterActions,
    hoistScenarioBuilder,
    correlate,
    propagateExecutionId,
    CorrelationDescription (..),
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
import Shoko.Identifier
import Shoko.Internal.Correlation
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
  AddDeferred :: Expectations op () -> ScenarioBuilder op ()
  AddCorrelation :: CorrelationAlias -> BusinessKeyName -> Input Text -> ScenarioBuilder op CorrelationRef
  AddExecution :: ScenarioBuilder op CorrelationRef
  Namespace :: Text -> ScenarioBuilder op a -> ScenarioBuilder op a

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

namespace :: Text -> ScenarioBuilder op a -> ScenarioBuilder op a
namespace = Namespace

-- | Declare a consequence checked after every action in the finished scenario.
expectAfterActions :: Expectations op () -> ScenarioBuilder op ()
expectAfterActions = AddDeferred

correlate :: CorrelationAlias -> BusinessKeyName -> Input Text -> ScenarioBuilder op CorrelationRef
correlate = AddCorrelation

propagateExecutionId :: ScenarioBuilder op CorrelationRef
propagateExecutionId = AddExecution

data CorrelationDescription = CorrelationDescription
  { correlationId :: !CorrelationId,
    correlationKey :: !BusinessKeyName,
    strategy :: !CorrelationStrategy,
    dependencies :: ![Text]
  }
  deriving stock (Eq, Show, Generic)

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
    predicate :: !Text,
    correlationId :: !(Maybe CorrelationId)
  }
  deriving stock (Eq, Show, Generic)

data Description = Description
  { scenarioId :: !Text,
    title :: !Text,
    revision :: !Text,
    nodes :: ![NodeDescription],
    expectations :: ![ExpectationDescription],
    correlations :: ![CorrelationDescription]
  }
  deriving stock (Eq, Show, Generic)

data DefinitionError
  = InvalidIdentifier
  | DuplicateIdentifier !Text
  | UnresolvedReference !Text
  | ActionAfterExpectations
  | EmptyOutcomeContract !Text
  | EmptyExpectations
  | ConflictingOperation !Text
  deriving stock (Eq, Show, Generic)

-- Internal traversal assigns only symbolic references. It never invokes IO.
data Entry op = StepEntry (Step op) | ExpectEntry Bool (Expectation op) | DeclarationEntry CorrelationDeclaration | InvalidNamespace

collect :: [Text] -> ScenarioBuilder op a -> (a, [Entry op])
collect _ (Pure a) = (a, [])
collect prefix (Bind program f) =
  let (a, first) = collect prefix program
      (b, second) = collect prefix (f a)
   in (b, first ++ second)
collect prefix (AddStep key fixture action) =
  let qualified = Text.intercalate "." (prefix ++ [key])
   in (Ref qualified, [InvalidNamespace | Text.null key] ++ [StepEntry (Step qualified fixture action)])
collect prefix (AddExpectations es) = ((), invalidExpectationNames es ++ map (ExpectEntry True . qualifyExpectation prefix) (expectationList es))
collect prefix (AddDeferred es) = ((), invalidExpectationNames es ++ map (ExpectEntry False . qualifyExpectation prefix) (expectationList es))
collect prefix (Namespace label program) =
  let (a, entries) = collect (prefix ++ [label]) program
   in (a, [InvalidNamespace | any Text.null (Text.splitOn "." label)] ++ entries)
collect prefix (AddCorrelation alias key input) =
  let local = correlationAliasText alias
      qualified = CorrelationId (Text.intercalate "." (prefix ++ [local]))
      invalid = local == "execution-id" || any Text.null (Text.splitOn "." local) || Text.null (businessKeyNameText key)
   in (CorrelationRef qualified, [InvalidNamespace | invalid] ++ [DeclarationEntry (BusinessDeclaration qualified key input)])
collect _ AddExecution = (CorrelationRef (CorrelationId "execution-id"), [DeclarationEntry ExecutionDeclaration])

uniqueExecution :: [Entry op] -> [Entry op]
uniqueExecution = go False
  where
    go _ [] = []
    go seen (DeclarationEntry ExecutionDeclaration : rest) =
      [DeclarationEntry ExecutionDeclaration | not seen] ++ go True rest
    go seen (entry : rest) = entry : go seen rest

invalidExpectationNames :: Expectations op a -> [Entry op]
invalidExpectationNames es = [InvalidNamespace | Expectation key _ _ _ <- expectationList es, Text.null key]

qualifyExpectation :: [Text] -> Expectation op -> Expectation op
qualifyExpectation prefix (Expectation key t windows observation) =
  Expectation (Text.intercalate "." (prefix ++ [key])) t windows observation

scenarioParts :: (Vocabulary op) => Scenario op -> Either [DefinitionError] (Description, [Step op], [Expectation op], [CorrelationDeclaration])
scenarioParts (Scenario key title revision program) =
  let (_, collected) = collect [] program
      entries = uniqueExecution collected
      declarations = [declaration | DeclarationEntry declaration <- entries]
      correlationDescriptions = [CorrelationDescription (declarationId d) (declarationKey d) (declarationStrategy d) (declarationDependencies d) | d <- declarations]
      steps = [step | StepEntry step <- entries]
      expectations = [e | ExpectEntry _ e <- entries]
      nodeDescriptions = map describeStep steps
      expectationDescriptions = map describeExpectation expectations
      identifiers = key : map nodeKey nodeDescriptions ++ map expectationKey expectationDescriptions
      errors =
        validateEntries (Set.fromList (map nodeKey nodeDescriptions)) Set.empty False entries
          ++ conflictingOperations (map (\(NodeDescription _ _ info _) -> info) nodeDescriptions ++ map (\(ExpectationDescription _ _ _ info _ _) -> info) expectationDescriptions)
          ++ duplicateErrors identifiers
          ++ duplicateErrors (map (correlationIdText . declarationId) declarations)
          ++ [InvalidIdentifier | any Text.null (title : revision : identifiers)]
          ++ [EmptyExpectations | null expectations]
   in if null errors
        then Right (Description key title revision nodeDescriptions expectationDescriptions correlationDescriptions, steps, expectations, declarations)
        else Left errors
  where
    nodeKey (NodeDescription k _ _ _) = k
    expectationKey (ExpectationDescription k _ _ _ _ _) = k
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
        (correlationRefId <$> observationCorrelation observation)
    validateEntries _ _ _ [] = []
    validateEntries final known afterExpect (entry : rest) = case entry of
      StepEntry (Step k _ action) ->
        let info@(OperationInfo _ _ deps _) = describeOperation (actionOperation action)
         in [ActionAfterExpectations | afterExpect]
              ++ validateOperation info
              ++ [InvalidIdentifier | any Text.null (Set.toList (acceptedTags action))]
              ++ [EmptyOutcomeContract k | Set.null (acceptedTags action)]
              ++ [UnresolvedReference dep | dep <- deps, Set.notMember dep known]
              ++ validateEntries final (Set.insert k known) afterExpect rest
      ExpectEntry strict (Expectation _ _ _ observation) ->
        let info@(OperationInfo _ _ deps _) = describeOperation (observationOperation observation)
         in validateOperation info
              ++ [InvalidIdentifier | not (validPredicate observation)]
              ++ [UnresolvedReference dep | dep <- deps, Set.notMember dep (if strict then known else final)]
              ++ validateEntries final known (afterExpect || strict) rest
      DeclarationEntry declaration ->
        [UnresolvedReference dep | dep <- declarationDependencies declaration, Set.notMember dep known]
          ++ validateEntries final known afterExpect rest
      InvalidNamespace -> InvalidIdentifier : validateEntries final known afterExpect rest
    validateOperation (OperationInfo opKey _ _ substeps) =
      [InvalidIdentifier | any Text.null (opKey : map fst substeps)] ++ duplicateErrors (map fst substeps)
    duplicateErrors = go Set.empty
      where
        go _ [] = []
        go seen (k : ks) = [DuplicateIdentifier k | Set.member k seen] ++ go (Set.insert k seen) ks

inspectScenario :: (Vocabulary op) => Scenario op -> Either [DefinitionError] Description
inspectScenario descriptionSource = case scenarioParts descriptionSource of
  Left errors -> Left errors
  Right (description, _, _, _) -> Right description

-- Dependency nodes vary per use; only operation-level contracts must agree.
conflictingOperations :: [OperationInfo] -> [DefinitionError]
conflictingOperations [] = []
conflictingOperations (OperationInfo key caps _ steps : rest) =
  [ConflictingOperation key | any conflicts rest] ++ conflictingOperations rest
  where
    conflicts (OperationInfo other otherCaps _ otherSteps) = key == other && (caps /= otherCaps || Set.fromList steps /= Set.fromList otherSteps)

hoistScenarioBuilder :: (forall x. f x -> g x) -> ScenarioBuilder f a -> ScenarioBuilder g a
hoistScenarioBuilder _ (Pure a) = Pure a
hoistScenarioBuilder transform (Bind first next) = Bind (hoistScenarioBuilder transform first) (hoistScenarioBuilder transform . next)
hoistScenarioBuilder transform (AddStep key fixture action) = AddStep key fixture (hoistAction transform action)
hoistScenarioBuilder transform (AddExpectations es) = AddExpectations (hoistExpectations transform es)
hoistScenarioBuilder transform (AddDeferred es) = AddDeferred (hoistExpectations transform es)
hoistScenarioBuilder transform (Namespace label program) = Namespace label (hoistScenarioBuilder transform program)
hoistScenarioBuilder _ (AddCorrelation alias key input) = AddCorrelation alias key input
hoistScenarioBuilder _ AddExecution = AddExecution
