module ConcurrentSpec (tests) where

import Consumer.Account (testOptions)
import Consumer.Idempotency hiding (rendezvous)
import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (cancel, waitCatch, withAsync)
import Control.Concurrent.MVar
import Control.Exception (finally)
import Control.Monad (when)
import Data.Either (isLeft)
import Data.IORef
import Data.Set qualified as Set
import Data.Text qualified as Text
import Hedgehog (Property, PropertyT, assert, evalIO, property, withTests, (===))
import Shoko hiding (binding)
import Shoko qualified
import Shoko.Clock
import Shoko.Evidence
import Shoko.Result
import Shoko.Scenario hiding (predicate)
import System.Timeout (timeout)
import Test.Tasty
import Test.Tasty.Hedgehog

tests :: TestTree
tests =
  testGroup
    "concurrent actions"
    [ testPropertyNamed "atomic duplicate handling passes" "atomic" $ once $ do
        result <- evalIO $ execute realClock (ordersBindingFor Idempotent False 3) concurrentDuplicates
        reasons result === [Satisfied, Satisfied, Satisfied],
      testPropertyNamed "race-prone concurrent duplicates deterministically fail all invariants" "race" $ once $ do
        result <- evalIO $ execute realClock (ordersBindingFor RaceProne False 3) concurrentDuplicates
        reasons result === [Mismatch, Mismatch, Mismatch],
      testPropertyNamed "race-prone sequential replay passes" "sequentialControl" $ once $ do
        result <- evalIO $ execute realClock (ordersBindingFor RaceProne False 1) retryScenario
        reasons result === [Satisfied, Satisfied],
      testPropertyNamed "preflight opt-in precedes acquisition" "optIn" $ once $ do
        acquired <- evalIO (newIORef False)
        let selectedBinding = Shoko.binding "not-concurrent" (\_ -> writeIORef acquired True) (const (pure Cleaned)) (\_ (Run _ _) -> Right $ Just $ actionHandler noRequirements (\_ _ -> pure (ActionObserved "done" True)))
        case resolveScenario concurrentEnvironment testOptions selectedBinding (program (concurrently "burst" (act "attempt-1" (accept ["done"] (Run 1 Healthy)) >> pure ()) >> expect (holds "yes" (pure True) (predicate "yes" id)))) of
          Left errors -> errors === [ConcurrentCallsUnsupported "attempt-1"]
          Right _ -> fail "missing opt-in was accepted"
        evalIO (readIORef acquired) >>= (=== False),
      testPropertyNamed "instrumented handlers overlap and evidence follows declaration order" "overlap" $ once $ do
        events <- evalIO (newIORef [])
        barrier <- evalIO (rendezvous 3)
        let handler :: Int -> CallContext -> IO (ActionOutcome Bool)
            handler n _ = do
              barrier
              threadDelay ((4 - n) * 20000)
              atomicModifyIORef' events (\old -> (old ++ [n], ()))
              pure (ActionObserved "done" True)
        result <- evalIO $ execute realClock (probeBinding (const (pure Cleaned)) handler) three
        evalIO (readIORef events) >>= (=== [3, 2, 1])
        let evidence = actionsOf result
        map (\ActionEvidence {nodeId = key} -> key) evidence === ["one", "two", "three"]
        let starts = [tick | ActionEvidence {startedAt = tick} <- evidence]
            ends = [tick | ActionEvidence {finishedAt = tick} <- evidence]
        assert (maximum starts < minimum ends),
      testPropertyNamed "member faults settle admitted siblings and block later stages" "faultSiblings" $ once $ do
        finished <- evalIO (newIORef [])
        barrier <- evalIO (rendezvous 3)
        let handler n _ = do
              when (n < 4) barrier
              if n == 1
                then fail "SECRET-CONCURRENT-FAULT"
                else do
                  threadDelay 10000
                  atomicModifyIORef' finished (\old -> (old ++ [n], ()))
                  pure (ActionObserved "done" True)
            selected = program $ do
              groupThree
              _ <- act "later" (accept ["done"] (Run 4 Healthy))
              expect $ holds "check" (pure True) (predicate "yes" id)
        result <- evalIO $ execute realClock (probeBinding (const (pure Cleaned)) handler) selected
        case result of RunnerFault UnexpectedRunnerFault (Just _) -> pure (); _ -> fail (show result)
        let evidence = actionsOf result
        map (\ActionEvidence {reason = why} -> why) evidence === [UnexpectedRunnerFault, Satisfied, Satisfied]
        completed <- evalIO (readIORef finished)
        assert (2 `elem` completed && 3 `elem` completed && 4 `notElem` completed)
        reasons result === [PrerequisiteUnavailable],
      testPropertyNamed "lazy public-summary faults cannot cancel siblings" "lazyFault" $ once $ do
        finished <- evalIO (newIORef (0 :: Int))
        barrier <- evalIO (rendezvous 3)
        let handler n _ = do
              barrier
              if n == 1
                then pure (ActionObservedWithDetails "done" True [("count", PublicCount (error "SECRET-LAZY"))])
                else do
                  atomicModifyIORef' finished (\old -> (old + 1, ()))
                  pure (ActionObserved "done" True)
        result <- evalIO $ execute realClock (probeBinding (const (pure Cleaned)) handler) three
        length (actionsOf result) === 3
        evalIO (readIORef finished) >>= (=== 2)
        case actionsOf result of ActionEvidence {reason = why} : _ -> why === UnexpectedRunnerFault; _ -> fail "missing fault",
      testPropertyNamed "cancellation joins every member before finalization" "cancellation" $ once $ do
        barrier <- evalIO (rendezvous 3)
        entered <- evalIO newEmptyMVar
        active <- evalIO (newIORef (0 :: Int))
        cleanupActive <- evalIO (newIORef (-1))
        let handler _ _ =
              ( do
                  atomicModifyIORef' active (\n -> (n + 1, ()))
                  barrier
                  _ <- tryPutMVar entered ()
                  threadDelay 10000000
                  pure (ActionObserved "done" True)
              )
                `finally` atomicModifyIORef' active (\n -> (n - 1, ()))
            release _ = readIORef active >>= writeIORef cleanupActive >> pure Cleaned
        outcome <- evalIO $ withAsync (execute realClock (probeBinding release handler) three) $ \worker -> do
          ready <- timeout 1000000 (readMVar entered)
          case ready of Nothing -> fail "members did not enter"; Just () -> cancel worker >> waitCatch worker
        assert (isLeft outcome)
        evalIO (readIORef active) >>= (=== 0)
        evalIO (readIORef cleanupActive) >>= (=== 0),
      testPropertyNamed "group deadline settles members and suppresses expectations" "deadline" $ once $ do
        entered <- evalIO (newIORef (0 :: Int))
        let handler _ _ = do
              atomicModifyIORef' entered (\n -> (n + 1, ()))
              threadDelay 10000000
              pure (ActionObserved "done" True)
        result <- evalIO $ execute realClock (probeBinding (const (pure Cleaned)) handler) three
        map (\ActionEvidence {reason = why} -> why) (actionsOf result) === replicate 3 DeadlineExceeded
        reasons result === [PrerequisiteUnavailable],
      testPropertyNamed "cancellation during admission leaves no handler or worker running" "admissionCancellation" $ once $ do
        arrivals <- evalIO (newIORef (0 :: Int))
        allWaiting <- evalIO newEmptyMVar
        blocked <- evalIO newEmptyMVar
        calls <- evalIO (newIORef (0 :: Int))
        let Clock now wall sleep bound = realClock
            admissionClock = Clock now wall sleep $ \end action -> bound end $ do
              count <- atomicModifyIORef' arrivals (\n -> (n + 1, n + 1))
              when (count >= 2 && count <= 4) $ do
                when (count == 4) (putMVar allWaiting ())
                readMVar blocked
              action
            handler _ _ = atomicModifyIORef' calls (\n -> (n + 1, ())) >> pure (ActionObserved "done" True)
        outcome <- evalIO $ withAsync (execute admissionClock (probeBinding (const (pure Cleaned)) handler) three) $ \worker -> do
          ready <- timeout 1000000 (readMVar allWaiting)
          case ready of Nothing -> fail "members did not await admission"; Just () -> cancel worker >> waitCatch worker
        assert (isLeft outcome)
        evalIO (readIORef calls) >>= (=== 0),
      testPropertyNamed "opt-in survives focus contract adjustment and composition" "preservation" $ once $ do
        let handler = allowConcurrentCalls (actionHandler noRequirements (\() _ -> pure (ActionObserved "done" True)))
        assert (handlerAllowsConcurrentCalls (focus fst (adjustContract (requiring [WriteState]) handler)))
        let both = combineBindings "pair" (probeBinding (const (pure Cleaned)) (\_ _ -> pure (ActionObserved "done" True))) (ordersBinding Idempotent)
        case bindingHandler both ActionOperation (InL (Run 1 Healthy)) of
          Right (Just combined) -> assert (handlerAllowsConcurrentCalls combined)
          _ -> fail "missing composed handler"
        let observation = observationHandler noRequirements RequiresExecutionId (sampledSource (SourceId "test")) (\() _ -> pure (ObservationUnavailable "unused"))
        assert (not (handlerAllowsConcurrentCalls (allowConcurrentCalls observation))),
      testPropertyNamed "invalid group constructs are all rejected" "invalidGroups" $ once $ mapM_ checkInvalid invalidGroups,
      testPropertyNamed "empty group label segments are invalid identifiers" "groupLabels" $ once $ do
        let selected = program $ do
              concurrently "bad..group" (act "member" (accept ["done"] (Run 1 Healthy)) >> pure ())
              expect $ holds "yes" (pure True) (predicate "yes" id)
        case inspectScenario selected of Left errors -> assert (InvalidIdentifier `elem` errors); Right _ -> fail "invalid label accepted",
      testPropertyNamed "qualified group labels and hoisting preserve membership" "qualification" $ once $ do
        let selected :: Scenario (Probe :+: Orders)
            selected = scenario "hoisted" "Hoisted group" "1" $ do
              namespace "x" $ hoistScenarioBuilder InL groupThree
              expect $ holds "yes" (pure True) (predicate "yes" id)
        case inspectScenario selected of
          Right Description {nodes = nodes} -> do
            map (\NodeDescription {group = group} -> group) nodes === replicate 3 (Just "x.burst")
            map (\NodeDescription {nodeId = key} -> key) nodes === ["x.one", "x.two", "x.three"]
          Left errors -> fail (show errors)
    ]

