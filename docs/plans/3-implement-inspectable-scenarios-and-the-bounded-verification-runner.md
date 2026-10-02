---
id: 3
slug: implement-inspectable-scenarios-and-the-bounded-verification-runner
title: "Implement inspectable scenarios and the bounded verification runner"
kind: exec-plan
created_at: 2026-10-02T03:52:02Z
intention: "intention_01m3xdacr3exqajqfcgh9btgev"
master_plan: "docs/masterplans/1-bootstrap-shoko-for-evidence-based-workflow-parity.md"
provenance:
  created_by:
    model: "gpt-6-astra"
    harness: "codex-cli"
    at: 2026-10-02T03:52:02Z
  revisions:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-02T04:18:40Z
      mode: "update"
      note: "Associate the bootstrap plan with the shared Mina intention requested by the user."
---

# Implement inspectable scenarios and the bounded verification runner


This ExecPlan is a living document. Keep accepted behavior, interfaces, and remaining milestones current; update the cited ADRs when durable decisions change.

## Purpose / Big Picture


A Haskell consumer can describe actions and evidence expectations once, inspect the description without executing effects, and run it with interchangeable bindings. Deterministic tests show that a source outage produces Unknown, a violated expectation produces Fail, and a supported observation produces Pass within a finite budget.

## Progress


- [ ] M1: A typed scenario can be inspected and bound without IO, and undeclared operations or disallowed capabilities are rejected before fixture/action execution.
- [ ] M2: The effectful runner evaluates eventually, never, and exactlyOnce with correct deadlines, correlation, coverage, and cancellation.
- [ ] M3: Two concrete consumer scenarios exercise the public API and stable versioned results through deterministic and real-clock checks.

## Surprises & Discoveries


## Decision Log


On 2026-10-01, keep an inspectable scenario description above effectful, with symbolic references and a fixed initial composition model. This resolves RES-1 F3 while making later inspection consume the same artifact as execution. Define observation/coverage semantics in core so adapters cannot each invent their own treatment of missing evidence.

## Outcomes & Retrospective


## Context and Orientation


Hard prerequisite `docs/plans/1-bootstrap-the-haskell-workspace-with-seihou-and-jitsurei-standards.md` supplies `shoko-core`, its prelude/test target, and the reproducible build. [RES-1](../research/initial-specification-requirement-validation.md) F2–F10 and M4–M5 motivates the contracts here. [ADR 0002](../adr/0002-keep-scenarios-inspectable-and-bindings-explicit.md) chooses the DSL, capabilities, environments, and correlation. [ADR 0003](../adr/0003-record-bounded-evidence-and-three-valued-results.md) fixes finite temporal semantics and three-valued results. Apply the coding rules in [ADR 0001](../adr/0001-use-jitsurei-standards-and-the-seihou-haskell-flake.md), including strict records, explicit deriving, generic-lens locality, and postpositive qualified imports.

