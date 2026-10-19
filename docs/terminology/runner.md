---
type: "Term"
title: "runner"
description: "The interpreter that executes a resolved scenario, gathers evidence, evaluates expectations, and attempts resource finalization."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-40"
status: "current"
tags:
  - "execution"
scope: "Shoko"
related:
  - "TERM-35"
  - "TERM-23"
  - "TERM-14"
  - "TERM-47"
anchors:
  - kind: "file"
    resource: "shoko-core/src/Shoko/Runner.hs"
---

# runner

The interpreter that executes a resolved scenario, gathers evidence, evaluates expectations, and attempts resource finalization.

The runner captures baselines before fixtures and actions, bounds handler calls and composite substeps, and starts sibling expectations together. Unexpected or uncertain actions stop later mutations. A runner fault can retain partial verification evidence; cancellation attempts cleanup and then remains cancellation.

See the [implementation or guide](../../shoko-core/src/Shoko/Runner.hs).

Related: [preflight](preflight.md), [execution budget](execution-budget.md), [disposition](disposition.md), [verdict](verdict.md).
