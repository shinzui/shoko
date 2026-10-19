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
  revisions:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-19T02:33:54Z
      mode: "update"
      note: "Validate and repair handler abstraction, effectful input resolution, source ownership, composition cleanup, and correlation API contracts."
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-10-19T03:08:37Z
      mode: "implement"
      note: "Implement reusable blocks, handler-based bindings, vocabulary composition, and scenario-owned correlation with acceptance checks."
  reviews:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-19T02:36:45Z
      verdict: "approved"
      note: "Approved after API revisions against core, adapters, CLI, and ADRs; 40 baseline core tests and Member API probe pass; proposed feature acceptance remains implementation work."
---

# Compose verifications from reusable scenario, vocabulary, and binding blocks


This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture


Shōko lets a domain owner describe a business workflow as a *scenario* (a typed, inspectable description of fixtures, actions, and expected consequences) and run it against a real system through a *binding* (the code that maps each described operation onto HTTP calls, SQL reads, or event-store reads). Today the smallest unit a scenario author can reuse is a single expectation. The pieces people actually want to reuse do not compose. These are "qualify an agent", "complete a registration and check its consequences", a bounded context's operation vocabulary, and an adapter's ready-made read handler. Reusing a scenario fragment twice is rejected as a duplicate. A fragment cannot carry its own expectations if anything follows it. Two contexts' vocabularies cannot be combined in one scenario. Each binding is a hand-written monolith whose metadata and handlers can silently disagree.

After this plan, a scenario author can compose reusable workflows in the following ways. They can write a fragment once and use it several times under distinct namespaces. A fragment can declare its own consequences, and more actions can follow it. They can combine the vocabularies and bindings of two bounded contexts with one combinator each. They can build a binding from per-operation handlers that adapters supply ready-made, each with its own evidence source and correlation requirement checked before anything runs. A scenario can also correlate different evidence sources by different business keys, for example `registrationId` for registration events and `accountId` for the account table, instead of forcing every source onto one key. Distinct instances of the same block may also use the same business-key name with different values: observations select explicit, namespaced correlation handles. Existing concrete-vocabulary blocks lift into larger vocabularies without being rewritten.

To see it working, run the core test suite. A new consumer module, `shoko-core/test/Consumer/Composed.hs`, builds a registration-shaped scenario from reusable blocks across two vocabularies and runs it to Pass. Then run the independent consumer host: `shoko-consumer-host explain composed-registration` prints namespaced node identifiers and three correlation instances across two business-key names, and `shoko-consumer-host run composed-registration` exits 0.

This plan should land before [plan 7](7-verify-one-real-workflow-across-legacy-and-keiro-implementations.md) writes its context-owned vocabulary, scenario, and binding in the bounded context's repository. Plan 7 has unfinished context-host milestones, while its manifest and identity tooling already exist in `integration/` and `scripts/`. Migrate affected consumers found in the working tree rather than assuming no work has started. Keep the independent workflow-manifest and identity-artifact schema versions unchanged.


## Progress


- [x] M1 (2026-10-19): Scenario and observation blocks. Verified all 44 core tests, the full `nix develop --command just check` gate, and byte-identical regenerated goldens. A fixture fragment reused twice under `namespace` inspects with distinct identifiers. A fragment using `expectAfterActions` can be followed by further actions. Named predicate combinators produce derived predicate identifiers. `just test` passes and goldens are unchanged.
- [x] M2 (2026-10-19): Handler-based bindings. Verified 51 core tests, all real adapter and CLI suites, positive/negative type fixtures, seven schema examples, and the full `just check` gate. Golden JSON differs only by `schemaVersion`. `Binding` is built from per-operation `Handler` values that own their contract, evidence `Source`, and correlation requirement. `CallContext` and `BindingContract` are abstract. Effectful reference resolution records undeclared accesses even if a handler ignores the error. Distinct identifier/time types prevent accidental interchange, and typed handler errors retain their causes through preflight while input errors remain distinguishable during execution. All four adapters export handler constructors. Every consumer, test, demo, and CLI path is migrated. Run results are schema v2. `just check` passes.
- [x] M3 (2026-10-19): Vocabulary sums and binding combination. Verified 63 core tests and the full `just check` gate, including the two-context consumer, hoisting laws, preflight collisions, nested cleanup, cancellation, and shared cleanup deadline. Regenerated goldens are unchanged. `(:+:)` combines two context vocabularies, `combineBindings` combines their bindings with correct acquisition and release order, and conflicting operation identifiers are a definition error. Concrete-vocabulary workflow blocks lift with `hoistScenarioBuilder` and compose without losing their typed return values. The composed consumer runs two vocabularies to Pass.
- [ ] M4: Scenario-owned correlation handles. Two instances of a self-contained block declare the same business-key name under distinct namespaced handles; each observation explicitly selects its instance with `correlatedBy`. Preflight checks selection, declaration, and handler compatibility. Reports identify each resolved instance. `CorrelationPlan` is gone from `resolveScenario` and `Entry`.
- [ ] M5: End-to-end host demonstration and durable records. The consumer host reuses one concrete workflow in two independent scenarios and twice inside `composed-registration`, which explains and runs through `runShokoCli`. Process checks cover it. `docs/core.md`, `docs/adapters.md`, and `docs/scenario-hosts.md` describe the composable API. ADR 0002 and ADR 0003 carry revisions. `just check` passes.


## Surprises & Discoveries


API validation, 2026-10-19: `shoko-core/src/Shoko/Runner.hs:makeContext` implements a pure `Input a -> Either Text a` resolver. The originally proposed `IORef` write cannot be implemented with that signature without hidden effects. M2 now changes the accessor to return `IO (Either InputResolutionError a)` and migrates callback types with it; M1 stays additive.

`shoko-cli/src/Shoko/Cli.hs:inspectBinding` consumes source and coverage metadata, but the original abstract handler API exposed neither. The revised API includes read-only metadata accessors and internal constructor access for the runner. `Shoko.Adapter.Postgres.Query` also hides `Query` constructors, so deriving its key requires a new `queryScope` accessor.

`shoko-adapters/src/Shoko/Adapter/EventStore/Internal.hs:capture` stores a baseline token in one reader's `IORef`; `observeEvents` requires that exact baseline. Two distinct readers with the same source label and coverage strength cannot safely share the first reader's baseline. M2 documents source sharing as an explicit binding-author obligation, and M3 rejects cross-binding source-label collisions before acquisition.

Baseline validation on 2026-10-19: `nix develop --command just test` passed all 40 current core tests. This verifies the current tree, not implementation of the proposed API. A standalone GHC2024 probe of the exact `Member` instances below also compiled and ran successfully for identity, left, right, three-context injection, and a constrained reusable block; it printed `Member API probe passed`.


Composition follow-up validation, 2026-10-19: a standalone GHC2024 type-check probe compiled the exact public consumer example below against minimal type scaffolding and structural implementations of the four vocabulary maps, including builder continuations, namespace nodes, and correlation declarations. This checks type compatibility and result preservation in the proposed shape; it is not evidence that the feature is implemented or that runtime isolation passes. The new public-consumer, hoisting-law, correlation-isolation, and process checks remain implementation acceptance.


Haskell-conventions validation, 2026-10-19: the revised consumer example type-checked under GHC2024 using the explicit identifier wrappers and `hoist…` functions in minimal scaffolding. Four negative probes rejected alias/key, source/key, timestamp/duration, and ID/handle substitutions. This validates the proposed type boundaries only; real public-package integration, typed-error propagation, serialization, and runtime acceptance remain M2–M5 work.


Implementation discovery, 2026-10-19: the public `Duration` constructor accepts whole milliseconds, while existing inclusivity probes exercise microsecond boundaries. Production and public fake clocks use the new time types; a test-local microsecond clock preserves the original boundary probes without rounding them. The M2 HTTP/SQL consumer compiles using focused sources and effectful payload builders with no public-interface change. Direct event adapter deadline probes obtain their baseline through a public runner report instead of retaining removed baseline helpers. Namespace collection also preserves rejection of empty local node/expectation IDs after qualification.


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

- Decision: Supersede the initial one-declaration-per-business-key design. Give every business correlation a namespaced instance identifier and an abstract `CorrelationRef`; keep its semantic business-key name unchanged. Observations select handles explicitly.
  Rationale: Two registrations in one run share the key name `registrationId` but identify different entities. Distinct handles remove the ambiguity without changing adapter SQL columns, HTTP scopes, or event fields.
  Date: 2026-10-19

