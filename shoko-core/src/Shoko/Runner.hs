{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeFamilies #-}

module Shoko.Runner (runScenario) where

import Control.Concurrent.Async (mapConcurrently, wait, withAsync)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, readMVar)
import Control.Exception (SomeAsyncException, SomeException, evaluate, fromException, mask, throwIO, try)
import Control.Monad (forM, forM_)
import Data.Dynamic (toDyn)
import Data.Dynamic qualified as Dynamic
import Data.IORef
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text qualified as Text
import Effectful (Dispatch (Dynamic), DispatchOf, Eff, Effect, IOE, liftIO, runEff)
import Effectful.Dispatch.Dynamic (interpret, send)
import Shoko.Action
import Shoko.Binding hiding (binding, bindingName)
import Shoko.Clock
import Shoko.Environment
import Shoko.Evidence
import Shoko.Expectation
import Shoko.Identifier
import Shoko.Internal.Binding (Binding (..), Handler (..), Source (..))
import Shoko.Internal.Call (CallContext (..))
import Shoko.Internal.Correlation
import Shoko.Internal.Digest qualified as Digest
import Shoko.Internal.Predicate (testPredicate)
import Shoko.Internal.Reference (evaluateInput)
import Shoko.Observation
import Shoko.Prelude
import Shoko.Result
import Shoko.Scenario

-- Execution is separate from construction. Only resolved operation IDs can be
-- dispatched through this interpreter; no IO is embedded in the scenario.
data Execute op :: Effect where
  ExecuteAction :: OperationRole -> CallContext -> op a -> Execute op m (ActionOutcome a)
  ExecuteObservation :: CallContext -> op a -> Execute op m (ObservationOutcome a)

type instance DispatchOf (Execute op) = Dynamic

