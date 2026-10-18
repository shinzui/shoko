module Shoko.Evidence
  ( Reason (..),
    Evidence (..),
    SubstepEvidence (..),
    ActionEvidence (..),
  )
where

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
    startedAt :: !Integer,
    finishedAt :: !Integer,
    reason :: !Reason
  }
  deriving stock (Eq, Show, Generic)

data ActionEvidence = ActionEvidence
  { nodeId :: !Text,
    operationId :: !Text,
    declaredOutcomes :: ![Text],
    observedOutcome :: !(Maybe Text),
    startedAt :: !Integer,
    finishedAt :: !Integer,
    reason :: !Reason,
    substeps :: ![SubstepEvidence],
    supportingData :: ![(Text, PublicValue)]
  }
  deriving stock (Eq, Show, Generic)

-- | Search evidence deliberately contains no raw domain values or requests.
data Evidence = Evidence
  { source :: !Text,
    operationId :: !Text,
    baseline :: !(Maybe Baseline),
    pollStartedAt :: !Integer,
    finishedAt :: !Integer,
    coverage :: !(Maybe Coverage),
    matchingOccurrenceIds :: ![Text],
    matchCount :: !Int,
    gaps :: !Bool,
    evidenceDeadline :: !Integer,
    supportingData :: ![(Text, PublicValue)]
  }
  deriving stock (Eq, Show, Generic)
