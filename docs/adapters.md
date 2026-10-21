# SQL, HTTP, durable event, and Kafka topic adapters

`shoko-adapters` supplies ready-made handlers and IO helpers for context-owned bindings. It
does not define business operations or infer domain outcomes from status codes.
See the compiling consumer in `shoko-adapters/test/AdapterTests.hs` for the full
inspection → resolution → HTTP command → SQL/REST observation → result path.

PostgreSQL queries use validated `identifier` values, a qualified `Table`, a
mandatory `Scope (BusinessKeyName "accountId") column` naming the selected business key and its text column, and an
optional typed predicate. `equals` supports text, bigint, and Boolean parameters;
`andAlso` combines them. `rowExists`, `rowAbsent`, `rowCount`, and `columnValue`
construct descriptors without IO. There is no raw SQL fragment or unscoped query
constructor. Values containing quotes remain binary parameters. A scope/key-name
mismatch or missing correlation fails before opening a connection.

`postgresObservation (SourceId "accounts.sql") query` packages a sampled source,
read contract, the semantic key from `queryScope`, and `observeQuery`.
`postgresSource` exposes the sampled source separately. For example,
`focus snd (postgresObservation (SourceId "accounts.sql") query)` projects its
capture and observation into the second component of a resource pair.

`columnValue` returns `NoRows`, `NullValue`, `OneValue a`, or `MultipleRows`.
It reads at most two rows and verifies the PostgreSQL column type before
decoding. Supported types are exactly PostgreSQL text, bigint, and Boolean;
schema mismatches are unavailable evidence. Hasql 1.10 validates column OIDs
before decoding. Nullable and absent values remain
different even when a predicate matches nothing.

`postgres` holds a connection string without rendering instances. `runQuery`
opens a connection per sample, starts a read-only transaction, installs a
remaining-budget `statement_timeout`, runs the parameterized statement, and
closes the connection on completion, error, or cancellation. Use a read-only
database role as well. Connection, permission, query, decode, correlation, and
deadline failures have typed categories; raw Hasql errors (which can contain
parameters and credentials) are discarded. `observeQuery` attaches a safe query
shape and counts/flags, never arbitrary column values. It advertises sampled
state: `rowAbsent` can support an eventually sampled absence assertion, but
cannot establish continuous absence or exactly-once delivery.

HTTP `endpoint` declarations fix the URL, method, response-byte limit, additional
capabilities, optional execution-label support, and optional business-key query
parameter. `httpConfig` rejects duplicate names; dispatch selects only from that
allowlist. `httpActionHandler` and `httpObservationHandler` own their contracts,
sources, and callbacks. Their contracts contribute `SendHttp`, `ReadState` or
`WriteState`, and the explicitly declared additional capabilities to preflight. The host
must add `ExternalSideEffect` for an endpoint with that behavior. Environment
names alone do not approve destinations.

`newHttp` uses verified TLS settings, disables automatic connection retries, and
keeps zero idle connections; response scopes close sockets. Requests reject
header line breaks, disable redirects and ambient proxy routing at both manager
and request levels, enforce the
remaining deadline, and stop after the response limit. Authorization and body
bytes live only in the non-renderable `HttpPayload`. Evidence contains the
endpoint name, method, and status. URLs, request/response bodies, authorization,
trace headers, and exception strings are excluded. Native `http-client` records
have no `Generic` instance, so the adapter uses their public selectors and
record-update API in this transport boundary.

`httpAction` requires an explicit status/body decoder producing a typed value
and domain tag. `httpActionHandler config endpoint payloadBuilder decoder` packages
that decoder with the same allowlisted descriptor used for policy. Only an exact documented rejection should receive its rejection
tag. Unexpected tags fail the core action contract; transport or decoding
uncertainty yields Unknown. A timeout never retries a mutation. `httpObservation`
requires GET plus a declared business-key query parameter and injects the
selected key using URL encoding. There is no broad-read fallback. `httpObservationHandler` rejects non-GET or unscoped descriptors during pure
construction. Payload builders return `IO (Either HttpPayloadError HttpPayload)`;
`PayloadInputError` retains typed input-resolution failures and `InvalidPayload`
represents invalid construction. Both read helpers advertise sampled coverage and
require their endpoint's `BusinessKeyName`. A validated W3C version-00 `traceparent` may be supplied.
HTTP handler wrappers populate `runLabel` from `executionId context` when the
scenario declares propagation and reject a conflicting explicit label. The header
is sent only to an opted-in endpoint. The independent transport check verifies
both matching IDs and disabled endpoints; this does not prove durable propagation.
Before transport IO, handlers compare acquired endpoint method, target, limits,
capabilities, propagation, and scope with the declared descriptor. Mismatches are
unavailable evidence.

Run the actual local IO checks from the workspace root:

```bash
nix develop --command just test-adapters
```

