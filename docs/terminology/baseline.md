---
type: "Term"
title: "baseline"
description: "The source boundary captured before fixtures and actions to separate existing evidence from the current run."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-3"
status: "current"
tags:
  - "evidence"
scope: "Shoko"
related:
  - "TERM-21"
  - "TERM-32"
  - "TERM-11"
anchors:
  - kind: "file"
    resource: "shoko-core/src/Shoko/Observation.hs"
---

# baseline

The source boundary captured before fixtures and actions to separate existing evidence from the current run.

For durable event readers, the baseline captures existing scoped occurrence IDs and host capture time. Later polls can exclude those IDs while still detecting events committed later at lower positions. A cursor may carry opaque run-owned state; it is not a reusable replay token.

See the [implementation or guide](../../shoko-core/src/Shoko/Observation.hs).

Related: [evidence source](evidence-source.md), [occurrence](occurrence.md), [correlation](correlation.md).
