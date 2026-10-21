module Shoko.Result.Json (encodeRunResult, decodeRunResult, resultValue, descriptionValue, preflightValue) where

import Control.Monad (unless)
import Data.Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Aeson.Types (Parser, parseEither)
import Data.ByteString.Lazy (ByteString)
import Data.Set qualified as Set
import Shoko.Action
import Shoko.Binding hiding (binding, correlation)
import Shoko.Clock (MonotonicTime (..), monotonicMicros)
import Shoko.Correlation
import Shoko.Environment
import Shoko.Evidence
import Shoko.Expectation
import Shoko.Identifier
import Shoko.Internal.Digest qualified as Digest
import Shoko.Observation hiding (predicate)
import Shoko.Prelude
import Shoko.Result
import Shoko.Scenario hiding (namespace)

encodeRunResult :: RunResult -> ByteString
encodeRunResult = encode . resultValue

-- Decode errors intentionally omit input fragments and parser exception text.
decodeRunResult :: ByteString -> Either Text RunResult
decodeRunResult bytes = case eitherDecode bytes >>= parseEither parseResult of
  Left _ -> Left "invalid shoko result v2"
  Right result -> Right result

resultValue :: RunResult -> Value
resultValue (Verification report) =
  object
    ["schemaVersion" .= (2 :: Int), "kind" .= ("verification" :: Text), "report" .= reportValue report]
resultValue (RunnerFault why partial) =
  object
    [ "schemaVersion" .= (2 :: Int),
      "kind" .= ("runner-fault" :: Text),
      "reason" .= tag reasons why,
      "report" .= fmap reportValue partial
    ]
resultValue (PreflightFailure errors) = preflightValue errors

parseResult :: Value -> Parser RunResult
parseResult = withObject "run-result" $ \o -> do
  version <- o .: "schemaVersion" :: Parser Int
  unless (version == 2) (fail "unsupported version")
  kind <- o .: "kind" :: Parser Text
  exactFields o $ case kind of
    "verification" -> ["schemaVersion", "kind", "report"]
    "runner-fault" -> ["schemaVersion", "kind", "reason", "report"]
    "preflight-error" -> ["schemaVersion", "kind", "errors"]
    _ -> ["schemaVersion", "kind"]
  case kind of
    "verification" -> Verification <$> (o .: "report" >>= parseReport)
    "runner-fault" -> RunnerFault <$> enumField o "reason" reasons <*> nullable o "report" parseReport
    "preflight-error" -> do
      errors <- list o "errors" parsePreflight
      unless (not (null errors)) (fail "empty preflight errors")
      pure (PreflightFailure errors)
    _ -> fail "unknown result kind"

reportValue :: VerificationResult -> Value
reportValue (VerificationResult description digest run environment binding build implementation target logical correlations policy started finished start deadline verdict actions expectations disposition) =
  object
    [ "description" .= descriptionValue description,
      "descriptionDigest" .= digest,
      "runId" .= run,
      "environment" .= environment,
      "binding" .= binding,
      "buildIdentity" .= build,
      "implementationIdentity" .= implementation,
      "targetIdentity" .= fmap targetValue target,
      "logicalInput" .= logicalValue logical,
      "correlations" .= map resolvedCorrelationValue correlations,
      "policy" .= policyValue policy,
      "startedAt" .= started,
      "finishedAt" .= finished,
      "executionStartedAt" .= monotonicMicros start,
      "executionDeadline" .= monotonicMicros deadline,
      "verdict" .= tag verdicts verdict,
      "actions" .= map actionValue actions,
      "expectations" .= map expectationValue expectations,
      "disposition" .= map (tag dispositions) disposition
    ]