An operation describes a domain action or observation without embedding its environment. A binding supplies the handler for that operation. A `Ref a` is a typed placeholder for a result available only during execution. An expectation judges observations; a coverage record describes the interval a source can actually support. An occurrence identity distinguishes one event/fact from another across repeated polls. The effectful dependency is [effectful](mori://effectful/effectful); its dynamic dispatch source was inspected and provides `interpret`/`reinterpret` for runtime-selected handlers. Resolve source through Mori and verify released package versions before adding bounds. Do not turn the scenario itself into unrestricted `Eff ... IO` code.

## Plan of Work


### M1 — Define one inspectable public contract


Implement `shoko-core/src/Shoko/Scenario.hs`, `Action.hs`, `Observation.hs`, `Expectation.hs`, `Environment.hs`, `Correlation.hs`, and `Binding.hs`, all under `Shoko`. Re-export supported construction functions from `shoko-core/src/Shoko.hs`, keeping internal constructors hidden where needed. Use an extensible typed vocabulary so a downstream context can define its own actions and observations without changing Shōko's closed domain types. A generalized algebraic data type (GADT) retains the result type of each operation; use it or an equivalent type-safe representation, not unchecked casts.

The canonical builder is `scenario scenarioId title $ do ...`: `given` creates a fixture node and returns `Ref a`, `act` creates an action node, and `expect` declares the expectation group. `eventually`, `never`, `exactlyOnce`, and `within` build expectation descriptions, not immediate IO. Model fixture/action dependencies through references. The initial runner supports an ordered fixture/action sequence followed by sibling expectations; do not expose runtime branching or a general workflow scheduler. Reject duplicate IDs, unresolved references, invalid durations, missing handlers, and unsupported implementation/correlation requirements with typed definition/preflight errors.

`inspectScenario` produces stable operation IDs, dependencies, observations, windows, and declared requirements without running handlers. `resolveScenario` combines this with binding requirements into a `ResolvedScenario` and `PolicyReport`. Required capabilities include fixture and cleanup capabilities as well as primary actions. Preflight checks the complete union against the environment; a synthetic capability also requires per-run opt-in. Check before acquisition of external resources. Unknown operation descriptors fail closed. Test handlers with counters that remain zero for rejected and inspected scenarios.

A composite domain action may need bounded reads between writes, such as requesting OTP and retrieving its SID before verification. Keep this in a binding handler with a statically declared full operation/capability inventory, one remaining deadline, and recorded substep evidence. The public description does not branch on runtime values. Test one composite consumer handler so later registration integration does not need to bypass preflight or introduce a second scheduler for expectations.

### M2 — Interpret the description with bounded evidence


Implement `Shoko.Runner`, `Shoko.Clock`, `Shoko.Evidence`, and `Shoko.Result` in the core source tree. Provide an injected monotonic clock/sleep effect for tests and a real-clock handler for consumers. Clock injection controls deadlines, not the timestamps of external events. Add an effectful operation interpreter whose resource lifetime encloses a run; always finalize resources after success, rejection after acquisition, timeout, or cancellation. Preserve asynchronous cancellation rather than catching it as an ordinary observation error. Bound each external handler by the remaining budget and do not replay a mutating action automatically after timeout.

Define positive validated durations, environment defaults of 30 seconds total, 10 seconds for eventually, and 100 milliseconds between polls. The total deadline begins before fixtures/actions. An expectation group's activation follows its prerequisite actions; siblings share that activation and remaining budget, so one slow expectation cannot postpone the start of another. Nested `within` uses the minimum enclosing deadline. The implementation may interleave polls deterministically or run bounded concurrent workers; test fairness, one shared deadline, cancellation, and resource cleanup whichever strategy is chosen.

Capture evidence-source baselines after policy resolution/resource acquisition but before the first triggering fixture/action, then start expectation polling after its dependencies are ready. Keep the evidence interval and polling interval separate: event queries include records produced during the action, yet exclude occurrence history before the baseline. If a business key is learned from an action, bind it to the already captured source baseline before querying; never issue an uncorrelated fallback.

Observation results carry typed values plus evidence and coverage, or typed unavailability. A complete empty response differs from an unavailable source. `eventually` passes when a matching witness completes by the deadline. State observations use an explicitly sampled contract: at expiry, all required scheduled reads being conclusive non-matches permits Fail; unresolved read gaps yield Unknown. This does not claim continuous state history. `never` fails on a witness in the pre-action-baseline-to-deadline evidence interval, otherwise waits to the end and requires complete declared interval coverage to Pass. `exactlyOnce` counts unique occurrence IDs over that same bounded evidence interval, fails on the second, and waits until a complete window closes before passing with one or failing with zero. Gaps make the result Unknown unless a decisive witness already proves the result. Recoverable event-history gaps may become complete after a successful catch-up; mutable snapshot gaps cannot be retroactively repaired.

Resolve `ByBusinessKey` or `ByExecutionId` before execution, recording binding support and selected key. A missing required key yields `CorrelationLost` and no uncorrelated query. Retain action failures separately: a definitive domain rejection can be Fail, while a transport timeout with unknown outcome is Unknown. Report and bound cleanup independently; cleanup failure must not erase primary evidence or be silently labelled success.

### M3 — Stabilize consumer usage and results


Use `Shoko.Result.Json` to own the versioned JSON representation with explicit codecs and `schemaVersion`, scenario/run/binding identities, correlation strategy, timestamps/windows, individual expectations, evidence/search coverage, and typed reasons. Include scenario revision and canonical description digest, binary build identity, normalized logical input, and an optional host-supplied `implementationIdentity` containing actual source revisions. The generic runner permits an absent implementation identity for toy/unit runs; the real parity consumer requires it. This keeps later report producers from inventing incompatible metadata fields. Aggregate Fail before Unknown before Pass while retaining child verdicts. Supply structured preflight and runner errors alongside scenario results. Add `schemas/run-result-v1.schema.json` and representative sanitized examples under `shoko-core/test/golden/`. Do not import Kenshou's harness; [its protocol ADR](mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-3) is a vocabulary reference, not an ABI contract.

Create two consuming test scenarios in `shoko-core/test/Consumer/`: an account-provisioning toy with domain state observations and an append-only delivery ledger with duplicate/negative event checks. They justify shared abstractions without embedding TAN types. The same toy scenario must run against two in-memory binding implementations with different internal storage/vocabulary. Add tests in `ScenarioSpec.hs`, `TemporalSpec.hs`, `PolicySpec.hs`, and `ResultSpec.hs` (under the test directory) for constructor validation, temporal boundary cases, property laws on evidence deduplication/verdict aggregation, and wire-codec round trips. Include a short real-clock smoke test with generous bounds only to verify actual cancellation/resource behavior; semantic tests use fake time.

## Concrete Steps


From the repository root, inspect dependencies first, then run the suite as milestones land:

```bash
mori registry search effectful
mori registry show effectful/effectful --full
mori registry docs effectful/effectful
nix develop --command cabal test shoko-core-test --test-show-details=direct
nix develop --command cabal build all
nix develop --command just check
```

The foundation test suite is named `shoko-core-test`; rename its bootstrap stanza to that name if needed. Tests must print successful groups for description/policy, deadlines, coverage, correlation, and results. These are future acceptance commands, not evidence that the implementation already exists.

## Validation and Acceptance


Before expanding adapters, demonstrate the public producer/consumer path: construct a typed toy scenario, inspect it, resolve two bindings, run each, and decode its report. The inspection/action counters prove zero effects until execution. Reject a hidden capability requirement introduced by a binding before its first fixture runs.

Test matches just before, at, and after the deadline with one documented inclusive boundary convention (accept observations completed at or before the deadline); nested windows cannot extend a parent. Test a missing event on a healthy complete source (Fail for eventually), the same query on an unavailable source (Unknown), an empty complete negative window (Pass), a snapshot-only negative window (Unknown for continuous absence), duplicate polls of one ID (one occurrence), two distinct IDs (Fail), and one ID followed by an unrecoverable coverage gap (Unknown). Both siblings start from the same activation and total runtime stays bounded. A missing business key never broadens the query. Interrupt a real-clock run and prove resources finalize. Property tests protect aggregation and deduplication laws; golden/schema checks protect the public wire format.

## Idempotence and Recovery


Core tests require no database or network. Fake-clock tests are repeatable and should not rely on wall-clock sleeps. Record failing Hedgehog seeds when useful. Keep any representation experiment inside the module until the public consumer compiles; discard approaches that require running fixtures to inspect a scenario. Do not weaken evidence coverage to make a test pass. If the real domain contract exposes a missing operation shape, update this plan and the ADR before dependent adapters implement incompatible alternatives.

## Interfaces and Dependencies


Hard dependency: all of `docs/plans/1-bootstrap-the-haskell-workspace-with-seihou-and-jitsurei-standards.md`. Soft dependency: `docs/plans/2-establish-the-first-workflow-contract-and-composed-local-environments.md` M1 for concrete domain examples; absence of a real pair does not block core. This plan owns Scenario/Ref/Action/Observation/Expectation, Environment/Policy, Binding/ResolvedScenario, CorrelationStrategy, Evidence/Coverage/OccurrenceId, Clock, VerificationResult, and JSON codecs. Database and HTTP adapters consume these types; CLI consumes inspection, resolution, execution, and reporting without reimplementing semantics.

Keep result types store-neutral. Evidence includes source and stable record identity but no mandatory PostgreSQL or Kiroku-specific field. The `exactlyOnce` interface must accept occurrence evidence, not arbitrary repeated Boolean snapshots. Downstream bindings advertise coverage strength and capabilities explicitly. Public typed entry points are `inspectScenario`, `resolveScenario`, and `runScenario`; finalize their polymorphic signatures with the two compiling consumers in M1/M3 and keep all three re-exported from `Shoko`.
