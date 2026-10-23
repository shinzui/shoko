module EmailSmoke.Config
  ( Config (..),
    PrivateValues (..),
    declaration,
    loadConfig,
    resolveSources,
    resolvePrivate,
    resolvePrivateWith,
    descriptors,
    operational,
  )
where

import Data.Char (isAsciiLower, isAsciiUpper)
import Data.Maybe (catMaybes)
import Data.Text (Text)
import Data.Text qualified as T
import Settei qualified as S
import Settei.Env qualified as E
import Settei.Yaml qualified as Y
import Shoko
import Shoko.Adapter.Email qualified as Mail
import Shoko.Adapter.Email.Resend qualified as Resend
import System.Environment (lookupEnv)

-- Private values are kept out of operational configuration and provenance.
data PrivateValues = PrivateValues !Resend.ResendCredentials !Text !(Maybe Mail.Address)

data Config = Config
  { sourceLabel :: !Text,
    accountLabel :: !Text,
    recipientPrefix :: !Text,
    limits :: !Mail.EmailLimits,
    policy :: !Policy,
    apiKeyEnv :: !Text,
    domainEnv :: !Text,
    senderEnv :: !Text
  }
  deriving stock (Eq, Show)

key :: Text -> S.Key
key = either (error . show) id . S.parseKey

public :: Text -> S.Decoder a -> S.Setting a
public name = S.publicSetting (key name) name

setting :: Text -> S.Decoder a -> a -> S.Config a
setting name decoder value = S.withDefault (public name decoder) (S.constantDefault (S.RuleName (name <> ".default")) "Bounded email smoke default" value)

ms :: Int -> Duration
ms = either (error . T.unpack) id . milliseconds

positive :: S.Decoder Int
positive = S.decoder $ \owner raw -> do
  n <- S.runDecoder S.boundedIntegralDecoder owner raw
  if n > 0 then Right n else Left (S.decodeFailure owner "positive integer")

duration :: S.Decoder Duration
duration = S.decoder $ \owner raw -> do
  n <- S.runDecoder positive owner raw
  either (const (Left (S.decodeFailure owner "positive milliseconds"))) Right (milliseconds n)

reference :: S.Decoder Text
reference = S.parsedDecoder "portable environment-variable reference" $ \name ->
  case T.uncons name of
    Just (first, _) | letter first || first == '_', T.all (\c -> letter c || c >= '0' && c <= '9' || c == '_') name -> Right name
    _ -> Left "invalid"
  where
    letter c = isAsciiLower c || isAsciiUpper c

declaration :: S.Config Config
declaration =
  (\_ -> Config)
    <$> setting "provider" (S.enumDecoder [("resend", ())]) ()
    <*> setting "source" S.textDecoder "email"
    <*> setting "account" S.textDecoder "approved-test-account"
    <*> setting "recipient.prefix" S.textDecoder "shoko-"
    <*> ( Mail.EmailLimits
            <$> setting "bounds.pageSize" positive 100
            <*> setting "bounds.maxPages" positive 10
            <*> setting "bounds.maxDetails" positive 20
            <*> setting "bounds.responseBytes" positive 262144
            <*> setting "bounds.scanBytes" positive 2097152
            <*> setting "bounds.payloadBytes" positive 65536
            <*> setting "bounds.requestMs" duration (ms 3000)
            <*> setting "bounds.scanMs" duration (ms 5000)
        )
    <*> ( Policy
            <$> setting "policy.executionMs" duration (ms 30000)
            <*> setting "policy.receiptMs" duration (ms 20000)
            <*> setting "policy.pollMs" duration (ms 1000)
            <*> pure (ms 1000)
        )
    <*> setting "access.apiKeyEnv" reference "SHOKO_EMAIL_RESEND_API_KEY"
    <*> setting "access.domainEnv" reference "SHOKO_EMAIL_RECEIVING_DOMAIN"
    <*> setting "access.senderEnv" reference "SHOKO_EMAIL_SENDER"

operational :: [(Text, Text)]
operational =
  [ ("SHOKO_EMAIL_PAGE_SIZE", "bounds.pageSize"),
    ("SHOKO_EMAIL_MAX_PAGES", "bounds.maxPages"),
    ("SHOKO_EMAIL_MAX_DETAILS", "bounds.maxDetails"),
    ("SHOKO_EMAIL_RESPONSE_BYTES", "bounds.responseBytes"),
    ("SHOKO_EMAIL_SCAN_BYTES", "bounds.scanBytes"),
    ("SHOKO_EMAIL_PAYLOAD_BYTES", "bounds.payloadBytes"),
    ("SHOKO_EMAIL_REQUEST_MS", "bounds.requestMs"),
    ("SHOKO_EMAIL_SCAN_MS", "bounds.scanMs"),
    ("SHOKO_EMAIL_EXECUTION_MS", "policy.executionMs"),
    ("SHOKO_EMAIL_RECEIPT_MS", "policy.receiptMs"),
    ("SHOKO_EMAIL_POLL_MS", "policy.pollMs")
  ]