- Decision: Remove `CorrelationPlan`, `BusinessKeyFrom`, `PropagatedExecutionId`, `businessKeyFromResult`, and the `MissingCorrelationReference` preflight error in M4. Do not keep them as deprecated aliases.
  Rationale: The legacy `businessKeyFromResult` helper refers to nodes by unprefixed string, which `namespace` breaks. `CorrelationPlan` itself already accepts typed inputs, but lives outside the scenario, so fragments cannot carry its declaration. The package is experimental (version 0.1.0.0) with no external consumers yet.
  Date: 2026-10-19

- Decision: Keep this plan standalone rather than adding it to [MasterPlan 1](../masterplans/1-bootstrap-shoko-for-evidence-based-workflow-parity.md). Record in plan 7's context that it should consume the API produced here.
  Rationale: The work is a single-repository API refinement prompted by a design review. Whether to register it as a prerequisite of plan 7 is the MasterPlan owner's call.
  Date: 2026-10-19

- Decision: Defer checked outcome-tag vocabularies, where an operation would declare the tags it can return so that `accept` could be validated at inspection.
  Rationale: The change alters `OperationInfo` and the description digest without enabling composition. It is worth a follow-up plan once real context vocabularies exist.
  Date: 2026-10-19


- Decision: Make reference resolution explicitly effectful in M2, expose handler metadata separately from execution, and retain constructors only in internal core modules.
  Rationale: Sticky undeclared-access diagnostics require IO; pure inspection must remain allocation-free, while the runner and composition module need constructor access without exporting executable internals to clients.
  Date: 2026-10-19

- Decision: Reject duplicate source labels across component bindings, including equal-coverage labels; require distinct labels for distinct readers within a binding. Combine resource lifetimes under masking and preserve the existing shared cleanup deadline.
  Rationale: Text equality cannot establish equality of capture functions or reader state. Silent baseline reuse across independently acquired resources is incorrect, and acquisition-to-registration gaps can leak resources on cancellation.
  Date: 2026-10-19

- Decision: A scenario's execution-ID declaration makes the run ID available to action handlers through a separate accessor. It does not establish remote propagation by itself. Business-key names describe adapter semantics; correlation instance IDs identify declarations. Reserve the global instance ID `execution-id` for the execution strategy, and make repeated requests for that one run-wide handle idempotent.
  Rationale: Observation-specific correlation cannot carry a pre-action propagation value, and two strategies must not produce indistinguishable declaration keys.
  Date: 2026-10-19


- Decision: Offer result-preserving vocabulary maps alongside `Member`: map actions, observations, expectation groups, and scenario builders with `forall x. f x -> g x`.
  Rationale: A context can export an ordinary concrete-vocabulary workflow and let consumers embed it with `InL`, `InR`, or `inject`. Reuse must not require redesigning the producer's API around a larger vocabulary.
  Date: 2026-10-19

- Decision: A reusable workflow block is a `ScenarioBuilder op a`, possibly a function of typed inputs. A finished `Scenario op` remains a verification boundary with its own ID, revision, run, and report; it is not concatenated or unwrapped by this API.
  Rationale: Composition happens before finalization so returned references and handles connect blocks explicitly. Independent scenarios reuse the same builder definition and run with separate resources. Merging finished scenarios would require new identity, revision, lifecycle, and scheduling semantics.
  Date: 2026-10-19


- Decision: Use separate newtypes for correlation aliases, business-key names, correlation IDs, source IDs, and absolute monotonic timestamps. Keep existing `Duration` for elapsed budgets and wire representations as strings or integer microseconds.
  Rationale: The compiler should reject swapped semantic identifiers and timestamps used as durations. This is a targeted boundary improvement; operation labels, titles, and private payload values remain unchanged.
  Date: 2026-10-19

- Decision: Preserve typed input-resolution and adapter-handler construction failures. Binding lookup returns `Either HandlerBuildError (Maybe (Handler resource a))`, distinguishing invalid construction from unsupported operations.
  Rationale: Collapsing construction errors into `Nothing` loses useful preflight diagnostics. Errors contain public identifiers and closed tags, never raw transport details or input values.
  Date: 2026-10-19

- Decision: Name the vocabulary transformations `hoistAction`, `hoistObservation`, `hoistExpectations`, and `hoistScenarioBuilder`, without aliases for the earlier proposed names.
  Rationale: These transform the operation vocabulary while preserving the result parameter; `fmap` remains the result-value transformation. `Member` stays optional over explicit `InL`/`InR` hoisting.
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


A *workflow block* is the existing `ScenarioBuilder op a` abstraction used as a reusable definition, not a new wrapper type. Its result `a` can contain `Ref`s and correlation handles for later blocks. Export the builder (or an input-taking function) beside a thin named `Scenario` wrapper. A scenario is finalized by `scenario id title revision (block >> pure ())`; each independent wrapper owns its revision, which must change when the block's semantics change. There is no `Semigroup Scenario`, `appendScenario`, or scenario-to-builder extraction in this plan. Reuse across scenarios means sharing the builder definition; reuse within one scenario means composing builders before finalization. All deferred expectations still run after all actions, so this API does not introduce intermediate verification checkpoints.


## Plan of Work


The work proceeds in five milestones. Each leaves the full test suite passing, and the composed example consumer grows with each one. M1 is additive. M2 is the single largest breaking change and should be done in one pass across all packages so the tree never has two binding styles. M3 and M4 build on M2's handler model.


### Milestone 1: Scenario and observation blocks


At the end of M1, scenario fragments are reusable, and observation predicates compose with derived identifiers. Nothing about bindings or the wire format changes, and the golden files remain byte-identical.

In `shoko-core/src/Shoko/Scenario.hs`, add two constructors to the `ScenarioBuilder` GADT: `Namespace :: Text -> ScenarioBuilder op a -> ScenarioBuilder op a` and `AddDeferred :: Expectations op () -> ScenarioBuilder op ()`. Change `collect` to carry the current prefix list. Inside `namespace "inviter"`, a step written with key `qualified` is recorded and referenced as `inviter.qualified`. Nested namespaces join with `.`. Expectation keys are prefixed the same way. Because `collect` assigns `Ref key` itself, references created inside a namespace carry their full prefixed key. References created outside keep theirs, so `fromRef` across a namespace boundary keeps working. Keep entries tagged as strict or deferred during collection. Only a strict expectation starts the `ActionAfterExpectations` restriction; validate deferred dependencies against the final set of step identifiers. Preserve the relative declaration order of all expectations in descriptions and reports instead of moving deferred entries behind later strict entries. A plain `expect` followed by a step still fails. Reject empty namespace components with `InvalidIdentifier`; do not prefix operation IDs, predicate IDs, or substep IDs. Dot-joined collisions still produce `DuplicateIdentifier`. Restore the outer prefix when leaving a nested namespace, including when the block returns a `Ref`. Export `namespace` and `expectAfterActions` from `Shoko.Scenario` and `Shoko`.

In `shoko-core/src/Shoko/Action.hs`, add an `OperationInfo` builder so dependencies are derived from the inputs rather than typed by hand. `declareOperation :: Text -> [Capability] -> OperationInfo` makes an operation with no dependencies or substeps, `dependsOn :: Input a -> OperationInfo -> OperationInfo` appends `inputDependencies`, and `withSubstep :: Text -> [Capability] -> OperationInfo -> OperationInfo` appends a substep. Keep the `OperationInfo` constructor for compatibility. Sticky undeclared-reference diagnostics move to M2 with its effectful resolver; do not hide IO in M1's pure resolver.

In `shoko-core/src/Shoko/Observation.hs`, add a small predicate type. `Predicate a` holds a list of leaf names, a derived identifier, and a function. Its constructors are `predicate :: Text -> (a -> Bool) -> Predicate a`, `(.&&.)`, `(.||.)`, `negated`, and `onPart :: Text -> (b -> a) -> Predicate a -> Predicate b` (for example, to look inside `EventEvidence`). Add `observeThat :: op a -> Predicate a -> Observation op a`, whose stored predicate identifier is the derived one. Derived identifiers render as `(a and b)`, `(a or b)`, `not(a)`, and `part:(a)`, recursively parenthesizing nested expressions. Use `infixr 3 .&&.` and `infixr 2 .||.`. Store predicate validation metadata in `Observation` when constructed by `observeThat`; `scenarioParts` must not try to recover leaf names by parsing the rendered identifier. Both leaf names and `onPart` labels must be nonempty and contain only ASCII letters, digits, `_`, `-`, or `.`; report `InvalidIdentifier` otherwise. This excludes delimiters from labels and prevents distinct expression trees from rendering the same identifier. The existing `observe` remains unchanged.

