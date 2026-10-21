---
type: "Term"
title: "AppendOnlyDuringRun"
description: "The source owner's promise that scoped event history will not be deleted, truncated, or rewritten during the finite run."
generated:
  by: "anthropic/claude-opus-5-5"
  at: "2026-10-21T22:40:00Z"
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

Durable completeness depends on this history policy, including exclusion of retention jobs. For a Kafka topic it also excludes time- or size-based retention and log compaction removing records produced during the run; the reader detects retention through low watermarks but cannot detect compaction. It is a declared condition that needs owner-backed readiness evidence, not a property the adapter can create. `UnverifiedHistory` does not make the promise and cannot support complete negative or cardinality claims.

See the [implementation or guide](../../shoko-adapters/src/Shoko/Adapter/EventStore.hs).

Related: [durable history](durable-history.md), [workflow contract](workflow-contract.md).
