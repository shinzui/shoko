---
type: "Term"
title: "run ID"
description: "The report identity assigned to one Shoko execution."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-39"
status: "current"
tags:
  - "results"
scope: "Shoko"
related:
  - "TERM-24"
  - "TERM-28"
anchors:
  - kind: "file"
    resource: "shoko-core/src/Shoko/Environment.hs"
---

# run ID

The report identity assigned to one Shoko execution.

It distinguishes results from separate invocations and can be offered as an HTTP run label. It becomes an execution-correlation key only when the binding and target explicitly support the required propagation. Reusing a report identity does not replay a run or its evidence.

See the [implementation or guide](../../shoko-core/src/Shoko/Environment.hs).

Related: [execution ID](execution-id.md), [logical input](logical-input.md).
