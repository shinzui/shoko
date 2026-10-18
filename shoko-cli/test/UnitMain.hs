module Main (main) where

import Control.Monad (unless)
import Data.Text qualified as Text
import Options.Applicative qualified as O
import Settei qualified as S
import Settei.Env qualified as E
import Settei.Optparse (namedOption)
import Settei.Yaml qualified as Y
import Shoko.Cli.Config

main :: IO ()
main = do
  yaml <-
    either
      (fail . Text.unpack . Y.renderYamlErrorsText)
      pure
      (Y.decodeYamlSource (Y.yamlSourceOptions "test-yaml") "runtime:\n  environment: yaml-env\noutput:\n  format: text\n")
  bindings <-
    either
      (fail . Text.unpack . E.renderEnvErrorsText)
      pure
      (E.bindings [E.binding (E.EnvName "TEST_ENVIRONMENT") (key "runtime.environment")])
  let injected = E.environmentSource bindings (E.envSnapshot [("TEST_ENVIRONMENT", "env-env")])
      parser = O.info (namedOption "--environment" (key "runtime.environment") (O.long "environment")) mempty
  override <- case O.execParserPure O.defaultPrefs parser ["--environment", "cli-env"] of
    O.Success (Just source) -> pure source
    _ -> fail "named configuration option did not parse"
  let resolved = S.resolve (S.ResolveOptions S.RejectUnknownKeys) [yaml, injected, override] declaration
  case resolved of
    S.ResolveResult (Right (HostConfig environment _ _ _ _ _ _ _)) report _ -> do
      unless (environment == "cli-env") (fail "source precedence changed")
      let explanation = S.renderResolutionText report
      unless (all (`Text.isInfixOf` explanation) ["test-yaml", "TEST_ENVIRONMENT", "--environment"]) (fail "winning/shadowed origins lost")
    _ -> fail "layered configuration failed"
  empty <-
    either
      (fail . Text.unpack . Y.renderYamlErrorsText)
      pure
      (Y.decodeYamlSource (Y.yamlSourceOptions "empty") "policy:\n  executionMs: 0\n")
  case S.resolve (S.ResolveOptions S.RejectUnknownKeys) [yaml, empty] declaration of
    S.ResolveResult (Left _) _ _ -> pure ()
    _ -> fail "invalid winning duration fell back"
  -- Missing differs from an explicitly empty environment value.
  case S.resolve (S.ResolveOptions S.RejectUnknownKeys) [E.environmentSource bindings (E.envSnapshot [("TEST_ENVIRONMENT", "")])] declaration of
    S.ResolveResult (Right (HostConfig "" _ _ _ _ _ _ _)) _ _ -> pure ()
    _ -> fail "empty environment candidate became absent"
  putStrLn "Settei YAML, injected environment, named CLI, provenance, and invalid-winner checks passed."
