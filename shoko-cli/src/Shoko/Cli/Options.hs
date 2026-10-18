module Shoko.Cli.Options (Command (..), Invocation (..), parserInfo) where

import Control.Applicative (optional)
import Data.Maybe (catMaybes)
import Data.Text qualified as Text
import Options.Applicative ((<**>))
import Options.Applicative qualified as O
import Settei (Source)
import Settei.Optparse (namedOption)
import Shoko.Cli.Config (key)
import Shoko.Cli.Version (buildIdentity)
import Shoko.Prelude

data Command = List | Explain !Text | Check !Text | Run !Text | Unsupported

data Invocation = Invocation !Command !(Maybe FilePath) ![Source] !Bool !(Maybe FilePath)

parserInfo :: O.ParserInfo Invocation
parserInfo =
  O.info
    (commands <**> O.helper <**> O.infoOption (Text.unpack buildIdentity) (O.long "version" <> O.help "Show binary version, source revision, and build dirtiness"))
    (O.fullDesc <> O.progDesc "Inspect compiled scenarios or run bounded verification against an approved binding" <> O.failureCode 2)
  where
    commands =
      O.hsubparser
        ( O.command "list" (O.info (pure (Invocation List Nothing [] False Nothing) <**> O.helper) (O.progDesc "List compiled scenarios; no resources are acquired"))
            <> O.command "explain" (sub Explain "Explain description, binding policy, and configuration origins without effects")
            <> O.command "check" (sub Check "Validate configuration and policy; does not check live target readiness")
            <> O.command "run" (sub Run "Execute once; return 0 Pass, 1 Fail, 2 preflight, 3 Unknown, 4 command fault")
            <> O.command "observe" (O.info (pure (Invocation Unsupported Nothing [] False Nothing)) (O.progDesc "Unsupported in bootstrap"))
            <> O.command "replay" (O.info (pure (Invocation Unsupported Nothing [] False Nothing)) (O.progDesc "Unsupported in bootstrap"))
        )
    sub constructor description = O.info (invocation constructor <**> O.helper) (O.progDesc description)
    invocation constructor =
      Invocation
        <$> (constructor <$> O.strArgument (O.metavar "SCENARIO"))
        <*> optional (O.strOption (O.long "config" <> O.metavar "YAML" <> O.help "One explicit strict YAML file; no ambient discovery"))
        <*> ( catMaybes
                <$> sequenceA
                  [ namedOption "--environment" (key "runtime.environment") (O.long "environment" <> O.metavar "NAME" <> O.help "Named environment; cannot enlarge capability grants"),
                    namedOption "--implementation" (key "runtime.implementation") (O.long "implementation" <> O.metavar "NAME" <> O.help "Compiled implementation binding"),
                    namedOption "--format" (key "output.format") (O.long "format" <> O.metavar "text|json" <> O.help "Result rendering format")
                  ]
            )
        <*> O.switch (O.long "allow-synthetic" <> O.help "Per-run consent; also requires the configured SyntheticResource grant")
        <*> optional (O.strOption (O.long "output" <> O.metavar "PATH" <> O.help "Atomically create a new JSON evidence file; existing files are never replaced"))
