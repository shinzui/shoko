---
type: "Term"
title: "preflight"
description: "Validation that rejects an invalid definition, policy, binding, or target before scenario resources are acquired."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
termId: "TERM-35"
status: "current"
tags:
  - "execution"
scope: "Shoko"
related:
  - "TERM-5"
  - "TERM-43"
  - "TERM-46"
  - "TERM-47"
anchors:
  - kind: "doc"
    resource: "docs/scenario-hosts.md"
---

# preflight

Validation that rejects an invalid definition, policy, binding, or target before scenario resources are acquired.

Core resolution is pure. CLI `check` also avoids credential-value lookup and live metadata callbacks. Live `run` separately resolves credential references, invokes host metadata preflight, and resolves the credential-backed binding before acquisition. A preflight failure is distinct from an assertion failing on business behavior.

See the [implementation or guide](../../docs/scenario-hosts.md).

Related: [binding contract](binding-contract.md), [scenario host](scenario-host.md), [target identity](target-identity.md), [verdict](verdict.md).
