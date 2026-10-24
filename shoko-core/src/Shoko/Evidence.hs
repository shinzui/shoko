module Shoko.Evidence
  ( Reason (..),
    Evidence (..),
    ResultCheckEvidence (..),
    SubstepEvidence (..),
    ActionEvidence (..),
  )
where

import Shoko.Clock (MonotonicTime)
import Shoko.Identifier (SourceId)
import Shoko.Observation
import Shoko.Prelude

data Reason
  = Satisfied
  | Mismatch
  | SourceUnavailable
  | DeadlineExceeded
  | CoverageIncomplete
  | CorrelationLost
  | PrerequisiteUnavailable
  | MissingOccurrenceIdentity
  | UndeclaredOperation
  | InvalidEvidence
  | UnexpectedRunnerFault
  deriving stock (Eq, Ord, Show, Enum, Bounded, Generic)

data SubstepEvidence = SubstepEvidence
  { substepId :: !Text,
    startedAt :: !MonotonicTime,
    finishedAt :: !MonotonicTime,
    reason :: !Reason
  }
  deriving stock (Eq, Show, Generic)

data ActionEvidence = ActionEvidence
  { nodeId :: !Text,
    operationId :: !Text,
    declaredOutcomes :: ![Text],
    observedOutcome :: !(Maybe Text),
    startedAt :: !MonotonicTime,
    finishedAt :: !MonotonicTime,
    reason :: !Reason,
    substeps :: ![SubstepEvidence],
    supportingData :: ![(Text, PublicValue)]
  }
  deriving stock (Eq, Show, Generic)

-- | Search evidence deliberately contains no raw domain values or requests.
data Evidence = Evidence
  { source :: !SourceId,
    operationId :: !Text,
    baseline :: !(Maybe Baseline),
    pollStartedAt :: !MonotonicTime,
    finishedAt :: !MonotonicTime,
    coverage :: !(Maybe Coverage),
    matchingOccurrenceIds :: ![Text],
    matchCount :: !Int,
    gaps :: !Bool,
    evidenceDeadline :: !MonotonicTime,
    supportingData :: ![(Text, PublicValue)]
  }
  deriving stock (Eq, Show, Generic)

-- | Only dependencies and completed evaluation time are public.
data ResultCheckEvidence = ResultCheckEvidence
  { dependencies :: ![Text],
    evaluatedAt :: !(Maybe MonotonicTime)
  }
  deriving stock (Eq, Show, Generic)
