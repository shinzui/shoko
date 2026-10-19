---
type: "Term"
title: "scenario"
description: "A named, revisioned description of a workflow and its expected observable consequences."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-42"
status: "current"
tags:
  - "authoring"
scope: "Shoko"
related:
  - "TERM-48"
  - "TERM-4"
  - "TERM-25"
  - "TERM-44"
anchors:
  - kind: "file"
    resource: "shoko-core/src/Shoko/Scenario.hs"
---

# scenario

A named, revisioned description of a workflow and its expected observable consequences.

A scenario declares fixtures and actions in a fixed order and expectations that activate after the final action. Reusable builders can declare deferred checks with `expectAfterActions` before later actions, while strict `expect` prevents later actions. The same description can be resolved against different implementation bindings. Its structure is inspectable before any operation runs.

See the [implementation or guide](../../shoko-core/src/Shoko/Scenario.hs).

Related: [vocabulary](vocabulary.md), [binding](binding.md), [expectation](expectation.md), [scenario revision](scenario-revision.md).
