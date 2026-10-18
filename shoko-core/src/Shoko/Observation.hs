module Shoko.Observation
  ( Observation,
    observe,
    observationOperation,
    predicateId,
    matches,
    CoverageStrength (..),
    Coverage (..),
    Baseline (..),
    Occurrence (..),
    ObservationOutcome (..),
  )
where

import Shoko.Prelude

data Observation op a = Observation !Text !(op a) (a -> Bool)

observe :: Text -> op a -> (a -> Bool) -> Observation op a
observe = Observation

observationOperation :: Observation op a -> op a
observationOperation (Observation _ op _) = op

predicateId :: Observation op a -> Text
predicateId (Observation key _ _) = key

matches :: Observation op a -> a -> Bool
matches (Observation _ _ predicate) = predicate

data CoverageStrength = SampledState | DurableHistory
  deriving stock (Eq, Ord, Show, Generic)

-- | Inclusive monotonic evidence interval, independent of the polling interval.
data Coverage = Coverage
  { strength :: !CoverageStrength,
    fromMicros :: !Integer,
    throughMicros :: !Integer,
    complete :: !Bool
  }
  deriving stock (Eq, Show, Generic)

data Baseline = Baseline
  { source :: !Text,
    capturedAt :: !Integer,
    cursor :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)

data Occurrence a = Occurrence
  { occurrenceId :: !(Maybe Text),
    value :: a
  }

data ObservationOutcome a
  = Observed ![Occurrence a] !Coverage
  | ObservationUnavailable !Text
