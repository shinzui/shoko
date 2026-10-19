---
type: "Term"
title: "sampled state"
description: "Evidence about mutable state at observation samples rather than all changes during an interval."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-41"
status: "current"
tags:
  - "evidence"
scope: "Shoko"
related:
  - "TERM-12"
  - "TERM-16"
  - "TERM-30"
  - "TERM-22"
anchors:
  - kind: "doc"
    resource: "docs/adapters.md"
---

# sampled state

Evidence about mutable state at observation samples rather than all changes during an interval.

HTTP GET and scoped PostgreSQL state queries advertise this strength. Seeing an absent row can satisfy an eventual sampled-absence predicate, but cannot establish that the row was absent continuously or that an event occurred only once.

See the [implementation or guide](../../docs/adapters.md).

Related: [coverage](coverage.md), [durable history](durable-history.md), [never](never.md), [exactlyOnce](exactly-once.md).
