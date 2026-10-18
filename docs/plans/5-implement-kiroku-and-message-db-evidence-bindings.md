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
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-18T17:14:48Z
      mode: "update"
      note: "Accept selected event readers independently before first MVP use."
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-10-18T20:42:12Z
      mode: "implement"
      note: "Implement real-store readers under the eligible-adapter fallback while staging inputs are pending."
  reviews:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-18T17:14:48Z
      verdict: "approved"
      note: "Planning review after MVP update: dependencies, ownership, references, and observable acceptance checked; build and live staging proof remain implementation gates."
---

# Implement Kiroku and Message DB evidence bindings


This ExecPlan is a living document. Keep evidence-source semantics and accepted version selections current.

## Purpose / Big Picture


A consumer can verify durable events from Kiroku and from legacy Message DB using one store-neutral expectation model. Repeated polling never counts one event twice, unrelated executions never satisfy the check, and observer reads do not change application acknowledgements or checkpoints.

Both readers remain full-bootstrap deliverables. First registration MVP acceptance depends only on a reader selected by `integration/workflow.json` and its actual contract tests. M1 and M2 are independent after the common prerequisites; M2 does not require M1. Complete the selected reader and its M3 checks before staging, then finish the unused reader after MVP acceptance. An HTTP/PostgreSQL-only workflow has no hard dependency on this plan, provided its declared assertions do not require event history.

## Progress


- [x] M1 (2026-10-18): The released Kiroku 0.11 reader passes the actual append -> read -> public runner cardinality path, with bounded stream/category pages, exact business-key/UUID filtering, and scoped occurrence IDs. All 18 Kiroku shared contract groups pass locally.
- [x] M2 (2026-10-18): The thin Message DB 1.3.0 public-function bridge passes all 18 shared contract groups locally, enforces decoded business keys, and rejects unsupported execution-ID mode. The actual server version is checked.
- [x] M3 (2026-10-18): Both real stores pass all 18 shared contract groups, including repeated pages, missing/duplicate occurrence handling, bounded coverage, ambiguity at cutoffs, source failures, actual blocked-read cancellation/connection release, delayed commits, and unchanged checkpoints. The complete workspace check and native Nix adapter fixture both pass.

## Surprises & Discoveries


Released `mori://shinzui/kiroku/packages/kiroku-store` 0.11.0.0 requires Hasql
1.10, so the previously accepted 1.9 selection could not be retained. The
coherent released family is pinned in `cabal.project`, its freeze, and the
unmanaged Nix module; SQL/HTTP must be revalidated. No generated toolchain pin,
source patch, or bounds waiver is used. Dependency evidence is in
`docs/dependencies.md`.

The 0.2.0.0 tag of `mori://tan/message-db-hs/packages/message-db-hs` is not
published on Hackage. Its public `hasql-migration` 0.3.1 dependency constructs
Hasql's removed `Statement` constructor, so it is incompatible with this Kiroku
family. The local migration fork has newer APIs but is not the released source.
Use this plan's allowed thin bridge, verified against the actual Message DB
1.3.0 public server functions, rather than adding unpublished dependencies.

A global position is not a safe universal committed prefix. The Message DB test
holds a lower-position write uncommitted in the selected category while another
category commits a higher position. A baseline and later observation still find
the delayed event. Both adapters therefore re-scan the finite scope in a single
repeatable-read snapshot and exclude baseline IDs. Page exhaustion remains
incomplete; no observer checkpoint is advanced.

The real core consumer exposed two closing-read boundaries. Durable `eventually`
misses need a closing read, and a response finishing after the cutoff may contain
a snapshot taken before it. Adapters report visibility only through a conservative
request-start lower bound. If a read crosses the cutoff, core obtains one actual
closing snapshot while execution time remains. Matching events first seen after
the cutoff are ambiguous and cannot produce accepted cardinality. Source UTC
and host monotonic clocks are never compared.

Kiroku supports retention/hard deletion, so complete history requires an explicit
source-owner append-only guarantee over the finite run. `UnverifiedHistory`
permits witnesses without complete negative coverage. The workflow schema now
requires the owner's `append-only-during-run` policy for durable sources. No
retention job, store lease, application writer, or staging setting is managed by
the observer.

## Decision Log


On 2026-10-01, implement both event readers behind the core evidence contract in one adapter package. Prefer Kiroku as the target substrate while keeping Message DB's legacy path disposable. Do not build observer subscriptions or causality operators in this bootstrap.

## Outcomes & Retrospective


Complete on 2026-10-18. Both actual stores pass 18 shared contract groups each
in Cabal and native Nix fixtures, with pinned upstream schema/functions, isolated
writer/reader credentials, transaction visibility, exact correlation, repeated
pages, cardinality, honest cutoff coverage, cancellation/connection release,
and unchanged application checkpoints. The full
`nix develop --command just check` passes: 40 core tests, 15 existing SQL/HTTP
checks, 36 event-store checks, 43 CLI invocations, eight workflow-contract
groups, seven result examples, and all seven native Nix checks. Existing result
goldens remain unchanged. Mori metadata type-checks and changed Markdown
links/fences validate.

