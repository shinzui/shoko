---
id: 8
slug: compose-verifications-from-reusable-scenario-vocabulary-and-binding-blocks
title: "Compose verifications from reusable scenario, vocabulary, and binding blocks"
kind: exec-plan
created_at: 2026-10-19T02:21:45Z
intention: "intention_01m58zdv7je22tn3phntb65mqg"
provenance:
  created_by:
    model: "claude-opus-5-5"
    harness: "claude-code"
    at: 2026-10-19T02:21:45Z
---

# Compose verifications from reusable scenario, vocabulary, and binding blocks

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Shōko lets a domain owner describe a business workflow as a *scenario* (a typed, inspectable description of fixtures, actions, and expected consequences) and run it against a real system through a *binding* (the code that maps each described operation onto HTTP calls, SQL reads, or event-store reads). Today the smallest unit a scenario author can reuse is a single expectation. The pieces people actually want to reuse do not compose. These are "qualify an agent", "complete a registration and check its consequences", a bounded context's operation vocabulary, and an adapter's ready-made read handler. Reusing a scenario fragment twice is rejected as a duplicate. A fragment cannot carry its own expectations if anything follows it. Two contexts' vocabularies cannot be combined in one scenario. Each binding is a hand-written monolith whose metadata and handlers can silently disagree.

After this plan, a scenario author can do four things they cannot do today. They can write a fragment once and use it several times under distinct namespaces. A fragment can declare its own consequences, and more actions can follow it. They can combine the vocabularies and bindings of two bounded contexts with one combinator each. They can build a binding from per-operation handlers that adapters supply ready-made, each with its own evidence source and correlation requirement checked before anything runs. A scenario can also correlate different evidence sources by different business keys, for example `registrationId` for registration events and `accountId` for the account table, instead of forcing every source onto one key.

To see it working, run the core test suite. A new consumer module, `shoko-core/test/Consumer/Composed.hs`, builds a registration-shaped scenario from reusable blocks across two vocabularies and runs it to Pass. Then run the independent consumer host: `shoko-consumer-host explain composed-registration` prints namespaced node identifiers and two correlation keys, and `shoko-consumer-host run composed-registration` exits 0.

This plan should land before [plan 7](7-verify-one-real-workflow-across-legacy-and-keiro-implementations.md) writes its context-owned vocabulary, scenario, and binding in the bounded context's repository. Plan 7 has not started. Every breaking change here is cheapest while the only consumers of the API live inside this repository.


## Progress

- [ ] M1: Scenario and observation blocks. A fixture fragment reused twice under `namespace` inspects with distinct identifiers. A fragment using `expectAfterActions` can be followed by further actions. An operation that resolves an undeclared reference yields reason `UndeclaredOperation` instead of a generic unavailable source. Named predicate combinators produce derived predicate identifiers. `just test` passes and goldens are unchanged.
- [ ] M2: Handler-based bindings. `Binding` is built from per-operation `Handler` values that own their contract, evidence `Source`, and correlation requirement. `CallContext` and `BindingContract` are abstract. All four adapters export handler constructors. Every consumer, test, demo, and CLI path is migrated. Run results are schema v2. `just check` passes.
- [ ] M3: Vocabulary sums and binding combination. `(:+:)` combines two context vocabularies, `combineBindings` combines their bindings with correct acquisition and release order, and conflicting operation identifiers are a definition error. The composed consumer runs two vocabularies to Pass.
- [ ] M4: Scenario-owned, multi-key correlation. `correlate` and `propagateExecutionId` live inside the scenario with typed references. Observation handlers declare which key they need. Preflight rejects an undeclared key. Each expectation receives only its own key's value. Reports list every correlation. `CorrelationPlan` is gone from `resolveScenario` and `Entry`.
- [ ] M5: End-to-end host demonstration and durable records. The consumer host's `composed-registration` entry explains and runs through `runShokoCli`. Process checks cover it. `docs/core.md`, `docs/adapters.md`, and `docs/scenario-hosts.md` describe the composable API. ADR 0002 and ADR 0003 carry revisions. `just check` passes.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Keep the runtime model unchanged. Every evidence source still captures its baseline before the first fixture, actions still run as one fixed sequence, and every expectation still activates together after the last action. `expectAfterActions` only changes where an expectation may be written, not when it runs.
  Rationale: `shoko-core/src/Shoko/Runner.hs` already captures all baselines before any step (lines 128–148) and starts all expectations concurrently after `runSteps` (lines 148–170). Deferring an expectation that is written mid-scenario therefore has exactly the evidence semantics it would have if written at the end. Runtime branching and per-stage activation remain deferred by ADR 0002.
  Date: 2026-10-19

- Decision: Keep strict `expect`, and add a separately named `expectAfterActions` instead of relaxing `expect`.
  Rationale: `ActionAfterExpectations` protects readers from believing that an expectation written before an action is checked before that action. A distinct name makes deferral explicit at the call site.
  Date: 2026-10-19

- Decision: Make `CallContext`, `BindingContract`, `Handler`, `Source`, and `Binding` abstract, and expose plain accessor functions and smart constructors rather than record fields.
  Rationale: All packages enable `DuplicateRecordFields`, so shared field names such as `capabilities` and `source` are ambiguous at use sites. GHC also cannot solve `HasField` for the rank-N fields `resolveInput` and `substep`, so record-dot access is impossible for them. This is why every consumer currently pattern-matches positionally (`CallContext resolve _ _ selected _ _ (Clock now _ _ _)`), and any new field breaks every binding. Plain functions avoid both problems and let later milestones add context fields without breaking callers.
  Date: 2026-10-19

