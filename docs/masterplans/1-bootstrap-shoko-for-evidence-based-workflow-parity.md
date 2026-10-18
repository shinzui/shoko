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
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-18T17:14:48Z
      mode: "update"
      note: "Validate registration MVP decomposition and separate first-use acceptance from full adapter completion."
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-10-18T17:41:49Z
      mode: "implement"
      note: "Begin foundation implementation; defer staging prerequisites until the owner prepares access."
  reviews:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-18T17:14:48Z
      verdict: "approved"
      note: "Planning review after MVP update: dependencies, ownership, references, and observable acceptance checked; build and live staging proof remain implementation gates."
---

# Bootstrap Shoko for evidence-based staging verification


This MasterPlan is a living coordination document. The registry owns child status; each child owns its milestones. Existing file paths and plan IDs remain stable after the staging-scope correction. The shared intention remains authoritative.

## Vision & Scope


Bootstrap Shōko into a Haskell library and CLI that describe distributed workflows, drive their real operations, gather evidence, and report Pass, Fail, or Unknown. First acceptance verifies the complete system already running in a Kubernetes test namespace. It includes a successful workflow and a documented negative scenario whose expected rejection/invariant produces Pass, plus controls demonstrating actual Fail and Unknown results. No local replacement stack or second implementation is required to satisfy this staging milestone.

