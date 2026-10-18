module Main (main) where

import AdapterTests (roundtripTests)
import Test.Tasty (defaultMain)

main :: IO ()
main = defaultMain roundtripTests