parseReport :: Value -> Parser VerificationResult
parseReport = checked
  [ "description",
    "descriptionDigest",
    "runId",
    "environment",
    "binding",
    "buildIdentity",
    "implementationIdentity",
    "targetIdentity",
    "logicalInput",
    "correlations",
    "policy",
    "startedAt",
    "finishedAt",
    "executionStartedAt",
    "executionDeadline",
    "verdict",
    "actions",
    "expectations",
    "disposition"
  ]
  "report"
  $ \o -> do
    description <- o .: "description" >>= parseDescription
    digest <- o .: "descriptionDigest"
    unless (digest == Digest.descriptionDigest description) (fail "description digest mismatch")
    VerificationResult description digest
      <$> o .: "runId"
      <*> o .: "environment"
      <*> o .: "binding"
      <*> o .: "buildIdentity"
      <*> o .: "implementationIdentity"
      <*> nullable o "targetIdentity" parseTarget
      <*> (o .: "logicalInput" >>= parseLogical)
      <*> list o "correlations" parseResolvedCorrelation
      <*> (o .: "policy" >>= parsePolicy)
      <*> o .: "startedAt"
      <*> o .: "finishedAt"
      <*> (MonotonicTime <$> o .: "executionStartedAt")
      <*> (MonotonicTime <$> o .: "executionDeadline")
      <*> enumField o "verdict" verdicts
      <*> list o "actions" parseAction
      <*> list o "expectations" parseExpectation
      <*> list o "disposition" (parseTag dispositions)

descriptionValue :: Description -> Value
descriptionValue (Description key title revision nodes expectations correlations) =
  object
    [ "scenarioId" .= key,
      "title" .= title,
      "revision" .= revision,
      "nodes" .= map nodeValue nodes,
      "expectations" .= map expectationDescriptionValue expectations,
      "correlations" .= map correlationDescriptionValue correlations
    ]

parseDescription :: Value -> Parser Description
parseDescription = checked ["scenarioId", "title", "revision", "nodes", "expectations", "correlations"] "description" $ \o ->
  Description
    <$> o .: "scenarioId"
    <*> o .: "title"
    <*> o .: "revision"
    <*> list o "nodes" parseNode
    <*> list o "expectations" parseExpectationDescription
    <*> list o "correlations" parseCorrelationDescription

nodeValue :: NodeDescription -> Value
nodeValue (NodeDescription key fixture operation outcomes) =
  object
    ["nodeId" .= key, "fixture" .= fixture, "operation" .= operationValue operation, "acceptedOutcomes" .= Set.toAscList outcomes]

parseNode :: Value -> Parser NodeDescription
parseNode = checked ["nodeId", "fixture", "operation", "acceptedOutcomes"] "node" $ \o ->
  NodeDescription
    <$> o .: "nodeId"
    <*> o .: "fixture"
    <*> (o .: "operation" >>= parseOperation)
    <*> (Set.fromList <$> o .: "acceptedOutcomes")

expectationDescriptionValue :: ExpectationDescription -> Value
expectationDescriptionValue (ExpectationDescription key temporal windows operation predicate selected) =
  object
    [ "expectationId" .= key,
      "temporal" .= tag temporals temporal,
      "windowsMicros" .= map durationMicros windows,
      "operation" .= operationValue operation,
      "predicateId" .= predicate,
      "correlationId" .= fmap correlationIdText selected
    ]

parseExpectationDescription :: Value -> Parser ExpectationDescription
parseExpectationDescription = checked ["expectationId", "temporal", "windowsMicros", "operation", "predicateId", "correlationId"] "expectation-description" $ \o ->
  ExpectationDescription
    <$> o .: "expectationId"
    <*> enumField o "temporal" temporals
    <*> list o "windowsMicros" parseDuration
    <*> (o .: "operation" >>= parseOperation)
    <*> o .: "predicateId"
    <*> (fmap (fmap CorrelationId) (o .: "correlationId"))

operationValue :: OperationInfo -> Value
operationValue (OperationInfo key required dependencies substeps) =
  object
    [ "operationId" .= key,
      "capabilities" .= map (tag capabilityTags) (Set.toAscList required),
      "dependencies" .= dependencies,
      "substeps" .= map (\(step, caps) -> object ["id" .= step, "capabilities" .= map (tag capabilityTags) (Set.toAscList caps)]) substeps
    ]

