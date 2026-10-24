module GoldenFixtures (resultFixtures, valueFixtures) where

import Consumer.Account
import Consumer.DeliveryLedger
import Consumer.Hooks (newMicroClock)
import Data.Aeson (Value)
import Data.IORef
import Data.Set qualified as Set
import Data.Time (UTCTime (..), fromGregorian)
import Shoko
import Shoko.Evidence
import Shoko.Result
import Shoko.Result.Json
import Shoko.Scenario (DefinitionError (..))

resultFixtures :: IO [(FilePath, RunResult)]
resultFixtures = do
  positive <-
    accountRun
      ( scenario "toy-account" "Provision a toy account" "v3" $ do
          qualified <- given "agent" (accept ["ready"] Qualified)
          created <- concurrently "creation" $ act "create" (accept ["created"] (Create (fromRef qualified) True))
          selected <- correlate (CorrelationAlias "account") (BusinessKeyName "accountId") (fromRef created)
          expect $ do
            eventually "account-exists" (correlatedBy selected $ observe "is-created" (Created (fromRef created)) id)
            holds "response" (fromRef created) (predicate "present" (/= ""))
      )
      True
  rejection <- accountRun rejectionScenario False
  failed <- ledgerRun 2 False
  unknown <- ledgerRun 0 True
  pure
    [ ("pass.json", positive),
      ("rejection.json", rejection),
      ("fail.json", failed),
      ("unknown.json", unknown),
      ("runner-fault.json", RunnerFault UnexpectedRunnerFault Nothing),
      ("preflight.json", PreflightFailure [CapabilitiesDenied (Set.singleton ExternalSideEffect)]),
      ("definition-error.json", PreflightFailure [InvalidDefinition [DuplicateIdentifier "duplicate-node"]])
    ]

valueFixtures :: IO [(FilePath, Value)]
valueFixtures = do
  results <- resultFixtures
  pure (map (\(path, result) -> (path, resultValue result)) results)

accountRun :: Scenario Account -> Bool -> IO RunResult
accountRun selected includeIdentity = do
  calls <- newIORef 0
  (clock, _) <- newMicroClock epoch
  let options =
        RunOptions
          "golden-run"
          True
          "toy-binary-v1"
          (if includeIdentity then Just "toy-implementation-v1" else Nothing)
          (if includeIdentity then Just (TargetIdentity "toy-fixture" "toy-namespace-uid" "toy-build-v1") else Nothing)
  case resolveScenario testEnvironment options (adjustHandlers (\role _ -> fmap (if role == ActionOperation then allowConcurrentCalls else id)) (memoryBinding calls)) selected of
    Left errors -> fail (show errors)
    Right resolved ->
      runScenario
        clock
        ( LogicalInput
            "account-recipe-v2"
            [("channel", PublicChoice "controlled"), ("accounts", PublicCount 1), ("toy", PublicFlag True)]
        )
        resolved

ledgerRun :: Int -> Bool -> IO RunResult
ledgerRun copies unavailable = do
  rows <- newIORef []
  readCalls <- newIORef 0
  (clock, _) <- newMicroClock epoch
  case resolveScenario
    ledgerEnvironment
    testOptions
    (ledgerBinding rows readCalls unavailable)
    ( scenario "toy-delivery" "Count append-only deliveries" "v3" $ do
        receipt <- act "append" (accept ["appended"] (Append copies))
        selected <- correlate (CorrelationAlias "delivery") (BusinessKeyName "deliveryId") (fromRef receipt)
        expect $ do
          if unavailable then pure () else holds "response" (fromRef receipt) (predicate "wrong-key" (== "different"))
          if unavailable
            then eventually "delivery-count" (correlatedBy selected $ observe "delivered" (Deliveries (fromRef receipt)) id)
            else exactlyOnce "delivery-count" (correlatedBy selected $ observe "delivered" (Deliveries (fromRef receipt)) id)
    ) of
    Left errors -> fail (show errors)
    Right resolved -> runScenario clock (LogicalInput "ledger-recipe-v1" [("copies", PublicCount (toInteger copies))]) resolved

epoch :: UTCTime
epoch = UTCTime (fromGregorian 2026 10 18) 0
