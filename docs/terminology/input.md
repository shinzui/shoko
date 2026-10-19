---
type: "Term"
title: "input"
description: "A typed description of a value supplied to an operation, possibly depending on earlier step results."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-27"
status: "current"
tags:
  - "authoring"
scope: "Shoko"
aliases:
  - "Input"
related:
  - "TERM-37"
  - "TERM-28"
anchors:
  - kind: "file"
    resource: "shoko-core/src/Shoko/Internal/Reference.hs"
---

# input

A typed description of a value supplied to an operation, possibly depending on earlier step results.

Inputs combine constants and references through pure mapping and applicative composition. They keep the scenario's dependencies inspectable. An input's private runtime value is distinct from the allowlisted logical-input summary stored in a report.

See the [implementation or guide](../../shoko-core/src/Shoko/Internal/Reference.hs).

Related: [reference](reference.md), [logical input](logical-input.md).
