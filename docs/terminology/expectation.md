---
type: "Term"
title: "expectation"
description: "A named requirement that applies a temporal rule to an observation."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-25"
status: "current"
tags:
  - "authoring"
scope: "Shoko"
related:
  - "TERM-18"
  - "TERM-30"
  - "TERM-22"
  - "TERM-47"
anchors:
  - kind: "file"
    resource: "shoko-core/src/Shoko/Expectation.hs"
---

# expectation

A named requirement that applies a temporal rule to an observation.

For example, an account must eventually exist, or a delivery event must occur exactly once in a finite window. Sibling expectations share one activation time and run concurrently. Each retains its own verdict and evidence in the result.

See the [implementation or guide](../../shoko-core/src/Shoko/Expectation.hs).

Related: [eventually](eventually.md), [never](never.md), [exactlyOnce](exactly-once.md), [verdict](verdict.md).
