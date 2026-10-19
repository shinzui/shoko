---
type: "Term"
title: "closing read"
description: "A final history observation that establishes coverage through a fixed evidence cutoff."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-9"
status: "current"
tags:
  - "evidence"
scope: "Shoko"
related:
  - "TERM-20"
  - "TERM-23"
  - "TERM-16"
anchors:
  - kind: "doc"
    resource: "docs/adapters.md"
---

# closing read

A final history observation that establishes coverage through a fixed evidence cutoff.

A negative or cardinality assertion may need this read after the evidence interval ends, using remaining execution budget. A read overlapping the cutoff may need a fresh snapshot. Closing does not extend the interval, and a late ambiguous match can leave coverage incomplete.

See the [implementation or guide](../../docs/adapters.md).

Related: [evidence cutoff](evidence-cutoff.md), [execution budget](execution-budget.md), [durable history](durable-history.md).