Create `shoko-core/test/Consumer/Composed.hs` with an in-memory vocabulary and binding. Give it a fixture block `qualifiedAgent :: ScenarioBuilder Composed (Ref Text)`, used twice under `namespace "inviter"` and `namespace "invitee"`. Give it a block `completeRegistration :: Ref Text -> ScenarioBuilder Composed (Ref Text)` that acts and declares its consequences with `expectAfterActions`, followed by one more `act`. Add `ScenarioSpec` cases for namespaced identifiers, deferred expectations followed by an action, the retained strict `expect` error, and predicate identifiers. Add a `RuntimeSpec` case proving that a deferred expectation first polls after the final action completes, and cases proving that references returned from nested namespaces resolve outside them and external references resolve inside them. Verify mixed strict/deferred expectation order and invalid namespace/predicate labels. A block is monomorphic in M1; M3 lifts that existing block with `hoistScenarioBuilder` and separately demonstrates the optional `Member` authoring style. Register `Consumer.Composed` in `shoko-core/shoko-core.cabal` under the test suite's `other-modules`.

Acceptance: `nix develop --command just test` passes with the new cases. `git diff --exit-code shoko-core/test/golden/` shows no change after regenerating goldens.


### Milestone 2: Handler-based bindings with owned sources


At the end of M2, a binding is a set of per-operation handlers. An adapter supplies a handler in one expression, and each handler packages its contract, evidence source, and implementation together. Pure metadata cannot prove that arbitrary IO or an independently acquired resource obeys that contract; enforce the concrete adapter consistency checks below. This milestone breaks the public API and introduces result schema v2. Do it in one pass across `shoko-core`, `shoko-adapters`, and `shoko-cli`, and bump all three package versions to `0.2.0.0` (update the `Shoko.version` check in `shoko-core/test/Main.hs` and add a `0.2.0.0` entry to `shoko-core/CHANGELOG.md`).

Introduce `shoko-core/src/Shoko/Identifier.hs`, an exposed module re-exported by `Shoko`, defining the `CorrelationAlias`, `BusinessKeyName`, `CorrelationId`, and `SourceId` newtypes specified below. Export explicit constructors and total text accessors, derive `Eq`, `Ord`, `Show`, and `Generic` with explicit strategies, and do not derive `IsString`. These types distinguish categories; they do not claim nonempty/valid contents. Existing scenario, preflight, and adapter validation still reject invalid values. Calls use wrappers such as `BusinessKeyName "registrationId"`; passing an already-typed alias where a business key is expected must fail compilation.

Migrate source identity end to end: `Source`, `Baseline.source`, `Evidence.source`, runner baseline-map keys, adapter reader source parameters/state, and `InconsistentSource` use `SourceId`. HTTP handlers wrap their public endpoint name as a `SourceId` when constructing the sampled source. Migrate semantic names in `Correlation`/`CorrelationRequirement`, the temporary M2 `CorrelationPlan`, PostgreSQL `Scope`, HTTP endpoint scopes, and event `BusinessKeyField` to `BusinessKeyName`. Correlation aliases and instance IDs enter use in M4. Adapter query compilation unwraps names only at the transport/JSON-key boundary; namespace qualification builds a `CorrelationId`, never a `BusinessKeyName`. Source and correlation string encodings stay unchanged. Do not mechanically wrap unrelated operation/node labels, fixture values, cursor tokens, or endpoint names.

In `shoko-core/src/Shoko/Clock.hs`, introduce `MonotonicTime` for an absolute timestamp in host-monotonic microseconds. Keep `Duration` for relative budgets. Migrate `Clock.monotonic`, `sleepUntil`, and `bounded`, context deadlines, baseline capture times, coverage intervals, adapter sample timestamps, and evidence/result monotonic fields to this type, preserving UTC timestamps separately. Use `addDuration` and `differenceMicros` rather than a `Num` instance; `differenceMicros later earlier` is signed, and existing timeout-boundary code clamps it as before. The fake clock's advance callback accepts `Duration`; starting at zero uses `MonotonicTime 0`. Migrate all runtime arithmetic and consumer tests in M2. Encode timestamps as the same integer microseconds, without new JSON wrappers or altered deadlines, inclusivity, or golden digests.

Move the `CallContext` record into a new internal module `shoko-core/src/Shoko/Internal/Call.hs` (listed under `other-modules`) so production contexts are constructed internally and consumers use the public accessors. `Shoko.Binding` exports the abstract type and these functions: `resolveInput`, `requestDeadline`, `evidenceUntil`, `sourceBaseline`, `correlation`, `runSubstep`, and `callClock`. Also export `detachedCallContext :: Clock -> MonotonicTime -> MonotonicTime -> Maybe Baseline -> Maybe Correlation -> CallContext` for adapter unit tests; in it inputs never resolve and substeps are refused. Change `resolveInput` to `CallContext -> Input a -> IO (Either InputResolutionError a)`. The internal resolver records denied dependencies in a per-invocation `IORef` before returning `Left (UndeclaredInputReference dependencyId)`, choosing the first denied dependency in input order. After an action or observation returns, that flag overrides ordinary success/unavailability with `UndeclaredOperation`; an observation ends as `Unknown`, and an action stops subsequent steps. Preserve unexpected-exception and deadline handling. Test a handler that deliberately ignores the `Left` and returns success: it must still not Pass. Keep `evaluateInput` pure but change its error type to `InputResolutionError`. Define the error in `Shoko.Internal.Reference` and re-export it through `Shoko.Binding`: split `Map.lookup` from `fromDynamic` to distinguish `InputReferenceMissing` and `InputReferenceTypeMismatch`, carrying only the public node ID. Detached contexts return `DetachedInputContext`. The runner maps denied access to `UndeclaredOperation`; unresolved/type-mismatched inputs retain the existing unavailable/prerequisite behavior, and M4 correlation resolution maps either to `CorrelationLost`. Do not serialize raw dynamic values or type representations. Update every caller to sequence the resolver in IO, including HTTP payload builders, which now return `IO (Either HttpPayloadError HttpPayload)`. Never use `unsafePerformIO` for diagnostic state. Detached contexts return `Left DetachedInputContext` in IO and refuse substeps.

Put `BindingContract`, `Source`, `Handler`, `Binding`, and `Disposition` representations in `shoko-core/src/Shoko/Internal/Binding.hs`, listed under Cabal `other-modules`. `Shoko.Binding` imports them and exposes only the public surface; `Shoko.Runner` and `Shoko.Compose` import the internal representations to execute handlers and manage resources. Keep internal imports acyclic: internal binding types depend on action/observation/context types, not on public preflight resolution. `resolvedParts` remains a runner hook but must migrate with M4's correlation representation; the CLI should use a new `resolvedPolicyReport` accessor instead of destructuring its tuple. Use the exact signatures in Interfaces and Dependencies. Make `BindingContract` abstract with `noRequirements`, `requiring`, `cleanupRequiring`, `contractCapabilities`, and `contractCleanup`. It no longer carries a source, coverage strength, or correlation support, because those move to the handler.

Introduce `Source resource` (an evidence source identifier, its coverage strength, and its baseline capture) with `newSource` and `sampledSource`. `sampledSource` records the host monotonic capture time with no cursor, which replaces the duplicated `postgresBaseline` and `httpBaseline`. Also introduce `CorrelationRequirement = RequiresBusinessKey BusinessKeyName | RequiresExecutionId`. Introduce the abstract `Handler resource a` with `actionHandler` and `observationHandler`, plus `focus` to adapt a handler to a larger resource, `handlerContract`, and `adjustContract`. Add `handlerKind`, `handlerSource`, `handlerCorrelation`, and `sourceCoverage` so the CLI can inspect abstract handlers without executing them. `ActionHandlerKind` is valid for fixtures and actions, and `ObservationHandlerKind` only for observations. `focus` projects both the handler implementation and its source capture onto the same inner resource, preserving all metadata and any correlation guard. The new `Binding op resource` is abstract and built with `binding name acquire release handlers`. `requiringLifecycle` adds lifecycle capabilities, and `adjustHandlers` lets tests wrap every handler, replacing the positional rebuild in `ScenarioSpec.hs`. Accessors `bindingName`, `bindingLifecycle`, and `bindingHandler` serve the CLI and runner.

