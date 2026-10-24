---
type: "Term"
title: "idempotency key"
description: "A caller-supplied identity used to recognize repeated submissions of the same logical operation."
generated:
  by: "openai/gpt-6.1-sol"
  at: "2026-10-24T03:35:12Z"
termId: "TERM-50"
status: "current"
tags:
  - "authoring"
scope: "Shoko"
anchors:
  - kind: "file"
    resource: "docs/core.md"
---

# idempotency key

A caller-supplied identity used to recognize repeated submissions of the same logical operation.

A context binding defines replay and changed-payload rejection semantics. Test response agreement separately from durable effect cardinality; sequential retries alone do not expose check-then-insert races.

See the [core guide](../core.md#idempotency-scenarios).
