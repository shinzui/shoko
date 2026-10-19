---
type: "Term"
title: "negative scenario"
description: "A scenario that expects a documented rejection or invariant to hold under a specific adverse input or condition."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-29"
status: "current"
tags:
  - "results"
scope: "Shoko"
related:
  - "TERM-15"
  - "TERM-47"
  - "TERM-49"
anchors:
  - kind: "file"
    resource: "shoko-core/test/TemporalSpec.hs"
---

# negative scenario

A scenario that expects a documented rejection or invariant to hold under a specific adverse input or condition.

A negative scenario can Pass when its expected rejection and downstream invariant are established. Unexpected acceptance or rejection is Fail; unavailable evidence or transport uncertainty is Unknown. A generic error is insufficient proof of the intended rejection contract.

See the [implementation or guide](../../shoko-core/test/TemporalSpec.hs).

Related: [domain outcome](domain-outcome.md), [verdict](verdict.md), [workflow contract](workflow-contract.md).