Preflight in `resolveScenario` asks `bindingHandler role op` for every step and expectation. The lookup returns `Either HandlerBuildError (Maybe (Handler resource a))`: `Right Nothing` means the operation/role is unsupported, `Right (Just handler)` means construction succeeded, and `Left error` means an advertised handler is invalid. Preserve the latter as `HandlerConstructionFailed opId error` before acquisition. It reports `MissingHandler opId` when the handler is absent or has the wrong role, for example an action handler returned for an observation. It unions the handler contract's capabilities and cleanup with the operation's declared capabilities, exactly as today. An observation handler's correlation requirement must match the run's plan: `RequiresBusinessKey k` requires `BusinessKeyFrom k _`, and `RequiresExecutionId` requires `PropagatedExecutionId`. A mismatch is the existing `UnsupportedCorrelation opId`. Action and fixture handlers have no observation correlation requirement; their `correlation` accessor remains `Nothing`. M4 adds a separate execution-ID accessor for propagation. Two observation handlers that use the same source identifier with different coverage strengths produce the new preflight error `InconsistentSource sourceId`. The runner captures one baseline per distinct observation source identifier, using the first handler's `Source` in declaration order. It no longer captures baselines for action sources, since nothing reads them. An empty source ID still yields `MissingSource opId`. Repeated source IDs inside one binding assert that all uses select the same acquired reader and capture semantics; callers must use distinct IDs for distinct readers/scopes. Coverage equality is only a partial consistency check, not proof of closure/resource identity. M3 additionally detects cross-component collisions. Validate returned baseline identity and capture time exactly as today. Source capture stays before all fixtures and actions; failures retain the existing whole-run suppression semantics.

Add a guard helper to `Shoko.Binding`: `guardCorrelation :: BusinessKeyName -> Input Text -> CallContext -> IO (ObservationOutcome a) -> IO (ObservationOutcome a)`. It resolves the operation's own key input, compares both the supplied key name and resolved value with the context's business-key correlation, and returns `ObservationUnavailable "correlation-lost"` on mismatch or failure. Replace the three hand-written guards with it.

Each adapter gains handler constructors that keep its existing safety checks. `Shoko.Adapter.Postgres` adds `postgresSource :: SourceId -> Source Postgres` and `postgresObservation :: SourceId -> Query a -> Handler Postgres a`, whose requirement is `RequiresBusinessKey` of the query's `Scope` key. Export `queryScope :: Query a -> Scope` from `shoko-adapters/src/Shoko/Adapter/Postgres/Query.hs`; the enclosing adapter cannot pattern-match its abstract query today. `Shoko.Adapter.Http` adds `httpActionHandler` and `httpObservationHandler`. Both return `Either HandlerBuildError (Handler Http a)` (`EndpointNotAllowlisted`, `ObservationMethodNotGet`, or `ObservationScopeMissing`, each carrying the public endpoint name), and the read requirement comes from the endpoint scope's key. `Shoko.Adapter.Kiroku` adds `kirokuObservation :: SourceId -> EventQuery a -> Handler (Kiroku a) (EventEvidence a)`. `Shoko.Adapter.MessageDb` adds `messageDbObservation`, which returns `Either HandlerBuildError (Handler (MessageDb a) (EventEvidence a))`; `ExecutionMetadata` yields `Left ExecutionMetadataUnsupported`. Each event handler's requirement comes from the query's `CorrelationMode`. Remove `postgresContract`, `postgresBaseline`, `httpContract`, `httpBaseline`, `kirokuContract`, `kirokuBaseline`, `messageDbContract`, and `messageDbBaseline` once every caller uses handlers. Change the adapters' positional `CallContext` matches to the accessor functions. Do not merely close over one configuration for metadata while executing another: before transport IO, HTTP handlers compare the selected endpoint's method, target, limits, capabilities, propagation flag, and scope with the acquired resource's endpoint. Event handlers compare source ID and the query's limits, scope, history policy, correlation mode, and event type with the allocated reader before baseline capture/observation. Reject mismatches as unavailable without performing source IO. Query decoder functions cannot be compared; document reuse of the same query value for acquisition and handler construction as the caller's obligation. Add mismatch tests and keep the zero-allocation preflight tests. Use the same declared descriptor for dispatch after a successful comparison; preserve existing deadline/error classification if a payload builder returns `Left`. None of these checks require a new third-party dependency.

Keep `HandlerBuildError` in the core internal binding types, re-exported by `Shoko.Binding`, so the core can retain adapter construction diagnostics without depending on adapter packages. Its constructors contain only allowlisted public metadata. A known HTTP operation returns `Just <$> httpObservationHandler ...`; an unsupported vocabulary pattern returns `Right Nothing`; infallible native handlers return `Right (Just handler)`. `focus` is applied inside the successful branch. `combineBindings` propagates errors unchanged, and `adjustHandlers` maps its existing `Maybe` transformation only over `Right`, preserving `Left`. Do not use `either (const Nothing) Just` at any adapter-to-binding boundary. Add `HttpPayloadError = PayloadInputError InputResolutionError | InvalidPayload` to `Shoko.Adapter.Http` for payload construction; its errors yield ordinary unavailable outcomes, while the resolver's sticky denied-access flag still takes precedence. Existing decoder `HttpFailure` and transport outcome APIs remain unchanged.

Migrate every binding: `shoko-core/test/Consumer/Account.hs`, `Consumer/DeliveryLedger.hs`, `Consumer/Composed.hs`, the core specs that rebuild bindings, `shoko-adapters/test/AdapterTests.hs`, `shoko-adapters/test/EventStore/Contract.hs`, `shoko-cli/app/Demo.hs`, and `shoko-cli/test/ConsumerHost/Main.hs`. Change `shoko-cli/src/Shoko/Cli.hs` so `explain` reads sources, coverage, and requirements from `bindingHandler` instead of the removed `contract` field.

Introduce result schema v2. In `Shoko.Result.Json`, emit and require `"schemaVersion": 2`, add the `inconsistent-source` and `handler-construction-failed` preflight-error tags (including a closed tagged encoding for `HandlerBuildError`: use the existing `code`/`id` object convention, with `handler-construction-failed` carrying the operation `id` and a `cause` object; its codes are `endpoint-not-allowlisted`, `observation-method-not-get`, `observation-scope-missing` with endpoint `id`, or `execution-metadata-unsupported` with no ID), and change the decode error text to `invalid shoko result v2`. Rename the schema with `git mv schemas/run-result-v1.schema.json schemas/run-result-v2.schema.json`, set its `schemaVersion` constants to 2, and add the new tag. Update every reference: `flake.module.nix` (lines 94 and 113), `scripts/check-result-schema.py:13`, `scripts/test-cli:25`, and `docs/core.md`. Search for remaining run-result v1 references with `rg`, including the schema `$id` and title. Do not bump `schemas/workflow-v1.schema.json`, `integration/examples/workflow.example.json`, or identity artifacts in `scripts/workflow_identity.py`: those have independent version contracts. Extend `ResultSpec` to reject v1 and malformed new tags, and retain strict unknown-field and digest validation. Regenerate the goldens. Their digests do not change, because the description format is unchanged in M2.

Acceptance: `nix develop --command just check` passes, which includes the PostgreSQL, HTTP, Kiroku, Message DB, and CLI process suites. `rg -n '\bCallContext [a-z_(]' shoko-*/src shoko-*/test shoko-cli/app` finds nothing outside `shoko-core/src/Shoko/Internal/Call.hs` and `shoko-core/src/Shoko/Runner.hs`. A new `PolicySpec` case shows that a binding whose observation handler requires `accountId` fails preflight with `UnsupportedCorrelation` under a `registrationId` plan, without acquisition. New `PolicySpec` cases show `InconsistentSource`, empty-source rejection, wrong handler-kind rejection, and every `HandlerBuildError` before acquisition. A combined binding preserves the original construction cause. Runtime tests distinguish missing and type-mismatched references, and HTTP payload-input failures preserve denied-access diagnostics. Existing temporal boundary tests prove the `MonotonicTime` migration changes no timing behavior. A public consumer compiles metadata inspection using only `Shoko.Binding` accessors. `RuntimeSpec` covers declared and denied input resolution, including ignored resolver errors, and `focus` against a tuple resource whose observation and capture use the same component. The existing allocation-count assertions in `EventStore/Contract.hs` still show zero allocations for a denied policy.


### Milestone 3: Vocabulary sums and binding combination


