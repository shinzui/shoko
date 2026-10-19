---
type: "Term"
title: "composite action"
description: "An action implemented through named substeps declared in its operation description."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-10"
status: "current"
tags:
  - "authoring"
scope: "Shoko"
related:
  - "TERM-1"
  - "TERM-23"
anchors:
  - kind: "file"
    resource: "shoko-core/src/Shoko/Binding.hs"
---

# composite action

An action implemented through named substeps declared in its operation description.

Each substep shares the parent's remaining deadline and records timing and reason evidence. An undeclared substep does not execute. This supports a multi-request business operation, such as a completion flow, without making its internal steps separate scenario nodes.

See the [implementation or guide](../../shoko-core/src/Shoko/Binding.hs).

Related: [action](action.md), [execution budget](execution-budget.md).