The script creates an isolated Unix-only PostgreSQL cluster and loopback HTTP
server, grants a read-only test role, runs all three suites, checks mutation
counts, and tears down its own resources. Missing PostgreSQL is an error.
`just check` includes these suites, and the Nix adapter derivation runs the same
fixture against its compiled test binaries. These are verifier fixtures; they
neither exercise nor certify the deployed registration system.

## Durable event readers

`Shoko.Adapter.Kiroku` consumes the released Kiroku 0.11 SQL API without
starting a store publisher or subscription. `Shoko.Adapter.MessageDb` calls
Message DB 1.3.0's public read functions through a thin read-only SQL bridge.
Both return `EventEvidence a`: the decoded context value, source position,
source timestamp, and optional causation ID. Occurrence IDs are scoped by the
public source identity. Positions and timestamps also enter explicit safe report
details, alongside scope kind, event/correlation filter, page limits, and scanned
position bounds. The unique public source name identifies the fixed scope; raw
payloads and transport diagnostics have no rendering path.

Describe a finite source query with `Shoko.Adapter.EventStore`:

```haskell
description :: Either Text (EventQuery Bool)
description = do
  scope <- categoryScope "deliveries"
  bounded <- limits 64 16 2000
  eventQuery bounded scope AppendOnlyDuringRun
    (BusinessKeyField (BusinessKeyName "deliveryId")) "Delivered" (const (Right True))
```

`limits` supplies page size, page count, and the maximum request time in
milliseconds. `streamScope` selects one named stream; `categoryScope` selects
one category, never `$all`. Event type and correlation are checked before the
context decoder runs. `BusinessKeyField` requires that logical key and a
nonempty selected value; missing/malformed correlation remains unavailable.
Kiroku additionally supports exact UUID execution metadata within the declared
scope. Its unbounded store-wide correlation helper is deliberately not used.
Message DB requires business-key correlation: its server correlation option
matches a category, so it cannot establish an exact execution ID. The bridge
never enables `sql_condition`.

`kirokuObservation (SourceId "deliveries.events") query` and
`messageDbObservation` return `Either HandlerBuildError (Handler ...)`: a handler
owning the durable source and its correlation requirement, or a typed cause.
Both reject a Kafka `TopicScope` with `UnsupportedEventScope` and record-key or
header correlation with `UnsupportedCorrelationSource`; Message DB also rejects
execution correlation with `ExecutionMetadataUnsupported`. Preserve these causes in
binding lookup with `Just <$> kirokuObservation source query`; unsupported
vocabulary patterns use `Right Nothing`. Construction performs no reader
allocation, and the `kiroku`/`messageDb` constructors refuse the same queries.

Create a fresh reader per finite run using the same query value and a distinct
`SourceId` for each reader/scope/decoder. Use `focus` when it belongs inside a
larger context resource. The handler checks its source ID, query limits, scope,
history policy, correlation mode, and event type against the allocated reader
before capture or observation IO. Decoder functions cannot be compared: reusing
the same query for acquisition and handler construction remains the caller's
obligation. The compiling example is
[`EventStore/Contract.hs`](../shoko-adapters/test/EventStore/Contract.hs).

Kiroku accepts credential text, a validated schema name, the public source ID,
and query. Message DB fixes the server schema to `message_store`. Resources
contain no persistent connections; each bounded read owns a connection and a
repeatable-read, read-only transaction with a server timeout. Credentials remain
separate from the public source name. No application checkpoints are advanced.

The baseline captures the exact set of existing scoped occurrence IDs before
actions. Every poll re-scans that bounded scope in one database snapshot and
deduplicates by source event identity. This preserves late lower-position
commits without assuming a global sequence is commit order. The cursor token is
opaque run-owned state; it is not a replay token. Exhausted page limits prevent
complete coverage; a truncated baseline fails before actions. Choose a narrower
scope or a deliberate larger finite limit when an existing history is too big.

Complete history requires `AppendOnlyDuringRun`: the source owner must exclude
deletion, truncation, and rewriting for the entire finite run, including retention
jobs. `UnverifiedHistory` supplies witnesses but cannot establish absence or
accepted exactly-once cardinality. Previously seen IDs disappearing also make
coverage incomplete. The staging contract requires an explicit
`historyPolicy: append-only-during-run` on durable sources; declarations still
need owner-backed readiness evidence.

Host cutoffs and stored event timestamps are independent clocks. A matching
occurrence first seen after the host cutoff is ambiguous: it is excluded from
the finite count and makes coverage incomplete. An event already seen before
the cutoff stays countable on overlapping reads. A complete closing scan with
no ambiguous matches, begun at or after the cutoff, can establish the window.
A read overlapping the cutoff reports only its conservative request-start lower
bound; core obtains a fresh closing snapshot while execution time remains.
Busy sources can therefore
honestly yield Unknown at a boundary. Durable `eventually` also needs a closing
history read before declaring a missing event Fail; its closing read uses only
remaining execution time, while a late positive cannot become Pass.

