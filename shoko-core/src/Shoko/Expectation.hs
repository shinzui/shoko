module Shoko.Expectation
  ( Expectation (..),
    Temporal (..),
    Expectations,
    eventually,
    never,
    exactlyOnce,
    within,
    expectationList,
  )
where

import Shoko.Environment
import Shoko.Observation
import Shoko.Prelude

data Temporal = Eventually | Never | ExactlyOnce
  deriving stock (Eq, Ord, Show, Generic)

data Expectation op where
  Expectation :: !Text -> !Temporal -> ![Duration] -> !(Observation op a) -> Expectation op

newtype Expectations op a = Expectations (a, [Expectation op])

instance Functor (Expectations op) where
  fmap f (Expectations (a, es)) = Expectations (f a, es)

instance Applicative (Expectations op) where
  pure a = Expectations (a, [])
  Expectations (f, es) <*> Expectations (a, more) = Expectations (f a, es ++ more)

instance Monad (Expectations op) where
  Expectations (a, es) >>= f = case f a of
    Expectations (b, more) -> Expectations (b, es ++ more)

eventually :: Text -> Observation op a -> Expectations op ()
eventually key observation = Expectations ((), [Expectation key Eventually [] observation])

never :: Text -> Observation op a -> Expectations op ()
never key observation = Expectations ((), [Expectation key Never [] observation])

exactlyOnce :: Text -> Observation op a -> Expectations op ()
exactlyOnce key observation = Expectations ((), [Expectation key ExactlyOnce [] observation])

within :: Duration -> Expectations op a -> Expectations op a
within duration (Expectations (a, es)) = Expectations (a, map addWindow es)
  where
    addWindow (Expectation key temporal windows observation) =
      Expectation key temporal (duration : windows) observation

expectationList :: Expectations op a -> [Expectation op]
expectationList (Expectations (_, es)) = es
