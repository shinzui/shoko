---
id: 5
slug: implement-kiroku-and-message-db-evidence-bindings
title: "Implement Kiroku and Message DB evidence bindings"
kind: exec-plan
created_at: 2026-10-02T03:52:03Z
intention: "intention_01m3xdacr3exqajqfcgh9btgev"
master_plan: "docs/masterplans/1-bootstrap-shoko-for-evidence-based-workflow-parity.md"
provenance:
  created_by:
    model: "gpt-6-astra"
    harness: "codex-cli"
    at: 2026-10-02T03:52:03Z
  revisions:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-02T04:18:41Z
      mode: "update"
      note: "Associate the bootstrap plan with the shared Mina intention requested by the user."
---

# Implement Kiroku and Message DB evidence bindings


This ExecPlan is a living document. Keep evidence-source semantics and accepted version selections current.

## Purpose / Big Picture


A consumer can verify durable events from Kiroku and from legacy Message DB using one store-neutral expectation model. Repeated polling never counts one event twice, unrelated executions never satisfy the check, and observer reads do not change application acknowledgements or checkpoints.

## Progress


- [ ] M1: A bounded Kiroku reader returns correlated occurrence evidence and demonstrates an actual store-write/read/runner roundtrip.
- [ ] M2: A thin Message DB reader returns business-key-scoped occurrence evidence without treating its category filter as an exact execution selector.
- [ ] M3: Both readers pass shared coverage, pagination, cardinality, outage, and non-interference acceptance.

## Surprises & Discoveries


## Decision Log


On 2026-10-01, implement both event readers behind the core evidence contract in one adapter package. Prefer Kiroku as the target substrate while keeping Message DB's legacy path disposable. Do not build observer subscriptions or causality operators in this bootstrap.

## Outcomes & Retrospective


## Context and Orientation


The core plan supplies `OccurrenceId`, correlation strategy, coverage, deadlines, and the typed binding API. `docs/plans/4-implement-postgresql-and-http-evidence-bindings.md` creates the adapter package; only its M1 (package plus accepted PostgreSQL observations) is a hard prerequisite, not its HTTP work. Both prerequisites are named again below. The foundation provides PostgreSQL tooling, but application/database migrations are distinct from evidence-reader permissions.

[RES-1](../research/initial-specification-requirement-validation.md) library findings and M2–M5 motivate this work. [ADR 0003](../adr/0003-record-bounded-evidence-and-three-valued-results.md) requires durable occurrence identity and complete interval coverage; [ADR 0004](../adr/0004-gate-parity-on-real-workflows-and-context-owned-vocabulary.md) keeps legacy support thin and runtime changes upstream. [ADR 0001](../adr/0001-use-jitsurei-standards-and-the-seihou-haskell-flake.md) supplies mandatory Haskell conventions.

