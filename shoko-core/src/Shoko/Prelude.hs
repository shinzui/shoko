{-# LANGUAGE PackageImports #-}

-- | Small shared vocabulary; add re-exports only when core actually uses them.
module Shoko.Prelude (module X) where

import "base" GHC.Generics as X (Generic)
import "text" Data.Text as X (Text)
