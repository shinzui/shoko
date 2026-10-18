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
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-18T17:14:48Z
      mode: "update"
      note: "Select registration MVP and specify requirement, adapter, host, OTP, and readiness contracts."
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-10-18T20:35:16Z
      mode: "implement"
      note: "Implement offline workflow schema and validation; concrete staging contract and live access remain pending."
  reviews:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-18T17:14:48Z
      verdict: "approved"
      note: "Planning review after MVP update: dependencies, ownership, references, and observable acceptance checked; build and live staging proof remain implementation gates."
---

# Establish the first workflow contract and Kubernetes staging target


This ExecPlan is a living document. Its existing path and identifier remain stable after the staging-scope correction. The acceptance target is the complete system already running in a Kubernetes test namespace.

## Purpose / Big Picture


A contributor can identify the deployed staging system, access its real action and evidence endpoints, submit controlled test inputs, and independently confirm a workflow's durable outcome. Shōko connects to that existing system; it does not need to recreate the application as local services or provision it in a CI job. This contract supplies the target and domain meaning for the final verification run.

## Progress


- [ ] M1: A checked workflow contract identifies the deployed staging target, domain owner, real actions, evidence sources, correlation, controlled inputs, and permitted external effects.
- [ ] M2: Repeatable access and independent workflow smoke checks succeed against the existing Kubernetes test namespace, retaining actual target/deployment identity and run-owned cleanup evidence.

Implementation handoff, 2026-10-18: `schemas/workflow-v1.schema.json`,
`scripts/workflow_contract.py`, `scripts/workflow-env validate`, the explicitly
synthetic `integration/examples/workflow.example.json`, and
`docs/workflows/first-staging-workflow.md` now define and validate the offline
contract. Durable sources also require an explicit owner-backed
`historyPolicy: append-only-during-run`; without it the selected reader cannot
claim complete negative coverage. No default `integration/workflow.json` exists because approved concrete
target/access/test inputs remain unavailable. M1 remains unfinished. The
`workflow-check` now performs guarded read-only identity discovery with private
before/after artifacts; its explicit `--identity-only` mode can establish matching
namespace/workload UIDs, controller generations, and template image references. Full
readiness remains blocked: runtime images, endpoint/evidence checks, permitted
test setup, and independent smoke behavior are still M2 work. `workflow-smoke`
exits 2 without calls. The owners confirmed the remaining inputs are still being
prepared. The user subsequently identified cluster `sennari`, namespace `test`;
read-only target inventory succeeded, but no workflow acceptance has occurred.
Resume with the environment/domain owner inputs listed in the workflow guide;
then populate the real manifest, freeze its assertions/reader selection, implement
the approved access route, and retain the required live acceptance.

## Surprises & Discoveries


The user confirmed that staging is a complete running system in a Kubernetes test namespace, and that verifying this system comes before legacy/Keiro comparison. On 2026-10-18 they named cluster `sennari`, namespace `test`. Read-only discovery verified the matching local context and namespace UID and inventoried four registration Deployments, their image references/runtime IDs, and the internal API Service. Access routes, endpoint authorization, domain test facilities and scoped evidence credentials remain unresolved. The research's missing local pair is no longer a bootstrap prerequisite.

The actual deployment pins the application image by digest but configures native
init-sidecars using tags (Cloud SQL Proxy by version, Kafka auth by `latest`).
The integration contract now permits a separate exact `templateImages` set while
keeping `imageDigests` as runtime expectations. The checker compares configured
template references; runtime verification and pod ownership remain unverified
readiness obligations. This avoids omitting sidecars or demanding an incidental
deployment change. Discovery remains separate from accepted readiness.

The current API package in `mori://tan/registration-service-v2` at revision
`6cd07aa8b9f032fc850fed4b2ba1022537da8c91` still exposes the described
from-qualified-agent, OTP request/verify, and registration-read routes. Its
project-relative `registration-service-v2-api/src/RegistrationServiceV2/Api/Routes.hs`
and `registration-service-v2-api/src/RegistrationServiceV2/Api/Types/UserView.hs`
(artifact-level URIs pending) support the documented sequence, but cannot establish
the live deployment, real completion mode, negative contract, or OTP facility.

