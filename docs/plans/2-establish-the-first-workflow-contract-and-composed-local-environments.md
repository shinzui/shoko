---
id: 2
slug: establish-the-first-workflow-contract-and-composed-local-environments
title: "Establish the first workflow contract and Kubernetes staging target"
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

# Establish the first workflow contract and Kubernetes staging target


This ExecPlan is a living document. Its existing path and identifier remain stable after the staging-scope correction. The acceptance target is the complete system already running in a Kubernetes test namespace.

## Purpose / Big Picture


A contributor can identify the deployed staging system, access its real action and evidence endpoints, submit controlled test inputs, and independently confirm a workflow's durable outcome. Shōko connects to that existing system; it does not need to recreate the application as local services or provision it in a CI job. This contract supplies the target and domain meaning for the final verification run.

## Progress


- [ ] M1: A checked workflow contract identifies the deployed staging target, domain owner, real actions, evidence sources, correlation, controlled inputs, and permitted external effects.
- [ ] M2: Repeatable access and independent workflow smoke checks succeed against the existing Kubernetes test namespace, retaining actual target/deployment identity and run-owned cleanup evidence.

## Surprises & Discoveries


The user confirmed that staging is a complete running system in a Kubernetes test namespace, and that verifying this system comes before legacy/Keiro comparison. The cluster/context, namespace name, current deployment identities, access route, and test credentials have not yet been inspected. Those concrete values are implementation inputs; the research's missing local pair is no longer a bootstrap prerequisite.

## Decision Log


On 2026-10-01, the initial plan required composing local legacy/Keiro environments. The user's clarification supersedes that choice: connect to the existing staging deployment, prove its real workflow, and leave application lifecycle management with its deployment owners. CI means an optional automated caller of the same verifier, not a separate system under test.

## Outcomes & Retrospective


## Context and Orientation


The build foundation comes from `docs/plans/1-bootstrap-the-haskell-workspace-with-seihou-and-jitsurei-standards.md`. [RES-1](../research/initial-specification-requirement-validation.md) S1–S9 remains evidence about the surveyed workflow and access prerequisites; its recommendation to compose local pairs is superseded for first acceptance by the user's staging requirement. [ADR 0004](../adr/0004-gate-parity-on-real-workflows-and-context-owned-vocabulary.md) defines staging acceptance and domain ownership. [ADR 0002](../adr/0002-keep-scenarios-inspectable-and-bindings-explicit.md) requires explicit correlation and environment policy.

A namespace identifies a set of Kubernetes resources; the workflow can also use databases, brokers, and external providers outside it. Inventory those dependencies and their actual targets. Do not assume that selecting a namespace isolates all downstream effects. No cluster access or deployment changes have occurred during planning.

