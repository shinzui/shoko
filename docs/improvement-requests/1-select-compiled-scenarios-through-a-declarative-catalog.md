---
type: Improvement Request
title: Select compiled scenarios through a declarative catalog with shared inspection
description: Give consumers a versioned scenario catalog schema and a packaged list, explain and check dispatcher so a QA repository can select compiled scenarios by stable ID without forking Shoko's inspection mechanics.
requestId: IR-1
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
    context: Author self-check against the current shoko-cli command surface, the independent consumer host, and the tan-platform-qa bootstrap plans that raise this request; no independent review or implementation evidence is claimed.
acceptanceCriteria:
  - id: AC-1
    statement: A strict versioned catalog schema accepts entries carrying a stable scenario ID, revision, canonical owning and participating project URIs, host artifact and immutable source identity, workflow and configuration paths, suite membership, and a required or control role, and a separate pending branch that carries an explicit missing-artifact reason.
    verification: Schema fixtures for valid ready and pending entries, and rejection fixtures for duplicate or unknown IDs, duplicate JSON keys, missing required fields, unsupported environments, path traversal outside the workspace, and unknown schema versions.
  - id: AC-2
    statement: A packaged dispatcher offers catalog-check, list, explain and check commands that resolve a declared host artifact and invoke it with an argument vector, preserve the host's exit codes 0, 1, 2, 3 and 4, and perform no credential-value lookup, metadata callback, fixture, action or target IO.
    verification: Process tests against the independent consumer host, including an instrumented fixture that proves zero callbacks and actions during list, explain and check, and checks that secret sentinels never appear in output.
  - id: AC-3
    statement: Live dispatch rejects pending catalog entries, production, and arbitrary environment aliases at the dispatcher boundary before any host invocation.
    verification: Tests selecting a pending entry, the production environment, and alias names exit 2 without starting the host process.
  - id: AC-4
    statement: A consumer repository pins the dispatcher by immutable Shoko revision and selects scenarios from its own catalog file without owning a parallel schema or parser.
    verification: The tan-platform-qa workspace child invokes the pinned dispatcher against its catalog and its tests exercise the real consumer process rather than mocked return values.
---

Let a consumer repository declare which compiled scenarios exist, which suite each belongs to, and where its host artifact comes from, then list, explain and policy-check them through one shared tool. Today `shoko-cli` inspects exactly one compiled scenario per process through `runShokoCli`, and the independent consumer host under `shoko-cli/test/ConsumerHost/` shows how a context compiles its own entries. There is no catalog across hosts, no notion of suite membership or control role, and no shared dispatcher that a second repository can pin instead of writing its own selector.

## Requested behavior

Publish a strict catalog schema and a packaged inspection dispatcher owned by Shoko. The schema is declarative test metadata, not a service inventory: each entry names a stable scenario ID, a revision, canonical owning and participating project URIs, the host artifact and its immutable source identity, the workflow and configuration paths the scenario reads, the suite it belongs to, and whether it is a required scenario or a labelled control. A pending branch records an explicit missing-artifact reason so a suite can be listed truthfully before its host exists; live dispatch refuses it.

The dispatcher resolves a declared host artifact and passes an argument vector. It never executes shell strings embedded in catalog data, never compiles Haskell at runtime, and never infers dependencies or classifies code changes. Its `list`, `explain` and `check` commands delegate to the host's existing commands and preserve the host's exit codes; `check` establishes policy validity only and must stay distinct from any live readiness check. Production and arbitrary environment aliases are rejected before invocation even when a host-side environment check alone would miss an alias.

## Consumer

`mori://tan/tan-platform-qa` keeps `config/scenarios.json` and a thin `scripts/qa` selector that invokes this pinned tool. Its workspace child, `mori://tan/tan-platform-qa/plans/1-establish-the-qa-workspace-and-explicit-scenario-catalog`, reserves the suite `notification-rendering` and the scenario IDs `notification-rendering-success` and `notification-rendering-refusal`. Later, a registration host from `mori://tan/registration-service-v2` can register entries in the same format. The suite executor requested by [IR-3](3-execute-a-catalog-suite-with-shoko-owned-acceptance-envelopes.md) consumes this catalog for selection.

## Completion

Completion requires evidence for AC-1 through AC-4, the schema and dispatcher published from one immutable Shoko revision, and a capability entry in the capability catalog describing the inspection surface and its limits.
