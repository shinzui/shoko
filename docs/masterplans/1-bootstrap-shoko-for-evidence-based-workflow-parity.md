---
id: 1
slug: bootstrap-shoko-for-evidence-based-workflow-parity
title: "Bootstrap Shoko for evidence-based staging verification"
kind: master-plan
created_at: 2026-10-02T03:52:02Z
intention: "intention_01m3xdacr3exqajqfcgh9btgev"
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

# Bootstrap Shoko for evidence-based staging verification


This MasterPlan is a living coordination document. The registry owns child status; each child owns its milestones. Existing file paths and plan IDs remain stable after the staging-scope correction. The shared intention remains authoritative.

## Vision & Scope


Bootstrap Shōko into a Haskell library and CLI that describe distributed workflows, drive their real operations, gather evidence, and report Pass, Fail, or Unknown. First acceptance verifies the complete system already running in a Kubernetes test namespace. It includes a successful workflow and a documented negative scenario whose expected rejection/invariant produces Pass, plus controls demonstrating actual Fail and Unknown results. No local replacement stack or second implementation is required to satisfy this staging milestone.

The user clarified the deployment target and confirmed staging verification before legacy/Keiro comparison. This supersedes the local-pair acceptance selected from [RES-1](../research/initial-specification-requirement-validation.md), whose service findings still inform domain contracts, correlation, and access prerequisites. The [specification](../intial-spec.md) remains design background with illustrative examples. Follow the required [Jitsurei Haskell practices](mori://shinzui/haskell-jitsurei/docs/core-standards), [Seihou nix-haskell-flake](mori://shinzui/seihou-modules/templates/nix-haskell-flake), and [Settei configuration](mori://shinzui/settei).

Scope includes a reproducible development build and automated checks; an inspectable typed DSL with multiple positive/negative scenarios; named environments and interchangeable implementation bindings; capability preflight; expected domain-outcome handling; correlation; bounded eventually/never/exactlyOnce; HTTP, PostgreSQL, Message DB, and Kiroku evidence; CLI inspection/run/reporting; and attributable acceptance against the existing staging deployment. Generic local adapter fixtures verify Shōko's implementation. CI is an optional automated caller of the same staging command, not the target environment or an obligation to provision the application.

Production execution, continuous Observe, Replay, causality, service rewrites, application deployment/lifecycle management, type-level safety proofs, generic Kafka/PGMQ/PubSub observers, trace/Prometheus querying, and migration parity comparison are outside this bootstrap. Domain scenarios remain portable so later parity can run the same meanings through another binding and compare retained results. Building both generic event-store adapters does not require installing both stores into staging.

## Decomposition Strategy


Seven work streams retain clear responsibilities: build foundation; staging workflow/access contract; descriptions and bounded runner; SQL/HTTP; durable event readers; configuration/CLI/reporting; and actual staging acceptance. Target access is investigated early. Generic core and adapter work can proceed while credentials or test facilities are resolved, but mocks cannot satisfy staging acceptance. The existing system is owned by its deployment team; Shōko owns verification and run-scoped test data/access resources.

Use three initial packages: `shoko-core`, `shoko-adapters`, and `shoko-cli` with a reusable host library. Context-owned packages define business vocabulary and scenarios. Keep generic semantics in core and concrete transport/evidence logic in adapters. Kubernetes discovery/access lives in the integration layer and supplies typed target metadata; core remains independent of Kubernetes libraries.

The local decisions are [ADR 0001](../adr/0001-use-jitsurei-standards-and-the-seihou-haskell-flake.md) for Haskell/build standards, [ADR 0002](../adr/0002-keep-scenarios-inspectable-and-bindings-explicit.md) for descriptions/capabilities/outcomes/configuration, [ADR 0003](../adr/0003-record-bounded-evidence-and-three-valued-results.md) for temporal evidence/results, and [ADR 0004](../adr/0004-gate-parity-on-real-workflows-and-context-owned-vocabulary.md) for staging acceptance/domain ownership. The repository has ordinary Markdown ADRs; the Mori manifest profiles only research, so no unrelated ADR corpus migration is required.

Previously consulted external decisions remain relevant: [Kenshou's result protocol](mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-3), [resolved identity](mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-2), and the [platform rewrite gates](mori://tan/tan-platform/docs/adr-0002-track-infrastructure-and-observability-as-rewrite-gates). Adopt their useful reasoning without claiming wire compatibility or whole-platform readiness.

Research F2/F3/F5/F7/F10/F12 inform EP-3/EP-6; F4/F8/F9 inform evidence/results; F11/M4 inform context ownership; F15 informs the small package graph. S1/S2/S5–S8 inform EP-2/EP-7's actual staging contract and controlled effects. M2/M5 inform event/correlation support. F6/F13 (continuous observation), F14/M6 (replay), S4 (trace querying), and S9 (production infrastructure) remain later work. The user's environment and first-acceptance decisions supersede RES-1's local-pair sequencing recommendation.

## Exec-Plan Registry


| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| 1 | Haskell/Seihou foundation | [Plan 1](../plans/1-bootstrap-the-haskell-workspace-with-seihou-and-jitsurei-standards.md) | None | None | Not Started |
| 2 | Workflow and Kubernetes staging target | [Plan 2](../plans/2-establish-the-first-workflow-contract-and-composed-local-environments.md) | EP-1 | None | Not Started |
| 3 | Inspectable DSL and bounded runner | [Plan 3](../plans/3-implement-inspectable-scenarios-and-the-bounded-verification-runner.md) | EP-1 | EP-2 M1 | Not Started |
| 4 | PostgreSQL and HTTP bindings | [Plan 4](../plans/4-implement-postgresql-and-http-evidence-bindings.md) | EP-3 | EP-2 M1 | Not Started |
| 5 | Kiroku and Message DB bindings | [Plan 5](../plans/5-implement-kiroku-and-message-db-evidence-bindings.md) | EP-3; EP-4 M1 | EP-2 M1 | Not Started |
| 6 | CLI inspection, execution, reports | [Plan 6](../plans/6-expose-scenario-inspection-execution-and-structured-reports.md) | EP-3 | EP-4; EP-5 | Not Started |
| 7 | Real staging scenario acceptance | [Plan 7](../plans/7-verify-one-real-workflow-across-legacy-and-keiro-implementations.md) | EP-2; EP-4; EP-5; EP-6 | None | Not Started |

Status values are Not Started, In Progress, Complete, and Cancelled. Whole-child hard dependencies require Complete. EP-4 M1 means an accepted adapter package and real PostgreSQL observations, not the later HTTP milestone. Historical paths remain valid even where titles changed.

## Dependency Graph


EP-1 supplies the shared build. EP-2 establishes deployed target access and domain behavior independently of Shōko's runner, avoiding a circular dependency. EP-3 needs the build; EP-4 and EP-6 consume its accepted public contract. EP-5 additionally requires EP-4 M1's adapter package/database integration. EP-7 requires all four named children Complete and consumes only the evidence sources needed by the actual staging workflows.

Default order is EP-1, EP-2, EP-3, EP-4, EP-5, EP-6, EP-7. Attempt EP-2 M1 early. If staging access, test identities, or a required read source is unavailable, record the precise prerequisite and continue eligible EP-3–EP-6 work; return to EP-2 before EP-7. This does not waive EP-7's accepted-target prerequisite. Shared manifest changes stay with their defining owner. No parallel agents are required.

The readiness gate identifies the actual cluster/namespace, deployed workload revisions, domain owner, controlled inputs, approved external-effect path, and reachable action/evidence endpoints. Independently demonstrate the real staging workflow. Registration completion is the reference slice; select a documented deployed workflow rather than requiring a service rewrite. [Keiro IR-52](mori://shinzui/keiro/okf/improvement-requests/concepts/IR-52) is not presumed complete; business-key correlation avoids that dependency.

## Integration Points


EP-1 owns `cabal.project`, `flake.module.nix`, `justfile`, build CI, Mori registration, dependency selection, and development docs. Local process tools support library/adapter fixtures. EP-4 owns `shoko-adapters.cabal`; EP-5 extends it. Verify current released dependency versions through registries/upstream tags when introducing them, especially shared Hasql constraints. Research survey versions are not pins.

EP-3 owns Scenario/Ref/Action/Observation/Expectation, explicit domain response contracts, Environment/Policy, bindings, clocks, correlation, evidence/coverage, and versioned individual result codecs. A declared domain rejection can be an observed typed action outcome: a negative scenario passes when its rejection and downstream invariants are satisfied. Unexpected rejection remains Fail; transport/decoding uncertainty remains Unknown. EP-4 maps protocol responses into that contract, EP-6 renders it, and EP-7 exercises it in staging. Negative scenario success is distinct from a deliberate Fail control.

EP-2 owns `integration/workflow.json`, `docs/workflows/first-staging-workflow.md`, target/readiness metadata, and `scripts/workflow-env`. It consumes the existing staging system and manages only explicitly owned access resources/test data. EP-7 adds real context-host runs, `integration/config/staging.yaml`, `scripts/run-staging`, the staging acceptance envelope/schema, and the operator tutorial. No application stack provisioning or teardown is part of this interface.

EP-3 accepts typed host-supplied target identity without depending on Kubernetes. EP-2 resolves expected and observed cluster/namespace/deployment identity. EP-7 retains before/after identity and rejects accepted Pass on mismatch, missing identity, or a changing deployment; individual evidence is preserved. The context owns business semantics; the selected implementation binding supplies actual sources. No report strengthens sampled observations into continuous negative guarantees.

EP-6 owns Settei integration and `runShokoCli`. Defaults precede one explicit YAML file, explicitly bound operational environment variables, and supported named CLI options. Capability grants cannot be enlarged by env/CLI overrides. Synthetic consent remains a separate per-run flag. Staging config contains approved target/access references and bounded settings; inspection is effect-free while the separate integration readiness check performs live reads. Production remains unsupported. A staging label cannot authorize arbitrary production endpoints.

The early integration sequence is two core consumers including positive/negative outcome handling, actual local HTTP -> SQL -> core result, actual event-store append -> read -> cardinality, then one real staging action -> consequence through the context host before expanding the full scenarios. Fake clocks do not replace actual cancellation or event-store transaction visibility checks.

## Progress


Planning is complete; implementation has not started and all seven children are Not Started. EP-1 is immediately eligible. The user has confirmed a complete staging system exists in a Kubernetes test namespace; its exact access, deployed identity, test facilities, and workflow have not been verified here. No cluster calls, application deployment changes, Haskell tests, or staging acceptance runs have occurred during planning.

Completion requires all registry rows Complete, a passing real positive workflow, a passing documented negative scenario, Fail/Unknown controls, and repeatable scoped cleanup/retention in staging. A working library/demo alone cannot complete the initiative. A second implementation is not required.

## Surprises & Discoveries


The researched manual registration path begins with an already-qualified agent. OTP channels and verification SID require reads between commands; a stubbed completion pipeline can report completion without account writes. EP-2 records the actual staging contract, EP-3 supports a fully declared bounded composite action, and EP-7 verifies real downstream outcomes. The source is `mori://tan/registration-service-v2` plus project-relative `docs/plans/2026-07-17-flow-2-staging-validation-plan.md` (artifact-level URI pending), sections 0 and 3–5.

The user's clarification changes the acceptance environment and sequence: staging is an already-running Kubernetes system; CI is only an optional invocation mechanism. Local-pair prerequisites and application lifecycle scripts were planning assumptions, not requirements. Negative scenarios must also distinguish expected domain rejection from a verifier failure.

## Decision Log


On 2026-10-01, the initial plan selected local migration parity from RES-1 M1 and the specification's revised milestones. That choice is superseded by the user's explicit staging-first acceptance decision; legacy/Keiro comparison remains a later use case.

On 2026-10-01, adopt three packages and one owner per shared interface, value-level capabilities, inspectable descriptions, bounded evidence, and context-owned vocabulary. Preserve these foundations under the staging correction.

On 2026-10-01, select Settei at the CLI/host configuration boundary while core retains policy and scenario semantics.

On 2026-10-01, accept the user's staging and scenario clarifications: verify the existing Kubernetes test namespace, require documented positive and negative scenarios, leave deployments with their owners, and make CI optional. Expected rejection is typed evidence whose expectations can Pass, not a global instruction to treat any failure as success.

Revision 2026-10-01: replace local paired acceptance with staging system verification; update EP-2/EP-7 responsibilities, supporting core/adapter/CLI contracts, ADRs, README, specification guidance, and the HTML explainer. Preserve stable plan IDs/paths and the shared intention.

## Outcomes & Retrospective


<!-- Record implementation outcomes here as they become available. -->
