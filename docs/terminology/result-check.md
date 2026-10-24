---
type: "Term"
title: "result check"
description: "A source-free expectation that evaluates a named predicate once over typed values from earlier scenario steps or constants."
generated:
  by: "openai/gpt-6.1-sol"
  at: "2026-10-24T03:35:12Z"
termId: "TERM-51"
status: "current"
tags:
  - "evidence"
scope: "Shoko"
anchors:
  - kind: "file"
    resource: "shoko-core/src/Shoko/Expectation.hs"
---

# result check

A source-free expectation that evaluates a named predicate once over typed values from earlier scenario steps or constants.

`holds` checks applicatively combined inputs; `agreeOn` compares a labelled projection of at least two references. All checks activate after the actions. Their public evidence contains ordered dependency IDs and nullable completion time, never compared values.

See the [core guide](../core.md#idempotency-scenarios).
