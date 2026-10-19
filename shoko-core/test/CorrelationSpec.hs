module CorrelationSpec (tests) where

import Consumer.Account (testEnvironment, testOptions)
import Consumer.Composed qualified as C
import Consumer.Hooks (newMicroClock)
import Data.Either (isLeft)
import Data.IORef
import Data.Set qualified as Set
import Data.String (fromString)
import Data.Text qualified as Text
import Data.Time (UTCTime (..), fromGregorian)
import Hedgehog (PropertyT, assert, evalIO, property, withTests, (===))
import Shoko hiding (binding)
import Shoko qualified
import Shoko.Clock
import Shoko.Evidence
import Shoko.Prelude (Text)
import Shoko.Result
import Shoko.Result.Json
import Shoko.Scenario (CorrelationDescription (..), DefinitionError (..), Description (..), ExpectationDescription (..))
import Test.Tasty
import Test.Tasty.Hedgehog

data Probe a where
  Seed :: Text -> Probe Text
  Action :: Bool -> Probe ()
  Read :: CorrelationRequirement -> Probe Bool

instance Vocabulary Probe where
  describeOperation (Seed _) = declareOperation "seed" []
  describeOperation (Action _) = declareOperation "act" []
  describeOperation (Read _) = declareOperation "read" []

type Seen = IORef ([Maybe Text], [Maybe Correlation])

