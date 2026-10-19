---
type: "Term"
title: "binding contract"
description: "The pure declaration of a handler's capability and cleanup requirements."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-5"
status: "current"
tags:
  - "execution"
scope: "Shoko"
related:
  - "TERM-4"
  - "TERM-7"
  - "TERM-35"
  - "TERM-12"
anchors:
  - kind: "file"
    resource: "shoko-core/src/Shoko/Binding.hs"
---

# binding contract

The pure declaration of a handler's capability and cleanup requirements.

Resolution looks up a handler for each operation and role before acquisition. Each handler owns its contract; observation handlers separately own their source, coverage strength, and correlation requirement. Contracts expose requirements for inspection and policy checks; they do not acquire resources or prove that the remote target is ready.

See the [implementation or guide](../../shoko-core/src/Shoko/Binding.hs).

Related: [binding](binding.md), [capability](capability.md), [preflight](preflight.md), [coverage](coverage.md).