resolveSources :: [S.Source] -> Either Text (Config, Text)
resolveSources sources = case S.resolve (S.ResolveOptions S.RejectUnknownKeys) sources declaration of
  S.ResolveResult (Left _) _ _ -> Left "email-configuration-invalid"
  S.ResolveResult (Right config) report _ -> do
    let Config {limits = bounds, policy = budgets} = config
        Policy execution receipt poll _ = budgets
    if Mail.requestLimit bounds > receipt || Mail.scanLimit bounds > execution || receipt >= execution || poll > receipt
      then Left "email-configuration-invalid"
      else pure ()
    -- Validate all pure descriptor fields without resolving the private domain.
    _ <- descriptors config "approved.invalid" Nothing
    Right (config, S.renderResolutionText report)

loadConfig :: Maybe FilePath -> IO (Either Text (Config, Text))
loadConfig path = do
  snapshot <- E.envSnapshot . catMaybes <$> traverse (\(name, _) -> fmap ((name,) . T.pack) <$> lookupEnv (T.unpack name)) operational
  file <- case path of
    Nothing -> pure (Right [])
    Just filename -> fmap pure <$> Y.readYamlSource (Y.withYamlSourcePath filename (Y.yamlSourceOptions "explicit email config")) filename
  let bindings = either (error . T.unpack . E.renderEnvErrorsText) id (E.bindings [E.binding (E.EnvName name) (key target) | (name, target) <- operational])
  pure $ case file of
    Left _ -> Left "email-configuration-invalid"
    Right files -> resolveSources (files ++ [E.environmentSource bindings snapshot])

-- An injectable lookup makes zero credential reads during inspection/denial observable.
resolvePrivateWith :: (String -> IO (Maybe String)) -> Bool -> Config -> IO (Either Text PrivateValues)
resolvePrivateWith lookupValue sending config = do
  let refs = [("apiKey", apiKeyEnv config), ("domain", domainEnv config)] ++ [("sender", senderEnv config) | sending]
      bindings = either (error . T.unpack . E.renderEnvErrorsText) id (E.bindings [E.binding (E.EnvName name) (key ("private." <> label)) | (label, name) <- refs])
      required label = S.required (S.secretSetting (key ("private." <> label)) "private email input" (S.parsedDecoder "nonempty private input" (\value -> if T.null value then Left "empty" else Right value)))
      privateDeclaration = (,,) <$> required "apiKey" <*> required "domain" <*> (if sending then Just <$> required "sender" else pure Nothing)
  values <- catMaybes <$> traverse (\(_, name) -> fmap ((name,) . T.pack) <$> lookupValue (T.unpack name)) refs
  pure $ case S.resolve (S.ResolveOptions S.RejectUnknownKeys) [E.environmentSource bindings (E.envSnapshot values)] privateDeclaration of
    S.ResolveResult (Left _) _ _ -> Left "email-private-inputs-unavailable"
    S.ResolveResult (Right (apiKey, domain, sender)) _ _ -> do
      credential <- either (const (Left "email-private-inputs-unavailable")) Right (Resend.resendCredentials apiKey)
      senderAddress <- either (const (Left "email-private-inputs-unavailable")) Right (traverse Mail.address sender)
      _ <- either (const (Left "email-private-inputs-unavailable")) Right (descriptors config domain senderAddress)
      Right (PrivateValues credential domain senderAddress)

resolvePrivate :: Bool -> Config -> IO (Either Text PrivateValues)
resolvePrivate = resolvePrivateWith lookupEnv

descriptors :: Config -> Text -> Maybe Mail.Address -> Either Text (Mail.Inbox, Maybe (Mail.SendDescriptor, Mail.Address))
descriptors config domain sender = do
  selected <- Mail.inbox (SourceId (sourceLabel config)) (accountLabel config) (BusinessKeyName "testMailboxId") domain (recipientPrefix config) (limits config)
  send <- traverse (\value -> (,value) <$> Mail.sendDescriptor selected [value]) sender
  Right (selected, send)
