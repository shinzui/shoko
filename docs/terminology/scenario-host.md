---
type: "Term"
title: "scenario host"
description: "A compiled application that registers domain scenarios and bindings and exposes them through Shoko's CLI."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-43"
status: "current"
tags:
  - "hosting"
scope: "Shoko"
related:
  - "TERM-38"
  - "TERM-4"
  - "TERM-46"
anchors:
  - kind: "doc"
    resource: "docs/scenario-hosts.md"
---

# scenario host

A compiled application that registers domain scenarios and bindings and exposes them through Shoko's CLI.

A context owner supplies the vocabulary, registry entries, binding factories, safe inputs, and live metadata callback, then calls `runShokoCli`. The generic executable hosts labelled demos. Hosts compile normally; they do not load or compile arbitrary Haskell scenarios at runtime.

See the [implementation or guide](../../docs/scenario-hosts.md).

Related: [registry](registry.md), [binding](binding.md), [target identity](target-identity.md).
