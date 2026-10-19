---
type: "Term"
title: "business key"
description: "A non-secret domain identifier shared by the actions and evidence reads for a workflow."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-6"
status: "current"
tags:
  - "evidence"
scope: "Shoko"
related:
  - "TERM-11"
  - "TERM-24"
anchors:
  - kind: "file"
    resource: "shoko-core/src/Shoko/Correlation.hs"
---

# business key

A non-secret domain identifier shared by the actions and evidence reads for a workflow.

For example, a registration ID can scope event and state queries. A correlation plan may use a fixed input or select a named action's returned text identity. If that runtime identity is missing, observations remain unavailable; they must not fall back to an unscoped read.

See the [implementation or guide](../../shoko-core/src/Shoko/Correlation.hs).

Related: [correlation](correlation.md), [execution ID](execution-id.md).
