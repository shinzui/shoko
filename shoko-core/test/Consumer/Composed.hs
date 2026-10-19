module Consumer.Composed (Composed (..), composedScenario, qualifiedAgent, completeRegistration, composedBinding) where

import Data.IORef
import Shoko
import Shoko.Clock
import Shoko.Prelude (Text)

data Composed a where
  Qualified :: Composed Text
  Complete :: Input Text -> Composed Text
  Finish :: Input Text -> Composed ()
  Registered :: Input Text -> Composed Bool

instance Vocabulary Composed where
  describeOperation Qualified = declareOperation "registration.qualify" [SyntheticResource]
  describeOperation (Complete input) = dependsOn input (declareOperation "registration.complete" [WriteState])
  describeOperation (Finish input) = dependsOn input (declareOperation "registration.finish" [WriteState])
  describeOperation (Registered input) = dependsOn input (declareOperation "registration.registered" [ReadState])

qualifiedAgent :: ScenarioBuilder Composed (Ref Text)
qualifiedAgent = given "qualified" (accept ["ready"] Qualified)

completeRegistration :: Ref Text -> ScenarioBuilder Composed (Ref Text)
completeRegistration agent = do
  registered <- act "complete" (accept ["completed"] (Complete (fromRef agent)))
  expectAfterActions $ eventually "registered" $ observeThat (Registered (fromRef registered)) (predicate "exists" id .&&. negated (predicate "absent" not))
  pure registered

composedScenario :: Scenario Composed
composedScenario = scenario "composed" "Reusable workflow blocks" "v1" $ do
  first <- namespace "inviter" qualifiedAgent
  second <- namespace "invitee" qualifiedAgent
  registered <- namespace "invitee" (completeRegistration second)
  _ <- act "finish" (accept ["finished"] (Finish ((<>) <$> fromRef first <*> fromRef registered)))
  pure ()

-- The log proves deferred observations start only after the last action.
composedBinding :: IORef [Text] -> Binding Composed (IORef [Text])
composedBinding logRef = binding "composed" (const (pure logRef)) (const (pure Cleaned)) inventory
  where
    inventory :: OperationRole -> Composed a -> Either HandlerBuildError (Maybe (Handler (IORef [Text]) a))
    inventory ObservationOperation op@(Registered _) = Right (Just (observationHandler noRequirements (RequiresBusinessKey (BusinessKeyName "registrationId")) (sampledSource (SourceId "registration")) (\resource call -> poll resource call op)))
    inventory FixtureOperation op@Qualified = Right (Just (actionHandler noRequirements (\resource call -> perform resource call op)))
    inventory ActionOperation op@(Complete _) = Right (Just (actionHandler noRequirements (\resource call -> perform resource call op)))
    inventory ActionOperation op@(Finish _) = Right (Just (actionHandler noRequirements (\resource call -> perform resource call op)))
    inventory _ _ = Right Nothing
    perform :: IORef [Text] -> CallContext -> Composed a -> IO (ActionOutcome a)
    perform log' _ Qualified = modifyIORef' log' (++ ["qualified"]) >> pure (ActionObserved "ready" "agent")
    perform log' call (Complete input) =
      resolveInput call input >>= \case
        Left _ -> pure (ActionUnavailable "input")
        Right value -> modifyIORef' log' (++ [value]) >> pure (ActionObserved "completed" "registration")
    perform log' call (Finish input) =
      resolveInput call input >>= \case
        Left _ -> pure (ActionUnavailable "input")
        Right _ -> modifyIORef' log' (++ ["finished"]) >> pure (ActionObserved "finished" ())
    perform _ _ _ = pure (ActionUnavailable "role")
    poll :: IORef [Text] -> CallContext -> Composed a -> IO (ObservationOutcome a)
    poll log' call (Registered input) =
      resolveInput call input >>= \case
        Left _ -> pure (ObservationUnavailable "input")
        Right _ -> do
          events <- readIORef log'
          modifyIORef' log' (++ ["polled"])
          tick <- monotonic (callClock call)
          pure (Observed [Occurrence Nothing ("finished" `elem` events)] (Coverage SampledState tick tick True))
    poll _ _ _ = pure (ObservationUnavailable "role")
