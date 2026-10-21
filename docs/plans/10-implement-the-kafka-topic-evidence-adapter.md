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
run. The reader never joins an application's consumer group, never commits offsets, never
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

- [ ] M1 — Toolchain and broker fixture accepted: librdkafka is in the Seihou-managed dev
  shell, released `hw-kafka-client` 5.3.0 is selected in Cabal and Nix, `scripts/test-kafka`
  boots an owned KRaft broker, and the spike checks prove assign-based reading without
  subscription, partition-EOF detection, watermark offsets, header/key/timestamp decoding,
  read-committed visibility, and zero observer groups, both locally and in `nix flake check`
  on Linux CI.
- [ ] M2 — Store-neutral scan refactor and Kafka reader: the shared finite-scan state
  machine is separated from Hasql, `TopicScope` and record-key/header correlation sources
  exist, `Shoko.Adapter.Kafka` passes the first contract slice (descriptor mismatch, denied
  policy before allocation, produce → exactlyOnce over repeated pages, cardinality, empty
  scans, unrelated keys, pre-baseline exclusion, independent readers, three partitions), and
  all 36 existing Kiroku/Message DB checks still pass.
- [ ] M3 — Complete Kafka contract suite integrated into `just check` and the native Nix
  check: missing/undecodable correlation, page exhaustion, cutoff ambiguity, crossing reads,
  unverified history, deadline with consumer release, outage before mutation, transactional
  visibility, truncation detection, and group/topic/offset non-interference all pass; CI is
  green.
- [ ] M4 — Contract, documentation, and catalog integration: the workflow schema and offline
  validator accept a `kafka` adapter and `kafka://` endpoints with tests; `docs/adapters.md`,
  `docs/development.md`, `docs/dependencies.md`, `README.md`, and `mori.dhall` describe the
  reader; CAP-11 is recorded; ADR 0001, 0003, and 0004 carry the durable decisions; `just
  check-docs` passes.


## Surprises & Discoveries

(None yet.)


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
  shape the research record attributed to shibuya's side-car consumers.
  Date: 2026-10-21

- Decision: Every poll re-reads each partition from its baseline offset to its end instead of
  advancing a forward cursor.
  Rationale: this keeps the shared `seen ⊆ ids` intactness check and occurrence deduplication
  identical to the SQL readers, makes retention deletions observable, and is bounded by the
  query's limits; the cost is proportional to records produced during the finite run.
  Date: 2026-10-21

- Decision: Select released `hw-kafka-client` 5.3.0 from Hackage, provided by the managed Nix
  package set, with librdkafka 2.15.0 from the pinned Nixpkgs; do not depend on the
  `mori://shinzui/hw-kafka-client` fork.
  Rationale: the fork's fix concerns `CallbackPollModeAsync`, which the synchronous observer
  does not use, and ADR 0001 forbids unpublished dependencies.
  Date: 2026-10-21

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
  Rationale: no TAN service propagates a Shōko execution ID into Kafka envelopes (Keiro IR-52
  is open), and the legacy `correlation-id` header carries a Message DB message id, not a run
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


## Outcomes & Retrospective

(To be filled during and after implementation.)


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

The shared contract suite is `shoko-adapters/test/EventStore/Contract.hs` (18 groups per
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

There is no Kafka code. `.seihou/config.dhall` records `nix.kafka = "false"` and
`nix.redpanda = "false"`, so the dev shell has no librdkafka. `flake.nix` already declares
the module-owned `redpanda-container` input, unused while the option is off.
`schemas/workflow-v1.schema.json` enumerates `http`, `postgresql`, `kiroku`, and `message-db`
for `requiredAdapters` and `source.adapter`; `scripts/workflow_contract.py` accepts only
`http`, `https`, and `postgresql` endpoint schemes and ties `durable-history` coverage to
Kiroku or Message DB. The capability catalog's next free handle is `CAP-11` (checked with
`okf id next docs/capabilities --profile docs/capabilities/profile.dhall CAP`), and the
terminology catalog's is `TERM-50`.

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

