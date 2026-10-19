---
type: "Term"
title: "disposition"
description: "The recorded outcome of a resource's contracted cleanup or retention."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-14"
status: "current"
tags:
  - "execution"
scope: "Shoko"
related:
  - "TERM-8"
  - "TERM-26"
  - "TERM-47"
anchors:
  - kind: "file"
    resource: "shoko-core/src/Shoko/Binding.hs"
---

# disposition

The recorded outcome of a resource's contracted cleanup or retention.

`Cleaned` records completed cleanup, `Retained` records contracted retention, and `CleanupFailed` or `CleanupTimedOut` record unsuccessful finalization. Retention can be appropriate when deletion is not the agreed outcome. An existing Fail remains Fail even when cleanup is unsuccessful.

See the [implementation or guide](../../shoko-core/src/Shoko/Binding.hs).

Related: [cleanup grace](cleanup-grace.md), [fixture](fixture.md), [verdict](verdict.md).
