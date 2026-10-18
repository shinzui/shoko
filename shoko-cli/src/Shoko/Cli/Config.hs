module Shoko.Cli.Config
  ( HostConfig (..),
    Access (..),
    Credentials,
    credential,
    declaration,
    configKeys,
    loadConfig,
    resolveCredentials,
    key,
  )
where

import Data.Char (isAsciiLower, isAsciiUpper)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes)
import Data.Set qualified as Set
import Data.Text qualified as Text
import Settei qualified as S
import Settei.Env qualified as E
import Settei.Yaml qualified as Y
import Shoko.Environment
import Shoko.Prelude
import System.Environment (lookupEnv)

-- | Values here are configuration and credential references, never secrets.
data Access = Access
  {endpointEnv :: !(Maybe Text), connectionEnv :: !(Maybe Text), tokenEnv :: !(Maybe Text)}
  deriving stock (Eq, Show, Generic)

data HostConfig = HostConfig
  { environmentName :: !Text,
    implementationName :: !Text,
    outputFormat :: !Text,
    grants :: ![Capability],
    policy :: !Policy,
    expectedTarget :: !(Maybe TargetIdentity),
    access :: !Access,
    extraRedactions :: ![Text]
  }
  deriving stock (Eq, Show, Generic)

newtype Credentials = Credentials (Map Text Text)

credential :: Text -> Credentials -> Either Text Text
credential name (Credentials values) = maybe (Left "undeclared-credential-reference") Right (Map.lookup name values)

key :: Text -> S.Key
key = either (error . show) id . S.parseKey

public :: Text -> S.Decoder a -> S.Setting a
public name = S.publicSetting (key name) name

defaulted :: Text -> S.Decoder a -> a -> S.Config a
defaulted name decoder value = S.withDefault (public name decoder) (S.constantDefault (S.RuleName (name <> ".default")) "Local-only host default" value)

duration :: S.Decoder Duration
duration = S.decoder $ \owner raw -> do
  value <- S.runDecoder S.boundedIntegralDecoder owner raw
  either (const (Left (S.decodeFailure owner "positive milliseconds"))) Right (milliseconds value)

envName :: S.Decoder Text
envName = S.parsedDecoder "portable environment-variable name" $ \name ->
  case Text.uncons name of
    Just (first, _) | (isAsciiUpper first || isAsciiLower first || first == '_') && Text.all (\c -> isAsciiUpper c || isAsciiLower c || (c >= '0' && c <= '9') || c == '_') name -> Right name
    _ -> Left "invalid"

capabilityDecoder :: S.Decoder Capability
capabilityDecoder = S.enumDecoder [("ReadState", ReadState), ("ReadEvents", ReadEvents), ("WriteState", WriteState), ("SendHttp", SendHttp), ("ExternalSideEffect", ExternalSideEffect), ("SyntheticResource", SyntheticResource)]

declaration :: S.Config HostConfig
declaration =
  assemble
    <$> defaulted "runtime.environment" S.textDecoder "local"
    <*> defaulted "runtime.implementation" S.textDecoder "demo"
    <*> defaulted "output.format" (S.enumDecoder [("text", "text"), ("json", "json")]) "text"
    <*> defaulted "policy.capabilities" (S.listDecoder capabilityDecoder) [ReadState, WriteState]
    <*> ( Policy
            <$> defaulted "policy.executionMs" duration (durationDefault 30000)
            <*> defaulted "policy.eventuallyMs" duration (durationDefault 10000)
            <*> defaulted "policy.pollMs" duration (durationDefault 100)
            <*> defaulted "policy.cleanupMs" duration (durationDefault 5000)
        )
    <*> S.optional (public "target.name" S.textDecoder)
    <*> S.optional (public "target.namespaceUid" S.textDecoder)
    <*> S.optional (public "target.deploymentRevision" S.textDecoder)
    <*> ( Access
            <$> S.optional (public "access.endpointEnv" envName)
            <*> S.optional (public "access.connectionEnv" envName)
            <*> S.optional (public "access.tokenEnv" envName)
        )
    <*> defaulted "redaction.extraFields" (S.listDecoder S.textDecoder) []
  where
    durationDefault = either (error . Text.unpack) id . milliseconds
    assemble env impl format capabilities policy name namespace revision access redactions =
      HostConfig
        env
        impl
        format
        capabilities
        policy
        ( case (name, namespace, revision) of
            (Nothing, Nothing, Nothing) -> Nothing
            _ -> Just (TargetIdentity (maybe "" id name) (maybe "" id namespace) (maybe "" id revision))
        )
        access
        redactions

configKeys :: [Text]
configKeys = map (S.renderKey . S.schemaSettingKey) (S.schemaPossible (S.describe declaration))

operational :: [(Text, Text)]
operational = [("SHOKO_ENVIRONMENT", "runtime.environment"), ("SHOKO_IMPLEMENTATION", "runtime.implementation"), ("SHOKO_FORMAT", "output.format"), ("SHOKO_EXECUTION_MS", "policy.executionMs"), ("SHOKO_EVENTUALLY_MS", "policy.eventuallyMs"), ("SHOKO_POLL_MS", "policy.pollMs"), ("SHOKO_CLEANUP_MS", "policy.cleanupMs")]

-- | Only operational names are looked up during inspection. Credential values
-- are resolved in a separate Secret declaration immediately before a live run.
loadConfig :: Maybe FilePath -> [S.Source] -> IO (Either Text (HostConfig, Text))
loadConfig path overrides = do
  snapshot <- E.envSnapshot . catMaybes <$> traverse (\(name, _) -> fmap ((name,) . Text.pack) <$> lookupEnv (Text.unpack name)) operational
  file <- case path of
    Nothing -> pure (Right [])
    Just filename -> fmap pure <$> Y.readYamlSource (Y.withYamlSourcePath filename (Y.yamlSourceOptions "explicit config")) filename
  let bindings = either (error . Text.unpack . E.renderEnvErrorsText) id (E.bindings [E.binding (E.EnvName name) (key setting) | (name, setting) <- operational])
  pure $ case file of
    Left errors -> Left (Y.renderYamlErrorsText errors)
    Right files -> case S.resolve (S.ResolveOptions S.RejectUnknownKeys) (files ++ [E.environmentSource bindings snapshot] ++ overrides) declaration of
      S.ResolveResult (Left errors) _ _ -> Left (S.renderErrorsText errors)
      S.ResolveResult (Right config) report _ -> Right (config, S.renderResolutionText report)

resolveCredentials :: Access -> IO (Either Text Credentials)
resolveCredentials (Access endpoint connection token) = do
  let names = Set.toAscList (Set.fromList (catMaybes [endpoint, connection, token]))
  pairs <- catMaybes <$> traverse (\name -> fmap ((name,) . Text.pack) <$> lookupEnv (Text.unpack name)) names
  let bindings = either (error . Text.unpack . E.renderEnvErrorsText) id (E.bindings [E.binding (E.EnvName name) (key ("credentials." <> name)) | name <- names])
      required name = (name,) <$> S.required (S.secretSetting (key ("credentials." <> name)) "live credential reference" (S.parsedDecoder "nonempty credential" (\value -> if value == "" then Left "empty" else Right value)))
      result = S.resolve (S.ResolveOptions S.RejectUnknownKeys) [E.environmentSource bindings (E.envSnapshot pairs)] (traverse required names)
  pure $ case result of
    S.ResolveResult (Left errors) _ _ -> Left (S.renderErrorsText errors)
    S.ResolveResult (Right values) _ _ -> Right (Credentials (Map.fromList values))
