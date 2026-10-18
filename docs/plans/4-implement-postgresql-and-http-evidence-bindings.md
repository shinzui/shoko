---
id: 4
slug: implement-postgresql-and-http-evidence-bindings
title: "Implement PostgreSQL and HTTP evidence bindings"
kind: exec-plan
created_at: 2026-10-02T03:52:02Z
intention: "intention_01m3xdacr3exqajqfcgh9btgev"
master_plan: "docs/masterplans/1-bootstrap-shoko-for-evidence-based-workflow-parity.md"
provenance:
  created_by:
    model: "gpt-6-astra"
    harness: "codex-cli"
    at: 2026-10-02T03:52:02Z
  revisions:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-02T04:18:41Z
      mode: "update"
      note: "Associate the bootstrap plan with the shared Mina intention requested by the user."
  reviews:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-18T17:14:48Z
      verdict: "approved"
      note: "Planning review after MVP update: dependencies, ownership, references, and observable acceptance checked; build and live staging proof remain implementation gates."
---

# Implement PostgreSQL and HTTP evidence bindings


This ExecPlan is a living document. Keep observable acceptance and the adapter contracts current; update durable decisions in `docs/adr/`.

## Purpose / Big Picture


A consumer can execute an HTTP action and verify its domain consequences in PostgreSQL or a REST read endpoint, without depending on the target service's implementation language. Unreachable sources produce structured Unknown results and all queries stay scoped to the selected business identity.

## Progress


- [ ] M1: Generic PostgreSQL existence, count, value, and absence observations work with typed parameters and truthful coverage.
- [ ] M2: HTTP actions and reads share core deadlines, correlation, policy, and sanitized evidence.
- [ ] M3: A real local HTTP-to-PostgreSQL roundtrip exercises the public runner, including Fail and Unknown controls.

## Surprises & Discoveries


## Decision Log


On 2026-10-01, implement a generic SQL/HTTP binding layer instead of adding TAN-specific dependencies. This is RES-1 M3's complete baseline for non-Haskell legacy services. HTTP mutation is never retried automatically merely because evidence is slow.

## Outcomes & Retrospective


## Context and Orientation


The hard prerequisite `docs/plans/3-implement-inspectable-scenarios-and-the-bounded-verification-runner.md` supplies typed operation descriptions, `resolveScenario`, `runScenario`, deadline handling, correlation, and evidence coverage. The workspace already has Nix/process-compose/PostgreSQL from its own foundation prerequisite. This plan creates the `shoko-adapters` package and its first real IO handlers.

[RES-1](../research/initial-specification-requirement-validation.md) S2, S5, M3, and M5 require business-key-scoped PostgreSQL reads, HTTP/REST access, and thin legacy support. [ADR 0001](../adr/0001-use-jitsurei-standards-and-the-seihou-haskell-flake.md) supplies Haskell/build rules; [ADR 0002](../adr/0002-keep-scenarios-inspectable-and-bindings-explicit.md) supplies policy/correlation; [ADR 0003](../adr/0003-record-bounded-evidence-and-three-valued-results.md) supplies verdicts/coverage. In particular, a successful empty query differs from a failed query, and mutable snapshots cannot establish continuous absence.

