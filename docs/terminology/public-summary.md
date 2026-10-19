---
type: "Term"
title: "public summary"
description: "An explicitly selected choice, count, or flag that may be retained in a report."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-36"
status: "current"
tags:
  - "results"
scope: "Shoko"
related:
  - "TERM-19"
  - "TERM-28"
anchors:
  - kind: "file"
    resource: "shoko-core/src/Shoko/Observation.hs"
---

# public summary

An explicitly selected choice, count, or flag that may be retained in a report.

Bindings choose public protocol statuses, row counts, or state flags instead of exposing raw typed values. `PublicChoice` is still author-supplied text: names and values must be non-secret. Selecting a summary does not make arbitrary payload contents safe.

See the [implementation or guide](../../shoko-core/src/Shoko/Observation.hs).

Related: [evidence](evidence.md), [logical input](logical-input.md).
