---
id: 9
slug: verify-idempotent-operations-with-result-checks-and-concurrent-actions
title: "Verify idempotent operations with result checks and concurrent actions"
kind: exec-plan
created_at: 2026-10-20T04:56:26Z
intention: "intention_01m5btnw9ne36v6p7qmemh32z1"
provenance:
  created_by:
    model: "claude-opus-5-5"
    harness: "claude-code"
    at: 2026-10-20T04:56:26Z
---

# Verify idempotent operations with result checks and concurrent actions

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

An operation is *idempotent* when performing it more than once with the same identity has
the same effect as performing it once. Distributed services make operations idempotent so
that client retries, message redelivery, and duplicate submissions cannot open two
accounts, charge twice, or emit two `AccountCreated` events. The usual mechanism is an
*idempotency key*: the caller attaches a unique key to a request, and the service records
the key with its first result so that a repeat returns the recorded result (a *replay*)
instead of performing the effect again. A repeat with the same key but a different payload
should get a documented rejection.

An idempotency test therefore claims three things about a repeated operation: the repeat
received an accepted outcome (replayed, or a documented duplicate/conflict rejection); the
repeat's response agrees with the original (for example, it names the same account); and
the side effect happened exactly once. The most valuable variant sends the duplicates
*concurrently*, because a service that checks "does this key exist?" and then inserts can
pass every sequential retry yet create two effects when two requests race.

After this plan, a scenario author can write all of these tests in Shōko:

```haskell
idempotentRetry :: ScenarioBuilder Orders ()
idempotentRetry = do
  key <- given "key" (accept ["issued"] NewKey)
  original <- act "original" (accept ["created"] (Submit (fromRef key) (pure "basket-1")))
  retry <- act "retry" (accept ["replayed"] (Submit (fromRef key) (pure "basket-1")))
  selected <- correlate (CorrelationAlias "order") (BusinessKeyName "idempotencyKey") (fromRef key)
  expect $ do
    agreeOn "same-order" "orderId" orderId original (retry :| [])
    exactlyOnce "one-effect" $ correlatedBy selected $
      observeThat (OrderPlaced (fromRef key)) (predicate "placed" id)

concurrentDuplicates :: ScenarioBuilder Orders ()
concurrentDuplicates = do
  key <- given "key" (accept ["issued"] NewKey)
  let attempt n = act ("attempt-" <> n) (accept ["created", "replayed"] (Submit (fromRef key) (pure "basket-1")))
  (a1, a2, a3) <- concurrently "burst" ((,,) <$> attempt "1" <*> attempt "2" <*> attempt "3")
  selected <- correlate (CorrelationAlias "order") (BusinessKeyName "idempotencyKey") (fromRef key)
  expect $ do
    agreeOn "same-order" "orderId" orderId a1 (a2 :| [a3])
    holds "one-creation" (traverse fromRef (a1 :| [a2, a3])) (predicate "single-created" ((== 1) . length . NonEmpty.filter created))
    exactlyOnce "one-effect" $ correlatedBy selected $
      observeThat (OrderPlaced (fromRef key)) (predicate "placed" id)
```

To see it working, run the compiled demonstration
host: `idempotent-retry` and `concurrent-duplicates` report Pass against an idempotent
in-memory service, and the same scenarios report Fail, exit code 1, against a deliberately
non-idempotent one. `explain` shows the result checks and the concurrent group without
running anything.

The research for this plan found that sequential retries are already expressible with
the current API: two `act` nodes can reuse the same operation and the same key reference,
`accept` can name replay tags, and `exactlyOnce` counts effects over durable history.
Two things are missing and are what this plan adds: a way to compare action results with
each other (today it needs a fake observation and evidence source), and a way to submit
duplicates concurrently (today every action runs strictly in sequence). Milestone 1 proves
the first claim with a working consumer before any API changes.


## Progress

- [ ] Milestone 1: an in-memory idempotency consumer proves sequential retry, payload
  conflict, Fail on duplicate effects, and Unknown on unavailable evidence with the
  current API; the response-agreement gap is recorded with a concrete example.
- [ ] Milestone 2: `holds` and `agreeOn` result checks are inspectable, evaluated after
  actions without an evidence source, and reported in result schema v3.
- [ ] Milestone 3: `concurrently` groups run independent actions together behind a start
  barrier; preflight requires handlers that opt into concurrent calls; a deterministic
  race-prone binding fails and an atomic one passes.
- [ ] Milestone 4: the consumer host demonstrates Pass and Fail through the CLI, and
  docs, catalogs, CHANGELOG, and ADRs 0002/0003 describe the new semantics.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Do not add a dedicated "retry" or "repeat" combinator. A repeated request is an
  ordinary second `act` node that reuses the same operation and the same key reference.
  Rationale: `Action op a` is a plain value and node IDs already distinguish the attempts
  (`original`, `retry`). Inspection already shows that both nodes depend on the same key
  fixture, which is the relationship a reader needs to see. A helper would hide the
  accepted-outcome sets, which must differ between the first call and the repeat.
  Date: 2026-10-20

