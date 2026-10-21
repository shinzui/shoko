---
type: Improvement Request
title: Generalize the staging workflow contract and readiness checks beyond registration
description: Factor the registration-specific workflow contract and identity checks into a workflow-independent schema and a packaged validate, check and observe command so a second workflow can declare its target, prerequisites and evidence without relabeling the registration example.
requestId: IR-2
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
    context: Author self-check against schemas/workflow-v1.schema.json, scripts/workflow_contract.py, scripts/workflow_identity.py, the first-staging-workflow guide, and the tan-platform-qa staging-contract plan that raises this request; no independent review or implementation evidence is claimed.
acceptanceCriteria:
  - id: AC-1
    statement: A versioned workflow-independent schema accepts a non-registration manifest carrying a workflow ID, scenario IDs and revisions, requirement-to-expectation mappings with evidence strength, fixture recipe identity, canonical owners and participants, pending prerequisites with owner, reason and clearing check, and explicit exclusions, while the registration manifest and its existing contract tests keep passing through a compatibility path or a new major version.
    verification: Fixtures for the notification-rendering workflow and the registration workflow both validate; the existing test-workflow-contract groups pass unchanged.
  - id: AC-2
    statement: A structure-only validate command exits 0 for a structurally valid manifest that still names pending prerequisites, reports readiness as unchecked, and performs no Kubernetes, credential or network access.
    verification: Process tests run with no kubeconfig and no credential values present and assert zero outbound calls.
  - id: AC-3
    statement: A read-only check command establishes readiness with an explicit context, API server and namespace on every call, TLS validation, runtime image IDs for every application, init and sidecar container, controller ownership and rollout state, endpoint-to-deployment associations, and configured expectations compared against observed identity, returning public blocker codes and exit 2 on any mismatch with zero writes.
    verification: Fake-cluster fixtures for each mismatch class, plus sanitized-artifact checks that exclude kubeconfig, process errors, addresses and secrets.
  - id: AC-4
    statement: An observe command produces one schema-governed bounded target observation that both a host metadata callback and a suite wrapper consume, so readiness has one implementation.
    verification: The notification host's metadata callback and the suite executor parse the same observation artifact in their tests.
  - id: AC-5
    statement: Registration-specific prerequisites such as the OTP path and qualified-agent completion are declared by the registration manifest rather than hard-coded in the shared validator.
    verification: A structural test asserts that the shared validator contains no workflow-specific requirement sets, and the registration manifest declares its own.
---

Let a second workflow declare its staging target, prerequisites, requirement mappings and evidence sources through the same contract the registration workflow uses, and establish read-only readiness through one shared implementation. Today `schemas/workflow-v1.schema.json` and `scripts/workflow_contract.py` hard-code registration: the validator requires the cluster-access, controlled-fixtures, otp-path and real-completion prerequisites, the five registration positive requirements, and the qualification exclusions. `scripts/workflow_identity.py` performs read-only Kubernetes identity observations, and `scripts/workflow-env check --identity-only` can establish matching namespace and workload identity, but full readiness and the independent smoke remain unfinished work of `docs/plans/2-establish-the-first-workflow-contract-and-composed-local-environments.md`. A consumer verifying notification-hub against notification-render-service cannot use any of this without relabeling the registration example.

## Requested behavior

Factor the workflow-independent parts into a versioned generic schema and a packaged `shoko-workflow` command with three modes. `validate --structure-only` checks structure and relationships without credentials or prerequisite confirmation and reports readiness as unchecked. `check` performs full read-only readiness against the deployed target named by the manifest: explicit context, server and namespace on every call, TLS validation, runtime pod image IDs for all containers including init and sidecar containers, controller ownership, rollout state, endpoint-to-deployment associations, and a comparison of configured expectations against observed identity, with bounded calls, subprocesses and response sizes. `observe` emits a bounded fresh target observation under a published schema so that a compiled host's metadata callback and a suite wrapper share one implementation instead of two checkers that drift.

Workflow-specific prerequisites move into each manifest. The registration manifest keeps its OTP and qualified-agent declarations; the notification manifest declares a controlled recipient, a published live notification type, a deployed safe-mode block and scoped evidence access. Credential presence is never sufficient; structural validity grants no action permission; synthetic examples must be rejected by live commands. A past artifact is never a reusable pass token: host callback and suite wrapper invoke the gate freshly for each run.

## Consumer

`mori://tan/tan-platform-qa/plans/2-establish-the-staging-workflow-contract-and-live-readiness-gate` writes `integration/notification-rendering/workflow.json` against this contract and pins the accepted command revision in its toolchain record. Its host metadata callback and the suite executor requested by [IR-3](3-execute-a-catalog-suite-with-shoko-owned-acceptance-envelopes.md) both consume the `observe` output. The registration workflow of `docs/plans/7-verify-one-real-workflow-across-legacy-and-keiro-implementations.md` remains the other consumer.

## Completion

Completion requires evidence for AC-1 through AC-5, the generic schema and command published from one immutable Shoko revision, the registration compatibility path recorded in the first-staging-workflow guide, and an updated capability entry for offline contract validation and target identity checks.