At the end of M3, two bounded contexts' vocabularies and bindings combine without either knowing the other. Create `shoko-core/src/Shoko/Compose.hs`, exported from `Shoko`, defining `data (f :+: g) a = InL (f a) | InR (g a)` with `infixr 6 :+:` and an instance `(Vocabulary f, Vocabulary g) => Vocabulary (f :+: g)` that delegates. Provide `class Member f g where inject :: f a -> g a` with the reflexive instance, an overlapping left-sum instance, and an overlappable recursive right-sum instance. Compile-check identity, left, right, and three-context right-nested injection under the repository's GHC2024 settings; enable the needed instance extensions locally. Use `FlexibleInstances`, `MultiParamTypeClasses`, and `UndecidableInstances` locally, with the instance definitions in Interfaces and Dependencies. The convenience API targets distinct component vocabularies in right-nested sums. Use exported `InL`/`InR` explicitly to choose an occurrence of a repeated vocabulary or address other sum shapes. Do not silently replace the promised `Member` API during implementation. Support new polymorphic blocks with constraints such as `Member Registration op => ScenarioBuilder op (Ref Text)` and `inject` at operation sites. Also retain a concrete `ScenarioBuilder Registration a` producer: lifting must not require rewriting it to use `Member`.

Add `hoistAction`, `hoistObservation`, `hoistExpectations`, and `hoistScenarioBuilder` in their owning public modules, enabling `RankNTypes` locally, with the rank-N signatures in Interfaces and Dependencies. The argument `forall x. f x -> g x` maps every operation while preserving its result type. `hoistAction` preserves accepted tags; `hoistObservation` preserves predicate functions, identifiers, validation metadata, and, after M4, correlation selection; `hoistExpectations` preserves returned values, temporal operators, windows, names, and order. Map a builder structurally: map both sides of `Bind` by composing with its continuation, and recurse into `Namespace`, strict expectations, and deferred expectations. Do not collect/finalize the builder before mapping: doing so loses returned values and lexical namespace placement. M4's correlation declarations preserve their input and alias; handles are still assigned by collection in the final namespace. No IO or runtime input resolution occurs while mapping. Implement helpers where abstract constructors are available, and re-export the functions from `Shoko`; the public consumer needs no internal imports.

Check the identity and composition laws through observable inspection and execution: `hoistScenarioBuilder id block` agrees with `block`, and mapping twice agrees with mapping the composed operation transformation. `InL`, `InR`, and `inject` preserve operation descriptions through the sum vocabulary; a user-supplied transformation that changes operation meaning is inspected as that new meaning and requires the usual scenario revision change. Test namespaced typed outputs, strict/deferred expectations, predicate metadata, and deadlines/windows. Compile a concrete `ScenarioBuilder Registration (Ref Text)` into `ScenarioBuilder (Registration :+: Accounts) (Ref Text)` using `hoistScenarioBuilder InL` and pass its returned reference into an accounts block.

Provide `combineBindings :: Text -> Binding f r1 -> Binding g r2 -> Binding (f :+: g) (r1, r2)`. Handler lookup delegates by side through `focus fst` or `focus snd`; lifecycle capabilities are unioned. Both components are acquired even when only one supplies operations in this scenario. Every unconditional acquisition/release capability belongs in `requiringLifecycle`, not only in a selected handler's contract; test that a denied capability on the otherwise unused component prevents all acquisition. Track each component's structural position internally so preflight reports `InconsistentSource sourceId` when separate component bindings advertise the same source ID, even with equal coverage. Internal repeated uses of a source within one component may still share its capture as specified in M2. Do not rename event baseline IDs without adapting reader state; callers choose distinct stable public labels such as `registration.events` and `accounts.events`.

Acquisition uses `mask` around each successful acquisition-to-registration handoff, restoring interruptibility while a child acquires. Acquire the left resource and immediately register its completed release actions, then do the same for the right before returning the pair. Do not leave the right release dependent on an interruptible return to the runner. Internally represent completed release as `resource -> [IO Disposition]`: the public `binding` constructor wraps its one release callback in a singleton list, while a composite has no additional completed-release actions because it registered both children. Adapt the runner to pass this list to `finalize`. Nested combinations register each leaf once; no synthetic composite disposition is emitted. The runner executes registered finalizers in reverse registration order. Each child remains responsible for registering cleanup of partial acquisitions before an interruptible operation. Preserve the shared grace deadline, synchronous-cleanup-failure handling, and cancellation rethrow. Within that deadline each finalizer runs at most once; expiry may prevent remaining releases and must report `CleanupTimedOut`. Each executed child release contributes its own disposition. Exercise both `(a :+: b) :+: c` and `a :+: (b :+: c)` resource nesting and verify right-to-left cleanup on success and partial acquisition failure.

Operation identifiers are flat text, and two contexts could collide. In `scenarioParts`, add the definition error `ConflictingOperation opId` when two operations in one scenario share an identifier but differ in capabilities or substeps. Add its tag to the v2 schema and the JSON codec.

Extend `Consumer/Composed.hs` into two GADTs, `Registration` and `Accounts`, each with its own binding, combined through `:+:` and `combineBindings`. Add tests: the combined scenario runs to Pass. A right-side acquisition failure still yields a `Cleaned` disposition for the left. Release order is right then left, observed through an `IORef` log. Two vocabularies reusing an operation identifier with different capabilities report `ConflictingOperation`. Repeated uses of the same operation with different input dependency nodes remain valid; compare capabilities and normalized substep inventories, not per-use dependencies. Equal metadata does not prove two operations mean the same thing, so context authors must use stable, context-qualified operation IDs. Test equal-coverage source collisions before allocation, left-acquisition failure, right-acquisition failure/timeout/cancellation, nested cleanup order, and absence of double release.

Acceptance: `nix develop --command just test` passes with these cases, and the goldens regenerate with no change, since the new tag appears only in its own test.


### Milestone 4: Scenario-owned correlation handles


At the end of M4, a self-contained workflow can be instantiated twice while each instance selects its own entity under the same business-key name. In `shoko-core/src/Shoko/Scenario.hs`, add `correlate :: CorrelationAlias -> BusinessKeyName -> Input Text -> ScenarioBuilder op CorrelationRef`: its arguments are a local declaration alias, a semantic business-key name, and a typed input for the value. For example, `correlate (CorrelationAlias "registration") (BusinessKeyName "registrationId") (fromRef registered)` inside `namespace "inviter"` creates instance ID `inviter.registration`, but the adapter still receives `ByBusinessKey (BusinessKeyName "registrationId") value`. `CorrelationRef` is abstract, with `correlationRefId` for inspection; consumers cannot construct it from text. The collector assigns its fully qualified identity, just as it assigns `Ref` identities. A returned handle retains that identity when passed outside its namespace; an external handle used inside another namespace is not renamed. Keep the representation in `shoko-core/src/Shoko/Internal/Correlation.hs`, register that module under Cabal `other-modules`, and expose the abstract type from `Shoko.Correlation`.

Aliases occupy a separate namespace from node/expectation identifiers. Reject duplicate fully qualified declaration IDs with `DuplicateIdentifier`, empty aliases or business-key names with `InvalidIdentifier`, and local alias `execution-id` as reserved. Repeating a semantic business-key name under different IDs is valid, including inside one namespace with different aliases. Correlation input dependencies must already exist at the declaration site, otherwise report `UnresolvedReference`; declarations neither start nor clear the strict-expectation barrier.

Add `correlatedBy :: CorrelationRef -> Observation op a -> Observation op a` and `observationCorrelation :: Observation op a -> Maybe CorrelationRef` to `shoko-core/src/Shoko/Observation.hs`. The wrapper selects the declaration for this observation; a subsequent wrapper replaces the selection, with the final selection visible in inspection. `observe` and `observeThat` initially have no selection. `hoistObservation` must preserve it. A handler's `RequiresBusinessKey (BusinessKeyName "registrationId")` is a compatibility constraint, not a lookup rule or implicit choice among instances. An observation with no selection fails preflight as `UnselectedCorrelation opId`; a selected ID absent from the scenario fails as `UndeclaredCorrelation opId correlationId`; a declared handle whose strategy or semantic key disagrees with the handler fails as `IncompatibleCorrelation opId correlationId`. All three reject before acquisition. There is no first-match or unique-key fallback. Core internal tests may construct a dangling handle to exercise the defensive undeclared-reference path; ordinary public builders generate handles with their declarations.