data Mode = Healthy

data Probe a where
  Run :: Int -> Mode -> Probe Bool

instance Vocabulary Probe where
  describeOperation (Run _ _) = declareOperation "probe.run" []

probeBinding :: (() -> IO Disposition) -> (Int -> CallContext -> IO (ActionOutcome Bool)) -> Binding Probe ()
probeBinding release handler = Shoko.binding "probe" (const (pure ())) release $ \_ (Run n _) -> Right $ Just $ allowConcurrentCalls (actionHandler noRequirements (\_ -> handler n))

program :: ScenarioBuilder Probe () -> Scenario Probe
program = scenario "concurrent" "Concurrent stages" "1"

groupThree :: ScenarioBuilder Probe ()
groupThree = concurrently "burst" $ do
  _ <- act "one" (accept ["done"] (Run 1 Healthy))
  _ <- act "two" (accept ["done"] (Run 2 Healthy))
  _ <- act "three" (accept ["done"] (Run 3 Healthy))
  pure ()

three :: Scenario Probe
three = program $ do
  groupThree
  expect $ holds "check" (pure True) (predicate "yes" id)

concurrentEnvironment :: Environment
concurrentEnvironment = Environment "local" False (Set.fromList [minBound .. maxBound]) (Policy (duration 1500) (duration 100) (duration 10) (duration 200))

