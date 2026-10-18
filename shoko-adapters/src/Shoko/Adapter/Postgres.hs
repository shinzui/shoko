{-# LANGUAGE MultilineStrings #-}

module Shoko.Adapter.Postgres
  ( Postgres,
    postgres,
    postgresContract,
    postgresBaseline,
    runQuery,
    observeQuery,
    module Shoko.Adapter.Postgres.Query,
    module Shoko.Adapter.Postgres.Evidence,
  )
where

import Control.Exception (bracket)
import Data.Set qualified as Set
import Data.Text qualified as Text
import Hasql.Connection qualified as Connection
import Hasql.Connection.Settings qualified as Settings
import Hasql.Decoders qualified as D
import Hasql.Encoders qualified as E
import Hasql.Errors qualified as Errors
import Hasql.Session qualified as Session
import Hasql.Statement (unpreparable)
import PostgresqlConnectionString qualified as ConnectionString
import Shoko.Adapter.Postgres.Evidence
import Shoko.Adapter.Postgres.Query
import Shoko.Binding
import Shoko.Clock
import Shoko.Correlation (CorrelationStrategy (BusinessKey))
import Shoko.Environment (Capability (ReadState))
import Shoko.Observation
import Shoko.Prelude

-- | Contains a credential, deliberately without Show or JSON instances.
data Postgres = Postgres !Text

postgres :: Text -> Postgres
postgres = Postgres

postgresContract :: Text -> BindingContract
postgresContract source = BindingContract (Set.singleton ReadState) Set.empty (Set.singleton BusinessKey) (Just source) SampledState

postgresBaseline :: Clock -> Text -> IO (Either Text Baseline)
postgresBaseline (Clock now _ _ _) source = do
  tick <- now
  pure (Right (Baseline source tick Nothing))

runQuery :: CallContext -> Postgres -> Query a -> IO (Either PostgresFailure (a, Sample))
runQuery (CallContext _ end _ selected _ _ (Clock now _ _ bound)) (Postgres settings) query =
  case selected >>= either (const Nothing) Just . (`compileQuery` query) of
    Nothing -> pure (Left CorrelationUnavailable)
    Just _ | Text.null (Text.strip settings) -> pure (Left ConnectionUnavailable)
    Just _ | Left _ <- ConnectionString.parse settings -> pure (Left ConnectionUnavailable)
    Just statement -> do
      started <- now
      if started >= end
        then pure (Left DeadlineExpired)
        else do
          result <-
            bound end $
              bracket
                (Connection.acquire (Settings.connectionString settings))
                (either (const (pure ())) Connection.release)
                ( \case
                    Left _ -> pure (Left ConnectionUnavailable)
                    Right connection -> do
                      -- New connection per sample: no sibling can interleave statements
                      -- inside this read-only transaction. The connection is discarded
                      -- on every error/cancellation, so an aborted transaction is safe.
                      current <- now
                      let remainingMs = max 1 ((end - current) `div` 1000)
                      answer <-
                        Connection.use
                          connection
                          ( do
                              Session.script "BEGIN READ ONLY"
                              _ <- Session.statement (Text.pack (show remainingMs)) timeoutStatement
                              value <- Session.statement () statement
                              Session.script "COMMIT"
                              pure value
                          )
                      pure (either (Left . classifyError) Right answer)
                )
          finished <- now
          pure $ case result of
            Nothing -> Left DeadlineExpired
            Just answer -> (\value -> (value, Sample started finished (queryDescription query))) <$> answer
  where
    timeoutStatement =
      unpreparable
        """
        SELECT set_config('statement_timeout', $1, true)
        """
        (E.param (E.nonNullable E.text))
        (D.singleRow (D.column (D.nonNullable D.text)))

classifyError :: Errors.SessionError -> PostgresFailure
classifyError (Errors.ConnectionSessionError _) = ConnectionUnavailable
classifyError (Errors.ScriptSessionError _ server) = classifyServer server
classifyError (Errors.StatementSessionError _ _ _ _ _ err) = case err of
  Errors.ServerStatementError server -> classifyServer server
  _ -> DecodeUnavailable
classifyError _ = QueryUnavailable

classifyServer :: Errors.ServerError -> PostgresFailure
classifyServer (Errors.ServerError code _ _ _ _) = case code of
  "42501" -> PermissionDenied
  "57014" -> DeadlineExpired
  _ -> QueryUnavailable

observeQuery :: CallContext -> Postgres -> Query a -> IO (ObservationOutcome a)
observeQuery context resource query =
  runQuery context resource query >>= \case
    Left failure -> pure (ObservationUnavailable (failureCode failure))
    Right (value, Sample started finished description) ->
      pure
        ( ObservedWithDetails
            [Occurrence Nothing value]
            (Coverage SampledState started finished True)
            ([("query", PublicChoice description), ("sample-count", PublicCount 1)] ++ queryDetails query value)
        )
