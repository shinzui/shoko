module Consumer.DeliveryLedger (Ledger (..), ledgerScenario, ledgerBinding, ledgerEnvironment) where

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
  expect $ case temporal of
    Eventually -> eventually "delivery-count" (observe "delivered" (Deliveries (fromRef receipt)) id)
    Never -> never "delivery-count" (observe "delivered" (Deliveries (fromRef receipt)) id)
    ExactlyOnce -> exactlyOnce "delivery-count" (observe "delivered" (Deliveries (fromRef receipt)) id)

ledgerEnvironment :: Environment
ledgerEnvironment =
  Environment "local" False (Set.fromList [minBound .. maxBound]) $
    Policy (duration 100) (duration 30) (duration 10) (duration 20)
  where
    duration n = either (error . Text.unpack) id (milliseconds n)

-- The initial list permits tests of pre-baseline exclusion. Only this toy
-- adapter uses an integer list length as a durable high-water cursor.
ledgerBinding :: IORef [Text] -> IORef Int -> Bool -> Binding Ledger ()
ledgerBinding rows readCalls unavailable =
  Binding
    "ledger"
    Set.empty
    describe
    (const (pure ()))
    (const (pure Cleaned))
    capture
    perform
    readObservation
  where
    describe :: OperationRole -> Ledger a -> Maybe BindingContract
    describe ActionOperation (Append _) = Just available
    describe ObservationOperation (Deliveries _) = Just available
    describe _ _ = Nothing
    available = BindingContract Set.empty Set.empty (Set.singleton BusinessKey) (Just "ledger") DurableHistory
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
    readObservation _ (CallContext resolve _ base selected _ cutoff (Clock now _ _ _)) (Deliveries input) = do
      modifyIORef' readCalls (+ 1)
      tick <- now
      entries <- readIORef rows
      pure $
        if unavailable
          then ObservationUnavailable "source-unavailable"
          else case (resolve input, base, selected) of
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
