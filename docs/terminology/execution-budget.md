---
type: "Term"
title: "execution budget"
description: "The finite total time available for acquisition, baselines, scenario operations, and evidence evaluation."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-23"
status: "current"
tags:
  - "execution"
scope: "Shoko"
related:
  - "TERM-20"
  - "TERM-8"
  - "TERM-9"
anchors:
  - kind: "file"
    resource: "shoko-core/src/Shoko/Environment.hs"
---

# execution budget

The finite total time available for acquisition, baselines, scenario operations, and evidence evaluation.

The budget starts before resource acquisition. Nested expectation windows take the earliest applicable deadline, and handler requests share the remaining time. Defaults are thirty seconds total, ten seconds for eventual assertions, and one hundred milliseconds between polls. Cleanup has a separate grace period.

See the [implementation or guide](../../shoko-core/src/Shoko/Environment.hs).

Related: [evidence cutoff](evidence-cutoff.md), [cleanup grace](cleanup-grace.md), [closing read](closing-read.md).
