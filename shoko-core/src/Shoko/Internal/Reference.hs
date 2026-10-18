module Shoko.Internal.Reference where

import Data.Dynamic (Dynamic, Typeable, fromDynamic)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Shoko.Prelude

-- No Show instance: a reference never prints its eventual value.
newtype Ref a = Ref Text

refId :: Ref a -> Text
refId (Ref key) = key

-- | Applicative inputs describe dependencies without exposing runtime values.
data Input a where
  Literal :: a -> Input a
  Reference :: (Typeable a) => Ref a -> Input a
  Apply :: Input (a -> b) -> Input a -> Input b

instance Functor Input where
  fmap f a = Apply (Literal f) a

instance Applicative Input where
  pure = Literal
  (<*>) = Apply

inputDependencies :: Input a -> [Text]
inputDependencies (Literal _) = []
inputDependencies (Reference r) = [refId r]
inputDependencies (Apply f a) = inputDependencies f ++ inputDependencies a

evaluateInput :: Map Text Dynamic -> Input a -> Either Text a
evaluateInput _ (Literal value) = Right value
evaluateInput values (Reference (Ref key)) =
  case Map.lookup key values >>= fromDynamic of
    Just value -> Right value
    Nothing -> Left key
evaluateInput values (Apply f a) = evaluateInput values f <*> evaluateInput values a
