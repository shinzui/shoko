module ScenarioSpec (tests) where

import Consumer.Account
import Consumer.Composed qualified as Composed
import Data.Either (isLeft, isRight)
import Data.IORef
import Data.Set qualified as Set
import Data.String (fromString)
import Data.Text qualified as Text
import Hedgehog (PropertyT, assert, evalIO, property, withTests, (===))
import Shoko hiding (binding, correlation)
import Shoko.Scenario
import Test.Tasty
import Test.Tasty.Hedgehog

tests :: TestTree
tests =
  testGroup
    "description and policy"
    [ check "namespaced blocks retain references and declaration order" $ do
        case inspectScenario Composed.composedScenario of
          Left errors -> fail (show errors)
          Right Description {nodes = ns, expectations = es} -> do
            map (\NodeDescription {nodeId = key} -> key) ns === ["inviter.qualified", "invitee.qualified", "invitee.complete", "finish"]
            map (\ExpectationDescription {expectationId = key} -> key) es === ["invitee.registered"]
            map (\ExpectationDescription {predicate = key} -> key) es === ["(exists and not(absent))"],
      check "strict/deferred order and invalid namespace/predicate labels" $ do
        let build label test = scenario "labels" "Labels" "v1" $ namespace label $ do
              a <- Composed.qualifiedAgent
              _ <- Composed.completeRegistration a
              expect $ eventually "strict" (observeThat (Composed.Registered (fromRef a)) test)
              expectAfterActions $ eventually "deferred" (observe "ok" (Composed.Registered (fromRef a)) id)
        case inspectScenario (build "outer.inner" (Shoko.predicate "valid" id)) of
          Right Description {expectations = es} -> map (\ExpectationDescription {expectationId = key} -> key) es === ["outer.inner.registered", "outer.inner.strict", "outer.inner.deferred"]
          Left errors -> fail (show errors)
        mapM_ (\label -> assert (isLeft (inspectScenario (build label (Shoko.predicate "valid" id))))) ["", ".x", "x..y", "x."]
        mapM_ (\label -> assert (isLeft (inspectScenario (build "valid" (Shoko.predicate label id))))) ["", "x and y", "(x)", "é"]
        assert (isLeft (inspectScenario (build "valid" (onPart "bad:part" id (Shoko.predicate "ok" id))))),
      check "namespaces retain local empty-identifier validation" $ do
        let invalid = scenario "empty-local" "Empty local ID" "1" $ namespace "valid" $ do
              _ <- given "" (accept ["ready"] Qualified)
              expect $ eventually "" (observe "exists" (Created (pure "toy-key")) id)
        assert (isLeft (inspectScenario invalid)),
      check "effect-free inspection and resolution" $ do
        calls <- evalIO (newIORef 0)
        let inspected = inspectScenario accountScenario
            resolved =
              resolveScenario
                testEnvironment
                testOptions
                (BusinessKeyFrom (BusinessKeyName "accountId") (pure "toy-key"))
                (memoryBinding calls)
                accountScenario
        assert (isRight inspected)
        assert (isRight resolved)
        evalIO (readIORef calls) >>= (=== 0)
        assert (not (Text.isInfixOf "SECRET-FIXTURE-SENTINEL" (Text.pack (show inspected)))),
      check "hidden binding capability denied before acquire" $ do
        calls <- evalIO (newIORef 0)
        let binding = adjustHandlers (\_ _ -> fmap (adjustContract (requiring [ExternalSideEffect]))) (memoryBinding calls)
            Environment envName prod caps policy = testEnvironment
            env = Environment envName prod (Set.delete ExternalSideEffect caps) policy
        assert (isLeft (resolveScenario env testOptions (BusinessKeyFrom (BusinessKeyName "accountId") (pure "toy")) binding accountScenario))
        evalIO (readIORef calls) >>= (=== 0),
      check "synthetic consent and production fail closed" $ do
        calls <- evalIO (newIORef 0)
        let RunOptions key _ build impl target = testOptions
            withoutConsent = RunOptions key False build impl target
            binding = memoryBinding calls
            correlation = BusinessKeyFrom (BusinessKeyName "accountId") (pure "toy")
            Environment envName _ caps policy = testEnvironment
        assert (isLeft (resolveScenario testEnvironment withoutConsent correlation binding accountScenario))
        assert (isLeft (resolveScenario (Environment envName True caps policy) testOptions correlation binding accountScenario))
        evalIO (readIORef calls) >>= (=== 0),
      check "duplicate and misplaced action rejected" $ do
        let invalid = scenario "invalid" "Invalid" "v1" $ do
              first <- given "same" (accept ["ready"] Qualified)
              expect $ eventually "assertion" (observe "false" (Created (pure "slow")) id)
              _ <- act "same" (accept ["created"] (Create (fromRef first) True))
              pure ()
        assert (isLeft (inspectScenario invalid)),
      check "missing handler and unsupported correlation rejected" $ do
        calls <- evalIO (newIORef 0)
        let missing =
              scenario "missing-scenario" "Missing handler" "v1" $
                expect $
                  eventually "missing-assertion" (observe "yes" Missing id)
        assert
          ( isLeft
              ( resolveScenario
                  testEnvironment
                  testOptions
                  (BusinessKeyFrom (BusinessKeyName "key") (pure "value"))
                  (memoryBinding calls)
                  missing
              )
          )
        assert (isLeft (resolveScenario testEnvironment testOptions PropagatedExecutionId (memoryBinding calls) accountScenario)),
      check "durations reject nonpositive and overflowing inputs" $ do
        assert (isLeft (milliseconds 0))
        assert (isLeft (milliseconds (-1)))
        assert (isLeft (milliseconds maxBound))
        assert (isRight (milliseconds 1))
    ]
  where
    check :: String -> PropertyT IO () -> TestTree
    check label = testPropertyNamed label (fromString label) . withTests 1 . property