The released package set is coherent without generated-pin changes or bounds
waivers. The observer deliberately favors finite re-scans and honest Unknown
results over an unsafe position/time shortcut. Durable source policy and the
core closing-read lessons are distilled into ADR 0001/0003 and the public guides.
No staging access, application deployment change, Keiro execution-ID propagation,
or registration acceptance is established by these verifier fixtures. Resume
EP-2 with its actual owner inputs before EP-7; both generic reader prerequisites
are now available whichever source that workflow selects.

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

Expose `just test-event-store kiroku` and `just test-event-store message-db` as explicit single-store selectors over the same shared suite. Each fails if its selected store was not exercised and prints that store's identity and covered checks. EP-7 may depend on an accepted M1 plus all Kiroku M3 checks, or M2 plus all Message DB M3 checks. Keep M3 and this child unfinished until the default two-store suite succeeds; a single-store pass must never be labelled two-store acceptance. Do not add an unused store dependency to the MVP build manifest ahead of its implementation merely to create an empty module.

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

When implementing only the reader required by the MVP, run the applicable explicit selector first:

```bash
nix develop --command just test-event-store message-db
# Or, when Kiroku is selected by the accepted manifest:
nix develop --command just test-event-store kiroku
```

These are alternative commands chosen from the manifest, not permission to omit a required reader. Both readers remain necessary to finish this child.

## Validation and Acceptance


Both adapters must drive the real public core runner. One matching event in a closed complete window passes exactlyOnce; the same ID returned twice still passes; two distinct matching IDs fail; a missing event with complete coverage fails eventually; an unavailable database produces Unknown. Unrelated business keys and metadata absent from the declared strategy never satisfy a query. An event written during the action before the first observation is still found. A delayed commit cannot be silently skipped while the adapter claims a complete window. A second independent reader sees the same evidence and application checkpoints remain unchanged.

This acceptance does not prove remote Keiro execution-id propagation. Record that separately only after a real Keiro command/process-manager chain produces and retrieves durable correlation evidence. No PGMQ acknowledgement, Kafka subscription management, or service process-manager handler belongs here.

Revision 2026-10-18: make the two reader milestones independently acceptable with explicit per-store shared checks; preserve both-store completion while removing unused adapters from the first registration MVP gate.

## Idempotence and Recovery


Use unique databases/streams and isolated fixture roles; keep migrations and fixture writes separate from read-only binding credentials. Reset only fixture-owned stores. Missing libraries/migrations are a setup failure, not a skipped passing test. Preserve evidence gaps in results. If pagination or transaction semantics invalidate interval coverage, return Unknown and revise the adapter/ADR instead of weakening the test.

## Interfaces and Dependencies


Pure contract helpers take the public source name and query, so policy and CLI
inspection require no reader allocation or credentials. Readers are created in
`Binding.acquire`; the compiled consumer proves denied policy leaves allocation
at zero.

The implemented public modules are `Shoko.Adapter.EventStore`,
`Shoko.Adapter.Kiroku` / `.Evidence`, and `Shoko.Adapter.MessageDb` / `.Evidence`.
`eventQuery` takes finite limits, a named stream/category, explicit history policy,
correlation mode, event type, and a typed payload decoder. Each fresh reader owns
one run's opaque baseline token and ID sets. A unique public source name identifies
that scope/decoder; credentials have no rendering instances. `EventEvidence a`
retains position, UTC timestamp, optional causation ID, and the decoded context
value. See `docs/adapters.md` and the compiling consumer in
`shoko-adapters/test/EventStore/Contract.hs` for the actual Binding integration.

Kiroku uses its released bounded SQL read/append API. Its unbounded store-wide
`findByCorrelation` helper cannot preserve the finite scoped query contract, so
exact typed UUID metadata is filtered within the paged selected scope instead.
Pinned migration SQL is installed verbatim only into disposable owned databases;
`shoko-adapters/test/EventStore/Fixture/sources.json` records canonical projects, revisions,
project-relative paths, licenses, and hashes. The native adapter derivation runs
the same two-store fixture script against built binaries.

Hard dependencies: Complete `docs/plans/3-implement-inspectable-scenarios-and-the-bounded-verification-runner.md`, plus M1 of `docs/plans/4-implement-postgresql-and-http-evidence-bindings.md`, whose accepted output is the adapter package and working PostgreSQL observation infrastructure. The latter plan may remain In Progress while HTTP work continues. Soft dependency: M1 of `docs/plans/2-establish-the-first-workflow-contract-and-composed-local-environments.md` for real vocabulary and key mappings. This plan owns event-store modules/tests and extends the existing adapter package manifest in coordination with its SQL/HTTP owner. Core owns the evidence/result types. The final staging host owns domain mapping; generic store readers must not import registration-specific event types.
