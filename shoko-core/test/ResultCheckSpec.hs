module ResultCheckSpec (tests) where

import Consumer.Account
import Consumer.Idempotency
import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (cancel, waitCatch, withAsync)
import Control.Concurrent.MVar
import Control.Exception (finally)
import Data.Aeson (Key, Value (..), encode, toJSON)
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Either (isLeft)
import Data.IORef
import Data.List.NonEmpty (NonEmpty (..))
import Data.Text qualified as Text
import Hedgehog (Property, PropertyT, assert, evalIO, property, withTests, (===))
import Shoko hiding (binding)
import Shoko qualified
import Shoko.Clock
import Shoko.Evidence
import Shoko.Result
import Shoko.Result.Json
import Shoko.Scenario hiding (predicate)
import System.IO.Unsafe (unsafePerformIO)
import System.Timeout (timeout)
import Test.Tasty
import Test.Tasty.Hedgehog

tests :: TestTree
tests =
  testGroup
    "result checks"
    [ testPropertyNamed "constants execute without observations or correlation" "constant" $ once $ do
        result <- evalIO $ run (expect $ holds "constant" (pure True) (predicate "true" id))
        assert (completed result /= Nothing)
        children result === [ExpectationResult "constant" Pass Satisfied (ResultEvidence (ResultCheckEvidence [] (completed result)))],
      testPropertyNamed "inspection retains ordered duplicate namespaced dependencies" "description" $ once $ do
        let selected = orders $ namespace "x" $ do
              key <- given "key" (accept ["issued"] NewKey)
              expect $ agreeOn "same" "orderId" id key (key :| [key])
        case inspectScenario selected of
          Right Description {expectations = [ExpectationDescription key temporal _ subject label selectedCorrelation]} -> do
            key === "x.same"
            temporal === Immediately
            subject === ResultSubject ["x.key", "x.key", "x.key"]
            label === "orderId:(agree)"
            selectedCorrelation === Nothing
          other -> fail (show other),
      testPropertyNamed "result checks keep heterogeneous applicative inputs private" "heterogeneous" $ once $ do
        result <- evalIO $ run $ expect $ holds "mixed" ((,) <$> pure ("SECRET-RESULT" :: Text.Text) <*> pure (12 :: Int)) (onPart "count" snd (predicate "positive" (> 0)))
        map verdictOf (children result) === [Pass]
        assert (not (Text.isInfixOf "SECRET-" (Text.pack (show (resultValue result))))),
      testPropertyNamed "terminal action suppresses check without an evaluation time" "skipped" $ once $ do
        result <- evalIO $ run $ do
          key <- given "key" (accept ["unexpected"] NewKey)
          expect $ holds "skipped" (fromRef key) (predicate "present" (/= ""))
        decodeRunResult (encodeRunResult result) === Right result
        children result === [ExpectationResult "skipped" Unknown PrerequisiteUnavailable (ResultEvidence (ResultCheckEvidence ["key"] Nothing))],
      testPropertyNamed "projection and equality exceptions retain sanitized partial reports" "exceptions" $ once $ do
        mapM_
          ( \test -> do
              result <- evalIO $ run $ expect $ holds "throwing" (pure True) test
              case result of
                RunnerFault UnexpectedRunnerFault (Just _) -> pure ()
                _ -> fail (show result)
              children result === [ExpectationResult "throwing" Unknown UnexpectedRunnerFault (ResultEvidence (ResultCheckEvidence [] Nothing))]
              assert (not (Text.isInfixOf "SECRET-" (Text.pack (show (resultValue result)))))
          )
          [onPart "projection" (\_ -> error "SECRET-PROJECTION") (predicate "test" id), predicate "equality" (\_ -> (error "SECRET-EQUALITY" :: Int) == 1)],
      testPropertyNamed "input projections are forced in the bounded fault boundary" "inputProjection" $ once $ do
        result <- evalIO $ run $ expect $ holds "throwing" (error "SECRET-INPUT" <$> pure ()) (predicate "test" id)
        children result === [ExpectationResult "throwing" Unknown UnexpectedRunnerFault (ResultEvidence (ResultCheckEvidence [] Nothing))],
      testPropertyNamed "nested windows bound a single evaluation without polling" "bounded" $ once $ do
        result <- evalIO $ run $ expect $ within (duration 200) $ within (duration 20) $ holds "slow" (pure ()) (predicate "blocked" slow)
        children result === [ExpectationResult "slow" Unknown DeadlineExceeded (ResultEvidence (ResultCheckEvidence [] Nothing))],
      testPropertyNamed "completion after the cutoff cannot pass" "lateCompletion" $ once $ do
        ticks <- evalIO (newIORef (MonotonicTime 0))
        let Clock _ wall _ _ = realClock
            clock = Clock (readIORef ticks) wall (const (pure ())) (\_ action -> Just <$> action)
            late answer = unsafePerformIO (writeIORef ticks (MonotonicTime 30000) >> pure answer)
            selected = orders $ expect $ within (duration 20) $ holds "late" (pure True) (predicate "late" late)
        result <- evalIO $ execute clock (ordersBinding Idempotent) selected
        children result === [ExpectationResult "late" Unknown DeadlineExceeded (ResultEvidence (ResultCheckEvidence [] Nothing))],
      testPropertyNamed "predicate leaf validation includes projection labels" "labels" $ once $ do
        assert (isLeft (inspectScenario (orders $ expect $ holds "bad" (pure True) (onPart "bad label" id (predicate "yes" id))))),
      testPropertyNamed "unresolved sibling correlation leaves result checks running" "siblingCorrelation" $ once $ do
        calls <- evalIO (newIORef 0)
        let selected = scenario "siblings" "Source-free sibling" "1" $ do
              missing <- correlate (CorrelationAlias "account") (BusinessKeyName "accountId") (pure "")
              expect $ do
                eventually "observation" (correlatedBy missing (observe "yes" (Created (pure "")) id))
                holds "result" (pure True) (predicate "yes" id)
        result <- evalIO $ execute realClock (memoryBinding calls) selected
        map reasonOf (children result) === [CorrelationLost, Satisfied],
      testPropertyNamed "acquisition failure leaves result evidence unevaluated" "acquisition" $ once $ do
        let selectedBinding = Shoko.binding "failed" (\_ -> fail "SECRET-ACQUIRE") (const (pure Cleaned)) (\_ (_ :: Orders a) -> Right Nothing)
        result <- evalIO $ execute realClock selectedBinding (orders $ expect $ holds "check" (pure True) (predicate "yes" id))
        children result === [ExpectationResult "check" Unknown UnexpectedRunnerFault (ResultEvidence (ResultCheckEvidence [] Nothing))],
      testPropertyNamed "async cancellation joins evaluation before cleanup" "cancellation" $ once $ do
        entered <- evalIO newEmptyMVar
        exited <- evalIO (newIORef False)
        released <- evalIO (newIORef False)
        let blocked value = unsafePerformIO $ (putMVar entered () >> threadDelay 10000000 >> pure value) `finally` writeIORef exited True
            selectedBinding = Shoko.binding "cancel" (const (pure ())) (\_ -> readIORef exited >>= writeIORef released >> pure Cleaned) (\_ (_ :: Orders a) -> Right Nothing)
            selected = orders $ expect $ holds "blocking" (pure True) (predicate "blocked" blocked)
        outcome <- evalIO $ withAsync (execute realClock selectedBinding selected) $ \worker -> do
          started <- timeout 1000000 (takeMVar entered)
          case started of
            Nothing -> fail "result check did not enter"
            Just () -> cancel worker >> waitCatch worker
        assert (isLeft outcome)
        evalIO (readIORef released) >>= (=== True),
      testPropertyNamed "v3 rejects cross-tag evidence fields and incompatible descriptions" "closedWire" $ once $ do
        result <- evalIO $ run $ expect $ holds "result" (pure True) (predicate "yes" id)
        decodeRunResult (encodeRunResult result) === Right result
        let badField = changeEvidence (KeyMap.insert "source" (String "foreign")) (resultValue result)
            badKind = changeEvidence (KeyMap.insert "kind" (String "observation")) (resultValue result)
            badTime = changeDescription (KeyMap.insert "temporal" (String "eventually")) (resultValue result)
            badCorrelation = changeDescription (KeyMap.insert "correlationId" (String "foreign")) (resultValue result)
        mapM_ (\value -> assert (isLeft (decodeRunResult (encode value)))) [badField, badKind, badTime, badCorrelation]
    ]

