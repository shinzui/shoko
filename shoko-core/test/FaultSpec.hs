module FaultSpec (tests) where

import Consumer.Account
import Consumer.DeliveryLedger (ledgerEnvironment)
import Consumer.Hooks
import Control.Exception (throwIO)
import Data.IORef
import Data.Text qualified as Text
import Data.Time (UTCTime (..), fromGregorian)
import Hedgehog (assert, evalIO, property, withTests, (===))
import Shoko hiding (binding)
import Shoko.Clock
import Shoko.Evidence
import Shoko.Result
import Shoko.Result.Json (resultValue)
import Test.Tasty
import Test.Tasty.Hedgehog

tests :: TestTree
tests =
  testGroup
    "fault and source identity boundaries"
    [ testPropertyNamed "unexpected handler fault retains partial evidence and finalizes" "runnerFault" $ withTests 1 $ property $ do
        calls <- evalIO (newIORef 0)
        released <- evalIO (newIORef False)
        let Hooks acquire _ baseline action observation = accountHooks calls
            failing :: AccountStore -> CallContext -> Account a -> IO (ActionOutcome a)
            failing _ _ (Create _ _) = throwIO (userError "SECRET-RUNNER-FAULT-SENTINEL")
            failing resource context op = action resource context op
            binding = accountBindingWith (Hooks acquire (\_ -> writeIORef released True >> pure Cleaned) baseline failing observation)
        result <- evalIO (run binding)
        case result of
          RunnerFault UnexpectedRunnerFault (Just VerificationResult {actions = actions, verdict = v}) -> do
            length actions === 2
            v === Unknown
          _ -> fail "expected a partial runner fault"
        evalIO (readIORef released) >>= (=== True)
        assert (not (Text.isInfixOf "SECRET-" (Text.pack (show (resultValue result))))),
      testPropertyNamed "foreign source baseline prevents all fixtures and actions" "baselineIdentity" $ withTests 1 $ property $ do
        calls <- evalIO (newIORef 0)
        let Hooks acquire release _ action observation = accountHooks calls
            capture _ (Clock now _ _ _) _ = do
              tick <- now
              pure (Right (Baseline (SourceId "another-source") tick Nothing))
        result <- evalIO (run (accountBindingWith (Hooks acquire release capture action observation)))
        evalIO (readIORef calls) >>= (=== 1)
        case result of
          Verification VerificationResult {verdict = v, expectations = children} -> do
            v === Unknown
            map (\ExpectationResult {reason = why} -> why) children === [InvalidEvidence]
          _ -> fail "expected unavailable evidence",
      testPropertyNamed "a different business key cannot satisfy an observation" "wrongBusinessKey" $ withTests 1 $ property $ do
        calls <- evalIO (newIORef 0)
        (clock, _) <- evalIO (newMicroClock (UTCTime (fromGregorian 2026 10 18) 0))
        result <- evalIO $ case resolveScenario
          ledgerEnvironment
          testOptions
          (BusinessKeyFrom (BusinessKeyName "accountId") (pure "another-key"))
          (memoryBinding calls)
          accountScenario of
          Left errors -> fail (show errors)
          Right resolved -> runScenario clock (LogicalInput "correlation-v1" []) resolved
        case result of
          Verification VerificationResult {verdict = v} -> v === Unknown
          _ -> fail "expected unavailable correlated evidence"
    ]
  where
    run binding = do
      (clock, _) <- newMicroClock (UTCTime (fromGregorian 2026 10 18) 0)
      case resolveScenario ledgerEnvironment testOptions (BusinessKeyFrom (BusinessKeyName "accountId") (pure "toy-key")) binding accountScenario of
        Left errors -> fail (show errors)
        Right resolved -> runScenario clock (LogicalInput "fault-v1" []) resolved
