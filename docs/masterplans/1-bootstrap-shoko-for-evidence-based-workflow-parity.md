---
id: 1
slug: bootstrap-shoko-for-evidence-based-workflow-parity
title: "Bootstrap Shoko for evidence-based workflow parity"
kind: master-plan
created_at: 2026-10-02T03:52:02Z
provenance:
  created_by:
    model: "gpt-6-astra"
    harness: "codex-cli"
    at: 2026-10-02T03:52:02Z
  revisions:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-02T04:14:56Z
      mode: "discuss"
      note: "Select Settei for typed YAML, environment, and CLI configuration with provenance and secret-safe diagnostics."
---

# Bootstrap Shoko for evidence-based workflow parity


This MasterPlan is a living coordination document. The registry owns child status; each child owns its milestones. Update durable project decisions in `docs/adr/` alongside material implementation changes.

## Vision & Scope


Bootstrap Shōko from its specification/research-only repository into a Haskell library and CLI that describe a distributed workflow once, obtain evidence through selected bindings, and report Pass, Fail, or Unknown with bounded, attributable evidence. Completion includes one real local parity run: the same domain scenario verifies both the legacy and Keiro implementations of a workflow. The local verification library remains useful while application prerequisites are being built, but fixture success alone cannot complete this initiative.

The primary requirements are [RES-1](../research/initial-specification-requirement-validation.md), especially recommendations 2–8 and rewrite findings M1–M8, and the revised milestones in [the specification](../intial-spec.md). F1's duplicate-text cleanup is already recorded as resolved; do not repeat it. A bootstrap note now marks older scenario examples as illustrative. The user's additions require [Jitsurei Haskell practices](mori://shinzui/haskell-jitsurei/docs/core-standards) and [Seihou nix-haskell-flake](mori://shinzui/seihou-modules/templates/nix-haskell-flake).

Scope includes a reproducible development/CI build; an inspectable typed DSL; named environments and implementation bindings; value-level capability policy; explicit business-key/execution-id correlation; eventually, never, and exactlyOnce with finite windows; SQL, HTTP, Message DB, and Kiroku evidence; CLI inspection/run/reporting; and one real composed local workflow pair. Generic PostgreSQL observations are the complete baseline for non-Haskell legacy services. Kiroku is the target evidence substrate and Message DB support remains thin.

Do not implement service rewrites, legacy instrumentation, type-level safety proofs, production/staging execution, Observe mode, replay, continuous monitoring, causality operators, a general Kafka/PGMQ/PubSub adapter, trace/Prometheus querying, property-generated distributed traffic, or scenario visualization in this initiative. Kafka may still be needed inside a real application's local stack. Future input replay is valuable for migration (M6), but remains a follow-up rather than an extra bootstrap dependency.

## Decomposition Strategy


Seven work streams preserve independently testable behavior: reproducible builds; actual workflow/environment readiness; pure descriptions and a bounded runner; general SQL/HTTP IO; durable event evidence; operator/CI access; and real parity acceptance. The environment work starts early because missing real systems are the largest external risk. Core and adapters can proceed without fabricating those systems. SQL/HTTP and event readers are separated because their coverage, identity, and legacy compatibility risks differ; they still share one adapter package. Inspection and reporting are one CLI stream because they must consume the same core protocol.

At creation there were no local ADR files and `mori.dhall` declared only a research bundle, so no existing profiled ADR contract applied. Before child creation, record [ADR 0001: build and Haskell standards](../adr/0001-use-jitsurei-standards-and-the-seihou-haskell-flake.md), [ADR 0002: DSL, capability, environment, correlation](../adr/0002-keep-scenarios-inspectable-and-bindings-explicit.md), [ADR 0003: temporal evidence and results](../adr/0003-record-bounded-evidence-and-three-valued-results.md), and [ADR 0004: real parity and vocabulary ownership](../adr/0004-gate-parity-on-real-workflows-and-context-owned-vocabulary.md). These resolve research recommendation 2 without adding an unrelated OKF migration.

Relevant external decisions consulted were [Kenshou ADR-3](mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-3), which owns its versioned verification protocol, [Kenshou ADR-2](mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-2), which requires actual resolved identities, and the [platform rewrite-gates ADR](mori://tan/tan-platform/docs/adr-0002-track-infrastructure-and-observability-as-rewrite-gates), which separates declarations from operational evidence. Shōko adopts compatible reasoning and result vocabulary without depending on Kenshou's full harness or claiming its wire protocol.

Start with core, then one adapters package, then a CLI package with reusable host library. Avoid the specification's seven-package day-one split until independent consumers justify it. Production vocabulary belongs beside the bounded context; test/demo vocabulary in Shōko is explicitly labelled. A single giant plan would hide external readiness and shared contracts; a separate child per type/file would obscure meaningful behavior.

Research traceability is explicit: F2/F3/F5/F7/F10/F12 are owned by EP-3's description/policy/correlation contract and EP-6's configuration; F4/F8/F9 by EP-3's coverage/results and EP-6's exits; F11/M4 by EP-2/EP-7's context ownership; F15 by EP-1's small package graph. S1/S2/S5/S6/S7/S8 and M1/M3/M8 drive EP-2's actual workflow contract and EP-7's real acceptance. S3/M7 constrain transport scope; M2/M5 drive EP-5's target event evidence and honest correlation support. F6/F13 (Observe binding/baseline), F14/M6 (replay), S4 (trace querying), and S9 (production replicas) remain explicit later work, not assumed bootstrap capabilities.

## Exec-Plan Registry


| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| 1 | Haskell/Seihou foundation | [Plan 1](../plans/1-bootstrap-the-haskell-workspace-with-seihou-and-jitsurei-standards.md) | None | None | Not Started |
| 2 | First workflow and local environments | [Plan 2](../plans/2-establish-the-first-workflow-contract-and-composed-local-environments.md) | EP-1 | None | Not Started |
| 3 | Inspectable DSL and bounded runner | [Plan 3](../plans/3-implement-inspectable-scenarios-and-the-bounded-verification-runner.md) | EP-1 | EP-2 M1 | Not Started |
| 4 | PostgreSQL and HTTP bindings | [Plan 4](../plans/4-implement-postgresql-and-http-evidence-bindings.md) | EP-3 | EP-2 M1 | Not Started |
| 5 | Kiroku and Message DB bindings | [Plan 5](../plans/5-implement-kiroku-and-message-db-evidence-bindings.md) | EP-3; EP-4 M1 | EP-2 M1 | Not Started |
| 6 | CLI inspection, execution, reports | [Plan 6](../plans/6-expose-scenario-inspection-execution-and-structured-reports.md) | EP-3 | EP-4; EP-5 | Not Started |
| 7 | Real workflow parity | [Plan 7](../plans/7-verify-one-real-workflow-across-legacy-and-keiro-implementations.md) | EP-2; EP-4; EP-5; EP-6 | None | Not Started |

Status values are Not Started, In Progress, Complete, and Cancelled. Whole-child hard dependencies require Complete. EP-4 M1 specifically means an accepted adapter package plus working typed PostgreSQL observations; it does not require the HTTP milestone.

## Dependency Graph


EP-1 supplies the build for every other stream. EP-2 uses its local process/database tools but verifies services independently of Shōko, avoiding a cycle with the runner. EP-3 requires the build, not a finished service rewrite. EP-4 and EP-6 consume EP-3's accepted public contract. EP-5 additionally needs EP-4 M1's real adapter package/PostgreSQL integration. EP-7 requires both accepted actual environments and all production-facing adapters/CLI. There are no cyclic dependencies.

Default execution is EP-1, EP-2, EP-3, EP-4, EP-5, EP-6, EP-7. At EP-2, attempt M1 early; if the real pair is unavailable, retain the precise upstream blocker and continue EP-3 through EP-6. Return to EP-2 before EP-7. This scheduling exception does not waive EP-7's whole-child prerequisite. If contributors work concurrently, EP-2 and EP-3 can proceed after EP-1, EP-6 can proceed after EP-3, and event work can begin after EP-4 M1. Shared manifests remain serialized through their defining owner. No parallel agents are required by this plan.

The external readiness gate is concrete: the workflow contract names actual source revisions, a context vocabulary owner, controlled inputs, and public actions/read paths, and both composed stacks pass independent smoke runs. Registration is the research reference; choose another first-ready pair only with demonstrated implementations and an updated domain contract. [Keiro IR-52](mori://shinzui/keiro/okf/improvement-requests/concepts/IR-52) is proposed, so execution-id propagation is not presumed. An explicitly supported business-key strategy avoids making that stronger contract a hard bootstrap dependency.

## Integration Points


EP-1 owns `cabal.project`, `flake.module.nix`, `justfile`, CI, Mori package registration, dependency selections, and development documentation. Other plans extend these deliberately without changing the Seihou-managed flake/toolchain. EP-4 creates/owns `shoko-adapters.cabal`; EP-5 adds event modules and dependency selections to it. Dependency versions must be checked against registries and upstream tags when introduced; no research survey version is a pin. Watch the shared Hasql constraints when combining Message DB and Kiroku before adding compatibility overrides.

EP-3 owns public `Shoko` types and runtime semantics: symbolic references, operations, bindings, policy, clocks, correlation, evidence/coverage, and result codecs/schema. EP-4/EP-5 construct evidence through those types; EP-6 renders and executes through them. The earliest proof is EP-3's two compiling toy consumers and binding-interchange test. EP-4 then proves HTTP action -> PostgreSQL row -> core result before expanding query variants; EP-5 proves actual store append -> event read -> core cardinality before expanding event filters. Real-clock cancellation and database transaction visibility must not contradict fake-clock or cursor assumptions.

EP-2 owns `integration/workflow.json`, `docs/workflows/first-parity-workflow.md`, source/readiness identities, local stack composition, and lifecycle scripts. EP-7 consumes those contracts, adding domain-host integration and paired reports. The selected context owns actual business vocabulary and scenario semantics; neither a legacy binding nor a generic Shōko module may define them independently. Changing the first workflow updates both EP-2 and EP-7 and the relevant ADR.

EP-6 owns `runShokoCli`, registry/config decoding, commands, and exit codes; EP-3 owns individual result JSON. EP-7 owns `schemas/parity-result-v1.schema.json` and immutable paired comparisons. Its separate consumer-host test proves registration before real domain integration. Results carry actual scenario/binding/source identities, normalized logical inputs, and the chosen correlation strategy. No report may strengthen sampled or incomplete evidence into a continuous negative guarantee.

EP-6 uses [Settei](mori://shinzui/settei) with its YAML, environment, and optparse-applicative adapters for typed configuration, deterministic precedence, provenance, and secret-safe diagnostics. It owns the Shōko declaration and passes resolved values to EP-3's environment/policy types; core stays independent of configuration sources. EP-7's context host reuses that path. Declared defaults precede the explicit YAML file, explicitly bound operational environment variables, and supported named CLI options. Capability grants cannot be enlarged by env/CLI overrides, and synthetic consent remains a separate per-run flag. EP-6's real Settei resolution test is the acceptance owner for this shared configuration boundary.

## Progress


Planning is complete; implementation has not started and all seven children are Not Started. The repository remains specification/planning-only. EP-1 is immediately eligible. Both composed real workflow environments and a context-owned vocabulary are unverified external prerequisites for EP-2/EP-7, not assumed deliverables already present. The template preview succeeded without writing the scaffold. No Haskell tests, service runs, or parity acceptance have been performed.

Completion requires all registry rows Complete and EP-7's real paired Pass plus Fail/Unknown controls. A working generic library/demo is an intermediate outcome, not an alternative completion criterion. Each child owns its acceptance evidence; do not duplicate its milestones here.

## Surprises & Discoveries


The manual workflow source linked by RES-1 selects registration completion from an already-qualified agent as the shortest real path. OTP channels and the verification SID come from status reads between commands, and a stubbed completion pipeline can claim completion without downstream account writes. EP-2 now freezes that narrower reference slice and rejects such stubbed parity; EP-3 permits a fully declared, bounded composite domain action; EP-7 checks the actual downstream outcomes. The source is `mori://tan/registration-service-v2` plus project-relative `docs/plans/2026-07-17-flow-2-staging-validation-plan.md` (artifact-level URI pending), sections 0 and 3–5. No service was run during planning.

## Decision Log


On 2026-10-01, make migration parity the first full acceptance target, following RES-1 M1 and the specification's Revised Milestones rather than its older local/staging milestone. Keep environment readiness early but outside the generic core's hard dependencies so a missing service rewrite does not force fictitious test evidence.

On 2026-10-01, adopt a three-package initial architecture and one owner for each shared contract. The adapter streams separate generic state/HTTP behavior from durable occurrence semantics without requiring separate package releases. Add Kiroku alongside the initial HTTP/PostgreSQL/Message DB set because the rewrite findings make it the primary target evidence store.

On 2026-10-01, resolve capability, DSL, temporal/result, correlation, and vocabulary decisions in local ADRs before child drafting. Require explicit coverage for negative evidence and preserve business-key fallback as a declared binding choice. Keep unavailable real parity dependencies visible through completion rather than reclassifying fixtures as a successful migration proof.

On 2026-10-01, select Settei for configuration following the user's question. Its existing typed resolver and source adapters replace an unspecified configuration implementation; the CLI owns integration and core retains policy enforcement. Update ADR 0002 and EP-6 together.

Revision 2026-10-01: make Settei explicit at the shared configuration boundary, including provenance/redaction and precedence acceptance. No work-stream or dependency ordering changes.

## Outcomes & Retrospective


<!-- Record implementation outcomes here as they become available. -->
