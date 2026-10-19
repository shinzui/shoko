---
type: "Term"
title: "capability"
description: "A declared permission category required by an operation or resource lifecycle and granted by an environment."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-7"
status: "current"
tags:
  - "execution"
scope: "Shoko"
related:
  - "TERM-34"
  - "TERM-5"
  - "TERM-45"
anchors:
  - kind: "file"
    resource: "shoko-core/src/Shoko/Environment.hs"
---

# capability

A declared permission category required by an operation or resource lifecycle and granted by an environment.

The runtime categories are `ReadState`, `ReadEvents`, `WriteState`, `SendHttp`, `ExternalSideEffect`, and `SyntheticResource`. Required permissions must fit within environment grants, including substeps and cleanup. This local runtime meaning differs from a CAP-N catalog record, which describes something Shoko provides to a consumer.

See the [implementation or guide](../../shoko-core/src/Shoko/Environment.hs).

Related: [policy](policy.md), [binding contract](binding-contract.md), [synthetic consent](synthetic-consent.md).
