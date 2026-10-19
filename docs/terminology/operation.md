---
type: "Term"
title: "operation"
description: "A typed request that a binding handles as a fixture, action, or observation."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-33"
status: "current"
tags:
  - "authoring"
scope: "Shoko"
related:
  - "TERM-26"
  - "TERM-1"
  - "TERM-31"
  - "TERM-5"
anchors:
  - kind: "file"
    resource: "shoko-core/src/Shoko/Action.hs"
---

# operation

A typed request that a binding handles as a fixture, action, or observation.

Its result type is retained by the application's operation datatype. Its public description declares an identifier, requirements, dependencies, and any substeps. The binding checks the role as well as the operation; an observation handler is not interchangeable with an action handler.

See the [implementation or guide](../../shoko-core/src/Shoko/Action.hs).

Related: [fixture](fixture.md), [action](action.md), [observation](observation.md), [binding contract](binding-contract.md).
