---
type: "Term"
title: "concurrent group"
description: "A declared nonempty set of independent actions admitted together as one stage in a fixed scenario."
generated:
  by: "openai/gpt-6.1-sol"
  at: "2026-10-24T03:35:13Z"
termId: "TERM-52"
status: "current"
tags:
  - "authoring"
scope: "Shoko"
anchors:
  - kind: "file"
    resource: "shoko-core/src/Shoko/Scenario.hs"
---

# concurrent group

A declared nonempty set of independent actions admitted together as one stage in a fixed scenario.

`concurrently` rejects member dependencies, fixtures, expectations, correlations and nested groups. Each handler explicitly promises safe concurrent calls. Admitted siblings settle after ordinary failure; later stages stop, and external cancellation joins the group before cleanup. The start gate guarantees no remote ordering or handler overlap.

See the [core guide](../core.md#idempotency-scenarios).
