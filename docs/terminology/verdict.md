---
type: "Term"
title: "verdict"
description: "The three-valued conclusion that evidence satisfies, violates, or cannot establish an expectation."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-47"
status: "current"
tags:
  - "results"
scope: "Shoko"
related:
  - "TERM-19"
  - "TERM-29"
  - "TERM-14"
anchors:
  - kind: "file"
    resource: "shoko-core/src/Shoko/Result.hs"
---

# verdict

The three-valued conclusion that evidence satisfies, violates, or cannot establish an expectation.

Pass means the scoped requirement was satisfied, Fail means a violation was established, and Unknown means evidence or execution was insufficient. Aggregation preserves every child and gives Fail precedence over Unknown over Pass. Preflight failure and runner fault are separate result variants, not additional business verdicts.

See the [implementation or guide](../../shoko-core/src/Shoko/Result.hs).

Related: [evidence](evidence.md), [negative scenario](negative-scenario.md), [disposition](disposition.md).
