module Shoko.Result
  ( Verdict (..),
    aggregateVerdicts,
    ExpectationResult (..),
    ExpectationEvidence (..),
    VerificationResult (..),
    RunResult (..),
    LogicalInput (..),
    PublicValue (..),
  )
where

import Data.Time (UTCTime)
import Shoko.Binding (Disposition, PolicyReport, PreflightError)
import Shoko.Clock (MonotonicTime)
import Shoko.Correlation
import Shoko.Environment (TargetIdentity)
import Shoko.Evidence
import Shoko.Observation (PublicValue (..))
import Shoko.Prelude
import Shoko.Scenario (Description)

data Verdict = Pass | Fail | Unknown
  deriving stock (Eq, Ord, Show, Generic)

aggregateVerdicts :: [Verdict] -> Verdict
aggregateVerdicts verdicts
  | Fail `elem` verdicts = Fail
  | Unknown `elem` verdicts = Unknown
  | otherwise = Pass

-- | Explicitly allowlisted logical parameters, separate from raw fixtures.
data LogicalInput = LogicalInput
  { recipeRevision :: !Text,
    parameters :: ![(Text, PublicValue)]
  }
  deriving stock (Eq, Show, Generic)

data ExpectationEvidence = ObservationEvidence !Evidence | ResultEvidence !ResultCheckEvidence
  deriving stock (Eq, Show, Generic)

data ExpectationResult = ExpectationResult
  { expectationId :: !Text,
    verdict :: !Verdict,
    reason :: !Reason,
    evidence :: !ExpectationEvidence
  }
  deriving stock (Eq, Show, Generic)

data VerificationResult = VerificationResult
  { description :: !Description,
    descriptionDigest :: !Text,
    runId :: !Text,
    environment :: !Text,
    binding :: !Text,
    buildIdentity :: !Text,
    implementationIdentity :: !(Maybe Text),
    targetIdentity :: !(Maybe TargetIdentity),
    logicalInput :: !LogicalInput,
    correlations :: ![ResolvedCorrelation],
    policyReport :: !PolicyReport,
    startedAt :: !UTCTime,
    finishedAt :: !UTCTime,
    executionStartedAt :: !MonotonicTime,
    executionDeadline :: !MonotonicTime,
    verdict :: !Verdict,
    actions :: ![ActionEvidence],
    expectations :: ![ExpectationResult],
    disposition :: ![Disposition]
  }
  deriving stock (Eq, Show, Generic)

data RunResult
  = Verification !VerificationResult
  | RunnerFault !Reason !(Maybe VerificationResult)
  | PreflightFailure ![PreflightError]
  deriving stock (Eq, Show, Generic)