- Decision: Replace run-result v1 with v2 in M2, the first milestone that changes a wire tag, rather than editing v1 in place. Later milestones of this plan amend v2 freely until the plan completes. The decoder accepts only v2.
  Rationale: ADR 0003 makes the result JSON an explicitly versioned contract. v1 has no consumer outside this repository, and plan 7 has not produced retained acceptance artifacts, so there is no reason to keep a v1 decoder.
  Date: 2026-10-19

- Decision: Correlation keys are scenario-global and are not prefixed by `namespace`. Declaring the same key twice is a `DuplicateIdentifier` definition error.
  Rationale: A business key names one real-world entity for the whole run. Two instances of a block correlating the same key would describe two entities under one key, which is ambiguous and must be rejected.
  Date: 2026-10-19

- Decision: Remove `CorrelationPlan`, `BusinessKeyFrom`, `PropagatedExecutionId`, `businessKeyFromResult`, and the `MissingCorrelationReference` preflight error in M4. Do not keep them as deprecated aliases.
  Rationale: They refer to nodes by unprefixed string, which `namespace` breaks. They also live outside the scenario, so fragments cannot carry correlation. The package is experimental (version 0.1.0.0) with no external consumers yet.
  Date: 2026-10-19

- Decision: Keep this plan standalone rather than adding it to [MasterPlan 1](../masterplans/1-bootstrap-shoko-for-evidence-based-workflow-parity.md). Record in plan 7's context that it should consume the API produced here.
  Rationale: The work is a single-repository API refinement prompted by a design review. Whether to register it as a prerequisite of plan 7 is the MasterPlan owner's call.
  Date: 2026-10-19

- Decision: Defer checked outcome-tag vocabularies, where an operation would declare the tags it can return so that `accept` could be validated at inspection.
  Rationale: The change alters `OperationInfo` and the description digest without enabling composition. It is worth a follow-up plan once real context vocabularies exist.
  Date: 2026-10-19


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

The repository is a Cabal multi-package workspace with three packages. Build everything through the Nix development shell (`nix develop --command …`) as described in `docs/development.md`.

`shoko-core` (directory `shoko-core/`) is the public library. Its entry module `shoko-core/src/Shoko.hs` re-exports the construction API. The following terms are used throughout this plan.

A *vocabulary* is a Haskell GADT, meaning a data type whose constructors fix their result type. Each constructor names one business operation. For example, `Created :: Input Text -> Account Bool` in `shoko-core/test/Consumer/Account.hs` is an observation that yields a `Bool`. A vocabulary implements the class `Vocabulary` (`shoko-core/src/Shoko/Action.hs`). Its one method, `describeOperation`, returns an `OperationInfo` with four parts: a public operation identifier, the capabilities the operation needs (for example `ReadState` or `WriteState`), the scenario nodes its inputs depend on, and its named *substeps* (sub-requests of one composite action). Authors currently compute the dependencies by hand with `inputDependencies`.

A *scenario* (`shoko-core/src/Shoko/Scenario.hs`) is built in the `ScenarioBuilder` monad. `given key action` adds a fixture step and `act key action` adds an action step. Each returns a `Ref a`, an opaque symbolic reference to the step's eventual result. `fromRef` turns a `Ref` into an `Input a`. `Input` (`shoko-core/src/Shoko/Internal/Reference.hs`) is applicative, so inputs combine without reading runtime values. `expect` adds an `Expectations` group (`shoko-core/src/Shoko/Expectation.hs`): `eventually`, `never`, or `exactlyOnce` wrapped around an `Observation` (`shoko-core/src/Shoko/Observation.hs`). An observation is a predicate identifier, an operation, and a Boolean predicate on the operation's result. `scenarioParts` walks the builder without running IO and validates it. All node and expectation identifiers share one flat namespace, and duplicates are `DuplicateIdentifier` errors. Any step written after an `expect` is an `ActionAfterExpectations` error. `inspectScenario` returns the public `Description`, whose SHA-256 digest is computed in `shoko-core/src/Shoko/Internal/Digest.hs` with the version tag `"shoko-description-v1"`.

A *binding* (`shoko-core/src/Shoko/Binding.hs`) is currently one record, `Binding op resource`, with eight positional fields. They are a name, lifecycle capabilities, one `contract` function returning a `BindingContract` per operation and role, `acquire` and `release` for a resource, one `captureBaseline` function chosen by source name, and one `performAction` and one `performObservation` function that each pattern-match on every operation. A *role* is `FixtureOperation`, `ActionOperation`, or `ObservationOperation`. A `BindingContract` holds extra capabilities, cleanup capabilities, supported correlation strategies, an optional evidence source name, and a coverage strength. Coverage strength is `SampledState` (point-in-time reads) or `DurableHistory` (an append-only event history that can prove absence). A *baseline* is a source's position captured before any action, so later reads only count evidence produced during the run. Handlers receive a `CallContext`, which holds a reference resolver, a request deadline, the baseline, the run's single selected `Correlation`, a substep runner, the evidence cutoff, and the clock.

*Correlation* means scoping every evidence read to this run's business entity so that a read can never fall back to an unscoped search (ADR 0002). Today a run has exactly one `Correlation` (`shoko-core/src/Shoko/Correlation.hs`): either `ByBusinessKey keyName value` or `ByExecutionId runId`. It comes from a `CorrelationPlan` that is passed to `resolveScenario` from outside the scenario. `businessKeyFromResult "registrationId" "complete"` names the source node by string.

