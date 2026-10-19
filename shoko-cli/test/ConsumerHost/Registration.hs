module Registration (registrationEntries) where

import Data.IORef
import Data.Set qualified as Set
import Data.Text qualified as Text
import Shoko
import Shoko.Cli
import Shoko.Clock (monotonic)
import Shoko.Result (LogicalInput (..))
import System.Environment (lookupEnv)

-- These two vocabularies belong to this independent public-package consumer.
data Registration a where
  Qualified :: Registration Text.Text
  Complete :: Input Text.Text -> Registration Text.Text
  Registered :: Input Text.Text -> Registration Bool

instance Vocabulary Registration where
  describeOperation Qualified = declareOperation "registration.qualify" []
  describeOperation (Complete input) = dependsOn input (declareOperation "registration.complete" [WriteState])
  describeOperation (Registered input) = dependsOn input (declareOperation "registration.registered" [ReadState])

data Accounts a where
  CreateAccount :: Input Text.Text -> Accounts Text.Text
  AccountExists :: Input Text.Text -> Accounts Bool

instance Vocabulary Accounts where
  describeOperation (CreateAccount input) = dependsOn input (declareOperation "accounts.create" [WriteState])
  describeOperation (AccountExists input) = dependsOn input (declareOperation "accounts.exists" [ReadState])

registrationBlock :: ScenarioBuilder Registration (Ref Text.Text, CorrelationRef)
registrationBlock = do
  qualified <- given "qualified" (accept ["ready"] Qualified)
  registered <- act "complete" (accept ["completed"] (Complete (fromRef qualified)))
  selected <- correlate (CorrelationAlias "registration") (BusinessKeyName "registrationId") (fromRef registered)
  expectAfterActions $
    eventually "registered" $
      correlatedBy selected $
        observeThat (Registered (fromRef registered)) (predicate "exists" id .&&. negated (predicate "absent" not))
  pure (registered, selected)

accountBlock :: Ref Text.Text -> ScenarioBuilder Accounts ()
accountBlock owner = do
  account <- act "create-account" (accept ["created"] (CreateAccount (fromRef owner)))
  selected <- correlate (CorrelationAlias "account") (BusinessKeyName "accountId") (fromRef account)
  expectAfterActions $
    eventually "account-exists" $
      correlatedBy selected $
        observeThat (AccountExists (fromRef account)) (predicate "exists" id)

registrationAlone :: Scenario Registration
registrationAlone = scenario "registration-alone" "Register one entity" "v1" (registrationBlock >> pure ())

registrationReused :: Scenario Registration
registrationReused = scenario "registration-reused" "Reuse the registration workflow" "v1" (registrationBlock >> pure ())

composedRegistration :: Scenario (Registration :+: Accounts)
composedRegistration = scenario "composed-registration" "Register two entities and check an account" "v1" $ do
  _ <- namespace "inviter" (hoistScenarioBuilder InL registrationBlock)
  (invitee, _) <- namespace "invitee" (hoistScenarioBuilder InL registrationBlock)
  hoistScenarioBuilder InR (accountBlock invitee)

mark :: IO ()
mark = lookupEnv "SHOKO_TEST_COUNTER" >>= maybe (pure ()) (\path -> appendFile path "effect\n")

registrationBinding :: Binding Registration (IORef (Set.Set Text.Text), IORef Int)
registrationBinding = binding "registration-memory" (\_ -> mark >> ((,) <$> newIORef Set.empty <*> newIORef 0)) (\_ -> mark >> pure Cleaned) handlers
  where
    handlers :: OperationRole -> Registration a -> Either HandlerBuildError (Maybe (Handler (IORef (Set.Set Text.Text), IORef Int) a))
    handlers FixtureOperation Qualified = Right $ Just $ actionHandler noRequirements $ \(_, sequenceNumber) _ -> do
      index <- atomicModifyIORef' sequenceNumber (\old -> (old + 1, old + 1))
      pure (ActionObservedWithDetails "ready" ("agent-" <> Text.pack (show index)) [("allocation", PublicCount (toInteger index))])
    handlers ActionOperation (Complete input) = Right $ Just $ actionHandler noRequirements $ \(rows, _) call ->
      resolveInput call input >>= \case
        Left _ -> pure (ActionUnavailable "input-unavailable")
        Right agent -> do
          let registration = "registration-" <> agent
          modifyIORef' rows (Set.insert registration)
          pure (ActionObserved "completed" registration)
    handlers ObservationOperation (Registered input) = Right $ Just $ observationHandler noRequirements (RequiresBusinessKey (BusinessKeyName "registrationId")) (sampledSource (SourceId "registration.state")) $ \(rows, _) call ->
      guardCorrelation (BusinessKeyName "registrationId") input call $ do
        answer <- resolveInput call input
        found <- case answer of Right key -> Set.member key <$> readIORef rows; _ -> pure False
        tick <- monotonic (callClock call)
        pure (Observed [Occurrence Nothing found] (Coverage SampledState tick tick True))
    handlers _ _ = Right Nothing

accountsBinding :: Binding Accounts (IORef (Set.Set Text.Text))
accountsBinding = binding "accounts-memory" (\_ -> mark >> newIORef Set.empty) (\_ -> mark >> pure Cleaned) handlers
  where
    handlers :: OperationRole -> Accounts a -> Either HandlerBuildError (Maybe (Handler (IORef (Set.Set Text.Text)) a))
    handlers ActionOperation (CreateAccount input) = Right $ Just $ actionHandler noRequirements $ \rows call ->
      resolveInput call input >>= \case
        Left _ -> pure (ActionUnavailable "input-unavailable")
        Right registration -> do
          let account = "account-" <> registration
          modifyIORef' rows (Set.insert account)
          pure (ActionObserved "created" account)
    handlers ObservationOperation (AccountExists input) = Right $ Just $ observationHandler noRequirements (RequiresBusinessKey (BusinessKeyName "accountId")) (sampledSource (SourceId "accounts.state")) $ \rows call ->
      guardCorrelation (BusinessKeyName "accountId") input call $ do
        answer <- resolveInput call input
        found <- case answer of Right key -> Set.member key <$> readIORef rows; _ -> pure False
        tick <- monotonic (callClock call)
        pure (Observed [Occurrence Nothing found] (Coverage SampledState tick tick True))
    handlers _ _ = Right Nothing

registrationEntries :: [Entry]
registrationEntries =
  [ entry registrationAlone registrationBinding,
    entry registrationReused registrationBinding,
    entry composedRegistration (combineBindings "composed-memory" registrationBinding accountsBinding)
  ]
  where
    entry :: (Vocabulary op) => Scenario op -> Binding op resource -> Entry
    entry source selected = Entry source (LogicalInput "registration-memory-v1" []) [("demo", \_ _ -> SomeBinding selected)] (\_ -> pure (Right (Nothing, Nothing)))
