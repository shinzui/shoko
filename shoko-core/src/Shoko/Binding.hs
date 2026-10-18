{-# LANGUAGE RankNTypes #-}

module Shoko.Binding
  ( Binding (..),
    BindingContract (..),
    CallContext (..),
    Disposition (..),
    ResolvedScenario,
    resolveScenario,
    resolvedParts,
    PolicyReport (..),
    PreflightError (..),
  )
where

import Data.Set (Set)
import Data.Set qualified as Set
import Shoko.Action
import Shoko.Clock (Clock)
import Shoko.Correlation
import Shoko.Environment
import Shoko.Expectation
import Shoko.Observation
import Shoko.Prelude
import Shoko.Scenario

data BindingContract = BindingContract
  { capabilities :: !(Set Capability),
    cleanupCapabilities :: !(Set Capability),
    supportedCorrelation :: !(Set CorrelationStrategy),
    source :: !(Maybe Text),
    coverageStrength :: !CoverageStrength
  }
  deriving stock (Eq, Show, Generic)

-- | A handler can only resolve its statically declared reference dependencies.
-- Composite substeps use the same remaining deadline and declared inventory.
data CallContext = CallContext
  { resolveInput :: forall a. Input a -> Either Text a,
    deadline :: !Integer,
    baseline :: !(Maybe Baseline),
    correlation :: !(Maybe Correlation),
    substep :: forall a. Text -> IO a -> IO (Either Text a),
    evidenceUntil :: !Integer,
    clock :: !Clock
  }

data Disposition = Cleaned | Retained | CleanupFailed | CleanupTimedOut
  deriving stock (Eq, Show, Generic)

data Binding op resource = Binding
  { name :: !Text,
    lifecycleCapabilities :: !(Set Capability),
    contract :: forall a. OperationRole -> op a -> Maybe BindingContract,
    acquire :: (IO Disposition -> IO ()) -> IO resource,
    release :: resource -> IO Disposition,
    captureBaseline :: resource -> Clock -> Text -> IO (Either Text Baseline),
    performAction :: forall a. resource -> CallContext -> op a -> IO (ActionOutcome a),
    performObservation :: forall a. resource -> CallContext -> op a -> IO (ObservationOutcome a)
  }

data PolicyReport = PolicyReport
  { requiredCapabilities :: !(Set Capability),
    selectedCorrelation :: !CorrelationStrategy
  }
  deriving stock (Eq, Show, Generic)

data PreflightError
  = InvalidDefinition ![DefinitionError]
  | MissingHandler !Text
  | MissingSource !Text
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
  binding@(Binding bindingName lifecycle lookupContract _ _ _ _ _)
  descriptionSource =
    case scenarioParts descriptionSource of
      Left errors -> Left [InvalidDefinition errors]
      Right (description@(Description _ _ _ descriptions _), steps, expectations) ->
        let results = map stepContract steps ++ map expectationContract expectations
            errors = concatMap fst results
            required = Set.unions (lifecycle : map snd results)
            denied = Set.difference required allowed
            known = Set.fromList [key | NodeDescription key _ _ _ <- descriptions]
            allErrors =
              errors
                ++ [ProductionUnsupported | production]
                ++ [InvalidBindingIdentifier | any (== "") [envName, bindingName, runKey, build]]
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
                      binding
                      environment
                      options
                      correlationPlan
                      (PolicyReport required (correlationStrategy correlationPlan))
                  )
              else Left allErrors
    where
      requirements :: forall a. OperationRole -> op a -> Bool -> ([PreflightError], Set Capability)
      requirements role op needsSource =
        let OperationInfo key declared _ substeps = describeOperation op
         in case lookupContract role op of
              Nothing -> ([MissingHandler key], declared)
              Just (BindingContract extra cleanup strategies source _) ->
                ( [UnsupportedCorrelation key | Set.notMember (correlationStrategy correlationPlan) strategies]
                    ++ [MissingSource key | (needsSource && source == Nothing) || source == Just ""],
                  Set.unions (declared : extra : cleanup : map snd substeps)
                )
      stepContract (Step _ fixture action) = requirements (if fixture then FixtureOperation else ActionOperation) (actionOperation action) False
      expectationContract (Expectation _ _ _ observation) = requirements ObservationOperation (observationOperation observation) True
      validTarget Nothing = True
      validTarget (Just (TargetIdentity targetName namespace revision)) = all (/= "") [targetName, namespace, revision]

-- | Used by the single runner interpreter; consumers should use inspection.
resolvedParts ::
  ResolvedScenario op resource ->
  (Description, [Step op], [Expectation op], Binding op resource, Environment, RunOptions, CorrelationPlan, PolicyReport)
resolvedParts (ResolvedScenario _ description steps expectations binding environment options correlation report) =
  (description, steps, expectations, binding, environment, options, correlation, report)
