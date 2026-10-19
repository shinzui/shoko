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

import Data.Char (isAlphaNum, isAscii)
import Data.Text qualified as Text
import Shoko.Prelude

data Observation op a = Observation !Text !(op a) (a -> Bool) ![Text]

observe :: Text -> op a -> (a -> Bool) -> Observation op a
observe key op test = Observation key op test []

observationOperation :: Observation op a -> op a
observationOperation (Observation _ op _ _) = op

predicateId :: Observation op a -> Text
predicateId (Observation key _ _ _) = key

matches :: Observation op a -> a -> Bool
matches (Observation _ _ test _) = test

data Predicate a = Predicate ![Text] !Text (a -> Bool)

predicate :: Text -> (a -> Bool) -> Predicate a
predicate key = Predicate [key] key

infixr 3 .&&.

infixr 2 .||.

(.&&.), (.||.) :: Predicate a -> Predicate a -> Predicate a
Predicate ls l f .&&. Predicate rs r g = Predicate (ls ++ rs) ("(" <> l <> " and " <> r <> ")") (\a -> f a && g a)
Predicate ls l f .||. Predicate rs r g = Predicate (ls ++ rs) ("(" <> l <> " or " <> r <> ")") (\a -> f a || g a)

negated :: Predicate a -> Predicate a
negated (Predicate leaves key test) = Predicate leaves ("not(" <> key <> ")") (not . test)

onPart :: Text -> (b -> a) -> Predicate a -> Predicate b
onPart label project (Predicate leaves key test) = Predicate (label : leaves) (label <> ":(" <> key <> ")") (test . project)

observeThat :: op a -> Predicate a -> Observation op a
observeThat op (Predicate leaves key test) = Observation key op test leaves

validPredicate :: Observation op a -> Bool
validPredicate (Observation key _ _ leaves) = not (Text.null key) && all valid leaves
  where
    valid label = not (Text.null label) && Text.all (\c -> isAscii c && (isAlphaNum c || c `elem` ['_', '-', '.'])) label

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
    value :: !a
  }

data ObservationOutcome a
  = Observed ![Occurrence a] !Coverage
  | ObservedWithDetails ![Occurrence a] !Coverage ![(Text, PublicValue)]
  | ObservationUnavailable !Text

-- | Only explicit public summaries are serializable. Raw typed values never are.
data PublicValue = PublicChoice !Text | PublicCount !Integer | PublicFlag !Bool
  deriving stock (Eq, Show, Generic)
