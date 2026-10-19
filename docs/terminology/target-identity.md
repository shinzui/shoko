---
type: "Term"
title: "target identity"
description: "The observed identity of the deployment a host is about to verify."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-46"
status: "current"
tags:
  - "staging"
scope: "Shoko"
related:
  - "TERM-43"
  - "TERM-49"
  - "TERM-35"
anchors:
  - kind: "doc"
    resource: "docs/workflows/first-staging-workflow.md"
---

# target identity

The observed identity of the deployment a host is about to verify.

The core record names a target, namespace UID, and deployment revision; the host supplies and validates it. Configured target fields are expectations, not observations. The repository's Kubernetes identity check compares namespace/workload identities and template references twice; this does not establish runtime image identity or full readiness.

See the [implementation or guide](../../docs/workflows/first-staging-workflow.md).

Related: [scenario host](scenario-host.md), [workflow contract](workflow-contract.md), [preflight](preflight.md).
