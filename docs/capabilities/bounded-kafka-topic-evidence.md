---
type: "Capability"
title: "Bounded Kafka topic evidence"
description: "Read finite, correlated Kafka topic histories without joining consumer groups, committing offsets, or creating topics."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-10-24T00:19:26Z"
capabilityId: "CAP-13"
provider: "mori://shinzui/shoko"
status: "shipped"
stability: "experimental"
since: "unreleased"
packages:
  - "shoko-adapters"
interface:
  - "Shoko.Adapter.Kafka"
  - "Shoko.Adapter.Kafka.Evidence"
  - "Shoko.Adapter.EventStore"
evidence:
  - kind: "conformance"
    resource: "shoko-adapters/test/Kafka/Broker.hs"
    proves: "Public-runner correlation, cardinality, finite coverage, transactional visibility, deadline release, partition changes, and real truncation."
  - kind: "conformance"
    resource: "shoko-adapters/test/Kafka/Contract.hs"
    proves: "Controlled cutoff, sticky history-loss, descriptor, and policy contracts through the shared event scanner."
  - kind: "test"
    resource: "shoko-adapters/test/Kafka/Spike.hs"
    proves: "Released-client assign-only reading, attributed EOF, ordered duplicate headers, committed-visible offsets, and synchronous teardown."
  - kind: "test"
    resource: "scripts/test-kafka"
    proves: "Owned Kafka broker, unchanged application offsets, no observer groups or unexpected topics, and private stderr."
---

# Bounded Kafka topic evidence

A topic query fixes its event type, business-key source, decoder, history policy,
and finite scan limits. `kafka` allocates run-local state without broker IO;
`kafkaObservation` contributes `ReadEvents` and the selected business-key requirement
to policy resolution before baseline capture or actions.

Membership begins at each partition's committed-visible end at baseline capture.
A transaction already open then can become evidence after committing during the
run. Every observation rereads each baseline partition to an attributed EOF.
Repeated reads preserve occurrence identities as `<source>:<partition>/<offset>`.
Record keys, the last matching header, or a payload field provide correlation.
The observer assigns partitions manually and synchronously destroys each client;
it never subscribes, commits offsets, or creates a topic.

## Limits

At most 64 partitions are supported. `limits pageSize pages budgetMillis` caps
records per partition at `pageSize * pages` and shares one deadline across all
metadata, watermark, assignment, and polling operations of a scan. Reaching a
record limit or timing out cannot prove the partition ended.

Complete history requires the topic owner's `AppendOnlyDuringRun` promise,
complete partition scans, intact observed watermarks and partition membership,
and an unambiguous closing read. Observed deletion or end regression stays sticky
even if the same scan later fails. Compaction cannot be detected: the owner must
exclude both retention and compaction during the finite run. `UnverifiedHistory`
provides witnesses but cannot prove absence or accepted exactly-once cardinality.
Producer timestamps never decide membership or host cutoff eligibility.

Execution-ID correlation, continuous observation, replay, publishing, destructive
consumption, and Redpanda compatibility are not provided. Staging read-only access
is a broker ACL contract, not a claim established by the unauthenticated fixture.
Hosts supply the topic, security settings, and decoder and must link executables
with `-threaded`. Credentials, record contents, header names, and bootstrap
addresses have no public rendering path.

## Use and evidence

See the [Kafka reader guide](../adapters.md#kafka-topic-reader). Run
`nix develop --command just test-kafka` for the owned real-broker contracts.
