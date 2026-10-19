---
type: "Term"
title: "environment"
description: "The named target policy that declares permitted capabilities and finite execution limits."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-17"
status: "current"
tags:
  - "execution"
scope: "Shoko"
related:
  - "TERM-4"
  - "TERM-34"
  - "TERM-46"
anchors:
  - kind: "file"
    resource: "shoko-core/src/Shoko/Environment.hs"
---

# environment

The named target policy that declares permitted capabilities and finite execution limits.

An environment also marks whether the target is production; the current runner rejects production execution. Its name does not authorize endpoints or discover deployment identity. Select a binding separately to choose the concrete operation handlers.

See the [implementation or guide](../../shoko-core/src/Shoko/Environment.hs).

Related: [binding](binding.md), [policy](policy.md), [target identity](target-identity.md).