## Decision Log


On 2026-10-01, the initial plan required composing local legacy/Keiro environments. The user's clarification supersedes that choice: connect to the existing staging deployment, prove its real workflow, and leave application lifecycle management with its deployment owners. CI means an optional automated caller of the same verifier, not a separate system under test.

## Outcomes & Retrospective


Partial implementation, 2026-10-18: the contract's structure and referential
checks are runnable without staging access. Synthetic examples cannot be accepted
as staging contracts, and schema/parse failures do not echo supplied values.
`nix develop --command just check` passed: eight offline contract test groups,
the existing 37 core tests, 15 real SQL/HTTP tests, 43 CLI process invocations,
seven result-schema examples, and all native Nix checks including
`workflow-contract`. Changed plan/guide links and code fences also validated.
Neither milestone is accepted: real owner inputs, deployed behavior, repeatable
access/OTP, and independent positive/negative runs remain prerequisites.

Identity-discovery checkpoint, 2026-10-18: `scripts/workflow_identity.py` and
`check --identity-only` now verify explicit kubeconfig/server selection and two
namespace/workload identity snapshots using only read-only commands. Reports
retain exact contract hashes and allowlisted fields under private ignored
`.shoko/runs/<uuid>/identity.json` paths. A changed generation, recreated resource,
wrong target, missing identity, timeout, or process failure prevents identity
success. Controller templates do not prove runtime image IDs or rollout readiness;
the record always declares full readiness blocked. Eight offline contract groups
and 16 identity process groups pass in the native Nix `workflow-contract` check,
including safe artifact failure and unapproved init-container images. The actual
installed kubectl v1.37.0 also selected the explicitly named context from an
isolated synthetic kubeconfig with a different current context; this made no API
requests and is not a client/server compatibility claim. The environment/domain
owners confirmed they are still preparing the required inputs. Both milestones
remain unaccepted.

Target discovery, 2026-10-18: the user supplied `sennari` / `test`; explicit
read-only queries succeeded. Two namespace/workload observations matched, all
four registration Deployments reported one ready replica, and the API Service
was internal ClusterIP. A private ignored target-discovery artifact retains
allowlisted observations; no secrets, action payloads, or raw resource responses
were persisted. This is new access evidence, not M1/M2 acceptance. The full
image/endpoint contract, controlled qualified-agent/recipient facility, repeatable
OTP, completion mode, precise negative scenario, evidence access, stable window
and cleanup/retention remain required. No scenario mutation occurred. The contract
and checker were refined to distinguish template references from runtime digests;
the new tagged-sidecar process test preserves readiness blocked after a template
match, and pinned-template/runtime-expectation inconsistencies fail validation.
All eight contract groups and 17 identity process groups pass locally; the native
Nix workflow check also passes. Changed Markdown links/fences and artifact
structure/private permissions were checked separately.

Qualified-agent discovery, 2026-10-18: the user supplied an existing Unix-socket
read route to staging `mls-service-v2` as `claude`. Connection, catalog and
aggregate queries succeeded with session-enforced read-only mode and bounded
connect/statement/lock timeouts. The read model is
`mls_service_read.qualified_agents`: 127 rows, 122 without the checked MLS
registration markers, and 119 of those with nonblank manual first/last names and
email. No personal field values or agent IDs were retained, and no writes or
workflow actions occurred. MLS source and the registration handler confirm that
API payload eligibility, existing QA claims, test ownership, and controlled OTP
targets still need checking. The workflow guide now records the precise read
route and these limitations; this supplies part of the fixture/evidence discovery
but accepts neither milestone.

## Context and Orientation


