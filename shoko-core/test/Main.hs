module Main (main) where

import ComposeSpec qualified
import CoverageSpec qualified
import FaultSpec qualified
import HandlerSpec qualified
import Hedgehog (property, withTests, (===))
import PolicySpec qualified
import ResultSpec qualified
import RuntimeSpec qualified
import ScenarioSpec qualified
import Shoko qualified
import TemporalSpec qualified
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
              Shoko.version === "0.2.0.0",
        ScenarioSpec.tests,
        ComposeSpec.tests,
        HandlerSpec.tests,
        TemporalSpec.tests,
        RuntimeSpec.tests,
        CoverageSpec.tests,
        PolicySpec.tests,
        ResultSpec.tests,
        FaultSpec.tests
      ]
