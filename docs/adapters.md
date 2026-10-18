# SQL, HTTP, and durable event adapters

`shoko-adapters` supplies IO helpers for context-owned `Binding` handlers. It
does not define business operations or infer domain outcomes from status codes.
See the compiling consumer in `shoko-adapters/test/AdapterTests.hs` for the full
inspection → resolution → HTTP command → SQL/REST observation → result path.

PostgreSQL queries use validated `identifier` values, a qualified `Table`, a
mandatory `Scope` naming the selected business key and its text column, and an
optional typed predicate. `equals` supports text, bigint, and Boolean parameters;
`andAlso` combines them. `rowExists`, `rowAbsent`, `rowCount`, and `columnValue`
construct descriptors without IO. There is no raw SQL fragment or unscoped query
constructor. Values containing quotes remain binary parameters. A scope/key-name
mismatch or missing correlation fails before opening a connection.

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
allowlist. `httpContract` contributes `SendHttp`, mutation's `WriteState`, and
the explicitly declared additional capabilities to core preflight. The host
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
and domain tag. Only an exact documented rejection should receive its rejection
tag. Unexpected tags fail the core action contract; transport or decoding
uncertainty yields Unknown. A timeout never retries a mutation. `httpObservation`
requires GET plus a declared business-key query parameter and injects the
selected key using URL encoding. There is no broad-read fallback. Both helpers
advertise sampled coverage. Binding metadata currently supports business-key
correlation only. A validated W3C version-00 `traceparent` may be supplied.
The optional `runLabel` sends `x-shoko-execution-id` only to an endpoint that
explicitly supports it; this label does not prove downstream propagation.

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
    (BusinessKeyField "deliveryId") "Delivered" (const (Right True))
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

The contract helpers take only the public source name and query: Kiroku returns
a pure `BindingContract`, while Message DB returns `Nothing` for unsupported
execution correlation. Resolve those contracts before IO; allocate readers in
`Binding.acquire`. The compiled consumer verifies denied policy performs zero
reader allocations.

Create one fresh reader per finite run, with a distinct public source identity
for each scope/decoder. Wire its contract, baseline, and observation functions
into the context's `Binding`; the compiling example is
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