- Decision: Add pure *result checks* (`holds`, `agreeOn`) as a new kind of expectation
  rather than asking contexts to write comparison observations.
  Rationale: An observation must be backed by a binding handler with an evidence source,
  baseline, coverage, and correlation requirement. Comparing two action responses has none
  of these; modelling it as an observation would report fabricated coverage from a source
  that does not exist. A result check reads only values already produced by earlier
  actions, so it can be evaluated once, needs no handler, and stays inspectable.
  Date: 2026-10-20

- Decision: Include concurrent action groups in this plan, as Milestone 3, with an
  explicit handler opt-in for concurrent calls.
  Rationale: Races between duplicate requests are the failure that sequential retries
  cannot reveal. ADR 0002 deferred user-defined scheduling; a declared, inspectable group
  of mutually independent actions is the narrowest extension that enables race tests and
  keeps runtime branching excluded. Existing bindings were written assuming sequential
  calls (for example `modifyIORef'` in `shoko-cli/test/ConsumerHost/Registration.hs`), so
  concurrency must be an explicit binding promise checked in preflight rather than an
  assumption. Milestone 3 is independent of Milestones 1–2 at the runtime level; if it is
  cut, Milestones 1, 2, and the documentation part of 4 still stand.
  Date: 2026-10-20

- Decision: Bump the result contract to schema v3 once, covering both result checks and
  concurrent groups. Schema v3 is a draft until this plan completes; Milestone 3 may
  extend it, and it is frozen in Milestone 4.
  Rationale: The v2 decoder in `shoko-core/src/Shoko/Result/Json.hs` rejects unknown
  fields and tags, so any new description or evidence shape is a breaking contract change.
  Bumping twice in one plan would create a short-lived v3 nobody consumes.
  Date: 2026-10-20

- Decision: Do not retry actions automatically, even inside idempotency scenarios.
  Rationale: ADR 0003 forbids automatic retries of mutating actions after a timeout. An
  author who wants to test "retry after an uncertain outcome" must declare the retry, and
  an uncertain first outcome still stops later mutations. Deliberately inducing an
  uncertain outcome (fault injection) is out of scope.
  Date: 2026-10-20


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Shōko is a Haskell library and CLI for verifying observable behavior of distributed
systems. The repository root is `/Users/shinzui/Keikaku/bokuno/shoko`; all paths below are
relative to it. There are three Cabal packages: `shoko-core` (the scenario language and
runner), `shoko-adapters` (PostgreSQL, HTTP, Kiroku, and Message DB evidence readers), and
`shoko-cli` (compiled scenario hosts). `docs/core.md` is the authoritative guide to the
current core API and should be read before starting.

Terms used throughout:

A *vocabulary* is a context-owned GADT whose constructors are business operations; each
constructor's type index is the operation's result type. Its `Vocabulary` instance
(`describeOperation`, in `shoko-core/src/Shoko/Action.hs`) returns an `OperationInfo`
naming the operation ID, required capabilities, input dependencies, and substeps.

A *scenario* (`shoko-core/src/Shoko/Scenario.hs`) is built in the `ScenarioBuilder op`
monad. `given key action` declares a *fixture* (a precondition such as "an issued key");
`act key action` declares an *action* (an operation that may change the system). Both
return an opaque `Ref a`. `fromRef ref` turns it into an `Input a`; `Input` is applicative,
so `(,) <$> fromRef a <*> fromRef b` is an `Input (a, b)`. Inputs are resolved only at run
time (`shoko-core/src/Shoko/Internal/Reference.hs`, `evaluateInput`). `accept tags op`
(`Shoko.Action`) wraps an operation with the set of *domain outcome* tags the scenario
accepts; a binding labels each outcome with a tag, and an unaccepted tag makes the action
`Mismatch` (Fail) and stops later actions.

An *expectation* (`shoko-core/src/Shoko/Expectation.hs`) is `Expectation key temporal
windows observation`. The temporal kinds are `Eventually`, `Never`, and `ExactlyOnce`.
`exactlyOnce` counts distinct occurrence identities over a completely covered evidence
interval and fails on a second distinct occurrence; it needs a source with
`DurableHistory` coverage (an append-only history), not a sampled snapshot. An
*observation* (`shoko-core/src/Shoko/Observation.hs`) pairs a vocabulary operation with a
`Predicate`; `predicate name test`, `.&&.`, `.||.`, `negated`, and `onPart label project`
build named predicates. `expect` declares expectations that forbid later actions;
`expectAfterActions` declares ones that allow later actions. All expectations activate
together after the last action.

