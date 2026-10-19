module ResultSpec (tests) where

import Consumer.Account (testOptions)
import Consumer.DeliveryLedger
import Consumer.Hooks (newMicroClock)
import Data.Aeson (Value (..), eitherDecode, encode, toJSON)
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy qualified as LBS
import Data.Either (isLeft)
import Data.IORef
import Data.List (sort)
import Data.Text qualified as Text
import Data.Time (UTCTime (..), fromGregorian)
import GoldenFixtures
import Hedgehog (assert, evalIO, forAll, property, withTests, (===))
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Shoko
import Shoko.Evidence
import Shoko.Result
import Shoko.Result.Json
import Shoko.Scenario (DefinitionError (..))
import Test.Tasty
import Test.Tasty.Hedgehog

tests :: TestTree
tests =
  testGroup
    "versioned result contract"
    [ testPropertyNamed "public consumers round trip with stable goldens and no fixture secrets" "resultGoldens" $ withTests 1 $ property $ do
        reports <- evalIO resultFixtures
        mapM_ (\(_, result) -> decodeRunResult (encodeRunResult result) === Right result) reports
        values <- evalIO valueFixtures
        mapM_
          ( \(name, value) -> do
              expected <- evalIO (LBS.readFile ("test/golden/" ++ name))
              (eitherDecode expected :: Either String Value) === Right value
              assert (not (Text.isInfixOf "SECRET-" (Text.pack (show value))))
          )
          values,
      testPropertyNamed "decoder rejects unknown versions, fields, and digest tampering" "strictResultDecoder" $ withTests 1 $ property $ do
        reports <- evalIO resultFixtures
        case reports of
          (_, result) : _ -> case resultValue result of
            Object fields -> do
              assert (isLeft (decodeRunResult (encode (Object (KeyMap.insert "schemaVersion" (toJSON (999 :: Int)) fields)))))
              let bad = Object (KeyMap.insert "undeclared" (String "SECRET-PARSER-SENTINEL") fields)
              decodeRunResult (encode bad) === Left "invalid shoko result v2"
              let changedReport = case KeyMap.lookup "report" fields of
                    Just (Object report) -> Object (KeyMap.insert "descriptionDigest" (String "wrong") report)
                    _ -> Null
              assert (isLeft (decodeRunResult (encode (Object (KeyMap.insert "report" changedReport fields)))))
            _ -> fail "expected result object"
          _ -> fail "expected report fixtures",
      testPropertyNamed "all reason tags have an explicit wire encoding" "reasonTags" $
        withTests 1 $
          property $
            mapM_
              (\why -> let result = RunnerFault why Nothing in decodeRunResult (encodeRunResult result) === Right result)
              [minBound .. maxBound],
      testPropertyNamed "preflight errors round trip without losing definition IDs" "preflightWire" $ withTests 1 $ property $ do
        let errors =
              [ InvalidDefinition
                  [ InvalidIdentifier,
                    DuplicateIdentifier "duplicate",
                    UnresolvedReference "missing",
                    ActionAfterExpectations,
                    EmptyOutcomeContract "action",
                    EmptyExpectations
                  ],
                MissingHandler "handler",
                MissingSource "source",
                SyntheticConsentRequired,
                UnsupportedCorrelation "op",
                MissingCorrelationReference "ref",
                ProductionUnsupported,
                InvalidBindingIdentifier,
                InvalidLogicalInput
              ]
            result = PreflightFailure errors
        decodeRunResult (encodeRunResult result) === Right result,
      testPropertyNamed "aggregation is associative, commutative, and idempotent" "verdictLaws" $ property $ do
        values <- forAll (Gen.list (Range.linear 0 30) (Gen.element [Pass, Fail, Unknown]))
        split <- forAll (Gen.int (Range.linear 0 (length values)))
        aggregateVerdicts values === aggregateVerdicts (sort values)
        aggregateVerdicts values === aggregateVerdicts (values ++ values)
        aggregateVerdicts values
          === aggregateVerdicts
            [aggregateVerdicts (take split values), aggregateVerdicts (drop split values)],
      testPropertyNamed "repeated polls count distinct durable occurrences" "cardinalityLaw" $ withTests 30 $ property $ do
        copies <- forAll (Gen.int (Range.linear 0 4))
        rows <- evalIO (newIORef [])
        readCalls <- evalIO (newIORef 0)
        (clock, _) <- evalIO (newMicroClock (UTCTime (fromGregorian 2026 10 18) 0))
        result <- evalIO $ case resolveScenario
          ledgerEnvironment
          testOptions
          (businessKeyFromResult (BusinessKeyName "deliveryId") "append")
          (ledgerBinding rows readCalls False)
          (ledgerScenario copies ExactlyOnce) of
          Left errors -> fail (show errors)
          Right resolved -> runScenario clock (LogicalInput "property-v1" [("copies", PublicCount (toInteger copies))]) resolved
        case result of
          Verification VerificationResult {verdict = v, expectations = children} -> do
            v === if copies == 1 then Pass else Fail
            if copies == 1
              then do
                calls <- evalIO (readIORef readCalls)
                assert (calls > 1)
                case children of
                  [ExpectationResult {evidence = Evidence {matchingOccurrenceIds = ids, matchCount = count}}] -> do
                    ids === ["0"]
                    count === 1
                  _ -> fail "expected one cardinality result"
              else pure ()
          _ -> fail "expected a verification result"
    ]