`resolveScenario` performs preflight: a pure check of the definition, binding contracts, capabilities, and correlation before any resource is acquired. `runScenario` in `shoko-core/src/Shoko/Runner.hs` is the single interpreter. It acquires the resource, captures one baseline per distinct source name, runs the steps, resolves correlation, and polls all expectations concurrently. It produces a `RunResult` (`shoko-core/src/Shoko/Result.hs`) with verdict `Pass`, `Fail`, or `Unknown` and typed `Reason`s. `shoko-core/src/Shoko/Result/Json.hs` encodes that result as JSON with `"schemaVersion": 1`, documented by `schemas/run-result-v1.schema.json`. Golden examples live in `shoko-core/test/golden/` and are regenerated by `shoko-core/test/UpdateGoldens.hs`.

`shoko-adapters` provides generic evidence adapters. `shoko-adapters/src/Shoko/Adapter/Postgres.hs` and its submodule `Postgres/Query.hs` provide scoped SQL reads. Every query's mandatory `Scope keyName column` must match the run's selected business-key name (`Query.hs:119–125`). `shoko-adapters/src/Shoko/Adapter/Http.hs` provides allowlisted HTTP endpoints, and a GET read injects the business key through the endpoint's declared scope. `shoko-adapters/src/Shoko/Adapter/Kiroku.hs` and `MessageDb.hs` provide bounded durable event reads through `shoko-adapters/src/Shoko/Adapter/EventStore/Internal.hs`, whose `CorrelationMode` is `BusinessKeyField keyName` or `ExecutionMetadata`. Each adapter exports a contract function, a baseline function, and an observe or action function that bindings call by hand. The adapters destructure `CallContext` positionally (`Postgres.hs:50`, `Http.hs:76`, `EventStore/Internal.hs:167`).

`shoko-cli` provides the host library `Shoko.Cli` (`shoko-cli/src/Shoko/Cli.hs`). Its `Registry` contains `Entry` values (`shoko-cli/src/Shoko/Cli/Registry.hs`), and each entry bundles a scenario, a `CorrelationPlan`, a logical input, named binding factories, and a metadata callback. `shoko-cli/app/Demo.hs` contains the labelled in-memory demos. `shoko-cli/test/ConsumerHost/Main.hs` is an independently compiled host executable, `shoko-consumer-host`, which `scripts/test-cli` exercises as real processes.

The design review that produced this plan confirmed the fragment problems with a probe against the current core:

```text
createAndCheck >> createAndCheck  → Left [ActionAfterExpectations, DuplicateIdentifier "create", DuplicateIdentifier "exists"]
create >> create                  → Left [DuplicateIdentifier "create"]
operation omitting inputDependencies → inspection accepted; at runtime resolveInput returns Left "undeclared-reference"
```

Several other current costs are visible in the tree. The same correlation guard is hand-written in `shoko-core/test/Consumer/Account.hs:87–94`, `shoko-cli/app/Demo.hs:61–68`, and `shoko-adapters/test/AdapterTests.hs:193–200`. `AdapterTests.hs:168` uses `postgresBaseline` for every source, which would silently mis-baseline a second kind of source. `ScenarioSpec.hs` deconstructs `Binding` and `BindingContract` positionally to inject a hidden capability.

Relevant ADRs follow. [ADR 0002](../adr/0002-keep-scenarios-inspectable-and-bindings-explicit.md) requires that descriptions never perform IO and that runtime values never choose branches absent from inspection. Composition stays a fixed action sequence followed by expectations, and arbitrary branching is deferred. Bindings declare their full operation inventory, capabilities, sources, and correlation support, which preflight checks before acquisition. The runner refuses undeclared operations. Correlation is explicit, and missing correlation yields `Unknown/CorrelationLost`, never a broad search. Contracts are role-aware. This plan keeps every one of those properties and moves correlation declaration into the scenario. [ADR 0003](../adr/0003-record-bounded-evidence-and-three-valued-results.md) defines the evidence semantics and the versioned result contract. This plan does not change temporal semantics; it introduces result schema v2. [ADR 0004](../adr/0004-gate-parity-on-real-workflows-and-context-owned-vocabulary.md) makes each bounded context own its vocabulary beside its domain code. A scenario spanning contexts therefore needs a way to combine vocabularies, which motivates M3. [ADR 0001](../adr/0001-use-jitsurei-standards-and-the-seihou-haskell-flake.md) defines the build and formatting practices used by the commands below. ADRs here are plain Markdown files under `docs/adr/`. They are not an OKF bundle, so revisions are appended as dated paragraphs in the existing style.


## Plan of Work

The work proceeds in five milestones. Each leaves the full test suite passing, and the composed example consumer grows with each one. M1 is additive. M2 is the single largest breaking change and should be done in one pass across all packages so the tree never has two binding styles. M3 and M4 build on M2's handler model.


### Milestone 1: Scenario and observation blocks

At the end of M1, scenario fragments are reusable, and observation predicates compose with derived identifiers. Nothing about bindings or the wire format changes, and the golden files remain byte-identical.