once :: PropertyT IO () -> Property
once = withTests 1 . property

orders :: ScenarioBuilder Orders () -> Scenario Orders
orders = scenario "result-checks" "Result checks" "1"

run :: ScenarioBuilder Orders () -> IO RunResult
run = execute realClock (ordersBinding Idempotent) . orders

execute :: (Vocabulary op) => Clock -> Binding op resource -> Scenario op -> IO RunResult
execute clock binding selected = case resolveScenario testEnvironment testOptions binding selected of
  Left errors -> fail (show errors)
  Right resolved -> runScenario clock (LogicalInput "result-checks" []) resolved

children :: RunResult -> [ExpectationResult]
children (Verification VerificationResult {expectations = results}) = results
children (RunnerFault _ (Just VerificationResult {expectations = results})) = results
children _ = []

completed :: RunResult -> Maybe MonotonicTime
completed result = case children result of
  [ExpectationResult _ _ _ (ResultEvidence (ResultCheckEvidence _ tick))] -> tick
  _ -> Nothing

verdictOf :: ExpectationResult -> Verdict
verdictOf (ExpectationResult _ verdict _ _) = verdict

reasonOf :: ExpectationResult -> Reason
reasonOf (ExpectationResult _ _ why _) = why

duration :: Int -> Duration
duration = either (error . Text.unpack) id . milliseconds

slow :: () -> Bool
slow () = unsafePerformIO (threadDelay 10000000 >> pure True)
{-# NOINLINE slow #-}

changeEvidence, changeDescription :: (KeyMap.KeyMap Value -> KeyMap.KeyMap Value) -> Value -> Value
changeEvidence f = at "report" (at "expectations" (each (at "evidence" (objectMap f))))
changeDescription f = at "report" (at "description" (at "expectations" (each (objectMap f))))

at :: Key -> (Value -> Value) -> Value -> Value
at key f (Object fields) = Object (case KeyMap.lookup key fields of Nothing -> fields; Just old -> KeyMap.insert key (f old) fields)
at _ _ value = value

objectMap :: (KeyMap.KeyMap Value -> KeyMap.KeyMap Value) -> Value -> Value
objectMap f (Object fields) = Object (f fields)
objectMap _ value = value

each :: (Value -> Value) -> Value -> Value
each f (Array values) = toJSON (map f (foldr (:) [] values))
each _ value = value
