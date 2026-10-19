---
type: "Term"
title: "fixture"
description: "A scenario step that establishes a declared precondition before the workflow actions."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-26"
status: "current"
tags:
  - "authoring"
scope: "Shoko"
related:
  - "TERM-37"
  - "TERM-45"
  - "TERM-14"
anchors:
  - kind: "file"
    resource: "shoko-core/src/Shoko/Scenario.hs"
---

# fixture

A scenario step that establishes a declared precondition before the workflow actions.

A `given` step returns a typed reference, just as an action does, but resolves through the fixture role. It may allocate a synthetic resource and therefore still needs declared permission, per-run consent, and a cleanup or retention contract.

See the [implementation or guide](../../shoko-core/src/Shoko/Scenario.hs).

Related: [reference](reference.md), [synthetic consent](synthetic-consent.md), [disposition](disposition.md).
