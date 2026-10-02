---
id: 2
slug: establish-the-first-workflow-contract-and-composed-local-environments
title: "Establish the first workflow contract and composed local environments"
kind: exec-plan
created_at: 2026-10-02T03:52:02Z
master_plan: "docs/masterplans/1-bootstrap-shoko-for-evidence-based-workflow-parity.md"
provenance:
  created_by:
    model: "gpt-6-astra"
    harness: "codex-cli"
    at: 2026-10-02T03:52:02Z
---

# Establish the first workflow contract and composed local environments


This ExecPlan is a living document. Keep progress and prerequisite evidence current; a missing rewritten service cannot be replaced with a fixture and marked complete.

## Purpose / Big Picture


A contributor can start the actual legacy and rewritten implementations of one workflow locally, submit controlled equivalent inputs, and see each reach its documented domain outcome. This supplies the systems that Shōko will verify, and prevents its first parity scenario from targeting an imaginary registration event chain.

## Progress


- [ ] M1: A checked workflow contract identifies the first runnable pair, its domain vocabulary owner, real actions, observations, correlation, and concrete prerequisites.
- [ ] M2: Repeatable composed local stacks execute that workflow on both implementations with controlled side effects and retained source/readiness evidence.

## Surprises & Discoveries


## Decision Log


On 2026-10-01, make composed environments an early work stream, as RES-1 recommendation 7 requires, while allowing the generic verifier to proceed independently. Registration is the researched reference; substitute another workflow only when both implementations and its domain contract are evidenced.

## Outcomes & Retrospective


## Context and Orientation


The repository initially has no service stack. The required build foundation comes from `docs/plans/1-bootstrap-the-haskell-workspace-with-seihou-and-jitsurei-standards.md`. [RES-1](../research/initial-specification-requirement-validation.md) S1–S9 and M1–M8 is the primary requirement. [ADR 0004](../adr/0004-gate-parity-on-real-workflows-and-context-owned-vocabulary.md) requires real paired environments and context-owned vocabulary; [ADR 0002](../adr/0002-keep-scenarios-inspectable-and-bindings-explicit.md) requires explicit correlation and environment policy. A vocabulary is the typed set of business actions and observations shared by both bindings, not a list of one implementation's events.

Registration involves submission/start, admin approval, qualification verification, OTP, and completion. Observed legacy names include `MembershipRequestSubmitted`, `RegistrationStarted`, `ApprovalReceived`, and `QualifiedAgentVerified`. Account and user creation are real; a registration-triggered `AgentQualified` chain and welcome email are not. `registrationId` is the researched cross-service business key. GraphQL currently needs a browser session, so use REST or PostgreSQL. The platform report does not establish a complete runnable rewritten registration pair, even though notification-hub uses the target runtime.