A *binding* (`shoko-core/src/Shoko/Binding.hs`) maps operations to *handlers*:
`actionHandler contract perform` for fixtures and actions, `observationHandler contract
correlationRequirement source perform` for observations. *Preflight* (`resolveScenario`)
checks handlers, capabilities, sources, and correlation before acquiring any resource and
returns `PreflightError`s. The *runner* (`shoko-core/src/Shoko/Runner.hs`) executes:
`runSteps` (around line 268) runs fixtures and actions strictly one after another, storing
each satisfied result in a `Map Text Dynamic` keyed by node ID, and stops at the first
terminal outcome with `PrerequisiteUnavailable`. Expectations then run concurrently.
Results (`shoko-core/src/Shoko/Result.hs`, `shoko-core/src/Shoko/Evidence.hs`) are
three-valued: `Pass`, `Fail`, `Unknown`. `ExpectationResult` currently always carries an
observation `Evidence` record (source ID, baseline, coverage, match count).

*Inspection* (`inspectScenario`) collects the builder into a `Description` without running
IO. `Description` holds `NodeDescription`s (node ID, fixture flag, `OperationInfo`, accepted
outcomes) and `ExpectationDescription`s (ID, temporal, windows, `OperationInfo`, predicate
ID, correlation ID). `scenarioParts` performs the collection and returns `DefinitionError`s
such as `DuplicateIdentifier`, `UnresolvedReference`, and `ActionAfterExpectations`.

The *result contract* is the JSON written by `encodeRunResult` in
`shoko-core/src/Shoko/Result/Json.hs`, currently `schemaVersion: 2`, validated by
`schemas/run-result-v2.schema.json` and the goldens in `shoko-core/test/golden/*.json`
(`pass`, `fail`, `unknown`, `rejection`, `runner-fault`, `preflight`, `definition-error`).
The *description digest* (`shoko-core/src/Shoko/Internal/Digest.hs`) is a SHA-256 over a
versioned fixed-order array of public description fields; it must change version when the
description gains fields. `scripts/check-result-schema.py` and `scripts/test-cli` hard-code
the v2 schema path and `schemaVersion == 2`.

Existing in-memory consumers live in `shoko-core/test/Consumer/` (`Account.hs`,
`DeliveryLedger.hs`, `Composed.hs`, with shared `Hooks.hs`). `DeliveryLedger.hs` is the
closest model for this plan: an append-only list in an `IORef` acts as a durable history,
`Append n` writes `n` copies of a delivery key, and `ledgerScenario` checks `exactlyOnce`.
Test specs are registered in `shoko-core/test/Main.hs` and listed under `other-modules` in
`shoko-core/shoko-core.cabal`. The compiled CLI demonstration host is
`shoko-cli/test/ConsumerHost/Main.hs` with `shoko-cli/test/ConsumerHost/Registration.hs`;
a registry `Entry` lists binding factories by implementation name, and the CLI selects
one with `runtime.implementation` in a YAML config or `SHOKO_IMPLEMENTATION`. The default
capability policy is `[ReadState, WriteState]` (`shoko-cli/src/Shoko/Cli/Config.hs`
line 78), so a scenario reading durable events needs a config granting `ReadEvents`.
`scripts/test-cli` drives the host as a subprocess.

Relevant ADRs (local Markdown files, revised by appending dated paragraphs):

[ADR 0002](../adr/0002-keep-scenarios-inspectable-and-bindings-explicit.md) requires that
building a description never performs IO and that runtime values never select branches
absent from inspection. It fixes composition as "a fixed action sequence followed by an
expectation group" and defers "arbitrary runtime branching, a general workflow graph, and
user-defined scheduling". Bindings declare their full contracts, which preflight checks.
Result checks stay within this model. Concurrent groups change "fixed action sequence"
into "fixed sequence of stages, where a stage is one action or a declared group of
mutually independent actions"; this needs a dated revision in Milestone 4.

[ADR 0003](../adr/0003-record-bounded-evidence-and-three-valued-results.md) defines the
three-valued verdicts, the bounded execution budget, `exactlyOnce` cardinality over durable
coverage, the rule that terminal unexpected or uncertain action outcomes stop later
mutations, the prohibition on automatic retries of mutating actions, and the versioned
result contract. This plan keeps all of those rules and introduces result schema v3.

[ADR 0004](../adr/0004-gate-parity-on-real-workflows-and-context-owned-vocabulary.md) makes
each bounded context own its vocabulary and bindings. Idempotency vocabularies such as
"submit with key" therefore belong to the context; Shōko core gains only generic
constructs. [ADR 0001](../adr/0001-use-jitsurei-standards-and-the-seihou-haskell-flake.md)
defines GHC 9.12, GHC2024, strict unprefixed record fields, and the build/format commands.


## Plan of Work