Change `propagateExecutionId :: ScenarioBuilder op CorrelationRef` to return the single run-wide execution handle. Repeated calls, including inside namespaces, are idempotent: they return that same handle and create one declaration at its first occurrence. Its ID is `CorrelationId "execution-id"` and its descriptive key is `BusinessKeyName "execution-id"`, with strategy `ExecutionId` and no dependencies. An observation selecting it must have a `RequiresExecutionId` handler. Business declarations cannot claim this reserved alias. This lets independently reused blocks request execution propagation without duplicate declarations.

Remove `CorrelationPlan`, its constructors and helpers, the `CorrelationPlan` argument of `resolveScenario`, the field of `Shoko.Cli.Registry.Entry`, and `MissingCorrelationReference`. Remove M2's `UnsupportedCorrelation` and wire tag; unsupported adapter modes produce typed construction errors rather than erasing their cause. Keep `MissingSource` for empty source IDs. Removing `CorrelationPlan` also removes `Shoko.Correlation`'s dependency on `Shoko.Action`, allowing `Shoko.Observation` to import the handle without the current `Action -> Observation -> Correlation -> Action` cycle. Store typed declaration inputs internally in the scenario representation, separately from public descriptions; never reconstruct inputs from dependency strings. Update `scenarioParts`, `ResolvedScenario`/`resolvedParts`, their consumers, and mapping functions together.

`Description.correlations` contains `CorrelationDescription` records with `correlationId`, `correlationKey`, `strategy`, and dependency node IDs, never values. `ExpectationDescription` gains `correlationId :: Maybe CorrelationId`, recording the explicit selection even before binding resolution. Serialize the identifier newtypes as their underlying strings in descriptions and reports. The description digest uses `"shoko-description-v2"`, adds a tagged optional selected ID to each expectation's encoding, and appends a counted declarations segment containing each ID, semantic key, strategy, and counted dependencies. Preserve declaration and expectation order. `PolicyReport.correlationStrategies` is the set of declared strategies, including unused declarations.

After the fixed action sequence completes, resolve declarations independently by instance ID. An empty value or failed input is `CorrelationLost`. A terminal action failure still suppresses all expectations with `PrerequisiteUnavailable`. Otherwise only expectations selecting an unresolved instance become `Unknown/CorrelationLost` without dispatch; siblings selecting resolved instances continue even when both instances have the same semantic business-key name. The observation's `CallContext.correlation` exposes only its selected `Correlation`. Existing SQL/HTTP/event adapters keep their semantic key checks unchanged and never receive the namespaced alias in place of the business-key name. Distinct selections within one binding may share one evidence source/baseline when they use the same acquired reader; do not acquire duplicate readers merely to distinguish entities.

`VerificationResult.correlations` becomes `[ResolvedCorrelation]`, where each record pairs `correlationId` with `resolvedCorrelation :: Correlation`. Include successful resolutions in declaration order, with no placeholder values for failures. In JSON each item has `correlationId` and `resolvedCorrelation`; the latter uses the existing tagged `Correlation` encoding. Descriptions retain unresolved declarations and expectation selections, so reports can attribute failures to one instance. Update schema v2 and strict codecs for these shapes, the optional expectation selection, policy strategies, and the `unselected-correlation`, `undeclared-correlation`, and `incompatible-correlation` preflight tags; remove obsolete fields/tags. Keep description inputs private and preserve the existing disclosure policy for resolved report values.

Expose `executionId :: CallContext -> Maybe Text`, which is `Just runKey` for calls only when the execution declaration exists, otherwise `Nothing`. It remains separate from observation selection. Detached contexts supply no execution ID. Native actions use it explicitly; HTTP wrappers copy it to the payload run label, reject a conflicting explicit label, and preserve endpoint propagation opt-in. Test matching transmitted/observed IDs and disabled endpoints. Declaring or transmitting an ID does not prove durable propagation; a context-owned propagation proof and target-compatible ID format remain required.

Migrate `shoko-cli/app/Demo.hs`, `shoko-cli/test/ConsumerHost/Main.hs`, all core consumers/specs, and adapter consumer tests to declare handles and attach `correlatedBy` to every observation. Update CLI `explain` and text reports to show instance IDs, semantic keys, strategies, and expectation-to-instance links. Extend `shoko-core/test/Consumer/Composed.hs` with the concrete reusable block and scenario wrappers shown below. Two registration instances must produce distinct values and use the same registration binding; combine that binding once with the accounts binding. The account block uses the invitee's returned reference and declares the third handle, `account`, with semantic key `accountId`.

Acceptance: `nix develop --command just check` passes. The composed scenario runs to Pass with three resolved instances: `inviter.registration`, `invitee.registration`, and `account`. A controlled cross-instance observation cannot be satisfied by the other registration's evidence. An accepted action returning an empty registration key makes only its selected expectation Unknown while the other same-key registration passes. Test absent selection, incompatible semantic key/strategy, dangling handle, duplicate aliases, empty/reserved labels, returned/external handles across namespaces, repeated execution requests, terminal-action suppression, and the HTTP propagation path. Codec tests round-trip repeated-key and partial results and reject unsupported v1, unknown fields, and digest tampering. Changing a declaration ID/key/strategy/dependency or an expectation's selected ID changes the digest; changing private input values does not. The hoisting identity/composition checks still pass after correlation nodes and selections are added.


### Milestone 5: End-to-end host demonstration and durable records


At the end of M5, a scenario host built only from the public API demonstrates the composed workflow as real processes, and the durable documentation matches the new API. Add an entry `composed-registration` to `shoko-cli/test/ConsumerHost/Main.hs`, using two in-memory context vocabularies, `combineBindings`, `hoistScenarioBuilder`, two instances of one complete workflow block, `expectAfterActions`, predicate combinators, and explicit correlation handles. Extend `scripts/test-cli` to assert the following. `explain composed-registration` prints the identifiers `inviter.qualified` and `invitee.qualified` and the correlation IDs `inviter.registration`, `invitee.registration`, and `account`, with semantic keys `registrationId` and `accountId` and each expectation's selected ID. `run composed-registration --format json` exits 0 with a v2 document whose `report.correlations` has three entries and that validates against `schemas/run-result-v2.schema.json`.

Also register `registration-alone` and `registration-reused`, distinct finalized scenarios backed by the same concrete `registrationBlock` definition. Execute each as a separate process and assert Pass, distinct scenario identities, and fresh run-owned state. Their builder definitions are shared; no execution results or handles are cached across runs. Document extracting a workflow definition from an existing scenario wrapper for reuse, keeping scenario IDs/revisions explicit. Do not expose scenario concatenation or imply that a deferred expectation is an intermediate checkpoint.

Rewrite the construction and binding sections of `docs/core.md` and the handler sections of `docs/adapters.md`, and update `docs/scenario-hosts.md`, the README outline, and `shoko-core/CHANGELOG.md`. Append dated revision paragraphs. In `docs/adr/0002-keep-scenarios-inspectable-and-bindings-explicit.md`, record namespaced blocks, deferred expectations under the unchanged runtime model, handler-based bindings with owned sources and correlation requirements, vocabulary sums with `combineBindings`, result-preserving hoisting, typed identifier/time boundaries and error contracts, the builder/scenario boundary, and explicit correlation-instance selection. In `docs/adr/0003-record-bounded-evidence-and-three-valued-results.md`, record result schema v2 and per-expectation `CorrelationLost`. Then complete Outcomes & Retrospective and the ADR distillation described in the skill's PLANS.md.

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

In M1 and M3 the diff must be empty. In M2 it shows only `schemaVersion` changes, plus any newly added preflight example; identifier/time wrappers add no JSON object layers or numeric changes. In M4 it shows description digests, correlations, and policy fields.

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


The plan is accepted when all of the following hold in one final-candidate tree. `nix develop --command just check` passes. One concrete-vocabulary workflow is reused by two independently finalized scenarios and twice under namespaces inside one combined scenario, without rewriting its producer to require `Member`. Returned typed references and correlation handles still connect later blocks after `hoistScenarioBuilder`. A deferred expectation first polls after the last action. Both vocabulary injection and binding composition preserve the expected observations and reverse cleanup order. Repeated registration blocks use separate correlation IDs with the same semantic key, and neither can consume the other's evidence. Missing selection, unknown selection, or incompatible selection fails preflight with zero acquisition. One unresolved instance leaves only its dependent expectations `Unknown/CorrelationLost`, even when a resolved sibling uses the same semantic key. The process check shows `composed-registration` explaining three instance IDs and every expectation's selection, then running to Pass with a schema-valid v2 document containing three resolved entries. The two standalone registration scenario entries also pass independently.

