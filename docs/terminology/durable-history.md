---
type: "Term"
title: "durable history"
description: "Evidence that can establish all relevant occurrences over a finite interval when its completeness conditions hold."
generated:
  by: "anthropic/claude-opus-5-5"
  at: "2026-10-21T22:40:00Z"
termId: "TERM-16"
status: "current"
tags:
  - "evidence"
scope: "Shoko"
related:
  - "TERM-12"
  - "TERM-2"
  - "TERM-9"
anchors:
  - kind: "doc"
    resource: "docs/adapters.md"
---

# durable history

Evidence that can establish all relevant occurrences over a finite interval when its completeness conditions hold.

Shoko's event readers can supply this strength with append-only retention during the run, sufficient scan bounds, and a valid closing read. Merely reading an event table or a topic does not establish those conditions. For Kafka, every baseline partition must be read to its end, and any observed retention deletion, read-committed end regression, or partition-set change is sticky history loss for the run; compaction stays excluded only by the topic owner's promise. Unverified history may supply positive witnesses without proving absence or accepted cardinality.

See the [implementation or guide](../../docs/adapters.md).

Related: [coverage](coverage.md), [AppendOnlyDuringRun](append-only-during-run.md), [closing read](closing-read.md).