parseOperation :: Value -> Parser OperationInfo
parseOperation = checked ["operationId", "capabilities", "dependencies", "substeps"] "operation" $ \o ->
  OperationInfo
    <$> o .: "operationId"
    <*> (Set.fromList <$> list o "capabilities" (parseTag capabilityTags))
    <*> o .: "dependencies"
    <*> list
      o
      "substeps"
      ( checked ["id", "capabilities"] "substep-description" $ \step ->
          (,) <$> step .: "id" <*> (Set.fromList <$> list step "capabilities" (parseTag capabilityTags))
      )

actionValue :: ActionEvidence -> Value
actionValue (ActionEvidence node operation declared observed started finished why substeps details) =
  object
    [ "nodeId" .= node,
      "operationId" .= operation,
      "declaredOutcomes" .= declared,
      "observedOutcome" .= observed,
      "startedAt" .= monotonicMicros started,
      "finishedAt" .= monotonicMicros finished,
      "reason" .= tag reasons why,
      "substeps" .= map substepValue substeps,
      "supportingData" .= map publicValue details
    ]

parseAction :: Value -> Parser ActionEvidence
parseAction = checked ["nodeId", "operationId", "declaredOutcomes", "observedOutcome", "startedAt", "finishedAt", "reason", "substeps", "supportingData"] "action" $ \o ->
  ActionEvidence
    <$> o .: "nodeId"
    <*> o .: "operationId"
    <*> o .: "declaredOutcomes"
    <*> o .: "observedOutcome"
    <*> (MonotonicTime <$> o .: "startedAt")
    <*> (MonotonicTime <$> o .: "finishedAt")
    <*> enumField o "reason" reasons
    <*> list o "substeps" parseSubstep
    <*> list o "supportingData" parsePublicValue

substepValue :: SubstepEvidence -> Value
substepValue (SubstepEvidence key started finished why) =
  object
    ["id" .= key, "startedAt" .= monotonicMicros started, "finishedAt" .= monotonicMicros finished, "reason" .= tag reasons why]

parseSubstep :: Value -> Parser SubstepEvidence
parseSubstep = checked ["id", "startedAt", "finishedAt", "reason"] "substep" $ \o ->
  SubstepEvidence <$> o .: "id" <*> (MonotonicTime <$> o .: "startedAt") <*> (MonotonicTime <$> o .: "finishedAt") <*> enumField o "reason" reasons

expectationValue :: ExpectationResult -> Value
expectationValue (ExpectationResult key verdict why evidence) =
  object
    ["expectationId" .= key, "verdict" .= tag verdicts verdict, "reason" .= tag reasons why, "evidence" .= evidenceValue evidence]

parseExpectation :: Value -> Parser ExpectationResult
parseExpectation = checked ["expectationId", "verdict", "reason", "evidence"] "expectation-result" $ \o ->
  ExpectationResult
    <$> o .: "expectationId"
    <*> enumField o "verdict" verdicts
    <*> enumField o "reason" reasons
    <*> (o .: "evidence" >>= parseEvidence)

evidenceValue :: Evidence -> Value
evidenceValue (Evidence source operation baseline started finished coverage identities count gaps deadline details) =
  object
    [ "source" .= sourceIdText source,
      "operationId" .= operation,
      "baseline" .= fmap baselineValue baseline,
      "pollStartedAt" .= monotonicMicros started,
      "finishedAt" .= monotonicMicros finished,
      "coverage" .= fmap coverageValue coverage,
      "matchingOccurrenceIds" .= identities,
      "matchCount" .= count,
      "gaps" .= gaps,
      "evidenceDeadline" .= monotonicMicros deadline,
      "supportingData" .= map publicValue details
    ]

