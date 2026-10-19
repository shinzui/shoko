---
type: "Term"
title: "evidence"
description: "The retained public record of what was observed, where, when, and under which correlation and coverage."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-19"
status: "current"
tags:
  - "evidence"
scope: "Shoko"
related:
  - "TERM-21"
  - "TERM-12"
  - "TERM-11"
  - "TERM-36"
anchors:
  - kind: "file"
    resource: "shoko-core/src/Shoko/Evidence.hs"
---

# evidence

The retained public record of what was observed, where, when, and under which correlation and coverage.

Action evidence includes declared and observed outcomes and substeps. Observation evidence records the source, baseline, timing, coverage, matching identities, and safe supporting summaries. Raw typed domain values are used for predicates but are not automatically copied into reports.

See the [implementation or guide](../../shoko-core/src/Shoko/Evidence.hs).

Related: [evidence source](evidence-source.md), [coverage](coverage.md), [correlation](correlation.md), [public summary](public-summary.md).
