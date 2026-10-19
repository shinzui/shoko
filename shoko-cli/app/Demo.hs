module Demo (registry) where

import Data.IORef
import Data.Set qualified as Set
import Shoko
import Shoko.Cli.Config (Credentials, HostConfig)
import Shoko.Cli.Registry
import Shoko.Clock (monotonic)
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
entry name tag written unavailable fault synthetic = Entry description (LogicalInput "demo-v1" []) [("demo", factory)] (\_ -> pure (Right (Nothing, Nothing)))
  where
    description = scenario name "Labelled in-memory verifier demo" "v1" $ do
      key <- act "create" (accept [tag] Create)
      selected <- correlate (CorrelationAlias "demo") (BusinessKeyName "demo-key") (fromRef key)
      expect (eventually "demo-state" (correlatedBy selected $ observe "expected-state" (Exists (fromRef key)) (if tag == "invalid-input" then not else id)))
    factory :: HostConfig -> Maybe Credentials -> SomeBinding Op
    factory _ _ =
      SomeBinding
        ( requiringLifecycle [SyntheticResource | synthetic] $
            binding "demo" (\_ -> newIORef False) (\_ -> pure Cleaned) handlers
        )
    handlers :: forall a. OperationRole -> Op a -> Either HandlerBuildError (Maybe (Handler (IORef Bool) a))
    handlers ActionOperation op@Create = Right (Just (actionHandler noRequirements (\resource call -> action resource call op)))
    handlers ObservationOperation op@(Exists _) = Right (Just (observationHandler noRequirements (RequiresBusinessKey (BusinessKeyName "demo-key")) (sampledSource (SourceId "demo-state")) (\resource call -> observation resource call op)))
    handlers _ _ = Right Nothing
    action :: forall a. IORef Bool -> CallContext -> Op a -> IO (ActionOutcome a)
    action state _ Create
      | fault = fail "PRIVATE-DEMO-FAULT-SENTINEL"
      | otherwise = writeIORef state written >> pure (ActionObservedWithDetails tag "demo-business-key" [("demo-detail", PublicChoice "visible-demo-summary")])
    action _ _ _ = pure (ActionUnavailable "unsupported-role")
    observation :: forall a. IORef Bool -> CallContext -> Op a -> IO (ObservationOutcome a)
    observation state call (Exists input)
      | unavailable = pure (ObservationUnavailable "demo-source-unavailable")
      | otherwise = guardCorrelation (BusinessKeyName "demo-key") input call $ do
          value <- readIORef state
          tick <- monotonic (callClock call)
          pure (Observed [Occurrence Nothing value] (Coverage SampledState tick tick True))
    observation _ _ _ = pure (ObservationUnavailable "unsupported-role")
