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
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-18T17:14:48Z
      mode: "update"
      note: "Clarify terminal actions, bounded cleanup, and sanitized input evidence."
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-10-18T17:48:58Z
      mode: "implement"
      note: "Implement typed descriptions and policy resolution before bounded execution and result codecs."
  reviews:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-18T17:14:48Z
      verdict: "approved"
      note: "Planning review after MVP update: dependencies, ownership, references, and observable acceptance checked; build and live staging proof remain implementation gates."
---

# Implement inspectable scenarios and the bounded verification runner


This ExecPlan is a living document. Keep accepted behavior, interfaces, and remaining milestones current; update the cited ADRs when durable decisions change.

## Purpose / Big Picture


A Haskell consumer can describe actions and evidence expectations once, inspect the description without executing effects, and run it with interchangeable bindings. Deterministic tests show that a source outage produces Unknown, a violated expectation produces Fail, and a supported observation produces Pass within a finite budget.

## Progress


- [x] M1 (2026-10-18): Typed context-owned GADT operations, symbolic/applicative inputs, explicit outcome contracts, and temporal descriptions inspect without IO. The public consumer suite passes seven checks, including zero acquisition/action calls under inspection and denied policy, hidden binding capabilities, synthetic consent, production denial, invalid descriptions, and missing handlers/correlation support.
- [x] M2 (2026-10-18): The effectful runner evaluates eventually, never, and exactlyOnce with inclusive deadlines, scoped correlation, coverage repair, shared sibling activation, terminal-action suppression, and bounded cancellation/finalization. Deterministic boundary/gap/cardinality tests and real-clock cancellation/cleanup checks pass.
- [x] M3 (2026-10-18): Account provisioning (two independent storage bindings and typed rejection) and append-only delivery consumers exercise the public API. All 37 tests pass, including 100 aggregation and 30 deduplication property trials. Seven sanitized v1 envelopes round trip and validate against the independent JSON Schema. `nix develop --command just check` passes Cabal build/tests and all four native Nix checks; `cabal check` reports no warnings. Linux checks remain CI work.

## Surprises & Discoveries


The template's `result` ignore rule also hid the Haskell `Result/` directory on a case-insensitive filesystem: Cabal could see the codec but Nix's Git snapshot could not. Explicit source-directory exceptions now preserve both behavior and reproducible builds. Cabal-gild must finish before Fourmolu reads rewritten package metadata; `just fmt` now has that barrier.

A negative window needs a closing read after its cutoff, within remaining execution time. The request deadline and evidence cutoff are separate; cleanup grace never funds evidence reads. Mutable state cannot repair historical gaps. Role-aware contracts prevent observation support from implying action support.

## Decision Log


On 2026-10-01, keep an inspectable scenario description above effectful, with symbolic references and a fixed initial composition model. This resolves RES-1 F3 while making later inspection consume the same artifact as execution. Define observation/coverage semantics in core so adapters cannot each invent their own treatment of missing evidence.

On 2026-10-18, use `scenario id title revision` with context-owned `Vocabulary op` GADTs, explicit named nodes, and applicative `Input` values. Static dependency descriptions and the binding's additional capabilities resolve before resource acquisition. Response contracts select allowed domain tags; raw operation/input values have no rendering path in inspection. The revision identifies predicate/recipe semantics that cannot be derived from a canonical data description.

On 2026-10-01, clarify multiple positive/negative scenarios and explicit expected domain outcomes after the user asked about negative testing. Preserve Kubernetes-independent core semantics; the integration host supplies actual staging target identity.

## Outcomes & Retrospective


Complete on 2026-10-18. The accepted public contract now spans pure inspection, fail-closed resolution, execution, explicit safe supporting evidence, and versioned reports. Actual cancellation preserves asynchronous exceptions and finalizes scoped resources; expected rejection stays a domain value. Secret-bearing typed values have no automatic serialization path. Durable decisions and build lessons are distilled into ADR 0001–0003 and `docs/core.md`. No service, database, cluster, or staging acceptance is claimed by these core tests. Adapters and the CLI can consume this accepted interface next.

## Context and Orientation


Hard prerequisite `docs/plans/1-bootstrap-the-haskell-workspace-with-seihou-and-jitsurei-standards.md` supplies `shoko-core`, its prelude/test target, and the reproducible build. [RES-1](../research/initial-specification-requirement-validation.md) F2–F10 and M4–M5 motivates the contracts here. [ADR 0002](../adr/0002-keep-scenarios-inspectable-and-bindings-explicit.md) chooses the DSL, capabilities, environments, and correlation. [ADR 0003](../adr/0003-record-bounded-evidence-and-three-valued-results.md) fixes finite temporal semantics and three-valued results. Apply the coding rules in [ADR 0001](../adr/0001-use-jitsurei-standards-and-the-seihou-haskell-flake.md), including strict records, explicit deriving, generic-lens locality, and postpositive qualified imports.