Run both actual stores or an explicit subset:

```bash
nix develop --command just test-event-stores
nix develop --command just test-event-store kiroku
nix develop --command just test-event-store message-db
```

The fixture script verifies vendored source hashes, applies pinned upstream
migrations/functions, separates writer/reader roles, and prints store revisions.
It compares application checkpoint rows before and after the shared suite and
stops only its owned Unix-only PostgreSQL cluster. Both-store acceptance requires
the default command; a single-store pass names only that store. Native Nix adapter
checks run these same fixtures against compiled binaries.

## Kafka topic reader

`Shoko.Adapter.Kafka` reads one Kafka topic as a third durable event source. It
uses the same `EventQuery` and `EventEvidence` vocabulary, with a topic scope and
a correlation source taken from the record key, a named header, or a payload
field:

```haskell
query :: Either Text (EventQuery RegistrationCompleted)
query = do
  bounded <- limits 100 10 1000
  scope <- topicScope "registration.completed.v1"
  eventQuery bounded scope AppendOnlyDuringRun
    (BusinessKeyRecordKey (BusinessKeyName "registrationId"))
    "RegistrationCompleted" decode
```

`topicScope` accepts 1 to 249 ASCII letters, digits, `.`, `_`, or `-`, and
rejects `.`, `..`, and broker-internal names starting with `__`.
`BusinessKeyHeader (BusinessKeyName "registrationId") "registration-id"` reads a
named header instead. Kafka permits duplicate headers; the last occurrence wins,
both for the configured header and for the `event-type` header that supplies the
event type. Only records of the declared type are correlated. A missing or
non-UTF-8 key or header, or a missing payload field, on such a record makes the
observation unavailable; it never broadens the query. Record values are parsed
as JSON only for correlated candidates. Execution-ID correlation is unsupported:
`kafkaObservation` returns `Left ExecutionMetadataUnsupported`, and a stream or
category scope returns `Left (UnsupportedEventScope ...)`.

`kafkaSettings servers properties` validates a comma-separated `host:port` list
without scheme or credentials and accepts only `security.protocol`, `sasl.*`,
and `ssl.*` client properties. Group, commit, end-of-partition, isolation, and
topic-creation settings belong to the observer and are rejected.
`KafkaSettings` has no rendering instance.

Semantics:

- The baseline records, per partition, the read-committed end offset (the last
  stable offset). Membership starts there: a transaction already open at capture
  becomes evidence when it commits during the run. Producer timestamps never
  decide membership.
- Every poll re-reads each partition from its baseline offset to its end with a
  fresh client per partition, under one deadline for the whole read. Only an
  observed end of every baseline partition establishes a complete scan;
  `limits pageSize pages budget` caps each partition at `pageSize * pages`
  records, and at most 64 partitions are supported.
- A low watermark past a baseline offset (retention or deletion), a read-committed
  end below one already observed, or a change of the partition set is history
  loss. Loss is sticky for the run: later reads cannot clear it, and coverage
  stays incomplete. Compaction cannot be detected; `AppendOnlyDuringRun` is the
  topic owner's promise that neither retention nor compaction removes records
  during the run.
- `EventEvidence.position` is the partition offset and `causation` is `Nothing`.
  Occurrence IDs are `<source>:<partition>/<offset>`.
- Public details add `partition-count`, per-partition
  `partition-<p>-baseline-offset` and `partition-<p>-end-offset`,
  `records-scanned`, `records-without-event-type`, `records-per-partition-limit`,
  `partitions-stable`, and `low-watermark-intact`. The correlation filter names
  only the source kind and business key, never the configured header name.
  Topic names, keys, headers, values, broker addresses, and client error text
  are never rendered.

The reader never joins a consumer group, commits offsets, or creates topics.
Read-only enforcement for a staging observer is a broker ACL contract owned by the
environment.

Status: the scan logic, handler, and descriptors are complete and tested through
the public runner against a controlled read-committed topic model. The
client-backed `kafka` constructor waits for the `hw-kafka-client` fork release
tracked by
[IR-2](mori://shinzui/hw-kafka-client/okf/improvement-requests/concepts/IR-2) and
[plan 10](plans/10-implement-the-kafka-topic-evidence-adapter.md); until then
hosts cannot allocate a Kafka reader.

```bash
nix develop --command just test-kafka
```

`scripts/test-kafka` boots an owned single-node Apache Kafka broker on loopback,
seeds an inactive `application-worker` group with a committed offset, runs the
Kafka suite, and fails if any `shoko-observer-` group appears, any topic outside
the `fixture-` prefix changes, or the application's committed offsets move. It
stops only its own broker process. Native Nix adapter checks run the same script.

Revision 2026-10-19: replace separate contract/baseline wiring with handler
constructors, typed source/business-key names, effectful payload builders, descriptor
consistency checks, and scenario-owned execution-ID transport.
