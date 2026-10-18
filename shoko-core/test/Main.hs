module Main (main) where

import Hedgehog (property, withTests, (===))
import ScenarioSpec qualified
import Shoko qualified
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.Hedgehog (testPropertyNamed)

main :: IO ()
main =
  defaultMain $
    testGroup
      "public core consumer"
      [ testPropertyNamed "imports the installed public API" "publicVersion" $
          withTests 1 $
            property $
              Shoko.version === "0.1.0.0",
        ScenarioSpec.tests
      ]
