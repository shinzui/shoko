---
type: "Term"
title: "policy"
description: "The configured permissions and finite timing rules under which a scenario may execute."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-34"
status: "current"
tags:
  - "execution"
scope: "Shoko"
related:
  - "TERM-7"
  - "TERM-23"
  - "TERM-8"
  - "TERM-35"
anchors:
  - kind: "doc"
    resource: "docs/scenario-hosts.md"
---

# policy

The configured permissions and finite timing rules under which a scenario may execute.

Environment grants govern allowed effects. The `Policy` record supplies execution budget, eventual window, poll interval, and cleanup grace. Configuration can choose these limits, but operational environment variables and named options cannot enlarge the YAML capability grant set.

See the [implementation or guide](../../docs/scenario-hosts.md).

Related: [capability](capability.md), [execution budget](execution-budget.md), [cleanup grace](cleanup-grace.md), [preflight](preflight.md).
