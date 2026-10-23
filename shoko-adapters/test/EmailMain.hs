module Main (main) where

import Email.Config qualified as Config
import Email.Contract qualified as Contract
import Email.Sending qualified as Sending
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main = defaultMain (testGroup "email" [Contract.tests, Sending.tests, Config.tests])
