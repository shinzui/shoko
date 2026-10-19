{-# LANGUAGE RankNTypes #-}

module AdapterTests (postgresTests, httpTests, roundtripTests) where

import Control.Exception (bracket)
import Control.Monad (unless, when)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.IORef
import Data.Set qualified as Set
import Data.String (fromString)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Hasql.Connection qualified as C
import Hasql.Connection.Settings qualified as CS
import Hasql.Session qualified as S
import Hedgehog (evalIO, property, withTests)
import Shoko
import Shoko.Adapter.Http qualified as Http
import Shoko.Adapter.Postgres qualified as Pg
import Shoko.Clock
import Shoko.Result hiding (binding)
import Shoko.Result.Json
import System.Environment (getEnv)
import Test.Tasty
import Test.Tasty.Hedgehog (testPropertyNamed)

check :: Bool -> IO ()
check value = unless value (fail "adapter assertion failed")

test :: String -> IO () -> TestTree
test title action = testPropertyNamed title (fromString title) (withTests 1 (property (evalIO action)))

ident :: Text.Text -> Pg.Identifier
ident name = either (error . Text.unpack) id (Pg.identifier name)

table :: Pg.Table
table = Pg.Table (ident "fixture") (ident "accounts")

scope :: Pg.Scope
scope = Pg.Scope (BusinessKeyName "accountId") (ident "id")

context :: Text.Text -> Int -> IO CallContext
context key budget = do
  let Clock now _ _ _ = realClock
  start <- now
  let end = MonotonicTime (monotonicMicros start + toInteger budget)
  pure (detachedCallContext realClock end end Nothing (Just (ByBusinessKey (BusinessKeyName "accountId") key)))

query :: Text.Text -> Pg.Query a -> IO (Either Pg.PostgresFailure (a, Pg.Sample))
query key descriptor = do
  resource <- Pg.postgres . Text.pack <$> getEnv "SHOKO_TEST_PG"
  call <- context key 2000000
  Pg.runQuery call resource descriptor

valueIs :: (Eq a) => a -> Either e (a, b) -> Bool
valueIs expected (Right (actual, _)) = expected == actual
valueIs _ _ = False

postgresTests :: TestTree
postgresTests =
  testGroup
    "real PostgreSQL"
    [ test "existence count and scoped absence" $ do
        query "one" (Pg.rowExists table scope Nothing) >>= check . valueIs True
        query "one" (Pg.rowCount table scope Nothing) >>= check . valueIs 1
        query "not-one" (Pg.rowAbsent table scope Nothing) >>= check . valueIs True
        query "one' OR true --" (Pg.rowCount table scope Nothing) >>= check . valueIs 0,
      test "typed conjunction and null absent multiple values" $ do
        let condition = Pg.andAlso (Pg.equals (ident "amount") Pg.SqlInt64 1) (Pg.equals (ident "active") Pg.SqlBool True)
        query "one" (Pg.rowCount table scope (Just condition)) >>= check . valueIs 1
        let column = Pg.columnValue table scope Nothing (ident "value") Pg.SqlText
        query "missing" column >>= check . valueIs Pg.NoRows
        query "null" column >>= check . valueIs Pg.NullValue
        query "one" column >>= check . valueIs (Pg.OneValue "value")
        query "many" column >>= check . valueIs Pg.MultipleRows,
      test "identifier and correlation rejection" $ do
        check (either (const True) (const False) (Pg.identifier "accounts; DROP TABLE accounts"))
        let noCorrelation = detachedCallContext realClock (MonotonicTime 999999) (MonotonicTime 999999) Nothing Nothing
        answer <- Pg.runQuery noCorrelation (Pg.postgres "not-a-connection") (Pg.rowExists table scope Nothing)
        check (either (== Pg.CorrelationUnavailable) (const False) answer),
      test "decoding failure is unavailable, never empty" $ do
        answer <- query "one" (Pg.columnValue table scope Nothing (ident "value") Pg.SqlInt64)
        unless (either (== Pg.DecodeUnavailable) (const False) answer) (fail (show answer)),
      test "server-side timeout respects the remaining request budget" $ do
        settings <- Text.pack <$> getEnv "SHOKO_TEST_PG"
        call <- context "slow" 40000
        answer <- Pg.runQuery call (Pg.postgres settings) (Pg.rowExists (Pg.Table (ident "fixture") (ident "slow")) scope Nothing)
        check (either (== Pg.DeadlineExpired) (const False) answer),
      test "read credential cannot mutate and permission error is typed" $ do
        settings <- Text.pack <$> getEnv "SHOKO_TEST_PG"
        bracket (C.acquire (CS.connectionString settings)) (either (const (pure ())) C.release) $ \case
          Left _ -> fail "fixture connection failed"
          Right connection -> C.use connection (S.script "INSERT INTO fixture.accounts(id) VALUES ('forbidden')") >>= check . either (const True) (const False)
        answer <- query "one" (Pg.rowCount (Pg.Table (ident "pg_catalog") (ident "pg_authid")) (Pg.Scope (BusinessKeyName "accountId") (ident "rolname")) Nothing)
        check (either (== Pg.PermissionDenied) (const False) answer)
    ]

config :: IO Http.HttpConfig
config = do
  base <- Text.pack <$> getEnv "SHOKO_TEST_HTTP"
  unavailable <- Text.pack <$> getEnv "SHOKO_TEST_UNAVAILABLE_HTTP"
  let make name route method limit = Http.endpoint name (base <> route) method limit Set.empty (name == "headers") (Just (BusinessKeyName "accountId", "id"))
  endpoints <-
    traverse
      (either (fail . Text.unpack) pure)
      [ make "create" "/create" Http.Post 1024,
        make "noop" "/noop" Http.Post 1024,
        make "invalid" "/invalid" Http.Post 1024,
        make "different" "/different" Http.Post 1024,
        make "undecodable" "/undecodable" Http.Post 1024,
        make "slow" "/slow" Http.Post 1024,
        make "large" "/large" Http.Post 64,
        make "redirect" "/redirect" Http.Post 1024,
        make "headers" "/headers" Http.Post 1024,
        make "read" "/read" Http.Get 1024,
        Http.endpoint "closed" unavailable Http.Post 1024 Set.empty False Nothing
      ]
  either (fail . Text.unpack) pure (Http.httpConfig endpoints)

payload :: Text.Text -> Http.HttpPayload
payload key = Http.HttpPayload (Text.encodeUtf8 key) "text/plain" (Just "Bearer ADAPTER-SECRET-SENTINEL") Nothing (Just "adapter-run")

httpTests :: TestTree
httpTests =
  testGroup
    "real HTTP"
    [ test "scenario execution ID reaches opted-in HTTP endpoints and conflicting labels fail" $ do
        executionRoundtrip "on" False "adapter-run" >>= expectVerdict Pass
        executionRoundtrip "off" False "none" >>= expectVerdict Pass
        executionRoundtrip "on" True "adapter-run" >>= expectVerdict Unknown,
      test "bounded body and redirect classification" $ do
        resource <- config >>= Http.newHttp
        call <- context "transport-check" 2000000
        answer <- Http.httpAction resource call "large" (payload "large-key") (\_ _ -> Right ("okay", ()))
        check (case answer of ActionUnavailable _ -> True; _ -> False)
        redirect <- Http.httpAction resource call "redirect" (payload "must-not-create") (\status _ -> Right (if status == 307 then "redirect" else "unexpected", ()))
        check (case redirect of ActionObservedWithDetails "redirect" _ _ -> True; _ -> False)
        query "must-not-create" (Pg.rowAbsent table scope Nothing) >>= check . valueIs True,
      test "timeout sends mutation once and returns bounded uncertainty" $ do
        resource <- config >>= Http.newHttp
        call <- context "slow-key" 40000
        answer <- Http.httpAction resource call "slow" (payload "slow-key") (\_ _ -> Right ("okay", ()))
        check (case answer of ActionUnavailable _ -> True; _ -> False),
      test "validated trace context and endpoint allowlist" $ do
        trace <- either (fail . Text.unpack) pure (Http.traceParent "00-0123456789abcdef0123456789abcdef-0123456789abcdef-01")
        check (either (const True) (const False) (Http.traceParent "00-00000000000000000000000000000000-0123456789abcdef-01"))
        resource <- config >>= Http.newHttp
        call <- context "headers-key" 2000000
        answer <- Http.httpAction resource call "headers" (Http.HttpPayload "" "text/plain" Nothing (Just trace) (Just "adapter-run")) (\status bytes -> Right ("okay", status == 200 && bytes == "true"))
        check (case answer of ActionObservedWithDetails "okay" True _ -> True; _ -> False)
        denied <- Http.httpAction resource call "unapproved" (payload "key") (\_ _ -> Right ("okay", ()))
        check (case denied of ActionUnavailable _ -> True; _ -> False)
    ]

data Execution a where
  SendExecution :: Text.Text -> Bool -> Execution Text.Text
  ReadExecution :: Input Text.Text -> Text.Text -> Execution Bool

instance Vocabulary Execution where
  describeOperation (SendExecution _ _) = declareOperation "execution-send" []
  describeOperation (ReadExecution input _) = dependsOn input (declareOperation "execution-observed" [ReadState])

executionRoundtrip :: Text.Text -> Bool -> Text.Text -> IO RunResult
executionRoundtrip endpointName conflict expected = do
  base <- Text.pack <$> getEnv "SHOKO_TEST_HTTP"
  endpoints <-
    traverse
      (either (fail . Text.unpack) pure)
      [ Http.endpoint "on" (base <> "/execution") Http.Post 1024 Set.empty True Nothing,
        Http.endpoint "off" (base <> "/execution") Http.Post 1024 Set.empty False Nothing
      ]
  httpConfig <- either (fail . Text.unpack) pure (Http.httpConfig endpoints)
  let handlers :: OperationRole -> Execution a -> Either HandlerBuildError (Maybe (Handler Http.Http a))
      handlers ActionOperation (SendExecution route conflicting) =
        Just
          <$> Http.httpActionHandler
            httpConfig
            route
            (\_ -> pure (Right (Http.HttpPayload "" "text/plain" Nothing Nothing (if conflicting then Just "conflict" else Nothing))))
            (\status bytes -> if status == 200 then Right ("sent", Text.decodeUtf8 bytes) else Left Http.ResponseUndecodable)
      handlers ObservationOperation (ReadExecution input wanted) = Right $ Just $ observationHandler noRequirements RequiresExecutionId (sampledSource (SourceId "execution.echo")) $ \_ call -> do
        answer <- resolveInput call input
        let found = case (answer, correlation call, executionId call) of
              (Right value, Just (ByExecutionId selected), Just propagated) -> value == wanted && selected == propagated
              _ -> False
        tick <- monotonic (callClock call)
        pure (Observed [Occurrence Nothing found] (Coverage SampledState tick tick True))
      handlers _ _ = Right Nothing
      selectedBinding = binding "http-execution" (const (Http.newHttp httpConfig)) (const (pure Cleaned)) handlers
      source = scenario "execution-http" "Explicit transport opt-in" "1" $ do
        handle <- propagateExecutionId
        answer <- act "send" (accept ["sent"] (SendExecution endpointName conflict))
        expect $ eventually "received" (correlatedBy handle (observe "expected-header" (ReadExecution (fromRef answer) expected) id))
      environment = Environment "local" False (Set.fromList [SendHttp, WriteState, ReadState]) defaultPolicy
  resolved <- either (fail . show) pure (resolveScenario environment (RunOptions "adapter-run" False "fixture" Nothing Nothing) selectedBinding source)
  runScenario realClock (LogicalInput "execution" []) resolved

data Op a where
  Command :: Text.Text -> Text.Text -> Op Text.Text
  State :: Input Text.Text -> Bool -> Op Bool
  Rest :: Input Text.Text -> Op Bool

instance Vocabulary Op where
  describeOperation (Command route _) = OperationInfo ("command-" <> route) Set.empty [] []
  describeOperation (State key _) = OperationInfo "state" (Set.singleton ReadState) (inputDependencies key) []
  describeOperation (Rest key) = OperationInfo "rest" (Set.singleton ReadState) (inputDependencies key) []

localBinding :: Http.HttpConfig -> Text.Text -> Binding Op (Http.Http, Pg.Postgres)
localBinding httpConfig = localBindingUsing httpConfig httpConfig

localBindingUsing :: Http.HttpConfig -> Http.HttpConfig -> Text.Text -> Binding Op (Http.Http, Pg.Postgres)
localBindingUsing httpConfig acquiredConfig settings =
  binding
    "local-adapters"
    (\_ -> (,Pg.postgres settings) <$> Http.newHttp acquiredConfig)
    (\_ -> pure Cleaned)
    handlers
  where
    handlers :: forall a. OperationRole -> Op a -> Either HandlerBuildError (Maybe (Handler (Http.Http, Pg.Postgres) a))
    handlers ActionOperation (Command route key) =
      Just . focus fst <$> Http.httpActionHandler httpConfig route (\_ -> pure (Right (payload key))) (decodeAction key)
    handlers ObservationOperation (State input absent) =
      let descriptor = (if absent then Pg.rowAbsent else Pg.rowExists) table scope Nothing
          pg = focus snd (Pg.postgresObservation (SourceId "sql") descriptor)
          guarded = case handlerSource pg of
            Nothing -> pg
            Just owned -> observationHandler (handlerContract pg) (RequiresBusinessKey (BusinessKeyName "accountId")) owned $ \(_, resource) call ->
              guardCorrelation (BusinessKeyName "accountId") input call (Pg.observeQuery call resource descriptor)
       in Right (Just guarded)
    handlers ObservationOperation (Rest input) = do
      http <-
        Http.httpObservationHandler
          httpConfig
          "read"
          ( \call ->
              resolveInput call input >>= \case
                Left err -> pure (Left (Http.PayloadInputError err))
                Right _ -> pure (Right Http.emptyPayload)
          )
          decodeRead
      pure (Just (focus fst http))
    handlers _ _ = Right Nothing
    decodeRead status bytes = if status == 200 && bytes `elem` ["true", "false"] then Right (bytes == "true") else Left Http.ResponseUndecodable
    decodeAction key status bytes =
      if status == 201
        then Right ("created", Text.decodeUtf8 bytes)
        else
          if status == 422 && bytes == "invalid-input"
            then Right ("invalid-input", key)
            else
              if status == 409 && bytes == "duplicate"
                then Right ("duplicate", key)
                else Left Http.ResponseUndecodable

run :: Text.Text -> Text.Text -> [Text.Text] -> Bool -> Text.Text -> IO RunResult
run route key tags absent settings = do
  httpConfig <- config
  budget <- either (fail . Text.unpack) pure (milliseconds 2000)
  window <- either (fail . Text.unpack) pure (milliseconds 500)
  poll <- either (fail . Text.unpack) pure (milliseconds 1000)
  -- This IO smoke test schedules one conclusive state sample, then waits for
  -- its window to expire. Fake-clock core tests cover repeated-poll semantics.
  -- Starting a fresh DB request in the last millisecond can honestly be Unknown.
  let environment = Environment "local-fixture" False (Set.fromList [ReadState, WriteState, SendHttp]) (Policy budget window poll budget)
      scenarioValue = scenario "adapter-roundtrip" "HTTP then SQL" "1" $ do
        result <- act "command" (accept tags (Command route key))
        selectedCorrelation <- correlate (CorrelationAlias "account") (BusinessKeyName "accountId") (fromRef result)
        expect (eventually "persisted-state" (correlatedBy selectedCorrelation $ observe "matches" (State (fromRef result) absent) id))
        when (route == "create") $ expect (eventually "rest-state" (correlatedBy selectedCorrelation $ observe "matches" (Rest (fromRef result)) id))
      options = RunOptions "adapter-run" False "test-build" Nothing Nothing
  resolved <- either (fail . show) pure (resolveScenario environment options (localBinding httpConfig settings) scenarioValue)
  runScenario realClock (LogicalInput "adapter-recipe-v1" []) resolved

verdictIs :: Verdict -> RunResult -> Bool
verdictIs expected (Verification (VerificationResult _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ actual _ _ _)) = actual == expected
verdictIs _ _ = False

expectVerdict :: Verdict -> RunResult -> IO ()
expectVerdict expected result = unless (verdictIs expected result) (fail (show result))

roundtripTests :: TestTree
roundtripTests =
  testGroup
    "HTTP to SQL public runner"
    [ test "HTTP handler rejects an acquired endpoint descriptor mismatch" $ do
        settings <- Text.pack <$> getEnv "SHOKO_TEST_PG"
        declared <- config
        base <- Text.pack <$> getEnv "SHOKO_TEST_HTTP"
        different <- either (fail . Text.unpack) pure (Http.endpoint "create" (base <> "/noop") Http.Post 1024 Set.empty False (Just (BusinessKeyName "accountId", "id")))
        acquired <- either (fail . Text.unpack) pure (Http.httpConfig [different])
        let source = scenario "mismatch" "Descriptor ownership" "1" $ do
              key <- act "command" (accept ["created"] (Command "create" "descriptor-mismatch"))
              selectedCorrelation <- correlate (CorrelationAlias "account") (BusinessKeyName "accountId") (fromRef key)
              expect $ eventually "state" (correlatedBy selectedCorrelation $ observe "yes" (State (fromRef key) False) id)
            environment = Environment "local" False (Set.fromList [ReadState, WriteState, SendHttp]) defaultPolicy
        resolved <- either (fail . show) pure (resolveScenario environment (RunOptions "mismatch" False "fixture" Nothing Nothing) (localBindingUsing declared acquired settings) source)
        result <- runScenario realClock (LogicalInput "mismatch" []) resolved
        check (verdictIs Unknown result)
        query "descriptor-mismatch" (Pg.rowAbsent table scope Nothing) >>= check . valueIs True,
      test "invalid HTTP handler construction is retained in zero-allocation preflight" $ do
        declared <- config
        let source = scenario "not-get" "Read handler method validation" "1" $ expect $ eventually "read" (observe "yes" (Rest (pure "key")) id)
            handlers :: OperationRole -> Op a -> Either HandlerBuildError (Maybe (Handler () a))
            handlers ObservationOperation (Rest _) = Just . focus (const (error "must not execute")) <$> Http.httpObservationHandler declared "create" (const (pure (Right Http.emptyPayload))) (\_ _ -> Right True)
            handlers _ _ = Right Nothing
            selected = binding "invalid" (\_ -> fail "must not acquire") (const (pure Cleaned)) handlers
        case resolveScenario (Environment "local" False (Set.fromList [ReadState, SendHttp]) defaultPolicy) (RunOptions "invalid" False "fixture" Nothing Nothing) selected source of
          Left errors -> check (errors == [HandlerConstructionFailed "rest" (ObservationMethodNotGet "create")])
          Right _ -> fail "invalid handler accepted",
      test "real committed write yields Pass and decodable safe evidence" $ do
        settings <- Text.pack <$> getEnv "SHOKO_TEST_PG"
        result <- run "create" "created' scoped" ["created"] False settings
        check (verdictIs Pass result)
        check (decodeRunResult (encodeRunResult result) == Right result)
        -- Correlation is intentionally attributable; payload/auth values differ
        -- from that public key and must never be included through transport errors.
        check (not ("Bearer ADAPTER-SECRET-SENTINEL" `BS.isInfixOf` BL.toStrict (encodeRunResult result))),
      test "conclusive missing consequence fails and unavailable DB is Unknown" $ do
        settings <- Text.pack <$> getEnv "SHOKO_TEST_PG"
        run "noop" "missing-consequence" ["created"] False settings >>= expectVerdict Fail
        run "noop" "unavailable-source" ["created"] False "host=/tmp/shoko-no-such-socket dbname=missing connect_timeout=1" >>= expectVerdict Unknown,
      test "expected rejection Pass, unexpected success/rejection Fail" $ do
        settings <- Text.pack <$> getEnv "SHOKO_TEST_PG"
        run "invalid" "invalid-case" ["invalid-input"] True settings >>= check . verdictIs Pass
        run "noop" "unexpected-success" ["invalid-input"] True settings >>= check . verdictIs Fail
        run "different" "unexpected-rejection" ["invalid-input"] True settings >>= check . verdictIs Fail,
      test "lost HTTP transport cannot count as expected rejection" $ do
        settings <- Text.pack <$> getEnv "SHOKO_TEST_PG"
        run "closed" "lost-response" ["invalid-input"] True settings >>= check . verdictIs Unknown,
      test "undecodable response is Unknown and omits its secret body" $ do
        settings <- Text.pack <$> getEnv "SHOKO_TEST_PG"
        result <- run "undecodable" "decode-case" ["invalid-input"] True settings
        check (verdictIs Unknown result)
        check (not ("OTP-ADAPTER-SECRET-SENTINEL" `BS.isInfixOf` BL.toStrict (encodeRunResult result))),
      test "denied policy has no acquisition or HTTP traffic" $ do
        httpConfig <- config
        calls <- newIORef (0 :: Int)
        let original = localBinding httpConfig "never-open"
            guarded = requiringLifecycle [ExternalSideEffect] original
            forbidden = Environment "denied" False Set.empty defaultPolicy
            scenarioValue = scenario "denied" "denied" "1" $ do
              _ <- act "command" (accept ["created"] (Command "noop" "never"))
              selectedCorrelation <- correlate (CorrelationAlias "account") (BusinessKeyName "accountId") (pure "never")
              expect (eventually "state" (correlatedBy selectedCorrelation $ observe "yes" (State (pure "never") False) id))
        check (either (const True) (const False) (resolveScenario forbidden (RunOptions "denied" False "test" Nothing Nothing) guarded scenarioValue))
        readIORef calls >>= check . (== 0)
    ]
