---
id: 7
slug: verify-one-real-workflow-across-legacy-and-keiro-implementations
title: "Verify one real workflow across legacy and Keiro implementations"
kind: exec-plan
created_at: 2026-10-02T03:52:03Z
master_plan: "docs/masterplans/1-bootstrap-shoko-for-evidence-based-workflow-parity.md"
provenance:
  created_by:
    model: "gpt-6-astra"
    harness: "codex-cli"
    at: 2026-10-02T03:52:03Z
---

# Verify one real workflow across legacy and Keiro implementations


This ExecPlan is a living document. Completion requires retained evidence from two actual implementations; document external prerequisites without converting them into a passing result.

## Purpose / Big Picture


Run the same context-owned domain scenario against a legacy local stack and its Keiro replacement, then retain two individual reports and a paired parity summary. A controlled defect must fail the relevant expectation, while an unreachable evidence source must remain Unknown. This proves Shōko's bootstrap against a real workflow rather than only its own fixtures.

## Progress


- [ ] M1: A context-owned scenario and two bindings compile through the public library/CLI host, with identical scenario semantics and explicit implementation identities.
- [ ] M2: Both real local runs pass and a versioned paired report preserves their evidence, inputs, correlation, and source revisions.
- [ ] M3: Controlled Fail/Unknown cases, repeatability, cleanup, and the documented local/CI invocation all pass; the bootstrap's durable lessons are distilled into ADRs.

## Surprises & Discoveries


## Decision Log


On 2026-10-01, require a real pair and keep application vocabulary in its bounded context. Business-key correlation is sufficient for bootstrap; execution-id parity must not wait on or falsely claim Keiro IR-52. Parity is confined to one named workflow and its recorded expectations.

## Outcomes & Retrospective


## Context and Orientation


Read `docs/research/initial-specification-requirement-validation.md`, particularly S1–S9 and M1–M8. Before this child starts, `integration/workflow.json`, `docs/workflows/first-parity-workflow.md`, and `scripts/workflow-env` must be accepted outputs of `docs/plans/2-establish-the-first-workflow-contract-and-composed-local-environments.md`. They identify the real workflow, domain owner, source revisions, action/read paths, local substitution policy, business keys, and the two smoke-tested stacks. If these files do not establish a runnable pair, the prerequisite is unmet.

Complete SQL/HTTP adapters from `docs/plans/4-implement-postgresql-and-http-evidence-bindings.md`, both event-store adapters from `docs/plans/5-implement-kiroku-and-message-db-evidence-bindings.md`, and the reusable CLI from `docs/plans/6-expose-scenario-inspection-execution-and-structured-reports.md` are also hard prerequisites. They transitively require the accepted core and foundation. These are whole-child dependencies; do not treat partial tests as acceptance.

[ADR 0004](../adr/0004-gate-parity-on-real-workflows-and-context-owned-vocabulary.md) defines domain ownership and limits the parity claim. [ADR 0002](../adr/0002-keep-scenarios-inspectable-and-bindings-explicit.md) defines the scenario/binding split and correlation. [ADR 0003](../adr/0003-record-bounded-evidence-and-three-valued-results.md) defines finite evidence semantics; [ADR 0001](../adr/0001-use-jitsurei-standards-and-the-seihou-haskell-flake.md) supplies mandatory coding/build practices. The platform's [rewrite-gates ADR](mori://tan/tan-platform/docs/adr-0002-track-infrastructure-and-observability-as-rewrite-gates) means a Shōko pass does not establish infrastructure/observability readiness for cutover.

## Plan of Work


### M1 — Compile a domain scenario against both bindings


Resolve the context package named by `integration/workflow.json` using Mori. Implement or extend its vocabulary, scenario, and host there, following that repository's instructions and linking this Shōko plan by canonical URI. The generic Shōko packages must not own the production registration types. Record the resulting immutable source/package revision and public module in the manifest. Use the CLI library's `runShokoCli` with the context registry; the same compiled scenario value is selected for both binding names.

For the registration-completion reference, use a qualified-agent fixture precondition and domain expectations for registration completed, account exists, user exists, and no duplicate account. Qualification and approval are not behaviors claimed by this narrower slice. Drive the real start/read-OTP-channels/request-OTP/read-verification-SID/verify/completion sequence in the accepted workflow contract, rather than inventing `QualificationRequested`, registration-triggered `AgentQualified`, or a welcome email. Completion must perform the downstream writes being asserted; only the external OTP delivery may be stubbed.

Expose this sequence as a typed domain action such as `completeQualifiedAgentRegistration`, returning a reference containing the business key. Its binding can perform the necessary bounded HTTP reads between requests, while statically declaring the full endpoint/method/capability inventory and sharing the remaining core deadline. This avoids pretending an OTP SID is known before execution and does not require runtime branching in the scenario builder. Evidence records the actual request/read steps; no ad hoc IO is hidden in scenario construction. Each binding maps observations to its own read models/events and business key. Event-level implementation invariant checks use separate scenario IDs and do not substitute for parity.

Respect coverage when defining negative/cardinality expectations. If a duplicate-account invariant uses mutable rows without history, it cannot pass `never` merely because polls were empty. Find a durable domain ledger or supported invariant evidence; otherwise leave that expectation Unknown and the parity gate unmet, or explicitly revise the accepted domain contract to a weaker point-in-time check with its limitation documented. Do not silently weaken it for a green result. Strong execution-id correlation is optional only if actual propagation is proved; explicit business-key correlation is the default.