The final gate also includes M2's ignored-reference-error and resource-focus checks, M3's nested/cancelled acquisition cleanup and source-collision checks, and M4's correlation declaration validation and execution-ID transport check. A public consumer must build without importing `Shoko.Internal.*`. M2 includes compile-failure fixtures for swapping `SourceId` and `BusinessKeyName` and supplying `Duration` as `MonotonicTime`; M4 adds swapped `CorrelationAlias`/`BusinessKeyName` and `CorrelationId`/`CorrelationRef` cases. Add a bounded Python harness at `scripts/test-core-types`, using the built public package via `cabal exec -- ghc -fno-code` on temporary positive/negative modules, and invoke it from `just check`. Compile each corresponding positive fixture first so missing packages/imports cannot count as a successful negative test; require the negative case to fail with the intended pair of type names rather than matching a full compiler diagnostic. Runtime tests cover typed error propagation and closed, sanitized wire encodings. No new third-party dependency is needed.

The early integration check is M2's migration of `shoko-adapters/test/AdapterTests.hs`, because that binding combines HTTP actions with both SQL and HTTP reads. Migrate it first, before the other adapters' handler constructors are finalized. If `focus`, `sampledSource`, or `httpObservationHandler` are awkward there, revise the interfaces before migrating the rest, and record the change in the Decision Log.

Checked outcome-tag vocabularies are proposed follow-up scope, not required acceptance.


## Idempotence and Recovery


Every step is a source edit under version control, and every command above is safe to repeat. Golden regeneration is deterministic and overwrites only `shoko-core/test/golden/*.json`. The schema rename uses `git mv`. If abandoning uncommitted M2 work, inspect its diff and reverse only this milestone's edits and rename; do not restore the entire schemas directory over unrelated work. Each milestone ends in its own commit, so a milestone can be reverted with `git revert <commit>` without disturbing earlier ones. If M2 is interrupted midway, the tree may not compile. Finish the migration rather than committing a partial one; `cabal build all` lists the remaining call sites as type errors. The real-IO suites create temporary clusters and directories and remove them on exit. Failed adapter runs keep their logs under `.dev/adapter-tests/` for inspection, and that directory can be deleted at any time.


## Interfaces and Dependencies


No new third-party dependency is required. The work uses `base`, `containers`, `text`, `effectful-core`, and `aeson`, which are already in the build. The following public signatures must exist at the end of the plan. Module paths are under `shoko-core/src/` unless stated otherwise.

In new `Shoko.Identifier`, re-exported from `Shoko` (each newtype derives `Eq`, `Ord`, `Show`, and `Generic` with `deriving stock`; no `IsString` instance):

```haskell
newtype CorrelationAlias = CorrelationAlias Text
newtype BusinessKeyName = BusinessKeyName Text
newtype CorrelationId = CorrelationId Text
newtype SourceId = SourceId Text
correlationAliasText :: CorrelationAlias -> Text
businessKeyNameText :: BusinessKeyName -> Text
correlationIdText :: CorrelationId -> Text
sourceIdText :: SourceId -> Text
```

In `Shoko.Clock` (export `MonotonicTime` and its helpers from `Shoko` as well):

```haskell
newtype MonotonicTime = MonotonicTime Integer
  deriving stock (Eq, Ord, Show, Generic)
monotonicMicros :: MonotonicTime -> Integer
addDuration :: MonotonicTime -> Duration -> MonotonicTime
differenceMicros :: MonotonicTime -> MonotonicTime -> Integer

data Clock = Clock
  { monotonic :: IO MonotonicTime,
    utc :: IO UTCTime,
    sleepUntil :: MonotonicTime -> IO (),
    bounded :: forall a. MonotonicTime -> IO a -> IO (Maybe a)
  }
newFakeClock :: UTCTime -> IO (Clock, Duration -> IO ())
```

In `Shoko.Scenario`, re-exported from `Shoko`:

```haskell
namespace :: Text -> ScenarioBuilder op a -> ScenarioBuilder op a
expectAfterActions :: Expectations op () -> ScenarioBuilder op ()
-- Local alias, semantic business-key name, value input.
correlate :: CorrelationAlias -> BusinessKeyName -> Input Text -> ScenarioBuilder op CorrelationRef
propagateExecutionId :: ScenarioBuilder op CorrelationRef
hoistScenarioBuilder ::
  (forall x. f x -> g x) -> ScenarioBuilder f a -> ScenarioBuilder g a

data CorrelationDescription = CorrelationDescription
  { correlationId :: !CorrelationId,
    correlationKey :: !BusinessKeyName,
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

In `Shoko.Correlation`, re-exported from `Shoko`:

```haskell
data Correlation = ByBusinessKey !BusinessKeyName !Text | ByExecutionId !Text
  deriving stock (Eq, Show, Generic)

data CorrelationRef
correlationRefId :: CorrelationRef -> CorrelationId

data ResolvedCorrelation = ResolvedCorrelation
  { correlationId :: !CorrelationId,
    resolvedCorrelation :: !Correlation
  }
```

`CorrelationRef` is a symbolic handle, not a runtime correlation value. Its constructor is internal. `ResolvedCorrelation` is public result data. `ExpectationDescription` adds `correlationId :: Maybe CorrelationId`; use `observationCorrelation` to inspect a constructed observation's handle.

In `Shoko.Action`:

```haskell
hoistAction :: (forall x. f x -> g x) -> Action f a -> Action g a
declareOperation :: Text -> [Capability] -> OperationInfo
dependsOn :: Input a -> OperationInfo -> OperationInfo
withSubstep :: Text -> [Capability] -> OperationInfo -> OperationInfo
```

In `Shoko.Observation`:

```haskell
hoistObservation :: (forall x. f x -> g x) -> Observation f a -> Observation g a
correlatedBy :: CorrelationRef -> Observation op a -> Observation op a
observationCorrelation :: Observation op a -> Maybe CorrelationRef

data Predicate a
predicate :: Text -> (a -> Bool) -> Predicate a
infixr 3 .&&.
infixr 2 .||.
(.&&.), (.||.) :: Predicate a -> Predicate a -> Predicate a
negated :: Predicate a -> Predicate a
onPart :: Text -> (b -> a) -> Predicate a -> Predicate b
observeThat :: op a -> Predicate a -> Observation op a
```

In `Shoko.Expectation`, re-exported from `Shoko`:

```haskell
hoistExpectations :: (forall x. f x -> g x) -> Expectations f a -> Expectations g a
```

In `Shoko.Binding`, where `CallContext`, `BindingContract`, `Source`, `Handler`, and `Binding` are abstract:

```haskell
data InputResolutionError
  = UndeclaredInputReference !Text
  | InputReferenceMissing !Text
  | InputReferenceTypeMismatch !Text
  | DetachedInputContext
  deriving stock (Eq, Show, Generic)

data HandlerBuildError
  = EndpointNotAllowlisted !Text
  | ObservationMethodNotGet !Text
  | ObservationScopeMissing !Text
  | ExecutionMetadataUnsupported
  deriving stock (Eq, Show, Generic)

data CorrelationRequirement = RequiresBusinessKey !BusinessKeyName | RequiresExecutionId

resolveInput :: CallContext -> Input a -> IO (Either InputResolutionError a)
requestDeadline :: CallContext -> MonotonicTime
evidenceUntil :: CallContext -> MonotonicTime
sourceBaseline :: CallContext -> Maybe Baseline
correlation :: CallContext -> Maybe Correlation
executionId :: CallContext -> Maybe Text
runSubstep :: CallContext -> Text -> IO a -> IO (Either Text a)
callClock :: CallContext -> Clock
detachedCallContext :: Clock -> MonotonicTime -> MonotonicTime -> Maybe Baseline -> Maybe Correlation -> CallContext

noRequirements :: BindingContract
requiring :: [Capability] -> BindingContract -> BindingContract
cleanupRequiring :: [Capability] -> BindingContract -> BindingContract
contractCapabilities :: BindingContract -> Set Capability
contractCleanup :: BindingContract -> Set Capability

newSource :: SourceId -> CoverageStrength -> (resource -> Clock -> IO (Either Text Baseline)) -> Source resource
sampledSource :: SourceId -> Source resource
sourceId :: Source resource -> SourceId
sourceCoverage :: Source resource -> CoverageStrength

actionHandler :: BindingContract -> (resource -> CallContext -> IO (ActionOutcome a)) -> Handler resource a
observationHandler ::
  BindingContract -> CorrelationRequirement -> Source resource ->
  (resource -> CallContext -> IO (ObservationOutcome a)) -> Handler resource a