In `shoko-core/src/Shoko/Scenario.hs`, add two constructors to the `ScenarioBuilder` GADT: `Namespace :: Text -> ScenarioBuilder op a -> ScenarioBuilder op a` and `AddDeferred :: Expectations op () -> ScenarioBuilder op ()`. Change `collect` to carry the current prefix list. Inside `namespace "inviter"`, a step written with key `qualified` is recorded and referenced as `inviter.qualified`. Nested namespaces join with `.`. Expectation keys are prefixed the same way. Because `collect` assigns `Ref key` itself, references created inside a namespace carry their full prefixed key. References created outside keep theirs, so `fromRef` across a namespace boundary keeps working. Deferred expectations are collected into a separate list that `scenarioParts` appends after all other entries. They are validated as if they appeared at the end, so they never trigger `ActionAfterExpectations`, while a plain `expect` followed by a step still does. Export `namespace` and `expectAfterActions` from `Shoko.Scenario` and `Shoko`.

In `shoko-core/src/Shoko/Action.hs`, add an `OperationInfo` builder so dependencies are derived from the inputs rather than typed by hand. `declareOperation :: Text -> [Capability] -> OperationInfo` makes an operation with no dependencies or substeps, `dependsOn :: Input a -> OperationInfo -> OperationInfo` appends `inputDependencies`, and `withSubstep :: Text -> [Capability] -> OperationInfo -> OperationInfo` appends a substep. Keep the `OperationInfo` constructor for compatibility. Separately, make an undeclared reference visible as a cause. In `makeContext` (`shoko-core/src/Shoko/Runner.hs`), set an `IORef Bool` whenever `resolve` refuses an undeclared dependency. In `runSteps`, a set flag makes the action's final reason `UndeclaredOperation`. In `runExpectation`, a set flag ends the expectation as `Unknown` with reason `UndeclaredOperation`. This reuses an existing reason tag, which already covers an undeclared substep, so the wire format is unchanged.

In `shoko-core/src/Shoko/Observation.hs`, add a small predicate type. `Predicate a` holds a list of leaf names, a derived identifier, and a function. Its constructors are `predicate :: Text -> (a -> Bool) -> Predicate a`, `(.&&.)`, `(.||.)`, `negated`, and `onPart :: Text -> (b -> a) -> Predicate a -> Predicate b` (for example, to look inside `EventEvidence`). Add `observeThat :: op a -> Predicate a -> Observation op a`, whose stored predicate identifier is the derived one. Derived identifiers render as `(a and b)`, `(a or b)`, `not a`, and `part:a`. In `scenarioParts`, report `InvalidIdentifier` when any leaf name is empty or contains whitespace or parentheses. The existing `observe` remains unchanged.

Create `shoko-core/test/Consumer/Composed.hs` with an in-memory vocabulary and binding. Give it a fixture block `qualifiedAgent :: ScenarioBuilder op (Ref Text)`, used twice under `namespace "inviter"` and `namespace "invitee"`. Give it a block `completeRegistration :: Ref Text -> ScenarioBuilder op (Ref Text)` that acts and declares its consequences with `expectAfterActions`, followed by one more `act`. Add `ScenarioSpec` cases for namespaced identifiers, deferred expectations followed by an action, the retained strict `expect` error, and predicate identifiers. Add a `RuntimeSpec` case proving that a deferred expectation first polls after the final action completes, and one proving that an operation using `declareOperation`/`dependsOn` resolves its input while a hand-written `OperationInfo` that omits the dependency ends with `UndeclaredOperation`. Register `Consumer.Composed` in `shoko-core/shoko-core.cabal` under the test suite's `other-modules`.

Acceptance: `nix develop --command just test` passes with the new cases. `git diff --exit-code shoko-core/test/golden/` shows no change after regenerating goldens.


### Milestone 2: Handler-based bindings with owned sources

At the end of M2, a binding is a set of per-operation handlers. An adapter supplies a handler in one expression, and the contract, evidence source, and implementation for an operation can no longer disagree. This milestone breaks the public API and introduces result schema v2. Do it in one pass across `shoko-core`, `shoko-adapters`, and `shoko-cli`, and bump all three package versions to `0.2.0.0` (update the `Shoko.version` check in `shoko-core/test/Main.hs` and add a `0.2.0.0` entry to `shoko-core/CHANGELOG.md`).

Move the `CallContext` record into a new internal module `shoko-core/src/Shoko/Internal/Call.hs` (listed under `other-modules`) so only the runner constructs it. `Shoko.Binding` exports the abstract type and these functions: `resolveInput`, `requestDeadline`, `evidenceUntil`, `sourceBaseline`, `correlation`, `runSubstep`, and `callClock`. Also export `detachedCallContext :: Clock -> Integer -> Integer -> Maybe Baseline -> Maybe Correlation -> CallContext` for adapter unit tests; in it inputs never resolve and substeps are refused. Use the exact signatures in Interfaces and Dependencies. Make `BindingContract` abstract with `noRequirements`, `requiring`, `cleanupRequiring`, `contractCapabilities`, and `contractCleanup`. It no longer carries a source, coverage strength, or correlation support, because those move to the handler.

Introduce `Source resource` (an evidence source identifier, its coverage strength, and its baseline capture) with `newSource` and `sampledSource`. `sampledSource` records the host monotonic capture time with no cursor, which replaces the duplicated `postgresBaseline` and `httpBaseline`. Also introduce `CorrelationRequirement = RequiresBusinessKey Text | RequiresExecutionId`. Introduce the abstract `Handler resource a` with `actionHandler` and `observationHandler`, plus `focus` to adapt a handler to a larger resource, `handlerContract`, and `adjustContract`. The new `Binding op resource` is abstract and built with `binding name acquire release handlers`. `requiringLifecycle` adds lifecycle capabilities, and `adjustHandlers` lets tests wrap every handler, replacing the positional rebuild in `ScenarioSpec.hs`. Accessors `bindingName`, `bindingLifecycle`, and `bindingHandler` serve the CLI and runner.

