module Shoko.Internal.Predicate where

import Data.Char (isAlphaNum, isAscii)
import Data.Text qualified as Text
import Shoko.Prelude

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

predicateKey :: Predicate a -> Text
predicateKey (Predicate _ key _) = key

testPredicate :: Predicate a -> a -> Bool
testPredicate (Predicate _ _ test) = test

validResultPredicate :: Predicate a -> Bool
validResultPredicate (Predicate leaves key _) = validLabels key leaves

validLabels :: Text -> [Text] -> Bool
validLabels key leaves = not (Text.null key) && all valid leaves
  where
    valid label = not (Text.null label) && Text.all (\c -> isAscii c && (isAlphaNum c || c `elem` ['_', '-', '.'])) label
