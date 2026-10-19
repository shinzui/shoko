---
type: "Term"
title: "cleanup grace"
description: "The separate finite period available to release resources and run registered finalizers after execution."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-8"
status: "current"
tags:
  - "execution"
scope: "Shoko"
related:
  - "TERM-14"
  - "TERM-23"
  - "TERM-40"
anchors:
  - kind: "doc"
    resource: "docs/core.md"
---

# cleanup grace

The separate finite period available to release resources and run registered finalizers after execution.

The default is five seconds. Completed-resource release runs before partial-resource finalizers, which run in reverse registration order. Cleanup grace cannot be borrowed for more evidence collection. Failed or timed-out required cleanup makes an otherwise passing result Unknown.

See the [implementation or guide](../../docs/core.md).

Related: [disposition](disposition.md), [execution budget](execution-budget.md), [runner](runner.md).