Preflight in `resolveScenario` asks `bindingHandler role op` for every step and expectation. It reports `MissingHandler opId` when the handler is absent or has the wrong role, for example an action handler returned for an observation. It unions the handler contract's capabilities and cleanup with the operation's declared capabilities, exactly as today. An observation handler's correlation requirement must match the run's plan: `RequiresBusinessKey k` requires `BusinessKeyFrom k _`, and `RequiresExecutionId` requires `PropagatedExecutionId`. A mismatch is the existing `UnsupportedCorrelation opId`. Action and fixture handlers have no correlation requirement, because they never receive a correlation; the runner passes `Nothing` to actions today. Two observation handlers that use the same source identifier with different coverage strengths produce the new preflight error `InconsistentSource sourceId`. The runner captures one baseline per distinct observation source identifier, using the first handler's `Source` in declaration order. It no longer captures baselines for action sources, since nothing reads them.

Add a guard helper to `Shoko.Binding`: `guardCorrelation :: Input Text -> CallContext -> IO (ObservationOutcome a) -> IO (ObservationOutcome a)`. It resolves the operation's own key input, compares it with the context's business-key value, and returns `ObservationUnavailable "correlation-lost"` on mismatch or failure. Replace the three hand-written guards with it.

Each adapter gains handler constructors that keep its existing safety checks. `Shoko.Adapter.Postgres` adds `postgresSource :: Text -> Source Postgres` and `postgresObservation :: Text -> Query a -> Handler Postgres a`, whose requirement is `RequiresBusinessKey` of the query's `Scope` key. `Shoko.Adapter.Http` adds `httpActionHandler` and `httpObservationHandler`. Both return `Maybe (Handler Http a)` (`Nothing` for an endpoint that is not allowlisted, or for a read endpoint without a scope), and the read requirement comes from the endpoint scope's key. `Shoko.Adapter.Kiroku` adds `kirokuObservation :: Text -> EventQuery a -> Handler (Kiroku a) (EventEvidence a)`. `Shoko.Adapter.MessageDb` adds `messageDbObservation`, which returns `Maybe` because `ExecutionMetadata` is rejected. Each event handler's requirement comes from the query's `CorrelationMode`. Remove `postgresContract`, `postgresBaseline`, `httpContract`, `httpBaseline`, `kirokuContract`, `kirokuBaseline`, `messageDbContract`, and `messageDbBaseline` once every caller uses handlers. Change the adapters' positional `CallContext` matches to the accessor functions.

Migrate every binding: `shoko-core/test/Consumer/Account.hs`, `Consumer/DeliveryLedger.hs`, `Consumer/Composed.hs`, the core specs that rebuild bindings, `shoko-adapters/test/AdapterTests.hs`, `shoko-adapters/test/EventStore/Contract.hs`, `shoko-cli/app/Demo.hs`, and `shoko-cli/test/ConsumerHost/Main.hs`. Change `shoko-cli/src/Shoko/Cli.hs` so `explain` reads sources, coverage, and requirements from `bindingHandler` instead of the removed `contract` field.

Introduce result schema v2. In `Shoko.Result.Json`, emit and require `"schemaVersion": 2`, add the `inconsistent-source` preflight-error tag, and change the decode error text to `invalid shoko result v2`. Rename the schema with `git mv schemas/run-result-v1.schema.json schemas/run-result-v2.schema.json`, set its `schemaVersion` constants to 2, and add the new tag. Update every reference: `flake.module.nix` (lines 94 and 113), `scripts/check-result-schema.py:13`, `scripts/test-cli:25`, and `docs/core.md`. Search for any remaining `run-result-v1` or `schemaVersion.*1` with `rg`. Regenerate the goldens. Their digests do not change, because the description format is unchanged in M2.

Acceptance: `nix develop --command just check` passes, which includes the PostgreSQL, HTTP, Kiroku, Message DB, and CLI process suites. `rg -n 'CallContext [a-z_(]' shoko-*/src shoko-*/test shoko-cli/app` finds nothing outside `shoko-core/src/Shoko/Internal/Call.hs` and `shoko-core/src/Shoko/Runner.hs`. A new `PolicySpec` case shows that a binding whose observation handler requires `accountId` fails preflight with `UnsupportedCorrelation` under a `registrationId` plan, without acquisition. A new `PolicySpec` case shows `InconsistentSource`. The existing allocation-count assertions in `EventStore/Contract.hs` still show zero allocations for a denied policy.


### Milestone 3: Vocabulary sums and binding combination

At the end of M3, two bounded contexts' vocabularies and bindings combine without either knowing the other. Create `shoko-core/src/Shoko/Compose.hs`, exported from `Shoko`, defining `data (f :+: g) a = InL (f a) | InR (g a)` with `infixr 6 :+:` and an instance `(Vocabulary f, Vocabulary g) => Vocabulary (f :+: g)` that delegates. Provide `class Member f g where inject :: f a -> g a`, with instances for `f` itself, the left of a sum, and recursion into the right of a sum. This lets a context's constructors be lifted into any larger vocabulary with `inject`. If overlapping-instance resolution proves awkward, use explicit `inL`/`inR` and record the change in the Decision Log. Provide `combineBindings :: Text -> Binding f r1 -> Binding g r2 -> Binding (f :+: g) (r1, r2)`. Its handler lookup delegates by side through `focus fst` or `focus snd`, and its lifecycle capabilities are the union. Its acquisition acquires the left resource and immediately registers the left release through the registrar, then acquires the right. Its release releases only the right. The runner already runs the completed release first and registered finalizers in reverse order, so the result is reverse-acquisition cleanup. A failure acquiring the right still releases the left, and nothing is released twice. Each side's disposition appears as its own entry in the report's disposition list.

