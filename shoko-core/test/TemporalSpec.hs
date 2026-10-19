module TemporalSpec (tests) where

import Consumer.Account
import Consumer.DeliveryLedger
import Consumer.Hooks (newMicroClock)
import Data.IORef
import Data.Time (UTCTime (..), fromGregorian)
import Hedgehog (evalIO, property, withTests, (===))
import Shoko hiding (binding)
import Shoko.Prelude (Text)
import Shoko.Result
import Test.Tasty
import Test.Tasty.Hedgehog

tests :: TestTree
tests =
  testGroup
    "bounded evidence"
    [ testPropertyNamed "append read cardinality and repeated polls" "ledgerCardinality" $ withTests 1 $ property $ do
        one <- evalIO (runLedger [] 1 ExactlyOnce False)
        verdictOf one === Just Pass
        two <- evalIO (runLedger [] 2 ExactlyOnce False)
        verdictOf two === Just Fail
        zero <- evalIO (runLedger [] 0 ExactlyOnce False)
        verdictOf zero === Just Fail,
      testPropertyNamed "complete empty negative interval and source outage" "negativeCoverage" $ withTests 1 $ property $ do
        empty <- evalIO (runLedger [] 0 Never False)
        verdictOf empty === Just Pass
        witness <- evalIO (runLedger [] 1 Never False)
        verdictOf witness === Just Fail
        missing <- evalIO (runLedger [] 0 Never True)
        verdictOf missing === Just Unknown,
      testPropertyNamed "pre-baseline history excluded" "baselineExclusion" $ withTests 1 $ property $ do
        old <- evalIO (runLedger ["delivery-key"] 0 Eventually False)
        verdictOf old === Just Fail,
      testPropertyNamed "typed rejection passes and fixture values stay private" "typedRejection" $ withTests 1 $ property $ do
        calls <- evalIO (newIORef 0)
        (clock, _) <- evalIO (newMicroClock epoch)
        let binding = memoryBinding calls
        positive <- run clock binding accountScenario
        negative <- run clock binding rejectionScenario
        verdictOf positive === Just Pass
        verdictOf negative === Just Pass
        -- Acquisition occurs for each run; only the positive runs the write.
        evalIO (readIORef calls) >>= (=== 3)
        otherCalls <- evalIO (newIORef 0)
        otherPositive <- run clock (alternateBinding otherCalls) accountScenario
        otherNegative <- run clock (alternateBinding otherCalls) rejectionScenario
        verdictOf otherPositive === Just Pass
        verdictOf otherNegative === Just Pass
    ]
  where
    run clock binding selected = case resolveScenario
      ledgerEnvironment
      testOptions
      (BusinessKeyFrom (BusinessKeyName "accountId") (pure "toy-key"))
      binding
      selected of
      Left errors -> fail (show errors)
      Right resolved -> evalIO (runScenario clock (LogicalInput "toy-v1" []) resolved)

epoch :: UTCTime
epoch = UTCTime (fromGregorian 2026 10 18) 0

runLedger :: [Text] -> Int -> Temporal -> Bool -> IO RunResult
runLedger initial copies temporal unavailable = do
  rows <- newIORef initial
  readCalls <- newIORef 0
  (clock, _) <- newMicroClock epoch
  case resolveScenario
    ledgerEnvironment
    testOptions
    (businessKeyFromResult (BusinessKeyName "deliveryId") "append")
    (ledgerBinding rows readCalls unavailable)
    (ledgerScenario copies temporal) of
    Left errors -> fail (show errors)
    Right resolved -> runScenario clock (LogicalInput "ledger-v1" []) resolved

verdictOf :: RunResult -> Maybe Verdict
verdictOf (RunnerFault _ _) = Nothing
verdictOf (Verification (VerificationResult _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ verdict _ _ _)) = Just verdict
verdictOf (PreflightFailure _) = Nothing
