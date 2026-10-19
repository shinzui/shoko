---
type: "Term"
title: "coverage"
description: "A source's claim about the evidence interval it establishes, its strength, and whether it is complete."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-12"
status: "current"
tags:
  - "evidence"
scope: "Shoko"
related:
  - "TERM-41"
  - "TERM-16"
  - "TERM-20"
anchors:
  - kind: "file"
    resource: "shoko-core/src/Shoko/Observation.hs"
---

# coverage

A source's claim about the evidence interval it establishes, its strength, and whether it is complete.

Coverage uses an inclusive monotonic interval. Sampled state and durable history make different claims, even if both return no matching values. Missing reads, exhausted page bounds, or ambiguous cutoff matches can make history incomplete. Source availability by itself does not prove completeness.

See the [implementation or guide](../../shoko-core/src/Shoko/Observation.hs).

Related: [sampled state](sampled-state.md), [durable history](durable-history.md), [evidence cutoff](evidence-cutoff.md).
