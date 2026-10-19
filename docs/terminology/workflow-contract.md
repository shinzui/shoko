---
type: "Term"
title: "workflow contract"
description: "The explicit agreement describing a staging workflow's target, requirements, evidence, prerequisites, access, and cleanup or retention."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-49"
status: "current"
tags:
  - "staging"
scope: "Shoko"
related:
  - "TERM-46"
  - "TERM-29"
  - "TERM-12"
anchors:
  - kind: "file"
    resource: "schemas/workflow-v1.schema.json"
---

# workflow contract

The explicit agreement describing a staging workflow's target, requirements, evidence, prerequisites, access, and cleanup or retention.

The v1 manifest ties business requirements to scenario/expectation pairs and scoped sources, including precise negative requirements. Offline validation checks structure and declarations. Acceptance still needs approved concrete inputs, live readiness, and actual workflow evidence; the checked-in synthetic example is not an accepted contract.

See the [implementation or guide](../../schemas/workflow-v1.schema.json).

Related: [target identity](target-identity.md), [negative scenario](negative-scenario.md), [coverage](coverage.md).