parseEvidence :: Value -> Parser Evidence
parseEvidence = checked ["source", "operationId", "baseline", "pollStartedAt", "finishedAt", "coverage", "matchingOccurrenceIds", "matchCount", "gaps", "evidenceDeadline", "supportingData"] "evidence" $ \o ->
  Evidence
    <$> (SourceId <$> o .: "source")
    <*> o .: "operationId"
    <*> nullable o "baseline" parseBaseline
    <*> (MonotonicTime <$> o .: "pollStartedAt")
    <*> (MonotonicTime <$> o .: "finishedAt")
    <*> nullable o "coverage" parseCoverage
    <*> o .: "matchingOccurrenceIds"
    <*> o .: "matchCount"
    <*> o .: "gaps"
    <*> (MonotonicTime <$> o .: "evidenceDeadline")
    <*> list o "supportingData" parsePublicValue

baselineValue :: Baseline -> Value
baselineValue (Baseline source captured cursor) = object ["source" .= sourceIdText source, "capturedAt" .= monotonicMicros captured, "cursor" .= cursor]

parseBaseline :: Value -> Parser Baseline
parseBaseline = checked ["source", "capturedAt", "cursor"] "baseline" $ \o -> Baseline <$> (SourceId <$> o .: "source") <*> (MonotonicTime <$> o .: "capturedAt") <*> o .: "cursor"

coverageValue :: Coverage -> Value
coverageValue (Coverage strength from through complete) =
  object
    ["strength" .= tag strengths strength, "fromMicros" .= monotonicMicros from, "throughMicros" .= monotonicMicros through, "complete" .= complete]

parseCoverage :: Value -> Parser Coverage
parseCoverage = checked ["strength", "fromMicros", "throughMicros", "complete"] "coverage" $ \o ->
  Coverage <$> enumField o "strength" strengths <*> (MonotonicTime <$> o .: "fromMicros") <*> (MonotonicTime <$> o .: "throughMicros") <*> o .: "complete"

publicValue :: (Text, PublicValue) -> Value
publicValue (key, value) = case value of
  PublicChoice choice -> object ["key" .= key, "kind" .= ("choice" :: Text), "value" .= choice]
  PublicCount count -> object ["key" .= key, "kind" .= ("count" :: Text), "value" .= count]
  PublicFlag flag -> object ["key" .= key, "kind" .= ("flag" :: Text), "value" .= flag]

parsePublicValue :: Value -> Parser (Text, PublicValue)
parsePublicValue = checked ["key", "kind", "value"] "public-value" $ \o -> do
  key <- o .: "key"
  kind <- o .: "kind" :: Parser Text
  value <- case kind of
    "choice" -> PublicChoice <$> o .: "value"
    "count" -> PublicCount <$> o .: "value"
    "flag" -> PublicFlag <$> o .: "value"
    _ -> fail "unknown public-value kind"
  pure (key, value)

logicalValue :: LogicalInput -> Value
logicalValue (LogicalInput revision parameters) = object ["recipeRevision" .= revision, "parameters" .= map publicValue parameters]

parseLogical :: Value -> Parser LogicalInput
parseLogical = checked ["recipeRevision", "parameters"] "logical-input" $ \o ->
  LogicalInput <$> o .: "recipeRevision" <*> list o "parameters" parsePublicValue

correlationValue :: Correlation -> Value
correlationValue (ByBusinessKey key value) = object ["kind" .= ("business-key" :: Text), "key" .= businessKeyNameText key, "value" .= value]
correlationValue (ByExecutionId value) = object ["kind" .= ("execution-id" :: Text), "value" .= value]

parseCorrelation :: Value -> Parser Correlation
parseCorrelation = withObject "correlation" $ \o -> do
  kind <- o .: "kind" :: Parser Text
  exactFields o (if kind == "business-key" then ["kind", "key", "value"] else ["kind", "value"])
  case kind of
    "business-key" -> ByBusinessKey <$> (BusinessKeyName <$> o .: "key") <*> o .: "value"
    "execution-id" -> ByExecutionId <$> o .: "value"
    _ -> fail "unknown correlation"

targetValue :: TargetIdentity -> Value
targetValue (TargetIdentity target namespace revision) = object ["target" .= target, "namespaceUid" .= namespace, "deploymentRevision" .= revision]