The Kafka client is [hw-kafka-client](mori://haskell-works/hw-kafka-client/packages/hw-kafka-client),
whose [consumer guide](mori://haskell-works/hw-kafka-client/docs/consumer-best-practices) and
source were inspected. The relevant API is `Kafka.Consumer` (`newConsumer`, `assign`,
`pollMessage`, `closeConsumer`, `ConsumerRecord` with `crTopic`, `crPartition`, `crOffset`,
`crTimestamp`, `crHeaders`, `crKey`, `crValue`), `Kafka.Consumer.ConsumerProperties`
(`brokersList`, `groupId`, `noAutoCommit`, `noAutoOffsetStore`, `extraProp`, `clientId`,
`callbackPollMode`), `Kafka.Metadata` (`topicMetadata`, `watermarkOffsets`), `Kafka.Producer`
and `Kafka.Transaction` for fixtures, and `Kafka.Types` (`TopicName`, `PartitionId`, `Offset`,
`Timeout`, `Headers`, `headersToList`, `KafkaError`). Hackage lists 5.3.0 as the latest
release (uploaded 2023-08-05); it links `-lrdkafka`. The C library is
[librdkafka](mori://confluentinc/librdkafka); its `CONFIGURATION.md` documents the consumer
defaults used below (`allow.auto.create.topics` false for consumers, `isolation.level`
`read_committed`, `enable.partition.eof` false, `enable.auto.commit` true), and
`src/rdkafka.c` creates the consumer group handle only when `group.id` is non-empty. The
pinned Nixpkgs revision `d5dfd8e6716dde34398bc14bc87c10dece9c8c68` provides
`haskell.packages.ghc9124.hw-kafka-client` 5.3.0 (not broken; Linux and Apple Silicon),
`rdkafka` 2.15.0, and `apacheKafka` 2.13-4.3.1 with JRE 17.0.19; it has no Redpanda server.

The dev-shell toggle is documented by the
[Seihou nix-haskell-flake template](mori://shinzui/seihou-modules/templates/nix-haskell-flake):
`nix.kafka=true` adds `pkgs.rdkafka` and `pkgs.rdkafka.dev` to the generated shell and exports
`CPATH`, `LIBRARY_PATH`, and `PKG_CONFIG_PATH` so GHC links `-lrdkafka`. The installed module
version is 0.31.0 (`docs/development.md`); the registry has moved on, so reconfiguration may
involve an update.

The first real topic is `registration.completed.v1`, published by
[registration-service-v2](mori://tan/registration-service-v2) (project-relative
`registration-service-v2/src/RegistrationServiceV2/Completion/Publisher.hs`; artifact-level
URI pending) and consumed by [mls-service-v2](mori://tan/mls-service-v2) (project-relative
`mls-service-v2-core/src/MlsService/Kafka/RegistrationCompleted/Inbound.hs` and
`MlsService/Kafka/Envelope.hs`). The record key is the `registrationId` text, the value is a
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
sandbox. At its end the dev shell links `hw-kafka-client`, `scripts/test-kafka` owns a broker,
and a small spike suite documents how librdkafka behaves for an assign-only observer.

Enable the client library through Seihou rather than by editing generated files. From the
repository root run `seihou run nix-haskell-flake --var nix.kafka=true --dry-run --no-commands`
and read the plan. If Seihou refuses because the installed module advanced past the recorded
0.31.0 and ships migrations, use `seihou update nix-haskell-flake --var nix.kafka=true
--dry-run` instead, inspect the generated changes, and apply without `--dry-run`. Either path
must leave `nix.redpanda` false, update `.seihou/config.dhall`, regenerate `nix/haskell.nix`
with the rdkafka block and shell exports, and keep `flake.lock` unchanged; run `seihou diff`
afterwards and record the resulting module version in `docs/development.md`. Add
`pkgs.apacheKafka` to `haskellProject.extraDevPackages` in `flake.module.nix` so
`kafka-storage.sh`, `kafka-server-start.sh`, `kafka-topics.sh`, `kafka-consumer-groups.sh`,
`kafka-console-producer.sh`, `kafka-console-consumer.sh`, and `kafka-delete-records.sh` are
on the dev-shell `PATH`.

Select the dependency per ADR 0001. Confirm the Hackage release listing and the upstream
`v5.3.0` tag revision (`git ls-remote --tags https://github.com/haskell-works/hw-kafka-client`),
add `hw-kafka-client == 5.3.0` to the `constraints` block of `cabal.project`, add
`hw-kafka-client >=5.3 && <5.4` to the `shoko-adapters` library `build-depends`, regenerate
`cabal.project.freeze` with `nix develop --command cabal freeze` after `cabal update`, and
confirm the Nix build takes the same 5.3.0 from the managed set without `callHackageDirect`.
Record release, upload date, upstream revision, librdkafka 2.15.0, and Apache Kafka 4.3.1
with JRE 17.0.19 in `docs/dependencies.md`. Note in that file that `hw-kafka-client` requires
`-threaded` executables for its callback machinery; all adapter test suites already pass
`-threaded`, and the scenario-host guide must tell hosts the same.

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
`kafka-server-start.sh`, waits up to 120 seconds for a TCP connection to the broker port, and
always binds and advertises `127.0.0.1` rather than `localhost`, because librdkafka resolves
`localhost` to `::1` first. It then seeds a fixture application group: creates topic
`application-events`, produces one record with `kafka-console-producer.sh`, and consumes it
with `kafka-console-consumer.sh --group application-worker --from-beginning --max-messages 1`
so that group has a committed offset. It snapshots `kafka-consumer-groups.sh --list`,
`kafka-topics.sh --list`, and `kafka-consumer-groups.sh --describe --group application-worker`,
runs the suite with `SHOKO_KAFKA_BOOTSTRAP=127.0.0.1:<broker>` and `SHOKO_KAFKA_LOG_DIR` set,
snapshots again, fails if any `shoko-observer-` group appeared, if the topic list changed
other than topics the suite names with its `fixture-` prefix, or if the application group's
offsets changed, and finally stops the broker and removes the directory. Sanitized failure
output goes under `.dev/kafka-tests/`. `--binaries dist/build` runs compiled test binaries
exactly as `test-event-stores` does.

Add the `kafka-adapter-test` suite (`shoko-adapters/test/KafkaMain.hs` and
`shoko-adapters/test/Kafka/Contract.hs`) and start it with the spike groups, written directly
against `hw-kafka-client` because the adapter does not exist yet. The suite creates one fresh
topic per test with `kafka-topics.sh --create --topic fixture-<unique> --partitions N`
through `System.Process` (the 5.3.0 release has no admin module), using the `LOG_DIR` the
script supplied. The spike must establish, with evidence recorded in Surprises & Discoveries:
that a consumer built with `brokersList`, `groupId (ConsumerGroupId "shoko-observer-<uuid>")`,
`noAutoCommit`, `noAutoOffsetStore`, `extraProp "enable.partition.eof" "true"`,
`extraProp "allow.auto.create.topics" "false"`, `extraProp "isolation.level" "read_committed"`,
`callbackPollMode CallbackPollModeSync`, and an empty `topics []` subscription can `assign`
explicit partition offsets, `pollMessage` with a 100 millisecond `Timeout` until each
partition reports `KafkaResponseError RdKafkaRespErrPartitionEof`, and read key, headers,
value, and `CreateTime`/`LogAppendTime` timestamps; that `watermarkOffsets` returns low and
high offsets per partition; that after `closeConsumer` the broker lists no
`shoko-observer-` group; that assigning a nonexistent topic yields an error rather than a
created topic; and that with an open transaction holding a record in a partition, a later
committed record in the same partition is invisible to a `read_committed` consumer until the
transaction commits, after which both appear at their original offsets. The fallback if
assign-only reading proves impossible is `subscribe` with the run-unique group and a
documented proof that the group disappears after close; record whichever applies.

Acceptance: `nix develop --command just test-kafka` passes locally on macOS; `nix flake
check` builds the adapter derivation with the Kafka script in its `checkPhase` on Linux CI.
If the Nix sandbox on macOS cannot run the JVM broker, gate that native step on Linux with
`pkgs.stdenv.isLinux` and record the reason; do not delete the check.

### M2 — Generalize the finite scan model and add the Kafka reader

This milestone separates the store-neutral evidence state machine from Hasql, extends the
shared descriptors, and adds the reader. At its end a context can write
`eventQuery bounded (topicScope "registration.completed.v1") AppendOnlyDuringRun
(BusinessKeyRecordKey (BusinessKeyName "registrationId")) "RegistrationCompleted" decode`
and bind it with `kafkaObservation`.

Refactor `shoko-adapters/src/Shoko/Adapter/EventStore/Internal.hs` so `Reader a` holds the
public `SourceId`, the `EventQuery a`, a `Scanner`, and the `IORef ReaderState`. A `Scanner`
is a record of two IO functions: `baselineScan`, which returns the ids to exclude and an
opaque cursor token, and `scan`, which returns a `Scan` of normalized `StoreEvent`s, a
`scannedAll` flag (false when a page or record limit stopped the read), a `historyIntact`
flag (false when the source itself reports deletion), and store-specific public details such
as scanned position bounds. Build the PostgreSQL scanner from the existing settings, schema,
and `Fetch` so `snapshot`'s repeatable-read transaction, statement timeout, page progress
check, and `event-baseline-scan-limit` behavior are unchanged, with `historyIntact` always
true. `observeEvents` then becomes store-neutral: it computes fresh and timely ids,
ambiguity at the cutoff, `intact = seen ⊆ ids`, `complete = AppendOnlyDuringRun && scannedAll
&& intact && historyIntact && not ambiguous`, `through = min started cutoff`, and the shared
public flags, appending the scanner's details. Change `StoreEvent.payload` to
`Either Text Value` so a non-JSON Kafka value does not fail an observation unless the record
is a correlated candidate; SQL scanners wrap their JSONB payloads in `Right`.

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
`Shoko.Adapter.EventStore`, matching the other stores). `KafkaSettings` holds the bootstrap
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

The Kafka scanner opens a fresh consumer per baseline and per scan inside `bracket`
(`newConsumer`/`closeConsumer`), under the clock's `bound` with the request budget from
`Limits` and the remaining deadline, and with poll timeouts of at most 100 milliseconds so a
blocking foreign call returns promptly for cancellation. It fetches `topicMetadata` for the
topic; a missing topic is `kafka-topic-missing`, more than 64 partitions is
`kafka-partition-limit`, and a partition count differing from the baseline's makes
`scannedAll` false and sets a `partitions-stable` flag to false. The baseline reads
`watermarkOffsets` for each partition and stores the high watermark as that partition's
baseline offset; the cursor token renders those offsets; no ids are excluded because records
before the baseline are excluded by offset. Each scan reads `watermarkOffsets` again and sets
`historyIntact` false if any low watermark exceeds its baseline offset (retention or
truncation removed records inside the window) or any high watermark fell below a previously
observed end; it then `assign`s every partition at its baseline offset and polls until each
reports partition EOF, stopping early with `scannedAll` false once a partition yields
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
never allocates a consumer (count `newConsumer` calls through the test's acquire function);
produce then `exactlyOnce` passes across repeated one-record pages with more than one poll;
two distinct records fail cardinality; a complete empty read passes `never` and fails
`eventually`; unrelated keys cannot satisfy the query; a record produced before capture is
excluded; a second independent reader sees identical occurrence ids; and one matching record
per partition on a three-partition topic yields three distinct occurrences. Acceptance:
`just test-kafka` passes this slice and `just test-event-stores` still reports all 18 groups
for both stores.

### M3 — Complete the Kafka contract suite and integrate it into the checks

This milestone finishes the honesty checks and wires the fixture into every gate. Add the
remaining groups: a declared-type record without a key is Unknown and never broadens the
query; an undecodable correlated payload is Unknown and the decoder's secret sentinel never
appears in the result; `limits 1 1 budget` with two records is Unknown rather than complete
history; a record first seen after the cutoff is counted ambiguous and excluded while
`through` equals the cutoff; a read spanning the cutoff under the fake clock keeps a
conservative `through`; `UnverifiedHistory` cannot pass `never` or `exactlyOnce`;
`ExecutionMetadata` is rejected at construction; `BusinessKeyHeader` and
`BusinessKeyRecordKey` each select exactly one occurrence among records with different keys
across partitions; a bootstrap address pointing at a loopback socket that accepts and never
answers (opened by the test with the `network` package, already in the freeze) returns
unavailable within an 80 millisecond deadline, in under one second, and the accepted
connection reaches end-of-file within one second afterwards, proving the consumer was
released; an unreachable bootstrap is Unknown before any action mutation; after an open
transaction holds a record while a committed record follows it in the same partition, the
first observation reports zero occurrences with complete coverage of the visible state and
the observation after commit reports both without skipping; `kafka-delete-records.sh`
truncating a partition past the baseline offset makes `low-watermark-intact` false and
`never` Unknown instead of Pass; and the script's before/after snapshots prove no observer
group, no new topic outside the fixture prefix, and unchanged application offsets.

Add `test-kafka` to `justfile` and to the `check` recipe, add the suite to
`shoko-adapters/shoko-adapters.cabal` with `hw-kafka-client`, `aeson`, `network`, `process`,
`time`, and `uuid` test dependencies, and in `flake.module.nix` add `pkgs.apacheKafka` to the
adapter derivation's `nativeBuildInputs` and `python ${./scripts/test-kafka} --binaries
dist/build` to its `checkPhase` (Linux-gated only if M1 recorded a sandbox limitation).
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
`haskell-works/hw-kafka-client:hw-kafka-client` and `confluentinc/librdkafka:librdkafka`, with
matching `dependencyRefs`). Add `docs/capabilities/bounded-kafka-topic-evidence.md` as
CAP-11 after confirming the handle with `okf id next`, with interface `Shoko.Adapter.Kafka`,
evidence `shoko-adapters/test/Kafka/Contract.hs` and `scripts/test-kafka`, and explicit
limits; add its index row and a dated entry in `docs/capabilities/log.md`. Update the
terminology anchors for `durable-history` and `append-only-during-run` to name Kafka
retention and compaction as the deletion hazards; allocate `TERM-50` only if a new term of
art is introduced. Revise ADR 0001 (Kafka client enabled; selected releases; Redpanda still
disabled), ADR 0003 (Kafka visibility bound, last-stable-offset behavior, retention and
compaction under `AppendOnlyDuringRun`), and ADR 0004 (bounded read-only Kafka observation in
scope; destructive consumers still deferred). Acceptance: `just check-docs`, `mori validate`,
`just test-workflow-contract`, and `just check` pass, and `git diff --check` is clean.


## Concrete Steps

All commands run from the repository root. Discover the dependencies and the template first:

```bash
mori registry show haskell-works/hw-kafka-client --full
mori registry docs haskell-works/hw-kafka-client
mori registry show confluentinc/librdkafka --full
mori registry show shinzui/seihou-modules --full
curl -sS https://hackage.haskell.org/package/hw-kafka-client/preferred.json
git ls-remote --tags https://github.com/haskell-works/hw-kafka-client | grep 'v5.3.0'
```

Enable the client in the managed shell and verify the generated changes:

```bash
seihou run nix-haskell-flake --var nix.kafka=true --dry-run --no-commands
seihou run nix-haskell-flake --var nix.kafka=true --no-commands --save-prompted
seihou diff
git diff --stat -- .seihou/config.dhall nix/haskell.nix flake.lock
```

If `seihou run` refuses because of pending migrations, substitute
`seihou update nix-haskell-flake --var nix.kafka=true --dry-run` and then the same command
without `--dry-run`; `flake.lock` must stay unchanged in either case. Then select the
dependency and rebuild:

```bash
nix develop --command cabal update
nix develop --command cabal freeze
nix develop --command cabal build all
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
Real kafka: apache-kafka 4.3.1 at 127.0.0.1:<port> (nixpkgs d5dfd8e6716dde34398bc14bc87c10dece9c8c68)
kafka: public runner, finite partition scans, correlation, cardinality, visibility, and group/topic non-interference passed
Accepted real broker: apache-kafka 4.3.1
```

After the documentation and catalog work:

```bash
just check-docs
mori validate
python3 scripts/test-workflow-contract
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
transaction commits and is never skipped; a second independent reader reports the same
occurrence ids; a record first observed after the cutoff cannot produce accepted
cardinality; `UnverifiedHistory` yields witnesses but never a passing `never` or
`exactlyOnce`; truncation detected through the low watermark makes coverage incomplete; and
after the whole suite the broker lists no `shoko-observer-` consumer group, no topic outside
the fixture prefix, and unchanged committed offsets for the `application-worker` group.

The early representative interaction check is the M1 spike: real `hw-kafka-client` against
the real broker, assign-only, before any adapter code exists. Its findings on partition EOF,
watermarks, and read-committed visibility are recorded in Surprises & Discoveries and govern
the M2 design.

This acceptance does not prove staging access-control: read-only enforcement for a staging
observer is a broker ACL contract owned by the environment, recorded as a workflow
prerequisite, because the fixture broker runs without an authorizer. It does not prove Keiro
execution-id propagation, Redpanda compatibility, or detection of compaction, which the topic
owner excludes through `AppendOnlyDuringRun`. Those remain explicit limits in CAP-11.


## Idempotence and Recovery

`scripts/test-kafka` owns its temporary directory, ports, and broker process; rerunning it
after a failure is safe, `--ignore-formatted` tolerates a reused directory, and the script
stops the broker in a `finally` block. A broker that does not become ready within 120 seconds
fails with the tail of its log retained under `.dev/kafka-tests/` after redacting the
fixture's secret sentinel. The Seihou reconfiguration is previewable with `--dry-run` and
`--diff` and reversible by rerunning with `nix.kafka=false`; never edit `nix/haskell.nix` or
`flake.lock` by hand. Regenerating the freeze file is deterministic for the pinned
`index-state`. The `Internal.hs` refactor is protected by the existing 36 real-store checks:
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

Dependencies: `hw-kafka-client` 5.3.0 (`mori://haskell-works/hw-kafka-client/packages/hw-kafka-client`,
library bound `>=5.3 && <5.4`, frozen at 5.3.0), librdkafka 2.15.0
(`mori://confluentinc/librdkafka`, supplied by the pinned Nixpkgs through the Seihou
`nix.kafka` option), Apache Kafka 2.13-4.3.1 with JRE 17.0.19 as a development and test tool
only (`pkgs.apacheKafka`; Mori has no registered project, so the Nixpkgs attribute is the
reference), and the already frozen `network` 3.2.9.0 and `process` 1.6.26.1 for test fixtures.
Core gains two `HandlerBuildError` constructors and their codec and schema entries.

Prerequisites: `docs/plans/3-implement-inspectable-scenarios-and-the-bounded-verification-runner.md`,
`docs/plans/4-implement-postgresql-and-http-evidence-bindings.md`, and
`docs/plans/5-implement-kiroku-and-message-db-evidence-bindings.md` are Complete, and
`docs/plans/8-compose-verifications-from-reusable-scenario-vocabulary-and-binding-blocks.md`
supplied the handler constructors this plan extends. This plan owns `Shoko.Adapter.Kafka*`,
`shoko-adapters/test/Kafka/`, `scripts/test-kafka`, the Kafka sections of the guides, and
CAP-11; it extends `Shoko.Adapter.EventStore.Internal`, `shoko-adapters.cabal`,
`flake.module.nix`, `justfile`, and the workflow schema and validator, whose registration
example stays unchanged. The staging host that selects this reader, its topic names, ACL
credentials, and append-only promise belong to the bounded context and the environment owner.
