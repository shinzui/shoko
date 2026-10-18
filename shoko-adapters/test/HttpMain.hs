module Main (main) where

import AdapterTests (httpTests)
import Test.Tasty (defaultMain)

main :: IO ()
main = defaultMain httpTests
