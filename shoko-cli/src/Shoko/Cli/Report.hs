module Shoko.Cli.Report (resultExit, renderText, persistResult, redactResult) where

import Control.Exception (IOException, bracketOnError, catch, onException)
import Data.ByteString.Lazy qualified as BL
import Data.Text qualified as Text
import Shoko.Evidence
import Shoko.Identifier (sourceIdText)
import Shoko.Prelude
import Shoko.Result
import Shoko.Result.Json
import System.Directory (removeFile)
import System.FilePath (takeDirectory)
import System.IO (hClose, hFlush, openBinaryTempFile)
import System.Posix.Files (createLink)

resultExit :: RunResult -> Int
resultExit (PreflightFailure _) = 2
resultExit (RunnerFault _ _) = 4
resultExit (Verification (VerificationResult _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ verdict _ _ _)) = case verdict of Pass -> 0; Fail -> 1; Unknown -> 3

renderText :: RunResult -> Text
renderText (PreflightFailure errors) = "Preflight error\n" <> Text.pack (show errors) <> "\n"
renderText (RunnerFault reason partial) = "Runner fault: " <> Text.pack (show reason) <> "\n" <> maybe "" (renderText . Verification) partial
renderText (Verification (VerificationResult _ _ runId environment binding _ _ _ _ correlation _ _ _ _ _ verdict actions expectations cleanup)) =
  Text.unlines
    ( [ Text.pack (show verdict),
        "run: " <> runId,
        "environment: " <> environment,
        "binding: " <> binding,
        "correlation: " <> Text.pack (show correlation)
      ]
        ++ map actionLine actions
        ++ map expectationLine expectations
        ++ ["disposition: " <> Text.pack (show cleanup)]
    )
  where
    actionLine (ActionEvidence node operation expected observed _ _ reason _ _) =
      node
        <> ": "
        <> operation
        <> "; observed="
        <> Text.pack (show observed)
        <> "; expected="
        <> Text.pack (show expected)
        <> "; reason="
        <> Text.pack (show reason)
    expectationLine (ExpectationResult name outcome reason (Evidence source _ baseline activation finished coverage _ count gaps cutoff _)) =
      name
        <> ": "
        <> Text.pack (show outcome)
        <> " "
        <> Text.pack (show reason)
        <> "; source="
        <> sourceIdText source
        <> "; activation="
        <> Text.pack (show activation)
        <> "; finished="
        <> Text.pack (show finished)
        <> "; cutoff="
        <> Text.pack (show cutoff)
        <> "; baseline="
        <> Text.pack (show baseline)
        <> "; coverage="
        <> Text.pack (show coverage)
        <> "; matches="
        <> Text.pack (show count)
        <> "; gaps="
        <> Text.pack (show gaps)

-- | Write all bytes before atomically linking the completed inode into place.
-- createLink fails if another run already owns the target, including races.
persistResult :: FilePath -> RunResult -> IO ()
persistResult path result =
  bracketOnError
    (openBinaryTempFile (takeDirectory path) ".shoko-result.tmp")
    (\(temporary, handle) -> ignore (hClose handle) >> ignore (removeFile temporary))
    ( \(temporary, handle) -> do
        BL.hPut handle (encodeRunResult result)
        hFlush handle
        hClose handle
        (createLink temporary path >> removeFile temporary) `onException` ignore (removeFile temporary)
    )
  where
    ignore action = catch action (\(_ :: IOException) -> pure ())

-- | Extra host redactions can only remove explicitly public summaries. Raw
-- transport/domain values never enter these result records in the first place.
redactResult :: [Text] -> RunResult -> RunResult
redactResult fields result = case result of
  Verification report -> Verification (redactReport report)
  RunnerFault reason partial -> RunnerFault reason (redactReport <$> partial)
  other -> other
  where
    keep = filter (\(name, _) -> name `notElem` fields)
    redactReport (VerificationResult description digest runId environment binding build implementation target (LogicalInput recipe parameters) correlation policy started finished executionStart deadline verdict actions expectations disposition) =
      VerificationResult description digest runId environment binding build implementation target (LogicalInput recipe (keep parameters)) correlation policy started finished executionStart deadline verdict (map redactAction actions) (map redactExpectation expectations) disposition
    redactAction (ActionEvidence node operation outcomes observed start end reason substeps details) = ActionEvidence node operation outcomes observed start end reason substeps (keep details)
    redactExpectation (ExpectationResult name verdict reason (Evidence source operation baseline activation finished coverage identities count gaps cutoff details)) =
      ExpectationResult name verdict reason (Evidence source operation baseline activation finished coverage identities count gaps cutoff (keep details))
