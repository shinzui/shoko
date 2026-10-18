module Main (main) where

import EventStore.Contract (tests)
import Test.Tasty (defaultMain)

main :: IO ()
main = tests >>= defaultMain
