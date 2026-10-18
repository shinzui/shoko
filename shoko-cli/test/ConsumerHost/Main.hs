module Main (main) where

import Data.Aeson (encode)
import Data.ByteString.Lazy.Char8 qualified as BL
import Data.Set qualified as Set
import Shoko
import Shoko.Cli
import Shoko.Cli.Config (configKeys)
import Shoko.Clock (Clock (..))
import Shoko.Result (LogicalInput (..))
import System.Environment (getArgs, lookupEnv)

-- A vocabulary independently owned by this consuming application.
data Decision a where
  Decide :: Bool -> Decision Bool
  ObservedDecision :: Input Bool -> Bool -> Decision Bool

instance Vocabulary Decision where
  describeOperation (Decide _) = OperationInfo "consumer-decision" (Set.singleton WriteState) [] []
  describeOperation (ObservedDecision input _) = OperationInfo "consumer-decision-observation" (Set.singleton ReadState) (inputDependencies input) []

registry :: Registry
registry = Registry ["local"] [entry "consumer-approved" True, entry "consumer-rejected" False]
  where
    entry name approved =
      Entry
        ( scenario name "Independent host decision" "v1" $ do
            result <- act "decide" (accept [if approved then "approved" else "denied"] (Decide approved))
            expect (eventually "decision-evidence" (observe "correct-decision" (ObservedDecision (fromRef result) approved) id))
        )
        (BusinessKeyFrom "case" (pure "consumer-case"))
        (LogicalInput "consumer-v1" [])
        [("demo", \_ _ -> SomeBinding consumerBinding)]
        (\_ -> pure (Right (Nothing, Nothing)))

consumerBinding :: Binding Decision ()
consumerBinding =
  Binding
    "independent-consumer"
    Set.empty
    contract
    (\_ -> mark >> pure ())
    (\_ -> mark >> pure Cleaned)
    (\_ (Clock now _ _ _) source -> do mark; tick <- now; pure (Right (Baseline source tick Nothing)))
    action
    observation
  where
    mark = lookupEnv "SHOKO_TEST_COUNTER" >>= maybe (pure ()) (\path -> appendFile path "effect\n")
    contract :: forall a. OperationRole -> Decision a -> Maybe BindingContract
    contract ActionOperation (Decide _) = Just (BindingContract Set.empty Set.empty (Set.singleton BusinessKey) Nothing SampledState)
    contract ObservationOperation (ObservedDecision _ _) = Just (BindingContract Set.empty Set.empty (Set.singleton BusinessKey) (Just "consumer-state") SampledState)
    contract _ _ = Nothing
    action :: forall a. () -> CallContext -> Decision a -> IO (ActionOutcome a)
    action _ _ (Decide approved) = mark >> pure (ActionObserved (if approved then "approved" else "denied") approved)
    action _ _ _ = pure (ActionUnavailable "unsupported-role")
    observation :: forall a. () -> CallContext -> Decision a -> IO (ObservationOutcome a)
    observation _ (CallContext resolve _ _ _ _ _ (Clock now _ _ _)) (ObservedDecision input expected) = do
      mark
      tick <- now
      pure $ case resolve input of
        Left _ -> ObservationUnavailable "unresolved-input"
        Right actual -> Observed [Occurrence Nothing (actual == expected)] (Coverage SampledState tick tick True)
    observation _ _ _ = pure (ObservationUnavailable "unsupported-role")

main :: IO ()
main =
  getArgs >>= \case
    ["--declared-config-keys"] -> BL.putStrLn (encode configKeys)
    _ -> runShokoCli registry
