module Shoko.Cli (runShokoCli, executeCli, CliRun (..), module Shoko.Cli.Registry) where

import Control.Exception (IOException, SomeAsyncException, SomeException, fromException, throwIO, try)
import Data.Aeson (encode, object, (.=))
import Data.ByteString.Lazy qualified as BL
import Data.List (nub)
import Data.Set qualified as Set
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Data.Text.IO qualified as TextIO
import GHC.Clock (getMonotonicTimeNSec)
import Options.Applicative qualified as O
import Shoko
import Shoko.Cli.Config
import Shoko.Cli.Options
import Shoko.Cli.Registry
import Shoko.Cli.Report
import Shoko.Cli.Version qualified as Version
import Shoko.Clock (realClock)
import Shoko.Prelude
import Shoko.Result
import Shoko.Result.Json
import Shoko.Scenario (Description (..), scenarioParts)
import System.Environment (getArgs)
import System.Exit (ExitCode (..), exitWith)
import System.IO (stderr)

data CliRun = CliRun {exitCode :: !Int, standardOutput :: !BL.ByteString, standardError :: !Text}
  deriving stock (Eq, Show, Generic)

failure :: Int -> Text -> CliRun
failure code message = CliRun code "" (message <> "\n")

textBytes :: Text -> BL.ByteString
textBytes = BL.fromStrict . Text.encodeUtf8

runShokoCli :: Registry -> IO ()
runShokoCli registry = do
  args <- getArgs
  CliRun code output diagnostic <- executeCli registry args
  BL.putStr output
  TextIO.hPutStr stderr diagnostic
  exitWith (if code == 0 then ExitSuccess else ExitFailure code)

executeCli :: Registry -> [String] -> IO CliRun
executeCli registry args = do
  answer <- try @SomeException $ case O.execParserPure O.defaultPrefs parserInfo args of
    O.Failure problem ->
      let (message, code) = O.renderFailure problem "shoko"
       in pure $ case code of ExitSuccess -> CliRun 0 (textBytes (Text.pack message <> "\n")) ""; _ -> failure 2 "Invalid command line. Use shoko --help or shoko COMMAND --help."
    O.CompletionInvoked _ -> pure (failure 2 "Shell completion is unsupported")
    O.Success invocation -> dispatch registry invocation
  case answer of
    Right result -> pure result
    Left exception -> case fromException exception :: Maybe SomeAsyncException of
      Just _ -> throwIO exception
      Nothing -> pure (failure 4 "Unexpected CLI fault")

dispatch :: Registry -> Invocation -> IO CliRun
dispatch (Registry environments entries) (Invocation command path overrides synthetic outputPath) =
  case traverse entryId entries of
    Left message -> pure (failure 2 message)
    Right names | length names /= length (nub names) -> pure (failure 2 "Duplicate compiled scenario ID")
    Right names -> case command of
      Unsupported -> pure (failure 2 "Observe and Replay are unsupported in bootstrap")
      List -> pure (CliRun 0 (textBytes (Text.unlines names)) "")
      _ -> case lookup (commandId command) (zip names entries) of
        Nothing -> pure (failure 2 "Unknown compiled scenario")
        Just entry -> do
          configured <- loadConfig path overrides
          case configured of
            Left message -> pure (failure 2 message)
            Right (config@(HostConfig environment _ _ _ _ target _ _), provenance)
              | environment == "production" -> pure (failure 2 "Production execution is unsupported")
              | environment `notElem` environments -> pure (failure 2 "Unsupported environment for this host")
              | not (validTarget target) -> pure (failure 2 "Expected target identity must be complete and nonempty")
              | otherwise -> executeEntry command config provenance synthetic outputPath entry
  where
    entryId (Entry source _ _ _ _) = case inspectScenario source of
      Left _ -> Left "Invalid compiled scenario definition"
      Right (Description name _ _ _ _) -> Right name
    commandId (Explain name) = name
    commandId (Check name) = name
    commandId (Run name) = name
    commandId _ = ""
    validTarget Nothing = True
    validTarget (Just (TargetIdentity name targetNamespace revision)) = all (/= "") [name, targetNamespace, revision]