parseTarget :: Value -> Parser TargetIdentity
parseTarget = checked ["target", "namespaceUid", "deploymentRevision"] "target" $ \o ->
  TargetIdentity <$> o .: "target" <*> o .: "namespaceUid" <*> o .: "deploymentRevision"

policyValue :: PolicyReport -> Value
policyValue (PolicyReport required strategy) =
  object
    ["requiredCapabilities" .= map (tag capabilityTags) (Set.toAscList required), "correlationStrategies" .= map (tag strategies) (Set.toAscList strategy)]

parsePolicy :: Value -> Parser PolicyReport
parsePolicy = checked ["requiredCapabilities", "correlationStrategies"] "policy" $ \o ->
  PolicyReport <$> (Set.fromList <$> list o "requiredCapabilities" (parseTag capabilityTags)) <*> (Set.fromList <$> list o "correlationStrategies" (parseTag strategies))

parseDuration :: Value -> Parser Duration
parseDuration value = do
  micros <- parseJSON value :: Parser Int
  unless (micros `mod` 1000 == 0) (fail "duration precision")
  either (const (fail "invalid duration")) pure (milliseconds (micros `div` 1000))

checked :: [Key] -> String -> (Object -> Parser a) -> Value -> Parser a
checked allowed name parser = withObject name $ \o -> do
  unless (all (`elem` allowed) (KeyMap.keys o)) (fail "unknown field")
  parser o

list :: Object -> Key -> (Value -> Parser a) -> Parser [a]
list o key parser = (o .: key :: Parser [Value]) >>= mapM parser

nullable :: Object -> Key -> (Value -> Parser a) -> Parser (Maybe a)
nullable o key parser = (o .: key :: Parser (Maybe Value)) >>= traverse parser

enumField :: Object -> Key -> [(Text, a)] -> Parser a
enumField o key table = o .: key >>= parseTag table

parseTag :: [(Text, a)] -> Value -> Parser a
parseTag table = withText "tag" $ \value -> maybe (fail "unknown tag") pure (lookup value table)

tag :: (Eq a) => [(Text, a)] -> a -> Value
tag table value = String $ case [key | (key, candidate) <- table, candidate == value] of
  key : _ -> key
  [] -> "unmapped-tag"

verdicts :: [(Text, Verdict)]
verdicts = [("pass", Pass), ("fail", Fail), ("unknown", Unknown)]

reasons :: [(Text, Reason)]
reasons =
  [ ("satisfied", Satisfied),
    ("mismatch", Mismatch),
    ("source-unavailable", SourceUnavailable),
    ("deadline-exceeded", DeadlineExceeded),
    ("coverage-incomplete", CoverageIncomplete),
    ("correlation-lost", CorrelationLost),
    ("prerequisite-unavailable", PrerequisiteUnavailable),
    ("missing-occurrence-identity", MissingOccurrenceIdentity),
    ("undeclared-operation", UndeclaredOperation),
    ("invalid-evidence", InvalidEvidence),
    ("unexpected-runner-fault", UnexpectedRunnerFault)
  ]

capabilityTags :: [(Text, Capability)]
capabilityTags =
  [ ("read-state", ReadState),
    ("read-events", ReadEvents),
    ("write-state", WriteState),
    ("send-http", SendHttp),
    ("external-side-effect", ExternalSideEffect),
    ("synthetic-resource", SyntheticResource)
  ]

temporals :: [(Text, Temporal)]
temporals = [("eventually", Eventually), ("never", Never), ("exactly-once", ExactlyOnce)]

strengths :: [(Text, CoverageStrength)]
strengths = [("sampled-state", SampledState), ("durable-history", DurableHistory)]

strategies :: [(Text, CorrelationStrategy)]
strategies = [("business-key", BusinessKey), ("execution-id", ExecutionId)]

dispositions :: [(Text, Disposition)]
dispositions = [("cleaned", Cleaned), ("retained", Retained), ("failed", CleanupFailed), ("timed-out", CleanupTimedOut)]

