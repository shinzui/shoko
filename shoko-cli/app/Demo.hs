module Demo (registry) where

import Data.IORef
import Data.Set qualified as Set
import Shoko
import Shoko.Cli.Config (Credentials, HostConfig)
import Shoko.Cli.Registry
import Shoko.Clock (Clock (..))
import Shoko.Prelude
import Shoko.Result (LogicalInput (..))

data Op a where
  Create :: Op Text
  Exists :: Input Text -> Op Bool

instance Vocabulary Op where
  describeOperation Create = OperationInfo "demo-create" (Set.singleton WriteState) [] []
  describeOperation (Exists key) = OperationInfo "demo-exists" (Set.singleton ReadState) (inputDependencies key) []

registry :: Registry
registry =
  Registry
    ["local"]
    [ entry "demo-account-created" "created" True False False False,
      entry "demo-missing-evidence" "created" False False False False,
      entry "demo-source-unavailable" "created" False True False False,
      entry "demo-expected-rejection" "invalid-input" False False False False,
      entry "demo-runner-fault" "created" False False True False,
      entry "demo-synthetic" "created" True False False True
    ]

entry :: Text -> Text -> Bool -> Bool -> Bool -> Bool -> Entry
entry name tag written unavailable fault synthetic = Entry description (businessKeyFromResult "demo-key" "create") (LogicalInput "demo-v1" []) [("demo", factory)] (\_ -> pure (Right (Nothing, Nothing)))
  where
    description = scenario name "Labelled in-memory verifier demo" "v1" $ do
      key <- act "create" (accept [tag] Create)
      expect (eventually "demo-state" (observe "expected-state" (Exists (fromRef key)) (if tag == "invalid-input" then not else id)))
    factory :: HostConfig -> Maybe Credentials -> SomeBinding Op
    factory _ _ =
      SomeBinding
        ( Binding
            "demo"
            (if synthetic then Set.singleton SyntheticResource else Set.empty)
            contract
            (\_ -> newIORef False)
            (\_ -> pure Cleaned)
            (\_ (Clock now _ _ _) source -> do tick <- now; pure (Right (Baseline source tick Nothing)))
            action
            observation
        )
    contract :: forall a. OperationRole -> Op a -> Maybe BindingContract
    contract ActionOperation Create = Just (BindingContract Set.empty Set.empty (Set.singleton BusinessKey) Nothing SampledState)
    contract ObservationOperation (Exists _) = Just (BindingContract Set.empty Set.empty (Set.singleton BusinessKey) (Just "demo-state") SampledState)
    contract _ _ = Nothing
    action :: forall a. IORef Bool -> CallContext -> Op a -> IO (ActionOutcome a)
    action state _ Create
      | fault = fail "PRIVATE-DEMO-FAULT-SENTINEL"
      | otherwise = writeIORef state written >> pure (ActionObservedWithDetails tag "demo-business-key" [("demo-detail", PublicChoice "visible-demo-summary")])
    action _ _ _ = pure (ActionUnavailable "unsupported-role")
    observation :: forall a. IORef Bool -> CallContext -> Op a -> IO (ObservationOutcome a)
    observation state (CallContext resolve _ _ selected _ _ (Clock now _ _ _)) (Exists input)
      | unavailable = pure (ObservationUnavailable "demo-source-unavailable")
      | otherwise = case (resolve input, selected) of
          (Right key, Just (ByBusinessKey "demo-key" selectedKey)) | key == selectedKey -> do
            value <- readIORef state
            tick <- now
            pure (Observed [Occurrence Nothing value] (Coverage SampledState tick tick True))
          _ -> pure (ObservationUnavailable "correlation-lost")
    observation _ _ _ = pure (ObservationUnavailable "unsupported-role")
