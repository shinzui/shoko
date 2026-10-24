module Idempotency where

import Control.Concurrent.MVar
import Control.Monad (when)
import Data.IORef
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Shoko
import Shoko.Cli
import Shoko.Clock
import Shoko.Prelude (Generic, Text)
import Shoko.Result (LogicalInput (..))
import System.Timeout (timeout)
import Text.Read (readMaybe)

data Submission = Submission {orderId :: !Text, created :: !Bool}
  deriving stock (Eq, Show, Generic)

data Orders a where
  NewKey :: Orders Text
  Submit :: Input Text -> Input Text -> Orders Submission
  OrderPlaced :: Input Text -> Orders Bool

instance Vocabulary Orders where
  describeOperation NewKey = declareOperation "orders.new-key" []
  describeOperation (Submit key payload) = dependsOn ((,) <$> key <*> payload) (declareOperation "orders.submit" [WriteState])
  describeOperation (OrderPlaced key) = dependsOn key (declareOperation "orders.placed" [ReadEvents])

data Behavior = Idempotent | NonIdempotent | RaceProne
  deriving stock (Eq, Show)

data OrdersResource = OrdersResource
  { ledger :: !(IORef (Map.Map Text (Text, Text))),
    history :: !(IORef [Text]),
    sequenceNumber :: !(IORef Int),
    arrivals :: !(IORef Int),
    rendezvous :: !(MVar ())
  }

ordersBinding :: Behavior -> Binding Orders OrdersResource
ordersBinding behavior = ordersBindingWith behavior False

ordersBindingWith :: Behavior -> Bool -> Binding Orders OrdersResource
ordersBindingWith behavior unavailable = ordersBindingFor behavior unavailable 1

ordersBindingFor :: Behavior -> Bool -> Int -> Binding Orders OrdersResource
ordersBindingFor behavior unavailable participants = binding "orders" acquire (const (pure Cleaned)) handlers
  where
    acquire _ = OrdersResource <$> newIORef Map.empty <*> newIORef [] <*> newIORef 0 <*> newIORef 0 <*> newEmptyMVar
    handlers :: OperationRole -> Orders a -> Either HandlerBuildError (Maybe (Handler OrdersResource a))
    handlers FixtureOperation NewKey = Right (Just (actionHandler noRequirements (\_ _ -> pure (ActionObserved "issued" "key-1"))))
    handlers ActionOperation (Submit key payload) = Right (Just (allowConcurrentCalls (actionHandler noRequirements (submit key payload))))
    handlers ObservationOperation (OrderPlaced key) = Right (Just (observationHandler noRequirements (RequiresBusinessKey (BusinessKeyName "idempotencyKey")) source (poll key)))
    handlers _ _ = Right Nothing
    source = newSource (SourceId "orders.history") DurableHistory $ \resource (Clock now _ _ _) -> do
      tick <- now
      count <- length <$> readIORef (history resource)
      pure (Right (Baseline (SourceId "orders.history") tick (Just (Text.pack (show count)))))
    submit key payload resource context = do
      resolvedKey <- resolveInput context key
      resolvedPayload <- resolveInput context payload
      case (resolvedKey, resolvedPayload) of
        (Right k, Right p) -> do
          candidate <- atomicModifyIORef' (sequenceNumber resource) (\n -> (n + 1, "SECRET-ORDER-" <> Text.pack (show n)))
          (tag, result) <-
            if behavior == RaceProne
              then do
                previous <- Map.lookup k <$> readIORef (ledger resource)
                arrived <- atomicModifyIORef' (arrivals resource) (\n -> (n + 1, n + 1))
                when (arrived >= participants) $ do
                  _ <- tryPutMVar (rendezvous resource) ()
                  pure ()
                ready <- timeout 1000000 (readMVar (rendezvous resource))
                case ready of
                  Nothing -> fail "rendezvous timed out"
                  Just () -> case previous of
                    Nothing -> do
                      atomicModifyIORef' (ledger resource) (\entries -> (Map.insert k (p, candidate) entries, ()))
                      pure ("created", Submission candidate True)
                    Just (previousPayload, original) -> pure (if previousPayload == p then "replayed" else "key-conflict", Submission original False)
              else atomicModifyIORef' (ledger resource) $ \entries ->
                case (behavior, Map.lookup k entries) of
                  (NonIdempotent, _) -> (entries, ("created", Submission candidate True))
                  (_, Nothing) -> (Map.insert k (p, candidate) entries, ("created", Submission candidate True))
                  (_, Just (previous, original)) -> (entries, (if previous == p then "replayed" else "key-conflict", Submission original False))
          if created result then atomicModifyIORef' (history resource) (\rows -> (rows ++ [k], ())) else pure ()
          pure (ActionObserved tag result)
        _ -> pure (ActionUnavailable "missing-input")
    poll key resource context = do
      resolved <- resolveInput context key
      let Clock now _ _ _ = callClock context
      tick <- now
      rows <- readIORef (history resource)
      pure $
        if unavailable
          then ObservationUnavailable "source-unavailable"
          else case (resolved, sourceBaseline context, correlation context) of
            (Right k, Just (Baseline _ captured cursor), Just (ByBusinessKey _ selected)) | k == selected -> case cursor >>= readMaybe . Text.unpack of
              Just start -> Observed [Occurrence (Just (Text.pack (show index))) True | (index, entry) <- drop start (zip [0 :: Int ..] rows), entry == k] (Coverage DurableHistory captured (min tick (evidenceUntil context)) True)
              Nothing -> ObservationUnavailable "missing-cursor"
            _ -> ObservationUnavailable "correlation-lost"