### Milestone 1: prove sequential idempotency with the current API

Scope: no change under `shoko-core/src`. Create `shoko-core/test/Consumer/Idempotency.hs`,
an in-memory "orders" context, and `shoko-core/test/IdempotencySpec.hs`. At the end, the
test suite shows which idempotency claims are already expressible and records, as a
Surprises & Discoveries entry, what comparing responses costs without new API.

The vocabulary:

```haskell
data Submission = Submission {orderId :: !Text, created :: !Bool}
  deriving stock (Eq, Show, Generic)

data Orders a where
  NewKey :: Orders Text
  Submit :: Input Text -> Input Text -> Orders Submission -- idempotency key, payload
  OrderPlaced :: Input Text -> Orders Bool
```

`NewKey` is a fixture (`declareOperation "orders.new-key" []`), `Submit` is an action
(`[WriteState]`, depends on both inputs), and `OrderPlaced` is a durable-history
observation (`[ReadEvents]`, depends on its input) correlated by
`BusinessKeyName "idempotencyKey"`. The binding resource holds an `IORef` key ledger
(`Map Text (Text, Text)` from key to payload and order ID) and an `IORef [Text]` append-only
effect history like `DeliveryLedger.hs`. Use `atomicModifyIORef'` for both so the binding
can later be marked safe for concurrent calls. Provide a binding constructor taking a mode:

```haskell
data Behavior = Idempotent | NonIdempotent | RaceProne
ordersBinding :: Behavior -> IO (Binding Orders OrdersResource)
```

`Idempotent` returns tag `created` with a new order and one appended effect for a new key;
`replayed` with the recorded order and no effect for a repeated key and equal payload; and
`key-conflict` with no effect for a repeated key and a different payload. `NonIdempotent`
ignores the ledger: every call returns `created`, a fresh order ID, and one effect.
`RaceProne` is added in Milestone 3. The observation reads the effect history from the
baseline cursor, filters by the selected key, and returns one `Occurrence` per effect with
the history index as its occurrence ID and `DurableHistory` coverage, exactly like
`readObservation` in `DeliveryLedger.hs`. Also allow an "unavailable" switch that makes the
observation return `ObservationUnavailable "source-unavailable"`.

Scenarios in the consumer module: `retryScenario` (original accepts `created`, retry accepts
`replayed`, `exactlyOnce` effect), and `conflictScenario` (the repeat sends a different
payload and accepts `key-conflict`; `exactlyOnce` effect still holds). `IdempotencySpec`
asserts, with the existing `runScenario` pattern from `shoko-core/test/RuntimeSpec.hs`:
retry against `Idempotent` is Pass; retry against `NonIdempotent` is Fail, either because
the retry's tag is `created` (an action `Mismatch`) or, if the retry accepts both tags,
because `exactlyOnce` sees two occurrences — test both variants, since the second shows
the effect check catching a defect the response tag hides; conflict against `Idempotent`
is Pass; retry with the unavailable switch is Unknown. Also assert from `inspectScenario`
that both `Submit` nodes list the `key` node among their dependencies.

Finally, try to state "the retry names the same order as the original" with the current
API. The only route is an extra vocabulary observation such as
`SameOrder :: Input Submission -> Input Submission -> Orders Bool` with a handler and a
`sampledSource` that compares resolved inputs. Write it in the spec, run it, and record in
Surprises & Discoveries that it works only by inventing an evidence source and sampled
coverage for something no system was asked. Keep this test until Milestone 2 replaces it.

Register both modules in `shoko-core/shoko-core.cabal` and `IdempotencySpec` in
`shoko-core/test/Main.hs`. Acceptance: `nix develop --command just test` passes with the
new cases listed.

### Milestone 2: result checks

Scope: add a second kind of expectation evaluated from earlier action results. At the
end, `holds` and `agreeOn` are exported from `Shoko`, inspectable, executed, and encoded in
result schema v3.

In `shoko-core/src/Shoko/Expectation.hs`, add a constructor:

```haskell
data Expectation op where
  Expectation :: !Text -> !Temporal -> ![Duration] -> !(Observation op a) -> Expectation op
  ResultCheck :: (Typeable a) => !Text -> ![Duration] -> !(Input a) -> !(Predicate a) -> Expectation op
```

`Predicate` must be exported abstractly from `Shoko.Observation` along with a way to read
its key, leaves, and test (add internal accessors, or move `Predicate` into an internal
module both can import; keep the public constructor hidden). Add:

```haskell
holds :: (Typeable a) => Text -> Input a -> Predicate a -> Expectations op ()
agreeOn :: (Typeable a, Eq b) => Text -> Text -> (a -> b) -> Ref a -> NonEmpty (Ref a) -> Expectations op ()
```

