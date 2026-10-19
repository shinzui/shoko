{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Consumer.Composed (Registration (..), registrationBlock, registrationAlone, registrationReused, composedRegistration, registrationBinding, registrationBindingWith, accountBlock, accountsBinding, Accounts (..), combinedScenario, combinedBinding, registrationWorkflow, memberQualification, composedScenario, qualifiedAgent, completeRegistration, composedBinding) where

import Data.IORef
import Data.Set qualified as Set
import Data.String (fromString)
import Shoko
import Shoko.Clock
import Shoko.Prelude (Text)

data Registration a where
  Qualified :: Registration Text
  Complete :: Input Text -> Registration Text
  Finish :: Input Text -> Registration ()
  Registered :: Input Text -> Registration Bool

instance Vocabulary Registration where
  describeOperation Qualified = declareOperation "registration.qualify" [SyntheticResource]
  describeOperation (Complete input) = dependsOn input (declareOperation "registration.complete" [WriteState])
  describeOperation (Finish input) = dependsOn input (declareOperation "registration.finish" [WriteState])
  describeOperation (Registered input) = dependsOn input (declareOperation "registration.registered" [ReadState])

qualifiedAgent :: ScenarioBuilder Registration (Ref Text)
qualifiedAgent = given "qualified" (accept ["ready"] Qualified)

completeRegistration :: Ref Text -> ScenarioBuilder Registration (Ref Text)
completeRegistration agent = do
  registered <- act "complete" (accept ["completed"] (Complete (fromRef agent)))
  selected <- correlate (CorrelationAlias "registration") (BusinessKeyName "registrationId") (fromRef registered)
  expectAfterActions $ eventually "registered" $ correlatedBy selected $ observeThat (Registered (fromRef registered)) (predicate "exists" id .&&. negated (predicate "absent" not))
  pure registered

composedScenario :: Scenario Registration
composedScenario = scenario "composed" "Reusable workflow blocks" "v1" $ do
  first <- namespace "inviter" qualifiedAgent
  second <- namespace "invitee" qualifiedAgent
  registered <- namespace "invitee" (completeRegistration second)
  _ <- act "finish" (accept ["finished"] (Finish ((<>) <$> fromRef first <*> fromRef registered)))
  pure ()

-- The log proves deferred observations start only after the last action.
composedBinding :: IORef [Text] -> Binding Registration (IORef [Text])
composedBinding logRef = binding "composed" (const (pure logRef)) (const (pure Cleaned)) inventory
  where
    inventory :: OperationRole -> Registration a -> Either HandlerBuildError (Maybe (Handler (IORef [Text]) a))
    inventory ObservationOperation op@(Registered _) = Right (Just (observationHandler noRequirements (RequiresBusinessKey (BusinessKeyName "registrationId")) (sampledSource (SourceId "registration")) (\resource call -> poll resource call op)))
    inventory FixtureOperation op@Qualified = Right (Just (actionHandler noRequirements (\resource call -> perform resource call op)))
    inventory ActionOperation op@(Complete _) = Right (Just (actionHandler noRequirements (\resource call -> perform resource call op)))
    inventory ActionOperation op@(Finish _) = Right (Just (actionHandler noRequirements (\resource call -> perform resource call op)))
    inventory _ _ = Right Nothing
    perform :: IORef [Text] -> CallContext -> Registration a -> IO (ActionOutcome a)
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
    poll :: IORef [Text] -> CallContext -> Registration a -> IO (ObservationOutcome a)
    poll log' call (Registered input) =
      resolveInput call input >>= \case
        Left _ -> pure (ObservationUnavailable "input")
        Right _ -> do
          events <- readIORef log'
          modifyIORef' log' (++ ["polled"])
          tick <- monotonic (callClock call)
          pure (Observed [Occurrence Nothing ("finished" `elem` events)] (Coverage SampledState tick tick True))
    poll _ _ _ = pure (ObservationUnavailable "role")

-- An ordinary concrete producer; consumers can lift it without changing its definition.
registrationWorkflow :: ScenarioBuilder Registration (Ref Text)
registrationWorkflow = do
  qualified <- qualifiedAgent
  registered <- completeRegistration qualified
  _ <- act "finish" (accept ["finished"] (Finish (fromRef registered)))
  pure registered

memberQualification :: (Member Registration op) => ScenarioBuilder op (Ref Text)
memberQualification = given "qualified" (accept ["ready"] (inject Qualified))

data Accounts a where
  AccountFor :: Input Text -> Accounts Text
  AccountExists :: Input Text -> Accounts Bool

instance Vocabulary Accounts where
  describeOperation (AccountFor input) = dependsOn input (declareOperation "accounts.create" [WriteState])
  describeOperation (AccountExists input) = dependsOn input (declareOperation "accounts.exists" [ReadState])

accountBlock :: Ref Text -> ScenarioBuilder Accounts ()
accountBlock owner = do
  account <- act "account" (accept ["created"] (AccountFor (fromRef owner)))
  selected <- correlate (CorrelationAlias "account") (BusinessKeyName "accountId") (fromRef account)
  expectAfterActions $ eventually "account-exists" $ correlatedBy selected $ observeThat (AccountExists (fromRef account)) (predicate "exists" id)

combinedScenario :: Scenario (Registration :+: Accounts)
combinedScenario = scenario "combined" "Two contexts" "1" $ do
  _ <- namespace "inviter" (hoistScenarioBuilder InL registrationWorkflow)
  invitee <- namespace "invitee" (hoistScenarioBuilder InL registrationWorkflow)
  hoistScenarioBuilder InR (accountBlock invitee)

combinedBinding :: IORef [Text] -> Binding (Registration :+: Accounts) (IORef [Text], IORef (Set.Set Text))
combinedBinding events = combineBindings "registration-and-accounts" (composedBinding events) accountsBinding

accountsBinding :: Binding Accounts (IORef (Set.Set Text))
accountsBinding = binding "accounts" (const (newIORef Set.empty)) (const (pure Cleaned)) handlers
  where
    handlers :: OperationRole -> Accounts a -> Either HandlerBuildError (Maybe (Handler (IORef (Set.Set Text)) a))
    handlers ActionOperation (AccountFor input) = Right $ Just $ actionHandler noRequirements $ \rows call ->
      resolveInput call input >>= \case
        Left _ -> pure (ActionUnavailable "input")
        Right owner -> let key = "account-" <> owner in modifyIORef' rows (Set.insert key) >> pure (ActionObserved "created" key)
    handlers ObservationOperation (AccountExists input) = Right $ Just $ observationHandler noRequirements (RequiresBusinessKey (BusinessKeyName "accountId")) (sampledSource (SourceId "accounts")) $ \rows call ->
      guardCorrelation (BusinessKeyName "accountId") input call $ do
        value <- resolveInput call input
        found <- case value of Right key -> Set.member key <$> readIORef rows; _ -> pure False
        tick <- monotonic (callClock call)
        pure (Observed [Occurrence Nothing found] (Coverage SampledState tick tick True))
    handlers _ _ = Right Nothing

-- Finished scenarios are thin identity/revision wrappers around one concrete block.
registrationBlock :: ScenarioBuilder Registration (Ref Text, CorrelationRef)
registrationBlock = do
  qualified <- given "qualified" (accept ["ready"] Qualified)
  registered <- act "complete" (accept ["completed"] (Complete (fromRef qualified)))
  selected <- correlate (CorrelationAlias "registration") (BusinessKeyName "registrationId") (fromRef registered)
  expectAfterActions $
    eventually "registered" $
      correlatedBy selected $
        observeThat (Registered (fromRef registered)) (predicate "exists" id .&&. negated (predicate "absent" not))
  pure (registered, selected)

registrationAlone :: Scenario Registration
registrationAlone = scenario "registration-alone" "Register one entity" "v1" (registrationBlock >> pure ())

registrationReused :: Scenario Registration
registrationReused = scenario "registration-reused" "Reuse the registration workflow" "v1" (registrationBlock >> pure ())

composedRegistration :: Scenario (Registration :+: Accounts)
composedRegistration = scenario "composed-registration" "Register two entities and check an account" "v1" $ do
  _ <- namespace "inviter" (hoistScenarioBuilder InL registrationBlock)
  (invitee, _) <- namespace "invitee" (hoistScenarioBuilder InL registrationBlock)
  hoistScenarioBuilder InR (accountBlock invitee)

registrationBinding :: Binding Registration (IORef (Set.Set Text), IORef Int)
registrationBinding = registrationBindingWith False

registrationBindingWith :: Bool -> Binding Registration (IORef (Set.Set Text), IORef Int)
registrationBindingWith emptyFirst = binding "registration" (\_ -> (,) <$> newIORef Set.empty <*> newIORef 0) (const (pure Cleaned)) handlers
  where
    handlers :: OperationRole -> Registration a -> Either HandlerBuildError (Maybe (Handler (IORef (Set.Set Text), IORef Int) a))
    handlers FixtureOperation Qualified = Right $ Just $ actionHandler noRequirements $ \(_, counter) _ -> do
      index <- atomicModifyIORef' counter (\old -> (old + 1, old + 1))
      pure (ActionObserved "ready" ("agent-" <> fromString (show index)))
    handlers ActionOperation (Complete input) = Right $ Just $ actionHandler noRequirements $ \(rows, _) call ->
      resolveInput call input >>= \case
        Left _ -> pure (ActionUnavailable "input")
        Right agent -> do
          let key = if emptyFirst && agent == "agent-1" then "" else "registration-" <> agent
          modifyIORef' rows (Set.insert key)
          pure (ActionObserved "completed" key)
    handlers ActionOperation (Finish input) = Right $ Just $ actionHandler noRequirements $ \_ call ->
      resolveInput call input >>= \case
        Left _ -> pure (ActionUnavailable "input")
        Right _ -> pure (ActionObserved "finished" ())
    handlers ObservationOperation (Registered input) = Right $ Just $ observationHandler noRequirements (RequiresBusinessKey (BusinessKeyName "registrationId")) (sampledSource (SourceId "registration.state")) $ \(rows, _) call ->
      guardCorrelation (BusinessKeyName "registrationId") input call $ do
        resolved <- resolveInput call input
        found <- case resolved of Right key -> Set.member key <$> readIORef rows; _ -> pure False
        tick <- monotonic (callClock call)
        pure (Observed [Occurrence Nothing found] (Coverage SampledState tick tick True))
    handlers _ _ = Right Nothing