runBinding :: forall op resource a. (Vocabulary op) => Set Text -> Binding op resource -> resource -> Eff '[Execute op, IOE] a -> IO a
runBinding approved selectedBinding resource =
  runEff
    . interpret
      ( \_ -> \case
          ExecuteAction role context op ->
            case bindingHandler selectedBinding role op of
              Right (Just (ActionHandler _ _ perform)) | permitted op -> liftIO (perform resource context)
              _ -> pure (ActionUnavailable "undeclared-operation")
          ExecuteObservation context op ->
            case bindingHandler selectedBinding ObservationOperation op of
              Right (Just (ObservationHandler _ _ _ perform)) | permitted op -> liftIO (perform resource context)
              _ -> pure (ObservationUnavailable "undeclared-operation")
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
        binding@(Binding bindingName _ acquire release _),
        Environment envName _ _ (Policy budget _ _ grace),
        (RunOptions runKey _ build implementation target),
        declarations,
        policyReport
        ) = resolvedParts resolved
      runEnd = addDuration start budget
      register finalizer = atomicModifyIORef' finalizers (\fs -> (finalizer : fs, ()))
      approved = Set.fromList (map stepOperation steps ++ mapMaybe expectationOperation expectations)
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
        pure ([], map (unexecuted tick why Map.empty) expectations, [], Unknown)
      execute resource = do
        let sources =
              foldl
                (\acc source -> if any ((== sourceId source) . sourceId) acc then acc else acc ++ [source])
                []
                [source | Expectation _ _ _ observation <- expectations, Right (Just handler) <- [bindingHandler binding ObservationOperation (observationOperation observation)], Just source <- [handlerSource handler]]
        captured <- forM sources $ \(Source label _ capture _) -> do
          result <- attempt runClock runEnd (capture resource runClock)
          capturedNow <- now
          pure
            ( label,
              case result of
                Right (Right base@(Baseline observed capturedAt _))
                  | observed == label && capturedAt >= start && capturedAt <= capturedNow -> Right base
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
            pure ([], map (unexecuted tick why baselines) expectations, [], Unknown)
          else do
            let propagated = if any ((== ExecutionId) . declarationStrategy) declarations then Just runKey else Nothing
            (values, actionResults, terminal) <- runSteps approved binding resource runClock runEnd propagated steps
            activation <- now
            let attempts = [(declarationId declaration, resolveDeclaration runKey values declaration) | declaration <- declarations]
                selected = [ResolvedCorrelation identity value | (identity, Right value) <- attempts]
                resolvedCorrelations = Map.fromList [(identity, value) | (identity, Right value) <- attempts]
            case terminal of
              Just why ->
                pure
                  ( actionResults,
                    map (unexecuted activation why baselines) expectations,
                    selected,
                    aggregateVerdicts (map actionVerdict actionResults ++ [Unknown])
                  )
              Nothing -> do
                results <-
                  mapConcurrently
                    ( \expectation -> case expectation of
                        ResultCheck {} -> runResultCheck runClock runEnd activation values expectation
                        Expectation _ _ _ observation ->
                          case observationCorrelation observation >>= (\handle -> Map.lookup (correlationRefId handle) resolvedCorrelations) of
                            Nothing -> pure (unexecuted activation CorrelationLost baselines expectation)
                            Just value -> runExpectation approved binding resource runClock runEnd activation values value propagated baselines resolved expectation
                    )
                    expectations
                pure
                  ( actionResults,
                    results,
                    selected,
                    aggregateVerdicts (map actionVerdict actionResults ++ map expectationVerdict results)
                  )
      sourceFor :: forall a. OperationRole -> op a -> Maybe SourceId
      sourceFor role op = case bindingHandler binding role op of
        Right (Just handler) -> sourceId <$> handlerSource handler
        _ -> Nothing
      unexecuted _ why _ (ResultCheck key _ input _) = ExpectationResult key Unknown why (ResultEvidence (ResultCheckEvidence (inputDependencies input) Nothing))
      unexecuted tick why baselines (Expectation key _ _ observation) =
        let OperationInfo opKey _ _ _ = describeOperation (observationOperation observation)
            source = fromMaybe (SourceId "unavailable") (sourceFor ObservationOperation (observationOperation observation))
         in ExpectationResult key Unknown why (ObservationEvidence (Evidence source opKey (Map.lookup source baselines) tick tick Nothing [] 0 True runEnd []))
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
      cleanup <- restore (finalize runClock grace finalizers (release resource))
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
  result <- attempt runClock (addDuration started grace) $
    forM_ finalizers $ \finalizer -> do
      outcome <- trySync finalizer
      modifyIORef' results (++ [either (const CleanupFailed) id outcome])
  completed <- readIORef results
  pure $
    completed ++ case result of
      Right () -> []
      Left DeadlineExceeded -> [CleanupTimedOut]
      Left _ -> [CleanupFailed]

attempt :: Clock -> MonotonicTime -> IO a -> IO (Either Reason a)
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
stepOperation (Step _ _ _ action) = case describeOperation (actionOperation action) of OperationInfo key _ _ _ -> key

expectationOperation :: (Vocabulary op) => Expectation op -> Maybe Text
expectationOperation ResultCheck {} = Nothing
expectationOperation (Expectation _ _ _ observation) = case describeOperation (observationOperation observation) of
  OperationInfo key _ _ _ -> Just key

resolveDeclaration :: Text -> Map Text Dynamic.Dynamic -> CorrelationDeclaration -> Either Reason Correlation
resolveDeclaration runKey _ ExecutionDeclaration = Right (ByExecutionId runKey)
resolveDeclaration _ values (BusinessDeclaration _ key input) = case evaluateInput values input of
  Right value | businessKeyNameText key /= "" && value /= "" -> Right (ByBusinessKey key value)
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
  MonotonicTime ->
  Maybe Text ->
  [Step op] ->
  IO (Map Text Dynamic.Dynamic, [ActionEvidence], Maybe Reason)
runSteps approved binding resource runClock@(Clock now _ _ _) end propagated = go Map.empty []
  where
    go values results [] = pure (values, results, Nothing)
    go values results (step@(Step _ _ group _) : rest) = do
      let (stage, later) = case group of
            Nothing -> ([step], rest)
            Just label -> let (members, remaining) = span (inGroup label) rest in (step : members, remaining)
      completed <- case group of
        Nothing -> traverse (runOne Nothing values) stage
        Just _ -> do
          gate <- newEmptyMVar
          let spawn [] workers = putMVar gate () >> traverse wait (reverse workers)
              spawn (member : members) workers = withAsync (runOne (Just gate) values member) $ \worker -> spawn members (worker : workers)
          spawn stage []
      let next = foldl (\acc (value, _) -> maybe acc (\(key, dynamic) -> Map.insert key dynamic acc) value) values completed
          evidence = map snd completed
      if any ((/= Pass) . actionVerdict) evidence
        then pure (next, results ++ evidence, Just PrerequisiteUnavailable)
        else go next (results ++ evidence) later
    inGroup label (Step _ _ group _) = group == Just label
    runOne gate values (Step key fixture _ action) = do
      let op = actionOperation action
          info@(OperationInfo opKey _ _ _) = describeOperation op
          accepted = acceptedTags action
      started <- now
      substeps <- newIORef []
      denied <- newIORef Nothing
      let context = makeContext runClock end end values info Nothing Nothing propagated substeps denied
      outcome <- attempt runClock end $ do
        maybe (pure ()) readMVar gate
        entered <- now
        if entered > end
          then pure (Nothing, DeadlineExceeded, [], Nothing)
          else do
            observed <- runBinding approved binding resource (send (ExecuteAction (if fixture then FixtureOperation else ActionOperation) context op))
            deniedAccess <- readIORef denied
            substepResults <- readIORef substeps
            let substepProblems = [problem | SubstepEvidence _ _ _ problem <- substepResults, problem /= Satisfied]
                classified = case observed of
                  ActionUnavailable _ -> Left SourceUnavailable
                  ActionObserved received output -> validatedOutcome received output []
                  ActionObservedWithDetails received output summaries -> validatedOutcome received output summaries
                (tag, why, details, value) = case classified of
                  Left failure -> (Nothing, failure, [], Nothing)
                  Right (received, result, publicDetails) ->
                    (Just received, if Set.member received accepted then Satisfied else Mismatch, publicDetails, Just (toDyn result))
                finalReason = case (deniedAccess, substepProblems) of
                  (Just _, _) -> UndeclaredOperation
                  (_, problem : _) -> problem
                  _ -> why
            -- Force classification and public details inside the worker's exception
            -- boundary so an ordinary fault cannot cancel already admitted siblings.
            _ <- evaluate (finalReason `seq` maybe () (\name -> Text.length name `seq` ()) tag `seq` forcePublicDetails details)
            pure (tag, finalReason, details, if finalReason == Satisfied then value else Nothing)
      finished <- now
      substepResults <- readIORef substeps
      let (tag, why, details, value) = case outcome of
            Left failure -> (Nothing, failure, [], Nothing)
            Right classified -> classified
          evidence = ActionEvidence key opKey (Set.toAscList accepted) tag started finished why substepResults details
      pure (fmap (key,) value, evidence)

forcePublicDetails :: [(Text, PublicValue)] -> ()
forcePublicDetails [] = ()
forcePublicDetails ((key, value) : rest) = Text.length key `seq` forceValue value `seq` forcePublicDetails rest
  where
    forceValue (PublicChoice choice) = Text.length choice `seq` ()
    forceValue (PublicCount count) = count `seq` ()
    forceValue (PublicFlag flag) = flag `seq` ()

makeContext ::
  Clock ->
  MonotonicTime ->
  MonotonicTime ->
  Map Text Dynamic.Dynamic ->
  OperationInfo ->
  Maybe Baseline ->
  Maybe Correlation ->
  Maybe Text ->
  IORef [SubstepEvidence] ->
  IORef (Maybe Text) ->
  CallContext
makeContext runClock@(Clock now _ _ _) end cutoff values (OperationInfo _ _ declared inventory) base selected propagated records denied =
  CallContext resolve end base selected substepRunner cutoff runClock propagated
  where
    resolve :: forall a. Input a -> IO (Either InputResolutionError a)
    resolve input = case filter (`notElem` declared) (inputDependencies input) of
      [] -> pure (evaluateInput values input)
      dependency : _ -> do
        atomicModifyIORef' denied (\old -> (case old of Nothing -> Just dependency; _ -> old, ()))
        pure (Left (UndeclaredInputReference dependency))
    substepRunner :: forall a. Text -> IO a -> IO (Either Text a)
    substepRunner key action = do
      started <- now
      result <- if key `elem` map fst inventory then attempt runClock end action else pure (Left UndeclaredOperation)
      finished <- now
      let why = either id (const Satisfied) result
      atomicModifyIORef' records (\es -> (es ++ [SubstepEvidence key started finished why], ()))
      pure $ either (const (Left "substep-unavailable")) Right result

-- Resolve and force the final Boolean inside the same bounded exception boundary.
runResultCheck :: Clock -> MonotonicTime -> MonotonicTime -> Map Text Dynamic.Dynamic -> Expectation op -> IO ExpectationResult
runResultCheck runClock@(Clock now _ _ _) runEnd activation values (ResultCheck key windows input test) = do
  let cutoff = minimum (runEnd : map (addDuration activation) windows)
  outcome <- attempt runClock cutoff $ case evaluateInput values input of
    Left _ -> pure Nothing
    Right value -> do
      answer <- evaluate (testPredicate test value)
      completed <- now
      pure (Just (answer, completed))
  let (verdict, reason, completed) = case outcome of
        Left why -> (Unknown, why, Nothing)
        Right Nothing -> (Unknown, PrerequisiteUnavailable, Nothing)
        Right (Just (_, tick)) | tick > cutoff -> (Unknown, DeadlineExceeded, Nothing)
        Right (Just (answer, tick)) -> (if answer then Pass else Fail, if answer then Satisfied else Mismatch, Just tick)
  pure (ExpectationResult key verdict reason (ResultEvidence (ResultCheckEvidence (inputDependencies input) completed)))
runResultCheck _ _ _ _ Expectation {} = error "observation dispatched as result check"

data SearchState = SearchState !(Set Text) !Int !Bool !(Maybe Coverage) !Bool ![(Text, PublicValue)]

runExpectation ::
  forall op resource.
  (Vocabulary op) =>
  Set Text ->
  Binding op resource ->
  resource ->
  Clock ->
  MonotonicTime ->
  MonotonicTime ->
  Map Text Dynamic.Dynamic ->
  Correlation ->
  Maybe Text ->
  Map SourceId Baseline ->
  ResolvedScenario op resource ->
  Expectation op ->
  IO ExpectationResult
runExpectation _ _ _ runClock runEnd activation values _ _ _ _ resultCheck@ResultCheck {} =
  runResultCheck runClock runEnd activation values resultCheck
runExpectation
  approved
  binding
  resource
  runClock@(Clock now _ sleep _)
  runEnd
  activation
  values
  selected
  propagated
  baselines
  resolved
  (Expectation key temporal windows observation) = do
    let op = observationOperation observation
        info@(OperationInfo opKey _ _ _) = describeOperation op
        (_, _, _, _, Environment _ _ _ (Policy _ defaultWindow polling _), _, _, _) = resolvedParts resolved
        cutoff =
          minimum
            ( runEnd
                : map (addDuration activation) windows
                ++ [addDuration activation defaultWindow | temporal == Eventually]
            )
        (source, advertised) = case bindingHandler binding ObservationOperation op of
          Right (Just handler) | Just owned <- handlerSource handler -> (sourceId owned, sourceCoverage owned)
          _ -> (SourceId "unavailable", SampledState)
        base = Map.lookup source baselines
        baselineTick = maybe activation (\(Baseline _ captured _) -> captured) base
        final (SearchState identities count gaps latest missingId details) why verdict = do
          finished <- now
          pure $
            ExpectationResult
              key
              verdict
              why
              ( ObservationEvidence $
                  Evidence
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
                Immediately -> final state InvalidEvidence Unknown
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
              denied <- newIORef Nothing
              let requestEnd = if temporal == Eventually && advertised /= DurableHistory then cutoff else runEnd
                  context = makeContext runClock requestEnd cutoff values info base (Just selected) propagated records denied
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
              deniedAccess <- readIORef denied
              case outcome of
                Left UnexpectedRunnerFault -> final state UnexpectedRunnerFault Unknown
                Left DeadlineExceeded -> final state DeadlineExceeded Unknown
                _ | Just _ <- deniedAccess -> final state UndeclaredOperation Unknown
                _ -> do
                  let result = case outcome of Right value -> value; _ -> Nothing
                      validCoverage (Coverage strength from through _) =
                        from >= MonotonicTime 0
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
                    Never
                      | witness && (finished <= cutoff || case nextCoverage of Just (Coverage DurableHistory _ _ _) -> True; _ -> False) -> final next Mismatch Fail
                    ExactlyOnce | Set.size nextIds > 1 -> final next Mismatch Fail
                    _
                      -- A read that began before the cutoff may finish after
                      -- it with an older database snapshot. Take the actual
                      -- closing read now, while execution time remains. A
                      -- read already begun at/after the cutoff closes once.
                      | advertised == DurableHistory && finished >= cutoff && current < cutoff && requestEnd > cutoff && finished < runEnd -> loop next
                      | finished >= cutoff -> close next
                      | otherwise -> sleep (min cutoff (addDuration finished polling)) >> loop next
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