preflightValue :: [PreflightError] -> Value
preflightValue errors = object ["schemaVersion" .= (2 :: Int), "kind" .= ("preflight-error" :: Text), "errors" .= map render errors]
  where
    render failure = case failure of
      InvalidDefinition definitionErrors -> object ["code" .= ("invalid-definition" :: Text), "details" .= map definitionValue definitionErrors]
      MissingHandler key -> identified "missing-handler" key
      MissingSource key -> identified "missing-source" key
      InconsistentSource label -> identified "inconsistent-source" (sourceIdText label)
      HandlerConstructionFailed key cause -> object ["code" .= ("handler-construction-failed" :: Text), "id" .= key, "cause" .= handlerErrorValue cause]
      CapabilitiesDenied caps -> object ["code" .= ("capabilities-denied" :: Text), "capabilities" .= map (tag capabilityTags) (Set.toAscList caps)]
      SyntheticConsentRequired -> identified "synthetic-consent-required" ""
      UnselectedCorrelation key -> identified "unselected-correlation" key
      UndeclaredCorrelation key selected -> selectedError "undeclared-correlation" key selected
      IncompatibleCorrelation key selected -> selectedError "incompatible-correlation" key selected
      ProductionUnsupported -> identified "production-unsupported" ""
      InvalidBindingIdentifier -> identified "invalid-binding-identifier" ""
      InvalidLogicalInput -> identified "invalid-logical-input" ""

identified :: Text -> Text -> Value
identified code key = object ["code" .= code, "id" .= key]

definitionValue :: DefinitionError -> Value
definitionValue problem = case problem of
  InvalidIdentifier -> identified "invalid-identifier" ""
  DuplicateIdentifier key -> identified "duplicate-identifier" key
  UnresolvedReference key -> identified "unresolved-reference" key
  ActionAfterExpectations -> identified "action-after-expectations" ""
  EmptyOutcomeContract key -> identified "empty-outcome-contract" key
  ConflictingOperation key -> identified "conflicting-operation" key
  EmptyExpectations -> identified "empty-expectations" ""

parsePreflight :: Value -> Parser PreflightError
parsePreflight = withObject "preflight-error" $ \o -> do
  code <- o .: "code" :: Parser Text
  let fields = case code of
        "invalid-definition" -> ["code", "details"]
        "capabilities-denied" -> ["code", "capabilities"]
        "handler-construction-failed" -> ["code", "id", "cause"]
        "undeclared-correlation" -> ["code", "id", "correlationId"]
        "incompatible-correlation" -> ["code", "id", "correlationId"]
        _ -> ["code", "id"]
  exactFields o fields
  if "id" `elem` fields then (o .: "id" :: Parser Text) >> pure () else pure ()
  case code of
    "invalid-definition" -> InvalidDefinition <$> list o "details" parseDefinition
    "missing-handler" -> MissingHandler <$> o .: "id"
    "missing-source" -> MissingSource <$> o .: "id"
    "inconsistent-source" -> InconsistentSource . SourceId <$> o .: "id"
    "handler-construction-failed" -> HandlerConstructionFailed <$> o .: "id" <*> (o .: "cause" >>= parseHandlerError)
    "capabilities-denied" -> CapabilitiesDenied . Set.fromList <$> list o "capabilities" (parseTag capabilityTags)
    "synthetic-consent-required" -> pure SyntheticConsentRequired
    "unselected-correlation" -> UnselectedCorrelation <$> o .: "id"
    "undeclared-correlation" -> UndeclaredCorrelation <$> o .: "id" <*> (CorrelationId <$> o .: "correlationId")
    "incompatible-correlation" -> IncompatibleCorrelation <$> o .: "id" <*> (CorrelationId <$> o .: "correlationId")
    "production-unsupported" -> pure ProductionUnsupported
    "invalid-binding-identifier" -> pure InvalidBindingIdentifier
    "invalid-logical-input" -> pure InvalidLogicalInput
    _ -> fail "unknown preflight code"

