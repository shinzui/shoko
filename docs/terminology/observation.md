---
type: "Term"
title: "observation"
description: "A read-only operation paired with a named predicate for deciding whether returned values match."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-31"
status: "current"
tags:
  - "authoring"
scope: "Shoko"
related:
  - "TERM-25"
  - "TERM-19"
  - "TERM-41"
  - "TERM-16"
anchors:
  - kind: "file"
    resource: "shoko-core/src/Shoko/Observation.hs"
---

# observation

A read-only operation paired with a named predicate for deciding whether returned values match.

An observation requests evidence; an expectation supplies the temporal rule for interpreting it. Reading a row once may establish its sampled state, while an event reader may establish bounded history. The predicate's identity is public, but the raw observed domain value remains private.

See the [implementation or guide](../../shoko-core/src/Shoko/Observation.hs).

Related: [expectation](expectation.md), [evidence](evidence.md), [sampled state](sampled-state.md), [durable history](durable-history.md).
