---
type: "Term"
title: "synthetic consent"
description: "Explicit per-run permission to perform operations requiring synthetic-resource creation or use."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-45"
status: "current"
tags:
  - "execution"
scope: "Shoko"
related:
  - "TERM-26"
  - "TERM-7"
  - "TERM-14"
anchors:
  - kind: "doc"
    resource: "docs/scenario-hosts.md"
---

# synthetic consent

Explicit per-run permission to perform operations requiring synthetic-resource creation or use.

The environment must grant `SyntheticResource` and the run must also opt in. CLI consent comes from `--allow-synthetic`; YAML or ambient environment variables cannot provide it. The permission does not invent a safe fixture or cleanup method: the binding still supplies both.

See the [implementation or guide](../../docs/scenario-hosts.md).

Related: [fixture](fixture.md), [capability](capability.md), [disposition](disposition.md).
