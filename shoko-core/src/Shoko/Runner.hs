{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeFamilies #-}

module Shoko.Runner (runScenario) where

import Control.Concurrent.Async (mapConcurrently)
import Control.Exception (SomeAsyncException, SomeException, evaluate, fromException, mask, throwIO, try)
import Control.Monad (forM, forM_)
import Data.Dynamic (toDyn)
import Data.Dynamic qualified as Dynamic
import Data.IORef
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Set (Set)
import Data.Set qualified as Set
import Effectful (Dispatch (Dynamic), DispatchOf, Eff, Effect, IOE, liftIO, runEff)
import Effectful.Dispatch.Dynamic (interpret, send)
import Shoko.Action
import Shoko.Binding
import Shoko.Clock
import Shoko.Correlation
import Shoko.Environment
import Shoko.Evidence
import Shoko.Expectation
import Shoko.Internal.Digest qualified as Digest
import Shoko.Internal.Reference (evaluateInput)
import Shoko.Observation
import Shoko.Prelude
import Shoko.Result
import Shoko.Scenario

-- Execution is separate from construction. Only resolved operation IDs can be
-- dispatched through this interpreter; no IO is embedded in the scenario.
data Execute op :: Effect where
  ExecuteAction :: CallContext -> op a -> Execute op m (ActionOutcome a)
  ExecuteObservation :: CallContext -> op a -> Execute op m (ObservationOutcome a)

type instance DispatchOf (Execute op) = Dynamic

runBinding :: forall op resource a. (Vocabulary op) => Set Text -> Binding op resource -> resource -> Eff '[Execute op, IOE] a -> IO a
runBinding approved (Binding _ _ _ _ _ _ actionHandler observationHandler) resource =
  runEff
    . interpret
      ( \_ -> \case
          ExecuteAction context op ->
            if permitted op
              then liftIO (actionHandler resource context op)
              else pure (ActionUnavailable "undeclared-operation")
          ExecuteObservation context op ->
            if permitted op
              then liftIO (observationHandler resource context op)
              else pure (ObservationUnavailable "undeclared-operation")
      )
  where
    permitted :: forall b. op b -> Bool
    permitted op = case describeOperation op of OperationInfo key _ _ _ -> Set.member key approved

-- | The clock starts before acquisition. All finalizers share one independent
-- grace period; asynchronous cancellation is rethrown after finalization.
runScenario :: forall op resource. (Vocabulary op) => Clock -> LogicalInput -> ResolvedScenario op resource -> IO RunResult
runScenario runClock logical resolved
  | validLogicalInput logical = runResolved runClock logical resolved
  | otherwise = pure (PreflightFailure [InvalidLogicalInput])

validLogicalInput :: LogicalInput -> Bool
validLogicalInput (LogicalInput revision parameters) =
  revision /= ""
    && validPublicDetails parameters
    && Set.size (Set.fromList (map fst parameters)) == length parameters

validPublicDetails :: [(Text, PublicValue)] -> Bool
validPublicDetails = all ((/= "") . fst)

runResolved :: forall op resource. (Vocabulary op) => Clock -> LogicalInput -> ResolvedScenario op resource -> IO RunResult
runResolved runClock@(Clock now wall _ _) logical resolved = mask $ \restore -> do
  start <- now
  startedUtc <- wall
  finalizers <- newIORef []
  let ( description,
        steps,
        expectations,
        binding@(Binding bindingName _ lookupContract acquire release capture _ _),
        Environment envName _ _ (Policy budget _ _ grace),
        (RunOptions runKey _ build implementation target),
        correlationPlan,
        policyReport
        ) = resolvedParts resolved
      runEnd = start + toInteger (durationMicros budget)
      register finalizer = atomicModifyIORef' finalizers (\fs -> (finalizer : fs, ()))
      approved = Set.fromList (map stepOperation steps ++ map expectationOperation expectations)
      finishReport (actionResults, expectationResults, selected, primary) cleanup = do
        finishedUtc <- wall
        let finalVerdict = aggregateVerdicts (primary : [Unknown | any failedCleanup cleanup])
        let report =
              VerificationResult
                description
                (Digest.descriptionDigest description)
                runKey
                envName
                bindingName
                build
                implementation
                target
                logical
                selected
                policyReport
                startedUtc
                finishedUtc
                start
                runEnd
                finalVerdict
                actionResults
                expectationResults
                cleanup
        pure $
          if any actionFault actionResults || any expectationFault expectationResults
            then RunnerFault UnexpectedRunnerFault (Just report)
            else Verification report
      unavailable why = do
        tick <- now
        pure ([], map (unexecuted tick why Map.empty) expectations, Nothing, Unknown)
      execute resource = do
        let sources =
              Set.toAscList $
                Set.fromList
                  [source | op <- map stepSource steps ++ map expectationSource expectations, Just source <- [op]]
        captured <- forM sources $ \source -> do
          result <- attempt runClock runEnd (capture resource runClock source)
          capturedNow <- now
          pure
            ( source,
              case result of
                Right (Right base@(Baseline observed capturedAt _))
                  | observed == source && capturedAt >= start && capturedAt <= capturedNow -> Right base
                  | otherwise -> Left InvalidEvidence
                Right (Left _) -> Left SourceUnavailable
                Left why -> Left why
            )
        let baselines = Map.fromList [(source, base) | (source, Right base) <- captured]
            failures = [why | (_, Left why) <- captured]
        if not (null failures)
          then do
            tick <- now
            let why = if UnexpectedRunnerFault `elem` failures then UnexpectedRunnerFault else case failures of first : _ -> first; [] -> SourceUnavailable
            pure ([], map (unexecuted tick why baselines) expectations, Nothing, Unknown)
          else do
            (values, actionResults, terminal) <- runSteps approved binding resource runClock runEnd steps
            activation <- now
            case resolveCorrelation runKey values correlationPlan of
              Left why ->
                pure
                  ( actionResults,
                    map (unexecuted activation why baselines) expectations,
                    Nothing,
                    aggregateVerdicts (map actionVerdict actionResults ++ [Unknown])
                  )
              Right selected -> case terminal of
                Just why ->
                  pure
                    ( actionResults,
                      map (unexecuted activation why baselines) expectations,
                      Just selected,
                      aggregateVerdicts (map actionVerdict actionResults ++ [Unknown])
                    )
                Nothing -> do
                  results <-
                    mapConcurrently
                      (runExpectation approved binding resource runClock runEnd activation values selected baselines resolved)
                      expectations
                  pure
                    ( actionResults,
                      results,
                      Just selected,
                      aggregateVerdicts (map actionVerdict actionResults ++ map expectationVerdict results)
                    )
      stepSource (Step _ fixture action) = sourceFor (if fixture then FixtureOperation else ActionOperation) (actionOperation action)
      expectationSource (Expectation _ _ _ observation) = sourceFor ObservationOperation (observationOperation observation)
      sourceFor :: forall a. OperationRole -> op a -> Maybe Text
      sourceFor role op = case lookupContract role op of Just (BindingContract _ _ _ source _) -> source; Nothing -> Nothing
      unexecuted tick why baselines (Expectation key _ _ observation) =
        let OperationInfo opKey _ _ _ = describeOperation (observationOperation observation)
            source = fromMaybe "unavailable" (sourceFor ObservationOperation (observationOperation observation))
         in ExpectationResult key Unknown why (Evidence source opKey (Map.lookup source baselines) tick tick Nothing [] 0 True runEnd [])
  acquired <- try (restore (attempt runClock runEnd (acquire register)))
  case acquired of
    Left (exception :: SomeException) -> do
      _ <- restore (finalize runClock grace finalizers [])
      rethrowOrFault exception
    Right (Left why) -> do
      cleanup <- restore (finalize runClock grace finalizers [])
      unavailable why >>= (`finishReport` cleanup)
    Right (Right resource) -> do
      primary <- try (restore (execute resource))
      cleanup <- restore (finalize runClock grace finalizers [release resource])
      case primary of
        Left (exception :: SomeException) -> rethrowOrFault exception
        Right result -> finishReport result cleanup
  where
    actionFault (ActionEvidence _ _ _ _ _ _ why _ _) = why == UnexpectedRunnerFault
    expectationFault (ExpectationResult _ _ why _) = why == UnexpectedRunnerFault
    failedCleanup Cleaned = False
    failedCleanup Retained = False
    failedCleanup _ = True

rethrowOrFault :: SomeException -> IO RunResult
rethrowOrFault exception = case fromException exception :: Maybe SomeAsyncException of
  Just _ -> throwIO exception
  Nothing -> pure (RunnerFault UnexpectedRunnerFault Nothing)

finalize :: Clock -> Duration -> IORef [IO Disposition] -> [IO Disposition] -> IO [Disposition]
finalize runClock@(Clock now _ _ _) grace registered first = do
  started <- now
  finalizers <- (first ++) <$> readIORef registered
  results <- newIORef []
  result <- attempt runClock (started + toInteger (durationMicros grace)) $
    forM_ finalizers $ \finalizer -> do
      outcome <- trySync finalizer
      modifyIORef' results (++ [either (const CleanupFailed) id outcome])
  completed <- readIORef results
  pure $
    completed ++ case result of
      Right () -> []
      Left DeadlineExceeded -> [CleanupTimedOut]
      Left _ -> [CleanupFailed]

attempt :: Clock -> Integer -> IO a -> IO (Either Reason a)
attempt (Clock _ _ _ bound) end action = do
  result <- trySync (bound end (action >>= evaluate))
  pure $ case result of
    Left () -> Left UnexpectedRunnerFault
    Right Nothing -> Left DeadlineExceeded
    Right (Just value) -> Right value

trySync :: IO a -> IO (Either () a)
trySync action = do
  result <- try action
  case result of
    Left (exception :: SomeException) -> case fromException exception :: Maybe SomeAsyncException of
      Just _ -> throwIO exception
      Nothing -> pure (Left ())
    Right value -> pure (Right value)

stepOperation :: (Vocabulary op) => Step op -> Text
stepOperation (Step _ _ action) = case describeOperation (actionOperation action) of OperationInfo key _ _ _ -> key

expectationOperation :: (Vocabulary op) => Expectation op -> Text
expectationOperation (Expectation _ _ _ observation) = case describeOperation (observationOperation observation) of
  OperationInfo key _ _ _ -> key

resolveCorrelation :: Text -> Map Text Dynamic.Dynamic -> CorrelationPlan -> Either Reason Correlation
resolveCorrelation runKey _ PropagatedExecutionId = Right (ByExecutionId runKey)
resolveCorrelation _ values (BusinessKeyFrom key input) = case evaluateInput values input of
  Right value | key /= "" && value /= "" -> Right (ByBusinessKey key value)
  _ -> Left CorrelationLost

actionVerdict :: ActionEvidence -> Verdict
actionVerdict (ActionEvidence _ _ _ _ _ _ why _ _) = case why of Satisfied -> Pass; Mismatch -> Fail; _ -> Unknown

expectationVerdict :: ExpectationResult -> Verdict
expectationVerdict (ExpectationResult _ verdict _ _) = verdict

runSteps ::
  forall op resource.
  (Vocabulary op) =>
  Set Text ->
  Binding op resource ->
  resource ->
  Clock ->
  Integer ->
  [Step op] ->
  IO (Map Text Dynamic.Dynamic, [ActionEvidence], Maybe Reason)
runSteps approved binding resource runClock@(Clock now _ _ _) end = go Map.empty []
  where
    go values results [] = pure (values, results, Nothing)
    go values results (Step key _ action : rest) = do
      let op = actionOperation action
          info@(OperationInfo opKey _ _ _) = describeOperation op
          accepted = acceptedTags action
      started <- now
      substeps <- newIORef []
      let context = makeContext runClock end end values info Nothing Nothing substeps
      outcome <- attempt runClock end $ runBinding approved binding resource (send (ExecuteAction context op))
      finished <- now
      substepResults <- readIORef substeps
      let substepProblems = [substepReason | SubstepEvidence _ _ _ substepReason <- substepResults, substepReason /= Satisfied]
          observedResult = case outcome of
            Left failure -> Left failure
            Right (ActionUnavailable _) -> Left SourceUnavailable
            Right (ActionObserved received value) -> validatedOutcome received value []
            Right (ActionObservedWithDetails received value safeDetails) -> validatedOutcome received value safeDetails
          (tag, why, details) = case observedResult of
            Left failure -> (Nothing, failure, [])
            Right (observed, _, publicDetails) -> (Just observed, if Set.member observed accepted then Satisfied else Mismatch, publicDetails)
          finalReason = case substepProblems of [] -> why; problem : _ -> problem
          evidence = ActionEvidence key opKey (Set.toAscList accepted) tag started finished finalReason substepResults details
      case (observedResult, finalReason) of
        (Right (_, value, _), Satisfied) -> go (Map.insert key (toDyn value) values) (results ++ [evidence]) rest
        _ -> pure (values, results ++ [evidence], Just PrerequisiteUnavailable)

makeContext ::
  Clock ->
  Integer ->
  Integer ->
  Map Text Dynamic.Dynamic ->
  OperationInfo ->
  Maybe Baseline ->
  Maybe Correlation ->
  IORef [SubstepEvidence] ->
  CallContext
makeContext runClock@(Clock now _ _ _) end cutoff values (OperationInfo _ _ declared inventory) base selected records =
  CallContext resolve end base selected runSubstep cutoff runClock
  where
    resolve :: forall a. Input a -> Either Text a
    resolve input
      | all (`elem` declared) (inputDependencies input) = evaluateInput values input
      | otherwise = Left "undeclared-reference"
    runSubstep :: forall a. Text -> IO a -> IO (Either Text a)
    runSubstep key action = do
      started <- now
      result <- if key `elem` map fst inventory then attempt runClock end action else pure (Left UndeclaredOperation)
      finished <- now
      let why = either id (const Satisfied) result
      atomicModifyIORef' records (\es -> (es ++ [SubstepEvidence key started finished why], ()))
      pure $ either (const (Left "substep-unavailable")) Right result

data SearchState = SearchState !(Set Text) !Int !Bool !(Maybe Coverage) !Bool ![(Text, PublicValue)]

runExpectation ::
  forall op resource.
  (Vocabulary op) =>
  Set Text ->
  Binding op resource ->
  resource ->
  Clock ->
  Integer ->
  Integer ->
  Map Text Dynamic.Dynamic ->
  Correlation ->
  Map Text Baseline ->
  ResolvedScenario op resource ->
  Expectation op ->
  IO ExpectationResult
runExpectation
  approved
  binding@(Binding _ _ lookupContract _ _ _ _ _)
  resource
  runClock@(Clock now _ sleep _)
  runEnd
  activation
  values
  selected
  baselines
  resolved
  (Expectation key temporal windows observation) = do
    let op = observationOperation observation
        info@(OperationInfo opKey _ _ _) = describeOperation op
        (_, _, _, _, Environment _ _ _ (Policy _ defaultWindow polling _), _, _, _) = resolvedParts resolved
        cutoff =
          minimum
            ( runEnd
                : map ((activation +) . toInteger . durationMicros) windows
                ++ [activation + toInteger (durationMicros defaultWindow) | temporal == Eventually]
            )
        (source, advertised) = case lookupContract ObservationOperation op of
          Just (BindingContract _ _ _ sourceName strength) -> (fromMaybe "unavailable" sourceName, strength)
          Nothing -> ("unavailable", SampledState)
        base = Map.lookup source baselines
        baselineTick = maybe activation (\(Baseline _ captured _) -> captured) base
        final (SearchState identities count gaps latest missingId details) why verdict = do
          finished <- now
          pure $
            ExpectationResult
              key
              verdict
              why
              ( Evidence
                  source
                  opKey
                  base
                  activation
                  finished
                  latest
                  (Set.toAscList identities)
                  count
                  (gaps || missingId)
                  cutoff
                  details
              )
        close state@(SearchState ids _ gaps latest missingId _) =
          let complete = case latest of
                Just (Coverage DurableHistory from through True) -> from <= baselineTick && through >= cutoff && advertised == DurableHistory
                _ -> False
           in case temporal of
                Eventually
                  | gaps || latest == Nothing -> final state SourceUnavailable Unknown
                  | advertised == DurableHistory && not complete -> final state CoverageIncomplete Unknown
                  | otherwise -> final state Mismatch Fail
                Never -> final state (if complete then Satisfied else CoverageIncomplete) (if complete then Pass else Unknown)
                ExactlyOnce
                  | not complete || missingId -> final state CoverageIncomplete Unknown
                  | Set.size ids == 1 -> final state Satisfied Pass
                  | otherwise -> final state Mismatch Fail
        loop state@(SearchState ids previousCount gaps latest missingId previousDetails) = do
          current <- now
          if current > runEnd || (current >= cutoff && temporal == Eventually && advertised /= DurableHistory)
            then close state
            else do
              records <- newIORef []
              let requestEnd = if temporal == Eventually && advertised /= DurableHistory then cutoff else runEnd
                  context = makeContext runClock requestEnd cutoff values info base (Just selected) records
                  query = do
                    observed <- runBinding approved binding resource (send (ExecuteObservation context op))
                    case observationBatch observed of
                      Nothing -> pure Nothing
                      Just (occurrences, coverage, details) -> do
                        let matchingIds = [identity | Occurrence identity value <- occurrences, matches observation value]
                        _ <- evaluate (length matchingIds)
                        pure (Just (matchingIds, coverage, details))
              outcome <- attempt runClock requestEnd query
              finished <- now
              case outcome of
                Left UnexpectedRunnerFault -> final state UnexpectedRunnerFault Unknown
                _ -> do
                  let result = case outcome of Right value -> value; _ -> Nothing
                      validCoverage (Coverage strength from through _) =
                        from >= 0
                          && from <= through
                          && through <= finished
                          && (strength /= DurableHistory || advertised == DurableHistory)
                      (nextIds, count, nextGaps, nextCoverage, noIdentity, witness, publicDetails) = case result of
                        Just (matchingIds, coverage@(Coverage strength from through complete), details)
                          | validCoverage coverage ->
                              let found = Set.fromList [identity | Just identity <- matchingIds, identity /= ""]
                                  merged = Set.union ids found
                                  durable = strength == DurableHistory && advertised == DurableHistory
                                  repaired = durable && complete && from <= baselineTick && through >= min current cutoff
                               in ( if durable then merged else ids,
                                    if durable then Set.size merged else length matchingIds,
                                    if repaired then False else gaps || not complete,
                                    Just coverage,
                                    missingId || (durable && any (\identity -> identity == Nothing || identity == Just "") matchingIds),
                                    not (null matchingIds),
                                    details
                                  )
                        _ -> (ids, previousCount, True, latest, missingId, False, previousDetails)
                      next = SearchState nextIds count nextGaps nextCoverage noIdentity publicDetails
                  case temporal of
                    Eventually | witness && finished <= cutoff -> final next Satisfied Pass
                    Never | witness -> final next Mismatch Fail
                    ExactlyOnce | Set.size nextIds > 1 -> final next Mismatch Fail
                    _
                      | finished >= cutoff -> close next
                      | otherwise -> sleep (min cutoff (finished + toInteger (durationMicros polling))) >> loop next
    loop (SearchState Set.empty 0 False Nothing False [])

observationBatch :: ObservationOutcome a -> Maybe ([Occurrence a], Coverage, [(Text, PublicValue)])
observationBatch (ObservationUnavailable _) = Nothing
observationBatch (Observed values coverage) = Just (values, coverage, [])
observationBatch (ObservedWithDetails values coverage details)
  | validPublicDetails details = Just (values, coverage, details)
  | otherwise = Nothing

validatedOutcome :: Text -> a -> [(Text, PublicValue)] -> Either Reason (Text, a, [(Text, PublicValue)])
validatedOutcome received value details
  | received /= "" && validPublicDetails details = Right (received, value, details)
  | otherwise = Left InvalidEvidence
