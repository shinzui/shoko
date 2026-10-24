{-# LANGUAGE RankNTypes #-}

module Shoko.Expectation
  ( Expectation (..),
    Temporal (..),
    Expectations,
    eventually,
    never,
    exactlyOnce,
    within,
    holds,
    agreeOn,
    expectationList,
    hoistExpectations,
  )
where

import Data.Dynamic (Typeable)
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty
import Shoko.Action (Input, Ref, fromRef)
import Shoko.Environment
import Shoko.Observation
import Shoko.Prelude

data Temporal = Eventually | Never | ExactlyOnce | Immediately
  deriving stock (Eq, Ord, Show, Generic)

data Expectation op where
  Expectation :: !Text -> !Temporal -> ![Duration] -> !(Observation op a) -> Expectation op
  ResultCheck :: !Text -> ![Duration] -> !(Input a) -> !(Predicate a) -> Expectation op

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

holds :: Text -> Input a -> Predicate a -> Expectations op ()
holds key input test = Expectations ((), [ResultCheck key [] input test])

agreeOn :: (Typeable a, Eq b) => Text -> Text -> (a -> b) -> Ref a -> NonEmpty (Ref a) -> Expectations op ()
agreeOn key label project original others =
  holds key ((:|) <$> fromRef original <*> traverse fromRef (NonEmpty.toList others)) $
    onPart label (fmap project) (predicate "agree" (\(x :| xs) -> all (== x) xs))

within :: Duration -> Expectations op a -> Expectations op a
within duration (Expectations (a, es)) = Expectations (a, map addWindow es)
  where
    addWindow (Expectation key temporal windows observation) =
      Expectation key temporal (duration : windows) observation
    addWindow (ResultCheck key windows input test) = ResultCheck key (duration : windows) input test

expectationList :: Expectations op a -> [Expectation op]
expectationList (Expectations (_, es)) = es

hoistExpectations :: (forall x. f x -> g x) -> Expectations f a -> Expectations g a
hoistExpectations transform (Expectations (a, es)) = Expectations (a, map hoist es)
  where
    hoist (ResultCheck key windows input test) = ResultCheck key windows input test
    hoist (Expectation key t windows observation) = Expectation key t windows (hoistObservation transform observation)