Registration completion from an already-qualified agent is the researched reference. Its durable business key is `registrationId`; real account/user outcomes must be checked. The actual deployed system determines the first available workflow, without requiring a matching second implementation. Use Mori to inspect [registration-service-v2](mori://tan/registration-service-v2), [account-service-v2](mori://tan/account-service-v2), [mls-service-v2](mori://tan/mls-service-v2), and [modernization coverage](mori://tan/tan-platform/docs/platform-modernization-coverage). The manual reference is `mori://tan/registration-service-v2` plus project-relative `docs/plans/2026-07-17-flow-2-staging-validation-plan.md` (artifact-level URI pending). Recheck current deployed contracts rather than treating the historical document as live configuration.

## Plan of Work


### M1 — Freeze the workflow and deployed target contract


Create `docs/workflows/first-staging-workflow.md` and `integration/workflow.json`. Record the real domain operation, expected consequences, action/read endpoints, evidence strength, business-key extraction, supported test identities, capability requirements, external-effect handling, and cleanup mechanism. The context owns the vocabulary and scenario package. Registration is the reference; another deployed workflow is acceptable with an explicit domain contract and retained reason for selection.

Use a manifest with `schemaVersion`, `workflowId`, `scenarioId`, `scenarioRevision`, `vocabularyOwner`, `vocabularyModule`, `logicalInput`, and `target`. The target records environment and implementation binding names, expected cluster/context and namespace identity, deployed workload identities, immutable image digests and source revisions where available, endpoint/evidence-source references, credential environment-variable names, access route, correlation strategy/key, and readiness with concrete reasons. Record observed deployed identities separately from expected labels. Pin the namespace UID when available so recreating a namespace cannot silently reuse a previous approval. The implementation name is independent of environment and is not restricted to a presumed legacy/Keiro pair. Store references rather than credentials or personal payloads.

Choose and document an access route supported by the actual staging setup: reachable ingress/internal endpoints, an approved tunnel, or execution inside the test namespace. The initial command-line runner can run wherever those routes and credentials work. An in-cluster Job is optional packaging, not a new core dependency or acceptance requirement. Use existing deployment tooling and namespace-scoped access; do not add a Kubernetes client to `shoko-core`. Consult official Kubernetes documentation and repository deployment instructions when implementing actual API/CLI integration.

For the registration reference (`registration-completion-staging`), arrange a valid qualified-agent fixture using the service's supported facility, start through `POST /v1/registrations/from-qualified-agent`, read OTP channels from `GET /v1/registrations/{id}`, request OTP, read `verificationSid` from that GET, and verify with code and SID. Acknowledgements do not provide the channel/SID fields. Record the staging delivery mode and controlled recipients: use an existing supported test delivery path where configured; real provider delivery needs a documented test recipient and its permitted effects. Do not assume a local stub exists in staging or change deployment flags implicitly. Qualification/approval is a precondition of this slice, not behavior claimed by it.

Map registration completion, account existence, user existence, and duplicate prevention to actual read sources. A completion stub that skips account/auth writes cannot support an assertion that those consequences happened. Use machine-callable REST or scoped read-only database access rather than presuming browser-session GraphQL works. Prefer business-key correlation unless execution-ID propagation is demonstrated. Keiro's [IR-52](mori://shinzui/keiro/okf/improvement-requests/concepts/IR-52) remains the owner of that stronger contract. An unavailable credential, test identity, external-effect route, or evidence source is an explicit unmet staging prerequisite, not permission to substitute a local mock.

Also freeze at least one documented negative scenario in `negativeScenarios` alongside the primary `scenarioId`: an expected input/authentication/domain rejection or duplicate-prevention path supported by the deployed API. Each entry states allowed typed response outcomes, the precise expected rejection or invariant, relevant downstream state/history evidence, and an isolated test identity. Candidate cases such as invalid OTP must be confirmed against the actual service contract. Do not presume any 4xx response is sufficient, use real customer identities, or equate network failure with expected rejection. A successful negative scenario has verdict Pass; the final plan separately demonstrates deliberate Fail/Unknown controls.

### M2 — Verify access and independently exercise the running system


Create `scripts/workflow-env` with `check` and `smoke` commands and `just workflow-check` / `just workflow-smoke` wrappers consuming the explicit manifest. `check` performs read-only target discovery, validates the expected cluster/namespace and actual deployment identities, checks endpoint/evidence connectivity and permitted test setup, and produces a sanitized readiness record. Never silently use the current kube context or a default namespace. The target contract must relate each application/evidence endpoint to the approved staging deployment, including resources outside Kubernetes. A test namespace label cannot authorize a production endpoint.

`smoke` drives the contracted real workflow with fresh test identities and independently checks its durable consequences using current service tools or scoped SQL, without depending on Shōko's runner. Record deployed identities before and after the run; a changed or unverifiable target prevents acceptance until repeated against a stable deployment. Demonstrate two runs with isolated business keys. A health check alone is not workflow acceptance.

These scripts do not deploy, scale, restart, migrate, or delete application workloads, create a replacement stack, reset shared databases/brokers, or remove the namespace. If a documented access route needs a verifier-owned tunnel or Job, manage only that resource. Domain cleanup uses supported APIs or specifically scoped operations against test records owned by this run. If deletion is unsupported, document bounded retention and ownership instead of claiming teardown. Required changes to staging infrastructure or service test facilities remain explicit work with their owners.

## Concrete Steps


At the repository root after the foundation is Complete, resolve the domain/deployment sources through Mori and obtain the actual staging context, namespace, access route, and credential references from the environment owner. Do not invent these values or automatically select them from a developer's current shell.

The following are interfaces this plan creates:

```bash
nix develop --command just workflow-check
nix develop --command just workflow-smoke
```

The wrappers load `integration/workflow.json` explicitly and reject missing or mismatched target identity before mutating actions. `workflow-check` reports the selected staging namespace, observed deployment identities, access/readiness status, and exact missing prerequisites with a nonzero exit when unusable. `workflow-smoke` records fresh business keys and actual domain consequences. Retain sanitized artifacts in an ignored run directory; describe its location in `docs/workflows/first-staging-workflow.md`.

## Validation and Acceptance


M1 passes with a concrete staging target and executable positive/negative workflow contracts; M2 passes after two independently checked real workflow runs with fresh identities and run-owned cleanup or documented retention. For registration, verify the qualified-agent precondition, OTP sequence, and actual account/user writes. Wrong cluster/namespace, unrelated endpoints, unknown deployment identity, missing credentials, or missing required evidence fail readiness before scenario mutations. A deployment change during smoke invalidates the acceptance evidence. Verify that normal startup and teardown leave existing workloads, shared data, and unrelated test records intact.

The availability of a second implementation is not required. Local library fixtures and mocked services cannot satisfy this staging milestone.

## Idempotence and Recovery


Allocate fresh run IDs and supported test identities. Preserve sanitized failure evidence. A transport timeout can leave an action's outcome uncertain; inspect the original business key and do not blindly resend it. Stop only verifier-owned access resources. Never reset a shared namespace, database, or broker to recover a run. Record unsupported cleanup and retention honestly. No production target is permitted by this bootstrap contract.

## Interfaces and Dependencies


Hard dependency: all of `docs/plans/1-bootstrap-the-haskell-workspace-with-seihou-and-jitsurei-standards.md`, for reproducible command tooling. No dependency on core/CLI: independent checks establish access and domain behavior first. This plan owns `integration/workflow.json`, `docs/workflows/first-staging-workflow.md`, the access/readiness script, and the staging target identity contract. The context owns business vocabulary. `docs/plans/7-verify-one-real-workflow-across-legacy-and-keiro-implementations.md` consumes this accepted staging contract; its historical path remains stable. Changes to the selected workflow or target must update both plans and ADR 0004.

Revision 2026-10-01: replace composed local pairs and lifecycle scripts with access/readiness for the existing Kubernetes staging system, following the user's confirmed first milestone.
