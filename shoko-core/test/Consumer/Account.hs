module Consumer.Account (Account (..), AccountStore, accountScenario, rejectionScenario, memoryBinding, alternateBinding, testEnvironment, testOptions) where

import Data.IORef
import Data.Set qualified as Set
import Shoko
import Shoko.Clock
import Shoko.Prelude (Text)

data Account a where
  Qualified :: Account Text
  Create :: Input Text -> Bool -> Account Text
  Created :: Input Text -> Account Bool
  Missing :: Account Bool

instance Vocabulary Account where
  describeOperation Qualified = OperationInfo "qualified-fixture" (Set.singleton SyntheticResource) [] []
  describeOperation (Create input _) =
    OperationInfo
      "create-account"
      (Set.singleton WriteState)
      (inputDependencies input)
      [("check", Set.singleton ReadState), ("write", Set.singleton WriteState)]
  describeOperation (Created input) = OperationInfo "account-created" (Set.singleton ReadState) (inputDependencies input) []
  describeOperation Missing = OperationInfo "missing" Set.empty [] []

accountScenario :: Scenario Account
accountScenario = scenario "toy-account" "Provision a toy account" "v2" $ do
  qualified <- given "agent" (accept ["ready"] Qualified)
  created <- act "create" (accept ["created"] (Create (fromRef qualified) True))
  expect $ eventually "account-exists" (observe "is-created" (Created (fromRef created)) id)

rejectionScenario :: Scenario Account
rejectionScenario = scenario "toy-rejection" "Reject invalid toy input" "v2" $ do
  qualified <- given "agent" (accept ["ready"] Qualified)
  rejected <- act "reject" (accept ["invalid-input"] (Create (fromRef qualified) False))
  expect $ eventually "no-account-created" (observe "absent" (Created (fromRef rejected)) not)

testEnvironment :: Environment
testEnvironment = Environment "local" False (Set.fromList [minBound .. maxBound]) defaultPolicy

testOptions :: RunOptions
testOptions = RunOptions "test-run" True "test-binary-v1" Nothing Nothing

-- Two distinct storage/vocabulary implementations of the same domain contract.
data AccountStore = AccountSet !(IORef (Set.Set Text)) | CreateLog !(IORef [Text])

memoryBinding :: IORef Int -> Binding Account AccountStore
memoryBinding = bindingUsing False

alternateBinding :: IORef Int -> Binding Account AccountStore
alternateBinding = bindingUsing True

bindingUsing :: Bool -> IORef Int -> Binding Account AccountStore
bindingUsing useLog calls = Binding sourceName Set.empty describe acquire (const (pure Cleaned)) capture perform readObservation
  where
    sourceName = if useLog then "account-create-log" else "account-set"
    acquire _ = do
      modifyIORef' calls (+ 1)
      if useLog then CreateLog <$> newIORef [] else AccountSet <$> newIORef Set.empty
    capture _ (Clock now _ _ _) source = do
      tick <- now
      pure (Right (Baseline source tick Nothing))
    describe :: OperationRole -> Account a -> Maybe BindingContract
    describe FixtureOperation Qualified = Just available
    describe ActionOperation (Create _ _) = Just available
    describe ObservationOperation (Created _) = Just available
    describe _ _ = Nothing
    available = BindingContract Set.empty Set.empty (Set.singleton BusinessKey) (Just sourceName) SampledState
    perform :: AccountStore -> CallContext -> Account a -> IO (ActionOutcome a)
    perform _ _ Qualified = pure (ActionObserved "ready" "SECRET-FIXTURE-SENTINEL")
    perform resource (CallContext resolve _ _ _ runSubstep _ _) (Create input valid) =
      case resolve input of
        Left _ -> pure (ActionUnavailable "unresolved-reference")
        Right _ -> do
          _ <- runSubstep "check" (pure ())
          if valid
            then do
              _ <- runSubstep "write" $ do
                modifyIORef' calls (+ 1)
                case resource of
                  AccountSet rows -> modifyIORef' rows (Set.insert "toy-key")
                  CreateLog rows -> modifyIORef' rows (++ ["account-created:toy-key"])
              pure (ActionObservedWithDetails "created" "toy-key" [("accounts-written", PublicCount 1)])
            else pure (ActionObservedWithDetails "invalid-input" "toy-key" [("rejection", PublicChoice "invalid-input")])
    perform _ _ _ = pure (ActionUnavailable "not-an-action")
    readObservation :: AccountStore -> CallContext -> Account a -> IO (ObservationOutcome a)
    readObservation resource (CallContext resolve _ _ selected _ _ (Clock now _ _ _)) (Created input) = case (resolve input, selected) of
      (Right key, Just (ByBusinessKey _ selectedKey)) | key == selectedKey -> do
        found <- case resource of
          AccountSet rows -> Set.member key <$> readIORef rows
          CreateLog rows -> elem ("account-created:" <> key) <$> readIORef rows
        tick <- now
        pure (ObservedWithDetails [Occurrence Nothing found] (Coverage SampledState tick tick True) [("exists", PublicFlag found)])
      _ -> pure (ObservationUnavailable "correlation-lost")
    readObservation _ _ _ = pure (ObservationUnavailable "not-an-observation")
