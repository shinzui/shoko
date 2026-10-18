# SQL and HTTP adapters

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
schema mismatches are unavailable evidence. Hasql 1.9's byte decoders alone do
not establish column-type compatibility. Nullable and absent values remain
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
