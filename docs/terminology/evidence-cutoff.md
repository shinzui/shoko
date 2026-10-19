---
type: "Term"
title: "evidence cutoff"
description: "The fixed end of the interval whose evidence an expectation is allowed to evaluate."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-20"
status: "current"
tags:
  - "execution"
scope: "Shoko"
related:
  - "TERM-9"
  - "TERM-23"
  - "TERM-12"
anchors:
  - kind: "file"
    resource: "shoko-core/src/Shoko/Binding.hs"
---

# evidence cutoff

The fixed end of the interval whose evidence an expectation is allowed to evaluate.

`evidenceUntil context` denotes this cutoff, while `requestDeadline context` bounds the current request using remaining execution time. A closing history read may happen after the cutoff but cannot count ambiguous later events as timely matches or extend the run budget.

See the [implementation or guide](../../shoko-core/src/Shoko/Binding.hs).

Related: [closing read](closing-read.md), [execution budget](execution-budget.md), [coverage](coverage.md).
