---
id: 10
slug: implement-the-kafka-topic-evidence-adapter
title: "Implement the Kafka topic evidence adapter"
kind: exec-plan
created_at: 2026-10-21T16:49:39Z
intention: "intention_01m5fnhddpehctvk1xwd9m4r9m"
provenance:
  created_by:
    model: "claude-fable-5-1"
    harness: "claude-code"
    at: 2026-10-21T16:49:39Z
  revisions:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-21T17:17:48Z
      mode: "update"
      note: "Validate released Kafka client APIs; record dependency blockers and correct EOF, visibility, lifecycle, and milestone guidance"
    - model: "claude-opus-5-5"
      harness: "claude-code"
      at: 2026-10-21T22:09:29Z
      mode: "implement"
      note: "Record the fork decision and IR-2 blocker; implement client-independent work"
    - model: "claude-fable-5-1"
      harness: "claude-code"
      at: 2026-10-22T03:50:32Z
      mode: "update"
      note: "Replace the hw-kafka-client fork with the released rdkafka-hs 1.0.0.0 pin, name its observer API, and unblock the client-dependent milestones"
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-10-23T22:32:33Z
      mode: "implement"
      note: "Bind the released Kafka client and verify broker-backed observer contracts"
  reviews:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-21T17:19:57Z
      verdict: "changes-requested"
      note: "Released 5.3.0 rejects empty subscriptions and lacks deterministic public teardown; M1 must resolve client selection before M2. EOF, visibility, fixture, and milestone defects corrected."
---

# Implement the Kafka topic evidence adapter

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Shōko verifies distributed behavior by running a scenario's actions against a real system and
then checking evidence from several sources: HTTP responses, PostgreSQL rows, and durable
event histories in Kiroku or Message DB. The TAN platform carries its integration events
between bounded contexts over Apache Kafka, and the Keiro rewrite keeps Kafka as the
integration transport. Today a scenario cannot assert anything about those events: there is
no Kafka evidence reader, so a requirement such as "completing a registration publishes
exactly one `RegistrationCompleted` integration event for this registration" has no source.

After this plan, `shoko-adapters` provides `Shoko.Adapter.Kafka`, a bounded, read-only Kafka
topic reader that fits the existing durable-event model. A context binding describes a
finite topic query with the same `eventQuery` function used for Kiroku and Message DB, selects
the correlation value from the record key, a header, or a payload field, and the public core
runner evaluates `eventually`, `never`, and `exactlyOnce` over the records produced during the
run. For Kafka, membership starts at the baseline's committed-visible boundary: a transaction
already open at capture can become evidence when it commits during the run. Producer timestamps
do not establish membership. The reader never joins an application's consumer group, never commits offsets, never
creates topics, and advertises honest coverage: complete history only when the topic owner
has promised append-only retention for the run, every partition was read to its end, and no
retention deletion or ambiguous late record was observed.

A reader can see it working by running, from the repository root:

```bash
nix develop --command just test-kafka
```

That command starts an owned single-node Apache Kafka broker on loopback, runs the shared
Kafka contract suite through the public runner, proves that no observer consumer group or
topic was created and that an application group's committed offsets are unchanged, and stops
the broker. `just check` and the native Nix adapter check include the same fixture.


## Progress

- [ ] M1 — Toolchain and broker fixture accepted: librdkafka and `c2hs` are in the
  Seihou-managed dev shell, `rdkafka-hs` 1.0.0.1 is pinned by commit in `cabal.project` and
  `flake.module.nix`, `scripts/test-kafka` boots an owned KRaft broker, and the spike checks
  prove assign-only reading without subscription, partition-attributed EOF, watermark
  offsets, header/key/timestamp decoding, read-committed visibility, deterministic
  teardown, and zero observer groups, both locally and in `nix flake check` on Linux CI.
- [x] M2 — Store-neutral scan refactor and client-backed Kafka reader accepted
  (2026-10-24): all 63 local Kafka groups pass through the real client and
  controlled seam, including the public-runner first slice, descriptor/policy
  rejection before allocation, and independent partition identities. The native
  adapter check also passes all 19 groups for each SQL store (38 total).
- [ ] M3 — Complete Kafka contract suite integrated into `just check` and the native Nix
  check: missing/undecodable correlation, page exhaustion, cutoff ambiguity, crossing reads,
  unverified history, deadline with consumer release, outage before mutation, transactional
  visibility, truncation detection, and group/topic/offset non-interference all pass; CI is
  green.
- [x] M4 — Contract, documentation, and catalog integration accepted
  (2026-10-24): Kafka workflow declarations and endpoint validation pass, CAP-13
  and the guides/ADRs describe the usable reader, and `just check-docs` validates
  13 capabilities and 49 terms. `mori validate`, workflow tests, `just check`,
  and `git diff --check` pass locally.


