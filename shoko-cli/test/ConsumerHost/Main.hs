module Main (main) where

import Data.Aeson (encode)
import Data.ByteString.Lazy.Char8 qualified as BL
import Data.Set qualified as Set
import Idempotency (idempotencyEntries)
import Registration (registrationEntries)
import Shoko
import Shoko.Cli
import Shoko.Cli.Config (configKeys)
import Shoko.Clock (monotonic)
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
registry = Registry ["local"] ([entry "consumer-approved" True, entry "consumer-rejected" False] ++ registrationEntries ++ idempotencyEntries)
  where
    entry name approved =
      Entry
        ( scenario name "Independent host decision" "v1" $ do
            result <- act "decide" (accept [if approved then "approved" else "denied"] (Decide approved))
            selected <- correlate (CorrelationAlias "decision") (BusinessKeyName "case") (pure "consumer-case")
            expect (eventually "decision-evidence" (correlatedBy selected $ observe "correct-decision" (ObservedDecision (fromRef result) approved) id))
        )
        (LogicalInput "consumer-v1" [])
        [("demo", \_ _ -> SomeBinding consumerBinding)]
        ( \_ -> do
            lookupEnv "SHOKO_TEST_COUNTER" >>= maybe (pure ()) (\path -> appendFile path "metadata\n")
            pure (Right (Nothing, Nothing))
        )

consumerBinding :: Binding Decision ()
consumerBinding = binding "independent-consumer" (\_ -> mark >> pure ()) (\_ -> mark >> pure Cleaned) handlers
  where
    mark = lookupEnv "SHOKO_TEST_COUNTER" >>= maybe (pure ()) (\path -> appendFile path "effect\n")
    handlers :: forall a. OperationRole -> Decision a -> Either HandlerBuildError (Maybe (Handler () a))
    handlers ActionOperation (Decide approved) = Right $ Just $ actionHandler noRequirements $ \_ _ -> mark >> pure (ActionObserved (if approved then "approved" else "denied") approved)
    handlers ObservationOperation (ObservedDecision input expected) = Right $ Just $ observationHandler noRequirements (RequiresBusinessKey (BusinessKeyName "case")) owned $ \_ call -> do
      mark
      tick <- monotonic (callClock call)
      resolveInput call input >>= \case
        Left _ -> pure (ObservationUnavailable "unresolved-input")
        Right actual -> pure (Observed [Occurrence Nothing (actual == expected)] (Coverage SampledState tick tick True))
    handlers _ _ = Right Nothing
    owned = newSource (SourceId "consumer-state") SampledState $ \_ clock -> do
      mark
      tick <- monotonic clock
      pure (Right (Baseline (SourceId "consumer-state") tick Nothing))

main :: IO ()
main =
  getArgs >>= \case
    ["--declared-config-keys"] -> BL.putStrLn (encode configKeys)
    _ -> runShokoCli registry
