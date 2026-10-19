{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE UndecidableInstances #-}

module Shoko.Compose ((:+:) (..), Member (..), combineBindings) where

import Control.Exception (mask)
import Control.Monad (forM_)
import Data.Set qualified as Set
import Shoko.Action
import Shoko.Binding (focus)
import Shoko.Internal.Binding
import Shoko.Prelude

data (f :+: g) a = InL (f a) | InR (g a)

infixr 6 :+:

instance (Vocabulary f, Vocabulary g) => Vocabulary (f :+: g) where
  describeOperation (InL op) = describeOperation op
  describeOperation (InR op) = describeOperation op

class Member f g where inject :: f a -> g a

instance Member f f where inject = id

instance {-# OVERLAPPING #-} Member f (f :+: g) where inject = InL

instance {-# OVERLAPPABLE #-} (Member f g) => Member f (h :+: g) where inject = InR . inject

-- Register each completed leaf under masking before acquiring the next one.
-- Partial acquisitions still register their own cleanup before blocking IO.
combineBindings :: forall f g r1 r2. Text -> Binding f r1 -> Binding g r2 -> Binding (f :+: g) (r1, r2)
combineBindings name left right = Binding name lifecycle acquire (const []) handlers
  where
    lifecycle = Set.union (internalLifecycle left) (internalLifecycle right)
    acquire register = mask $ \restore -> do
      l <- restore (internalAcquire left register)
      forM_ (internalRelease left l) register
      r <- restore (internalAcquire right register)
      forM_ (internalRelease right r) register
      pure (l, r)
    handlers :: OperationRole -> (f :+: g) a -> Either HandlerBuildError (Maybe (Handler (r1, r2) a))
    handlers role (InL op) = fmap (markOwner False . focus fst) <$> internalHandler left role op
    handlers role (InR op) = fmap (markOwner True . focus snd) <$> internalHandler right role op

markOwner :: Bool -> Handler resource a -> Handler resource a
markOwner _ handler@(ActionHandler _ _) = handler
markOwner side (ObservationHandler contract requirement (Source label strength capture path) perform) =
  ObservationHandler contract requirement (Source label strength capture (side : path)) perform
