module Consumer.Account (Account (..), AccountStore, accountScenario, rejectionScenario, memoryBinding, alternateBinding, testEnvironment, testOptions, accountHooks, accountBindingWith) where

import Consumer.Hooks
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
bindingUsing useLog calls = accountBindingNamed (if useLog then "account-create-log" else "account-set") (hooksUsing useLog calls)

accountBindingWith :: Hooks Account AccountStore -> Binding Account AccountStore
accountBindingWith = accountBindingNamed "account-set"

accountBindingNamed :: Text -> Hooks Account AccountStore -> Binding Account AccountStore
accountBindingNamed name (Hooks acquire release capture perform poll) = binding name acquire release handlers
  where
    handlers :: OperationRole -> Account a -> Either HandlerBuildError (Maybe (Handler AccountStore a))
    handlers FixtureOperation op@Qualified = Right (Just (actionHandler noRequirements (\resource call -> perform resource call op)))
    handlers ActionOperation op@(Create _ _) = Right (Just (actionHandler noRequirements (\resource call -> perform resource call op)))
    handlers ObservationOperation op@(Created _) = Right (Just (observationHandler noRequirements (RequiresBusinessKey (BusinessKeyName "accountId")) (newSource (SourceId name) SampledState (\resource clock -> capture resource clock (SourceId name))) (\resource call -> poll resource call op)))
    handlers _ _ = Right Nothing

accountHooks :: IORef Int -> Hooks Account AccountStore
accountHooks = hooksUsing False

hooksUsing :: Bool -> IORef Int -> Hooks Account AccountStore
hooksUsing useLog calls = Hooks acquire (const (pure Cleaned)) capture perform readObservation
  where
    acquire _ = do
      modifyIORef' calls (+ 1)
      if useLog then CreateLog <$> newIORef [] else AccountSet <$> newIORef Set.empty
    capture _ clock label = do
      tick <- monotonic clock
      pure (Right (Baseline label tick Nothing))
    perform :: AccountStore -> CallContext -> Account a -> IO (ActionOutcome a)
    perform _ _ Qualified = pure (ActionObserved "ready" "SECRET-FIXTURE-SENTINEL")
    perform resource context (Create input valid) = do
      resolved <- resolveInput context input
      case resolved of
        Left _ -> pure (ActionUnavailable "unresolved-reference")
        Right _ -> do
          _ <- runSubstep context "check" (pure ())
          if valid
            then do
              _ <- runSubstep context "write" $ do
                modifyIORef' calls (+ 1)
                case resource of
                  AccountSet rows -> modifyIORef' rows (Set.insert "toy-key")
                  CreateLog rows -> modifyIORef' rows (++ ["account-created:toy-key"])
              pure (ActionObservedWithDetails "created" "toy-key" [("accounts-written", PublicCount 1)])
            else pure (ActionObservedWithDetails "invalid-input" "toy-key" [("rejection", PublicChoice "invalid-input")])
    perform _ _ _ = pure (ActionUnavailable "not-an-action")
    readObservation :: AccountStore -> CallContext -> Account a -> IO (ObservationOutcome a)
    readObservation resource context (Created input) = guardCorrelation (BusinessKeyName "accountId") input context $ do
      resolved <- resolveInput context input
      case resolved of
        Left _ -> pure (ObservationUnavailable "input")
        Right key -> do
          found <- case resource of
            AccountSet rows -> Set.member key <$> readIORef rows
            CreateLog rows -> elem ("account-created:" <> key) <$> readIORef rows
          tick <- monotonic (callClock context)
          pure (ObservedWithDetails [Occurrence Nothing found] (Coverage SampledState tick tick True) [("exists", PublicFlag found)])
    readObservation _ _ _ = pure (ObservationUnavailable "not-an-observation")
