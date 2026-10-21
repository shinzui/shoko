---
type: "Capability"
title: "Bounded durable event evidence"
description: "Read correlated Kiroku or Message DB events in finite stream or category scopes without advancing application checkpoints."
generated:
  by: "anthropic/claude-opus-5-5"
  at: "2026-10-21T22:40:00Z"
capabilityId: "CAP-7"
provider: "mori://shinzui/shoko"
status: "shipped"
stability: "experimental"
since: "unreleased"
packages:
  - "shoko-adapters"
interface:
  - "Shoko.Adapter.EventStore"
  - "Shoko.Adapter.Kiroku"
  - "Shoko.Adapter.MessageDb"
evidence:
  - kind: "conformance"
    resource: "shoko-adapters/test/EventStore/Contract.hs"
    proves: "Shared core-runner contracts, policy gating, correlation, coverage, and checkpoint preservation across both stores."
  - kind: "test"
    resource: "scripts/test-event-stores"
    proves: "Bounded real-store fixtures, explicit backend selection, and unchanged application checkpoints."
---

# Bounded durable event evidence

A finite event query fixes its stream or category, event type, correlation strategy, decoding, and page/request limits. A fresh reader captures existing scoped occurrence IDs before actions and repeatedly scans the bounded scope in read-only repeatable-read transactions. Stable source-scoped occurrence identities avoid double counting across polls and preserve late lower-position commits.

Both backends provide business-key correlation from a payload field. Kiroku also supports exact UUID execution metadata; Message DB does not advertise exact execution-ID correlation. Handler construction rejects a Kafka topic scope with `UnsupportedEventScope` and record-key or header correlation with `UnsupportedCorrelationSource` before any reader is allocated. Raw event payloads and transport diagnostics are excluded from public evidence.

## Limits

Complete history requires the source owner's `AppendOnlyDuringRun` promise, enough finite scan capacity, and an unambiguous closing read. Deletion, truncation, exhausted bounds, disappearing IDs, and ambiguous late matches prevent complete coverage. The cursor is run-owned state, not a replay token. Readers do not subscribe, publish, or advance consumer checkpoints.

## Use and evidence

See [durable event readers](../adapters.md) and [the store fixture driver](../../scripts/test-event-stores).
