module Consumer.Idempotency where

import Data.IORef
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Shoko
import Shoko.Clock
import Shoko.Prelude (Generic, Text)
import Text.Read (readMaybe)

data Submission = Submission {orderId :: !Text, created :: !Bool}
  deriving stock (Eq, Show, Generic)

data Orders a where
  NewKey :: Orders Text
  Submit :: Input Text -> Input Text -> Orders Submission
  OrderPlaced :: Input Text -> Orders Bool
  SameOrder :: Input Submission -> Input Submission -> Orders Bool

instance Vocabulary Orders where
  describeOperation NewKey = declareOperation "orders.new-key" []
  describeOperation (Submit key payload) = dependsOn ((,) <$> key <*> payload) (declareOperation "orders.submit" [WriteState])
  describeOperation (OrderPlaced key) = dependsOn key (declareOperation "orders.placed" [ReadEvents])
  describeOperation (SameOrder a b) = dependsOn ((,) <$> a <*> b) (declareOperation "orders.same" [])

data Behavior = Idempotent | NonIdempotent | RaceProne
  deriving stock (Eq, Show)

data OrdersResource = OrdersResource
  { ledger :: !(IORef (Map.Map Text (Text, Text))),
    history :: !(IORef [Text]),
    sequenceNumber :: !(IORef Int)
  }

ordersBinding :: Behavior -> Binding Orders OrdersResource
ordersBinding behavior = ordersBindingWith behavior False

ordersBindingWith :: Behavior -> Bool -> Binding Orders OrdersResource
ordersBindingWith behavior unavailable = binding "orders" acquire (const (pure Cleaned)) handlers
  where
    acquire _ = OrdersResource <$> newIORef Map.empty <*> newIORef [] <*> newIORef 0
    handlers :: OperationRole -> Orders a -> Either HandlerBuildError (Maybe (Handler OrdersResource a))
    handlers FixtureOperation NewKey = Right (Just (actionHandler noRequirements (\_ _ -> pure (ActionObserved "issued" "key-1"))))
    handlers ActionOperation (Submit key payload) = Right (Just (actionHandler noRequirements (submit key payload)))
    handlers ObservationOperation (OrderPlaced key) = Right (Just (observationHandler noRequirements (RequiresBusinessKey (BusinessKeyName "idempotencyKey")) source (poll key)))
    handlers ObservationOperation (SameOrder a b) =
      Right
        ( Just
            ( observationHandler
                noRequirements
                (RequiresBusinessKey (BusinessKeyName "idempotencyKey"))
                (sampledSource (SourceId "fabricated-comparison"))
                ( \_ context -> do
                    left <- resolveInput context a
                    right <- resolveInput context b
                    let Clock now _ _ _ = callClock context
                    tick <- now
                    pure $ case (left, right) of
                      (Right x, Right y) -> Observed [Occurrence Nothing (orderId x == orderId y)] (Coverage SampledState tick tick True)
                      _ -> ObservationUnavailable "missing-response"
                )
            )
        )
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
          candidate <- atomicModifyIORef' (sequenceNumber resource) (\n -> (n + 1, "order-" <> Text.pack (show n)))
          (tag, result) <- atomicModifyIORef' (ledger resource) $ \entries ->
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
  _ <- act "original" (accept ["created"] (Submit (fromRef key) (pure "basket-1")))
  _ <- act "retry" (accept tags (Submit (fromRef key) (pure "basket-1")))
  checkEffect key

conflictScenario :: Scenario Orders
conflictScenario = scenario "payload-conflict" "Reject changed payload" "v1" $ do
  key <- given "key" (accept ["issued"] NewKey)
  _ <- act "original" (accept ["created"] (Submit (fromRef key) (pure "basket-1")))
  _ <- act "conflict" (accept ["key-conflict"] (Submit (fromRef key) (pure "basket-2")))
  checkEffect key

checkEffect :: Ref Text -> ScenarioBuilder Orders ()
checkEffect key = do
  selected <- correlate (CorrelationAlias "order") (BusinessKeyName "idempotencyKey") (fromRef key)
  expect $ within evidenceWindow $ exactlyOnce "one-effect" $ correlatedBy selected $ observeThat (OrderPlaced (fromRef key)) (predicate "placed" id)

evidenceWindow :: Duration
evidenceWindow = either (error . Text.unpack) id (milliseconds 20)
