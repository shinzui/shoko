---
type: "Term"
title: "eventually"
description: "A temporal assertion requiring a matching observation completed within its finite deadline."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-18"
status: "current"
tags:
  - "evidence"
scope: "Shoko"
related:
  - "TERM-25"
  - "TERM-20"
  - "TERM-9"
  - "TERM-47"
anchors:
  - kind: "doc"
    resource: "docs/core.md"
---

# eventually

A temporal assertion requiring a matching observation completed within its finite deadline.

A witness completed at the deadline can pass. Healthy conclusive nonmatching sampled reads can establish failure at expiry; unresolved evidence gaps yield Unknown. A durable-history source also needs complete closing history before a missing event can be called Fail. A later completed witness cannot retroactively pass the earlier window.

See the [implementation or guide](../../docs/core.md).

Related: [expectation](expectation.md), [evidence cutoff](evidence-cutoff.md), [closing read](closing-read.md), [verdict](verdict.md).
