---
type: "Capability"
title: "Allowlisted HTTP operations"
description: "Perform declared HTTP actions and business-key-scoped GET observations with explicit domain decoding, finite limits, and safe evidence."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
capabilityId: "CAP-6"
provider: "mori://shinzui/shoko"
status: "shipped"
stability: "experimental"
since: "unreleased"
packages:
  - "shoko-adapters"
interface:
  - "Shoko.Adapter.Http"
  - "Shoko.Adapter.Http.Request"
  - "Shoko.Adapter.Http.Evidence"
evidence:
  - kind: "test"
    resource: "shoko-adapters/test/AdapterTests.hs"
    proves: "Loopback HTTP limits, request scoping, transport boundaries, and typed outcomes."
  - kind: "example"
    resource: "shoko-adapters/test/AdapterTests.hs"
    proves: "HTTP commands followed by SQL and REST observations."
---

# Allowlisted HTTP operations

Endpoint declarations fix destinations, methods, response size bounds, and additional capabilities. Actions use an explicit decoder to distinguish documented domain outcomes from transport or decode uncertainty. Read observations require GET and a declared business-key query parameter.

The transport verifies TLS, disables redirects, ambient proxies, and automatic connection retries, and enforces remaining deadlines and response bounds. Evidence retains endpoint names, methods, and statuses rather than bodies or credentials.

## Limits

Observation coverage is sampled state. The binding contract supports business-key correlation; an optional execution header is only a run label. Authors must declare external effects and classify domain rejections precisely. Timed-out mutations are not retried.

## Use and evidence

See [HTTP binding guidance](../adapters.md).
