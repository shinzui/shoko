module Consumer.DeliveryLedger (Ledger (..), ledgerScenario, ledgerBinding, ledgerEnvironment, ledgerHooks, ledgerBindingWith) where

import Consumer.Hooks
import Data.IORef
import Data.Set qualified as Set
import Data.Text qualified as Text
import Shoko
import Shoko.Clock
import Shoko.Prelude (Text)
import Text.Read (readMaybe)

data Ledger a where
  Append :: Int -> Ledger Text
  Deliveries :: Input Text -> Ledger Bool

instance Vocabulary Ledger where
  describeOperation (Append _) = OperationInfo "append" (Set.singleton WriteState) [] []
  describeOperation (Deliveries input) = OperationInfo "deliveries" (Set.singleton ReadEvents) (inputDependencies input) []

ledgerScenario :: Int -> Temporal -> Scenario Ledger
ledgerScenario copies temporal = scenario "toy-delivery" "Count append-only deliveries" "v1" $ do
  receipt <- act "append" (accept ["appended"] (Append copies))
  selected <- correlate (CorrelationAlias "delivery") (BusinessKeyName "deliveryId") (fromRef receipt)
  expect $ case temporal of
    Immediately -> error "not an observation temporal"
    Eventually -> eventually "delivery-count" (correlatedBy selected $ observe "delivered" (Deliveries (fromRef receipt)) id)
    Never -> never "delivery-count" (correlatedBy selected $ observe "delivered" (Deliveries (fromRef receipt)) id)
    ExactlyOnce -> exactlyOnce "delivery-count" (correlatedBy selected $ observe "delivered" (Deliveries (fromRef receipt)) id)

ledgerEnvironment :: Environment
ledgerEnvironment =
  Environment "local" False (Set.fromList [minBound .. maxBound]) $
    Policy (duration 100) (duration 30) (duration 10) (duration 20)
  where
    duration n = either (error . Text.unpack) id (milliseconds n)

-- The initial list permits tests of pre-baseline exclusion. Only this toy
-- adapter uses an integer list length as a durable high-water cursor.
ledgerBinding :: IORef [Text] -> IORef Int -> Bool -> Binding Ledger ()
ledgerBinding rows readCalls unavailable = ledgerBindingWith (ledgerHooks rows readCalls unavailable)

ledgerBindingWith :: Hooks Ledger () -> Binding Ledger ()
ledgerBindingWith (Hooks acquire release capture perform poll) = binding "ledger" acquire release handlers
  where
    handlers :: OperationRole -> Ledger a -> Either HandlerBuildError (Maybe (Handler () a))
    handlers ActionOperation op@(Append _) = Right (Just (actionHandler noRequirements (\resource call -> perform resource call op)))
    handlers ObservationOperation op@(Deliveries _) = Right (Just (observationHandler noRequirements (RequiresBusinessKey (BusinessKeyName "deliveryId")) (newSource (SourceId "ledger") DurableHistory (\resource clock -> capture resource clock (SourceId "ledger"))) (\resource call -> poll resource call op)))
    handlers _ _ = Right Nothing

ledgerHooks :: IORef [Text] -> IORef Int -> Bool -> Hooks Ledger ()
ledgerHooks rows readCalls unavailable = Hooks (const (pure ())) (const (pure Cleaned)) capture perform readObservation
  where
    capture _ (Clock now _ _ _) source = do
      tick <- now
      count <- length <$> readIORef rows
      pure (Right (Baseline source tick (Just (Text.pack (show count)))))
    perform :: () -> CallContext -> Ledger a -> IO (ActionOutcome a)
    perform _ _ (Append copies) = do
      modifyIORef' rows (++ replicate copies "delivery-key")
      pure (ActionObserved "appended" "delivery-key")
    perform _ _ _ = pure (ActionUnavailable "not-an-action")
    readObservation :: () -> CallContext -> Ledger a -> IO (ObservationOutcome a)
    readObservation _ context (Deliveries input) = do
      let base = sourceBaseline context
          selected = correlation context
          cutoff = evidenceUntil context
          Clock now _ _ _ = callClock context
      resolved <- resolveInput context input
      modifyIORef' readCalls (+ 1)
      tick <- now
      entries <- readIORef rows
      pure $
        if unavailable
          then ObservationUnavailable "source-unavailable"
          else case (resolved, base, selected) of
            (Right businessKey, Just (Baseline _ captured cursor), Just (ByBusinessKey _ selectedKey))
              | businessKey == selectedKey -> case cursor >>= readMaybe . Text.unpack of
                  Just from ->
                    Observed
                      [ Occurrence (Just (Text.pack (show index))) True
                      | (index, entry) <- drop from (zip [0 :: Int ..] entries),
                        entry == businessKey
                      ]
                      (Coverage DurableHistory captured (min cutoff tick) True)
                  Nothing -> ObservationUnavailable "missing-cursor"
            _ -> ObservationUnavailable "correlation-lost"
    readObservation _ _ _ = pure (ObservationUnavailable "not-an-observation")
