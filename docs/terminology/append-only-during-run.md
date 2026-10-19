---
type: "Term"
title: "AppendOnlyDuringRun"
description: "The source owner's promise that scoped event history will not be deleted, truncated, or rewritten during the finite run."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-2"
status: "current"
tags:
  - "evidence"
scope: "Shoko"
related:
  - "TERM-16"
  - "TERM-49"
anchors:
  - kind: "file"
    resource: "shoko-adapters/src/Shoko/Adapter/EventStore.hs"
---

# AppendOnlyDuringRun

The source owner's promise that scoped event history will not be deleted, truncated, or rewritten during the finite run.

Durable completeness depends on this history policy, including exclusion of retention jobs. It is a declared condition that needs owner-backed readiness evidence, not a property the adapter can create. `UnverifiedHistory` does not make the promise and cannot support complete negative or cardinality claims.

See the [implementation or guide](../../shoko-adapters/src/Shoko/Adapter/EventStore.hs).

Related: [durable history](durable-history.md), [workflow contract](workflow-contract.md).