An operation describes a domain action or observation without embedding its environment. A binding supplies the handler for that operation. A `Ref a` is a typed placeholder for a result available only during execution. An expectation judges observations; a coverage record describes the interval a source can actually support. An occurrence identity distinguishes one event/fact from another across repeated polls. The effectful dependency is [effectful](mori://effectful/effectful); its dynamic dispatch source was inspected and provides `interpret`/`reinterpret` for runtime-selected handlers. Resolve source through Mori and verify released package versions before adding bounds. Do not turn the scenario itself into unrestricted `Eff ... IO` code.

## Plan of Work


### M1 — Define one inspectable public contract


Implement `shoko-core/src/Shoko/Scenario.hs`, `Action.hs`, `Observation.hs`, `Expectation.hs`, `Environment.hs`, `Correlation.hs`, and `Binding.hs`, all under `Shoko`. Re-export supported construction functions from `shoko-core/src/Shoko.hs`, keeping internal constructors hidden where needed. Use an extensible typed vocabulary so a downstream context can define its own actions and observations without changing Shōko's closed domain types. A generalized algebraic data type (GADT) retains the result type of each operation; use it or an equivalent type-safe representation, not unchecked casts.

The canonical builder is `scenario scenarioId title $ do ...`: `given` creates a fixture node and returns `Ref a`, `act` creates an action node, and `expect` declares the expectation group. `eventually`, `never`, `exactlyOnce`, and `within` build expectation descriptions, not immediate IO. Model fixture/action dependencies through references. The initial runner supports an ordered fixture/action sequence followed by sibling expectations; do not expose runtime branching or a general workflow scheduler. Reject duplicate IDs, unresolved references, invalid durations, missing handlers, and unsupported implementation/correlation requirements with typed definition/preflight errors.

`inspectScenario` produces stable operation IDs, dependencies, observations, windows, and declared requirements without running handlers. `resolveScenario` combines this with binding requirements into a `ResolvedScenario` and `PolicyReport`. Required capabilities include fixture and cleanup capabilities as well as primary actions. Preflight checks the complete union against the environment; a synthetic capability also requires per-run opt-in. Check before acquisition of external resources. Unknown operation descriptors fail closed. Test handlers with counters that remain zero for rejected and inspected scenarios.

A composite domain action may need bounded reads between writes, such as requesting OTP and retrieving its SID before verification. Keep this in a binding handler with a statically declared full operation/capability inventory, one remaining deadline, and recorded substep evidence. The public description does not branch on runtime values. Test one composite consumer handler so later registration integration does not need to bypass preflight or introduce a second scheduler for expectations.

Each named scenario states the outcomes it expects, including negative business cases. Define typed action response contracts and outcome evidence: a handler can return a documented domain rejection as a value when that operation declares it, enabling an observation/expectation on the returned `Ref` without a hidden runtime branch. A successful negative test Pass means the expected rejection and downstream invariants were observed. An unexpected rejection or unexpected success is a conclusive mismatch; transport, permission-to-observe, or decoding failures that hide the outcome are Unknown. Never add a blanket `expectFailure` switch that converts every error into success. Keep actual HTTP status/error-code decoding in adapters. Include action outcome evidence in versioned results without retaining secrets.

A registry may contain many independently inspectable scenarios with distinct IDs, inputs, and expectations. The existing fixed per-scenario sequence supports valid requests, invalid inputs, authorization rejection, duplicate prevention, and bounded absence/cardinality assertions. Runtime branching, generated traffic, and a concurrent suite scheduler remain separate features.

Environment configuration is independent of the process invoking the runner. The same scenario can run against the named staging binding from an operator shell or automation. Accept optional typed host-supplied `targetIdentity` metadata identifying the approved target, environment, and observed deployment; generic toy tests may omit it, while staging acceptance requires it. Core has no Kubernetes discovery or application lifecycle effects.


### M2 — Interpret the description with bounded evidence


Implement `Shoko.Runner`, `Shoko.Clock`, `Shoko.Evidence`, and `Shoko.Result` in the core source tree. Provide an injected monotonic clock/sleep effect for tests and a real-clock handler for consumers. Clock injection controls deadlines, not the timestamps of external events. Add an effectful operation interpreter whose resource lifetime encloses a run; attempt resource finalization within the cleanup grace budget after success, rejection after acquisition, timeout, or cancellation. Preserve asynchronous cancellation rather than catching it as an ordinary observation error. Bound each external handler by the remaining budget and do not replay a mutating action automatically after timeout.

Define positive validated durations, environment defaults of 30 seconds total, 10 seconds for eventually, and 100 milliseconds between polls. The total deadline begins before fixtures/actions. An expectation group's activation follows its prerequisite actions; siblings share that activation and remaining budget, so one slow expectation cannot postpone the start of another. Nested `within` uses the minimum enclosing deadline. The implementation may interleave polls deterministically or run bounded concurrent workers; test fairness, one shared deadline, cancellation, and resource cleanup whichever strategy is chosen.

Capture evidence-source baselines after policy resolution/resource acquisition but before the first triggering fixture/action, then start expectation polling after its dependencies are ready. Keep the evidence interval and polling interval separate: event queries include records produced during the action, yet exclude occurrence history before the baseline. If a business key is learned from an action, bind it to the already captured source baseline before querying; never issue an uncorrelated fallback.

Observation results carry typed values plus evidence and coverage, or typed unavailability. A complete empty response differs from an unavailable source. `eventually` passes when a matching witness completes by the deadline. State observations use an explicitly sampled contract: at expiry, all required scheduled reads being conclusive non-matches permits Fail; unresolved read gaps yield Unknown. This does not claim continuous state history. `never` fails on a witness in the pre-action-baseline-to-deadline evidence interval, otherwise waits to the end and requires complete declared interval coverage to Pass. `exactlyOnce` counts unique occurrence IDs over that same bounded evidence interval, fails on the second, and waits until a complete window closes before passing with one or failing with zero. Gaps make the result Unknown unless a decisive witness already proves the result. Recoverable event-history gaps may become complete after a successful catch-up; mutable snapshot gaps cannot be retroactively repaired.

Resolve `ByBusinessKey` or `ByExecutionId` before execution, recording binding support and selected key. A missing required key yields `CorrelationLost` and no uncorrelated query. Retain action failures separately: an unexpected definitive domain rejection can be Fail, while a transport timeout with unknown outcome is Unknown. Report and bound cleanup independently; cleanup failure must not erase primary evidence or be silently labelled success.

Define terminal action behavior explicitly: after an unexpected definitive outcome or uncertain transport outcome, do not run subsequent mutating actions or resolve dependent references with fabricated values. Retain the terminal Fail/Unknown and mark unexecuted dependent expectations as Unknown with a prerequisite reason; Fail still dominates aggregation. A declared expected rejection remains an ordinary typed result and can be judged by its negative expectations. Test that no later mutation runs after a terminal outcome.

Separate the execution budget (resource acquisition, baselines, fixtures, actions, expectations) from a finite cleanup grace budget, defaulting to five seconds. A cancelled or expired execution gets at most that grace period for owned-resource finalization; no cleanup retry extends it. Record cleanup status separately, preserving any primary Fail. Required cleanup failure makes an otherwise passing invocation Unknown; an explicitly contracted retention policy counts as successful disposition without deletion. Tests bound execution plus grace and prove a blocked cleanup cannot hang the command. Artifact persistence errors remain command errors owned by the CLI.

### M3 — Stabilize consumer usage and results


Use `Shoko.Result.Json` to own the versioned JSON representation with explicit codecs and `schemaVersion`, scenario/run/binding identities, correlation strategy, timestamps/windows, individual expectations, evidence/search coverage, and typed reasons. Include scenario revision and canonical description digest, binary build identity, a sanitized logical-input summary, and optional host-supplied `implementationIdentity` and `targetIdentity` containing actual implementation/deployment and target identity. The generic runner permits an absent implementation identity for toy/unit runs; the real staging consumer requires observed target/deployment identity and records source revisions when available. This keeps later report producers from inventing incompatible metadata fields. Aggregate Fail before Unknown before Pass while retaining child verdicts. Supply structured preflight and runner errors alongside scenario results. Add `schemas/run-result-v1.schema.json` and representative sanitized examples under `shoko-core/test/golden/`. Do not import Kenshou's harness; [its protocol ADR](mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-3) is a vocabulary reference, not an ABI contract.

The logical-input summary contains only explicitly allowlisted non-secret parameters and an input-recipe revision. Keep generated run/business identities separate from equivalent logical parameters so later runs can use fresh fixtures. Never serialize raw fixture values, OTPs, credentials, or personal payloads, or hash a low-entropy secret as a substitute for redaction. Use stable expectation IDs for EP-7’s requirement mapping. Add a secret-bearing fixture/outcome test proving sentinel values are absent from results, description/input summaries, and error rendering.

Create two consuming test scenarios in `shoko-core/test/Consumer/`: an account-provisioning toy with domain state observations and an append-only delivery ledger with duplicate/negative event checks. They justify shared abstractions without embedding TAN types. The same toy scenario must run against two in-memory binding implementations with different internal storage/vocabulary. Add one typed rejection consumer and tests proving an expected rejection Pass, unexpected success/rejection Fail, and transport uncertainty Unknown; the expected rejection must remain inspectable and retain its actual evidence. Add tests in `ScenarioSpec.hs`, `TemporalSpec.hs`, `PolicySpec.hs`, and `ResultSpec.hs` (under the test directory) for constructor validation, temporal boundary cases, property laws on evidence deduplication/verdict aggregation, and wire-codec round trips. Include a short real-clock smoke test with generous bounds only to verify actual cancellation/resource behavior; semantic tests use fake time.

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

Revision 2026-10-01: add explicit typed domain rejection outcomes for negative scenarios and host-supplied target metadata for staging acceptance.

Revision 2026-10-18: define terminal-action suppression, finite cleanup/disposition, and sanitized input evidence for a repeatable registration rewrite gate.