probeBinding :: IORef Int -> Seen -> Binding Probe ()
probeBinding allocations seen = Shoko.binding "correlation-probe" (\_ -> modifyIORef' allocations (+ 1)) (const (pure Cleaned)) handlers
  where
    handlers :: OperationRole -> Probe a -> Either HandlerBuildError (Maybe (Handler () a))
    handlers FixtureOperation (Seed value) = Right $ Just $ actionHandler noRequirements (\_ _ -> pure (ActionObserved "ready" value))
    handlers ActionOperation (Action failAction) = Right $ Just $ actionHandler noRequirements $ \_ call -> do
      modifyIORef' seen (\(actions, observations) -> (actions ++ [executionId call], observations))
      pure (if failAction then ActionUnavailable "unavailable" else ActionObserved "done" ())
    handlers ObservationOperation (Read requirement) = Right $ Just $ observationHandler noRequirements requirement (sampledSource (SourceId "probe")) $ \_ call -> do
      atomicModifyIORef' seen (\(actions, observations) -> ((actions, observations ++ [correlation call]), ()))
      tick <- monotonic (callClock call)
      pure (Observed [Occurrence Nothing True] (Coverage SampledState tick tick True))
    handlers _ _ = Right Nothing

run :: (Vocabulary op) => Binding op r -> Scenario op -> IO VerificationResult
run selected source = do
  (clock, _) <- newMicroClock (UTCTime (fromGregorian 2026 10 18) 0)
  resolved <- either (fail . show) pure (resolveScenario testEnvironment testOptions selected source)
  runScenario clock (LogicalInput "correlations" []) resolved >>= \case
    Verification report -> pure report
    other -> fail (show other)

newProbe :: IO (Binding Probe (), IORef Int, Seen)
newProbe = do
  allocations <- newIORef 0
  seen <- newIORef ([], [])
  pure (probeBinding allocations seen, allocations, seen)

keyName :: BusinessKeyName
keyName = BusinessKeyName "entityId"

observeSelected :: CorrelationRef -> CorrelationRequirement -> Observation Probe Bool
observeSelected handle requirement = correlatedBy handle (observe "yes" (Read requirement) id)

tests :: TestTree
tests =
  testGroup
    "scenario-owned correlation instances"
    [ check "two instances share a semantic key and resolve independently across contexts" $ do
        report@VerificationResult {correlations = resolved, description = description, verdict = v} <- evalIO $ run (combineBindings "composed" C.registrationBinding C.accountsBinding) C.composedRegistration
        v === Pass
        map (\(ResolvedCorrelation identity _) -> identity) resolved === [CorrelationId "inviter.registration", CorrelationId "invitee.registration", CorrelationId "account"]
        [value | ResolvedCorrelation _ (ByBusinessKey (BusinessKeyName "registrationId") value) <- resolved] === ["registration-agent-1", "registration-agent-2"]
        case description of
          Description {correlations = declarations, expectations = expectations} -> do
            map (\(CorrelationDescription _ key _ _) -> key) declarations === [BusinessKeyName "registrationId", BusinessKeyName "registrationId", BusinessKeyName "accountId"]
            map (\(ExpectationDescription _ _ _ _ _ selected) -> selected) expectations === map Just [CorrelationId "inviter.registration", CorrelationId "invitee.registration", CorrelationId "account"]
        decodeRunResult (encodeRunResult (Verification report)) === Right (Verification report),
      check "one unresolved repeated-key instance leaves resolved siblings running" $ do
        report@VerificationResult {verdict = v, expectations = children, correlations = resolved} <- evalIO $ run (combineBindings "partial" (C.registrationBindingWith True) C.accountsBinding) C.composedRegistration
        v === Unknown
        map (\ExpectationResult {reason = why} -> why) children === [CorrelationLost, Satisfied, Satisfied]
        map (\(ResolvedCorrelation identity _) -> identity) resolved === [CorrelationId "invitee.registration", CorrelationId "account"]
        decodeRunResult (encodeRunResult (Verification report)) === Right (Verification report),
      check "a sibling's input cannot satisfy another instance's selection" $ do
        let source = scenario "cross-instance" "Explicit isolation" "1" $ do
              (_, first) <- namespace "first" C.registrationBlock
              (second, _) <- namespace "second" C.registrationBlock
              expectAfterActions $ eventually "cross" $ correlatedBy first $ observe "exists" (C.Registered (fromRef second)) id
        VerificationResult {verdict = v, expectations = children} <- evalIO (run C.registrationBinding source)
        v === Unknown
        map (\ExpectationResult {verdict = result} -> result) children === [Pass, Pass, Unknown],
      check "missing and incompatible selections fail with zero acquisition" $ do
        (selected, allocations, _) <- evalIO newProbe
        let missing = scenario "missing" "No implicit selection" "1" $ expect $ eventually "check" (observe "yes" (Read (RequiresBusinessKey keyName)) id)
            wrongKey = scenario "wrong-key" "Semantic compatibility" "1" $ do
              handle <- correlate (CorrelationAlias "entity") (BusinessKeyName "otherId") (pure "one")
              expect $ eventually "check" (observeSelected handle (RequiresBusinessKey keyName))
            wrongStrategy = scenario "wrong-strategy" "Strategy compatibility" "1" $ do
              handle <- propagateExecutionId
              expect $ eventually "check" (observeSelected handle (RequiresBusinessKey keyName))
        errorsOf (resolveScenario testEnvironment testOptions selected missing) === [UnselectedCorrelation "read"]
        errorsOf (resolveScenario testEnvironment testOptions selected wrongKey) === [IncompatibleCorrelation "read" (CorrelationId "entity")]
        errorsOf (resolveScenario testEnvironment testOptions selected wrongStrategy) === [IncompatibleCorrelation "read" (CorrelationId "execution-id")]
        evalIO (readIORef allocations) >>= (=== 0),
      check "declaration aliases validate separately from step identifiers" $ do
        let source alias key duplicate = scenario "aliases" "Declaration validation" "1" $ do
              node <- given "same" (accept ["ready"] (Seed "one"))
              handle <- correlate alias key (fromRef node)
              if duplicate then correlate alias key (pure "two") >> pure () else pure ()
              expect $ eventually "check" (observeSelected handle (RequiresBusinessKey key))
        assert (not (isLeft (inspectScenario (source (CorrelationAlias "same") keyName False))))
        errorsOf (inspectScenario (source (CorrelationAlias "same") keyName True)) === [DuplicateIdentifier "same"]
        mapM_ (\alias -> assert (isLeft (inspectScenario (source (CorrelationAlias alias) keyName False)))) ["", "execution-id", "a..b"]
        assert (isLeft (inspectScenario (source (CorrelationAlias "valid") (BusinessKeyName "") False))),
      check "returned handles retain their namespace and external handles are not renamed" $ do
        (selected, _, seen) <- evalIO newProbe
        let source = scenario "boundaries" "Lexical handles" "1" $ do
              external <- correlate (CorrelationAlias "external") keyName (pure "outside")
              (_, returned) <- namespace "outer" $ namespace "inner" $ do
                node <- given "node" (accept ["ready"] (Seed "inside"))
                handle <- correlate (CorrelationAlias "local") keyName (fromRef node)
                pure (node, handle)
              namespace "consumer" $ expectAfterActions $ do
                eventually "returned" (observeSelected returned (RequiresBusinessKey keyName))
                eventually "external" (observeSelected external (RequiresBusinessKey keyName))
        VerificationResult {verdict = v, description = description} <- evalIO (run selected source)
        v === Pass
        case description of Description {expectations = expectations} -> map (\(ExpectationDescription _ _ _ _ _ identity) -> identity) expectations === [Just (CorrelationId "outer.inner.local"), Just (CorrelationId "external")]
        (_, observed) <- evalIO (readIORef seen)
        length observed === 2
        mapM_ (\value -> assert (value `elem` observed)) [Just (ByBusinessKey keyName "inside"), Just (ByBusinessKey keyName "outside")],
      check "execution requests are idempotent and propagation is separate from observation selection" $ do
        (selected, _, seen) <- evalIO newProbe
        let source = scenario "execution" "One global execution handle" "1" $ do
              first <- namespace "first" propagateExecutionId
              second <- namespace "second" propagateExecutionId
              business <- correlate (CorrelationAlias "business") keyName (pure "one")
              _ <- act "act" (accept ["done"] (Action False))
              expect $ do
                eventually "execution-observed" (correlatedBy second (observeSelected first RequiresExecutionId))
                eventually "business" (correlatedBy business (observeSelected second (RequiresBusinessKey keyName)))
        VerificationResult {verdict = v, correlations = resolved, policyReport = PolicyReport _ strategies} <- evalIO (run selected source)
        v === Pass
        length resolved === 2
        strategies === Set.fromList [BusinessKey, ExecutionId]
        (actions, observations) <- evalIO (readIORef seen)
        actions === [Just "test-run"]
        length observations === 2
        mapM_ (\value -> assert (value `elem` observations)) [Just (ByExecutionId "test-run"), Just (ByBusinessKey keyName "one")],
      check "unused declarations still contribute policy strategies" $ do
        (selected, _, _) <- evalIO newProbe
        let source = scenario "unused-declarations" "Declared policy inventory" "1" $ do
              handle <- propagateExecutionId
              _ <- correlate (CorrelationAlias "unused") keyName (pure "one")
              expect $ eventually "check" (observeSelected handle RequiresExecutionId)
        VerificationResult {policyReport = PolicyReport _ strategies} <- evalIO (run selected source)
        strategies === Set.fromList [BusinessKey, ExecutionId],
      check "absent execution declaration supplies no action execution ID" $ do
        (selected, _, seen) <- evalIO newProbe
        let source = scenario "no-propagation" "No implicit propagation" "1" $ do
              handle <- correlate (CorrelationAlias "business") keyName (pure "one")
              _ <- act "act" (accept ["done"] (Action False))
              expect $ eventually "check" (observeSelected handle (RequiresBusinessKey keyName))
        _ <- evalIO (run selected source)
        (actions, _) <- evalIO (readIORef seen)
        actions === [Nothing],
      check "terminal action failure suppresses even unresolved selections as prerequisites" $ do
        (selected, _, _) <- evalIO newProbe
        let source = scenario "terminal" "Terminal precedence" "1" $ do
              handle <- correlate (CorrelationAlias "lost") keyName (pure "")
              _ <- act "stop" (accept ["done"] (Action True))
              expect $ eventually "check" (observeSelected handle (RequiresBusinessKey keyName))
        VerificationResult {expectations = children} <- evalIO (run selected source)
        map (\ExpectationResult {reason = why} -> why) children === [PrerequisiteUnavailable],
      check "public declaration and selection changes affect digest while private values do not" $ do
        (selected, _, _) <- evalIO newProbe
        let source alias key useExecution useSecond useOtherNode private = scenario "digest" "Public identity" "1" $ do
              first <- given "first" (accept ["ready"] (Seed private))
              second <- given "second" (accept ["ready"] (Seed private))
              handle <- correlate alias key (fromRef (if useOtherNode then second else first))
              other <- correlate (CorrelationAlias "other") key (fromRef first)
              execution <- if useExecution then Just <$> propagateExecutionId else pure Nothing
              let chosen = case execution of Just handle' -> handle'; Nothing -> if useSecond then other else handle
                  requirement = if useExecution then RequiresExecutionId else RequiresBusinessKey key
              expect $ eventually "check" (observeSelected chosen requirement)
            standard = source (CorrelationAlias "entity") keyName False False False
        baseline@VerificationResult {descriptionDigest = digest, description = description} <- evalIO (run selected (standard "PRIVATE-A"))
        VerificationResult {descriptionDigest = same} <- evalIO (run selected (standard "PRIVATE-B"))
        digest === same
        assert (not (Text.isInfixOf "PRIVATE-A" (Text.pack (show (descriptionValue description)))))
        mapM_
          ( \changed -> do
              VerificationResult {descriptionDigest = other} <- evalIO (run selected changed)
              assert (other /= digest)
          )
          [ source (CorrelationAlias "renamed") keyName False False False "PRIVATE-A",
            source (CorrelationAlias "entity") (BusinessKeyName "otherId") False False False "PRIVATE-A",
            source (CorrelationAlias "entity") keyName True False False "PRIVATE-A",
            source (CorrelationAlias "entity") keyName False True False "PRIVATE-A",
            source (CorrelationAlias "entity") keyName False False True "PRIVATE-A"
          ]
        decodeRunResult (encodeRunResult (Verification baseline)) === Right (Verification baseline)
    ]
  where
    check :: String -> PropertyT IO () -> TestTree
    check label = testPropertyNamed label (fromString label) . withTests 1 . property
    errorsOf (Left errors) = errors
    errorsOf (Right _) = []
