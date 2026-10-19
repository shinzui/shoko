module CoverageSpec (tests) where

import Consumer.Account
import Consumer.DeliveryLedger
import Consumer.Hooks
import Data.IORef
import Data.Time (UTCTime (..), fromGregorian)
import Hedgehog (evalIO, property, withTests, (===))
import Shoko hiding (binding)
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
        (clock, _) <- evalIO (newMicroClock epoch)
        let selected =
              scenario "snapshot-negative" "Sampled absence" "v1" $
                expect $
                  never "no-account" (observe "exists" (Created (pure "toy-key")) id)
        result <- evalIO $ case resolveScenario
          ledgerEnvironment
          testOptions
          (BusinessKeyFrom (BusinessKeyName "accountId") (pure "toy-key"))
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
      testPropertyNamed "durable eventually requires a closing history read" "eventualClosingRead" $ withTests 1 $ property $ do
        (available, readCount) <- evalIO (closingRun True)
        resultVerdict available === Just Fail
        readCount === 4
        (unavailable, _) <- evalIO (closingRun False)
        resultVerdict unavailable === Just Unknown,
      testPropertyNamed "a read crossing the cutoff is followed by a closing snapshot" "crossingClosingRead" $ withTests 1 $ property $ do
        result <- evalIO crossingRun
        resultVerdict result === Just Fail,
      testPropertyNamed "late sampled presence cannot violate an earlier negative window" "lateSampledWitness" $ withTests 1 $ property $ do
        calls <- evalIO (newIORef 0)
        (clock, advance) <- evalIO (newMicroClock epoch)
        let Hooks acquire release baseline action observation = accountHooks calls
            late :: AccountStore -> CallContext -> Account a -> IO (ObservationOutcome a)
            late resource context op = case op of
              Created _ -> advance 21000 >> pure (Observed [Occurrence Nothing True] (Coverage SampledState (MonotonicTime 21000) (MonotonicTime 21000) True))
              _ -> observation resource context op
            binding = accountBindingWith (Hooks acquire release baseline action late)
            selected =
              scenario "late-sample" "Finite negative state window" "v1" $
                expect $
                  within (duration 20) $
                    never "absent" (observe "exists" (Created (pure "toy-key")) id)
        result <- evalIO $ case resolveScenario ledgerEnvironment testOptions (BusinessKeyFrom (BusinessKeyName "accountId") (pure "toy-key")) binding selected of
          Left errors -> fail (show errors)
          Right resolved -> runScenario clock (LogicalInput "late-sample-v1" []) resolved
        resultVerdict result === Just Unknown,
      testPropertyNamed "nested within keeps the earliest deadline" "nestedWithin" $ withTests 1 $ property $ do
        calls <- evalIO (newIORef 0)
        (clock, advance) <- evalIO (newMicroClock epoch)
        let Hooks acquire release baseline action observation = accountHooks calls
            delayed :: AccountStore -> CallContext -> Account a -> IO (ObservationOutcome a)
            delayed resource context op = advance 20001 >> observation resource context op
            binding = accountBindingWith (Hooks acquire release baseline action delayed)
            selected =
              scenario "nested" "Earliest enclosing window" "v1" $
                expect $
                  within (duration 50) $
                    within (duration 20) $
                      eventually "absent" (observe "absent" (Created (pure "toy-key")) not)
        result <- evalIO $ case resolveScenario
          ledgerEnvironment
          testOptions
          (BusinessKeyFrom (BusinessKeyName "accountId") (pure "toy-key"))
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
  (clock, _) <- newMicroClock epoch
  let Hooks acquire release baseline action observation = ledgerHooks rows readCalls False
      interrupted :: () -> CallContext -> Ledger a -> IO (ObservationOutcome a)
      interrupted resource context op = do
        index <- atomicModifyIORef' sequenceNumber (\current -> (current + 1, current))
        if (recover && index == 0) || (not recover && index > 0)
          then pure (ObservationUnavailable "gap")
          else observation resource context op
      binding = ledgerBindingWith (Hooks acquire release baseline action interrupted)
  case resolveScenario ledgerEnvironment testOptions (businessKeyFromResult (BusinessKeyName "deliveryId") "append") binding (ledgerScenario copies temporal) of
    Left errors -> fail (show errors)
    Right resolved -> runScenario clock (LogicalInput "gap-v1" []) resolved

resultVerdict :: RunResult -> Maybe Verdict
resultVerdict (Verification VerificationResult {verdict = v}) = Just v
resultVerdict (RunnerFault _ _) = Nothing
resultVerdict (PreflightFailure _) = Nothing

closingRun :: Bool -> IO (RunResult, Int)
closingRun available = do
  rows <- newIORef []
  calls <- newIORef 0
  attempts <- newIORef (0 :: Int)
  (clock@(Clock now _ _ _), _) <- newMicroClock epoch
  let Hooks acquire release baseline action observation = ledgerHooks rows calls False
      closing :: () -> CallContext -> Ledger a -> IO (ObservationOutcome a)
      closing resource context op = do
        modifyIORef' attempts (+ 1)
        tick <- now
        if tick >= evidenceUntil context && not available then pure (ObservationUnavailable "closing-source-unavailable") else observation resource context op
      binding = ledgerBindingWith (Hooks acquire release baseline action closing)
  resolved <- either (fail . show) pure (resolveScenario ledgerEnvironment testOptions (businessKeyFromResult (BusinessKeyName "deliveryId") "append") binding (ledgerScenario 0 Eventually))
  result <- runScenario clock (LogicalInput "closing-history-v1" []) resolved
  count <- readIORef attempts
  pure (result, count)

crossingRun :: IO RunResult
crossingRun = do
  rows <- newIORef []
  calls <- newIORef 0
  (clock, advance) <- newMicroClock epoch
  let Hooks acquire release baseline action observation = ledgerHooks rows calls False
      crossing :: () -> CallContext -> Ledger a -> IO (ObservationOutcome a)
      crossing resource context op = do
        result <- observation resource context op
        advance 40000
        pure result
      binding = ledgerBindingWith (Hooks acquire release baseline action crossing)
  resolved <- either (fail . show) pure (resolveScenario ledgerEnvironment testOptions (businessKeyFromResult (BusinessKeyName "deliveryId") "append") binding (ledgerScenario 0 Eventually))
  runScenario clock (LogicalInput "crossing-history-v1" []) resolved