duration :: Int -> Duration
duration = either (error . Text.unpack) id . milliseconds

execute :: (Vocabulary op) => Clock -> Binding op resource -> Scenario op -> IO RunResult
execute clock binding selected = case resolveScenario concurrentEnvironment testOptions binding selected of
  Left errors -> fail (show errors)
  Right resolved -> runScenario clock (LogicalInput "concurrent" []) resolved

rendezvous :: Int -> IO (IO ())
rendezvous expected = do
  arrivals <- newIORef (0 :: Int)
  gate <- newEmptyMVar
  pure $ do
    count <- atomicModifyIORef' arrivals (\n -> (n + 1, n + 1))
    when (count == expected) (putMVar gate ())
    ready <- timeout 1000000 (readMVar gate)
    case ready of Nothing -> fail "rendezvous timeout"; Just () -> pure ()

once :: PropertyT IO () -> Property
once = withTests 1 . property

actionsOf :: RunResult -> [ActionEvidence]
actionsOf (Verification VerificationResult {actions = results}) = results
actionsOf (RunnerFault _ (Just VerificationResult {actions = results})) = results
actionsOf _ = []

reasons :: RunResult -> [Reason]
reasons (Verification VerificationResult {expectations = results}) = map (\ExpectationResult {reason = why} -> why) results
reasons (RunnerFault _ (Just VerificationResult {expectations = results})) = map (\ExpectationResult {reason = why} -> why) results
reasons _ = []

invalidGroups :: [ScenarioBuilder Orders ()]
invalidGroups =
  [ concurrently "burst" (pure ()),
    concurrently "burst" (given "fixture" (accept ["issued"] NewKey) >> pure ()),
    concurrently "burst" (expect (holds "yes" (pure True) (predicate "yes" id))),
    concurrently "burst" (expectAfterActions (holds "yes" (pure True) (predicate "yes" id))),
    concurrently "burst" (correlate (CorrelationAlias "x") (BusinessKeyName "x") (pure "x") >> pure ()),
    concurrently "burst" (propagateExecutionId >> pure ()),
    concurrently "burst" (concurrently "nested" (act "action" (accept ["issued"] NewKey) >> pure ())),
    concurrently
      "burst"
      ( do
          key <- act "first" (accept ["issued"] NewKey)
          _ <- act "second" (accept ["created"] (Submit (fromRef key) (pure "payload")))
          pure ()
      ),
    do
      concurrently "burst" (act "action" (accept ["issued"] NewKey) >> pure ())
      concurrently "burst" (act "another" (accept ["issued"] NewKey) >> pure ())
  ]

checkInvalid :: ScenarioBuilder Orders () -> PropertyT IO ()
checkInvalid body = case inspectScenario (scenario "invalid" "Invalid group" "1" (body >> expect (holds "yes" (pure True) (predicate "yes" id)))) of
  Left errors -> assert (InvalidConcurrentGroup "burst" `elem` errors || DuplicateIdentifier "burst" `elem` errors)
  Right _ -> fail "invalid group accepted"
