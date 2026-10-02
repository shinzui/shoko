---
id: 7
slug: verify-one-real-workflow-across-legacy-and-keiro-implementations
title: "Verify one real workflow in the Kubernetes staging system"
kind: exec-plan
created_at: 2026-10-02T03:52:03Z
intention: "intention_01m3xdacr3exqajqfcgh9btgev"
master_plan: "docs/masterplans/1-bootstrap-shoko-for-evidence-based-workflow-parity.md"
provenance:
  created_by:
    model: "gpt-6-astra"
    harness: "codex-cli"
    at: 2026-10-02T03:52:03Z
  revisions:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-02T04:18:41Z
      mode: "update"
      note: "Associate the bootstrap plan with the shared Mina intention requested by the user."
---

# Verify one real workflow in the Kubernetes staging system


This ExecPlan is a living document. Its existing identifier/path remain stable after the staging-scope correction. Completion requires retained evidence from the complete system already deployed in the approved Kubernetes test namespace.

## Purpose / Big Picture


Run a context-owned domain scenario against the existing staging system, perform its real operation, and retain bounded evidence of downstream consequences. An operator can inspect the scenario, execute it from an authorized runner location, and distinguish Pass, Fail, and Unknown. CI may invoke the same command, but is not needed to create the system under test or establish the first acceptance.

## Progress


- [ ] M1: Context-owned positive and negative staging scenarios and their binding compile through the public library/CLI host and complete an early real action-to-evidence check.
- [ ] M2: The positive workflow and a documented negative scenario both pass in the running Kubernetes test namespace with immutable reports identifying the actual target, deployment, scenario, inputs, and evidence.
- [ ] M3: Scoped Fail/Unknown controls, repeated fresh-input runs, cleanup/retention, and the operator tutorial pass; durable lessons are recorded in ADRs.

## Surprises & Discoveries


The user confirmed that first acceptance is verification of the currently deployed staging system. A second legacy/Keiro deployment is not a prerequisite. Migration parity remains a later application of the scenario/binding architecture and cannot be inferred from one staging result.

## Decision Log


On 2026-10-01, the initial plan selected paired local migration verification. The user's clarified requirement supersedes that acceptance gate with one real staging workflow. Keep domain vocabulary with its context and preserve binding portability, without delivering a paired report/comparison command in this bootstrap.

## Outcomes & Retrospective


## Context and Orientation


Read `docs/research/initial-specification-requirement-validation.md`, especially its real workflow, correlation, machine access, OTP, and evidence findings. Accepted outputs of `docs/plans/2-establish-the-first-workflow-contract-and-composed-local-environments.md` are now `integration/workflow.json`, `docs/workflows/first-staging-workflow.md`, and `scripts/workflow-env`. They define the expected and observed Kubernetes target identity, actual deployment, controlled inputs, actions/read paths, credentials/access route, external-effect policy, and independently smoke-tested domain outcome. Missing access remains an unmet prerequisite rather than a skipped passing integration test.

Complete `docs/plans/4-implement-postgresql-and-http-evidence-bindings.md`, `docs/plans/5-implement-kiroku-and-message-db-evidence-bindings.md`, and `docs/plans/6-expose-scenario-inspection-execution-and-structured-reports.md` are also hard dependencies. These preserve the bootstrap's four generic evidence adapters; the selected staging binding uses only sources actually present in that workflow. No additional event store must be deployed merely because its adapter exists.

