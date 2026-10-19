---
type: "Term"
title: "vocabulary"
description: "The context-owned set of typed operations from which scenarios are written."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-48"
status: "current"
tags:
  - "authoring"
scope: "Shoko"
related:
  - "TERM-33"
  - "TERM-42"
  - "TERM-7"
anchors:
  - kind: "file"
    resource: "shoko-core/src/Shoko/Action.hs"
---

# vocabulary

The context-owned set of typed operations from which scenarios are written.

The vocabulary gives operations public identities and declares their capabilities, reference dependencies, and composite substeps. Business meanings belong to the application context; Shoko supplies the construction and execution machinery. Reusable composition of separate vocabularies is still planned.

See the [implementation or guide](../../shoko-core/src/Shoko/Action.hs).

Related: [operation](operation.md), [scenario](scenario.md), [capability](capability.md).