Use [Hasql](mori://hasql/hasql) for typed PostgreSQL parameters/results and [http-client](mori://snoyberg/http-client) for HTTP. Hasql's local `Hasql.Session.statement` and Message DB's statement-based interface were inspected; versions may differ from the research survey. Resolve documentation and source with Mori, verify current releases and tags before setting bounds, and update `docs/dependencies.md`. Do not guess a connection-pool or timeout API from an older version.

## Plan of Work


### M1 — Query generic SQL facts safely and honestly


Create `shoko-adapters/shoko-adapters.cabal`, `shoko-adapters/src/Shoko/Adapter/Postgres.hs`, `Postgres/Query.hs`, and `Postgres/Evidence.hs`. Add the package to `cabal.project`, Nix outputs, and Mori metadata through the established extension points. Follow GHC2024/common stanza, strict unprefixed records, explicit deriving strategies, local generic-lens imports, and multiline SQL conventions from Jitsurei.

Define validated SQL identifiers separately from bound data values. Provide `rowExists`, `rowCount`, `columnValue`, and `rowAbsent` descriptors over explicit schema/table/column names and a small typed predicate vocabulary (equality and conjunction are sufficient for bootstrap). Render identifiers with correct quoting and reject invalid names; use Hasql parameter encoders for values, never string-concatenate them into SQL. No user-supplied SQL fragments or mutable statement API is needed. A caller maps a domain observation to one descriptor and supplies decoding for its result. `columnValue` must distinguish absent row, one null value, one non-null value, and multiple rows; do not silently choose the first row.

Run observations with a read-only role/transaction and an execution deadline bounded by the runner's remaining budget. Record a redacted query description, binding/source identity, business key, timestamps, row counts, and coverage. Return typed connection, permission, query, and decode failures as unavailable evidence, not empty results. PostgreSQL polling over a mutable table advertises sampled state; a binding can assert stronger coverage only with a documented durable source such as an append-only ledger. Do not turn `rowCount == 1` into exactly-once event delivery.

### M2 — Issue bounded HTTP actions and observations


Create `Shoko.Adapter.Http`, `Http.Request`, and `Http.Evidence` in the adapter package. A binding supplies a base URL, named endpoint, method, typed input encoding/response decoding, declared capabilities, and redaction rules. Policy resolution includes `SendHttp` and any mutation/external-side-effect capability; reads do not bypass endpoint allowlists. Use a managed HTTP client resource, bounded response sizes, remaining-budget request timeouts, and explicit response classification. Disable automatic redirects for mutating actions or validate each redirected destination against the same policy before following it; do not leak credentials across origins.

Supply `x-shoko-execution-id` as a run label only when the binding's endpoint contract supports it; it never establishes downstream correlation by itself. Preserve/inject valid W3C trace context when supplied by the host, using a verified library API or a clearly scoped existing header value, without adding a trace-query backend. Business-key extraction is typed binding logic, not an assumption about a universal response field. A service's `minPosition` read floor is an optional binding-specific argument, not a mandatory core protocol.

Classify responses against each declared operation contract. A documented rejection expected by a negative scenario becomes a typed domain outcome with sanitized evidence, available to its expectations. An unexpected domain rejection is a failed action. An unexpected success must fail the negative expectation. Network/decoding problems that prevent knowing the outcome are Unknown; an arbitrary 4xx/5xx or timeout never counts as expected rejection. Do not rerun mutating requests automatically. Observation retries remain under the core polling scheduler. Store method, sanitized route/status, timing, selected identifiers, and approved response evidence. Exclude authorization headers, connection passwords, OTP codes, and unrestricted personal payloads from reports.

### M3 — Prove an actual producer/consumer path


Create a small local test service under `shoko-adapters/test/Fixture/` that handles an HTTP command and commits a business-keyed row to a disposable PostgreSQL schema. It is explicitly a Shōko adapter fixture, not a TAN service. Add `postgres-adapter-test`, `http-adapter-test`, and `adapter-roundtrip-test` Cabal suites, managed by `scripts/test-adapters` and `just test-adapters`. The script provisions only run-owned data, starts the fixture server, waits for readiness, executes the suites, and cleans up its resources even on failure.

First prove HTTP action -> persisted row -> core eventually -> JSON evidence before expanding descriptor variants. Then cover count/value/absence, response errors, timeouts, row decoding errors, and missing correlation. The success case must use the actual Hasql and HTTP client implementations, not an in-memory substitute.

## Concrete Steps


Run at the repository root after core is Complete:

```bash
mori registry show hasql/hasql --full
mori registry docs hasql/hasql
mori registry show snoyberg/http-client --full
mori registry docs snoyberg/http-client
nix develop --command cabal build shoko-adapters
nix develop --command just test-adapters
nix develop --command just check
```

`test-adapters` is a new recipe delivered here; it owns database/server setup rather than requiring undocumented background processes. It exits zero only after real IO tests run. Report explicitly whether integration fixtures ran; no implicit pass on missing PostgreSQL.

## Validation and Acceptance


A controlled HTTP action creates exactly the expected business-keyed row and eventually passes. An action returning success while withholding the expected row yields Fail after conclusive reads. Disconnecting PostgreSQL or stopping the HTTP source yields Unknown with the source and reason. Parameter values containing quotes remain data, invalid identifiers are rejected, and a query with another business key cannot satisfy the expectation. Test null versus absent and multiple rows for `columnValue`. A read-only credential cannot mutate data. Slow requests respect remaining deadlines, timeouts do not resend mutations, and rejected policy produces no network traffic. Test a documented invalid-input response through a real HTTP fixture and prove the negative scenario Pass; substitute unexpected success, a different rejection code, and connection loss to prove Fail, Fail, and Unknown respectively. Inspect results for secret redaction. A mutable-row absence check cannot claim complete interval coverage.

The real staging consumer uses configured approved remote endpoints and read-only evidence credentials; local fixture scripts remain for adapter validation only. Staging access is established by `docs/plans/2-establish-the-first-workflow-contract-and-composed-local-environments.md`. Preserve endpoint allowlists, authenticated transport, query scoping, response limits, and remaining-budget timeouts through that access route. Never disable certificate validation to make staging work or silently fall back to a different target.

## Idempotence and Recovery


Tests allocate run-owned databases/schemas and loopback ports; terminate only their fixture processes. Retain sanitized failure artifacts before cleanup. Repeating tests uses fresh business keys. No command points at a production/staging database by default. Test scripts refuse remote or unmarked reset targets. If the chosen Hasql release conflicts with an event-store dependency, solve the package set in the build manifest and prove the exact consumed API; do not fork the core evidence type or apply blanket bounds overrides.

## Interfaces and Dependencies


Hard dependency: all of `docs/plans/3-implement-inspectable-scenarios-and-the-bounded-verification-runner.md`. Soft dependency: `docs/plans/2-establish-the-first-workflow-contract-and-composed-local-environments.md` M1 for actual schema/endpoints. This plan owns the adapter package manifest and SQL/HTTP modules, binding constructors, fixture scripts, and `test-adapters` recipe. Event-store work extends that package without changing these generic interfaces. The core remains the owner of result, policy, clock, coverage, and correlation types; adapters only construct them. The CLI plan can consume these modules when available, but its core-only acceptance does not depend on them.

Revision 2026-10-01: distinguish expected domain rejection from action failure and transport uncertainty; exercise those cases through real adapter IO and retain approved remote staging access.