`agreeOn key label project original others` is
`holds key ((:|) <$> fromRef original <*> traverse fromRef (toList others))` with the
predicate `onPart label (fmap project) (predicate "agree" allEqual)`, so its predicate ID
renders as `orderId:(agree)`. `NonEmpty` guarantees at least two results are compared.
`within` keeps adding windows to result checks so mixed groups compose, but windows have no
effect on them; document that. `hoistExpectations` maps result checks unchanged (they hold
no operation). Extend `validPredicate`-style validation to result-check predicates.

In `shoko-core/src/Shoko/Scenario.hs`, change `ExpectationDescription` to describe its
subject instead of always carrying an `OperationInfo`:

```haskell
data ExpectationSubject
  = ObservationSubject !OperationInfo
  | ResultSubject ![Text] -- node IDs read by the check, from inputDependencies
  deriving stock (Eq, Show, Generic)
```

Replace the `operation` field with `subject :: ExpectationSubject`, and give result checks
a new `Temporal` value `Immediately` (JSON tag `immediately`) meaning "evaluated once at
activation". In `scenarioParts`, qualify result-check keys by namespace like other
expectations, validate their dependencies exactly like an observation's (strict checks
against known nodes so far, deferred checks against the final node set, producing
`UnresolvedReference`), and exclude them from `conflictingOperations`. A result check may
depend on fixtures and actions alike. `correlatedBy` cannot apply, because it takes an
`Observation`, so `correlationId` is always `Nothing` for result checks.

In `shoko-core/src/Shoko/Runner.hs`, at activation, evaluate each result check with the
same `values` map that `runSteps` returns: `evaluateInput values input` then the predicate.
`Right True` is Pass/`Satisfied`; `Right False` is Fail/`Mismatch`; a `Left` (missing or
mistyped value) is Unknown/`PrerequisiteUnavailable`. The existing rule that a terminal
action failure suppresses every expectation as `PrerequisiteUnavailable` applies unchanged.
Evaluate the predicate under the same `attempt` wrapper used for handlers so that an
exception thrown by user predicate code becomes `UnexpectedRunnerFault` instead of
crashing the run. Result checks do not wait for or consume evidence sources and do not
affect baselines; preflight requires no handler for them.

In `shoko-core/src/Shoko/Result.hs` and `Shoko/Evidence.hs`, replace
`ExpectationResult.evidence :: Evidence` with:

```haskell
data ExpectationEvidence
  = ObservationEvidence !Evidence
  | ResultEvidence !ResultCheckEvidence

data ResultCheckEvidence = ResultCheckEvidence
  { dependencies :: ![Text],
    evaluatedAt :: !MonotonicTime
  }
```

No result value is ever rendered; only node IDs and the time are public, consistent with the
redaction rule in ADR 0003.

In `shoko-core/src/Shoko/Result/Json.hs`, change the accepted and emitted version to 3,
encode the subject as `{"kind": "observation", "operation": …}` or
`{"kind": "result", "dependencies": […]}`, the evidence as a tagged object with `kind`
`observation` or `result`, and add `immediately` to `temporals`. Bump the digest version in
`shoko-core/src/Shoko/Internal/Digest.hs` and include the subject kind and result
dependencies in its fixed-order array. Copy `schemas/run-result-v2.schema.json` to
`schemas/run-result-v3.schema.json`, edit it for the new shapes, and delete the v2 file
(the v2 codec is removed, as plan 8 did for v1). Update the default schema path and
expected version in `scripts/check-result-schema.py` and `scripts/test-cli`. Fix every
compile error in `shoko-cli/src/Shoko/Cli.hs`, `shoko-cli/src/Shoko/Cli/Report.hs`, and the
core tests that pattern-match `ExpectationDescription` or `ExpectationResult` (find them
with `grep -rn "ExpectationDescription\|ExpectationResult" shoko-core shoko-cli
shoko-adapters`). Text reports should print result checks as
`<id> immediately <predicate> from <dependencies>`.

Tests: replace the Milestone 1 `SameOrder` workaround with `agreeOn`; assert Pass for
`Idempotent`, Fail for `NonIdempotent` with a retry that accepts both tags (different order
IDs), and Unknown/`PrerequisiteUnavailable` for a check reading a node that did not
complete. In `ScenarioSpec`, assert the description of a result check (subject, temporal
`Immediately`, namespaced ID, predicate ID `orderId:(agree)`), `UnresolvedReference` for a
strict check that names a later node, and acceptance of a deferred one. Add a result-check
expectation to the `pass` and `fail` golden fixtures in `shoko-core/test/GoldenFixtures.hs`,
regenerate goldens (command below), and inspect the diff. Acceptance: `nix develop
--command just check` passes, including schema validation of the regenerated goldens.

### Milestone 3: concurrent action groups