The build foundation comes from `docs/plans/1-bootstrap-the-haskell-workspace-with-seihou-and-jitsurei-standards.md`. [RES-1](../research/initial-specification-requirement-validation.md) S1–S9 remains evidence about the surveyed workflow and access prerequisites; its recommendation to compose local pairs is superseded for first acceptance by the user's staging requirement. [ADR 0004](../adr/0004-gate-parity-on-real-workflows-and-context-owned-vocabulary.md) defines staging acceptance and domain ownership. [ADR 0002](../adr/0002-keep-scenarios-inspectable-and-bindings-explicit.md) requires explicit correlation and environment policy.

A namespace identifies a set of Kubernetes resources; the workflow can also use databases, brokers, and external providers outside it. Inventory those dependencies and their actual targets. Do not assume that selecting a namespace isolates all downstream effects. No cluster access or deployment changes have occurred during planning.

Registration completion from an already-qualified agent is the user-selected MVP workflow. Its durable business key is `registrationId`; real account/user outcomes must be checked. The deployed system must support that workflow; a matching second implementation is not required. Use Mori to inspect [registration-service-v2](mori://tan/registration-service-v2), [account-service-v2](mori://tan/account-service-v2), [mls-service-v2](mori://tan/mls-service-v2), and [modernization coverage](mori://tan/tan-platform/docs/platform-modernization-coverage). The manual reference is `mori://tan/registration-service-v2` plus project-relative `docs/plans/2026-07-17-flow-2-staging-validation-plan.md` (artifact-level URI pending). Recheck current deployed contracts rather than treating the historical document as live configuration.

## Plan of Work


### M1 — Freeze the workflow and deployed target contract


Create `docs/workflows/first-staging-workflow.md`, `integration/workflow.json`, and `schemas/workflow-v1.schema.json`. Record the real domain operation, expected consequences, action/read endpoints, evidence strength, business-key extraction, supported test identities, capability requirements, external-effect handling, and cleanup mechanism. The user selected registration completion on 2026-10-18; a different workflow requires an explicit scope revision. M1 can start before the build foundation because it establishes the contract rather than compiling the verifier.

Add `requirements`, `excludedRequirements`, and `requiredAdapters` to the manifest. Every requirement has a stable ID, plain-language business invariant, scenario and expectation IDs, evidence source, and required coverage (sampled state or complete durable history). Cover completed registration, actual account/user creation and association, and the chosen negative contract. Declare duplicate prevention precisely: one observed account row is a sampled cardinality fact, not proof of exactly-once delivery. If the selected requirement needs event history, name `kiroku` or `message-db` in `requiredAdapters` and explain why HTTP/PostgreSQL observations cannot discharge it. Freeze this selection before acceptance; unavailable history remains a blocker or Unknown, never an implicit reduction in scope. List qualification and untested registration flows as excluded. This mapping makes a result useful to rewrite reviewers without certifying an entire service.

Record a `host` contract with canonical owning project/package references, project-relative package directory and public module, executable target, build/invocation recipe, and immutable source revision once implemented. The registration context owns a small Haskell verification package beside its domain code; it can use typed HTTP/SQL bindings without linking the service executable or its full runtime dependency graph. No such host is assumed to exist today. EP-7 creates it and records the consumed revision. M1 must identify its intended location and build integration, so context ownership cannot hide an unassigned packaging prerequisite.

Use a manifest with `schemaVersion`, `workflowId`, `scenarioId`, `scenarioRevision`, `vocabularyOwner`, `vocabularyModule`, `logicalInput`, and `target`. The target records environment and implementation binding names, expected cluster/context and namespace identity, deployed workload identities, immutable image digests and source revisions where available, endpoint/evidence-source references, credential environment-variable names, access route, correlation strategy/key, and readiness with concrete reasons. Record observed deployed identities separately from expected labels. Pin the namespace UID when available so recreating a namespace cannot silently reuse a previous approval. The implementation name is independent of environment and is not restricted to a presumed legacy/Keiro pair. Store references rather than credentials or personal payloads.

Choose and document an access route supported by the actual staging setup: reachable ingress/internal endpoints, an approved tunnel, or execution inside the test namespace. The initial command-line runner can run wherever those routes and credentials work. An in-cluster Job is optional packaging, not a new core dependency or acceptance requirement. Use existing deployment tooling and namespace-scoped access; do not add a Kubernetes client to `shoko-core`. Consult official Kubernetes documentation and repository deployment instructions when implementing actual API/CLI integration.

For the registration reference (`registration-completion-staging`), arrange a valid qualified-agent fixture using the service's supported facility, start through `POST /v1/registrations/from-qualified-agent`, read OTP channels from `GET /v1/registrations/{id}`, request OTP, read `verificationSid` from that GET, and verify with code and SID. Acknowledgements do not provide the channel/SID fields. Record the staging delivery mode and controlled recipients: use an existing supported test delivery path where configured; real provider delivery needs a documented test recipient and its permitted effects. Do not assume a local stub exists in staging or change deployment flags implicitly. Qualification/approval is a precondition of this slice, not behavior claimed by it.

Map registration completion, account existence, user existence, and duplicate prevention to actual read sources. A completion stub that skips account/auth writes cannot support an assertion that those consequences happened. Use machine-callable REST or scoped read-only database access rather than presuming browser-session GraphQL works. Prefer business-key correlation unless execution-ID propagation is demonstrated. Keiro's [IR-52](mori://shinzui/keiro/okf/improvement-requests/concepts/IR-52) remains the owner of that stronger contract. An unavailable credential, test identity, external-effect route, or evidence source is an explicit unmet staging prerequisite, not permission to substitute a local mock.

Record deployed completion/OTP mode explicitly. The local source inspected on 2026-10-18 defaults `RS2_COMPLETION_ACL_STUB` to false, unlike the historical staging warning; this is not evidence that the deployed worker uses real clients. Confirm real account/auth consequences in M2. Specify how the bounded host obtains a fresh OTP: an already-approved service test path or an automated controlled-recipient retrieval binding with declared capabilities. Do not require an operator to type a code into the middle of the finite runner or record OTP values in artifacts. If no repeatable retrieval facility exists, record its owner as an unmet prerequisite; do not change deployment flags or build a new provider platform as incidental verifier work.

Also freeze at least one documented negative scenario in `negativeScenarios` alongside the primary `scenarioId`: an expected input/authentication/domain rejection or duplicate-prevention path supported by the deployed API. Each entry states allowed typed response outcomes, the precise expected rejection or invariant, relevant downstream state/history evidence, and an isolated test identity. Candidate cases such as invalid OTP must be confirmed against the actual service contract. Do not presume any 4xx response is sufficient, use real customer identities, or equate network failure with expected rejection. A successful negative scenario has verdict Pass; the final plan separately demonstrates deliberate Fail/Unknown controls.

### M2 — Verify access and independently exercise the running system


Create `scripts/workflow-env` with `check` and `smoke` commands and `just workflow-check` / `just workflow-smoke` wrappers consuming the explicit manifest. `check` performs read-only target discovery, validates the expected cluster/namespace and actual deployment identities, checks endpoint/evidence connectivity and permitted test setup, and produces a sanitized readiness record. Never silently use the current kube context or a default namespace. The target contract must relate each application/evidence endpoint to the approved staging deployment, including resources outside Kubernetes. A test namespace label cannot authorize a production endpoint.

`smoke` drives the contracted real workflow with fresh test identities and independently checks its durable consequences using current service tools or scoped SQL, without depending on Shōko's runner. Record deployed identities before and after the run; a changed or unverifiable target prevents acceptance until repeated against a stable deployment. Demonstrate two runs with isolated business keys. A health check alone is not workflow acceptance.

These scripts do not deploy, scale, restart, migrate, or delete application workloads, create a replacement stack, reset shared databases/brokers, or remove the namespace. If a documented access route needs a verifier-owned tunnel or Job, manage only that resource. Domain cleanup uses supported APIs or specifically scoped operations against test records owned by this run. If deletion is unsupported, document bounded retention and ownership instead of claiming teardown. Required changes to staging infrastructure or service test facilities remain explicit work with their owners.

## Concrete Steps


At the repository root, begin M1 by resolving domain/deployment sources through Mori and obtaining the actual staging context, namespace, access route, and credential references from the environment owner. Do not invent these values or automatically select them from a developer's current shell. M2's commands require the foundation Complete.

The following are interfaces this plan creates:

```bash
nix develop --command just workflow-check
nix develop --command just workflow-smoke
```

The currently available offline checks are:

```bash
nix develop --command just test-workflow-contract
nix develop --command just workflow-validate
```

`workflow-validate` requires the real manifest with all prerequisite declarations
confirmed; its success establishes structural validity only. The contract tests
exercise synthetic fixtures directly and never call a cluster. Until the approved
target/access contract is supplied, the live wrappers fail closed rather than
claiming a health check or mocked run satisfies M2.

With a real confirmed contract, `python3 scripts/workflow-env check --identity-only`
performs read-only identity discovery and exits 0 only for matching observations.
Plain `check` still exits 2 because identity matching alone cannot establish full
readiness. Reports use private run directories documented in the workflow guide;
no manifest recipes are executed. `smoke` remains unavailable until implemented
against the approved domain/access contract.

The wrappers load `integration/workflow.json` explicitly and reject missing or mismatched target identity before mutating actions. `workflow-check` reports the selected staging namespace, observed deployment identities, access/readiness status, and exact missing prerequisites with a nonzero exit when unusable. `workflow-smoke` records fresh business keys and actual domain consequences. Retain sanitized artifacts in an ignored run directory; describe its location in `docs/workflows/first-staging-workflow.md`.

## Validation and Acceptance


M1 passes with a concrete staging target and executable positive/negative workflow contracts; M2 passes after two independently checked real workflow runs with fresh identities and run-owned cleanup or documented retention. For registration, verify the qualified-agent precondition, OTP sequence, and actual account/user writes. Wrong cluster/namespace, unrelated endpoints, unknown deployment identity, missing credentials, or missing required evidence fail readiness before scenario mutations. A deployment change during smoke invalidates the acceptance evidence. Verify that normal startup and teardown leave existing workloads, shared data, and unrelated test records intact.

Validate the manifest against its schema and reject a requirement without an expectation/source/coverage mapping, an undeclared required adapter, or an unresolved host location. Independently smoke-check the selected negative case as well as the positive case before completing M2. Retain the exact domain rejection/invariant observed; a generic HTTP error is insufficient. Repeated positive runs must acquire OTPs through the documented repeatable route. Readiness records missing prerequisites with owner, reason, and the check that will clear them.

The availability of a second implementation is not required. Local library fixtures and mocked services cannot satisfy this staging milestone.

## Idempotence and Recovery


Allocate fresh run IDs and supported test identities. Preserve sanitized failure evidence. A transport timeout can leave an action's outcome uncertain; inspect the original business key and do not blindly resend it. Stop only verifier-owned access resources. Never reset a shared namespace, database, or broker to recover a run. Record unsupported cleanup and retention honestly. No production target is permitted by this bootstrap contract.

## Interfaces and Dependencies


M1 has no hard prerequisite. M2 requires all of `docs/plans/1-bootstrap-the-haskell-workspace-with-seihou-and-jitsurei-standards.md` for reproducible command tooling. No dependency on core/CLI: independent checks establish access and domain behavior first. This plan owns `integration/workflow.json`, `schemas/workflow-v1.schema.json`, `docs/workflows/first-staging-workflow.md`, the access/readiness script, and the staging target identity contract. The context owns business vocabulary. `docs/plans/7-verify-one-real-workflow-across-legacy-and-keiro-implementations.md` consumes this accepted staging contract; its historical path remains stable. Changes to the selected workflow or target must update both plans and ADR 0004.

Revision 2026-10-01: replace composed local pairs and lifecycle scripts with access/readiness for the existing Kubernetes staging system, following the user's confirmed first milestone.

Revision 2026-10-18: select registration completion, allow early M1 discovery, require a schema-backed rewrite coverage/adapter/host contract, and make repeatable OTP acquisition and real completion writes explicit readiness gates.
