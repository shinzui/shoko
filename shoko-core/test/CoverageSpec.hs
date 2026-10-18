module CoverageSpec (tests) where

import Consumer.Account
import Consumer.DeliveryLedger
import Data.IORef
import Data.Time (UTCTime (..), fromGregorian)
import Hedgehog (evalIO, property, withTests, (===))
import Shoko
import Shoko.Clock
import Shoko.Result
import Test.Tasty
import Test.Tasty.Hedgehog

tests :: TestTree
tests =
  testGroup
    "coverage strength and gaps"
    [ testPropertyNamed "snapshot absence cannot prove a continuous negative" "snapshotAbsence" $ withTests 1 $ property $ do
        calls <- evalIO (newIORef 0)
        (clock, _) <- evalIO (newFakeClock epoch)
        let selected =
              scenario "snapshot-negative" "Sampled absence" "v1" $
                expect $
                  never "no-account" (observe "exists" (Created (pure "toy-key")) id)
        result <- evalIO $ case resolveScenario
          ledgerEnvironment
          testOptions
          (BusinessKeyFrom "accountId" (pure "toy-key"))
          (memoryBinding calls)
          selected of
          Left errors -> fail (show errors)
          Right resolved -> runScenario clock (LogicalInput "snapshot-v1" []) resolved
        resultVerdict result === Just Unknown,
      testPropertyNamed "one occurrence followed by an unrecovered gap is Unknown" "unrecoveredGap" $ withTests 1 $ property $ do
        result <- evalIO (gapRun ExactlyOnce 1 False)
        resultVerdict result === Just Unknown,
      testPropertyNamed "durable catch-up repairs an earlier source gap" "recoveredGap" $ withTests 1 $ property $ do
        exactlyOne <- evalIO (gapRun ExactlyOnce 1 True)
        resultVerdict exactlyOne === Just Pass
        missing <- evalIO (gapRun Eventually 0 True)
        resultVerdict missing === Just Fail,
      testPropertyNamed "nested within keeps the earliest deadline" "nestedWithin" $ withTests 1 $ property $ do
        calls <- evalIO (newIORef 0)
        (clock, advance) <- evalIO (newFakeClock epoch)
        let Binding n caps describe acquire release baseline action observation = memoryBinding calls
            delayed :: AccountStore -> CallContext -> Account a -> IO (ObservationOutcome a)
            delayed resource context op = advance 20001 >> observation resource context op
            binding = Binding n caps describe acquire release baseline action delayed
            selected =
              scenario "nested" "Earliest enclosing window" "v1" $
                expect $
                  within (duration 50) $
                    within (duration 20) $
                      eventually "absent" (observe "absent" (Created (pure "toy-key")) not)
        result <- evalIO $ case resolveScenario
          ledgerEnvironment
          testOptions
          (BusinessKeyFrom "accountId" (pure "toy-key"))
          binding
          selected of
          Left errors -> fail (show errors)
          Right resolved -> runScenario clock (LogicalInput "nested-v1" []) resolved
        resultVerdict result === Just Unknown
    ]

epoch :: UTCTime
epoch = UTCTime (fromGregorian 2026 10 18) 0

duration :: Int -> Duration
duration n = either (const (error "invalid test duration")) id (milliseconds n)

-- A complete catch-up re-reads immutable history from the pre-action cursor.
gapRun :: Temporal -> Int -> Bool -> IO RunResult
gapRun temporal copies recover = do
  rows <- newIORef []
  readCalls <- newIORef 0
  sequenceNumber <- newIORef (0 :: Int)
  (clock, _) <- newFakeClock epoch
  let Binding n caps describe acquire release baseline action observation = ledgerBinding rows readCalls False
      interrupted :: () -> CallContext -> Ledger a -> IO (ObservationOutcome a)
      interrupted resource context op = do
        index <- atomicModifyIORef' sequenceNumber (\current -> (current + 1, current))
        if (recover && index == 0) || (not recover && index > 0)
          then pure (ObservationUnavailable "gap")
          else observation resource context op
      binding = Binding n caps describe acquire release baseline action interrupted
  case resolveScenario ledgerEnvironment testOptions (businessKeyFromResult "deliveryId" "append") binding (ledgerScenario copies temporal) of
    Left errors -> fail (show errors)
    Right resolved -> runScenario clock (LogicalInput "gap-v1" []) resolved

resultVerdict :: RunResult -> Maybe Verdict
resultVerdict (Verification VerificationResult {verdict = v}) = Just v
resultVerdict (RunnerFault _ _) = Nothing
resultVerdict (PreflightFailure _) = Nothing
