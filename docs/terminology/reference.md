---
type: "Term"
title: "reference"
description: "An opaque typed handle to the result of an earlier named fixture or action."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-37"
status: "current"
tags:
  - "authoring"
scope: "Shoko"
aliases:
  - "Ref"
related:
  - "TERM-27"
  - "TERM-26"
  - "TERM-1"
anchors:
  - kind: "file"
    resource: "shoko-core/src/Shoko/Internal/Reference.hs"
---

# reference

An opaque typed handle to the result of an earlier named fixture or action.

A reference declares a dependency without reading the runtime value while the scenario is being built. Later handlers resolve it through checked lookups. A missing dependency is a definition error; use the reference to form an input rather than extracting its value during construction.

See the [implementation or guide](../../shoko-core/src/Shoko/Internal/Reference.hs).

Related: [input](input.md), [fixture](fixture.md), [action](action.md).
