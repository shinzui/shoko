---
type: "Term"
title: "scenario revision"
description: "The author-controlled version of a scenario's predicates and recipe meaning."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-44"
status: "current"
tags:
  - "results"
scope: "Shoko"
related:
  - "TERM-42"
  - "TERM-13"
  - "TERM-28"
anchors:
  - kind: "file"
    resource: "shoko-core/src/Shoko/Scenario.hs"
---

# scenario revision

The author-controlled version of a scenario's predicates and recipe meaning.

A revision must change when the scenario's meaning changes, including changes that inspection cannot infer from predicate functions. It is separate from the logical recipe revision, binary build identity, and report schema version. A description digest does not replace that author responsibility.

See the [implementation or guide](../../shoko-core/src/Shoko/Scenario.hs).

Related: [scenario](scenario.md), [description digest](description-digest.md), [logical input](logical-input.md).