Scope: allow a declared group of independent actions to run at the same time. At the end,
`concurrently` and `allowConcurrentCalls` are exported, inspection shows group membership,
and a deterministic race test fails against `RaceProne` and passes against `Idempotent`.

API, in `shoko-core/src/Shoko/Scenario.hs` and `shoko-core/src/Shoko/Binding.hs`:

```haskell
concurrently :: Text -> ScenarioBuilder op a -> ScenarioBuilder op a
allowConcurrentCalls :: Handler resource a -> Handler resource a
handlerAllowsConcurrentCalls :: Handler resource a -> Bool
```

Add a `Concurrently :: Text -> ScenarioBuilder op a -> ScenarioBuilder op a` constructor to
the `ScenarioBuilder` GADT and map it in `hoistScenarioBuilder`. The group label is an
identifier qualified by the current namespace (so `namespace "x" (concurrently "burst" …)`
yields group `x.burst`); it joins the duplicate-identifier check with node and expectation
IDs. It does not prefix node IDs; authors namespace them explicitly if they want. Inside a
group only `act`, `namespace`, `pure`, and binding are allowed. A fixture, strict or
deferred expectation, correlation declaration, `propagateExecutionId`, a nested
`concurrently`, an empty group, or a step that depends on another step of the same group is
the new `DefinitionError` `InvalidConcurrentGroup !Text` (carrying the group ID). Track the
current group in `collect` the same way it tracks the namespace prefix.

Add `group :: !(Maybe Text)` to `NodeDescription` and to `Step` (the `Step` constructor is
exported; update every pattern match). Encode it in v3 JSON as `"concurrentGroup"`, nullable,
and include it in the digest array. Steps of one group are consecutive by construction.

In `shoko-core/src/Shoko/Binding.hs`, add a `Bool` to the internal action-handler
representation, defaulting to `False` in `actionHandler`; `allowConcurrentCalls` sets it and
`focus`/`adjustContract` preserve it. In `resolveScenario`, every step in a group must use a
handler that allows concurrent calls; otherwise preflight returns the new
`PreflightError` `ConcurrentCallsUnsupported !Text` naming the node ID, before acquisition.
This is a binding promise that the handler is safe to run alongside other handlers of the
same binding on the same resource; preflight cannot verify it, as with other contracts.

In `shoko-core/src/Shoko/Runner.hs`, change `runSteps` to process stages: a step without a
group runs as today; a maximal run of consecutive steps with the same group runs together.
For a group, create every call context from the same `values` map, spawn one thread per
step with `Control.Concurrent.Async` (`async` is already a `shoko-core` dependency) using
`withAsync`/`mapConcurrently` so cancellation of the runner cancels the group, and make each
thread wait on a shared start gate (an `MVar ()` read with `readMVar`) that the runner fills
after all threads exist. Each call keeps its own `attempt runClock end` bound, its own
substep and denied-access `IORef`s, and its own `started`/`finished` timestamps. After all
complete, classify every outcome with the existing logic, append evidence in declaration
order, insert all satisfied values, and, if any member is terminal, stop before the next
stage with `PrerequisiteUnavailable`. Members of the same group never observe one another's
results, which the definition rule already guarantees.

Race tests: implement `RaceProne` in `shoko-core/test/Consumer/Idempotency.hs` as a
check-then-insert service whose check and insert are separated by a test rendezvous: each
call reads the ledger, then waits on a counter until N calls have read (or a short timeout),
then inserts and appends an effect. With N = 3 concurrent attempts, all three see "no key"
and all create, deterministically. Mark all three bindings' `Submit` handlers with
`allowConcurrentCalls`. Assert: `concurrentDuplicates` against `Idempotent` is Pass;
against `RaceProne` is Fail (both `one-creation` and `one-effect` fail, and `same-order`
fails); against a binding whose `Submit` handler lacks `allowConcurrentCalls`,
`resolveScenario` returns `ConcurrentCallsUnsupported "attempt-1"` and the acquire hook never
ran. Assert from the action evidence that the three attempts' `[startedAt, finishedAt]`
intervals overlap. Add `ScenarioSpec` cases for every `InvalidConcurrentGroup` rule, group
qualification under a namespace, and `hoistScenarioBuilder` preserving groups. Add a
`FaultSpec` case where one member throws and the others still complete and are reported,
and a cancellation case in the style of the existing cancellation tests where cancelling the
runner during a group leaves no running member threads. Add a group to one golden fixture
and regenerate. Acceptance: `nix develop --command just check` passes.

### Milestone 4: CLI demonstration, documentation, and ADRs

Scope: process-level evidence and durable documentation. At the end, the consumer host
runs both idempotency scenarios, and every document describing scenarios, results, or
schema versions is current.

