---
type: "Term"
title: "execution ID"
description: "A run identity propagated through the target system and used to select that run's evidence."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-24"
status: "current"
tags:
  - "evidence"
scope: "Shoko"
related:
  - "TERM-11"
  - "TERM-6"
  - "TERM-39"
anchors:
  - kind: "doc"
    resource: "docs/adapters.md"
---

# execution ID

A run identity propagated through the target system and used to select that run's evidence.

A binding must explicitly support this correlation strategy. Kiroku can select exact UUID execution metadata within a declared scope; Message DB's bridge does not claim exact execution-ID support. Assigning a report run ID or sending an HTTP run label does not prove downstream propagation.

See the [implementation or guide](../../docs/adapters.md).

Related: [correlation](correlation.md), [business key](business-key.md), [run ID](run-id.md).
