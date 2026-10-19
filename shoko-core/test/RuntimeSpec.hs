{-# LANGUAGE RankNTypes #-}

module RuntimeSpec (tests) where

import Consumer.Account
import Consumer.Composed qualified as Composed
import Consumer.DeliveryLedger (ledgerEnvironment)
import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (cancel, waitCatch, withAsync)
import Control.Concurrent.MVar
import Data.Either (isLeft)
import Data.IORef
import Data.Text qualified as Text
import Data.Time (UTCTime (..), fromGregorian)
import Hedgehog (PropertyT, assert, evalIO, property, withTests, (===))
import Shoko
import Shoko.Clock
import Shoko.Evidence
import Shoko.Result
import System.Timeout (timeout)
import Test.Tasty
import Test.Tasty.Hedgehog

tests :: TestTree
tests =
  testGroup
    "execution boundaries"
    [ testPropertyNamed "deferred observation waits for the final action" "deferredOrder" $ withTests 1 $ property $ do
        events <- evalIO (newIORef [])
        (clock, _) <- evalIO (newFakeClock epoch)
        case resolveScenario testEnvironment testOptions (BusinessKeyFrom "registrationId" (pure "registration")) (Composed.composedBinding events) Composed.composedScenario of
          Left errors -> fail (show errors)
          Right resolved -> do
            result <- evalIO (runScenario clock (LogicalInput "blocks" []) resolved)
            resultVerdict result === Just Pass
            evalIO (readIORef events) >>= (=== ["qualified", "qualified", "agent", "finished", "polled"]),
      testPropertyNamed "nested blocks return references and accept external inputs" "nestedReferences" $ withTests 1 $ property $ do
        events <- evalIO (newIORef [])
        (clock, _) <- evalIO (newFakeClock epoch)
        let selected = scenario "nested" "Nested references" "v1" $ do
              outside <- Composed.qualifiedAgent
              returned <- namespace "outer" $ namespace "inner" $ Composed.completeRegistration outside
              _ <- act "finish" (accept ["finished"] (Composed.Finish (fromRef returned)))
              pure ()
        case resolveScenario testEnvironment testOptions (BusinessKeyFrom "registrationId" (pure "registration")) (Composed.composedBinding events) selected of
          Left errors -> fail (show errors)
          Right resolved -> evalIO (runScenario clock (LogicalInput "nested" []) resolved) >>= (\result -> resultVerdict result === Just Pass),
      testPropertyNamed "inclusive observation deadline" "deadlineBoundary" $ withTests 1 $ property $ do
        before <- evalIO (boundary 29999)
        at <- evalIO (boundary 30000)
        afterDeadline <- evalIO (boundary 30001)
        resultVerdict before === Just Pass
        resultVerdict at === Just Pass
        assert (resultVerdict afterDeadline /= Just Pass),
      testPropertyNamed "terminal mismatch and transport uncertainty suppress later mutations" "terminalActions" $ withTests 1 $ property $ do
        forMTest [False, True] $ \transport -> do
          calls <- evalIO (newIORef 0)
          (clock, _) <- evalIO (newFakeClock epoch)
          let Binding n caps describe acquire release baseline action observation = memoryBinding calls
              override :: AccountStore -> CallContext -> Account a -> IO (ActionOutcome a)
              override _ _ (Create _ False) =
                pure $
                  if transport then ActionUnavailable "SECRET-TRANSPORT-SENTINEL" else ActionObserved "unexpected-success" "toy-key"
              override resource context op = action resource context op
              binding = Binding n caps describe acquire release baseline override observation
              selected = scenario "terminal" "Stop after uncertain or mismatched action" "v1" $ do
                agent <- given "agent" (accept ["ready"] Qualified)
                _ <- act "first" (accept ["invalid-input"] (Create (fromRef agent) False))
                later <- act "later" (accept ["created"] (Create (fromRef agent) True))
                expect $ eventually "later-exists" (observe "created" (Created (fromRef later)) id)
          result <- evalIO (runAccount clock binding selected)
          resultVerdict result === Just (if transport then Unknown else Fail)
          evalIO (readIORef calls) >>= (=== 1)
          assert (not (Text.isInfixOf "SECRET-TRANSPORT-SENTINEL" (Text.pack (show result)))),
      testPropertyNamed "undeclared composite substep never executes" "undeclaredSubstep" $ withTests 1 $ property $ do
        calls <- evalIO (newIORef 0)
        (clock, _) <- evalIO (newFakeClock epoch)
        let Binding n caps describe acquire release baseline action observation = memoryBinding calls
            override :: AccountStore -> CallContext -> Account a -> IO (ActionOutcome a)
            override _ (CallContext _ _ _ _ runSubstep _ _) (Create _ _) = do
              _ <- runSubstep "undeclared-write" (modifyIORef' calls (+ 100))
              pure (ActionObserved "created" "toy-key")
            override resource context op = action resource context op
        result <- evalIO (runAccount clock (Binding n caps describe acquire release baseline override observation) accountScenario)
        resultVerdict result === Just Unknown
        evalIO (readIORef calls) >>= (=== 1),
      testPropertyNamed "cleanup failure preserves Fail and changes Pass to Unknown" "cleanupVerdict" $ withTests 1 $ property $ do
        calls <- evalIO (newIORef 0)
        (clock, _) <- evalIO (newFakeClock epoch)
        let Binding n caps describe acquire _ baseline action observation = memoryBinding calls
            binding = Binding n caps describe acquire (const (pure CleanupFailed)) baseline action observation
        result <- evalIO (runAccount clock binding accountScenario)
        resultVerdict result === Just Unknown
        let wrongContract = scenario "wrong-contract" "Unexpected rejection remains Fail" "v1" $ do
              agent <- given "agent" (accept ["ready"] Qualified)
              rejected <- act "create" (accept ["created"] (Create (fromRef agent) False))
              expect $ eventually "exists" (observe "exists" (Created (fromRef rejected)) id)
        failed <- evalIO (runAccount clock binding wrongContract)
        resultVerdict failed === Just Fail,
      testPropertyNamed "blocked cleanup cannot extend its grace budget" "cleanupBudget" $ withTests 1 $ property $ do
        calls <- evalIO (newIORef 0)
        let Binding n caps describe acquire _ baseline action observation = memoryBinding calls
            release _ = threadDelay 10000000 >> pure Cleaned
            binding = Binding n caps describe acquire release baseline action observation
            Clock now _ _ _ = realClock
        started <- evalIO now
        result <- evalIO (runAccount realClock binding accountScenario)
        finished <- evalIO now
        resultVerdict result === Just Unknown
        assert (finished - started < 1000000)
        case result of
          Verification VerificationResult {disposition = cleanup} -> cleanup === [CleanupTimedOut]
          _ -> fail "expected a verification result",
      testPropertyNamed "real cancellation finalizes and remains cancellation" "realCancellation" $ withTests 1 $ property $ do
        calls <- evalIO (newIORef 0)
        released <- evalIO (newIORef False)
        entered <- evalIO newEmptyMVar
        let Binding n caps describe acquire _ baseline action observation = memoryBinding calls
            blocking :: AccountStore -> CallContext -> Account a -> IO (ActionOutcome a)
            blocking _ _ (Create _ _) = putMVar entered () >> threadDelay 10000000 >> pure (ActionObserved "created" "toy-key")
            blocking resource context op = action resource context op
            binding = Binding n caps describe acquire (\_ -> writeIORef released True >> pure Cleaned) baseline blocking observation
        outcome <- evalIO $ withAsync (runAccount realClock binding accountScenario) $ \worker -> do
          started <- timeout 1000000 (takeMVar entered)
          case started of
            Nothing -> fail "action did not start"
            Just () -> cancel worker >> waitCatch worker
        assert (isLeft outcome)
        evalIO (readIORef released) >>= (=== True),
      testPropertyNamed "partial acquisition finalizer survives timeout" "partialAcquisition" $ withTests 1 $ property $ do
        calls <- evalIO (newIORef 0)
        disposed <- evalIO (newIORef False)
        let Binding n caps describe originalAcquire release baseline action observation = memoryBinding calls
            acquire register = do
              register (writeIORef disposed True >> pure Cleaned)
              threadDelay 10000000
              originalAcquire register
            binding = Binding n caps describe acquire release baseline action observation
        result <- evalIO (runAccount realClock binding accountScenario)
        resultVerdict result === Just Unknown
        evalIO (readIORef disposed) >>= (=== True),
      testPropertyNamed "slow sibling cannot delay a fast sibling activation" "siblingFairness" $ withTests 1 $ property $ do
        calls <- evalIO (newIORef 0)
        let Binding n caps describe acquire release baseline action observation = memoryBinding calls
            readBoth :: AccountStore -> CallContext -> Account a -> IO (ObservationOutcome a)
            readBoth resource context@(CallContext resolve _ _ _ _ _ _) op@(Created input) = case resolve input of
              Right "slow" -> threadDelay 10000000 >> observation resource context op
              _ -> observation resource context op
            readBoth resource context op = observation resource context op
            binding = Binding n caps describe acquire release baseline action readBoth
            selected = scenario "siblings" "Independent sibling windows" "v1" $ expect $ do
              eventually "slow" (observe "yes" (Created (pure "slow")) id)
              eventually "fast" (observe "absent" (Created (pure "toy-key")) not)
        result <- evalIO (runAccount realClock binding selected)
        case result of
          Verification VerificationResult {expectations = children} -> do
            map (\ExpectationResult {verdict = v} -> v) children === [Unknown, Pass]
            let activations = [tick | ExpectationResult {evidence = Evidence {pollStartedAt = tick}} <- children]
            case activations of
              [first, second] -> first === second
              _ -> fail "expected two sibling activations"
          _ -> fail "expected a verification result"
    ]

epoch :: UTCTime
epoch = UTCTime (fromGregorian 2026 10 18) 0

runAccount :: Clock -> Binding Account AccountStore -> Scenario Account -> IO RunResult
runAccount clock binding selected = case resolveScenario
  ledgerEnvironment
  testOptions
  (BusinessKeyFrom "accountId" (pure "toy-key"))
  binding
  selected of
  Left errors -> fail (show errors)
  Right resolved -> runScenario clock (LogicalInput "toy-v1" []) resolved

boundary :: Integer -> IO RunResult
boundary elapsed = do
  calls <- newIORef 0
  (clock, advance) <- newFakeClock epoch
  let Binding n caps describe acquire release baseline action observation = memoryBinding calls
      delayed :: AccountStore -> CallContext -> Account a -> IO (ObservationOutcome a)
      delayed resource context op = advance elapsed >> observation resource context op
  runAccount clock (Binding n caps describe acquire release baseline action delayed) accountScenario

resultVerdict :: RunResult -> Maybe Verdict
resultVerdict (Verification VerificationResult {verdict = v}) = Just v
resultVerdict (RunnerFault _ _) = Nothing
resultVerdict (PreflightFailure _) = Nothing

forMTest :: [a] -> (a -> PropertyT IO ()) -> PropertyT IO ()
forMTest = flip mapM_