Create `shoko-cli/test/ConsumerHost/Idempotency.hs` with its own copy of the orders
vocabulary and bindings (the consumer host is an independent public-package consumer and
must not import `shoko-core` test modules), exporting `idempotencyEntries :: [Entry]` with
`idempotent-retry` and `concurrent-duplicates`. Each entry lists binding factories
`("demo", idempotent)` and `("non-idempotent", raceProne)`; the race-prone binding fails
both scenarios. Append the entries to the registry in `shoko-cli/test/ConsumerHost/Main.hs`
and add the module to the `shoko-consumer-host` stanza's `other-modules` in
`shoko-cli/shoko-cli.cabal`. Add `config/idempotency-demo.yaml`, a copy of
`config/demo.yaml` whose `policy.capabilities` is `[ReadState, ReadEvents, WriteState]`.
Extend `scripts/test-cli` to assert: `explain concurrent-duplicates --format json` lists the
three attempts with `concurrentGroup: "burst"` and the result checks with subject kind
`result`; `run` of each scenario with the demo config exits 0 with a schema-valid v3 Pass
document; and the same runs with `SHOKO_IMPLEMENTATION=non-idempotent` exit 1 with Fail.

Documentation: add an "Idempotency scenarios" section to `docs/core.md` with the two
patterns from Purpose, the rules for result checks and concurrent groups, the binding
obligation behind `allowConcurrentCalls`, and the reminder that `exactlyOnce` counts
evidence occurrences over durable history, not remote executions. Update the README outline
if it lists the core surface, `docs/scenario-hosts.md` for the new demonstration commands,
and `shoko-core/CHANGELOG.md` with a new `0.3.0.0` entry; bump `version` in
`shoko-core/src/Shoko.hs` and the Cabal version to `0.3.0.0`. Append a dated revision to
ADR 0002 (stages and concurrent groups, result checks as source-free expectations, handler
concurrency opt-in) and ADR 0003 (result schema v3, `Immediately` semantics, result-check
evidence, terminal handling for groups). Update the capability catalog entries
`docs/capabilities/inspectable-typed-scenarios.md` (interface list) and
`docs/capabilities/versioned-private-result-contract.md` (v3), and add terminology entries
for *idempotency key*, *result check*, and *concurrent group* under `docs/terminology/`,
following the existing files' frontmatter and updating `index.md` and `log.md` in each
bundle. Mark schema v3 frozen in the Decision Log, then complete Outcomes & Retrospective.
Acceptance: `nix develop --command just check` and `nix develop --command just check-docs`
pass.


## Concrete Steps

Run everything from the repository root, `/Users/shinzui/Keikaku/bokuno/shoko`.

Before starting, confirm the baseline is green:

```bash
nix develop --command cabal update
nix develop --command just check
```

During each milestone, iterate with the core suite only:

```bash
nix develop --command just test
```

Expected tail of a passing run (counts will differ):

```text
All 1xx tests passed (x.xxs)
Test suite shoko-core-test: PASS
```

To run only the new spec while developing, pass a tasty pattern:

```bash
nix develop --command cabal test shoko-core-test --test-show-details=direct --test-options='-p Idempotency'
```

After changing the result contract or golden fixtures (Milestones 2 and 3), regenerate and
review the goldens deliberately:

```bash
nix develop --command cabal build all
nix develop --command cabal exec -- runghc -XGHC2024 -XOverloadedStrings \
  -package=shoko-core -ishoko-core/test shoko-core/test/UpdateGoldens.hs
git diff -- shoko-core/test/golden/
nix develop --command python3 scripts/check-result-schema.py
```

The schema check should end with:

```text
Validated 7 run-result examples against schema v3
```

Milestone 4 process demonstration:

```bash
nix develop --command cabal run shoko-consumer-host -- explain concurrent-duplicates
nix develop --command cabal run shoko-consumer-host -- run idempotent-retry --config config/idempotency-demo.yaml
SHOKO_IMPLEMENTATION=non-idempotent nix develop --command cabal run shoko-consumer-host -- run concurrent-duplicates --config config/idempotency-demo.yaml; echo "exit $?"
```

The second command prints a report beginning with `Pass`; the third prints a report
beginning with `Fail` followed by `exit 1`.

Format before each commit and run the full gate at each milestone boundary:

```bash
nix develop --command just fmt
nix develop --command just check
```

Commit at each milestone with Conventional Commits and both trailers, for example:

```text
feat(core)!: check idempotent responses with result expectations

Add holds and agreeOn, evaluated once from earlier action results without an
evidence source, and move the result contract to schema v3.

ExecPlan: docs/plans/9-verify-idempotent-operations-with-result-checks-and-concurrent-actions.md
Intention: intention_01m5btnw9ne36v6p7qmemh32z1
```


## Validation and Acceptance