Before running the full workflow, perform one real action and one downstream observation through the context host on each stack. This early integration check proves that the typed vocabulary, generic adapters, and real schemas agree. Expand the remaining domain expectations only after that succeeds.

### M2 — Produce an attributable paired parity run


Add `scripts/run-parity` and `just parity`, plus `integration/config/legacy-local.yaml` and `keiro-local.yaml`. The script calls `workflow-check`, starts or verifies the accepted stacks, invokes the context host twice, and records output under `artifacts/parity/<pair-id>/`. Ignore generated artifacts in Git. Retain `legacy-result.json`, `keiro-result.json`, and `parity-result.json` with no credentials/personal data. Record the actual binary/scenario revision, canonical scenario-description digest, normalized logical input, implementation source revisions observed by startup, separate physical business-key mappings, selected correlation strategies, and evidence windows. An intended config label alone is not the implementation identity.

Define `schemas/parity-result-v1.schema.json`. The summary references both individual result files and their digests, scenario ID/revision, pair ID, logical input mapping, and compatibility checks. Pass requires both reports to Pass and all pairing checks to agree. If either has a definitive Fail, the pair is Fail while retaining other Unknown results. Missing reports, mismatched scenario/input identity, unknown implementation revisions, incomplete evidence, or an unavailable stack yield Unknown and a nonzero result. Invalid invocation/configuration is exit 2; use the core CLI's 0/1/3 verdict mapping and 4 for unexpected runner faults. Never overwrite individual results when summarizing them.

### M3 — Demonstrate sensitivity and reproducibility


Use controlled local fixture settings to withhold one expected projection/event or introduce an actual duplicate outcome where the fixture supports it, then show a conclusive Fail. Separately deny one evidence connection while keeping the application unchanged, then show Unknown with the unavailable source. Prefer the existing documented service controls; do not add arbitrary production fault injection. Restore the fixture and rerun with fresh IDs to recover Pass. Demonstrate repeated paired runs do not share stale evidence and cleanup is limited to their owned resources.

Create `docs/tutorials/first-parity-run.md` with exact prerequisites, source revisions, build/start/inspect/run/cleanup commands, example sanitized outputs, and diagnostic meaning. Add the real parity invocation to CI only on a job that actually provisions its dependencies; keep unit/adapter checks available independently. A missing optional environment may be visibly unavailable in an ordinary developer run, but the release/acceptance parity job must fail rather than silently skip. Update README and the MasterPlan with retained acceptance evidence. Review all child decisions/discoveries/outcomes and update `docs/adr/` before marking the initiative complete.

## Concrete Steps


From the Shōko repository root after all hard dependencies are Complete:

```bash
nix develop --command just workflow-check
nix develop --command just workflow-up legacy
nix develop --command just workflow-up keiro
nix develop --command just parity
nix develop --command just parity-failure-control
nix develop --command just parity-unavailable-control
nix develop --command just workflow-down legacy
nix develop --command just workflow-down keiro
nix develop --command just check
```

This plan creates the three parity recipes. `parity-failure-control` and `parity-unavailable-control` are test wrappers that assert expected nonzero verifier exits and succeed only when those outcomes and reasons are observed. `parity` reports the exact artifact directory and exits zero only on two valid passing results. The tutorial must include the domain host's exact command, obtained from the accepted manifest, so the wrapper is not an opaque prerequisite.

## Validation and Acceptance


Acceptance requires the same compiled scenario ID, revision/digest, normalized inputs, and domain expectation set on both actual implementations, with both Pass results and a valid paired summary. Inspect evidence to confirm business-key isolation and actual source identities. Change only one implementation binding or inject the controlled defect and observe Fail. Remove evidence access and observe Unknown, not missing-row Fail or empty-query Pass. A mismatched scenario digest or unavailable target prevents a parity Pass. Repeat with new identities to prove old evidence cannot satisfy the run. Check cleanup, JSON schema validation, and tutorial reproducibility from a fresh shell.

A toy demo, a single real implementation plus a mock, a healthy HTTP status, or two structurally different scenarios cannot meet these criteria. Staging OTP, production read access, Kafka observation, replay, tracing queries, and cutover approval are not acceptance obligations of this bootstrap.

## Idempotence and Recovery


Use a unique pair ID and separate physical fixture IDs for each implementation. Preserve reports as immutable evidence and create a new pair directory for retries. Cleanup only manifest-owned data/processes; restore controlled failure settings before retrying. If a required domain package or target service is absent, record its canonical upstream owner/prerequisite and leave the child incomplete. Revisit the workflow-selection plan rather than implementing a service rewrite as incidental Shōko work. Any change to the domain contract must update both bindings, the workflow manifest, the plans, and relevant ADRs before acceptance.

## Interfaces and Dependencies


Hard dependencies: Complete `docs/plans/2-establish-the-first-workflow-contract-and-composed-local-environments.md`, `docs/plans/4-implement-postgresql-and-http-evidence-bindings.md`, `docs/plans/5-implement-kiroku-and-message-db-evidence-bindings.md`, and `docs/plans/6-expose-scenario-inspection-execution-and-structured-reports.md`. No soft dependencies remain at this final gate. The workflow plan owns the source manifest/lifecycle interface; the context owns business vocabulary; core owns individual result JSON; CLI owns host invocation; this plan owns paired-result schema, comparison logic, integration configs, tutorials, and acceptance automation. Shared manifest/build/CI changes preserve their original owners' contracts.