Operation identifiers are flat text, and two contexts could collide. In `scenarioParts`, add the definition error `ConflictingOperation opId` when two operations in one scenario share an identifier but differ in capabilities or substeps. Add its tag to the v2 schema and the JSON codec.

Extend `Consumer/Composed.hs` into two GADTs, `Registration` and `Accounts`, each with its own binding, combined through `:+:` and `combineBindings`. Add tests: the combined scenario runs to Pass. A right-side acquisition failure still yields a `Cleaned` disposition for the left. Release order is right then left, observed through an `IORef` log. Two vocabularies reusing an operation identifier with different capabilities report `ConflictingOperation`.

Acceptance: `nix develop --command just test` passes with these cases, and the goldens regenerate with no change, since the new tag appears only in its own test.


### Milestone 4: Scenario-owned, multi-key correlation

At the end of M4, a scenario declares its correlations itself, with typed references, and different observations can be scoped by different keys. In `shoko-core/src/Shoko/Scenario.hs`, add `correlate :: Text -> Input Text -> ScenarioBuilder op ()` and `propagateExecutionId :: ScenarioBuilder op ()`. Validation treats a correlation input's dependencies like any operation's, so an unknown or later reference is `UnresolvedReference`. A key declared twice is `DuplicateIdentifier`, and an empty key is `InvalidIdentifier`. Keys are not prefixed by `namespace`. `Description` gains `correlations :: [CorrelationDescription]`, each holding a key name (or the fixed name `execution-id`), a strategy, and dependency node identifiers, never values. The digest version string becomes `"shoko-description-v2"`, and correlations are included as a counted segment after expectations.

Remove `CorrelationPlan` and its constructors, `businessKeyFromResult`, the `CorrelationPlan` argument of `resolveScenario`, the `CorrelationPlan` field of `Shoko.Cli.Registry.Entry`, and the `MissingCorrelationReference` preflight error. Preflight now checks each observation handler's requirement against the scenario's declarations. A missing key is the new preflight error `UndeclaredCorrelation opId key`, which replaces the M2 use of `UnsupportedCorrelation` for this case; keep `UnsupportedCorrelation` only if another use remains, otherwise remove it and its tag. `PolicyReport.selectedCorrelation` becomes `correlationStrategies :: Set CorrelationStrategy`.

At activation the runner resolves each declared correlation independently. An expectation whose required key failed to resolve ends as `Unknown/CorrelationLost` without calling its handler. Expectations whose keys resolved still run. This is finer-grained than today, where one failure stops all expectations. The `CallContext` built for an observation exposes only that handler's required correlation through `correlation`, just as `resolveInput` exposes only declared dependencies. `VerificationResult.correlation :: Maybe Correlation` becomes `correlations :: [Correlation]`, in declaration order. Update the v2 schema and codec for the description `correlations`, the report `correlations` array, `policyReport.correlationStrategies`, and the `undeclared-correlation` tag. Remove the old fields and tags.

The adapters already name their key in `Scope`, the HTTP endpoint scope, and `BusinessKeyField`. They keep their defensive key-name check against the single correlation they now receive. Update the CLI text renderer and `explain` to list every correlation, and update `Demo.hs`, `ConsumerHost/Main.hs`, and all tests from `businessKeyFromResult`/`BusinessKeyFrom` to `correlate`. Extend `Consumer/Composed.hs` so registration observations require `registrationId` and the account observation requires `accountId`, which comes from a separate fixture's result.

Acceptance: `nix develop --command just check` passes. The composed scenario runs to Pass, and its report lists two correlations. A `PolicySpec` case shows `UndeclaredCorrelation "account-exists" "accountId"` when the scenario omits `correlate "accountId"`. A `RuntimeSpec` case shows one expectation `Unknown/CorrelationLost` while another, keyed differently, passes in the same run.


### Milestone 5: End-to-end host demonstration and durable records

At the end of M5, a scenario host built only from the public API demonstrates the composed workflow as real processes, and the durable documentation matches the new API. Add an entry `composed-registration` to `shoko-cli/test/ConsumerHost/Main.hs`, using two in-memory context vocabularies, `combineBindings`, reused namespaced blocks, `expectAfterActions`, predicate combinators, and two correlation keys. Extend `scripts/test-cli` to assert the following. `explain composed-registration` prints the identifiers `inviter.qualified` and `invitee.qualified` and both keys `registrationId` and `accountId`. `run composed-registration --format json` exits 0 with a v2 document whose `report.correlations` has two entries and that validates against `schemas/run-result-v2.schema.json`.

Rewrite the construction and binding sections of `docs/core.md` and the handler sections of `docs/adapters.md`, and update `docs/scenario-hosts.md`, the README outline, and `shoko-core/CHANGELOG.md`. Append dated revision paragraphs. In `docs/adr/0002-keep-scenarios-inspectable-and-bindings-explicit.md`, record namespaced blocks, deferred expectations under the unchanged runtime model, handler-based bindings with owned sources and correlation requirements, vocabulary sums with `combineBindings`, and scenario-owned multi-key correlation. In `docs/adr/0003-record-bounded-evidence-and-three-valued-results.md`, record result schema v2 and per-expectation `CorrelationLost`. Then complete Outcomes & Retrospective and the ADR distillation described in the skill's PLANS.md.

