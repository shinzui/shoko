---
type: "Term"
title: "never"
description: "A temporal assertion requiring no matching occurrence throughout a bounded evidence interval."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-30"
status: "current"
tags:
  - "evidence"
scope: "Shoko"
related:
  - "TERM-25"
  - "TERM-12"
  - "TERM-41"
  - "TERM-16"
anchors:
  - kind: "doc"
    resource: "docs/core.md"
---

# never

A temporal assertion requiring no matching occurrence throughout a bounded evidence interval.

A matching witness in the interval fails the assertion. Passing requires complete interval coverage, so repeatedly observing an absent mutable row does not prove continuous absence. An unavailable source or incomplete history leaves the assertion Unknown.

See the [implementation or guide](../../docs/core.md).

Related: [expectation](expectation.md), [coverage](coverage.md), [sampled state](sampled-state.md), [durable history](durable-history.md).
