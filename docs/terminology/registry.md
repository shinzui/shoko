---
type: "Term"
title: "registry"
description: "The scenario host's inventory of supported environment names and compiled scenario entries."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-38"
status: "current"
tags:
  - "hosting"
scope: "Shoko"
related:
  - "TERM-43"
  - "TERM-4"
  - "TERM-35"
anchors:
  - kind: "file"
    resource: "shoko-cli/src/Shoko/Cli/Registry.hs"
---

# registry

The scenario host's inventory of supported environment names and compiled scenario entries.

Each entry packages a typed scenario with its own correlation declarations, logical-input summary, named binding factories, and metadata callback. This is the local `Shoko.Cli.Registry`, distinct from the external Mori project registry. Binding factories remain pure so inspection can describe them without credentials or resource IO.

See the [implementation or guide](../../shoko-cli/src/Shoko/Cli/Registry.hs).

Related: [scenario host](scenario-host.md), [binding](binding.md), [preflight](preflight.md).
