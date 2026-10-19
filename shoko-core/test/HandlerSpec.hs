{-# LANGUAGE RankNTypes #-}

module HandlerSpec (tests) where

import Consumer.Account (testEnvironment, testOptions)
import Consumer.Hooks (newMicroClock)
import Data.IORef
import Data.String (fromString)
import Data.Time (UTCTime (..), fromGregorian)
import Hedgehog (PropertyT, assert, evalIO, property, withTests, (===))
import Shoko
import Shoko.Clock
import Shoko.Evidence
import Shoko.Result hiding (binding)
import Shoko.Result.Json
import Test.Tasty
import Test.Tasty.Hedgehog

data Probe a where
  Seed :: Probe Bool
  BlindAction :: Input Bool -> Probe Bool
  BlindRead :: Input Bool -> Probe Bool
  ReadSource :: SourceId -> CoverageStrength -> Probe Bool
  Broken :: HandlerBuildError -> Probe Bool

instance Vocabulary Probe where
  describeOperation Seed = declareOperation "seed" []
  describeOperation (BlindAction _) = declareOperation "blind-action" []
  describeOperation (BlindRead _) = declareOperation "blind-read" []
  describeOperation (ReadSource _ _) = declareOperation "read-source" []
  describeOperation (Broken _) = declareOperation "broken" []

probeBinding :: IORef Int -> Binding Probe ()
probeBinding calls = probeBindingRecording (const (pure ())) calls

probeBindingRecording :: (InputResolutionError -> IO ()) -> IORef Int -> Binding Probe ()
probeBindingRecording record calls = binding "probe" (\_ -> modifyIORef' calls (+ 1)) (const (pure Cleaned)) handlers
  where
    handlers :: OperationRole -> Probe a -> Either HandlerBuildError (Maybe (Handler () a))
    handlers FixtureOperation Seed = Right (Just (actionHandler noRequirements (\_ _ -> pure (ActionObserved "ready" True))))
    handlers ActionOperation (BlindAction input) =
      Right
        ( Just
            ( actionHandler
                noRequirements
                ( \_ call -> do
                    answer <- resolveInput call input
                    case answer of Left failure -> record failure; Right _ -> pure ()
                    pure (ActionObserved "ready" True)
                )
            )
        )
    handlers ObservationOperation (BlindRead input) =
      Right
        ( Just
            ( readHandler
                (SourceId "probe")
                SampledState
                ( \call -> do
                    _ <- resolveInput call input
                    pure True
                )
            )
        )
    handlers ObservationOperation (ReadSource label strength) = Right (Just (readHandler label strength (const (pure True))))
    handlers _ (Broken cause) = Left cause
    handlers _ _ = Right Nothing
    readHandler label strength get = observationHandler
      noRequirements
      (RequiresBusinessKey (BusinessKeyName "probe"))
      ( newSource
          label
          strength
          ( \_ clock -> do
              tick <- monotonic clock
              pure (Right (Baseline label tick Nothing))
          )
      )
      $ \_ call -> do
        value <- get call
        tick <- monotonic (callClock call)
        pure (Observed [Occurrence (Just "one") value] (Coverage strength tick tick True))

runProbe :: Binding Probe () -> Scenario Probe -> IO RunResult
runProbe selected source = do
  (clock, _) <- newMicroClock (UTCTime (fromGregorian 2026 10 18) 0)
  resolved <- either (fail . show) pure (resolveScenario testEnvironment testOptions selected source)
  runScenario clock (LogicalInput "probe" []) resolved

tests :: TestTree
tests =
  testGroup
    "handler-owned contracts and sources"
    [ check "ignored undeclared action input cannot pass or dispatch later steps" $ do
        calls <- evalIO (newIORef 0)
        let source = scenario "denied-action" "Sticky input diagnostics" "1" $ do
              selectedCorrelation <- correlate (CorrelationAlias "probe") (BusinessKeyName "probe") (pure "one")
              seed <- given "fixture" (accept ["ready"] Seed)
              _ <- act "blind" (accept ["ready"] (BlindAction (fromRef seed)))
              _ <- act "later" (accept ["ready"] (BlindAction (pure True)))
              expect $ eventually "check" (correlatedBy selectedCorrelation $ observe "yes" (ReadSource (SourceId "probe") SampledState) id)
        result <- evalIO (runProbe (probeBinding calls) source)
        case result of
          Verification VerificationResult {actions = actions, verdict = v} -> do
            v === Unknown
            map (\ActionEvidence {reason = why} -> why) actions === [Satisfied, UndeclaredOperation]
          _ -> fail "expected verification",
      check "undeclared input errors retain the first denied dependency in input order" $ do
        calls <- evalIO (newIORef 0)
        failures <- evalIO (newIORef [])
        let source = scenario "input-order" "Typed denied references" "1" $ do
              first <- given "first" (accept ["ready"] Seed)
              second <- given "second" (accept ["ready"] Seed)
              handle <- correlate (CorrelationAlias "probe") (BusinessKeyName "probe") (pure "one")
              _ <- act "blind" (accept ["ready"] (BlindAction ((&&) <$> fromRef first <*> fromRef second)))
              expect $ eventually "check" (correlatedBy handle $ observe "yes" (ReadSource (SourceId "probe") SampledState) id)
        _ <- evalIO (runProbe (probeBindingRecording (\failure -> modifyIORef' failures (++ [failure])) calls) source)
        evalIO (readIORef failures) >>= (=== [UndeclaredInputReference "first"]),
      check "ignored undeclared observation input is Unknown" $ do
        calls <- evalIO (newIORef 0)
        let source = scenario "denied-read" "Sticky observation diagnostic" "1" $ do
              selectedCorrelation <- correlate (CorrelationAlias "probe") (BusinessKeyName "probe") (pure "one")
              seed <- given "fixture" (accept ["ready"] Seed)
              expect $ eventually "check" (correlatedBy selectedCorrelation $ observe "yes" (BlindRead (fromRef seed)) id)
        result <- evalIO (runProbe (probeBinding calls) source)
        case result of
          Verification VerificationResult {expectations = children} -> map (\ExpectationResult {reason = why} -> why) children === [UndeclaredOperation]
          _ -> fail "expected verification",
      check "inconsistent source strength fails before allocation" $ do
        calls <- evalIO (newIORef 0)
        let source = scenario "sources" "Source consistency" "1" $ do
              selectedCorrelation <- correlate (CorrelationAlias "probe") (BusinessKeyName "probe") (pure "one")
              expect $ do
                eventually "sampled" (correlatedBy selectedCorrelation $ observe "yes" (ReadSource (SourceId "same") SampledState) id)
                eventually "durable" (correlatedBy selectedCorrelation $ observe "yes" (ReadSource (SourceId "same") DurableHistory) id)
        resolveScenario testEnvironment testOptions (probeBinding calls) source `isErrors` [InconsistentSource (SourceId "same")]
        evalIO (readIORef calls) >>= (=== 0),
      check "empty source and wrong handler kind reject before acquisition" $ do
        calls <- evalIO (newIORef 0)
        let source label = scenario "source-kind" "Owned source validation" "1" $ do
              handle <- correlate (CorrelationAlias "probe") (BusinessKeyName "probe") (pure "one")
              expect $ eventually "check" (correlatedBy handle $ observe "yes" (ReadSource label SampledState) id)
            replace :: OperationRole -> Probe a -> Maybe (Handler () a) -> Maybe (Handler () a)
            replace ObservationOperation (ReadSource _ _) _ = Just (actionHandler noRequirements (\_ _ -> pure (ActionObserved "observed" True)))
            replace _ _ original = original
        resolveScenario testEnvironment testOptions (probeBinding calls) (source (SourceId "")) `isErrors` [MissingSource "read-source"]
        resolveScenario testEnvironment testOptions (adjustHandlers replace (probeBinding calls)) (source (SourceId "valid")) `isErrors` [MissingHandler "read-source"]
        evalIO (readIORef calls) >>= (=== 0),
      check "combined bindings preserve every typed construction cause before acquisition" $ do
        calls <- evalIO (newIORef 0)
        mapM_
          ( \cause -> do
              let source = scenario "combined-cause" "Construction errors survive sums" "1" $ do
                    handle <- correlate (CorrelationAlias "probe") (BusinessKeyName "probe") (pure "one")
                    expect $ eventually "check" (correlatedBy handle $ observe "yes" (InR (Broken cause)) id)
              resolveScenario testEnvironment testOptions (combineBindings "combined" (probeBinding calls) (probeBinding calls)) source `isErrors` [HandlerConstructionFailed "broken" cause]
          )
          [EndpointNotAllowlisted "public", ObservationMethodNotGet "write", ObservationScopeMissing "scope", ExecutionMetadataUnsupported]
        evalIO (readIORef calls) >>= (=== 0),
      check "typed construction causes survive preflight and closed JSON" $ do
        calls <- evalIO (newIORef 0)
        mapM_
          ( \cause -> do
              let source = scenario "broken-scenario" "Invalid handler" "1" $ do
                    selectedCorrelation <- correlate (CorrelationAlias "probe") (BusinessKeyName "probe") (pure "one")
                    expect $ eventually "check" (correlatedBy selectedCorrelation $ observe "yes" (Broken cause) id)
                  expected = [HandlerConstructionFailed "broken" cause]
              resolveScenario testEnvironment testOptions (adjustHandlers (\_ _ -> id) (probeBinding calls)) source `isErrors` expected
              decodeRunResult (encodeRunResult (PreflightFailure expected)) === Right (PreflightFailure expected)
          )
          [EndpointNotAllowlisted "public-endpoint", ObservationMethodNotGet "write", ObservationScopeMissing "unscoped", ExecutionMetadataUnsupported]
        assert (either (const True) (const False) (decodeRunResult "{\"schemaVersion\":1,\"kind\":\"preflight-error\",\"errors\":[]}")),
      check "focus projects baseline capture and execution to the same resource" $ do
        captured <- evalIO (newIORef False)
        let inner :: Handler (IORef Bool) Bool
            inner =
              observationHandler
                noRequirements
                (RequiresBusinessKey (BusinessKeyName "probe"))
                ( newSource
                    (SourceId "focused")
                    SampledState
                    ( \resource clock -> do
                        writeIORef resource True
                        tick <- monotonic clock
                        pure (Right (Baseline (SourceId "focused") tick Nothing))
                    )
                )
                ( \resource call -> do
                    value <- readIORef resource
                    tick <- monotonic (callClock call)
                    pure (Observed [Occurrence Nothing value] (Coverage SampledState tick tick True))
                )
            handlers :: OperationRole -> Probe a -> Either HandlerBuildError (Maybe (Handler ((), IORef Bool) a))
            handlers ObservationOperation (ReadSource _ _) = Right (Just (focus snd inner))
            handlers _ _ = Right Nothing
            selected = binding "focused" (const (pure ((), captured))) (const (pure Cleaned)) handlers
            source = scenario "focus" "Focused source" "1" $ do
              selectedCorrelation <- correlate (CorrelationAlias "probe") (BusinessKeyName "probe") (pure "one")
              expect $ eventually "check" (correlatedBy selectedCorrelation $ observe "yes" (ReadSource (SourceId "ignored") SampledState) id)
        (clock, _) <- evalIO (newMicroClock (UTCTime (fromGregorian 2026 10 18) 0))
        resolved <- either (fail . show) pure (resolveScenario testEnvironment testOptions selected source)
        result <- evalIO (runScenario clock (LogicalInput "focus" []) resolved)
        case result of Verification VerificationResult {verdict = v} -> v === Pass; _ -> fail "expected verification",
      check "detached inputs and substeps are refused and fake time advances by Duration" $ do
        (clock, advance) <- evalIO (newFakeClock (UTCTime (fromGregorian 2026 10 18) 0))
        let call = detachedCallContext clock (MonotonicTime 10000) (MonotonicTime 10000) Nothing Nothing
        evalIO (resolveInput call (pure True)) >>= (=== Left DetachedInputContext)
        evalIO (runSubstep call "no" (pure True)) >>= (=== Left "detached-substep")
        duration <- either (fail . show) pure (milliseconds 2)
        evalIO (advance duration)
        evalIO (monotonic clock) >>= (=== MonotonicTime 2000)
    ]
  where
    check :: String -> PropertyT IO () -> TestTree
    check label = testPropertyNamed label (fromString label) . withTests 1 . property
    isErrors result expected = case result of Left errors -> errors === expected; Right _ -> fail "preflight unexpectedly succeeded"