Current handoff (2026-10-24): the upstream blocker is resolved by the published
`rdkafka-hs` 1.0.0.1 release (tag object `33e2ab5f31be57e14c9820d4ad99032d3e9b41f1`,
commit `45d9e21ad3c72b56c482173e17ca3fa2bd8b1bc7`).
[IR-3](mori://shinzui/rdkafka-hs/okf/improvement-requests/concepts/IR-3) is completed.
Cabal and Nix now pin that same commit, and all 37 original spike/controlled
checks pass without a local header reversal. The public `kafka` constructor and
client-backed `KafkaPort` are implemented; a first complete slice passed 44
checks, including repeated exactly-once reads, cardinality, empty history,
pre-baseline exclusion, independent three-partition readers, and zero allocation
for policy/descriptor rejection. All 63 Kafka groups now pass locally, including actual transactions, retained
cutoff ambiguity, socket release, partition growth during a read, and real record
deletion. The fixture confirms group/topic/offset non-interference and private
stderr. Full regression/native gates and Linux CI remain to be accepted.

The toolchain remains Seihou 0.35.0, GHC 9.12.4, librdkafka 2.15.0, c2hs 0.28.8,
and Apache Kafka 4.3.1 with JRE 17.0.19. M4 documentation and the CAP-13 record
are implemented. The first native full flake run from the preceding checkpoint
had ten-second workflow-test timeouts during parallel compilation; recheck that
gate at the final candidate rather than treating the earlier failure as accepted.
All local acceptance gates now pass: the full broker suite, regression tests,
and the native adapter and full flake checks. Linux CI on the pushed
implementation passed all 63 Kafka groups in Linux Cabal at
https://github.com/shinzui/shoko/actions/runs/40047314301, then failed the
existing native workflow fixture because its generated executable used
`/usr/bin/env`, unavailable inside the Linux sandbox. The fixture now uses
`sys.executable`; Linux CI must accept that correction. M1 and M3 remain open
only for the required Linux CI acceptance.

Blocker history: on 2026-10-21 M1 was blocked because Hackage `hw-kafka-client` 5.3.0 could
not construct an assign-only consumer, its EOF errors omitted partition identity, and its
close did not destroy the client; the work then waited for the owner's fork to carry IR-2.

Earlier unblock (2026-10-22; superseded by the IR-3 gate above): the fork shipped
as the renamed successor package `rdkafka-hs`
1.0.0.0 (`mori://shinzui/rdkafka-hs`, tag `v1.0.0.0`, commit
`63031a21d070819fe89afbacb6ce76238816748f`), and
[IR-2](mori://shinzui/rdkafka-hs/okf/improvement-requests/concepts/IR-2) is `completed`
there with that release as its resolution. That release initially permitted the
M1 pin and spike to proceed; IR-3 now gates
the client binding of `KafkaPort`, the public `kafka` constructor, and the
real-broker contract groups of M2/M3 behind the same M1 → M2 → M3 → M4 order. See
the Decision Log entries dated 2026-10-22 for the pin and the Cross-repository references
for the API.

Earlier implementation checkpoints supplied the store-neutral scanner, topic
and correlation descriptors, 30 controlled Kafka groups, 38 real SQL-store
groups, owned broker fixture, workflow schema/validator support, and the initial
guides and ADRs. The 2026-10-23 checkpoint added the managed client toolchain,
1.0.0.0 reproduction pin, and header-order regression. Those historical failures
remain in Surprises & Discoveries; they are not current release blockers.


## Surprises & Discoveries

Linux native fixture discovery (2026-10-24): the second run passed all 63
Kafka groups and non-interference checks, then failed `checks.workflow-v2`
with `kubectl-unavailable`. Its generated fake executable used an
`/usr/bin/env python3` shebang, which is absent in the Linux Nix sandbox.
The fixture now writes the current `sys.executable` into that shebang.
Production workflow behavior and all deadlines are unchanged.

Linux fixture discovery (2026-10-24): the first Linux run passed 62 of 63
Kafka groups and failed the silent-broker test's exact reason assertion. The
acceptance requires unavailable evidence plus bounded return and socket release;
a native transport failure may race with the host deadline. The fixture now
accepts only the two contracted unavailable categories (`kafka-source-deadline`
or `kafka-source-unavailable`), reports the fixed category, and retains both
one-second timing/EOF bounds. It still rejects every observed outcome. Linux CI
must pass this corrected assertion before M1/M3 completion.


CI discovery (2026-10-24): repository Actions permissions reported
`enabled: false`, so pushing the implementation did not schedule Linux checks.
Actions was enabled to run the existing CI workflow required by this plan;
a subsequent plan-checkpoint push triggers that gate. The code checkpoint is
`105fbf8`, with all 63 Kafka groups and strict catalog validation passing locally.
Final native and Linux results remain required before completion.


Release-source validation on 2026-10-21 found that the local corpus has fixes absent from
the selected release. Hackage still lists 5.3.0 as the newest normal release; its upstream
tag is `e80c3220c46f4b6b2a1cd5007fca5e6df7f22ba1`. In that tarball,
`mori://haskell-works/hw-kafka-client` (project-relative `src/Kafka/Consumer.hs`,
artifact-level URI pending), `newConsumer` unconditionally calls `subscribe`, including for
`topics []`. In `mori://confluentinc/librdkafka` at tag `v2.15.0`
(`9a94e11452cdeb0a844db44ee5dd01ccbe17d3ab`), project-relative
`src/rdkafka_subscription.c` rejects an empty subscription with
`RD_KAFKA_RESP_ERR__INVALID_ARG`. The corpus skips subscription when the set is empty;
that is not evidence that 5.3.0 supports the same operation.

The same Hackage tarball's project-relative `src/Kafka/Consumer/Convert.hs` converts every
errored message to `KafkaResponseError errorCode`, losing its topic, partition, and offset.
Counting these anonymous EOF errors cannot prove that every assigned partition finished.
Its `closeConsumer` calls `rd_kafka_consumer_close`; destruction is attached to a concurrent
foreign-pointer finalizer in project-relative `src/Kafka/Internal/RdKafka.chs`. A `bracket`
around this API does not by itself establish the plan's bounded socket-release guarantee.
Those source paths belong to `mori://haskell-works/hw-kafka-client`; artifact-level URIs
are pending.

In `mori://confluentinc/librdkafka` at `v2.15.0`, project-relative
`src/rdkafka_request.c` sends the configured isolation level in `rd_kafka_ListOffsetsRequest`.
The end returned by a `read_committed` watermark query is therefore a visibility boundary
(last stable offset), not an unconditional physical high watermark. M1 must demonstrate
this with a transaction open before baseline capture. Artifact-level URI pending.

Implementation session (2026-10-21): the event-store suite has 19 groups per store (38
checks), not the 18/36 the plan recorded. `kafka-producer-perf-test.sh --transactional-id …
--transaction-duration-ms 100` completes one transaction with only the stock tools, so the
fixture can create `__transaction_state` before its snapshot. `kafka-consumer-groups.sh
--reset-offsets --to-offset 1 --execute` on an absent group creates the inactive
`application-worker` group with a committed offset. The owned broker boots in the macOS dev
shell in a few seconds with the settings in M1, plus single-partition offsets/transaction
topics and share-coordinator replication of 1 for Kafka 4.x.

Repository validation passed `just check-docs`, `nix develop --command just
test-workflow-contract` (8 contract and 17 identity tests), and `nix develop --command
python3 scripts/check-result-schema.py` (7 examples). The host Python lacks `jsonschema`;
use the managed shell for the Python validation commands. No Kafka runtime acceptance was
run: the adapter, fixture, and test target do not yet exist.

Recheck on 2026-10-21 (implementation session): Hackage `preferred.json` still lists 5.3.0 as
newest, and the 5.3.0 tarball's library stanza lists `Kafka.Internal.RdKafka` and
`Kafka.Consumer.Convert` under `other-modules`, so no public escape hatch exists. The fork
`mori://shinzui/hw-kafka-client` (branch `fix/async-consumer-fatal-observability`, head
`6caed636898a78e9f6e5a9c93eeb5562cbb2580a`) already contains upstream's empty-subscription
skip but still drops message-error origin in `fromMessagePtr` and destroys the client only
from the concurrent finalizer registered in `newRdKafkaT`; running that finalizer with
`finalizeForeignPtr` is the deterministic-destroy route proposed in IR-2.

Fork outcome (2026-10-22): the fork did not land as a tagged commit of
`shinzui/hw-kafka-client`. It shipped as a renamed successor package, `rdkafka-hs` 1.0.0.0
(https://github.com/shinzui/rdkafka-hs, annotated tag `v1.0.0.0` at
`e499013e3a8a84328834bb0b0755332263c4cdee` peeling to commit
`63031a21d070819fe89afbacb6ce76238816748f`), whose history starts from hw-kafka-client 5.3.0
plus upstream's twelve unreleased `main` commits and the fatal-error fix `6caed63`. The
package keeps the `Kafka.*` module namespace, type names, and record fields, so only the
dependency name and bounds change. It is not on Hackage (its `preferred.json` returns 404)
and is distributed only as the tag; its ADR-7 records that a Hackage upload is a separate
decision. It requires GHC 9.12 or newer and librdkafka 2.15 or newer (a build-time `#error`
on `RD_KAFKA_VERSION`), and generates its FFI with the `c2hs` build tool. The pinned
Nixpkgs provides `rdkafka` 2.15.0 and `haskell.packages.ghc9124.c2hs` 0.28.8, so no
package-set change is needed. The IR-2 copy in the old fork repository still reads
`status: proposed`; the authoritative, completed record is the one in `rdkafka-hs`.

Two of the plan's earlier assumptions about conventions were wrong. `kafka-effectful` pins
the old fork only in `cabal.project` and adds `pkgs.rdkafka` to its shell; it has no Nix
Haskell override for the fork and, as of 2026-10-22, still depends on `hw-kafka-client`.
Shōko therefore writes its own override in `flake.module.nix` (see M1). And the Mori
registry entry for `mori://shinzui/rdkafka-hs` was registered before the release: its
checkout lagged `origin/master` by 431 commits and listed no OKF bundles, so `mori registry
show`, `mori path` for its artifacts, and on-disk reads must follow a `git fetch` and
fast-forward plus `mori register --local` in that repository before they reflect 1.0.0.0.

What the release changes for this plan: `newAssignedConsumer` never calls subscribe;
`pollMessageAttributed` returns `ConsumerMessageError` with `cmeTopic`, `cmePartition`, and
`cmeOffset`, so partition EOF is attributed and the one-consumer-per-partition workaround is
no longer needed for correctness; `destroyConsumer` frees the client synchronously and
exactly once (the release's integration test measured the accepted connection closed 49 ms
after the call against a silent listener), so `bracket` around it does establish the
bounded socket-release guarantee; and `partitionWatermarkOffsets` under `read_committed` is
pinned by a test to stop at the last stable offset. `Kafka.Topic.createTopic` and
`deleteTopic` exist, so the "no admin module" rationale for `kafka-topics.sh` in the suite
no longer holds; the suite keeps the CLI so the fixture does not depend on the client under
test (see Decision Log).

Catalog handle (2026-10-22): `CAP-11`, which this plan reserved for the Kafka capability,
was allocated to declarative scenario catalog inspection by later work. The Kafka capability
takes the next free handle, `CAP-12` at this revision; M4 re-checks it with `okf id next`.


Released-client spike (2026-10-23): `Kafka.Internal.Shared.readHeaders` in
`mori://shinzui/rdkafka-hs` at the pinned 1.0.0.0 commit (project-relative
`src/Kafka/Internal/Shared.hs`, artifact-level URI pending) visits header indices
in ascending order, prepends to an accumulator, and returns it without reversing.
The real-broker ordered-duplicate roundtrip therefore fails:

```text
wire header order preserves last duplicate selection: FAIL
mori://shinzui/rdkafka-hs/okf/improvement-requests/concepts/IR-3: decoded headers reverse wire order; last-duplicate correlation is unsafe
1 out of 37 tests failed
```

The request is [IR-3](mori://shinzui/rdkafka-hs/okf/improvement-requests/concepts/IR-3).
It asks for ordered roundtrips through both polling APIs and callback modes and
a tagged release. Existing upstream header tests compare unique names as sets and
did not establish this contract. Shōko keeps the regression in the normal suite.
A missing topic can accept local `assign` before metadata arrives; the spike
therefore verifies metadata reports it missing and the topic list stays unchanged,
rather than treating a poll timeout as either a record or EOF.

Managed-environment integration (2026-10-23): Seihou advanced from 0.31.0 to
0.35.0. Its combined update initially rolled back with
`changed_after_migration_command`; applying `seihou migrate nix-haskell-flake`
first and retrying `seihou update ... --var nix.kafka=true --json` succeeded.
The migration makes `.envrc` tracked. Save `nix.kafka=true` in
`.seihou/config.dhall` as well; the update records the override in its manifest
but does not save the config. `seihou diff` then reports no drift. The managed
Nixpkgs remains `d5dfd8e6716dde34398bc14bc87c10dece9c8c68`; GHC 9.12.4,
librdkafka 2.15.0, c2hs 0.28.8, Kafka 4.3.1, and its JRE 17.0.19 are unchanged.
Nix supplies network 3.2.8.0 while Cabal freezes 3.2.9.0; the fixture uses their
shared API with a `>=3.2.8 && <3.3` bound. Cabal freeze does record the source
package version and flags, contrary to the earlier M1 assumption; its immutable
source identity remains the `source-repository-package` commit.


Resume discovery (2026-10-24): GitHub release `v1.0.0.1` was published on
2026-10-23 at 23:30:30 UTC. The source diff reverses the completed header
accumulator at the decoding boundary, preserving wire order for every consumer
path; its public API is unchanged. Hackage still returns 404 for the package.
The 37-group Shōko spike passes against the release, including the formerly
failing duplicate-header roundtrip. The published tag peels to the same commit
used by Cabal and Nix; its Nix source hash is
`sha256-lno5sy1FDVLTzHeunuUmnbqNAMGGrFymWyJg/5KgwuM=`.

Client integration exposed a scanner edge case: watermark loss was previously
saved only after a complete successful scan. A later read failure could discard
that observed loss. The scanner now saves watermark and partition-set losses
immediately; a controlled regression observes a low-watermark loss, fails the
trailing read, restores the apparent watermark, and still gets incomplete
history. The public reader's first 44-group broker slice passes with this fix.


## Decision Log

- Decision: Implement Kafka as a third backend of the shared finite event-scan model in
  `shoko-adapters/src/Shoko/Adapter/EventStore/Internal.hs`, adding a `TopicScope`, Kafka
  correlation sources, and a store-neutral scanner, rather than a separate query and evidence
  type.
  Rationale: contexts keep one `eventQuery`/`EventEvidence` vocabulary across stores, and the
  cutoff, ambiguity, deduplication, and intactness logic already proven by 36 real-store checks
  is reused instead of duplicated.
  Date: 2026-10-21

- Decision: The observer uses a fresh, run-unique consumer group id that is never committed,
  manual partition assignment, auto-commit and auto-offset-store disabled, automatic topic
  creation disabled, and `read_committed` isolation. It never calls subscribe.
  Rationale: librdkafka's high-level consumer API (`rd_kafka_consumer_poll`, `rd_kafka_assign`)
  returns `RD_KAFKA_RESP_ERR__UNKNOWN_GROUP` without a `group.id`, but an assign-only consumer
  never joins or commits, so the broker records no group state; this is the observer-safe
  shape to verify against the released client, with
  `mori://shinzui/shibuya-kafka-adapter` as precedent only.
  Date: 2026-10-21

- Decision: Every poll re-reads each partition from its baseline offset to its end instead of
  advancing a forward cursor.
  Rationale: this keeps the shared `seen ⊆ ids` intactness check and occurrence deduplication
  identical to the SQL readers, makes retention deletions observable, and is bounded by the
  query's limits; the cost is proportional to records produced during the finite run.
  Date: 2026-10-21

- Decision: Evaluate released `hw-kafka-client` 5.3.0 from Hackage, provided by the managed Nix
  package set, with librdkafka 2.15.0 from the pinned Nixpkgs; do not depend on the
  `mori://shinzui/hw-kafka-client` fork.
  Rationale: ADR 0001 requires released dependencies. Validation found that 5.3.0 cannot
  meet the proposed construction path; it is a reproduction baseline, not an accepted
  implementation pin. The earlier assumption that only asynchronous callback behavior
  differed from the corpus was incorrect. M1 must resolve construction and deterministic
  teardown through a released supported API before selection is final.
  Date: 2026-10-21
  Superseded: 2026-10-22, by the `rdkafka-hs` decision below.

- Decision: The fixture broker is Apache Kafka 4.3.1 (`pkgs.apacheKafka`, KRaft single node on
  loopback with a run-owned data directory) for both `just test-kafka` and the native Nix
  check; Seihou's `nix.redpanda` stays disabled.
  Rationale: the package exists for Linux and Apple Silicon in the pinned Nixpkgs, a sibling
  project already boots it inside a flake-check sandbox, and the Redpanda option is macOS-only
  and depends on Apple Container.
  Date: 2026-10-21

- Decision: Execution-ID correlation is unsupported for Kafka in this plan; construction
  returns `Left ExecutionMetadataUnsupported`. Business-key correlation may come from the
  record key, a named header, or a payload JSON field.
  Rationale: the inspected publisher does not propagate a Shōko execution ID into its Kafka
  envelope ([IR-52](mori://shinzui/keiro/okf/improvement-requests/concepts/IR-52) is proposed),
  and the legacy `correlation-id` header carries a Message DB correlation id, not a run
  identity.
  Date: 2026-10-21

- Decision: `EventEvidence` keeps its shape; for Kafka, `position` is the partition offset,
  `causation` is `Nothing`, and the partition appears in the occurrence id and public details.
  Rationale: avoids a breaking change to the typed evidence consumed by contexts while keeping
  the public report able to locate the record.
  Date: 2026-10-21

- Decision: All three event handler builders return `Either HandlerBuildError`; two cause
  constructors are added for unsupported scopes and correlation sources, and
  `kirokuObservation` changes signature accordingly.
  Rationale: a Kiroku binding given a `TopicScope` must fail in preflight as
  `HandlerConstructionFailed`, never as an acquisition failure after fixtures start.
  Date: 2026-10-21

- Decision: The Kafka client is the owner's fork `mori://shinzui/hw-kafka-client`
  (https://github.com/shinzui/hw-kafka-client), pinned by immutable commit through a
  `source-repository-package` stanza in `cabal.project` and the matching Nix override, the
  convention `mori://shinzui/kafka-effectful` already uses for this fork. The fork must first
  carry [IR-2](mori://shinzui/hw-kafka-client/okf/improvement-requests/concepts/IR-2):
  assign-only construction without `subscribe` (upstream commit
  `56be4a6f61f17f91eeb1c7d0feac4084bd10ce93`, unreleased), partition-attributed per-message
  errors including partition EOF, deterministic client destruction, and a pinned
  read-committed watermark test. The plan is blocked on that tagged commit. This is an
  owner-authorized, scoped exception to ADR 0001's released-dependency rule; it ends when a
  released version (the owner's later "proper fork" or upstream) carries the same API.
  Rationale: rechecked on 2026-10-21, Hackage's newest `hw-kafka-client` is still 5.3.0 and no
  other Hackage package is viable (`librdkafka` and `kafka` are 0.0.0.0 placeholders,
  `kafka-client` dates from 2015, `haskakafka` from 2016 against librdkafka 0.9, and
  `kafka-interchange` only encodes the wire protocol). The owner chose the fork over a
  Shōko-owned librdkafka FFI binding and over waiting for an upstream release.
  Date: 2026-10-21
  Superseded: 2026-10-22, by the `rdkafka-hs` decision below; the fork completed IR-2 as
  the successor package rather than as a tagged `hw-kafka-client` commit.

- Decision: While blocked, implement everything that does not call the client. The Kafka
  scanner is written against an internal port — a record of IO functions for topic metadata,
  per-partition watermarks, and reading one partition from an offset to its end under a
  deadline — so the offset bookkeeping, sticky history loss, partition-set checks, record
  normalization, correlation selection, and every runner-level honesty check run now against
  a controlled in-memory port. The public `kafka` constructor, which needs the client binding
  of that port, is added when the fork lands. `Shoko.Adapter.Kafka.Internal` is an exposed
  module so the suite can supply the controlled port; hosts use only `Shoko.Adapter.Kafka`.
  Rationale: the plan already requires a controlled scanner test for sticky history loss; the
  port is that seam made explicit, and it keeps the client binding a small, separately
  verifiable step once IR-2 lands.
  Date: 2026-10-21

- Decision: Defer the Seihou `nix.kafka=true` toggle to the client binding step; add Apache
  Kafka to the dev shell and adapter checks through `flake.module.nix` now.
  Rationale: the dry run shows the toggle is not a same-version change — Seihou requires
  `seihou update`, upgrading `nix-haskell-flake` from 0.31.0 to 0.34.0 and replacing
  `flake.lock`, `flake.nix`, and `nix/haskell.nix`. librdkafka is useless until the fork is
  linked, so the upgrade and its pin reverification belong to that step.
  Date: 2026-10-21

- Decision: Do not record the Kafka capability (planned as CAP-11, now CAP-12; see
  Surprises & Discoveries) until hosts can allocate a client-backed Kafka reader.
  Rationale: the capabilities profile permits only `shipped`, `deprecated`, or `withdrawn`
  ("whether a consumer can use this capability right now"); without the public `kafka`
  constructor no consumer can. CAP-7 is refreshed for the SQL readers' new typed rejections.
  Date: 2026-10-21

- Decision: Shared public details report `history-intact` as the conjunction of the shared
  `seen ⊆ ids` check and the scanner's own `historyIntact`; Kafka adds
  `low-watermark-intact` as a separate sticky flag. Baseline failures for an unstable
  partition set return `kafka-partitions-unstable`, and records whose offsets are not
  strictly increasing from the requested offset, or exceed the record limit, return
  `kafka-offsets-invalid`.
  Rationale: these keep the plan's fixed-reason rule for cases the plan did not name, and SQL
  output is unchanged because SQL scanners always report intact history.
  Date: 2026-10-21

- Decision: The Kafka client is `rdkafka-hs` 1.0.0.0 (`mori://shinzui/rdkafka-hs`,
  https://github.com/shinzui/rdkafka-hs), the maintained successor of the owner's
  `hw-kafka-client` fork, pinned in `cabal.project` by a `source-repository-package` stanza
  whose `tag` is the immutable commit `63031a21d070819fe89afbacb6ce76238816748f` (what the
  annotated tag `v1.0.0.0` peels to), with `rdkafka-hs >=1.0 && <1.1` in every component
  that uses it, and built in Nix from the same commit through `fetchFromGitHub` and
  `callCabal2nix` in `flake.module.nix`. This supersedes both earlier client decisions. The
  owner-authorized exception to ADR 0001's released-dependency rule continues in narrowed
  form: the dependency is a published, tagged release with a changelog and a GitHub
  release, but not a Hackage release; the exception ends when `rdkafka-hs` (or upstream) is
  on Hackage with the same API.
  Rationale: IR-2 is completed and its acceptance criteria are covered by the release's own
  integration tests (`AssignOnlyTest`, `AttributedErrorTest`, `DestroyTest`,
  `ReadCommittedTest`, `ObserverTest`, all passing in both callback poll modes). Pinning the
  commit rather than the tag name keeps the resolution reproducible even though the
  project promises never to move a published tag. Cabal and Nix must build the same code,
  and the managed Nix package set has no `rdkafka-hs`, so an explicit hashed source
  override is the only coherent selection.
  Date: 2026-10-22

- Decision: Keep the per-partition `KafkaPort.readPartition` seam and bind it with one
  `newAssignedConsumer` per call, assigned exactly one partition; use
  `pollMessageAttributed` and accept EOF only when `cmePartition` names that partition and
  `cmeOffset` is present; release with `destroyConsumer` in `bracket`.
  Rationale: the port and the thirty controlled contract groups already exist and pass;
  changing the port to a multi-partition read would reopen tested code for an optimization
  no requirement needs yet. Attributed EOF is still used so the end of a partition is
  proven by identity rather than counted. Consolidating partitions onto one consumer per
  scan is a later, port-level change if connection count becomes a problem.
  Date: 2026-10-22

- Decision: The fixture keeps creating topics with `kafka-topics.sh` through
  `System.Process` even though `Kafka.Topic.createTopic` now exists.
  Rationale: the topic-list check in `scripts/test-kafka` proves the observer never creates
  topics; a fixture that created topics through the client under test would blur that
  evidence.
  Date: 2026-10-22


- Decision: Treat the 1.0.0.0 pin as the reproducible M1 baseline while IR-3 is
  open; the client-backed constructor and shipped capability remain gated on a
  fixed tagged release. Preserve the failing ordered-header spike in all normal
  Kafka gates, rather than reversing headers locally or marking it expected-fail.
  Rationale: M1 explicitly requires an upstream request and next-release pin for
  client defects. Header order is necessary to the accepted correlation contract.
  Date: 2026-10-23


- Decision: Advance the immutable client pin to the published `rdkafka-hs`
  1.0.0.1 tag, commit `45d9e21ad3c72b56c482173e17ca3fa2bd8b1bc7`, after the
  unchanged released-client spike passes. Require `rdkafka-hs >=1.0.0.1 && <1.1` so external consumers cannot
  select the known-broken first release. Preserve the header-order regression
  in normal gates. Persist observed history loss before any subsequent scan IO.
  Rationale: the release resolves IR-3 without a local workaround, and failed
  scans must not erase evidence of deletion or end regression.
  Date: 2026-10-24


## Outcomes & Retrospective

Implementation resumed on 2026-10-24 with the fixed 1.0.0.1 release. The
client-backed reader, public runner contracts, and catalog/docs are implemented.
All 63 Kafka groups, the native adapter derivation, `just check-docs`, and the
full local `just check` pass. Linux CI remains in progress. The local full check
uses `NIX_CONFIG` with `max-jobs = 1` and `cores = 2` to avoid the previously
observed parallel-build workflow-test contention; no test deadline or production
request bound was relaxed. The 1.0.0.0 header-order blocker is resolved,
and the scanner now preserves observed loss even across failed scans. Do not
mark this plan complete until the full broker, native, regression, and Linux CI
acceptance below is recorded. Durable client selection and loss semantics are
distilled in ADR 0001 and ADR 0003.


## Context and Orientation

### What Shōko already does

`shoko-core` defines scenarios (typed descriptions of actions and expectations), bindings
(the handlers that give those operations runtime meaning), sources (named evidence surfaces
with a baseline captured before actions), and the bounded runner that returns Pass, Fail, or
Unknown. `shoko-adapters` supplies generic handlers. The public guides are `docs/core.md`,
`docs/adapters.md`, and `docs/scenario-hosts.md`; the controlled vocabulary is in
`docs/terminology/index.md`.

The durable event readers live in `shoko-adapters/src/Shoko/Adapter/EventStore.hs` (public
re-exports), `shoko-adapters/src/Shoko/Adapter/EventStore/Internal.hs` (the implementation),
`shoko-adapters/src/Shoko/Adapter/Kiroku.hs`, and `shoko-adapters/src/Shoko/Adapter/MessageDb.hs`.
The important names in `Internal.hs` are:

- `EventScope` (`StreamScope`, `CategoryScope`) with validators `streamScope` and
  `categoryScope`; `Limits` built by `limits pageSize pages budgetMillis`; `CorrelationMode`
  (`BusinessKeyField key`, `ExecutionMetadata`); `HistoryPolicy` (`AppendOnlyDuringRun`,
  `UnverifiedHistory`); `EventQuery a` built by `eventQuery`, which also carries the expected
  event type and a payload decoder `Value -> Either Text a`.
- `EventEvidence a` (`position`, `recordedAt`, `causation`, `value`), the typed result a
  context receives for each matching occurrence.
- `StoreEvent`, the internal normalized record (identity, event type, position, timestamp,
  JSON payload, optional correlation and causation ids); `Reader a`, which holds connection
  settings, the schema, the public `SourceId`, the query, a Hasql `Fetch` function, and an
  `IORef ReaderState` (baseline, excluded ids, seen ids, and the `timely` map of ids first
  seen before each cutoff).
- `readerHandler`, which builds the public `Handler` with `observationHandler`, requires the
  `ReadEvents` capability, advertises `DurableHistory` coverage through `newSource`, and
  checks the allocated reader's source id and query against the declared descriptor before
  any IO; `snapshot`, which re-scans the whole scope in one repeatable-read transaction under
  the remaining deadline; `capture`, which records the pre-action baseline (existing ids and
  an opaque token); and `observeEvents`, which turns a scan into `ObservedWithDetails` with
  occurrences, `Coverage DurableHistory from through complete`, and safe public details.

The shared contract suite is `shoko-adapters/test/EventStore/Contract.hs` (19 groups per
store) driven by `shoko-adapters/test/EventStoreMain.hs` and the fixture script
`scripts/test-event-stores`, which owns a Unix-socket PostgreSQL cluster and passes
`SHOKO_EVENT_STORE`, `SHOKO_EVENT_READ`, and `SHOKO_EVENT_WRITE` to the suite. `justfile`
exposes `test-event-stores`; `flake.module.nix` runs the same script against compiled test
binaries in the `shoko-adapters` derivation's `checkPhase`; `.github/workflows/ci.yml` runs
`nix develop --command just check` on Ubuntu.

### Kafka terms used in this plan

A Kafka *topic* is a named, append-only log split into numbered *partitions*. Each *record*
in a partition has a monotonically increasing *offset*, an optional byte *key*, a byte
*value*, a list of byte *headers*, and a millisecond *timestamp* set by the producer
(`CreateTime`) or the broker (`LogAppendTime`). A partition's *high watermark* is the offset
after the last fully replicated record; its *low watermark* is the first offset still
retained. A *consumer group* is a named set of consumers whose *committed offsets* the broker
stores in an internal topic; *subscribe* joins a group and lets the broker assign partitions,
while *assign* lets the client choose partitions and offsets itself without joining.
*Retention* deletes old records by age or size; *compaction* deletes superseded records with
the same key. *Transactions* let a producer write records atomically; a consumer with
`read_committed` isolation only sees records up to the *last stable offset*, the first offset
belonging to a still-open transaction. *Partition EOF* is an event librdkafka can emit when a
consumer's fetch reaches the end of a partition. *KRaft* is Kafka's built-in consensus mode
that runs a broker without ZooKeeper.

### Current state of the repository

As of 2026-10-24 the public client-backed Kafka reader exists. Cabal and Nix pin
`rdkafka-hs` 1.0.0.1, the owned broker runs the released-client spike, controlled
scanner contracts, and public-runner contracts in `Kafka/Broker.hs`, and the
workflow schema accepts `kafka` and `kafka://`. Seihou 0.35.0 enables the Kafka
client shell while private Redpanda stays disabled. CAP-13 describes the reader;
final acceptance is tracked in Progress. Staging topic ownership and access remain
separate from these local fixture checks.


### Relevant ADRs

[ADR 0001](../adr/0001-use-jitsurei-standards-and-the-seihou-haskell-flake.md) requires the
Jitsurei Haskell standards, keeps `flake.nix`, `flake.lock`, and `nix/*.nix` under Seihou
ownership with project wiring in `flake.module.nix`, and states that Kafka clients and private
Redpanda stay disabled "until a selected workflow requires them". It also fixes the dependency
rules: verify Hackage releases and upstream tags before pinning, select versions coherent
with the managed Nix package set, record the selection in `cabal.project`, the freeze file,
and `docs/dependencies.md`, and never add unpublished dependencies or blanket bounds waivers.
This plan is the moment a workflow requires the Kafka client; M1 enables the option through
Seihou and M4 revises the ADR.

[ADR 0002](../adr/0002-keep-scenarios-inspectable-and-bindings-explicit.md) makes correlation
explicit: a binding advertises `RequiresBusinessKey` or `RequiresExecutionId`, missing
correlation yields Unknown rather than a broad search, and bindings contribute capabilities
(`ReadEvents` for event readers) to preflight before any resource is acquired.

[ADR 0003](../adr/0003-record-bounded-evidence-and-three-valued-results.md) defines bounded
evidence: baselines before actions, coverage that distinguishes sampled state from durable
history, the separation of the evidence cutoff from the request deadline, the closing read
that durable `eventually` needs before failing, and the rule that source adapters own the
cursor and visibility proof and never compare host monotonic time with remote timestamps.
The Kafka reader must satisfy every one of these.

[ADR 0004](../adr/0004-gate-parity-on-real-workflows-and-context-owned-vocabulary.md) lists
"generic Kafka observation" among deferred work and states that Shōko owns generic adapters
while bounded contexts own vocabulary, with legacy support thin and business-key correlated.
This plan moves bounded read-only Kafka observation into scope; destructive queue consumers,
continuous Observe, and Replay remain deferred. M4 records that revision.

### Cross-repository references

The Kafka client is [rdkafka-hs](mori://shinzui/rdkafka-hs/packages/rdkafka-hs) 1.0.0.1,
the maintained successor of
[hw-kafka-client](mori://haskell-works/hw-kafka-client/packages/hw-kafka-client), published
as tag `v1.0.0.1` of https://github.com/shinzui/rdkafka-hs (commit
`45d9e21ad3c72b56c482173e17ca3fa2bd8b1bc7`, released 2026-10-23) and not on Hackage. Its
`README.md` sections "Reading partitions without joining a group" and "Shutting down a
consumer" and its `CHANGELOG.md` describe the observer API; the completed request is
[IR-2](mori://shinzui/rdkafka-hs/okf/improvement-requests/concepts/IR-2), and the durable
decisions are its ADR-1 (consumer queue and teardown ownership) and ADR-7 (first release
scope and distribution) in the `adrs` bundle of `mori://shinzui/rdkafka-hs`. The module
namespace is unchanged from hw-kafka-client. The relevant API is `Kafka.Consumer`
(`newAssignedConsumer`, `assign`, `pollMessageAttributed`, `destroyConsumer`,
`closeConsumer`, `consumerFatalError`; `ConsumerRecord` with `crTopic`, `crPartition`,
`crOffset`, `crTimestamp`, `crHeaders`, `crKey`, `crValue`; `TopicPartition` with
`tpTopicName`, `tpPartition`, `tpOffset`; the re-exported `RdKafkaRespErrT` constructors
such as `RdKafkaRespErrPartitionEof` and `RdKafkaRespErrTimedOut`),
`Kafka.Consumer.Types.ConsumerMessageError` (`cmeError`, `cmeTopic`, `cmePartition`,
`cmeOffset`; the last three are `Nothing` only for a poll timeout or a raised fatal error),
`Kafka.Consumer.ConsumerProperties` (`brokersList`, `groupId`, `noAutoCommit`,
`noAutoOffsetStore`, `extraProp`, `clientId`, `callbackPollMode`, `setCallback` with
`errorCallback` and `logCallback` from `Kafka.Callbacks`), `Kafka.Metadata`
(`topicMetadata`, `partitionWatermarkOffsets` returning `WatermarkOffsets` with
`woLowWatermark` and `woHighWatermark`), `Kafka.Version` (`librdkafkaVersion`),
`Kafka.Producer`, `Kafka.Transaction`, and `Kafka.Topic` (`createTopic`, `deleteTopic`) for
fixtures, and `Kafka.Types` (`TopicName`, `PartitionId`, `Offset`, `Timeout`, `Headers`,
`headersToList`, `KafkaError`). The package requires GHC 9.12 or newer, librdkafka 2.15 or
newer with headers (enforced at build time), and the `c2hs` build tool declared in its
`build-tool-depends`; every executable linking it must be `-threaded`. The C library is
[librdkafka](mori://confluentinc/librdkafka); its `CONFIGURATION.md` documents the consumer
defaults used below (`allow.auto.create.topics` false for consumers, `isolation.level`
`read_committed`, `enable.partition.eof` false, `enable.auto.commit` true), and
`src/rdkafka.c` creates the consumer group handle only when `group.id` is non-empty. The
pinned Nixpkgs revision `d5dfd8e6716dde34398bc14bc87c10dece9c8c68` provides `rdkafka`
2.15.0, `haskell.packages.ghc9124.c2hs` 0.28.8, and `apacheKafka` 2.13-4.3.1 with JRE
17.0.19; it has no `rdkafka-hs` and no Redpanda server. Hackage `hw-kafka-client` 5.3.0
remains only the reproduction baseline recorded in Surprises & Discoveries.

The dev-shell toggle is documented by the
[Seihou nix-haskell-flake template](mori://shinzui/seihou-modules/templates/nix-haskell-flake):
`nix.kafka=true` adds `pkgs.rdkafka` and `pkgs.rdkafka.dev` to the generated shell and exports
`CPATH`, `LIBRARY_PATH`, and `PKG_CONFIG_PATH` so GHC links `-lrdkafka`. The installed module
version is now 0.35.0 (`docs/development.md`); the managed upgrade and Kafka
toggle have landed. Use Seihou for any subsequent regeneration.

The first real topic is `registration.completed.v1`, published by
[registration-service-v2](mori://tan/registration-service-v2) (project-relative
`registration-service-v2/src/RegistrationServiceV2/Completion/Publisher.hs`; artifact-level
URI pending) and consumed by [mls-service-v2](mori://tan/mls-service-v2) (project-relative
`mls-service-v2-core/src/MlsService/Kafka/RegistrationCompleted/Inbound.hs` and
`mls-service-v2-core/src/MlsService/Kafka/Envelope.hs`; artifact-level URIs pending).
The record key is the `registrationId` text, the value is a
bare JSON object that also carries `registrationId`, and the headers are `event-type`
(`RegistrationCompleted`), `event-version`, `source-service`, optional `correlation-id` (the
source Message DB correlation UUID), and optional `traceparent`. The same service's test
fixture boots a single-node KRaft broker inside its flake check; its gotchas are reused here.
[Keiro IR-52](mori://shinzui/keiro/okf/improvement-requests/concepts/IR-52) owns execution-id
propagation and is not presumed complete. [shibuya-kafka-adapter](mori://shinzui/shibuya-kafka-adapter)
is a consumer-group adapter and is precedent only, not a dependency.


## Plan of Work

### M1 — Prove the toolchain and the broker fixture (prototyping)

This milestone de-risks the two uncertain interfaces: the C-backed Kafka client inside the
managed Nix environment, and a JVM broker inside both the dev shell and the Nix build
sandbox. At its end the dev shell links `rdkafka-hs`, `scripts/test-kafka` owns a broker,
and a small spike suite documents how librdkafka behaves for an assign-only observer. The
broker-fixture half is already done (see Progress). The client half was initially unblocked on
2026-10-22 by `rdkafka-hs` 1.0.0.0, and its header-order fix shipped in 1.0.0.1 (IR-3).
The updated spike passes locally and permits promotion into M2. The 5.3.0
reproducer is no longer required; the recorded defects stand as history. A `subscribe` call of any kind
remains forbidden in observer code: even if no group survives shutdown, it cannot
establish that the observer never joined a group. If 1.0.0.1 fails any spike check below,
file an improvement request in `mori://shinzui/rdkafka-hs` and pin its next release; do not
patch or vendor dependency code, weaken the guarantee, or widen this plan into client
development.

Enable the client library through Seihou rather than by editing generated files. From the
repository root run `seihou run nix-haskell-flake --var nix.kafka=true --dry-run --no-commands`
and read the plan. If Seihou refuses because the installed module advanced past the recorded
0.31.0 and ships migrations, use `seihou update nix-haskell-flake --var nix.kafka=true
--dry-run` instead, inspect the generated changes, and apply without `--dry-run`. Either path
must leave `nix.redpanda` false, update `.seihou/config.dhall`, and regenerate `nix/haskell.nix`
with the rdkafka block and shell exports. A same-version toggle keeps `flake.lock` unchanged;
an actual module upgrade may replace the managed lock. In that case inspect the generated
pin changes and reverify every package version below before proceeding; never restore an old
lock over the new template or hand-edit it. Run `seihou diff`
afterwards and record the resulting module version in `docs/development.md`. The toggle is
what gives `cabal build` in the dev shell the librdkafka headers that `rdkafka-hs` checks at
build time. Also add `pkgs.haskellPackages.c2hs` to `haskellProject.extraDevPackages` in
`flake.module.nix`, as `rdkafka-hs`'s own flake module does, so Cabal finds the `c2hs`
build tool on `PATH` instead of building it from Hackage. `pkgs.apacheKafka` is already in
`extraDevPackages`, which puts `kafka-storage.sh`, `kafka-server-start.sh`,
`kafka-topics.sh`, `kafka-consumer-groups.sh`, `kafka-console-producer.sh`,
`kafka-console-consumer.sh`, and `kafka-delete-records.sh` on the dev-shell `PATH`.

Pin the dependency. First confirm the release: `git ls-remote --tags
https://github.com/shinzui/rdkafka-hs 'refs/tags/v1.0.0.1*'` must list the annotated tag
`33e2ab5f31be57e14c9820d4ad99032d3e9b41f1` peeling (`^{}`) to
`45d9e21ad3c72b56c482173e17ca3fa2bd8b1bc7`, and `gh release view v1.0.0.1 --repo
shinzui/rdkafka-hs` must show a published, non-draft release. Then add to `cabal.project`,
after the `constraints` block, a stanza pinned by that commit, with a comment saying it is
what `v1.0.0.1` peels to and that the package is distributed only as a tag:

```cabal
source-repository-package
  type: git
  location: https://github.com/shinzui/rdkafka-hs.git
  tag: 45d9e21ad3c72b56c482173e17ca3fa2bd8b1bc7
```

Add `rdkafka-hs >=1.0.0.1 && <1.1` to the `shoko-adapters` library `build-depends` and to the
`kafka-adapter-test` suite in `shoko-adapters/shoko-adapters.cabal`. No additional `constraints` line
is needed: a source-repository package is selected by the stanza. `cabal freeze`
records its version and flags, while the stanza fixes the commit. Regenerate `cabal.project.freeze` with `nix develop --command cabal
freeze` after `cabal update`, because `rdkafka-hs` brings `bifunctors` into the plan. On the
Nix side add, inside the `overrides` of `flake.module.nix` beside the `callHackageDirect`
entries, a hashed source override built from the same commit:

```nix
rdkafka-hs = hself.callCabal2nix "rdkafka-hs"
  (pkgs.fetchFromGitHub {
    owner = "shinzui";
    repo = "rdkafka-hs";
    rev = "45d9e21ad3c72b56c482173e17ca3fa2bd8b1bc7";
    hash = "<the hash printed by nix flake prefetch>";
  })
  { };
```

Compute the hash with `nix flake prefetch
github:shinzui/rdkafka-hs/45d9e21ad3c72b56c482173e17ca3fa2bd8b1bc7 --json` and copy its
`hash` field. `callCabal2nix` maps the package's `extra-libraries: rdkafka` to `pkgs.rdkafka`
2.15.0 and its `build-tool-depends: c2hs:c2hs` to the package set's `c2hs`; its unit suite
is broker-free, so do not add `dontCheck`. Confirm Cabal and Nix build the same commit:
`nix develop --command cabal build shoko-adapters` and `nix build .#shoko-adapters` both
succeed, and the Cabal log shows `rdkafka-hs-1.0.0.1` fetched from that commit.

Record in `docs/dependencies.md`: `rdkafka-hs` 1.0.0.1, GitHub release `v1.0.0.1` of
2026-10-22, the tag object and commit, "not on Hackage; tag-only distribution per the
project's ADR-7", the narrowed ADR 0001 exception, the GHC 9.12 and librdkafka 2.15 floors,
`c2hs`, librdkafka 2.15.0 and `c2hs` 0.28.8 from the pinned Nixpkgs, and Apache Kafka 4.3.1
with JRE 17.0.19. Note in that file that `rdkafka-hs` requires `-threaded` executables for
its callback machinery; all adapter test suites already pass `-threaded`, and the
scenario-host guide must tell hosts the same. In the same change replace every mention of
the `shinzui/hw-kafka-client` fork and its IR-2 handle in `docs/dependencies.md`,
`docs/adapters.md`, `docs/development.md`, and ADR 0001 with `rdkafka-hs` and
`mori://shinzui/rdkafka-hs/okf/improvement-requests/concepts/IR-2`, keeping the 5.3.0
findings as history.

Write `scripts/test-kafka` as a Python sibling of `scripts/test-event-stores`. It reserves
two free loopback ports, writes a `server.properties` with `node.id=1`,
`process.roles=broker,controller`, `listeners=PLAINTEXT://127.0.0.1:<broker>,CONTROLLER://127.0.0.1:<controller>`,
`advertised.listeners=PLAINTEXT://127.0.0.1:<broker>`, `controller.quorum.voters=1@127.0.0.1:<controller>`,
`controller.listener.names=CONTROLLER`, `inter.broker.listener.name=PLAINTEXT`, replication
factors of 1 for offsets and transaction-state topics, `transaction.state.log.min.isr=1`,
`auto.create.topics.enable=false`, `group.initial.rebalance.delay.ms=0`, and `log.dirs` inside
a run-owned temporary directory. Every JVM child gets `LOG_DIR` pointing at a writable
run-owned directory and `KAFKA_OPTS` extended with `-Djava.security.egd=file:/dev/./urandom`;
without these the broker fails to start inside the Nix sandbox. It formats storage with
`kafka-storage.sh format --ignore-formatted -t <cluster-id> -c server.properties`, starts
`kafka-server-start.sh`, waits up to 120 seconds for a successful Kafka metadata command
(`kafka-topics.sh --bootstrap-server <bootstrap> --list`, with a per-attempt process timeout), and
always binds and advertises `127.0.0.1` rather than `localhost`, because librdkafka resolves
`localhost` to `::1` first. It then seeds a fixture application group: creates topic
`application-events`, produces one record with `kafka-console-producer.sh`, and
sets a committed offset explicitly with `kafka-consumer-groups.sh --bootstrap-server
<bootstrap> --group application-worker --topic application-events --reset-offsets --to-offset
1 --execute`. Verify the inactive group describes offset 1; do not rely on a short-lived
console consumer's periodic auto-commit. Initialize a fixture transactional producer and
complete one transaction before snapshots, so lazy creation of `__transaction_state` is not
mistaken for observer topic creation. It snapshots `kafka-consumer-groups.sh --list`,
`kafka-topics.sh --list`, and `kafka-consumer-groups.sh --describe --group application-worker`
(each with `--bootstrap-server <bootstrap>`),
runs the suite with `SHOKO_KAFKA_BOOTSTRAP=127.0.0.1:<broker>` and `SHOKO_KAFKA_LOG_DIR` set,
snapshots again, fails if any `shoko-observer-` group appeared, if the topic list changed
other than topics the suite names with its `fixture-` prefix, or if the application's parsed
`(group, topic, partition, committed-offset)` tuples changed. Do not compare transient
member IDs, lag, or whitespace from CLI output. Finally stop the broker and remove the directory. Sanitized failure
output goes under `.dev/kafka-tests/`. `--binaries dist/build` runs compiled test binaries
exactly as `test-event-stores` does.

`test-kafka` is already in `justfile`, the `kafka-adapter-test` suite already exists with
`-threaded`, `aeson`, `hedgehog`, `process`, `time`, `tasty`, and `tasty-hedgehog`, and the
adapter derivation already has `pkgs.apacheKafka` in `nativeBuildInputs` and runs `python
${./scripts/test-kafka} --binaries dist/build` in its `checkPhase`. Extend the suite's
`build-depends` with `rdkafka-hs >=1.0.0.1 && <1.1` and, as the spike groups need them, the
already frozen `async`, `network`, and `uuid`.

Add spike groups to the existing `kafka-adapter-test` suite (a new
`shoko-adapters/test/Kafka/Spike.hs` module listed in its `other-modules`), written directly
against `rdkafka-hs` because the client binding does not exist yet. The suite creates one
fresh topic per test with `kafka-topics.sh --bootstrap-server <bootstrap> --create --topic
fixture-<unique> --partitions N --replication-factor 1` through `System.Process`, using the
`LOG_DIR` the script supplied (the Decision Log records why the client's `Kafka.Topic` is
not used here). The spike must establish, with evidence recorded in Surprises & Discoveries:
that a consumer built with `newAssignedConsumer` from `brokersList`, `groupId
(ConsumerGroupId "shoko-observer-<uuid>")`, `noAutoCommit`, `noAutoOffsetStore`, `extraProp
"enable.partition.eof" "true"`, `extraProp "allow.auto.create.topics" "false"`, `extraProp
"isolation.level" "read_committed"`, `callbackPollMode CallbackPollModeSync`, and
`setCallback` with no-op `errorCallback` and `logCallback` can `assign` a `TopicPartition`
at an explicit `PartitionOffset` and receive records; that `pollMessageAttributed` reports
each partition's end as a `ConsumerMessageError` whose `cmeError` is `KafkaResponseError
RdKafkaRespErrPartitionEof`, whose `cmePartition` is `Just` that partition, and whose
`cmeOffset` equals that partition's visible end, exactly once per assigned partition, also
when several partitions are assigned to one consumer; and that a poll timeout arrives as
`RdKafkaRespErrTimedOut` with no origin and is never treated as an end. Poll with at most a
100 millisecond `Timeout`, capped by remaining request time, and read key, headers, value,
and `CreateTime`/`LogAppendTime` timestamps. Establish that `partitionWatermarkOffsets`
returns `woLowWatermark` and a committed-visible `woHighWatermark` per partition, including
when the transaction is already open before capture; that after `destroyConsumer` the
broker lists no `shoko-observer-` group; that assigning a nonexistent topic yields an error
rather than a created topic; and that with an open transaction holding a record in a
partition, a later committed record in the same partition is invisible to a
`read_committed` consumer until the transaction commits, after which both appear at their
original offsets. Include two empty partitions and one busy partition, and test EOF after
aborted transactions/control records. Prove the 80 millisecond stalled-broker deadline and
socket-release criterion from M3 already in this spike: against a loopback listener that
accepts and never answers, `destroyConsumer` returns and the accepted connection reaches
end-of-file within one second, with no forced GC, no hidden-module import, and no detached
cleanup thread (the release's own `DestroyTest` measured 49 ms; record the figure observed
here). Promote only a passing spike into M2; a failing check becomes an improvement request
in `mori://shinzui/rdkafka-hs`, not a local patch.

Acceptance: `nix develop --command just test-kafka` passes locally on macOS; `nix flake
check` builds the adapter derivation with the Kafka script in its `checkPhase` on Linux CI.
If the Nix sandbox on macOS cannot run the JVM broker, gate that native step on Linux with
`pkgs.stdenv.isLinux` and record the reason; do not delete the check.

### M2 — Generalize the finite scan model and add the Kafka reader

This milestone separates the store-neutral evidence state machine from Hasql, extends the
shared descriptors, and adds the reader. At its end a context can write
the following validated query and bind it with `kafkaObservation`:

```haskell
query = do
  bounded <- limits 100 10 1000
  scope <- topicScope "registration.completed.v1"
  eventQuery bounded scope AppendOnlyDuringRun
    (BusinessKeyRecordKey (BusinessKeyName "registrationId"))
    "RegistrationCompleted" decode
```

Refactor `shoko-adapters/src/Shoko/Adapter/EventStore/Internal.hs` so `Reader a` holds the
public `SourceId`, the `EventQuery a`, a `Scanner`, and the `IORef ReaderState`. A `Scanner`
is a record of two IO functions, both receiving the `Clock` and absolute request deadline:
`baselineScan`, which returns the ids to exclude and an
opaque cursor token, and `scan`, which returns a `Scan` of normalized `StoreEvent`s, a
`scannedAll` flag (false when a page or record limit stopped the read), a `historyIntact`
flag (false when the source itself reports deletion), and store-specific public details such
as scanned position bounds. The Kafka scanner owns typed run-local state for the baseline
partition-ID set, each partition's start and greatest observed visible end, and a sticky
history-loss flag; the public token is diagnostic, never parsed back into that state.
Build the PostgreSQL scanner from the existing settings, schema,
and `Fetch` so `snapshot`'s repeatable-read transaction, statement timeout, page progress
check, and `event-baseline-scan-limit` behavior are unchanged, with `historyIntact` always
true. `observeEvents` then becomes store-neutral: it computes fresh and timely ids,
ambiguity at the cutoff, `intact = seen ⊆ ids`, `complete = AppendOnlyDuringRun && scannedAll
&& intact && historyIntact && not ambiguous`, `through = min started cutoff`, and the shared
public flags, appending the scanner's details. Change `StoreEvent.payload` to
`Either Text Value` so a non-JSON Kafka value does not fail an observation unless the record
is a correlated candidate; SQL scanners wrap their JSONB payloads in `Right`. Add an internal
optional normalized record correlation field, separate from execution `correlationId`:
Kafka fills it from the selected record key/header, SQL uses `Nothing`, and shared selection
uses it only for `BusinessKeyRecordKey` and `BusinessKeyHeader`. Preserve the actual
correlation value only in memory; never render it. Select the last header with a given name
(Kafka permits duplicates), for both `event-type` and the configured correlation header,
and test that rule. Emit only the fixed correlation source kind in Kafka public details,
not the configured header name or its contents.

Extend the descriptors. Add `TopicScope !Text` to `EventScope` with
`topicScope :: Text -> Either Text EventScope`, which accepts 1 to 249 ASCII letters, digits,
`.`, `_`, or `-`, rejects `.` and `..`, and rejects names starting with `__` (Kafka internal
topics). Add `BusinessKeyRecordKey !BusinessKeyName` and
`BusinessKeyHeader !BusinessKeyName !Text` to `CorrelationMode`; `eventQuery` rejects empty
key and header names, and `queryRequirement` maps every business-key source to
`RequiresBusinessKey`. In `shoko-core/src/Shoko/Internal/Binding.hs` add
`UnsupportedEventScope !Text` and `UnsupportedCorrelationSource !Text` to
`HandlerBuildError`, encode and decode them in `shoko-core/src/Shoko/Result/Json.hs` beside
`ExecutionMetadataUnsupported`, extend the cause enumeration in
`schemas/run-result-v2.schema.json`, and keep `scripts/check-result-schema.py` passing. Make
`kirokuObservation` return `Either HandlerBuildError (Handler (Kiroku a) (EventEvidence a))`
and have both `kirokuObservation` and `messageDbObservation` return `Left` for a
`TopicScope` or a record-key/header source; the `kiroku` and `messageDb` constructors return
`Left "unsupported-event-scope"` or `Left "unsupported-correlation-source"` for the same
inputs so acquisition can never silently reinterpret them. Update the consumer in
`shoko-adapters/test/EventStore/Contract.hs` and `docs/adapters.md` for the new signature.

Create `shoko-adapters/src/Shoko/Adapter/Kafka.hs` and
`shoko-adapters/src/Shoko/Adapter/Kafka/Evidence.hs` (a re-export of
`Shoko.Adapter.EventStore`, matching the other stores), and list both in the library's
`exposed-modules` in `shoko-adapters/shoko-adapters.cabal`. `KafkaSettings` holds the bootstrap
list and opaque client properties and has no rendering instance. `kafkaSettings` validates a
comma-separated `host:port` list without scheme or credentials, accepts only
`security.protocol`, `sasl.*`, and `ssl.*` extra properties, and rejects observer-controlled
keys (`group.id`, `client.id`, `enable.auto.commit`, `enable.auto.offset.store`,
`enable.partition.eof`, `isolation.level`, `allow.auto.create.topics`). `kafka settings
source query` performs no broker IO; it returns `Left` for a non-topic scope or
`ExecutionMetadata` and otherwise allocates the reader with a Kafka scanner.
`kafkaObservation source query` returns `Either HandlerBuildError (Handler (Kafka a)
(EventEvidence a))` by focusing the shared `readerHandler`, and `observeKafka` exposes the
observation for direct tests.

The client binding of `KafkaPort` (`topicPartitions`, `partitionWatermarks`, and
`readPartition` in `shoko-adapters/src/Shoko/Adapter/Kafka/Internal.hs`) uses
`newAssignedConsumer` and `destroyConsumer` inside `bracket`, with one fresh consumer per
`readPartition` call assigned exactly one partition, and accepts that partition's end only
from an attributed EOF naming it. The whole
baseline or scan shares one deadline, `min requestDeadline (started + budget)`, rather than
receiving a new budget for each partition. Recompute remaining time before metadata,
`partitionWatermarkOffsets`, assignment, and polling; cap each timed foreign call by that
remaining time and polling by 100 milliseconds. A timeout is unavailable evidence, never
EOF. `Clock.bounded` alone cannot guarantee prompt cancellation of foreign calls or masked
cleanup, which is why M1 must prove the complete lifecycle. Install no-op `errorCallback`
and `logCallback` values through `setCallback` before client creation so raw broker
addresses and secrets cannot escape to stderr;
discard raw library error text from return values as well. It fetches `topicMetadata` for the
topic; a missing topic is `kafka-topic-missing`, more than 64 partitions is
`kafka-partition-limit`. Reject topic/partition metadata errors, compare the exact partition-ID
set with the baseline before and after reading, and make `scannedAll` false and
`partitions-stable` false on change. The baseline calls `partitionWatermarkOffsets` for each
partition using `read_committed` and stores the returned visible end (last stable offset)
as that partition's baseline offset. It does not substitute a physical high watermark:
records hidden behind a transaction at capture must still be found after commit. The token
renders those offsets; no ids are excluded because the committed prefix is excluded by
offset. Each scan checks low and visible-end offsets before and after reading and sets a
sticky `historyIntact` false if any low watermark exceeds its baseline offset, any visible
end falls below a previously observed end, or the partition-ID set changes. Once observed,
history loss cannot be cleared by later offset recovery. The scanner assigns exactly one
partition per fresh consumer at its baseline offset and polls to that consumer's EOF;
only EOF from every baseline partition establishes `scannedAll`. Stop early with
`scannedAll` false once a partition yields
`pageSize * pages` records. Records become `StoreEvent`s with identity `<partition>/<offset>`,
event type from the UTF-8 `event-type` header or empty when absent, position equal to the
offset, `recordedAt` from the record timestamp (`NoTimestamp` is
`kafka-record-timestamp-missing`), payload `Right` of the parsed JSON value or `Left` of a
fixed reason, and no causation. Correlation selection runs only for records of the declared
event type: `BusinessKeyRecordKey` reads the key bytes as UTF-8, `BusinessKeyHeader` reads the
named header, and `BusinessKeyField` reads the payload field; a missing or undecodable value
on a declared-type record is unavailable evidence, as it is for the SQL stores, and a record
whose value matches but whose payload decoder fails is unavailable too. Public details are
`scope-kind=topic`, `partition-count`, per-partition `partition-<p>-baseline-offset` and
`partition-<p>-end-offset`, `records-scanned`, `records-without-event-type`,
`records-per-partition-limit`, `partitions-stable`, and `low-watermark-intact`, plus the
shared flags; topic names, keys, headers, and values are never rendered. Unavailable reasons
are fixed texts (`kafka-source-unavailable`, `kafka-source-deadline`, `kafka-topic-missing`,
`kafka-partition-limit`, `kafka-record-timestamp-missing`,
`event-payload-or-correlation-undecodable`, `event-descriptor-mismatch`); raw librdkafka
messages, which may contain broker addresses, are discarded.

Replace the spike groups in `shoko-adapters/test/Kafka/Contract.hs` with the first contract
slice, mirroring `EventStore/Contract.hs`: descriptor mismatches (other limits, scope,
history policy, correlation source, event type) reject before fixtures; a denied environment
never allocates a consumer (count `newAssignedConsumer` calls through the test's acquire
function);
produce then `exactlyOnce` passes across repeated one-record pages with more than one poll;
two distinct records fail cardinality; a complete empty read passes `never` and fails
`eventually`; unrelated keys cannot satisfy the query; a record produced before capture is
excluded; a second independent reader sees identical occurrence ids; and one matching record
per partition on a three-partition topic yields three distinct occurrences. Acceptance:
`just test-kafka` passes this slice and `just test-event-stores` still reports all 19 groups
for both stores.

### M3 — Complete the Kafka contract suite and integrate it into the checks

This milestone finishes the honesty checks and wires the fixture into every gate. Add the
remaining groups: a declared-type record without a key is Unknown and never broadens the
query; an undecodable correlated payload is Unknown and the decoder's secret sentinel never
appears in the result; `limits 1 1 budget` with two records is Unknown rather than complete
history; a record first seen after the cutoff is counted ambiguous and excluded while
`through` equals the cutoff; a read spanning the cutoff under the fake clock keeps a
conservative `through`; `UnverifiedHistory` cannot pass `never` or `exactlyOnce`;
`ExecutionMetadata` is rejected at construction; malformed key/header UTF-8 and duplicate
headers obey the declared correlation rules; Kafka header names/values, bootstrap addresses,
and secret sentinels are absent from both reports and captured process stderr;
`BusinessKeyHeader` and
`BusinessKeyRecordKey` each select exactly one occurrence among records with different keys
across partitions; a bootstrap address pointing at a loopback socket that accepts and never
answers (opened by the test with the `network` package, already in the freeze) returns
unavailable within an 80 millisecond deadline, in under one second, and the accepted
connection reaches end-of-file within one second afterwards, proving the consumer was
released; an unreachable bootstrap is Unknown before any action mutation; after an open
transaction holds a record while a committed record follows it in the same partition, the
first observation reports zero occurrences with complete coverage of the visible state and
the observation after commit reports both without skipping (repeat with the transaction
opened before baseline capture); two empty partitions and one busy partition cannot report
complete until all three finish; a partition added during a read invalidates completeness;
`kafka-delete-records.sh`
truncating a partition past the baseline offset makes `low-watermark-intact` false and
`never` Unknown instead of Pass, with a controlled scanner test proving history loss stays
sticky after apparent offset recovery; and the script's before/after snapshots prove no observer
group, no new topic outside the fixture prefix, and unchanged application offsets.

Add the M1 `test-kafka` recipe to `check` in `justfile`; retain and extend the Cabal and
native Nix wiring already established in M1 (Linux-gated only if M1 recorded a sandbox limitation).
Acceptance: `nix develop --command just check` passes with the new suite listed in its
output, `nix flake check` passes, and the GitHub Actions run on the pushed commit is green.

### M4 — Integrate the contract, documentation, catalogs, and ADRs

This milestone makes the reader selectable by a staging contract and documents it. In
`schemas/workflow-v1.schema.json` add `kafka` to both adapter enumerations. In
`scripts/workflow_contract.py` accept `kafka` as an endpoint scheme (an address such as
`kafka://broker.example.invalid:9092`, credential-free, one bootstrap host), map a `kafka`
source to that scheme, and allow `durable-history` for `kiroku`, `message-db`, and `kafka`.
In `scripts/test-workflow-contract` add a passing case where a `kafka` source on a `kafka://`
endpoint discharges a `durable-history` requirement with `historyPolicy`, and rejection cases
for a `kafka` source on an HTTP endpoint and for a `kafka` source whose adapter is not in
`requiredAdapters`. Leave `integration/examples/workflow.example.json` as the HTTP and
PostgreSQL synthetic example; mention the Kafka adapter in `docs/workflows/first-staging-workflow.md`
where adapters are listed.

Document the reader in `docs/adapters.md` (a "Kafka topic reader" section with the query
example, settings, correlation sources, semantics, limits, and `just test-kafka`), in
`docs/development.md` (the rdkafka shell block, `apacheKafka` in the shell, the Kafka suite,
and the `-threaded` requirement), in `docs/dependencies.md`, in the `README.md` status line,
and in `mori.dhall` (package description and dependencies naming
`shinzui/rdkafka-hs:rdkafka-hs` and `confluentinc/librdkafka:librdkafka`, with matching
`dependencyRefs`). Add `docs/capabilities/bounded-kafka-topic-evidence.md` under the next
free handle (`CAP-13` at this revision) after confirming it with `okf id next`, with
interface `Shoko.Adapter.Kafka`,
evidence `shoko-adapters/test/Kafka/Contract.hs` and `scripts/test-kafka`, and explicit
limits; add its index row and a dated entry in `docs/capabilities/log.md`. Update the
terminology anchors for `durable-history` and `append-only-during-run` to name Kafka
retention and compaction as the deletion hazards; allocate `TERM-50` only if a new term of
art is introduced. Revise ADR 0001 (Kafka client `rdkafka-hs` 1.0.0.1 enabled under the
narrowed exception; selected releases; Redpanda still disabled), ADR 0003 (Kafka visibility bound, last-stable-offset behavior, retention and
compaction under `AppendOnlyDuringRun`), and ADR 0004 (bounded read-only Kafka observation in
scope; destructive consumers still deferred). Acceptance: `just check-docs`, `mori validate`,
`just test-workflow-contract`, and `just check` pass, and `git diff --check` is clean.


## Concrete Steps

All commands run from the repository root. IR-2 and IR-3 are resolved by the
published 1.0.0.1 release; the commands below verify its immutable pin and the
complete client-backed implementation. Discover the dependencies
and the template first. The Mori-registered `rdkafka-hs` checkout may lag the release, so
fetch it, fast-forward it, and refresh the registry before reading it:

```bash
mori registry show shinzui/rdkafka-hs --full
git -C "$(mori path mori://shinzui/rdkafka-hs)" fetch --tags origin
git -C "$(mori path mori://shinzui/rdkafka-hs)" merge --ff-only origin/master
(cd "$(mori path mori://shinzui/rdkafka-hs)" && mori register --local)
mori registry show confluentinc/librdkafka --full
mori registry show shinzui/seihou-modules --full
git ls-remote --tags https://github.com/shinzui/rdkafka-hs 'refs/tags/v1.0.0.1*'
gh release view v1.0.0.1 --repo shinzui/rdkafka-hs
nix flake prefetch github:shinzui/rdkafka-hs/45d9e21ad3c72b56c482173e17ca3fa2bd8b1bc7 --json
```

Expected: the tag listing shows `33e2ab5f31be57e14c9820d4ad99032d3e9b41f1 refs/tags/v1.0.0.1`
and `45d9e21ad3c72b56c482173e17ca3fa2bd8b1bc7 refs/tags/v1.0.0.1^{}`; the release is not a
draft; the prefetch prints the `hash` to copy into `flake.module.nix`.

Enable the client in the managed shell and verify the generated changes:

```bash
seihou run nix-haskell-flake --var nix.kafka=true --dry-run --no-commands
seihou run nix-haskell-flake --var nix.kafka=true --no-commands --save-prompted
seihou diff
git diff --stat -- .seihou/config.dhall nix/haskell.nix flake.lock
```

If `seihou run` refuses because of pending migrations, substitute
`seihou update nix-haskell-flake --var nix.kafka=true --dry-run` and then the same command
without `--dry-run`; a same-version toggle preserves the lock, while an upgrade requires
the managed-pin review described in M1. After the `rdkafka-hs` pin is in `cabal.project`,
`shoko-adapters.cabal`, and `flake.module.nix`, rebuild through both toolchains:

```bash
nix develop --command cabal update
nix develop --command cabal freeze
nix develop --command cabal build all
nix build .#shoko-adapters
```

Run the Kafka fixture and the existing suites:

```bash
nix develop --command just test-kafka
nix develop --command just test-event-stores
nix develop --command just test-adapters
nix develop --command just check
nix develop --command just fmt
```

A passing `just test-kafka` prints, with the port varying per run:

```text
Real kafka: apache-kafka 4.3.1 at 127.0.0.1:<port>
kafka: public runner, finite partition scans, correlation, cardinality, visibility, and group/topic non-interference passed
Accepted real broker: apache-kafka 4.3.1
```

After the documentation and catalog work:

```bash
just check-docs
mori validate
nix develop --command just test-workflow-contract
git diff --check
```

Record only concise acceptance evidence in this plan.


## Validation and Acceptance

Every verdict in the Kafka suite must come from the public core runner, as the existing
event-store suite does, with direct `observeKafka` calls reserved for deadline, cutoff, and
visibility probes. The required behaviors are:

One record matching the selected business key produced after the baseline, in a topic whose
every partition was read to its end, passes `exactlyOnce`; re-reading the same record on later
polls does not increase cardinality; two distinct matching records fail; a missing record with
complete coverage fails `eventually` only after the closing read; an unreachable or silent
broker produces Unknown without retrying any mutation; records with unrelated keys, headers,
or payload fields never satisfy the query; a record produced during the action before the
first poll is found; a committed record hidden behind an open transaction is found after the
transaction commits and is never skipped, including a transaction open at baseline;
a second independent reader reports the same
occurrence ids; a record first observed after the cutoff cannot produce accepted
cardinality; `UnverifiedHistory` yields witnesses but never a passing `never` or
`exactlyOnce`; truncation detected through the low watermark makes coverage incomplete; and
after the whole suite the broker lists no `shoko-observer-` consumer group, no new topic
outside the fixture prefix compared with the warmed-up baseline, and unchanged committed
offsets for the `application-worker` group. Source/API inspection must additionally prove
no group-joining subscription is used; before/after snapshots alone cannot prove that.

The early representative interaction check is the M1 spike: real `rdkafka-hs` against
the real broker, assign-only, before any adapter code exists. Its findings on partition EOF,
watermarks, and read-committed visibility are recorded in Surprises & Discoveries and govern
the M2 design.

This acceptance does not prove staging access-control: read-only enforcement for a staging
observer is a broker ACL contract owned by the environment, recorded as a workflow
prerequisite, because the fixture broker runs without an authorizer. It does not prove Keiro
execution-id propagation, Redpanda compatibility, or detection of compaction, which the topic
owner excludes through `AppendOnlyDuringRun`. Those remain explicit limits in the Kafka
capability record.


## Idempotence and Recovery

`scripts/test-kafka` owns its temporary directory, ports, and broker process; rerunning it
after a failure is safe, `--ignore-formatted` tolerates a reused directory, and the script
stops the broker in a `finally` block. A broker that does not become ready within 120 seconds
fails with the tail of its log retained under `.dev/kafka-tests/` after redacting the
fixture's secret sentinel. The Seihou reconfiguration is previewable with `--dry-run` and
`--diff` and reversible by rerunning with `nix.kafka=false`; never edit `nix/haskell.nix` or
`flake.lock` by hand. Regenerating the freeze file is deterministic for the pinned
`index-state`. The `Internal.hs` refactor is protected by the existing 38 real-store checks:
run `just test-event-stores` after each change to that module before touching Kafka code. If
the Nix sandbox cannot run the JVM broker on one platform, gate the native Kafka step by
platform and record the reason rather than removing the check. If `kafka-delete-records.sh`
or the transactional fixture proves flaky, keep the assertion and stabilize the fixture; do
not weaken coverage semantics to make a test pass.


## Interfaces and Dependencies

Public modules after this plan: `Shoko.Adapter.EventStore` (unchanged exports plus
`topicScope` and the new `CorrelationMode` constructors), `Shoko.Adapter.Kafka`, and
`Shoko.Adapter.Kafka.Evidence`. The intended signatures are:

```haskell
-- Shoko.Adapter.EventStore
data EventScope = StreamScope !Text | CategoryScope !Text | TopicScope !Text
topicScope :: Text -> Either Text EventScope
data CorrelationMode
  = BusinessKeyField !BusinessKeyName
  | BusinessKeyRecordKey !BusinessKeyName
  | BusinessKeyHeader !BusinessKeyName !Text
  | ExecutionMetadata

-- Shoko.Adapter.Kafka
data KafkaSettings                      -- bootstrap list and opaque security properties; no rendering
kafkaSettings :: Text -> Map Text Text -> Either Text KafkaSettings
data Kafka a                            -- abstract; wraps the shared internal reader
kafka :: KafkaSettings -> SourceId -> EventQuery a -> IO (Either Text (Kafka a))
kafkaObservation :: SourceId -> EventQuery a -> Either HandlerBuildError (Handler (Kafka a) (EventEvidence a))
observeKafka :: CallContext -> Kafka a -> IO (ObservationOutcome (EventEvidence a))

-- Shoko.Adapter.Kiroku (signature change)
kirokuObservation :: SourceId -> EventQuery a -> Either HandlerBuildError (Handler (Kiroku a) (EventEvidence a))

-- Shoko.Binding (new causes)
data HandlerBuildError
  = EndpointNotAllowlisted !Text | ObservationMethodNotGet !Text | ObservationScopeMissing !Text
  | ExecutionMetadataUnsupported | UnsupportedEventScope !Text | UnsupportedCorrelationSource !Text
```

For Kafka, `limits pageSize pages budget` bounds each scan to `pageSize * pages` records per
partition and `budget` milliseconds per request; at most 64 partitions are supported. The
`SourceId` names one topic, decoder, and correlation source, as for the other stores, and the
same `EventQuery` value must be used for allocation and handler construction because decoder
functions cannot be compared.

Scripts and environment: `scripts/test-kafka` (owned broker, before/after snapshots,
`--binaries`), which passes `SHOKO_KAFKA_BOOTSTRAP` and `SHOKO_KAFKA_LOG_DIR` to the
`kafka-adapter-test` suite; `just test-kafka`; `flake.module.nix` adds `pkgs.apacheKafka` to
the dev shell and the adapter derivation.

Dependencies: the Kafka client is `rdkafka-hs` 1.0.0.1
(`mori://shinzui/rdkafka-hs/packages/rdkafka-hs`), the maintained successor of the
`mori://shinzui/hw-kafka-client` fork, which completed
[IR-2](mori://shinzui/rdkafka-hs/okf/improvement-requests/concepts/IR-2). It is consumed as
the commit `45d9e21ad3c72b56c482173e17ca3fa2bd8b1bc7` (annotated tag `v1.0.0.1`, tag object
`33e2ab5f31be57e14c9820d4ad99032d3e9b41f1`, GitHub release of 2026-10-23) through the
`source-repository-package` stanza and the `fetchFromGitHub`/`callCabal2nix` override given
in M1, with `rdkafka-hs >=1.0.0.1 && <1.1` bounds; it is not on Hackage. API evidence for the
observer contract: `newAssignedConsumer` (never subscribes; `AssignOnlyTest`),
`pollMessageAttributed` with `ConsumerMessageError` (partition-attributed EOF;
`AttributedErrorTest`), `destroyConsumer` (synchronous, exactly-once destroy with sockets
closed on return; `DestroyTest`), and `partitionWatermarkOffsets` under `read_committed`
stopping at the last stable offset (`ReadCommittedTest`), all under the release's
`test-integration/Kafka/Integration/` and passing in both callback poll modes. The M1 pin is now present and the fixed header-order spike passes. Hackage `hw-kafka-client` 5.3.0 remains
only the reproduction baseline; its `>=5.3 && <5.4` bound is not approved for the observer.
The native dependency is librdkafka 2.15.0
(`mori://confluentinc/librdkafka/packages/librdkafka`, supplied by the pinned Nixpkgs through
the Seihou `nix.kafka` option; `rdkafka-hs` refuses anything older than 2.15 at build time),
the `c2hs` 0.28.8 build tool from the same Nixpkgs, Apache Kafka 2.13-4.3.1 with JRE 17.0.19
as a development and test tool only (`pkgs.apacheKafka`; Mori has no registered project, so
the Nixpkgs attribute is the reference), and the already frozen `network` 3.2.9.0 and
`process` 1.6.26.1 for test fixtures. Core gains two `HandlerBuildError` constructors and
their codec and schema entries.

Release evidence checked on 2026-10-21: the
[Hackage release listing](https://hackage.haskell.org/package/hw-kafka-client/preferred.json)
and [5.3.0 source archive](https://hackage.haskell.org/package/hw-kafka-client-5.3.0/hw-kafka-client-5.3.0.tar.gz)
were compared with upstream tags. Checked on 2026-10-22: `git ls-remote --tags
https://github.com/shinzui/rdkafka-hs` lists `refs/tags/v1.0.0.0` at
`e499013e3a8a84328834bb0b0755332263c4cdee` peeling to
`63031a21d070819fe89afbacb6ce76238816748f`; `rdkafka-hs.cabal` at that commit declares
`version: 1.0.0.0`; and https://hackage.haskell.org/package/rdkafka-hs/preferred.json
returns 404. Apache Kafka tag 4.3.1 peels to `26b251a451ce941d3d7a55e6487bcb7f16b5ad48`.
Re-run the tag check when pinning; the package-set versions above describe the current
lock, not a guarantee after a Seihou upgrade.

Prerequisites: `docs/plans/3-implement-inspectable-scenarios-and-the-bounded-verification-runner.md`,
`docs/plans/4-implement-postgresql-and-http-evidence-bindings.md`, and
`docs/plans/5-implement-kiroku-and-message-db-evidence-bindings.md` are Complete, and
`docs/plans/8-compose-verifications-from-reusable-scenario-vocabulary-and-binding-blocks.md`
supplied the handler constructors this plan extends. This plan owns `Shoko.Adapter.Kafka*`,
`shoko-adapters/test/Kafka/`, `scripts/test-kafka`, the Kafka sections of the guides, and
the Kafka capability record; it extends `Shoko.Adapter.EventStore.Internal`,
`shoko-adapters.cabal`,
`flake.module.nix`, `justfile`, and the workflow schema and validator, whose registration
example stays unchanged. The staging host that selects this reader, its topic names, ACL
credentials, and append-only promise belong to the bounded context and the environment owner.

Revision 2026-10-21: validated the plan against the working tree, local ADRs, Mori-discovered
sources, and the actual released client. Recorded construction and teardown blockers;
corrected partition EOF attribution, committed-visible baselines, persistent history-loss
state, secret-safe diagnostics, fixture readiness and offset snapshots, and M1 build wiring.
The four implementation milestones remain incomplete; this revision changes only the plan.

Revision 2026-10-22: the client blocker is resolved. The owner's fork shipped as the
successor package `rdkafka-hs` 1.0.0.0 (tag `v1.0.0.0`, commit `63031a2…`), not as a tagged
`shinzui/hw-kafka-client` commit, and IR-2 is completed there. This revision replaces the
client selection with that pin (a commit-pinned `source-repository-package` stanza plus a
`fetchFromGitHub`/`callCabal2nix` Nix override), names the released observer API
(`newAssignedConsumer`, `pollMessageAttributed`, `destroyConsumer`,
`partitionWatermarkOffsets`), drops the 5.3.0 reproducer and the anonymous-EOF workaround
rationale, adds `c2hs` to the toolchain, moves the Kafka capability to the next free handle
(CAP-12), brings the repository orientation up to date, and schedules the refresh of the
four documents that still name the old fork. Milestones are unchanged and remain open.

Revision 2026-10-23: implemented the M1 pin, Seihou-managed toolchain upgrade,
and real-client spike. Recorded the released header-order defect as IR-3, kept
all milestones open behind the existing M1 gate, refreshed dependency/host
documentation and ADR 0001, corrected the network compatibility floor and freeze
behavior, and noted CAP-13 as the next free handle. Acceptance is unchanged.

Revision 2026-10-24: resumed after the published 1.0.0.1 header-order fix, advanced
the Cabal/Nix pins, implemented the assign-only client port and public constructor,
added real adapter contracts, persisted losses across failed scans, and finished
the Kafka capability and dependency/host documentation. Acceptance is unchanged.
