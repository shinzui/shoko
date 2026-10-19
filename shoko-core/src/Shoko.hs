-- | Public library entry point. Scenario semantics are implemented separately.
module Shoko
  ( version,
    module Shoko.Action,
    module Shoko.Identifier,
    MonotonicTime (..),
    monotonicMicros,
    addDuration,
    differenceMicros,
    module Shoko.Binding,
    module Shoko.Correlation,
    module Shoko.Compose,
    module Shoko.Environment,
    module Shoko.Expectation,
    module Shoko.Observation,
    Scenario,
    ScenarioBuilder,
    scenario,
    given,
    act,
    expect,
    namespace,
    expectAfterActions,
    hoistScenarioBuilder,
    correlate,
    propagateExecutionId,
    inspectScenario,
    runScenario,
  )
where

import Shoko.Action
import Shoko.Binding
import Shoko.Clock (MonotonicTime (..), addDuration, differenceMicros, monotonicMicros)
import Shoko.Compose
import Shoko.Correlation
import Shoko.Environment
import Shoko.Expectation
import Shoko.Identifier
import Shoko.Observation
import Shoko.Prelude
import Shoko.Runner (runScenario)
import Shoko.Scenario (Scenario, ScenarioBuilder, act, correlate, expect, expectAfterActions, given, hoistScenarioBuilder, inspectScenario, namespace, propagateExecutionId, scenario)

-- | Version of the public core package.
version :: Text
version = "0.2.0.0"
