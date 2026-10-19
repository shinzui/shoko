---
type: "Capability"
title: "Scoped PostgreSQL evidence"
description: "Observe business-key-scoped PostgreSQL state through typed parameterized queries and read-only transactions bounded by the remaining run budget."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
capabilityId: "CAP-5"
provider: "mori://shinzui/shoko"
status: "shipped"
stability: "experimental"
since: "unreleased"
packages:
  - "shoko-adapters"
interface:
  - "Shoko.Adapter.Postgres"
  - "Shoko.Adapter.Postgres.Query"
  - "Shoko.Adapter.Postgres.Evidence"
evidence:
  - kind: "test"
    resource: "shoko-adapters/test/AdapterTests.hs"
    proves: "Real PostgreSQL scoping, type, null, timeout, and unavailable-evidence behavior."
  - kind: "example"
    resource: "shoko-adapters/test/AdapterTests.hs"
    proves: "Scoped SQL observations used through a core binding."
---

# Scoped PostgreSQL evidence

Consumers construct row existence, absence, count, and scalar-column queries using validated identifiers, a mandatory business-key scope, and typed predicates. Values remain parameters. Scalar reads distinguish no rows, SQL null, one value, and multiple rows and check column types before decoding.

Each sample owns a read-only transaction with a server statement timeout and connection cleanup. Safe evidence exposes query shape and counts or flags.

## Limits

Supported scalar types are PostgreSQL text, bigint, and Boolean. There is no public raw SQL or unscoped query constructor. These observations provide sampled state; a missing row cannot establish continuous absence or exactly-once delivery. Database credentials and read-only role provisioning belong to the host.

## Use and evidence

See the [adapter guide](../adapters.md).