[ADR 0004](../adr/0004-gate-parity-on-real-workflows-and-context-owned-vocabulary.md) sets staging acceptance and domain ownership. [ADR 0002](../adr/0002-keep-scenarios-inspectable-and-bindings-explicit.md) defines scenario/binding/policy boundaries; [ADR 0003](../adr/0003-record-bounded-evidence-and-three-valued-results.md) defines evidence semantics; [ADR 0001](../adr/0001-use-jitsurei-standards-and-the-seihou-haskell-flake.md) defines build practices. The [platform rewrite-gates ADR](mori://tan/tan-platform/docs/adr-0002-track-infrastructure-and-observability-as-rewrite-gates) means a workflow pass does not establish migration parity, infrastructure readiness, or cutover approval.

## Plan of Work


### M1 — Connect the domain scenario to the staging binding


Resolve the context package named by `integration/workflow.json` using Mori. Implement or extend its vocabulary, scenario, and host in that repository, following its instructions and linking this Shōko plan by canonical URI. Record the immutable consumed package revision and public module in the manifest. Use the public `runShokoCli` host so the context reuses Settei configuration, core policy, evidence semantics, and reporting. Keep production domain types out of the generic Shōko packages.

For the researched registration slice, use the qualified-agent precondition and domain expectations for registration completed, account exists, user exists, and duplicate prevention. Execute the accepted start/read-channels/request-OTP/read-SID/verify/completion sequence. A typed composite action such as `completeQualifiedAgentRegistration` declares all suboperations and capabilities, shares the remaining deadline, and records substep evidence. Use the approved staging OTP/test-recipient path; do not silently enable local stubs or bypass real downstream writes. Qualification/admin approval remains a precondition rather than an untested assertion.

Negative/cardinality expectations require suitable coverage. A mutable account table cannot prove continuous `never` from empty polls alone. Use a durable ledger or supported invariant evidence; otherwise retain Unknown or explicitly agree a weaker point-in-time contract before acceptance. Business-key correlation is the default unless remote execution-ID propagation is demonstrated.

Perform one real action and one downstream observation through the actual context host before expanding all assertions. This checks the vocabulary, endpoint credentials/routes, adapters, real schemas, and correlation together. It must use the already-running staging target, not a locally recreated service stack.

Implement at least one separate negative scenario from the accepted manifest. Its operation contract exposes the specific rejection or duplicate outcome as a typed value and retains the response as evidence. Expectations verify that exact outcome and any documented downstream invariant. An invalid-OTP example should Pass only for the contracted invalid-code rejection and the appropriate unchanged registration state; a timeout, unrelated authorization error, malformed response, or successful completion cannot satisfy it. Use a supported isolated test identity and verify the actual service contract before selecting this case. State snapshots support a point-in-time unchanged-state assertion; claims that no forbidden event occurred over a window require durable complete coverage. A negative scenario Pass must not be confused with an intentionally false assertion producing Fail.

### M2 — Produce an attributable staging result


Add `scripts/run-staging`, `just staging`, and `integration/config/staging.yaml`. The explicit configuration names the target/binding approved by `integration/workflow.json`, required credential references, permitted capabilities, bounded polling, and deadlines suitable for that workflow. Do not treat local/CI timing defaults as a staging service-level promise. The wrapper calls the live `workflow-check`, runs the context host separately for the primary and selected negative scenario, and retains artifacts under `artifacts/staging/<run-id>/`; ignore generated run artifacts in Git. It does not deploy or start application services.

Retain `target-before.json`, `result.json`, and `target-after.json` plus an `acceptance.json` envelope governed by `schemas/staging-acceptance-v1.schema.json`. The core owns `result.json`; this plan owns the envelope referencing those files and digests, actual target/deployment identities, and compatibility checks. Record namespace/cluster identity, workload image digests and source revisions where known, scenario revision/digest, actual verifier binary identity, logical inputs, test business keys, correlation strategy, and evidence windows. Never copy credentials or personal payloads into these records.

Acceptance Pass requires a core Pass and agreement of approved, before-run, and after-run target/deployment identities. A conclusive workflow Fail is retained even if other checks are Unknown; incomplete evidence or unverifiable/changed deployment prevents a Pass. Preserve the original core result rather than rewriting it to represent an infrastructure check. Map the acceptance result through the established 0/1/3 verdict exits, with exit 2 for invalid invocation/policy and 4 for unexpected runner faults. Capture evidence on timeout/cancellation where possible without labelling a partial run complete.

The tutorial documents one supported runner location and access route verified against the actual staging setup. The host may run from an operator shell or automation runner with access; an in-cluster Job is optional packaging. Kubernetes discovery and access setup remain in the integration layer, outside `shoko-core`.

### M3 — Prove sensitivity, repeatability, and operator use


Add `just staging-failure-control` and `just staging-unavailable-control`. Use distinct, clearly labelled control scenario IDs. For Fail, assert a known-false domain expectation on this run's controlled test data through the real staging reader. This demonstrates detection of a conclusive mismatch without changing the primary acceptance contract or altering other users' workloads. For Unknown, make only the verifier's evidence connection unavailable, for example through a test-only binding endpoint/credential override constrained to this control. Do not stop shared services, change application credentials, or inject a deployment-wide fault. A service-owner-provided scoped failure facility is optional, not a prerequisite.

Controls pass only when the expected nonzero verifier exit and typed evidence reason appear; they must never be merged into a green primary workflow report. Restore verifier configuration and repeat the normal staging run with new identities to recover Pass. Demonstrate that earlier evidence cannot satisfy a later run and that cleanup/retention is limited to owned test records and access resources.

Create `docs/tutorials/first-staging-run.md` with exact build/access/check/inspect/run/cleanup commands, deployment prerequisites, credential references, target identity, external-effect policy, example sanitized reports, and Fail/Unknown diagnostics. Include the context host's actual command as well as wrapper usage. Manual invocation is sufficient for first acceptance. If CI integration is added, it launches this same staging command using approved access and preserves nonzero outcomes; it neither provisions a replacement system nor silently skips unavailable staging. Update README and the MasterPlan with retained acceptance evidence and distill durable findings into ADRs.

## Concrete Steps


At the repository root after all hard dependencies are Complete and the staging manifest/access are configured:

```bash
nix develop --command just workflow-check
nix develop --command just staging
nix develop --command just staging-failure-control
nix develop --command just staging-unavailable-control
nix develop --command just staging
nix develop --command just check
```

The staging recipes are created here. `staging` runs the positive and selected negative scenarios separately and exits zero only when both acceptance records Pass. Every invocation uses fresh run-owned input identities and reports each artifact directory; no batch scheduler is required in the core. `staging` exits zero only for a valid accepted workflow result against the identified deployment. Control wrappers exit zero only after checking their expected Fail/Unknown result and reason. There are no application `up`, `down`, or shared-reset commands.

## Validation and Acceptance


Acceptance requires a real positive workflow Pass and a documented negative scenario Pass from the existing Kubernetes test namespace, actual downstream consequences, stable target/deployment identity, scoped evidence, both controls, repeated fresh-input success, and reproducible operator instructions. A healthy HTTP status, toy demo, local replacement stack, missing credentials, or skipped integration run cannot meet this criterion. Target mismatch must reject before actions. Deployment changes during a run cannot yield an accepted Pass. Evidence-access failure yields Unknown, not missing-row Fail or empty-query Pass. Check report schemas, sanitized persistence, and cleanup/retention without affecting unrelated records or workloads.

One implementation is sufficient. Legacy/Keiro parity, production execution, continuous Observe, Replay, generic Kafka observation, trace querying, and cutover approval remain outside this bootstrap.

## Idempotence and Recovery


Use fresh run IDs and supported test identities. Preserve reports immutably and create a new directory for retries. An uncertain mutation outcome must be investigated through its existing business key before another attempt; do not automatically replay it. Cleanup only owned test records through approved mechanisms; retain bounded tagged data when deletion is unsupported. A failed run does not authorize namespace/database reset, rollout, or service rewrite. Missing staging access or domain prerequisites leave this child unfinished with their exact owner and reason.

## Interfaces and Dependencies


Hard dependencies: Complete `docs/plans/2-establish-the-first-workflow-contract-and-composed-local-environments.md`, `docs/plans/4-implement-postgresql-and-http-evidence-bindings.md`, `docs/plans/5-implement-kiroku-and-message-db-evidence-bindings.md`, and `docs/plans/6-expose-scenario-inspection-execution-and-structured-reports.md`. The target plan owns readiness and observed target metadata; the context owns vocabulary; core owns individual results and typed host-supplied target identity; CLI owns configuration/host invocation. This plan owns the staging acceptance envelope, target compatibility checks, integration config, tutorial, and end-to-end acceptance wrappers. Future parity can reuse the same scenario against another binding; no paired comparison is required or claimed here.

Revision 2026-10-01: replace local paired acceptance with verification of the existing Kubernetes staging system, following the user's confirmed goal. Keep CI as an optional launcher and parity as a later use case.
