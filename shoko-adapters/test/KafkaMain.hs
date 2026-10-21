module Main (main) where

import Kafka.Contract (tests)
import Test.Tasty (defaultMain)

main :: IO ()
main = tests >>= defaultMain
