---
type: "Term"
title: "binding"
description: "The implementation-specific handlers and contracts that give a scenario's operations their runtime meaning."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-4"
status: "current"
tags:
  - "execution"
scope: "Shoko"
related:
  - "TERM-5"
  - "TERM-17"
  - "TERM-35"
  - "TERM-42"
anchors:
  - kind: "file"
    resource: "shoko-core/src/Shoko/Binding.hs"
---

# binding

The implementation-specific handlers and contracts that give a scenario's operations their runtime meaning.

A binding supplies pure operation metadata and scoped acquisition, release, baseline, action, and observation handlers. The same scenario can use different bindings. An environment provides policy; a binding supplies behavior. This is trusted Haskell code and must describe its complete operation inventory.

See the [implementation or guide](../../shoko-core/src/Shoko/Binding.hs).

Related: [binding contract](binding-contract.md), [environment](environment.md), [preflight](preflight.md), [scenario](scenario.md).
