module Shoko.Cli.Report (resultExit, renderText, renderDescription, persistResult, redactResult) where

import Control.Exception (IOException, bracketOnError, catch, onException)
import Data.ByteString.Lazy qualified as BL
import Data.Text qualified as Text
import Shoko.Action (OperationInfo (..))
import Shoko.Correlation
import Shoko.Evidence
import Shoko.Identifier
import Shoko.Prelude
import Shoko.Result
import Shoko.Result.Json
import Shoko.Scenario (CorrelationDescription (..), Description (..), ExpectationDescription (..), ExpectationSubject (..), NodeDescription (..))
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
renderText (Verification (VerificationResult description _ runId environment binding _ _ _ _ correlations _ _ _ _ _ verdict actions expectations cleanup)) =
  Text.unlines
    ( [ Text.pack (show verdict),
        "run: " <> runId,
        "environment: " <> environment,
        "binding: " <> binding
      ]
        ++ map resolvedLine correlations
        ++ map actionLine actions
        ++ map expectationLine expectations
        ++ ["disposition: " <> Text.pack (show cleanup)]
    )
  where
    resolvedLine (ResolvedCorrelation identity value) =
      "correlation: " <> correlationIdText identity <> case value of
        ByBusinessKey key selected -> "; key=" <> businessKeyNameText key <> "; value=" <> selected
        ByExecutionId selected -> "; strategy=execution-id; value=" <> selected
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
    expectationLine (ExpectationResult name outcome reason (ObservationEvidence (Evidence source _ baseline activation finished coverage _ count gaps cutoff _))) =
      name
        <> ": "
        <> Text.pack (show outcome)
        <> " "
        <> Text.pack (show reason)
        <> "; correlation="
        <> selectedFor description name
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
    expectationLine (ExpectationResult name outcome reason (ResultEvidence (ResultCheckEvidence dependencies completed))) =
      name <> ": " <> Text.pack (show outcome) <> " " <> Text.pack (show reason) <> "; from=" <> Text.intercalate "," dependencies <> "; evaluatedAt=" <> Text.pack (show completed)

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
    redactExpectation (ExpectationResult name verdict reason (ObservationEvidence (Evidence source operation baseline activation finished coverage identities count gaps cutoff details))) =
      ExpectationResult name verdict reason (ObservationEvidence (Evidence source operation baseline activation finished coverage identities count gaps cutoff (keep details)))
    redactExpectation child@ExpectationResult {evidence = ResultEvidence _} = child

selectedFor :: Description -> Text -> Text
selectedFor (Description _ _ _ _ expectations _) key = case [selected | ExpectationDescription identity _ _ _ _ selected <- expectations, identity == key] of
  Just selected : _ -> correlationIdText selected
  _ -> "unselected"

renderDescription :: Description -> Text
renderDescription description@(Description key title revision nodes expectations correlations) =
  Text.unlines
    ( ["Scenario " <> key <> " (" <> revision <> ")", title]
        ++ ["node " <> identity <> ": " <> operation <> maybe "" ("; concurrentGroup=" <>) group | NodeDescription identity _ (OperationInfo operation _ _ _) _ group <- nodes]
        ++ ["correlation " <> correlationIdText identity <> ": key=" <> businessKeyNameText semantic <> "; strategy=" <> Text.pack (show strategy) | CorrelationDescription identity semantic strategy _ <- correlations]
        ++ map expectationLine expectations
    )
  where
    expectationLine (ExpectationDescription identity _ _ (ResultSubject dependencies) predicate _) = identity <> " immediately " <> predicate <> " from " <> Text.intercalate "," dependencies
    expectationLine (ExpectationDescription identity _ _ (ObservationSubject _) _ _) = "expectation " <> identity <> ": correlation=" <> selectedFor description identity