[Kiroku](mori://shinzui/kiroku) exposes stream/category reads and `findByCorrelation`; the inspected modules are project-relative `kiroku-store/src/Kiroku/Store/Read.hs`, `Causation.hs`, and `Types.hs` (artifact-level URIs pending; resolve the canonical project first). [message-db-hs](mori://tan/message-db-hs) exposes `MessageDb.Db.Statements.getCategoryMessages` with `GetCategoryMessagesQuery`. Its `correlation` selector is category-oriented; it is not an exact execution-ID predicate. Inspect [Message DB](mori://message-db/message-db) documentation before relying on server semantics. Do not enable the server's arbitrary `sql_condition` facility for bootstrap.

[Keiro IR-52](mori://shinzui/keiro/okf/improvement-requests/concepts/IR-52) was proposed when this plan was created. Writing correlated Kiroku fixture events proves the adapter, not Keiro propagation. Use explicit business-key strategies for real systems until that propagation is demonstrated. Recheck releases and upstream tags before selecting package bounds; corpus versions are not authoritative release selections.

## Plan of Work


### M1 — Read Kiroku occurrence evidence


Create `shoko-adapters/src/Shoko/Adapter/Kiroku.hs` and `Kiroku/Evidence.hs`. A binding declares category/stream scope, event decoder, event-type mapping, correlation strategy, and stable occurrence identity projection. Capture a source cursor/baseline before the triggering action, read bounded pages through the core deadline, and return complete/gapped coverage accurately. Use exact typed correlation lookup when supported and populated. For business-key mode, select documented streams or filter decoded payload keys within a bounded source scope. Missing metadata must not trigger an unbounded fallback.

Use source event IDs scoped by store/binding identity for deduplication, retaining source positions and timestamps. Preserve causation metadata when present for diagnosis, but do not implement a `causes` verdict or infer it from positions. Be explicit about global-position commit order: validate whether the selected store's cursor API guarantees no late lower-position commits. If it does not, use overlapping rereads/deduplication or a documented stable boundary, and return incomplete coverage whenever the requested finite window cannot be closed soundly. A high position by itself is not proof of complete committed history.

Build a Kiroku test store using its actual migration/append API from the selected released dependency and run one append -> evidence read -> exactlyOnce scenario before expanding filters. Keep fixture writes under separate setup credentials/capabilities; the adapter's production interface is read-only.

### M2 — Read legacy Message DB evidence


Create `Shoko.Adapter.MessageDb` and `MessageDb.Evidence`. Prefer known stream names/business-key mappings. If category scanning is needed, retrieve bounded batches, filter the decoded business key client-side, and record scanned bounds and filters. A server-side category correlation selector may reduce the candidate set but cannot establish exact key matching. Keep observer position in runner-owned memory for this finite run; never advance a service subscription checkpoint or delete/acknowledge its queue messages.

Use `MessageDb.Db.Statements` from the selected compatible release where possible. If release compatibility conflicts with Kiroku/Hasql, document the actual constraint and select a coherent supported set. A minimal read-only SQL bridge to documented Message DB functions is an acceptable bounded fallback only after recording the reason and testing those exact server functions; do not silently pin a stale stack or loosen all bounds. Use the same coverage/commit-order discipline as Kiroku.

### M3 — Exercise both actual stores under one contract


Add `event-store-adapter-test` and shared contract tests under `shoko-adapters/test/EventStore/`, plus `scripts/test-event-stores` and `just test-event-stores`. The script initializes disposable local Kiroku and Message DB databases using verified migrations from their pinned sources, records versions, starts the fixture writers, runs the suite, and stops only run-owned resources. It must fail with prerequisites if either real store was not exercised.

Test empty complete scans, two different business keys, repeated batches, pagination, events appearing during polling, pre-action baselines, concurrent transaction visibility, and unavailable/undecodable sources. Prove a duplicate ID is counted once and two event IDs are counted twice. Snapshot checkpoint rows/counts before and after observation to demonstrate no application consumer state changed. Keep fixture data synthetic.

## Concrete Steps


Run from the Shōko repository root once core and SQL M1 are accepted:

```bash
mori registry show shinzui/kiroku --full
mori registry docs shinzui/kiroku
mori registry show tan/message-db-hs --full
mori registry docs tan/message-db-hs
mori registry docs message-db/message-db
mori path mori://shinzui/keiro/okf/improvement-requests/concepts/IR-52
nix develop --command just test-event-stores
nix develop --command just check
```

The new `test-event-stores` recipe must print the actual two store versions and successful contract groups, including read-only/non-interference checks. Record only concise acceptance evidence in this plan.

## Validation and Acceptance


Both adapters must drive the real public core runner. One matching event in a closed complete window passes exactlyOnce; the same ID returned twice still passes; two distinct matching IDs fail; a missing event with complete coverage fails eventually; an unavailable database produces Unknown. Unrelated business keys and metadata absent from the declared strategy never satisfy a query. An event written during the action before the first observation is still found. A delayed commit cannot be silently skipped while the adapter claims a complete window. A second independent reader sees the same evidence and application checkpoints remain unchanged.

This acceptance does not prove remote Keiro execution-id propagation. Record that separately only after a real Keiro command/process-manager chain produces and retrieves durable correlation evidence. No PGMQ acknowledgement, Kafka subscription management, or service process-manager handler belongs here.

## Idempotence and Recovery


Use unique databases/streams and isolated fixture roles; keep migrations and fixture writes separate from read-only binding credentials. Reset only fixture-owned stores. Missing libraries/migrations are a setup failure, not a skipped passing test. Preserve evidence gaps in results. If pagination or transaction semantics invalidate interval coverage, return Unknown and revise the adapter/ADR instead of weakening the test.

## Interfaces and Dependencies


Hard dependencies: Complete `docs/plans/3-implement-inspectable-scenarios-and-the-bounded-verification-runner.md`, plus M1 of `docs/plans/4-implement-postgresql-and-http-evidence-bindings.md`, whose accepted output is the adapter package and working PostgreSQL observation infrastructure. The latter plan may remain In Progress while HTTP work continues. Soft dependency: M1 of `docs/plans/2-establish-the-first-workflow-contract-and-composed-local-environments.md` for real vocabulary and key mappings. This plan owns event-store modules/tests and extends the existing adapter package manifest in coordination with its SQL/HTTP owner. Core owns the evidence/result types. The final parity host owns domain mapping; generic store readers must not import registration-specific event types.
