module IdempotencySpec (tests) where

import Consumer.Account (testOptions)
import Consumer.DeliveryLedger (ledgerEnvironment)
import Consumer.Hooks (newMicroClock)
import Consumer.Idempotency
import Data.Time (UTCTime (..), fromGregorian)
import Hedgehog
import Shoko
import Shoko.Result
import Shoko.Scenario hiding (predicate)
import Test.Tasty
import Test.Tasty.Hedgehog

tests :: TestTree
tests =
  testGroup
    "Idempotency"
    [ testPropertyNamed "sequential replay passes" "retry" $ once $ run Idempotent False retryScenario >>= (=== Pass),
      testPropertyNamed "unexpected created outcome fails" "tag" $ once $ run NonIdempotent False retryScenario >>= (=== Fail),
      testPropertyNamed "duplicate effects fail despite accepted outcome" "effects" $ once $ run NonIdempotent False (retryAccepting ["created", "replayed"]) >>= (=== Fail),
      testPropertyNamed "payload conflict retains one effect" "conflict" $ once $ run Idempotent False conflictScenario >>= (=== Pass),
      testPropertyNamed "unavailable history is unknown" "unavailable" $ once $ run Idempotent True retryScenario >>= (=== Unknown),
      testPropertyNamed "attempts depend on the same key" "dependencies" $ once $ case inspectScenario retryScenario of
        Right Description {nodes = nodes} -> [deps | NodeDescription {operation = OperationInfo "orders.submit" _ deps _} <- nodes] === [["key"], ["key"]]
        Left errors -> fail (show errors),
      testPropertyNamed "response agreement currently needs fabricated sampled evidence" "comparisonWorkaround" $ once $ run Idempotent False comparisonScenario >>= (=== Pass)
    ]

once :: PropertyT IO () -> Property
once = withTests 1 . property

run :: Behavior -> Bool -> Scenario Orders -> PropertyT IO Verdict
run behavior unavailable selected = do
  (clock, _) <- evalIO (newMicroClock (UTCTime (fromGregorian 2026 10 23) 0))
  case resolveScenario ledgerEnvironment testOptions (ordersBindingWith behavior unavailable) selected of
    Left errors -> fail (show errors)
    Right resolved ->
      evalIO (runScenario clock (LogicalInput "idempotency" []) resolved) >>= \case
        Verification VerificationResult {verdict = result} -> pure result
        other -> fail (show other)

comparisonScenario :: Scenario Orders
comparisonScenario = scenario "comparison" "Compare order IDs" "v1" $ do
  key <- given "key" (accept ["issued"] NewKey)
  original <- act "original" (accept ["created"] (Submit (fromRef key) (pure "basket-1")))
  retry <- act "retry" (accept ["replayed"] (Submit (fromRef key) (pure "basket-1")))
  selected <- correlate (CorrelationAlias "order") (BusinessKeyName "idempotencyKey") (fromRef key)
  expect $ eventually "same-order" $ correlatedBy selected $ observeThat (SameOrder (fromRef original) (fromRef retry)) (predicate "same" id)
