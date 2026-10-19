---
type: "Term"
title: "correlation"
description: "The rule that attributes observed evidence to the business activity being verified."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-11"
status: "current"
tags:
  - "evidence"
scope: "Shoko"
related:
  - "TERM-6"
  - "TERM-24"
  - "TERM-3"
anchors:
  - kind: "file"
    resource: "shoko-core/src/Shoko/Correlation.hs"
---

# correlation

The rule that attributes observed evidence to the business activity being verified.

Shoko selects a business key or explicitly supported propagated execution ID. A baseline alone cannot establish attribution. Missing or malformed correlation must leave evidence unavailable rather than broaden a query to unrelated activity.

See the [implementation or guide](../../shoko-core/src/Shoko/Correlation.hs).

Related: [business key](business-key.md), [execution ID](execution-id.md), [baseline](baseline.md).