Acceptance: `nix develop --command just check` passes, including the new process assertions.


## Concrete Steps

Run every command from the repository root, `/Users/shinzui/Keikaku/bokuno/shoko`. Build and run the fast core suite while developing:

```bash
nix develop --command cabal build all
nix develop --command just test
```

The core suite ends with a line of this form, where the count grows with each milestone:

```text
All <n> tests passed (<t>s)
```
 Any `FAIL` line is a failure. For milestones that touch adapters or the CLI, also run the real-IO suites. They start their own loopback HTTP server, PostgreSQL clusters, and event stores, and need no external services:

```bash
nix develop --command just test-adapters
nix develop --command just test-event-stores
nix develop --command just test-cli
```

Regenerate goldens after a deliberate wire change, and inspect the diff:

```bash
nix develop --command cabal build all
nix develop --command cabal exec -- runghc -XGHC2024 -XOverloadedStrings \
  -package=shoko-core -ishoko-core/test shoko-core/test/UpdateGoldens.hs
git diff --stat -- shoko-core/test/golden/
```

In M1 and M3 the diff must be empty. In M2 it shows only `schemaVersion` changes, plus any newly added preflight example. In M4 it shows description digests, correlations, and policy fields.

Format and run the full gate before each milestone commit:

```bash
nix develop --command just fmt
nix develop --command just check
```

Commit at each milestone boundary with a Conventional Commits message and both trailers, for example:

```text
feat(core)!: build bindings from per-operation handlers

Bindings now map each operation to a Handler owning its contract,
evidence source, and correlation requirement. Run results move to
schema v2 for the inconsistent-source preflight error.

ExecPlan: docs/plans/8-compose-verifications-from-reusable-scenario-vocabulary-and-binding-blocks.md
Intention: intention_01m58zdv7je22tn3phntb65mqg
```


## Validation and Acceptance

The plan is accepted when all of the following hold in one final-candidate tree. `nix develop --command just check` passes. A fixture fragment used twice under different namespaces inspects without error and reports identifiers such as `inviter.qualified` and `invitee.qualified`. A fragment that declares consequences with `expectAfterActions` can be followed by another `act`, and its expectation's first poll happens after that later action, as shown by `RuntimeSpec`. Two context vocabularies combined with `:+:` and `combineBindings` run to Pass, and cleanup runs in reverse acquisition order. A binding handler that requires a correlation key the scenario never declared is rejected in preflight with `UndeclaredCorrelation` and zero resource acquisitions. Within one run, an expectation whose key failed to resolve is `Unknown/CorrelationLost` while a differently keyed expectation passes. The process check against `shoko-consumer-host` shows `explain composed-registration` listing namespaced identifiers and both correlation keys, and `run composed-registration --format json` exiting 0 with a v2 document that validates against `schemas/run-result-v2.schema.json`.

The early integration check is M2's migration of `shoko-adapters/test/AdapterTests.hs`, because that binding combines HTTP actions with both SQL and HTTP reads. Migrate it first, before the other adapters' handler constructors are finalized. If `focus`, `sampledSource`, or `httpObservationHandler` are awkward there, revise the interfaces before migrating the rest, and record the change in the Decision Log.

Checked outcome-tag vocabularies are proposed follow-up scope, not required acceptance.


## Idempotence and Recovery

Every step is a source edit under version control, and every command above is safe to repeat. Golden regeneration is deterministic and overwrites only `shoko-core/test/golden/*.json`. The schema rename uses `git mv`, so `git checkout -- schemas/` together with renaming back restores v1 if M2 is abandoned. Each milestone ends in its own commit, so a milestone can be reverted with `git revert <commit>` without disturbing earlier ones. If M2 is interrupted midway, the tree may not compile. Finish the migration rather than committing a partial one; `cabal build all` lists the remaining call sites as type errors. The real-IO suites create temporary clusters and directories and remove them on exit. Failed adapter runs keep their logs under `.dev/adapter-tests/` for inspection, and that directory can be deleted at any time.


## Interfaces and Dependencies

No new third-party dependency is required. The work uses `base`, `containers`, `text`, `effectful-core`, and `aeson`, which are already in the build. The following public signatures must exist at the end of the plan. Module paths are under `shoko-core/src/` unless stated otherwise.

In `Shoko.Scenario`, re-exported from `Shoko`:

```haskell
namespace :: Text -> ScenarioBuilder op a -> ScenarioBuilder op a
expectAfterActions :: Expectations op () -> ScenarioBuilder op ()
correlate :: Text -> Input Text -> ScenarioBuilder op ()
propagateExecutionId :: ScenarioBuilder op ()

data CorrelationDescription = CorrelationDescription
  { correlationKey :: !Text,
    strategy :: !CorrelationStrategy,
    dependencies :: ![Text]
  }

data DefinitionError
  = InvalidIdentifier
  | DuplicateIdentifier !Text
  | UnresolvedReference !Text
  | ActionAfterExpectations
  | EmptyOutcomeContract !Text
  | EmptyExpectations
  | ConflictingOperation !Text
```

In `Shoko.Action`:

```haskell
declareOperation :: Text -> [Capability] -> OperationInfo
dependsOn :: Input a -> OperationInfo -> OperationInfo
withSubstep :: Text -> [Capability] -> OperationInfo -> OperationInfo
```