executeEntry :: Command -> HostConfig -> Text -> Bool -> Maybe FilePath -> Entry -> IO CliRun
executeEntry command config@(HostConfig environment implementation format grants policy expected access redactions) provenance synthetic outputPath (Entry source correlation logical factories metadata) =
  case lookup implementation factories of
    Nothing -> pure (failure 2 "Unsupported implementation binding")
    Just factory -> do
      tick <- getMonotonicTimeNSec
      let runId = "run-" <> Text.pack (show tick)
          options = RunOptions runId synthetic Version.buildIdentity Nothing Nothing
          targetEnvironment = Environment environment False (Set.fromList grants) policy
          inspectBinding (SomeBinding binding@(Binding _ _ contract _ _ _ _ _)) = case resolveScenario targetEnvironment options correlation binding source of
            Left errors -> Left errors
            Right resolved ->
              let (_, _, _, _, _, _, _, report) = resolvedParts resolved
                  sources = case scenarioParts source of
                    Left _ -> []
                    Right (_, _, expectations) ->
                      [ (operationId, sourceName, strength)
                      | Expectation _ _ _ observation <- expectations,
                        let operation = observationOperation observation,
                        let OperationInfo operationId _ _ _ = describeOperation operation,
                        Just (BindingContract _ _ _ sourceName strength) <- [contract ObservationOperation operation]
                      ]
               in Right (report, sources)
          checked = inspectBinding (factory config Nothing)
      case command of
        Explain _ -> case inspectScenario source of
          Left _ -> pure (failure 2 "Invalid compiled scenario definition")
          Right description ->
            pure
              ( CliRun
                  (either (const 2) (const 0) checked)
                  ( if format == "json"
                      then
                        encode
                          ( object
                              [ "description" .= descriptionValue description,
                                "configuration" .= provenance,
                                "binding" .= implementation,
                                "environment" .= environment,
                                "policy" .= Text.pack (show policy),
                                "required" .= either (Text.pack . show) (Text.pack . show) checked
                              ]
                          )
                          <> "\n"
                      else textBytes ("Scenario " <> scenarioName description <> "\nBinding " <> implementation <> "\n" <> Text.pack (show policy) <> "\n" <> provenance <> "\n" <> either (Text.pack . show) (\report -> Text.pack (show report) <> "\nPolicy supported; live readiness unchecked") checked <> "\n")
                  )
                  ""
              )
        Check _ -> pure $ case checked of
          Left errors -> resultRun format (PreflightFailure errors)
          Right _ -> CliRun 0 (if format == "json" then "{\"kind\":\"policy-check\",\"valid\":true,\"liveReadinessChecked\":false}\n" else "Configuration and policy valid; live readiness unchecked\n") ""
        Run _ -> case checked of
          Left errors -> pure (resultRun format (PreflightFailure errors))
          Right _ -> do
            secrets <- resolveCredentials access
            case secrets of
              Left message -> pure (failure 2 message)
              Right credentials -> do
                identity <- metadata config
                case identity of
                  Left _ -> pure (failure 2 "Host target metadata preflight failed")
                  Right (_, targetIdentity) | maybe False (\expectedIdentity -> Just expectedIdentity /= targetIdentity) expected -> pure (failure 2 "Observed host target does not match the configured expectation")
                  Right (implementationIdentity, targetIdentity) -> case factory config (Just credentials) of
                    SomeBinding binding -> case resolveScenario targetEnvironment (RunOptions runId synthetic Version.buildIdentity implementationIdentity targetIdentity) correlation binding source of
                      Left errors -> pure (resultRun format (PreflightFailure errors))
                      Right resolved -> do
                        result <- redactResult redactions <$> runScenario realClock logical resolved
                        let rendered@(CliRun _ stdout _) = resultRun format result
                        persisted <- try @IOException $ maybe (pure ()) (`persistResult` result) outputPath
                        pure $ case persisted of
                          Right () -> rendered
                          Left _ -> CliRun 4 stdout "Could not persist evidence; result preserved on stdout and existing output left intact\n"
        _ -> pure (failure 2 "Unsupported command")
  where
    scenarioName (Description name _ _ _ _) = name

resultRun :: Text -> RunResult -> CliRun
resultRun format result = CliRun (resultExit result) (if format == "json" then encodeRunResult result <> "\n" else textBytes (renderText result)) ""
