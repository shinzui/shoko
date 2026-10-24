{-# LANGUAGE RankNTypes #-}

module Shoko.Observation
  ( Observation,
    observe,
    Predicate,
    predicate,
    (.&&.),
    (.||.),
    negated,
    onPart,
    observeThat,
    validPredicate,
    observationOperation,
    hoistObservation,
    correlatedBy,
    observationCorrelation,
    predicateId,
    matches,
    CoverageStrength (..),
    Coverage (..),
    Baseline (..),
    Occurrence (..),
    ObservationOutcome (..),
    PublicValue (..),
  )
where

import Shoko.Clock (MonotonicTime)
import Shoko.Correlation (CorrelationRef)
import Shoko.Identifier (SourceId)
import Shoko.Internal.Predicate
import Shoko.Prelude

data Observation op a = Observation !Text !(op a) (a -> Bool) ![Text] !(Maybe CorrelationRef)

observe :: Text -> op a -> (a -> Bool) -> Observation op a
observe key op test = Observation key op test [] Nothing

observationOperation :: Observation op a -> op a
observationOperation (Observation _ op _ _ _) = op

predicateId :: Observation op a -> Text
predicateId (Observation key _ _ _ _) = key

matches :: Observation op a -> a -> Bool
matches (Observation _ _ test _ _) = test

observeThat :: op a -> Predicate a -> Observation op a
observeThat op (Predicate leaves key test) = Observation key op test leaves Nothing

validPredicate :: Observation op a -> Bool
validPredicate (Observation key _ _ leaves _) = validLabels key leaves

data CoverageStrength = SampledState | DurableHistory
  deriving stock (Eq, Ord, Show, Generic)

-- | Inclusive monotonic evidence interval, independent of the polling interval.
data Coverage = Coverage
  { strength :: !CoverageStrength,
    fromMicros :: !MonotonicTime,
    throughMicros :: !MonotonicTime,
    complete :: !Bool
  }
  deriving stock (Eq, Show, Generic)

data Baseline = Baseline
  { source :: !SourceId,
    capturedAt :: !MonotonicTime,
    cursor :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)

data Occurrence a = Occurrence
  { occurrenceId :: !(Maybe Text),
    value :: !a
  }

data ObservationOutcome a
  = Observed ![Occurrence a] !Coverage
  | ObservedWithDetails ![Occurrence a] !Coverage ![(Text, PublicValue)]
  | ObservationUnavailable !Text

-- | Only explicit public summaries are serializable. Raw typed values never are.
data PublicValue = PublicChoice !Text | PublicCount !Integer | PublicFlag !Bool
  deriving stock (Eq, Show, Generic)

hoistObservation :: (forall x. f x -> g x) -> Observation f a -> Observation g a
hoistObservation transform (Observation key op test leaves selected) = Observation key (transform op) test leaves selected

correlatedBy :: CorrelationRef -> Observation op a -> Observation op a
correlatedBy selected (Observation key op test leaves _) = Observation key op test leaves (Just selected)

observationCorrelation :: Observation op a -> Maybe CorrelationRef
observationCorrelation (Observation _ _ _ _ selected) = selected
