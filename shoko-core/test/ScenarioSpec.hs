module ScenarioSpec (tests) where

import Consumer.Account
import Data.Either (isLeft, isRight)
import Data.IORef
import Data.Set qualified as Set
import Data.String (fromString)
import Data.Text qualified as Text
import Hedgehog (PropertyT, assert, evalIO, property, withTests, (===))
import Shoko
import Test.Tasty
import Test.Tasty.Hedgehog

tests :: TestTree
tests =
  testGroup
    "description and policy"
    [ check "effect-free inspection and resolution" $ do
        calls <- evalIO (newIORef 0)
        let inspected = inspectScenario accountScenario
            resolved =
              resolveScenario
                testEnvironment
                testOptions
                (BusinessKeyFrom "accountId" (pure "toy-key"))
                (memoryBinding calls)
                accountScenario
        assert (isRight inspected)
        assert (isRight resolved)
        evalIO (readIORef calls) >>= (=== 0)
        assert (not (Text.isInfixOf "SECRET-FIXTURE-SENTINEL" (Text.pack (show inspected)))),
      check "hidden binding capability denied before acquire" $ do
        calls <- evalIO (newIORef 0)
        let Binding name lifecycle lookupContract acquire release baseline action observation = memoryBinding calls
            hiddenContract :: OperationRole -> Account a -> Maybe BindingContract
            hiddenContract role op = case lookupContract role op of
              Nothing -> Nothing
              Just (BindingContract extraCaps cleanup support source strength) ->
                Just (BindingContract (Set.insert ExternalSideEffect extraCaps) cleanup support source strength)
            binding = Binding name lifecycle hiddenContract acquire release baseline action observation
            Environment envName prod caps policy = testEnvironment
            env = Environment envName prod (Set.delete ExternalSideEffect caps) policy
        assert (isLeft (resolveScenario env testOptions (BusinessKeyFrom "accountId" (pure "toy")) binding accountScenario))
        evalIO (readIORef calls) >>= (=== 0),
      check "synthetic consent and production fail closed" $ do
        calls <- evalIO (newIORef 0)
        let RunOptions key _ build impl target = testOptions
            withoutConsent = RunOptions key False build impl target
            binding = memoryBinding calls
            correlation = BusinessKeyFrom "accountId" (pure "toy")
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
                  (BusinessKeyFrom "key" (pure "value"))
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