retryScenario :: Scenario Orders
retryScenario = retryAccepting ["replayed"]

retryAccepting :: [Text] -> Scenario Orders
retryAccepting tags = scenario "idempotent-retry" "Retry an order" "v1" $ do
  key <- given "key" (accept ["issued"] NewKey)
  original <- act "original" (accept ["created"] (Submit (fromRef key) (pure "basket-1")))
  retry <- act "retry" (accept tags (Submit (fromRef key) (pure "basket-1")))
  expectAfterActions $ agreeOn "same-order" "orderId" orderId original (retry :| [])
  checkEffect key

conflictScenario :: Scenario Orders
conflictScenario = scenario "payload-conflict" "Reject changed payload" "v1" $ do
  key <- given "key" (accept ["issued"] NewKey)
  original <- act "original" (accept ["created"] (Submit (fromRef key) (pure "basket-1")))
  retry <- act "conflict" (accept ["key-conflict"] (Submit (fromRef key) (pure "basket-2")))
  expectAfterActions $ agreeOn "same-order" "orderId" orderId original (retry :| [])
  checkEffect key

checkEffect :: Ref Text -> ScenarioBuilder Orders ()
checkEffect key = do
  selected <- correlate (CorrelationAlias "order") (BusinessKeyName "idempotencyKey") (fromRef key)
  expect $ within evidenceWindow $ exactlyOnce "one-effect" $ correlatedBy selected $ observeThat (OrderPlaced (fromRef key)) (predicate "placed" id)

evidenceWindow :: Duration
evidenceWindow = either (error . Text.unpack) id (milliseconds 20)

concurrentDuplicates :: Scenario Orders
concurrentDuplicates = scenario "concurrent-duplicates" "Race duplicate orders" "v1" $ do
  key <- given "key" (accept ["issued"] NewKey)
  let attempt n = act ("attempt-" <> n) (accept ["created", "replayed"] (Submit (fromRef key) (pure "basket-1")))
  (a, b, c) <- concurrently "burst" ((,,) <$> attempt "1" <*> attempt "2" <*> attempt "3")
  expectAfterActions $ within evidenceWindow $ do
    agreeOn "same-order" "orderId" orderId a (b :| [c])
    holds "one-creation" (traverse fromRef (a :| [b, c])) (predicate "single-created" ((== 1) . length . NonEmpty.filter created))
  checkEffect key

idempotencyEntries :: [Entry]
idempotencyEntries = [entry retryScenario 1, entry concurrentDuplicates 3]
  where
    entry selected participants =
      Entry
        selected
        (LogicalInput "orders-v1" [])
        [ ("demo", \_ _ -> SomeBinding (ordersBindingFor Idempotent False participants)),
          ("non-idempotent", \_ _ -> SomeBinding (ordersBindingFor NonIdempotent False participants)),
          ("race-prone", \_ _ -> SomeBinding (ordersBindingFor RaceProne False participants))
        ]
        (\_ -> pure (Right (Nothing, Nothing)))
