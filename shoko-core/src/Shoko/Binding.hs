{-# LANGUAGE RankNTypes #-}

module Shoko.Binding
  ( Binding,
    BindingContract,
    CallContext,
    Source,
    Handler,
    Disposition (..),
    InputResolutionError (..),
    HandlerBuildError (..),
    CorrelationRequirement (..),
    HandlerKind (..),
    resolveInput,
    requestDeadline,
    evidenceUntil,
    sourceBaseline,
    correlation,
    executionId,
    runSubstep,
    callClock,
    detachedCallContext,
    noRequirements,
    requiring,
    cleanupRequiring,
    contractCapabilities,
    contractCleanup,
    newSource,
    sampledSource,
    sourceId,
    sourceCoverage,
    actionHandler,
    observationHandler,
    focus,
    handlerKind,
    handlerSource,
    handlerCorrelation,
    handlerContract,
    adjustContract,
    binding,
    requiringLifecycle,
    adjustHandlers,
    bindingName,
    bindingLifecycle,
    bindingHandler,
    guardCorrelation,
    ResolvedScenario,
    resolveScenario,
    resolvedParts,
    resolvedPolicyReport,
    PolicyReport (..),
    PreflightError (..),
  )
where

import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text qualified as Text
import Shoko.Action
import Shoko.Clock
import Shoko.Correlation
import Shoko.Environment
import Shoko.Expectation
import Shoko.Identifier
import Shoko.Internal.Binding
import Shoko.Internal.Call
import Shoko.Internal.Reference (InputResolutionError (..))
import Shoko.Observation
import Shoko.Prelude
import Shoko.Scenario

resolveInput :: CallContext -> Input a -> IO (Either InputResolutionError a)
resolveInput context input = callResolve context input

requestDeadline :: CallContext -> MonotonicTime
requestDeadline = callDeadline

evidenceUntil :: CallContext -> MonotonicTime
evidenceUntil = callCutoff

sourceBaseline :: CallContext -> Maybe Baseline
sourceBaseline = callBaseline

correlation :: CallContext -> Maybe Correlation
correlation = callCorrelation

executionId :: CallContext -> Maybe Text
executionId = callExecutionId

runSubstep :: CallContext -> Text -> IO a -> IO (Either Text a)
runSubstep context key action = callSubstep context key action

callClock :: CallContext -> Clock
callClock = callTime

detachedCallContext :: Clock -> MonotonicTime -> MonotonicTime -> Maybe Baseline -> Maybe Correlation -> CallContext
detachedCallContext clock end cutoff base selected =
  CallContext (const (pure (Left DetachedInputContext))) end base selected (\_ _ -> pure (Left "detached-substep")) cutoff clock Nothing

noRequirements :: BindingContract
noRequirements = BindingContract Set.empty Set.empty

requiring :: [Capability] -> BindingContract -> BindingContract
requiring extra (BindingContract caps cleanup) = BindingContract (Set.union caps (Set.fromList extra)) cleanup

cleanupRequiring :: [Capability] -> BindingContract -> BindingContract
cleanupRequiring extra (BindingContract caps cleanup) = BindingContract caps (Set.union cleanup (Set.fromList extra))

contractCapabilities :: BindingContract -> Set Capability
contractCapabilities (BindingContract caps _) = caps

contractCleanup :: BindingContract -> Set Capability
contractCleanup (BindingContract _ caps) = caps

newSource :: SourceId -> CoverageStrength -> (resource -> Clock -> IO (Either Text Baseline)) -> Source resource
newSource label strength capture = Source label strength capture []

sampledSource :: SourceId -> Source resource
sampledSource label = newSource label SampledState $ \_ clock -> do
  tick <- monotonic clock
  pure (Right (Baseline label tick Nothing))

sourceId :: Source resource -> SourceId
sourceId (Source label _ _ _) = label

sourceCoverage :: Source resource -> CoverageStrength
sourceCoverage (Source _ strength _ _) = strength

actionHandler :: BindingContract -> (resource -> CallContext -> IO (ActionOutcome a)) -> Handler resource a
actionHandler = ActionHandler

observationHandler :: BindingContract -> CorrelationRequirement -> Source resource -> (resource -> CallContext -> IO (ObservationOutcome a)) -> Handler resource a
observationHandler = ObservationHandler

focus :: (outer -> inner) -> Handler inner a -> Handler outer a
focus project (ActionHandler contract perform) = ActionHandler contract (perform . project)
focus project (ObservationHandler contract requirement (Source label strength capture owner) perform) =
  ObservationHandler contract requirement (Source label strength (capture . project) owner) (perform . project)

handlerKind :: Handler resource a -> HandlerKind
handlerKind (ActionHandler _ _) = ActionHandlerKind
handlerKind (ObservationHandler _ _ _ _) = ObservationHandlerKind

handlerSource :: Handler resource a -> Maybe (Source resource)
handlerSource (ActionHandler _ _) = Nothing
handlerSource (ObservationHandler _ _ source _) = Just source

handlerCorrelation :: Handler resource a -> Maybe CorrelationRequirement
handlerCorrelation (ActionHandler _ _) = Nothing
handlerCorrelation (ObservationHandler _ requirement _ _) = Just requirement

handlerContract :: Handler resource a -> BindingContract
handlerContract (ActionHandler contract _) = contract
handlerContract (ObservationHandler contract _ _ _) = contract

adjustContract :: (BindingContract -> BindingContract) -> Handler resource a -> Handler resource a
adjustContract f (ActionHandler contract perform) = ActionHandler (f contract) perform
adjustContract f (ObservationHandler contract requirement source perform) = ObservationHandler (f contract) requirement source perform

binding :: Text -> ((IO Disposition -> IO ()) -> IO resource) -> (resource -> IO Disposition) -> (forall a. OperationRole -> op a -> Either HandlerBuildError (Maybe (Handler resource a))) -> Binding op resource
binding name acquire release = Binding name Set.empty acquire (\resource -> [release resource])

requiringLifecycle :: [Capability] -> Binding op resource -> Binding op resource
requiringLifecycle extra b = b {internalLifecycle = Set.union (internalLifecycle b) (Set.fromList extra)}

adjustHandlers :: (forall a. OperationRole -> op a -> Maybe (Handler resource a) -> Maybe (Handler resource a)) -> Binding op resource -> Binding op resource
adjustHandlers f b = b {internalHandler = \role op -> f role op <$> internalHandler b role op}

bindingName :: Binding op resource -> Text
bindingName = internalName

bindingLifecycle :: Binding op resource -> Set Capability
bindingLifecycle = internalLifecycle

bindingHandler :: Binding op resource -> OperationRole -> op a -> Either HandlerBuildError (Maybe (Handler resource a))
bindingHandler selected role op = internalHandler selected role op

guardCorrelation :: BusinessKeyName -> Input Text -> CallContext -> IO (ObservationOutcome a) -> IO (ObservationOutcome a)
guardCorrelation name input context action =
  resolveInput context input >>= \case
    Right value | Just (ByBusinessKey selected actual) <- correlation context, name == selected && value == actual && value /= "" -> action
    _ -> pure (ObservationUnavailable "correlation-lost")

data PolicyReport = PolicyReport
  { requiredCapabilities :: !(Set Capability),
    selectedCorrelation :: !CorrelationStrategy
  }
  deriving stock (Eq, Show, Generic)

data PreflightError
  = InvalidDefinition ![DefinitionError]
  | MissingHandler !Text
  | MissingSource !Text
  | InconsistentSource !SourceId
  | HandlerConstructionFailed !Text !HandlerBuildError
  | CapabilitiesDenied !(Set Capability)
  | SyntheticConsentRequired
  | UnsupportedCorrelation !Text
  | MissingCorrelationReference !Text
  | ProductionUnsupported
  | InvalidBindingIdentifier
  | InvalidLogicalInput
  deriving stock (Eq, Show, Generic)

data ResolvedScenario op resource
  = ResolvedScenario
      !(Scenario op)
      !Description
      ![Step op]
      ![Expectation op]
      !(Binding op resource)
      !Environment
      !RunOptions
      !CorrelationPlan
      !PolicyReport

resolveScenario ::
  forall op resource.
  (Vocabulary op) =>
  Environment ->
  RunOptions ->
  CorrelationPlan ->
  Binding op resource ->
  Scenario op ->
  Either [PreflightError] (ResolvedScenario op resource)
resolveScenario
  environment@(Environment envName production allowed _)
  options@(RunOptions runKey synthetic build implementation target)
  correlationPlan
  selectedBinding@(Binding name lifecycle _ _ lookupHandler)
  descriptionSource =
    case scenarioParts descriptionSource of
      Left errors -> Left [InvalidDefinition errors]
      Right (description@(Description _ _ _ descriptions _), steps, expectations) ->
        let results = map stepContract steps ++ map expectationContract expectations
            errors = concatMap (\(es, _, _) -> es) results
            sources = concatMap (\(_, _, ss) -> ss) results
            sourceErrors = [InconsistentSource label | (index, (label, strength, owner)) <- zip [0 :: Int ..] sources, (otherLabel, otherStrength, otherOwner) <- take index sources, label == otherLabel, strength /= otherStrength || owner /= otherOwner]
            required = Set.unions (lifecycle : map (\(_, caps, _) -> caps) results)
            denied = Set.difference required allowed
            known = Set.fromList [key | NodeDescription key _ _ _ <- descriptions]
            allErrors =
              errors
                ++ sourceErrors
                ++ [ProductionUnsupported | production]
                ++ [InvalidBindingIdentifier | any (== "") [envName, name, runKey, build]]
                ++ [InvalidBindingIdentifier | implementation == Just "" || not (validTarget target)]
                ++ [CapabilitiesDenied denied | not (Set.null denied)]
                ++ [SyntheticConsentRequired | Set.member SyntheticResource required && not synthetic]
                ++ [MissingCorrelationReference key | key <- correlationDependencies correlationPlan, Set.notMember key known]
         in if null allErrors
              then
                Right
                  ( ResolvedScenario
                      descriptionSource
                      description
                      steps
                      expectations
                      selectedBinding
                      environment
                      options
                      correlationPlan
                      (PolicyReport required (correlationStrategy correlationPlan))
                  )
              else Left allErrors
    where
      requirements :: forall a. OperationRole -> op a -> Bool -> ([PreflightError], Set Capability, [(SourceId, CoverageStrength, [Bool])])
      requirements role op needsSource =
        let OperationInfo key declared _ substeps = describeOperation op
            declaredCaps = Set.unions (declared : map snd substeps)
         in case lookupHandler role op of
              Left cause -> ([HandlerConstructionFailed key cause], declaredCaps, [])
              Right Nothing -> ([MissingHandler key], declaredCaps, [])
              Right (Just handler) ->
                let requiredKind = if needsSource then ObservationHandlerKind else ActionHandlerKind
                    contract = handlerContract handler
                    required = Set.unions [declaredCaps, contractCapabilities contract, contractCleanup contract]
                    support = case (handlerCorrelation handler, correlationPlan) of
                      (Nothing, _) -> True
                      (Just (RequiresBusinessKey name'), BusinessKeyFrom selected _) -> name' == selected
                      (Just RequiresExecutionId, PropagatedExecutionId) -> True
                      _ -> False
                    sources = case handlerSource handler of
                      Just (Source label strength _ owner) -> [(label, strength, owner)]
                      Nothing -> []
                 in ( [MissingHandler key | handlerKind handler /= requiredKind]
                        ++ [UnsupportedCorrelation key | not support]
                        ++ [MissingSource key | needsSource && (null sources || any (Text.null . sourceIdText . (\(label, _, _) -> label)) sources)],
                      required,
                      sources
                    )
      stepContract (Step _ fixture action) = requirements (if fixture then FixtureOperation else ActionOperation) (actionOperation action) False
      expectationContract (Expectation _ _ _ observation) = requirements ObservationOperation (observationOperation observation) True
      validTarget Nothing = True
      validTarget (Just (TargetIdentity targetName targetNamespace revision)) = all (/= "") [targetName, targetNamespace, revision]

-- | Used by the single runner interpreter; consumers should use inspection.
resolvedParts ::
  ResolvedScenario op resource ->
  (Description, [Step op], [Expectation op], Binding op resource, Environment, RunOptions, CorrelationPlan, PolicyReport)
resolvedParts (ResolvedScenario _ description steps expectations selectedBinding environment options plan report) =
  (description, steps, expectations, selectedBinding, environment, options, plan, report)

resolvedPolicyReport :: ResolvedScenario op resource -> PolicyReport
resolvedPolicyReport resolved = let (_, _, _, _, _, _, _, report) = resolvedParts resolved in report
