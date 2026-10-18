module Main (main) where

import AdapterTests (postgresTests)
import Test.Tasty (defaultMain)

main :: IO ()
main = defaultMain postgresTests