The user clarified the deployment target and confirmed staging verification before legacy/Keiro comparison. This supersedes the local-pair acceptance selected from [RES-1](../research/initial-specification-requirement-validation.md), whose service findings still inform domain contracts, correlation, and access prerequisites. The [specification](../intial-spec.md) remains design background with illustrative examples. Follow the required [Jitsurei Haskell practices](mori://shinzui/haskell-jitsurei/docs/core-standards), [Seihou nix-haskell-flake](mori://shinzui/seihou-modules/templates/nix-haskell-flake), and [Settei configuration](mori://shinzui/settei).

Scope includes a reproducible development build and automated checks; an inspectable typed DSL with multiple positive/negative scenarios; named environments and interchangeable implementation bindings; capability preflight; expected domain-outcome handling; correlation; bounded eventually/never/exactlyOnce; HTTP, PostgreSQL, Message DB, and Kiroku evidence; CLI inspection/run/reporting; and attributable acceptance against the existing staging deployment. Generic local adapter fixtures verify Shōko's implementation. CI is an optional automated caller of the same staging command, not the target environment or an obligation to provision the application.

The first usable MVP is a registration-completion regression gate, confirmed by the user on 2026-10-18. It runs the same positive and negative domain requirements against a named deployed rewrite revision and preserves requirement-to-expectation evidence. It requires EP-1, EP-2, EP-3, EP-4, EP-6, and EP-7 Complete, plus only the EP-5 reader milestones required by the accepted workflow. HTTP and PostgreSQL are the baseline; an event store becomes mandatory only when a required assertion needs its durable history. Both generic event readers remain required for full MasterPlan completion, but an unused reader must not delay first use. No assertion may be weakened silently to avoid a reader prerequisite.

After MVP acceptance, an operator can rerun the pinned scenario contract after a service owner deploys a candidate rewrite, identify failed requirements and unavailable evidence, and retain results under the actual workload digests. This provides behavioral regression evidence for registration completion, not automatic legacy/candidate comparison or whole-service rewrite certification. Qualification, other registration flows, deployment conformance, observability, performance, and cutover remain explicitly outside that result's coverage.

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
| 1 | Haskell/Seihou foundation | [Plan 1](../plans/1-bootstrap-the-haskell-workspace-with-seihou-and-jitsurei-standards.md) | None | None | Complete |
| 2 | Registration workflow and Kubernetes staging target | [Plan 2](../plans/2-establish-the-first-workflow-contract-and-composed-local-environments.md) | M1: None; M2: EP-1 | None | Not Started |
| 3 | Inspectable DSL and bounded runner | [Plan 3](../plans/3-implement-inspectable-scenarios-and-the-bounded-verification-runner.md) | EP-1 | EP-2 M1 | Complete |
| 4 | PostgreSQL and HTTP bindings | [Plan 4](../plans/4-implement-postgresql-and-http-evidence-bindings.md) | EP-3 | EP-2 M1 | Not Started |
| 5 | Kiroku and Message DB bindings | [Plan 5](../plans/5-implement-kiroku-and-message-db-evidence-bindings.md) | EP-3; EP-4 M1 | EP-2 M1 | Not Started |
| 6 | CLI inspection, execution, reports | [Plan 6](../plans/6-expose-scenario-inspection-execution-and-structured-reports.md) | EP-3 | EP-4; EP-5 | Not Started |
| 7 | Registration MVP staging acceptance | [Plan 7](../plans/7-verify-one-real-workflow-across-legacy-and-keiro-implementations.md) | EP-2; EP-4; EP-6; selected EP-5 milestones below | None | Not Started |

Status values are Not Started, In Progress, Complete, and Cancelled. Whole-child hard dependencies require Complete. EP-4 M1 means an accepted adapter package and real PostgreSQL observations, not the later HTTP milestone. Historical paths remain valid even where titles changed.

EP-2 M1 records `requiredAdapters` and each assertion's coverage requirement. EP-7 additionally requires EP-5 M1 plus M3's Kiroku contract checks if Kiroku is selected, or EP-5 M2 plus M3's Message DB contract checks if Message DB is selected; both sets apply when both are selected. An empty event-reader selection means no EP-5 hard edge, not a waiver of coverage. EP-5 remains In Progress until both readers and the complete shared suite pass. EP-2 M1 is discovery/contract work and may start before the build; M2 needs the EP-1 tooling.

## Dependency Graph


EP-1 supplies the shared build. EP-2 establishes deployed target access and domain behavior independently of Shōko's runner, avoiding a circular dependency. EP-3 needs the build; EP-4 and EP-6 consume its accepted public contract. EP-5 additionally requires EP-4 M1's adapter package/database integration. EP-7 requires EP-2, EP-4, and EP-6 Complete and the explicitly selected EP-5 milestones. Neither event reader depends on the other.

Default order is EP-2 M1, EP-1, EP-2 M2, EP-3, EP-4, EP-6, any selected EP-5 reader with its M3 checks, and EP-7. Complete the remaining EP-5 work after the first usable MVP. If EP-2 lacks staging access, test identities, an automated OTP path, or a required read source, record the missing prerequisite and owner and continue eligible build/core/adapter/CLI work; return to EP-2 before EP-7. Do not mark a placeholder contract M1 accepted. Shared manifest changes stay with their defining owner. No parallel agents are required.

The readiness gate identifies the actual cluster/namespace, deployed workload revisions, domain owner, controlled inputs, approved external-effect path, and reachable action/evidence endpoints. Independently demonstrate registration completion from an already-qualified agent, including actual account/user writes. The user selected this workflow; changing it requires an explicit scope revision. [Keiro IR-52](mori://shinzui/keiro/okf/improvement-requests/concepts/IR-52) is not presumed complete; business-key correlation avoids that dependency.

## Integration Points


EP-1 owns `cabal.project`, `flake.module.nix`, `justfile`, build CI, Mori registration, dependency selection, and development docs. Local process tools support library/adapter fixtures. EP-4 owns `shoko-adapters.cabal`; EP-5 extends it. Verify current released dependency versions through registries/upstream tags when introducing them, especially shared Hasql constraints. Research survey versions are not pins.

EP-3 owns Scenario/Ref/Action/Observation/Expectation, explicit domain response contracts, Environment/Policy, bindings, clocks, correlation, evidence/coverage, and versioned individual result codecs. A declared domain rejection can be an observed typed action outcome: a negative scenario passes when its rejection and downstream invariants are satisfied. Unexpected rejection remains Fail; transport/decoding uncertainty remains Unknown. EP-4 maps protocol responses into that contract, EP-6 renders it, and EP-7 exercises it in staging. Negative scenario success is distinct from a deliberate Fail control.

EP-2 owns `integration/workflow.json`, `docs/workflows/first-staging-workflow.md`, target/readiness metadata, and `scripts/workflow-env`. It consumes the existing staging system and manages only explicitly owned access resources/test data. EP-7 adds real context-host runs, `integration/config/staging.yaml`, `scripts/run-staging`, the staging acceptance envelope/schema, and the operator tutorial. No application stack provisioning or teardown is part of this interface.

EP-2 also owns `schemas/workflow-v1.schema.json`: stable requirement IDs mapped to scenario/expectation IDs, evidence strength, selected adapters, test-input recipes, and the canonical context-host package/source/build contract. EP-7 validates this mapping and records covered and excluded rewrite requirements in each acceptance envelope; it must not infer whole-service coverage from a workflow Pass. EP-3 owns a separate sanitized logical-input summary, never raw fixture or OTP values. EP-7 owns per-suite/per-scenario/per-run artifact paths and writes each acceptance envelope last as a completion marker. Positive, negative, and control runs cannot overwrite or masquerade as each other.

EP-3 accepts typed host-supplied target identity without depending on Kubernetes. EP-2 resolves expected and observed cluster/namespace/deployment identity. EP-7 retains before/after identity and rejects accepted Pass on mismatch, missing identity, or a changing deployment; individual evidence is preserved. The context owns business semantics; the selected implementation binding supplies actual sources. No report strengthens sampled observations into continuous negative guarantees.

EP-6 owns Settei integration and `runShokoCli`. Defaults precede one explicit YAML file, explicitly bound operational environment variables, and supported named CLI options. Capability grants cannot be enlarged by env/CLI overrides. Synthetic consent remains a separate per-run flag. Staging config contains approved target/access references and bounded settings; inspection is effect-free while the separate integration readiness check performs live reads. Production remains unsupported. A staging label cannot authorize arbitrary production endpoints.

The early integration sequence is two core consumers including positive/negative outcome handling, actual local HTTP -> SQL -> core result, actual event-store append -> read -> cardinality, then one real staging action -> consequence through the context host before expanding the full scenarios. Fake clocks do not replace actual cancellation or event-store transaction visibility checks.

## Progress


EP-1 is Complete on 2026-10-18: Seihou 0.31.0, GHC 9.12.4, the public core package/consumer, Cabal/Nix checks, formatting, and CI configuration are accepted. `just check` passed in the primary tree and a clean detached checkout of `8cb274a`; the managed lock stayed unchanged. The user is preparing the staging context, namespace, test identity, OTP route, and credential references and requested deferring those details until the foundation is built. EP-2 remains Not Started; no concrete staging contract or accepted readiness evidence exists. EP-3 is also Complete: 37 core tests, seven independently schema-validated result examples, and all four native Nix checks pass. EP-4 is the next eligible generic work while staging prerequisites remain pending. No cluster calls, application deployment changes, or staging acceptance runs have occurred. Linux CI is configured but has not been executed in this session.

Completion requires all registry rows Complete, a passing real positive workflow, a passing documented negative scenario, Fail/Unknown controls, and repeatable scoped cleanup/retention in staging. A working library/demo alone cannot complete the initiative. A second implementation is not required.

The earlier MVP release gate is EP-7 Complete with its selected prerequisites accepted. Record that gate separately from full MasterPlan completion so the verifier can be used while an unused event reader remains unfinished. Dependency solver/build acceptance belongs to EP-1 and each package introduction; this document does not certify an unbuilt package set.

## Surprises & Discoveries


EP-3 acceptance fixes role-aware binding contracts and separates a negative evidence cutoff from the deadline for its final closing read. Adapters must enforce selected correlation, advertise sampled versus durable coverage honestly, and never spend cleanup grace on evidence. The stable v1 result codec/schema and two compiling consumers are the shared contract for EP-4 and EP-6.

The researched manual registration path begins with an already-qualified agent. OTP channels and verification SID require reads between commands; a stubbed completion pipeline can report completion without account writes. EP-2 records the actual staging contract, EP-3 supports a fully declared bounded composite action, and EP-7 verifies real downstream outcomes. The source is `mori://tan/registration-service-v2` plus project-relative `docs/plans/2026-07-17-flow-2-staging-validation-plan.md` (artifact-level URI pending), sections 0 and 3–5.

The user's clarification changes the acceptance environment and sequence: staging is an already-running Kubernetes system; CI is only an optional invocation mechanism. Local-pair prerequisites and application lifecycle scripts were planning assumptions, not requirements. Negative scenarios must also distinguish expected domain rejection from a verifier failure.

The 2026-10-18 audit found unnecessary whole-EP-5 serialization, ambiguous artifact paths for multiple scenarios, and no explicit mapping from assertions to rewrite requirements. The update resolves all three. All eight plans were authored by `gpt-6-astra` and had no recorded review entries before this pass; existing provenance is preserved. Mori resolves the cited shared standards and external ADRs. Current local registration source supports the documented endpoint/SID shape and defaults its completion stub off, but source defaults cannot establish deployed configuration; the historical staging warning must be rechecked through EP-2.

## Decision Log


On 2026-10-01, the initial plan selected local migration parity from RES-1 M1 and the specification's revised milestones. That choice is superseded by the user's explicit staging-first acceptance decision; legacy/Keiro comparison remains a later use case.

On 2026-10-01, adopt three packages and one owner per shared interface, value-level capabilities, inspectable descriptions, bounded evidence, and context-owned vocabulary. Preserve these foundations under the staging correction.

On 2026-10-01, select Settei at the CLI/host configuration boundary while core retains policy and scenario semantics.

On 2026-10-01, accept the user's staging and scenario clarifications: verify the existing Kubernetes test namespace, require documented positive and negative scenarios, leave deployments with their owners, and make CI optional. Expected rejection is typed evidence whose expectations can Pass, not a global instruction to treat any failure as success.

On 2026-10-18, select registration completion as the first-use MVP, separate its required-reader gate from full adapter completion, and preserve rewrite requirement coverage, bounded cleanup, and independent scenario artifacts. The source/build preview supports starting implementation; it does not replace solver/build or staging acceptance.

Revision 2026-10-01: replace local paired acceptance with staging system verification; update EP-2/EP-7 responsibilities, supporting core/adapter/CLI contracts, ADRs, README, specification guidance, and the HTML explainer. Preserve stable plan IDs/paths and the shared intention.

## Outcomes & Retrospective


Planning outcome, 2026-10-18: the MVP has an explicit, acyclic implementation route and a real registration acceptance gate. Build feasibility is supported by the successful scaffold preview and inspected dependency/consumer sources, with actual solver, compilation, and staging proof still required. Validation evidence: all eight plan documents passed structural/local-link/fence checks; all 23 canonical Mori references resolved; the milestone graph was acyclic for all four event-reader selections; the explainer JavaScript parsed; and `git diff --check` passed. No implementation outcome is claimed.

Revision 2026-10-18: prioritize the user-selected registration-completion MVP, gate event adapters by required evidence, permit early target discovery, define rewrite requirement coverage and isolated artifacts, and retain the original full-bootstrap obligations after first use. Cascade the contracts into child plans, README, and ADRs 0003/0004.
