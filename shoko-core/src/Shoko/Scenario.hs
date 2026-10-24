{-# LANGUAGE RankNTypes #-}

module Shoko.Scenario
  ( Scenario,
    ScenarioBuilder,
    scenario,
    given,
    act,
    expect,
    namespace,
    concurrently,
    expectAfterActions,
    hoistScenarioBuilder,
    correlate,
    propagateExecutionId,
    CorrelationDescription (..),
    Description (..),
    NodeDescription (..),
    ExpectationDescription (..),
    ExpectationSubject (..),
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
import Shoko.Internal.Predicate (predicateKey, validResultPredicate)
import Shoko.Internal.Reference (Ref (..))
import Shoko.Observation
import Shoko.Prelude

data Step op where
  Step :: (Typeable a) => !Text -> !Bool -> !(Maybe Text) -> !(Action op a) -> Step op

data ScenarioBuilder op a where
  Pure :: a -> ScenarioBuilder op a
  Bind :: ScenarioBuilder op a -> (a -> ScenarioBuilder op b) -> ScenarioBuilder op b
  AddStep :: (Typeable a) => Text -> Bool -> Action op a -> ScenarioBuilder op (Ref a)
  AddExpectations :: Expectations op () -> ScenarioBuilder op ()
  AddDeferred :: Expectations op () -> ScenarioBuilder op ()
  AddCorrelation :: CorrelationAlias -> BusinessKeyName -> Input Text -> ScenarioBuilder op CorrelationRef
  AddExecution :: ScenarioBuilder op CorrelationRef
  Concurrently :: Text -> ScenarioBuilder op a -> ScenarioBuilder op a
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

-- | Declare independent actions admitted together. Validation rejects other nodes
-- and dependencies between members; bindings explicitly opt into concurrent calls.
concurrently :: Text -> ScenarioBuilder op a -> ScenarioBuilder op a
concurrently = Concurrently

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
    acceptedOutcomes :: !(Set Text),
    group :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)

data ExpectationSubject = ObservationSubject !OperationInfo | ResultSubject ![Text]
  deriving stock (Eq, Show, Generic)

data ExpectationDescription = ExpectationDescription
  { expectationId :: !Text,
    temporal :: !Temporal,
    windows :: ![Duration],
    subject :: !ExpectationSubject,
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
  | InvalidExpectationTemporal !Text
  | InvalidConcurrentGroup !Text
  deriving stock (Eq, Show, Generic)

-- Internal traversal assigns only symbolic references. It never invokes IO.
data Entry op = StepEntry (Step op) | ExpectEntry Bool (Expectation op) | DeclarationEntry CorrelationDeclaration | InvalidNamespace | BeginGroup Text | EndGroup | InvalidGroup Text

collect :: [Text] -> Maybe Text -> ScenarioBuilder op a -> (a, [Entry op])
collect _ _ (Pure a) = (a, [])
collect prefix group (Bind program f) =
  let (a, first) = collect prefix group program
      (b, second) = collect prefix group (f a)
   in (b, first ++ second)
collect prefix group (AddStep key fixture action) =
  let qualified = Text.intercalate "." (prefix ++ [key])
   in (Ref qualified, [InvalidNamespace | Text.null key] ++ forbidden group fixture ++ [StepEntry (Step qualified fixture group action)])
collect prefix group (AddExpectations es) = ((), forbidden group True ++ invalidExpectationNames es ++ map (ExpectEntry True . qualifyExpectation prefix) (expectationList es))
collect prefix group (AddDeferred es) = ((), forbidden group True ++ invalidExpectationNames es ++ map (ExpectEntry False . qualifyExpectation prefix) (expectationList es))
collect prefix group (Namespace label program) =
  let (a, entries) = collect (prefix ++ [label]) group program
   in (a, [InvalidNamespace | any Text.null (Text.splitOn "." label)] ++ entries)
collect prefix group (Concurrently label program) =
  let qualified = Text.intercalate "." (prefix ++ [label])
      (a, entries) = collect prefix (Just qualified) program
   in (a, forbidden group True ++ [InvalidNamespace | any Text.null (Text.splitOn "." label)] ++ [BeginGroup qualified] ++ [InvalidGroup qualified | null [() | StepEntry (Step _ _ selected _) <- entries, selected == Just qualified]] ++ entries ++ [EndGroup])
collect prefix group (AddCorrelation alias key input) =
  let local = correlationAliasText alias
      qualified = CorrelationId (Text.intercalate "." (prefix ++ [local]))
      invalid = local == "execution-id" || any Text.null (Text.splitOn "." local) || Text.null (businessKeyNameText key)
   in (CorrelationRef qualified, forbidden group True ++ [InvalidNamespace | invalid] ++ [DeclarationEntry (BusinessDeclaration qualified key input)])
collect _ group AddExecution = (CorrelationRef (CorrelationId "execution-id"), forbidden group True ++ [DeclarationEntry ExecutionDeclaration])

forbidden :: Maybe Text -> Bool -> [Entry op]
forbidden (Just group) True = [InvalidGroup group]
forbidden _ _ = []

uniqueExecution :: [Entry op] -> [Entry op]
uniqueExecution = go False
  where
    go _ [] = []
    go seen (DeclarationEntry ExecutionDeclaration : rest) =
      [DeclarationEntry ExecutionDeclaration | not seen] ++ go True rest
    go seen (entry : rest) = entry : go seen rest

invalidExpectationNames :: Expectations op a -> [Entry op]
invalidExpectationNames es = [InvalidNamespace | e <- expectationList es, Text.null (expectationName e)]
  where
    expectationName (Expectation key _ _ _) = key
    expectationName (ResultCheck key _ _ _) = key

qualifyExpectation :: [Text] -> Expectation op -> Expectation op
qualifyExpectation prefix (ResultCheck key windows input test) =
  ResultCheck (Text.intercalate "." (prefix ++ [key])) windows input test
qualifyExpectation prefix (Expectation key t windows observation) =
  Expectation (Text.intercalate "." (prefix ++ [key])) t windows observation

scenarioParts :: (Vocabulary op) => Scenario op -> Either [DefinitionError] (Description, [Step op], [Expectation op], [CorrelationDeclaration])
scenarioParts (Scenario key title revision program) =
  let (_, collected) = collect [] Nothing program
      entries = uniqueExecution collected
      declarations = [declaration | DeclarationEntry declaration <- entries]
      correlationDescriptions = [CorrelationDescription (declarationId d) (declarationKey d) (declarationStrategy d) (declarationDependencies d) | d <- declarations]
      steps = [step | StepEntry step <- entries]
      expectations = [e | ExpectEntry _ e <- entries]
      nodeDescriptions = map describeStep steps
      expectationDescriptions = map describeExpectation expectations
      identifiers = key : map nodeKey nodeDescriptions ++ map expectationKey expectationDescriptions ++ [group | BeginGroup group <- entries]
      errors =
        validateEntries steps (Set.fromList (map nodeKey nodeDescriptions)) Set.empty Nothing False entries
          ++ conflictingOperations (map (\(NodeDescription _ _ info _ _) -> info) nodeDescriptions ++ [info | ExpectationDescription _ _ _ (ObservationSubject info) _ _ <- expectationDescriptions])
          ++ duplicateErrors identifiers
          ++ duplicateErrors (map (correlationIdText . declarationId) declarations)
          ++ [InvalidIdentifier | any Text.null (title : revision : identifiers)]
          ++ [EmptyExpectations | null expectations]
   in if null errors
        then Right (Description key title revision nodeDescriptions expectationDescriptions correlationDescriptions, steps, expectations, declarations)
        else Left errors
  where
    nodeKey (NodeDescription k _ _ _ _) = k
    expectationKey (ExpectationDescription k _ _ _ _ _) = k
    describeStep (Step k fixture group action) =
      NodeDescription
        k
        fixture
        (describeOperation (actionOperation action))
        (acceptedTags action)
        group
    describeExpectation (ResultCheck k windows input test) = ExpectationDescription k Immediately windows (ResultSubject (inputDependencies input)) (predicateKey test) Nothing
    describeExpectation (Expectation k t windows observation) =
      ExpectationDescription
        k
        t
        windows
        (ObservationSubject (describeOperation (observationOperation observation)))
        (predicateId observation)
        (correlationRefId <$> observationCorrelation observation)
    validateEntries _ _ _ _ _ [] = []
    validateEntries members final known active afterExpect (entry : rest) = case entry of
      StepEntry (Step k _ _ action) ->
        let info@(OperationInfo _ _ deps _) = describeOperation (actionOperation action)
         in [ActionAfterExpectations | afterExpect]
              ++ validateOperation info
              ++ [InvalidIdentifier | any Text.null (Set.toList (acceptedTags action))]
              ++ [EmptyOutcomeContract k | Set.null (acceptedTags action)]
              ++ case active of
                Nothing -> [UnresolvedReference dep | dep <- deps, Set.notMember dep known]
                Just (group, before) ->
                  let memberIds = [identity | Step identity _ (Just selected) _ <- members, selected == group]
                   in [InvalidConcurrentGroup group | any (`elem` memberIds) deps]
                        ++ [UnresolvedReference dep | dep <- deps, dep `notElem` memberIds, Set.notMember dep before]
              ++ validateEntries members final (Set.insert k known) active afterExpect rest
      ExpectEntry strict (ResultCheck _ _ input test) ->
        [InvalidIdentifier | not (validResultPredicate test)]
          ++ [UnresolvedReference dep | dep <- inputDependencies input, Set.notMember dep (if strict then known else final)]
          ++ validateEntries members final known active (afterExpect || strict) rest
      ExpectEntry strict (Expectation k temporal _ observation) ->
        let info@(OperationInfo _ _ deps _) = describeOperation (observationOperation observation)
         in validateOperation info
              ++ [InvalidExpectationTemporal k | temporal == Immediately]
              ++ [InvalidIdentifier | not (validPredicate observation)]
              ++ [UnresolvedReference dep | dep <- deps, Set.notMember dep (if strict then known else final)]
              ++ validateEntries members final known active (afterExpect || strict) rest
      DeclarationEntry declaration ->
        [UnresolvedReference dep | dep <- declarationDependencies declaration, Set.notMember dep known]
          ++ validateEntries members final known active afterExpect rest
      BeginGroup group ->
        [InvalidConcurrentGroup group | null [() | Step _ _ (Just selected) _ <- members, selected == group]]
          ++ validateEntries members final known (Just (group, known)) afterExpect rest
      EndGroup -> validateEntries members final known Nothing afterExpect rest
      InvalidGroup group -> InvalidConcurrentGroup group : validateEntries members final known active afterExpect rest
      InvalidNamespace -> InvalidIdentifier : validateEntries members final known active afterExpect rest
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
hoistScenarioBuilder transform (Concurrently label program) = Concurrently label (hoistScenarioBuilder transform program)
hoistScenarioBuilder transform (Namespace label program) = Namespace label (hoistScenarioBuilder transform program)
hoistScenarioBuilder _ (AddCorrelation alias key input) = AddCorrelation alias key input
hoistScenarioBuilder _ AddExecution = AddExecution