focus :: (outer -> inner) -> Handler inner a -> Handler outer a
data HandlerKind = ActionHandlerKind | ObservationHandlerKind
handlerKind :: Handler resource a -> HandlerKind
handlerSource :: Handler resource a -> Maybe (Source resource)
handlerCorrelation :: Handler resource a -> Maybe CorrelationRequirement
handlerContract :: Handler resource a -> BindingContract
adjustContract :: (BindingContract -> BindingContract) -> Handler resource a -> Handler resource a

binding ::
  Text ->
  ((IO Disposition -> IO ()) -> IO resource) ->
  (resource -> IO Disposition) ->
  (forall a. OperationRole -> op a -> Either HandlerBuildError (Maybe (Handler resource a))) ->
  Binding op resource
requiringLifecycle :: [Capability] -> Binding op resource -> Binding op resource
adjustHandlers ::
  (forall a. OperationRole -> op a -> Maybe (Handler resource a) -> Maybe (Handler resource a)) ->
  Binding op resource -> Binding op resource
bindingName :: Binding op resource -> Text
bindingLifecycle :: Binding op resource -> Set Capability
bindingHandler :: Binding op resource -> OperationRole -> op a -> Either HandlerBuildError (Maybe (Handler resource a))

guardCorrelation :: BusinessKeyName -> Input Text -> CallContext -> IO (ObservationOutcome a) -> IO (ObservationOutcome a)

resolvedPolicyReport :: ResolvedScenario op resource -> PolicyReport

resolveScenario ::
  Vocabulary op =>
  Environment -> RunOptions -> Binding op resource -> Scenario op ->
  Either [PreflightError] (ResolvedScenario op resource)
```

`PreflightError` gains `InconsistentSource !SourceId`, `HandlerConstructionFailed !Text !HandlerBuildError`, `UnselectedCorrelation !Text`, `UndeclaredCorrelation !Text !CorrelationId`, and `IncompatibleCorrelation !Text !CorrelationId`, and loses `MissingCorrelationReference` and `UnsupportedCorrelation`. `MissingSource` remains for empty source identifiers. `PolicyReport` becomes `{ requiredCapabilities :: Set Capability, correlationStrategies :: Set CorrelationStrategy }`. `VerificationResult` replaces `correlation :: Maybe Correlation` with `correlations :: [ResolvedCorrelation]`. `Description` gains `correlations :: [CorrelationDescription]`.

In the new module `Shoko.Compose`, re-exported from `Shoko`:

```haskell
data (f :+: g) a = InL (f a) | InR (g a)
infixr 6 :+:
instance (Vocabulary f, Vocabulary g) => Vocabulary (f :+: g)
class Member f g where inject :: f a -> g a
instance Member f f where inject = id
instance {-# OVERLAPPING #-} Member f (f :+: g) where inject = InL
instance {-# OVERLAPPABLE #-} Member f g => Member f (h :+: g) where
  inject = InR . inject
combineBindings :: Text -> Binding f r1 -> Binding g r2 -> Binding (f :+: g) (r1, r2)
```

In `shoko-adapters`:

```haskell
-- Shoko.Adapter.Postgres
postgresSource :: SourceId -> Source Postgres
postgresObservation :: SourceId -> Query a -> Handler Postgres a
-- Shoko.Adapter.Postgres.Query, re-exported by Shoko.Adapter.Postgres
queryScope :: Query a -> Scope
-- Shoko.Adapter.Http
data HttpPayloadError = PayloadInputError !InputResolutionError | InvalidPayload
  deriving stock (Eq, Show, Generic)
httpActionHandler ::
  HttpConfig -> Text -> (CallContext -> IO (Either HttpPayloadError HttpPayload)) ->
  (Int -> ByteString -> Either HttpFailure (Text, a)) -> Either HandlerBuildError (Handler Http a)
httpObservationHandler ::
  HttpConfig -> Text -> (CallContext -> IO (Either HttpPayloadError HttpPayload)) ->
  (Int -> ByteString -> Either HttpFailure a) -> Either HandlerBuildError (Handler Http a)
-- Shoko.Adapter.Kiroku
kirokuObservation :: SourceId -> EventQuery a -> Handler (Kiroku a) (EventEvidence a)
-- Shoko.Adapter.MessageDb
messageDbObservation :: SourceId -> EventQuery a -> Either HandlerBuildError (Handler (MessageDb a) (EventEvidence a))
```

The following public consumer shape is required in M4/M5. `Qualified :: Registration Text`, `Complete :: Input Text -> Registration Text`, and `Registered :: Input Text -> Registration Bool` are consumer vocabulary constructors. `accountBlock :: Ref Text -> ScenarioBuilder Accounts ()` creates its own account result, declares handle `account` for `accountId`, and selects it on its deferred account observation. Their bindings supply the corresponding roles and semantic correlation requirements. The two uses of `registrationBlock` share one registration binding, with a fresh entity allocated per fixture.

```haskell
registrationBlock :: ScenarioBuilder Registration (Ref Text, CorrelationRef)
registrationBlock = do
  qualified <- given "qualified" (accept ["ready"] Qualified)
  registered <- act "complete" (accept ["completed"] (Complete (fromRef qualified)))
  selected <- correlate (CorrelationAlias "registration") (BusinessKeyName "registrationId") (fromRef registered)
  expectAfterActions $
    eventually "registered" $
      correlatedBy selected $
        observeThat (Registered (fromRef registered)) (predicate "exists" id)
  pure (registered, selected)

registrationAlone :: Scenario Registration
registrationAlone =
  scenario "registration-alone" "Register one entity" "v1" $
    registrationBlock >> pure ()

registrationReused :: Scenario Registration
registrationReused =
  scenario "registration-reused" "Reuse the registration workflow" "v1" $
    registrationBlock >> pure ()

composedRegistration :: Scenario (Registration :+: Accounts)
composedRegistration =
  scenario "composed-registration" "Register two entities and check an account" "v1" $ do
    _ <- namespace "inviter" (hoistScenarioBuilder InL registrationBlock)
    (invitee, _) <- namespace "invitee" (hoistScenarioBuilder InL registrationBlock)
    hoistScenarioBuilder InR (accountBlock invitee)
```

The standalone wrappers explicitly discard the block's symbolic return value; within the combined workflow the returned `Ref` connects to the account block. Returning the correlation handle also permits additional caller-owned observations with `correlatedBy` without exposing or reconstructing its namespaced ID. There is no scenario extraction/concatenation step, and all three blocks' expectations activate together after the account actions.

In `shoko-cli`, `Shoko.Cli.Registry.Entry` loses its `CorrelationPlan` field and becomes `Entry (Scenario op) LogicalInput [(Text, HostConfig -> Maybe Credentials -> SomeBinding op)] (HostConfig -> IO (Either Text (Maybe Text, Maybe TargetIdentity)))`.

Downstream, [plan 7](7-verify-one-real-workflow-across-legacy-and-keiro-implementations.md) should write its context vocabulary and binding against these interfaces. The existing core, adapter, and CLI outputs are migrated in M2/M4; retained historical plan descriptions remain records of their original interfaces. Check active downstream host work before landing the breaking release.


Revision 2026-10-19: validated the proposal against the core interpreter, adapter implementations, CLI, ADRs, and passing baseline tests. Corrected the pure-resolver/IO mismatch, abstract metadata access, polymorphic block constraints, source-sharing assumptions, exception-safe composition, predicate/namespace validation, and multi-key/propagation semantics. Added concrete public-consumer and failure-path acceptance without marking implementation milestones complete.

Revision 2026-10-19 (composition follow-up): addressed the three reuse limitations by separating namespaced correlation instances from semantic key names with explicit observation selection, adding result-preserving vocabulary maps for concrete blocks, and documenting/testing the reusable-builder versus finalized-scenario boundary. Updated signatures, migration, digest/schema shapes, milestones, examples, and process acceptance together. The earlier review records the pre-follow-up revision; implementation and acceptance remain pending.

Revision 2026-10-19 (Haskell conventions): adopted the three agreed API refinements: distinct identifier/time newtypes, typed input and handler-construction errors retained through binding preflight, and the `hoist…` vocabulary-transform naming family. Updated signatures, producer/consumer migrations, examples, wire compatibility requirements, and compile-time/runtime acceptance. Existing review/probe evidence describes earlier revisions and does not establish implementation of these additions.
