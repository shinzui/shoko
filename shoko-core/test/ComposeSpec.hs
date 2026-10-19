{-# LANGUAGE RankNTypes #-}

module ComposeSpec (tests) where

import Consumer.Account (testEnvironment, testOptions)
import Consumer.Composed qualified as C
import Consumer.DeliveryLedger (Ledger, ledgerEnvironment)
import Consumer.Hooks (newMicroClock)
import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (cancel, waitCatch, withAsync)
import Control.Concurrent.MVar
import Data.Either (isLeft)
import Data.IORef
import Data.Set qualified as Set
import Data.String (fromString)
import Data.Time (UTCTime (..), fromGregorian)
import Hedgehog (PropertyT, assert, evalIO, property, withTests, (===))
import Shoko hiding (binding)
import Shoko qualified
import Shoko.Clock
import Shoko.Prelude (Text)
import Shoko.Result hiding (binding)
import Shoko.Scenario (DefinitionError (..))
import System.Timeout (timeout)
import Test.Tasty
import Test.Tasty.Hedgehog

-- Repeated vocabularies are intentionally selected with explicit sum constructors.
data Leaf a where
  ReadLeaf :: SourceId -> [Capability] -> Leaf Bool

instance Vocabulary Leaf where
  describeOperation (ReadLeaf _ caps) = declareOperation "leaf.read" caps

type Log = IORef [String]

leaf :: String -> Log -> ((IO Disposition -> IO ()) -> IO ()) -> IO Disposition -> Binding Leaf ()
leaf name events acquire release = Shoko.binding (fromString name) acquire release' handlers
  where
    release' _ = modifyIORef' events (++ ["release:" ++ name]) >> release
    handlers :: OperationRole -> Leaf a -> Either HandlerBuildError (Maybe (Handler () a))
    handlers ObservationOperation (ReadLeaf label _) = Right $ Just $ observationHandler noRequirements (RequiresBusinessKey (BusinessKeyName "probe")) (sampledSource label) $ \_ call -> do
      tick <- monotonic (callClock call)
      pure (Observed [Occurrence Nothing True] (Coverage SampledState tick tick True))
    handlers _ _ = Right Nothing

normal :: String -> Log -> Binding Leaf ()
normal name events = leaf name events (\_ -> modifyIORef' events (++ ["acquire:" ++ name])) (pure Cleaned)

pairScenario :: SourceId -> SourceId -> Scenario (Leaf :+: Leaf)
pairScenario left right = scenario "pair" "Two readers" "1" $ expect $ do
  eventually "left" (observe "yes" (InL (ReadLeaf left [])) id)
  eventually "right" (observe "yes" (InR (ReadLeaf right [])) id)

plan :: CorrelationPlan
plan = BusinessKeyFrom (BusinessKeyName "probe") (pure "one")

run :: (Vocabulary op) => Binding op r -> Scenario op -> IO RunResult
run selected source = do
  resolved <- either (fail . show) pure (resolveScenario ledgerEnvironment testOptions plan selected source)
  runScenario realClock (LogicalInput "compose" []) resolved

expectPass :: RunResult -> PropertyT IO ()
expectPass (Verification VerificationResult {verdict = v}) = v === Pass
expectPass _ = fail "expected verification"

tests :: TestTree
tests =
  testGroup
    "vocabulary and binding composition"
    [ check "concrete workflow lifts, returns typed references, and runs across two contexts" $ do
        events <- evalIO (newIORef [])
        (clock, _) <- evalIO (newMicroClock (UTCTime (fromGregorian 2026 10 18) 0))
        resolved <- either (fail . show) pure (resolveScenario testEnvironment testOptions (BusinessKeyFrom (BusinessKeyName "registrationId") (pure "registration")) (C.combinedBinding events) C.combinedScenario)
        evalIO (runScenario clock (LogicalInput "combined" []) resolved) >>= expectPass,
      check "hoisting identity and composition preserve descriptions and builder results" $ do
        let block = C.registrationWorkflow
            wrap program = scenario "law" "Hoist law" "1" $ namespace "outer" (program >> pure ())
            identity = wrap (hoistScenarioBuilder id block)
            direct = wrap block
            twice = wrap (hoistScenarioBuilder InL (hoistScenarioBuilder InL block)) :: Scenario ((C.Registration :+: C.Accounts) :+: Ledger)
            once = wrap (hoistScenarioBuilder (InL . InL) block) :: Scenario ((C.Registration :+: C.Accounts) :+: Ledger)
        inspectScenario identity === inspectScenario direct
        inspectScenario twice === inspectScenario once
        events <- evalIO (newIORef [])
        let verify :: (Vocabulary op) => Binding op r -> Scenario op -> PropertyT IO ()
            verify selected source = do
              evalIO (writeIORef events [])
              resolved <- either (fail . show) pure (resolveScenario testEnvironment testOptions (BusinessKeyFrom (BusinessKeyName "registrationId") (pure "registration")) selected source)
              evalIO (runScenario realClock (LogicalInput "hoist-law" []) resolved) >>= expectPass
            unused :: Binding Ledger ()
            unused = Shoko.binding "unused" (const (pure ())) (const (pure Cleaned)) (\_ _ -> Right Nothing)
            nested = combineBindings "nested" (C.combinedBinding events) unused
        verify (C.composedBinding events) direct
        verify (C.composedBinding events) identity
        verify nested twice
        verify nested once
        -- Member's identity, left, right, and three-context injection all typecheck.
        let original = describeOperation C.Qualified
        original === describeOperation (inject C.Qualified :: C.Registration Text)
        original === describeOperation (inject C.Qualified :: (C.Registration :+: C.Accounts) Text)
        original === describeOperation (inject C.Qualified :: (C.Accounts :+: C.Registration) Text)
        original === describeOperation (inject C.Qualified :: (Leaf :+: C.Accounts :+: C.Registration) Text),
      check "hoisting retains strict/deferred order, windows, predicate metadata, and expected tags" $ do
        duration <- either (fail . show) pure (milliseconds 20)
        let block = do
              key <- C.registrationWorkflow
              expect $ within duration $ eventually "strict" (observeThat (C.Registered (fromRef key)) (onPart "flag" id (predicate "yes" id)))
              expectAfterActions $ within duration $ never "deferred" (observeThat (C.Registered (fromRef key)) (predicate "no" not))
            wrap program = scenario "metadata" "Hoisted metadata" "1" $ namespace "nested" program
            lifted = wrap (hoistScenarioBuilder InL block) :: Scenario (C.Registration :+: C.Accounts)
            invalid = scenario "invalid" "Preserved invalid predicate metadata" "1" $ expect $ eventually "check" (observeThat (C.Registered (pure "registration")) (onPart "bad:label" id (predicate "yes" id)))
        inspectScenario lifted === inspectScenario (wrap block)
        inspectScenario (scenario "invalid" "Preserved invalid predicate metadata" "1" (hoistScenarioBuilder InL $ expect $ eventually "check" (observeThat (C.Registered (pure "registration")) (onPart "bad:label" id (predicate "yes" id)))) :: Scenario (C.Registration :+: C.Accounts)) === inspectScenario invalid
        acceptedTags (hoistAction InL (accept ["ready"] C.Qualified) :: Action (C.Registration :+: C.Accounts) Text) === Set.singleton "ready"
        let observed = hoistObservation InL (observeThat (C.Registered (pure "registration")) (predicate "yes" id)) :: Observation (C.Registration :+: C.Accounts) Bool
        predicateId observed === "yes"
        assert (matches observed True),
      check "both resources acquire and clean up right then left exactly once" $ do
        events <- evalIO (newIORef [])
        result <- evalIO (run (combineBindings "pair" (normal "a" events) (normal "b" events)) (pairScenario (SourceId "a") (SourceId "b")))
        expectPass result
        evalIO (readIORef events) >>= (=== ["acquire:a", "acquire:b", "release:b", "release:a"])
        case result of Verification VerificationResult {disposition = ds} -> ds === [Cleaned, Cleaned]; _ -> fail "verification",
      check "equal-coverage labels across components reject before allocation" $ do
        events <- evalIO (newIORef [])
        case resolveScenario testEnvironment testOptions plan (combineBindings "pair" (normal "a" events) (normal "b" events)) (pairScenario (SourceId "same") (SourceId "same")) of
          Left errors -> errors === [InconsistentSource (SourceId "same")]
          Right _ -> fail "source collision accepted"
        evalIO (readIORef events) >>= (=== []),
      check "unused component lifecycle requirements prevent all allocation" $ do
        events <- evalIO (newIORef [])
        let selected = combineBindings "pair" (normal "a" events) (requiringLifecycle [ExternalSideEffect] (normal "b" events))
            source = scenario "only-left" "Unused lifecycle" "1" $ expect $ eventually "left" (observe "yes" (InL (ReadLeaf (SourceId "a") [])) id)
            Environment name production allowed policy = testEnvironment
        assert (isLeft (resolveScenario (Environment name production (Set.delete ExternalSideEffect allowed) policy) testOptions plan selected source))
        evalIO (readIORef events) >>= (=== []),
      check "operation conflicts compare capabilities and ignore per-use dependencies" $ do
        let source = scenario "conflict" "Conflicting inventories" "1" $ expect $ do
              eventually "left" (observe "yes" (InL (ReadLeaf (SourceId "a") [ReadState])) id)
              eventually "right" (observe "yes" (InR (ReadLeaf (SourceId "b") [ReadEvents])) id)
        case inspectScenario source of Left errors -> errors === [ConflictingOperation "leaf.read"]; Right _ -> fail "conflict accepted",
      check "failed or timed out right acquisition cleans the completed left resource" $ do
        mapM_
          ( \blocking -> do
              events <- evalIO (newIORef [])
              let acquire _ = if blocking then threadDelay 10000000 else fail "right acquisition failed"
                  selected = combineBindings "pair" (normal "a" events) (leaf "b" events acquire (pure Cleaned))
              result <- evalIO (run selected (pairScenario (SourceId "a") (SourceId "b")))
              case result of
                Verification VerificationResult {disposition = ds} -> ds === [Cleaned]
                RunnerFault _ (Just VerificationResult {disposition = ds}) -> ds === [Cleaned]
                _ -> fail "expected a partial report"
              evalIO (readIORef events) >>= (=== ["acquire:a", "release:a"])
          )
          [False, True],
      check "left acquisition failure never acquires right" $ do
        events <- evalIO (newIORef [])
        let selected = combineBindings "pair" (leaf "a" events (\_ -> fail "left") (pure Cleaned)) (normal "b" events)
        _ <- evalIO (run selected (pairScenario (SourceId "a") (SourceId "b")))
        evalIO (readIORef events) >>= (=== []),
      check "cancellation releases partial right then completed left and rethrows" $ do
        events <- evalIO (newIORef [])
        entered <- evalIO newEmptyMVar
        let acquire register = do
              register (modifyIORef' events (++ ["partial:b"]) >> pure Cleaned)
              putMVar entered ()
              threadDelay 10000000
            selected = combineBindings "pair" (normal "a" events) (leaf "b" events acquire (pure Cleaned))
        result <- evalIO $ withAsync (run selected (pairScenario (SourceId "a") (SourceId "b"))) $ \worker -> do
          ready <- timeout 1000000 (takeMVar entered)
          case ready of Nothing -> fail "acquisition did not start"; Just () -> cancel worker >> waitCatch worker
        assert (isLeft result)
        evalIO (readIORef events) >>= (=== ["acquire:a", "partial:b", "release:a"]),
      check "composed finalizers share one cleanup deadline" $ do
        events <- evalIO (newIORef [])
        let selected = combineBindings "pair" (normal "a" events) (leaf "b" events (\_ -> modifyIORef' events (++ ["acquire:b"])) (threadDelay 10000000 >> pure Cleaned))
        result <- evalIO (run selected (pairScenario (SourceId "a") (SourceId "b")))
        case result of
          Verification VerificationResult {disposition = ds} -> ds === [CleanupTimedOut]
          _ -> fail "expected bounded cleanup"
        evalIO (readIORef events) >>= (=== ["acquire:a", "acquire:b", "release:b"]),
      check "nested combinations clean each leaf in reverse order on success and partial failure" $ do
        mapM_
          ( \failThird -> do
              events <- evalIO (newIORef [])
              let a = normal "a" events
                  b = normal "b" events
                  c = if failThird then leaf "c" events (\_ -> fail "third") (pure Cleaned) else normal "c" events
                  left = combineBindings "left-nested" (combineBindings "ab" a b) c
                  right = combineBindings "right-nested" a (combineBindings "bc" b c)
                  ls = scenario "nested" "Nested leaves" "1" $ expect $ do
                    eventually "a" (observe "yes" (InL (InL (ReadLeaf (SourceId "a") []))) id)
                    eventually "b" (observe "yes" (InL (InR (ReadLeaf (SourceId "b") []))) id)
                    eventually "c" (observe "yes" (InR (ReadLeaf (SourceId "c") [])) id)
                  rs = scenario "nested" "Nested leaves" "1" $ expect $ do
                    eventually "a" (observe "yes" (InL (ReadLeaf (SourceId "a") [])) id)
                    eventually "b" (observe "yes" (InR (InL (ReadLeaf (SourceId "b") []))) id)
                    eventually "c" (observe "yes" (InR (InR (ReadLeaf (SourceId "c") []))) id)
                  expected = if failThird then ["acquire:a", "acquire:b", "release:b", "release:a"] else ["acquire:a", "acquire:b", "acquire:c", "release:c", "release:b", "release:a"]
              _ <- evalIO (run left ls)
              evalIO (readIORef events) >>= (=== expected)
              evalIO (writeIORef events [])
              _ <- evalIO (run right rs)
              evalIO (readIORef events) >>= (=== expected)
          )
          [False, True]
    ]
  where
    check :: String -> PropertyT IO () -> TestTree
    check label = testPropertyNamed label (fromString label) . withTests 1 . property
