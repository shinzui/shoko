---
type: Improvement Request
title: Execute a catalog suite with Shoko-owned acceptance envelopes and offline verification
description: Provide shared run and verify commands so any consumer can execute a catalog suite against an observed target, retain per-scenario acceptance envelopes atomically, aggregate exits with a fixed precedence, and verify bundle integrity offline without a consumer-local executor.
requestId: IR-3
status: proposed
origin: mori://tan/tan-platform-qa
generated:
  by: anthropic/claude-fable-5-1
  at: "2026-10-21T18:15:00Z"
reviews:
  - kind: model
    reviewer: anthropic/claude-fable-5-1
    provider: anthropic
    model: claude-fable-5-1
    effort: unspecified
    reviewed_at: "2026-10-21T18:15:00Z"
    document_timestamp: "2026-10-21T18:15:00Z"
    scope: content-and-metadata
    outcome: commented
    context: Author self-check against the scenario-hosts guide, the run-result v2 schema and atomic --output behavior, plan 7's envelope and wrapper scope, and the tan-platform-qa suite-execution plan that raises this request; no independent review or implementation evidence is claimed.
dependencies:
  - ref: mori://shinzui/shoko/okf/improvement-requests/concepts/IR-1
    kind: hard
    reason: The executor selects required and control scenarios from the shared catalog and resolves each host artifact through the catalog dispatcher.
  - ref: mori://shinzui/shoko/okf/improvement-requests/concepts/IR-2
    kind: hard
    reason: The executor calls the shared readiness and observe command before and after each scenario and embeds its observation in the acceptance envelope.
acceptanceCriteria:
  - id: AC-1
    statement: A run command taking a catalog, a manifest, a suite ID, an artifacts root and explicit per-invocation synthetic consent calls the shared target check, executes each required scenario once through its declared host, captures the unchanged core v2 report and exit, re-observes the target, and writes a Shoko-owned acceptance envelope atomically last under a fresh suite, attempt, scenario and run directory, refusing existing directories.
    verification: Process tests with the independent consumer host, including interrupted-write and pre-existing-directory cases that leave no accepted envelope and never replace prior evidence.
  - id: AC-2
    statement: The envelope schema references exact file digests, manifest and catalog digests, scenario ID, revision and description digest, evidence sources and coverage, the requirement mapping, resolved business keys, safe recipe identity, verifier binary and source identity, before and after target identity, and cleanup disposition, and never carries payloads, secrets, addresses, OTPs, rendered content or raw transport exceptions.
    verification: Schema validation of produced envelopes plus secret-sentinel absence checks over stdout, stderr and every retained artifact.
  - id: AC-3
    statement: A suite summary preserves every individual outcome and uses the aggregate exit precedence 4 for a command or persistence fault, 2 for invalid invocation, policy or readiness, 1 for a conclusive Fail, 3 for Unknown or an unexecuted required scenario, and otherwise 0; controls carry separate IDs and roles and never enter the all-required-pass decision; a core Fail stays visible when target attribution is incomplete.
    verification: Table-driven summary tests covering each precedence level, skipped required scenarios, controls, and incomplete attribution.
  - id: AC-4
    statement: An offline verify command checks schema validity, digests, completeness and requirement mapping over a completed bundle and states that it checks integrity rather than recomputing any verdict.
    verification: Tampered-digest, missing-file and changed-manifest fixtures fail verification while an unmodified bundle passes, and the command's output names its integrity-only scope.
  - id: AC-5
    statement: The registration suite and the notification-rendering suite both run through the identical command with different catalog and manifest inputs, and the executor contains no workflow-specific logic.
    verification: Both suites are exercised through the same command in tests, and a structural test asserts the executor has no registration-specific or notification-specific branches.
---

Let a consumer run every required scenario of a suite against an explicitly observed staging target and keep evidence that a reviewer can trust later, through one shared executor rather than a per-repository script. Today `shoko-cli` runs one scenario per process, writes one core v2 result atomically with `--output`, and returns exits 0, 1, 2, 3 and 4. The staging acceptance envelope, suite summary, control wrappers and operator tutorial are planned by `docs/plans/7-verify-one-real-workflow-across-legacy-and-keiro-implementations.md`, but that plan is scoped to the registration workflow and is not started, and no generic executor exists in source.

## Requested behavior

Publish a `shoko-suite` executor with two commands. `run --catalog PATH --manifest PATH --suite ID --artifacts PATH`, with explicit `--allow-synthetic` forwarded only when supplied, selects the suite's required scenarios from the catalog of [IR-1](1-select-compiled-scenarios-through-a-declarative-catalog.md), calls the shared readiness and observe command of [IR-2](2-generalize-the-staging-workflow-contract-and-readiness-checks.md), executes each scenario once through its declared host, captures the unchanged v2 report and exit, re-observes the target, and persists the acceptance envelope atomically as the completion marker. Artifacts live under `<artifacts>/<suite-id>/<attempt-id>/<scenario-id>/<run-id>/`; the attempt directory groups the scenarios of one suite invocation and holds the summary. The executor validates required expectation IDs, source IDs and coverage against the manifest; a missing or duplicate expectation, incompatible revision, undeclared source, skipped required scenario, missing artifact or unmatched before-and-after deployment prevents acceptance. The core verdict stays separate from target and attribution validity, and a core report is never rewritten to encode an infrastructure failure.

`verify BUNDLE` performs schema, digest, completeness and mapping checks over a completed bundle offline and says so: it checks integrity, it does not recompute a verdict, and plain JSON validation is not an attestation.

Controls use separate IDs and roles. A control wrapper may exit 0 after proving its expected nonzero Shoko outcome and reason, but it retains that outcome and stays labelled; it can never enter the suite's all-required-pass decision, and an optional check cannot hide a missing required scenario. No application lifecycle commands, automatic mutation retries, scheduler, or deployment subscription belong to this executor.

## Consumers

`mori://tan/tan-platform-qa/plans/4-deliver-attributable-staging-suite-execution-and-operator-acceptance` adds `scripts/qa staging --suite notification-rendering` and `just staging` as thin invocations and consumes the envelope schema when a platform curator cites an accepted bundle. The registration suite of plan 7 is the second consumer; its `scripts/run-staging` and `just staging` become thin registration-specific invocations of the same command.

## Completion

Completion requires evidence for AC-1 through AC-5, the executor and envelope schema published from one immutable Shoko revision, one notification producer-and-consumer bundle validated before further catalog variants, and a capability entry describing the executor's guarantees and limits.
