---
type: "Term"
title: "occurrence"
description: "One observed domain value with an optional stable identity used to recognize repeated reads of the same fact."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-32"
status: "current"
tags:
  - "evidence"
scope: "Shoko"
related:
  - "TERM-22"
  - "TERM-3"
  - "TERM-21"
anchors:
  - kind: "file"
    resource: "shoko-core/src/Shoko/Observation.hs"
---

# occurrence

One observed domain value with an optional stable identity used to recognize repeated reads of the same fact.

Exactly-once counting requires stable, source-unique identities. A stream-local position must include its stream identity when used across a wider query. Reobserving one identity is not a second occurrence; a distinct identity is, even if its payload looks identical.

See the [implementation or guide](../../shoko-core/src/Shoko/Observation.hs).

Related: [exactlyOnce](exactly-once.md), [baseline](baseline.md), [evidence source](evidence-source.md).
