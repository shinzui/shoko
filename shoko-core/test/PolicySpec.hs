module PolicySpec (tests) where

import Consumer.Account
import Consumer.DeliveryLedger (ledgerEnvironment)
import Consumer.Hooks
import Data.Either (isLeft)
import Data.IORef
import Data.Set qualified as Set
import Data.Time (UTCTime (..), fromGregorian)
import Hedgehog (assert, evalIO, property, withTests, (===))
import Shoko hiding (binding)
import Shoko.Evidence
import Shoko.Result
import Test.Tasty
import Test.Tasty.Hedgehog

tests :: TestTree
tests =
  testGroup
    "complete capability and correlation preflight"
    [ testPropertyNamed "cleanup and lifecycle grants are checked before acquisition" "lifecyclePolicy" $ withTests 1 $ property $ do
        calls <- evalIO (newIORef 0)
        let binding = requiringLifecycle [SendHttp] $ adjustHandlers (\_ _ -> fmap (adjustContract (cleanupRequiring [ExternalSideEffect]))) (memoryBinding calls)
            Environment envName prod allowed policy = testEnvironment
            environment = Environment envName prod (Set.delete ExternalSideEffect (Set.delete SendHttp allowed)) policy
        assert (isLeft (resolveScenario environment testOptions (BusinessKeyFrom (BusinessKeyName "accountId") (pure "toy-key")) binding accountScenario))
        evalIO (readIORef calls) >>= (=== 0),
      testPropertyNamed "unresolved correlation node fails before any effects" "correlationPreflight" $ withTests 1 $ property $ do
        calls <- evalIO (newIORef 0)
        assert
          ( isLeft
              ( resolveScenario
                  testEnvironment
                  testOptions
                  (businessKeyFromResult (BusinessKeyName "id") "missing-node")
                  (memoryBinding calls)
                  accountScenario
              )
          )
        evalIO (readIORef calls) >>= (=== 0),
      testPropertyNamed "missing business key never dispatches an uncorrelated observation" "correlationLost" $ withTests 1 $ property $ do
        calls <- evalIO (newIORef 0)
        queries <- evalIO (newIORef (0 :: Int))
        (clock, _) <- evalIO (newMicroClock (UTCTime (fromGregorian 2026 10 18) 0))
        let Hooks acquire release baseline action observation = accountHooks calls
            counted :: AccountStore -> CallContext -> Account a -> IO (ObservationOutcome a)
            counted resource context op = modifyIORef' queries (+ 1) >> observation resource context op
            binding = accountBindingWith (Hooks acquire release baseline action counted)
        result <- evalIO $ case resolveScenario ledgerEnvironment testOptions (BusinessKeyFrom (BusinessKeyName "accountId") (pure "")) binding accountScenario of
          Left errors -> fail (show errors)
          Right resolved -> runScenario clock (LogicalInput "correlation-v1" []) resolved
        evalIO (readIORef queries) >>= (=== 0)
        case result of
          Verification VerificationResult {verdict = v, expectations = children} -> do
            v === Unknown
            map (\ExpectationResult {reason = why} -> why) children === [CorrelationLost]
          _ -> fail "expected a verification result",
      testPropertyNamed "invalid logical metadata fails before acquisition" "logicalMetadata" $ withTests 1 $ property $ do
        calls <- evalIO (newIORef 0)
        (clock, _) <- evalIO (newMicroClock (UTCTime (fromGregorian 2026 10 18) 0))
        result <- case resolveScenario
          testEnvironment
          testOptions
          (BusinessKeyFrom (BusinessKeyName "accountId") (pure "toy-key"))
          (memoryBinding calls)
          accountScenario of
          Left errors -> fail (show errors)
          Right resolved -> evalIO (runScenario clock (LogicalInput "" []) resolved)
        result === PreflightFailure [InvalidLogicalInput]
        evalIO (readIORef calls) >>= (=== 0),
      testPropertyNamed "unsupported operation role fails before acquisition" "operationRole" $ withTests 1 $ property $ do
        calls <- evalIO (newIORef 0)
        let wrongRole = scenario "wrong-role" "Observation used as an unsupported action" "v1" $ do
              _ <- act "read-as-action" (accept ["observed"] (Created (pure "toy-key")))
              expect $ eventually "exists" (observe "exists" (Created (pure "toy-key")) id)
        assert
          ( isLeft
              ( resolveScenario
                  testEnvironment
                  testOptions
                  (BusinessKeyFrom (BusinessKeyName "accountId") (pure "toy-key"))
                  (memoryBinding calls)
                  wrongRole
              )
          )
        evalIO (readIORef calls) >>= (=== 0)
    ]
