---
type: "Term"
title: "exactlyOnce"
description: "A temporal assertion requiring exactly one distinct matching occurrence in a completely covered bounded interval."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-22"
status: "current"
tags:
  - "evidence"
scope: "Shoko"
related:
  - "TERM-32"
  - "TERM-12"
  - "TERM-9"
anchors:
  - kind: "doc"
    resource: "docs/core.md"
---

# exactlyOnce

A temporal assertion requiring exactly one distinct matching occurrence in a completely covered bounded interval.

Repeated polls of the same occurrence are deduplicated by identity. A second distinct occurrence fails immediately; one occurrence passes only after interval closure, and complete closure with zero fails. This is a count of evidence occurrences, not a guarantee that remote code executed or committed only once.

See the [implementation or guide](../../docs/core.md).

Related: [occurrence](occurrence.md), [coverage](coverage.md), [closing read](closing-read.md).
