---
type: "Term"
title: "action"
description: "A scenario operation that may change the system and declares which domain outcomes are acceptable."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-1"
status: "current"
tags:
  - "authoring"
scope: "Shoko"
related:
  - "TERM-15"
  - "TERM-29"
  - "TERM-10"
  - "TERM-31"
anchors:
  - kind: "file"
    resource: "shoko-core/src/Shoko/Action.hs"
---

# action

A scenario operation that may change the system and declares which domain outcomes are acceptable.

An `act` step wraps an operation with an explicit accepted outcome-tag set. A documented rejection can be acceptable in a negative scenario. An unexpected domain tag is a mismatch; a transport timeout leaves the result uncertain and does not trigger an automatic mutation retry.

See the [implementation or guide](../../shoko-core/src/Shoko/Action.hs).

Related: [domain outcome](domain-outcome.md), [negative scenario](negative-scenario.md), [composite action](composite-action.md), [observation](observation.md).