parseDefinition :: Value -> Parser DefinitionError
parseDefinition = checked ["code", "id"] "definition-error" $ \o -> do
  code <- o .: "code" :: Parser Text
  _ <- o .: "id" :: Parser Text
  case code of
    "invalid-identifier" -> pure InvalidIdentifier
    "duplicate-identifier" -> DuplicateIdentifier <$> o .: "id"
    "unresolved-reference" -> UnresolvedReference <$> o .: "id"
    "action-after-expectations" -> pure ActionAfterExpectations
    "empty-outcome-contract" -> EmptyOutcomeContract <$> o .: "id"
    "conflicting-operation" -> ConflictingOperation <$> o .: "id"
    "empty-expectations" -> pure EmptyExpectations
    _ -> fail "unknown definition code"

handlerErrorValue :: HandlerBuildError -> Value
handlerErrorValue (EndpointNotAllowlisted key) = identified "endpoint-not-allowlisted" key
handlerErrorValue (ObservationMethodNotGet key) = identified "observation-method-not-get" key
handlerErrorValue (ObservationScopeMissing key) = identified "observation-scope-missing" key
handlerErrorValue ExecutionMetadataUnsupported = object ["code" .= ("execution-metadata-unsupported" :: Text)]
handlerErrorValue (UnsupportedEventScope key) = identified "unsupported-event-scope" key
handlerErrorValue (UnsupportedCorrelationSource key) = identified "unsupported-correlation-source" key

parseHandlerError :: Value -> Parser HandlerBuildError
parseHandlerError = withObject "handler-error" $ \o -> do
  code <- o .: "code" :: Parser Text
  let identifiedCause constructor = do
        unless (all (`elem` ["code", "id"]) (KeyMap.keys o)) (fail "unknown field")
        constructor <$> o .: "id"
  case code of
    "endpoint-not-allowlisted" -> identifiedCause EndpointNotAllowlisted
    "observation-method-not-get" -> identifiedCause ObservationMethodNotGet
    "observation-scope-missing" -> identifiedCause ObservationScopeMissing
    "unsupported-event-scope" -> identifiedCause UnsupportedEventScope
    "unsupported-correlation-source" -> identifiedCause UnsupportedCorrelationSource
    "execution-metadata-unsupported" -> do
      unless (KeyMap.keys o == ["code"]) (fail "unknown field")
      pure ExecutionMetadataUnsupported
    _ -> fail "unknown handler cause"

selectedError :: Text -> Text -> CorrelationId -> Value
selectedError code key selected = object ["code" .= code, "id" .= key, "correlationId" .= correlationIdText selected]

correlationDescriptionValue :: CorrelationDescription -> Value
correlationDescriptionValue (CorrelationDescription identity key strategy deps) =
  object
    [ "correlationId" .= correlationIdText identity,
      "correlationKey" .= businessKeyNameText key,
      "strategy" .= tag strategies strategy,
      "dependencies" .= deps
    ]

parseCorrelationDescription :: Value -> Parser CorrelationDescription
parseCorrelationDescription = checked ["correlationId", "correlationKey", "strategy", "dependencies"] "correlation-description" $ \o ->
  CorrelationDescription <$> (CorrelationId <$> o .: "correlationId") <*> (BusinessKeyName <$> o .: "correlationKey") <*> enumField o "strategy" strategies <*> o .: "dependencies"

resolvedCorrelationValue :: ResolvedCorrelation -> Value
resolvedCorrelationValue (ResolvedCorrelation identity value) = object ["correlationId" .= correlationIdText identity, "resolvedCorrelation" .= correlationValue value]

parseResolvedCorrelation :: Value -> Parser ResolvedCorrelation
parseResolvedCorrelation = checked ["correlationId", "resolvedCorrelation"] "resolved-correlation" $ \o ->
  ResolvedCorrelation <$> (CorrelationId <$> o .: "correlationId") <*> (o .: "resolvedCorrelation" >>= parseCorrelation)

-- Tagged alternatives have their own closed field inventories, not their union.
exactFields :: Object -> [Key] -> Parser ()
exactFields fields expected =
  unless (all (`elem` expected) (KeyMap.keys fields) && all (`KeyMap.member` fields) expected) (fail "unexpected fields")
