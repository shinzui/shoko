---
type: "Term"
title: "domain outcome"
description: "The typed result of an action, labelled with a public tag that the scenario can accept or reject."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-15"
status: "current"
tags:
  - "results"
scope: "Shoko"
related:
  - "TERM-1"
  - "TERM-29"
  - "TERM-47"
anchors:
  - kind: "file"
    resource: "shoko-core/src/Shoko/Action.hs"
---

# domain outcome

The typed result of an action, labelled with a public tag that the scenario can accept or reject.

A documented invalid-input rejection is an ordinary value, not a transport failure. Only the precise expected rejection receives its accepted tag. An unavailable service or undecodable response remains uncertainty and cannot be relabelled as a successful negative case.

See the [implementation or guide](../../shoko-core/src/Shoko/Action.hs).

Related: [action](action.md), [negative scenario](negative-scenario.md), [verdict](verdict.md).
