-- | Public library entry point. Scenario semantics are implemented separately.
module Shoko
  ( version,
    module Shoko.Action,
    module Shoko.Binding,
    module Shoko.Correlation,
    module Shoko.Environment,
    module Shoko.Expectation,
    module Shoko.Observation,
    Scenario,
    ScenarioBuilder,
    scenario,
    given,
    act,
    expect,
    inspectScenario,
  )
where

import Shoko.Action
import Shoko.Binding
import Shoko.Correlation
import Shoko.Environment
import Shoko.Expectation
import Shoko.Observation
import Shoko.Prelude
import Shoko.Scenario (Scenario, ScenarioBuilder, act, expect, given, inspectScenario, scenario)

-- | Version of the public core package.
version :: Text
version = "0.1.0.0"