Milestone 1 is accepted when `just test` shows the `Idempotency` group passing with these
behaviors against the in-memory orders service: sequential retry Pass (idempotent); Fail
(non-idempotent, both by outcome mismatch and by `exactlyOnce` seeing two effects); payload
conflict accepted as `key-conflict` with one effect, Pass; unavailable effect history,
Unknown. The response-agreement workaround and its cost are recorded in Surprises &
Discoveries.

Milestone 2 is accepted when `agreeOn` passes for an idempotent retry, fails when the retry
returns a different order ID, and is Unknown/`PrerequisiteUnavailable` when a referenced node
did not complete; `inspectScenario` describes the check with a `ResultSubject` listing node
IDs and temporal `Immediately`; no binding handler is needed for the check; and `just check`
passes with regenerated v3 goldens validated against `schemas/run-result-v3.schema.json`.

Milestone 3 is accepted when, with three concurrent attempts sharing one key,
the idempotent binding yields Pass, the race-prone binding yields Fail on `one-creation`,
`one-effect`, and `same-order` on every run (confirm determinism by running
`nix develop --command cabal test shoko-core-test --test-options='-p concurrent'` 20 times in
a shell loop with no failures),
the attempts' recorded intervals overlap, a handler without `allowConcurrentCalls` produces
`ConcurrentCallsUnsupported` with zero acquisition, and every `InvalidConcurrentGroup` rule is
covered by a test.

Milestone 4 is accepted when `scripts/test-cli` (run by `just check`) proves the explain and
run behavior listed in the milestone, including exit 0 for the demo binding and exit 1 for
`SHOKO_IMPLEMENTATION=non-idempotent`, and `just check-docs` passes.

The whole plan is accepted when all four hold in one final tree. These are local in-memory
demonstrations. They do not establish that any real staging service is idempotent; a context
proves that by writing these scenarios against its own staging binding, which is outside
this plan.


## Idempotence and Recovery

Every step is additive or a type change caught by the compiler, and every command above can
be rerun. The golden update script overwrites `shoko-core/test/golden/*.json`; review
`git diff` before committing, and restore with `git checkout -- shoko-core/test/golden/` if
the diff contains unintended changes. Deleting `schemas/run-result-v2.schema.json` is
reversible from git history. If Milestone 3 must be abandoned after Milestone 2 is
committed, revert only the Milestone 3 commits; schema v3 as of Milestone 2 is complete on
its own, and the Decision Log should then record that v3 was frozen without
`concurrentGroup`. The race-prone test binding uses a bounded rendezvous timeout so that a
mistake cannot hang the suite.


## Interfaces and Dependencies

No new package dependencies are needed. `async` (already in `shoko-core`'s library
`build-depends`) provides the concurrent group threads; `Data.List.NonEmpty` from `base`
provides `NonEmpty`. Wherever this plan's design depends on a library API's exact behavior
(for example, `mapConcurrently` cancelling siblings on exception), confirm it in the
dependency source located with `mori registry show` rather than from memory.

Public additions, all re-exported from `shoko-core/src/Shoko.hs`:

```haskell
-- Shoko.Expectation
holds :: (Typeable a) => Text -> Input a -> Predicate a -> Expectations op ()
agreeOn :: (Typeable a, Eq b) => Text -> Text -> (a -> b) -> Ref a -> NonEmpty (Ref a) -> Expectations op ()
data Temporal = Eventually | Never | ExactlyOnce | Immediately

-- Shoko.Scenario
concurrently :: Text -> ScenarioBuilder op a -> ScenarioBuilder op a
data ExpectationSubject = ObservationSubject !OperationInfo | ResultSubject ![Text]
-- ExpectationDescription: field `operation` replaced by `subject :: ExpectationSubject`
-- NodeDescription and Step: new field `group :: Maybe Text`
-- DefinitionError: new constructor InvalidConcurrentGroup !Text

-- Shoko.Binding
allowConcurrentCalls :: Handler resource a -> Handler resource a
handlerAllowsConcurrentCalls :: Handler resource a -> Bool
-- PreflightError: new constructor ConcurrentCallsUnsupported !Text

-- Shoko.Result / Shoko.Evidence
data ExpectationEvidence = ObservationEvidence !Evidence | ResultEvidence !ResultCheckEvidence
data ResultCheckEvidence = ResultCheckEvidence {dependencies :: ![Text], evaluatedAt :: !MonotonicTime}
-- ExpectationResult.evidence :: ExpectationEvidence
```

These are breaking changes to `shoko-core` (hence `0.3.0.0` and the `!` commit marker).
`shoko-adapters` constructs handlers but does not pattern-match descriptions; confirm it
still compiles unchanged. Downstream context hosts must update pattern matches on the
changed records and accept schema v3; no such host exists in this repository besides
`shoko-cli/test/ConsumerHost`, and plan 7
(`docs/plans/7-verify-one-real-workflow-across-legacy-and-keiro-implementations.md`) will
consume the new API when it writes its staging host.