In `Shoko.Observation`:

```haskell
data Predicate a
predicate :: Text -> (a -> Bool) -> Predicate a
(.&&.), (.||.) :: Predicate a -> Predicate a -> Predicate a
negated :: Predicate a -> Predicate a
onPart :: Text -> (b -> a) -> Predicate a -> Predicate b
observeThat :: op a -> Predicate a -> Observation op a
```

In `Shoko.Binding`, where `CallContext`, `BindingContract`, `Source`, `Handler`, and `Binding` are abstract:

```haskell
data CorrelationRequirement = RequiresBusinessKey !Text | RequiresExecutionId

resolveInput :: CallContext -> Input a -> Either Text a
requestDeadline :: CallContext -> Integer
evidenceUntil :: CallContext -> Integer
sourceBaseline :: CallContext -> Maybe Baseline
correlation :: CallContext -> Maybe Correlation
runSubstep :: CallContext -> Text -> IO a -> IO (Either Text a)
callClock :: CallContext -> Clock
detachedCallContext :: Clock -> Integer -> Integer -> Maybe Baseline -> Maybe Correlation -> CallContext

noRequirements :: BindingContract
requiring :: [Capability] -> BindingContract -> BindingContract
cleanupRequiring :: [Capability] -> BindingContract -> BindingContract
contractCapabilities :: BindingContract -> Set Capability
contractCleanup :: BindingContract -> Set Capability

newSource :: Text -> CoverageStrength -> (resource -> Clock -> IO (Either Text Baseline)) -> Source resource
sampledSource :: Text -> Source resource
sourceId :: Source resource -> Text

actionHandler :: BindingContract -> (resource -> CallContext -> IO (ActionOutcome a)) -> Handler resource a
observationHandler ::
  BindingContract -> CorrelationRequirement -> Source resource ->
  (resource -> CallContext -> IO (ObservationOutcome a)) -> Handler resource a
focus :: (outer -> inner) -> Handler inner a -> Handler outer a
handlerContract :: Handler resource a -> BindingContract
adjustContract :: (BindingContract -> BindingContract) -> Handler resource a -> Handler resource a

binding ::
  Text ->
  ((IO Disposition -> IO ()) -> IO resource) ->
  (resource -> IO Disposition) ->
  (forall a. OperationRole -> op a -> Maybe (Handler resource a)) ->
  Binding op resource
requiringLifecycle :: [Capability] -> Binding op resource -> Binding op resource
adjustHandlers ::
  (forall a. OperationRole -> op a -> Maybe (Handler resource a) -> Maybe (Handler resource a)) ->
  Binding op resource -> Binding op resource
bindingName :: Binding op resource -> Text
bindingLifecycle :: Binding op resource -> Set Capability
bindingHandler :: Binding op resource -> OperationRole -> op a -> Maybe (Handler resource a)

guardCorrelation :: Input Text -> CallContext -> IO (ObservationOutcome a) -> IO (ObservationOutcome a)

resolveScenario ::
  Vocabulary op =>
  Environment -> RunOptions -> Binding op resource -> Scenario op ->
  Either [PreflightError] (ResolvedScenario op resource)
```

`PreflightError` gains `InconsistentSource !Text` and `UndeclaredCorrelation !Text !Text`, and loses `MissingCorrelationReference`. `PolicyReport` becomes `{ requiredCapabilities :: Set Capability, correlationStrategies :: Set CorrelationStrategy }`. `VerificationResult` replaces `correlation :: Maybe Correlation` with `correlations :: [Correlation]`. `Description` gains `correlations :: [CorrelationDescription]`.

In the new module `Shoko.Compose`, re-exported from `Shoko`:

```haskell
data (f :+: g) a = InL (f a) | InR (g a)
infixr 6 :+:
instance (Vocabulary f, Vocabulary g) => Vocabulary (f :+: g)
class Member f g where inject :: f a -> g a
combineBindings :: Text -> Binding f r1 -> Binding g r2 -> Binding (f :+: g) (r1, r2)
```

In `shoko-adapters`:

```haskell
-- Shoko.Adapter.Postgres
postgresSource :: Text -> Source Postgres
postgresObservation :: Text -> Query a -> Handler Postgres a
-- Shoko.Adapter.Http
httpActionHandler ::
  HttpConfig -> Text -> (CallContext -> Either Text HttpPayload) ->
  (Int -> ByteString -> Either HttpFailure (Text, a)) -> Maybe (Handler Http a)
httpObservationHandler ::
  HttpConfig -> Text -> (CallContext -> Either Text HttpPayload) ->
  (Int -> ByteString -> Either HttpFailure a) -> Maybe (Handler Http a)
-- Shoko.Adapter.Kiroku
kirokuObservation :: Text -> EventQuery a -> Handler (Kiroku a) (EventEvidence a)
-- Shoko.Adapter.MessageDb
messageDbObservation :: Text -> EventQuery a -> Maybe (Handler (MessageDb a) (EventEvidence a))
```

In `shoko-cli`, `Shoko.Cli.Registry.Entry` loses its `CorrelationPlan` field and becomes `Entry (Scenario op) LogicalInput [(Text, HostConfig -> Maybe Credentials -> SomeBinding op)] (HostConfig -> IO (Either Text (Maybe Text, Maybe TargetIdentity)))`.

Downstream, [plan 7](7-verify-one-real-workflow-across-legacy-and-keiro-implementations.md) should write its context vocabulary and binding against these interfaces. No other plan's accepted outputs depend on the interfaces this plan removes.
