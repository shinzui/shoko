{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE OverloadedStrings #-}

-- Run from the repository root after building core:
-- cabal exec -- runghc -XGHC2024 -XOverloadedStrings -package=shoko-core -ishoko-core/test shoko-core/test/UpdateGoldens.hs
module Main (main) where

import Data.Aeson (encode)
import Data.ByteString.Lazy qualified as LBS
import GoldenFixtures (valueFixtures)

main :: IO ()
main = do
  fixtures <- valueFixtures
  mapM_ (\(path, value) -> LBS.writeFile ("shoko-core/test/golden/" ++ path) (encode value <> "\n")) fixtures
