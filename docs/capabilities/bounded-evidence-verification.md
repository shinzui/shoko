---
type: "Capability"
title: "Bounded evidence verification"
description: "Execute scenarios with finite deadlines, correlated evidence, three temporal assertions, and bounded cleanup while preserving uncertain outcomes."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
capabilityId: "CAP-3"
provider: "mori://shinzui/shoko"
status: "shipped"
stability: "experimental"
since: "unreleased"
packages:
  - "shoko-core"
interface:
  - "Shoko.runScenario"
  - "Shoko.eventually"
  - "Shoko.never"
  - "Shoko.exactlyOnce"
  - "Shoko.within"
  - "Shoko.Clock"
requires:
  - "CAP-2"
evidence:
  - kind: "test"
    resource: "shoko-core/test/TemporalSpec.hs"
    proves: "Temporal cardinality, baseline exclusion, and typed negative outcomes."
  - kind: "test"
    resource: "shoko-core/test/CoverageSpec.hs"
    proves: "Coverage gaps, closing history reads, and cutoff boundaries."
  - kind: "test"
    resource: "shoko-core/test/RuntimeSpec.hs"
    proves: "Cancellation, cleanup limits, composite substeps, and suppression of later mutations."
  - kind: "test"
    resource: "shoko-core/test/FaultSpec.hs"
    proves: "Unexpected faults retain available partial results and sanitize reasons."
---

# Bounded evidence verification

The runner captures source baselines before fixtures and actions, resolves declared inputs, and runs sibling expectations concurrently. It supports business-key correlation, including a key returned by an action, and execution-ID correlation when a binding explicitly supports propagation. Handlers and declared composite substeps share finite execution deadlines.

`eventually`, `never`, and `exactlyOnce` evaluate bounded evidence. Fail dominates Unknown, which dominates Pass. Expected typed domain rejections can pass a negative scenario. Required cleanup has its own finite grace; cancellation still propagates after finalization is attempted.

## Limits

Mutating actions are never automatically retried after a timeout. Sampled state cannot prove continuous absence or durable cardinality. Negative and cardinality assertions need complete interval coverage; missing durable history closure remains Unknown. The runner neither implements Observe/Replay nor compares two implementation reports automatically.

## Use and evidence

See [bounded verification](../core.md).

## Builds on

- [Execution policy preflight](execution-policy-preflight.md)