Use Mori to inspect [registration-service-v2](mori://tan/registration-service-v2), [account-service-v2](mori://tan/account-service-v2), [mls-service-v2](mori://tan/mls-service-v2), and the [modernization coverage](mori://tan/tan-platform/docs/platform-modernization-coverage). The researched manual registration acceptance source is `mori://tan/registration-service-v2` plus project-relative `docs/plans/2026-07-17-flow-2-staging-validation-plan.md` (artifact-level URI pending; resolve the project through Mori). Read that file and the service smoke scripts before specifying endpoints or SQL; their contents were summarized, not copied, into RES-1.

## Plan of Work


### M1 — Freeze a real workflow contract and readiness inventory


Create `docs/workflows/first-parity-workflow.md` and `integration/workflow.json`. Inspect current sources and identify the first workflow that exists on both sides, preferring the researched registration workflow when ready. Record the vocabulary/scenario package's canonical Mori project owner and immutable revision, expected module and scenario identity, upstream build/start commands, source revisions, configuration needs, supported read paths, business-key extraction, and controlled test inputs. Explain which dependencies are real and which external side effects are replaced by existing local stubs.

Use registration completion from an already-qualified agent as the reference slice (`registration-completion-parity`). The manual source's sections 3–5 prescribe creating a controlled qualified-agent fixture through the existing service facility, starting through `POST /v1/registrations/from-qualified-agent`, reading OTP channels from `GET /v1/registrations/{id}`, requesting OTP, reading `verificationSid` from that GET, and verifying with both code and SID. The command acknowledgements do not contain the channels or SID. In the local fixture use the supported OTP stub, with its exact code and current configuration verified from service source. Qualification/approval is a fixture precondition for this slice; the self-register/admin-approval flow is a distinct optional future scenario, not a hidden acceptance claim.

Map completion, account existence, user existence, and absence of duplicate accounts to actual public read sources. Independently verify real downstream writes: the manual source warns that a stubbed completion pipeline can emit `RegistrationCompleted` without calling account/auth services. Permit an OTP delivery stub, but not a stub for a downstream consequence claimed by the parity scenario. Recheck current service flags instead of copying the historical staging configuration. Do not make timestamp order a causation claim. Derive identities from supported fixtures instead of assuming an arbitrary MLS member exists. Do not add legacy instrumentation. Select business-key correlation unless execution propagation is demonstrated; Keiro's [IR-52](mori://shinzui/keiro/okf/improvement-requests/concepts/IR-52) owns the stronger contract.

`integration/workflow.json` must contain `schemaVersion`, `workflowId`, `scenarioId`, `scenarioRevision`, `vocabularyOwner`, `vocabularyModule`, `logicalInput`, and `implementations`. Each implementation records canonical source owner, immutable revision, startup/readiness/stop commands, connection environment-variable names, correlation strategy and key, required fixture capabilities, and a readiness state (`ready` or `unavailable`) with reasons. Store secret references, never credentials. It must not name a fake service as a real implementation. If no pair exists, record exact missing owner/artifact and leave M1 and M2 unfinished: a useful inventory is partial work, not acceptance. Continue the parent plan's eligible generic work rather than inventing a target service or broadening into a rewrite.

### M2 — Run and reset both composed local stacks


Once the pair is available, add `integration/process-compose.workflow.yaml` and executable `scripts/workflow-env` supporting `check`, `up`, `smoke`, `down`, and `reset`, each with `--implementation legacy|keiro`. Add `just workflow-check`, `workflow-up implementation`, `workflow-smoke implementation`, and `workflow-down implementation` wrappers. Use the template's project-local PostgreSQL/process-compose tools, but keep application composition in the new integration file instead of editing the generated `process-compose.yaml`. Use distinct databases, ports, and namespaces for the two implementations. If approval requires Kafka, use the service's existing publisher and an isolated broker; record how Linux CI and macOS provide it. Adding Kafka runtime infrastructure does not authorize a new generic Shōko Kafka observer.

`check` validates the manifest, prerequisites, accessible source revisions, configured commands, and required local tools without starting processes. `up` starts only run-owned processes and waits on readiness. `smoke` drives a real public action and independently checks its durable domain result using documented service tools/SQL, without Shōko's runner. Capture source revisions and the effective substitute flags. A health endpoint alone does not pass M2. `down` stops only this run's stack. `reset` affects only a manifest-listed disposable local database/namespace and refuses unknown or remote targets; describe the ownership marker used for this guard.

## Concrete Steps


Start at the Shōko repository root after the foundation is Complete:

```bash
mori registry show tan/registration-service-v2 --full
mori registry docs tan/registration-service-v2
mori registry show tan/account-service-v2 --full
mori registry show tan/mls-service-v2 --full
mori path mori://tan/tan-platform/docs/platform-modernization-coverage
```

Read the resolved service sources and fill the exact application commands into the manifest before attempting M2. The following commands are interfaces this plan must create, not commands available at plan creation:

```bash
nix develop --command just workflow-check
nix develop --command just workflow-up legacy
nix develop --command just workflow-up keiro
nix develop --command just workflow-smoke legacy
nix develop --command just workflow-smoke keiro
nix develop --command just workflow-down legacy
nix develop --command just workflow-down keiro
```

`workflow-check` prints the chosen workflow and both resolved source identities, exits zero only if ready, and exits nonzero with concrete prerequisites otherwise. Each smoke command reports its created business key and expected domain outcome. Keep sanitized evidence in `integration/evidence/` or an ignored run directory linked from the plan; do not commit captured personal data.

## Validation and Acceptance


M1 passes only with a real pair, a context owner, and no unresolved prerequisite needed for the controlled local workflow. M2 passes after both actual implementations complete their independent smoke checks twice with isolated identities, no collisions, and successful cleanup. For the registration-completion slice, prove the qualified-agent precondition, OTP read/request/verify handling, and actual account/user writes rather than substituting a linear fake event chain or successful completion stub. A deliberately missing process or wrong revision makes `workflow-check` fail, naming the cause. The generic framework's toy workflow is never counted as this acceptance.

## Idempotence and Recovery


Use unique run identifiers and scoped resources. On failure retain sanitized logs, stop only known processes, and retry with new fixture identities or the guarded local reset. Never reset a shared database/broker, alter legacy deployments, or send real OTP/email as a side effect of testing. External service changes and the rewrite itself remain upstream work; record their canonical artifacts and recheck them before resuming. Do not mark this child complete merely because an external prerequisite has been documented.

## Interfaces and Dependencies


Hard dependency: all of `docs/plans/1-bootstrap-the-haskell-workspace-with-seihou-and-jitsurei-standards.md`, for Nix/process tooling. No dependency on the Shōko core or CLI: independent service smoke checks establish that the systems exist first. This plan owns `integration/workflow.json`, `docs/workflows/first-parity-workflow.md`, service lifecycle scripts, and fixture configuration. The domain owner owns actual business types and meaning; the manifest references that package. The final parity plan consumes this complete, accepted interface. Changes to workflow selection must update both this plan and `docs/plans/7-verify-one-real-workflow-across-legacy-and-keiro-implementations.md` before integration.
