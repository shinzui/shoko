module Consumer.Account (Account (..), accountScenario, rejectionScenario, memoryBinding, testEnvironment, testOptions) where

import Data.IORef
import Data.Set qualified as Set
import Shoko
import Shoko.Prelude (Text)

data Account a where
  Qualified :: Account Text
  Create :: Input Text -> Bool -> Account Bool
  Created :: Input Bool -> Account Bool
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
accountScenario = scenario "toy-account" "Provision a toy account" "v1" $ do
  qualified <- given "agent" (accept ["ready"] Qualified)
  created <- act "create" (accept ["created"] (Create (fromRef qualified) True))
  expect $ eventually "account-exists" (observe "is-created" (Created (fromRef created)) id)

rejectionScenario :: Scenario Account
rejectionScenario = scenario "toy-rejection" "Reject invalid toy input" "v1" $ do
  qualified <- given "agent" (accept ["ready"] Qualified)
  created <- act "reject" (accept ["invalid-input"] (Create (fromRef qualified) False))
  expect $ eventually "rejected" (observe "not-created" (Created (fromRef created)) not)

testEnvironment :: Environment
testEnvironment = Environment "local" False (Set.fromList [minBound .. maxBound]) defaultPolicy

testOptions :: RunOptions
testOptions = RunOptions "test-run" True "test-binary-v1" Nothing Nothing

memoryBinding :: IORef Int -> Binding Account ()
memoryBinding calls =
  Binding
    "memory"
    Set.empty
    describe
    (modifyIORef' calls (+ 1))
    (const (pure Cleaned))
    (\_ source -> pure (Right (Baseline source 0 Nothing)))
    perform
    readObservation
  where
    describe :: Account a -> Maybe BindingContract
    describe Missing = Nothing
    describe _ = Just (BindingContract Set.empty Set.empty (Set.singleton BusinessKey) (Just "memory") SampledState)
    perform :: () -> CallContext -> Account a -> IO (ActionOutcome a)
    perform _ _ Qualified = pure (ActionObserved "ready" "SECRET-FIXTURE-SENTINEL")
    perform _ (CallContext resolve _ _ _ runSubstep) (Create input valid) =
      case resolve input of
        Left _ -> pure (ActionUnavailable "unresolved-reference")
        Right _ -> do
          _ <- runSubstep "check" (pure ())
          if valid
            then do
              _ <- runSubstep "write" (modifyIORef' calls (+ 1))
              pure (ActionObserved "created" True)
            else pure (ActionObserved "invalid-input" False)
    perform _ _ _ = pure (ActionUnavailable "not-an-action")
    readObservation :: () -> CallContext -> Account a -> IO (ObservationOutcome a)
    readObservation _ (CallContext resolve deadline _ _ _) (Created input) = pure $ case resolve input of
      Left _ -> ObservationUnavailable "unresolved-reference"
      Right value -> Observed [Occurrence Nothing value] (Coverage SampledState 0 deadline True)
    readObservation _ _ _ = pure (ObservationUnavailable "not-an-observation")
