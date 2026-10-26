---
id: 12
slug: add-a-redis-evidence-adapter-using-hedis
title: "Add a Redis evidence adapter using Hedis"
kind: exec-plan
created_at: 2026-10-26T14:56:29Z
intention: "intention_01m5wb8reveq6rzgxcxzn3kmnd"
provenance:
  created_by:
    model: "gpt-6-astra"
    harness: "codex-cli"
    at: 2026-10-26T14:56:29Z
  reviews:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-26T22:20:12Z
      verdict: "changes-requested"
      note: "Initial review: reject silently ignored authentication/TLS settings; specify runtime key-limit failures and opaque module ownership; cover TLS lifecycle before claiming support."
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-26T22:22:56Z
      verdict: "approved"
      note: "Re-review after update: configuration, key-limit and module ownership findings resolved; bounded plain/TLS release remains an explicit implementation gate. Documentation, local links and fence checks pass."
  revisions:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-26T22:20:12Z
      mode: "update"
      note: "Apply review corrections to connection validation, bounded keys, internal module ownership, and TLS lifecycle acceptance."
---

# Add a Redis evidence adapter using Hedis

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record implementation friction using `agents/skills/exec-plan/FRICTION.md`.


## Purpose / Big Picture

Let a context-owned Shōko scenario verify Redis-backed application state using Hedis:
whether its correlated key exists, whether it is absent, and whether its string value
matches the scenario's expectation. The adapter supplies ordinary Shōko observation
handlers, so inspection, policy rejection, deadlines, and private result handling work
the same way as existing PostgreSQL observations.

The demonstration is a compiled test consumer that writes a uniquely identified cache
entry through its own application fixture, then observes that entry through the public
adapter and `runScenario`. A matching value passes, a conclusive mismatch fails after
the observation window, and an unavailable Redis server yields Unknown. Run this and
the failure controls with the new `nix develop --command just test-redis` target.

This first adapter reads one explicitly scoped key at a time on a standalone Redis
endpoint. It provides sampled state: evidence about the reads actually performed,
not a history of everything that happened between reads. Redis writes, arbitrary
commands or Lua, hashes/collections, Pub/Sub, Streams, cluster discovery, and Sentinel
failover are outside this plan. Test setup may write its own isolated server; the
adapter itself has no mutation interface. No production domain vocabulary, deployed
staging acceptance, or result-schema change is required. There is no parent MasterPlan.


## Progress

- [ ] M1 — A public-runner consumer observes a real Redis string through Hedis, with
  Pass, mismatch Fail, and unavailable-source Unknown controls in `just test-redis`.
- [ ] M2 — Scoped existence, absence, and bounded binary string reads distinguish
  missing, empty, wrong-type, and oversized values; policy and privacy controls pass.
- [ ] M3 — Deadline, cancellation, concurrent observation, and sampled-coverage
  controls pass against owned real sockets without leaking connections or evidence.
- [ ] M4 — Redis checks run through Cabal, the native Nix adapter check, and normal
  CI; documentation, dependency evidence, capability catalog, and ADRs describe the
  validated public contract.

Planning is complete; implementation has not started. The intention in frontmatter
was created with `mina ci --json 'Add a Redis adapter using Hedis'` at the user's request.


## Surprises & Discoveries

2026-10-26 review: released Hedis 0.16.4 authenticates only when `connectAuth`
is present, even if `connectUsername` is set. It also applies TLS only to a
host/port endpoint; a Unix-socket endpoint with TLS parameters silently uses a
plain handle. Reject these ambiguous configurations before IO. Evidence is in
`createConnection` and `ConnectionContext.connect` under
[the Hedis repository](mori://informatikr/hedis/repos/hedis), at the release commit
recorded below (source-file artifact URIs are pending).

The same release closes plain handles under `uninterruptibleMask_`, and TLS
release calls `TLS.bye` before closing the context and handle. Wrapping the call
in `Clock.bounded` alone does not prove bounded teardown; the lifecycle controls
must exercise pending output and TLS shutdown as well as blocked reads.


## Decision Log

2026-10-26: Add read-only sampled-state observations inside `shoko-adapters`, following
the existing PostgreSQL boundary. A Redis key is mutable and may expire or be evicted;
observing it repeatedly cannot prove continuous absence or exactly-once occurrence.
The initial operation set is existence, absence, and bounded string value retrieval.

2026-10-26: Require a named business-key scope, construct one exact Redis key from
fixed prefix/suffix bytes and the selected business-key value, and expose no scan or
raw-command escape hatch. This makes the selected correlation part of both pure
handler metadata and runtime dispatch.

2026-10-26: Use released Hedis 0.16.4 with component bounds `>=0.16.4 && <0.17`,
subject to the normal build proof, and keep it out of `shoko-core`. Own a fresh Hedis
connection pool for each sample, closing it before the call returns. This favors
simple cancellation and transaction isolation over persistent-pool throughput.

2026-10-26: Bound string transfer with `GETRANGE key 0 limit`, requesting one byte
beyond the permitted value size, paired with `EXISTS` in a read-only `MULTI`/`EXEC`
transaction. The pair distinguishes a missing key from an existing empty string
without an unbounded `GET`. Transaction failure is unavailable evidence. Do not
silently fall back to separate, racing reads if the deployment denies transactions.

2026-10-26 review revision: reject username-without-password and TLS-on-Unix-socket
configuration, define a separate runtime key-limit failure, and keep shared query
constructors in a non-exposed internal module. Preserve the intended connection
and privacy contract with explicit TLS and teardown acceptance controls.

## Outcomes & Retrospective



## Context and Orientation

`shoko-core/src/Shoko/Binding.hs` exposes pure handler construction, source metadata,
`CallContext`, `correlation`, `requestDeadline`, and `callClock`. A binding connects a
context's typed operation to an acquired resource and handler. Policy preflight
resolves the declared requirements before acquisition. A business key is the named
application identity selected for an observation, such as `accountId`; it is distinct
from the Redis key, which is the actual byte sequence sent to the server.

`shoko-core/src/Shoko/Clock.hs` supplies a monotonic clock and `bounded` IO. Monotonic
time measures elapsed durations without wall-clock adjustments. `requestDeadline`
is the latest allowed completion of a call; it must bound connection establishment,
authentication, commands, result evaluation, and owned resource release.
`shoko-core/src/Shoko/Observation.hs` defines `ObservationOutcome`, `Occurrence`,
`Coverage`, and allowlisted `PublicValue` details. `SampledState` is the existing
coverage strength for mutable snapshots. `shoko-core/src/Shoko/Runner.hs` already
interprets this coverage and preserves three verdicts: Pass, Fail, and Unknown.

The closest implementation is `shoko-adapters/src/Shoko/Adapter/Postgres.hs`, with
descriptors in `shoko-adapters/src/Shoko/Adapter/Postgres/Query.hs` and sanitized
failures in `shoko-adapters/src/Shoko/Adapter/Postgres/Evidence.hs`. Its pure
`postgresObservation` requires `ReadState` and the descriptor's business-key name;
`runQuery` validates correlation before opening a connection; `observeQuery`
returns one typed occurrence with sampled coverage and safe details. Read these
files as the shape to follow, while using Hedis-specific transport handling.
`shoko-adapters/test/AdapterTests.hs` contains an existing public-runner consumer.

`shoko-adapters/shoko-adapters.cabal` is version 0.2.0.0 and currently contains no
Redis module. It builds on GHC 9.12.4 and GHC2024. `cabal.project.freeze` records the
Cabal dependency selection. `flake.module.nix` owns Shōko's package overrides,
development tools, and native test fixtures; `flake.nix`, `flake.lock`, and
`nix/*.nix` are managed through Seihou. `scripts/test-adapters` demonstrates owned
local service setup and `--binaries dist/build` support. `justfile` invokes the
individual suites and `just check`; `.github/workflows/ci.yml` runs that same check
on Ubuntu. New Redis fixture tools belong in unmanaged `flake.module.nix`.

The ADR filename/heading scan and `mori show --full` found an ordinary filesystem
ADR corpus, not an OKF-profiled ADR bundle. Relevant decisions were consulted:
[ADR 0001](../adr/0001-use-jitsurei-standards-and-the-seihou-haskell-flake.md) requires
released dependency verification, GHC2024 practices, and unmanaged project wiring;
its original Redis deferral is now superseded for this explicitly requested adapter
and its test fixture. [ADR 0002](../adr/0002-keep-scenarios-inspectable-and-bindings-explicit.md)
requires pure inspection, explicit correlation and capability contracts, and
host-owned secret resolution. [ADR 0003](../adr/0003-record-bounded-evidence-and-three-valued-results.md)
requires finite evidence, cancellation propagation, sanitized reports, and honest
sampled coverage. [ADR 0004](../adr/0004-gate-parity-on-real-workflows-and-context-owned-vocabulary.md)
keeps application vocabulary and actual staging acceptance in their owning context.
There is no existing Redis-specific ADR. Preserve the filesystem ADR format.

Dependency discovery used `mori registry list`, `mori registry search hedis`,
`mori registry show informatikr/hedis --full`, and `mori registry docs informatikr/hedis`.
The canonical package is [Hedis](mori://informatikr/hedis/packages/hedis), resolvable
with `mori path`. It has no curated DocRefs. Under the canonical repository
[mori://informatikr/hedis/repos/hedis](mori://informatikr/hedis/repos/hedis), inspect
`src/Database/Redis/Connection.hs`, `src/Database/Redis/Transactions.hs`,
`src/Database/Redis/ConnectionContext.hs`, `src/Database/Redis/ProtocolPipelining.hs`,
`src/Database/Redis/Commands.hs`, `src/Database/Redis/ManualCommands.hs`, and
`hedis.cabal`; artifact-level URIs for these source files are pending.

On 2026-10-26, the authoritative [Hackage version list](https://hackage.haskell.org/package/hedis/preferred.json)
identified 0.16.4 as the newest normal release. Its
[published Cabal file](https://hackage.haskell.org/package/hedis-0.16.4/hedis.cabal)
lists GHC 9.12.4 and requires `resource-pool >=0.5 && <0.6` and
`scanner >=0.2 && <0.4`. The upstream `v0.16.4` tag object is
`2ce8183a53ed571a70a86077af2bcfa7a07ce900`, peeling to commit
`a77cd336c79b5981f1125f1ccd462d872149afc8`. The inspected corpus HEAD was
`2567073dbce7b26e1d5624a834c896431ff63d7c`; tag source was also checked for the
transaction and existence interfaces. Use the release, not that corpus HEAD.

Hedis `connect` allocates a pool lazily; actual socket creation and authentication
happen in `runRedis`. `connectTimeout` covers establishment, not the entire request.
`disconnect` destroys idle pooled resources, so each call must finish or unwind
`runRedis` before disconnecting. Commands normally return `Either Reply a`, but
`multiExec` returns `TxSuccess`, `TxAborted`, or `TxError`. Its released implementation
can also raise a synchronous exception for an unexpected `EXEC` reply. These are
all relevant transport failure paths, including errors evaluated lazily. No raw
`Reply`, `TxError` message, or exception text may enter Shōko evidence.
Release evidence was rechecked on 2026-10-26 during review. The local checkout did
not have `v0.16.4` as a Git object; use the published archive or upstream tagged
source when local tag lookup fails, rather than treating corpus HEAD as the release.


## Plan of Work

### M1 — Exercise the real producer-to-observer path


Add Hedis to the adapter library and the new `redis-adapter-test` component, using
the existing common stanza and `-threaded`. Create
`shoko-adapters/src/Shoko/Adapter/Redis.hs`,
`shoko-adapters/src/Shoko/Adapter/Redis/Query.hs`, and
`shoko-adapters/src/Shoko/Adapter/Redis/Evidence.hs` with the interfaces below.
Begin with a bounded string observation, the pure handler, and a small real consumer
in `shoko-adapters/test/Redis/Contract.hs`, launched by
`shoko-adapters/test/RedisMain.hs`. Keep fixture/setup Hedis writes in test code.
Put the shared descriptor representation and closed command compiler in
`shoko-adapters/src/Shoko/Adapter/Redis/Internal.hs`, listed in Cabal's
`other-modules`. The public `Query` module re-exports only the opaque types and
safe constructors/accessors; the umbrella implementation imports the internal
representation directly. This lets it interpret queries without exposing query
constructors, resolved keys, or arbitrary Hedis actions to consumers.

Create `scripts/test-redis` using Python's standard library and the owned-process
pattern in `scripts/test-adapters`. Start `redis-server` with persistence disabled,
TCP disabled, and a short private Unix-socket path in a temporary directory. Wait
for readiness with a finite timeout, run the suite with explicit fixture variables,
then terminate and reap only the process this invocation started. Support both
Cabal and `--binaries dist/build`; missing Redis or failed readiness is an error,
never a skipped passing suite. Avoid the default localhost:6379 service entirely.
Add `just test-redis` and `pkgs.redis` to the development tools in `flake.module.nix`.

Resolve Hedis 0.16.4 in Cabal and the native Nix graph, inspecting transitive bounds
instead of adding `allow-newer`. If the pinned Nix package set supplies an older
Hedis, add a hashed `callHackageDirect` override in `flake.module.nix` using the
existing released-package pattern. If upstream Hedis tests assume an unprovided
server, disable only those dependency checks with an explanation; Shōko's real
Redis suite must still run in the adapter derivation. Freeze the compatible Cabal
selection without unrelated upgrades. Record exact versions and source hashes in
`docs/dependencies.md`. Keep generated template files unchanged.

The consumer uses a labelled toy cache operation and declared business-key
correlation. Its fixture writes one key using a separate writer identity, and its
observation runs via `redisObservation` and `runScenario`. M1 passes when
`nix develop --command just test-redis` proves a matching value gives Pass, a stable
different value gives Fail after a short window, and a stopped or unavailable
endpoint gives Unknown. This tests the actual Hedis/Redis/core interaction before
expanding the descriptor family. Do not substitute a mock for this early proof.


### M2 — Complete bounded queries, scope, policy, and privacy


Complete opaque scope/query constructors in `Shoko.Adapter.Redis.Query`. A scope
contains one nonempty `BusinessKeyName`, a fixed nonempty byte prefix, and a fixed
byte suffix. Resolve only `ByBusinessKey` with the identical name and a nonempty
value. The exact Redis key is `prefix <> encodeUtf8 value <> suffix`, with no case
folding, normalization, interpolation, or glob expansion. Bound the composed key
to 1024 bytes. At construction, reject an empty business-key name, an empty prefix,
or prefix/suffix lengths whose sum exceeds 1023 bytes, leaving room for at least
one correlation byte. At dispatch, check the UTF-8 byte length of the selected
value against the remaining budget before concatenation; an oversized result is
`KeyLimitExceeded`, mapped to `redis-key-limit-exceeded` and Unknown. Mismatch,
missing/empty correlation, and execution-only correlation are
`CorrelationUnavailable`. All these failures happen before opening any socket.
Test keys of exactly 1024 and 1025 bytes, including multibyte correlation values,
and prove the rejected cases make zero connection attempts.
Different selected values must remain distinct within a fixed scope even when
they contain quotes, wildcard characters, delimiters, NUL, or non-ASCII text.

`keyExists` sends one `EXISTS`; `keyAbsent` negates only a successful result.
`stringValue` returns `Maybe ByteString`, preserving `Nothing` for missing and
`Just ""` for present-but-empty. A positive `ValueLimit` is validated in the range
1 through 1048576 bytes. Retrieve at most `limit + 1` bytes using the inclusive
end offset of [GETRANGE](https://redis.io/docs/latest/commands/getrange/).
Never return a truncated value as a complete observation. A response exceeding
the limit produces `ValueLimitExceeded` and Unknown through the handler.

Use Hedis `multiExec` to queue `EXISTS` and `GETRANGE` for the same exact key and
combine their `Queued` results. Redis executes transaction commands without another
client interleaving writes; see the [transaction contract](https://redis.io/docs/latest/develop/using-commands/transactions/).
This is a fixed read-only transaction, with no arbitrary transaction API exported.
An error in either command, an abort, or an inconsistent decoded pair is unavailable
evidence. Include missing, empty, exact-limit, limit-plus-one, binary, wrong-type,
expiration, and concurrent replacement tests. The byte bound covers a conforming
server's successful value reply; Hedis does not expose a general maximum wire-frame
size, so do not claim protection against arbitrary oversized malicious protocol replies.

Construct `Redis` as an opaque configuration wrapper without `Show`, `Generic`, or
JSON instances, accepting Hedis `ConnectInfo` through a pure validating constructor.
Require a nonnegative database index, positive maximum connection count and any
explicit stripe count, idle time at least 0.5 seconds, and a positive optional
connection timeout. Reject an empty host or Unix-socket path, TCP port zero,
an empty supplied username, a username without `connectAuth`, and TLS parameters
on a Unix-socket endpoint. Hedis would silently ignore the last two settings.
Do not reject an explicitly supplied empty password solely because it is empty:
it is distinct from not requesting authentication.
Internally normalize to one connection and one stripe per sample, default no-op
hooks, and an empty pool instrumentation label. Preserve the caller's endpoint,
authentication, and TCP TLS parameters; certificate/trust policy stays host-owned.
Cap the effective connection timeout to the remaining request budget and convert
it to a positive, representable microsecond count before giving it to Hedis.
Arbitrary instrumentation hooks must not add commands or expose secret values
through this adapter. Do not connect or resolve host secrets during descriptor construction or
inspection. Settei remains the owning host's configuration boundary, as in ADR 0002.

`redisObservation` declares `ReadState`, `RequiresBusinessKey`, and `sampledSource`
metadata. Successful reads return one `Occurrence Nothing value` and
`Coverage SampledState started finished True`. Reports contain only fixed query-kind
labels and counts/flags such as existence and observed byte count. Raw Redis keys,
prefixes/suffixes, values, credentials, endpoints, and transport diagnostics are
excluded. A successful absent value is still one typed sample; it is not a source
outage or a durable event. Domain decoding and business predicates belong in the
context-owned vocabulary, not in a generic JSON/text decoder added to this adapter.

Extend the fixture to use a restricted Redis ACL, meaning an access-control rule
that permits only the exact read and connection commands needed. Give it access to
the fixture key prefix, `EXISTS`, `GETRANGE`, `MULTI`, and `EXEC`, plus connection
setup commands required by the chosen database/authentication settings. Keep the
writer separate. Direct writer-command attempts using the reader credentials must
be rejected. Verify the configured nonzero database is selected using distinct
values for the same key in database zero and the selected database. The fixture
reader needs `SELECT` for that case; ordinary `connect` does not issue `PING`.
Denied commands and authentication failures must produce unavailable
evidence, including a transaction queued-command denial that makes Hedis throw.

M2 passes when `just test-redis` verifies these data cases and proves denied
`ReadState` policy causes zero acquisition/socket attempts. Inspecting a scenario
needs neither a running Redis nor credentials. Use private sentinels in keys,
payloads, credentials, and injected error text; the actual public JSON and text
renderers must omit them. Invalid connection configurations must return closed
`RedisConfigError` values before IO. Include a controlled observation showing
supplied Hedis hooks are not invoked, and a compile-fail consumer probe showing
the internal module and query constructors are unavailable from the installed library.


### M3 — Prove deadlines, cancellation, concurrency, and coverage limits


Bound the entire sample with `Clock.bounded` at `requestDeadline`. Check expiry
before acquisition, cap connection establishment timeout to the remaining duration,
force the selected command result and its byte length inside the protected IO
scope, unwind `runRedis`, and bracket `disconnect` on success, error, or cancellation.
Use a new pool per call so concurrent expectations cannot share transaction state.
Do not add an adapter retry loop. Subsequent polling is owned by Shōko's runner.

Handle Hedis connection/authentication exceptions, `Either Reply` failures,
transaction failures, and synchronous protocol/decoding exceptions with a closed
`RedisFailure` value. Place broad synchronous exception handling outside the
deadline mechanism so the timeout's internal exception cannot be swallowed. Rethrow
`SomeAsyncException` instead of turning caller cancellation into evidence. Check
the completion timestamp as well as the timer result: a value completing after the
deadline is unavailable even if delivery of the timer was late. Cleanup must not
turn an expired call into a successful observation or leave a running receive task.
Hedis 0.16.4's plain-handle close is uninterruptibly masked, and TLS close can
perform IO. Exercise these paths; a timeout wrapper is not evidence that release
is interruptible. Do not abandon an unjoined cleanup worker to make a timeout test
return. If the released API cannot meet the required finite-release contract,
record the failing case and resolve the lifecycle/dependency design before M3
can pass; preserve the unfinished gate rather than silently weakening it.

Add `shoko-adapters/test/Redis/Controlled.hs` for controlled clock and cancellation
cases. Extend `scripts/test-redis` or add
`shoko-adapters/test/Redis/Fixture/server.py` for a small controlled socket peer
using RESP, Redis's request/reply wire format. It must observe that requests arrive
and that timeout/cancellation closes the client socket, rather than relying only
on sleeps. Exercise stalls during initial authentication and during a command,
abrupt disconnect, malformed replies, and command errors containing private text.
Keep these controls alongside the real Redis consumer, not as a replacement.
Also use that peer on an ephemeral loopback TCP port with Python's standard-library
`ssl` support. Store test-only CA/server certificates and a private test key under
`shoko-adapters/test/Redis/Fixture/`, using a certificate valid for the fixture's
hostname and a documented validity interval. Configure Hedis to trust only that
test CA and verify a successful encrypted command plus rejection of an untrusted
certificate and wrong hostname. Add the test component's direct `tls` dependency
with bounds compatible with the existing freeze, looking up its API through Mori.
Exercise a stalled TLS handshake, a peer that stops reading, and cancellation
during TLS command/release handling under outer hang-detection deadlines. Assert
all accepted sockets close and all peer workers join. These tests validate the
already-promised TCP/TLS lifecycle; they need no Redis server TLS build option.

Run concurrent observations for separate correlated keys, with one cancelled or
failing read while another completes. Verify a later call succeeds, the peer sees
all owned sockets close, and no process/thread is left waiting after teardown.
Use generous outer test deadlines to detect hangs while keeping each Shōko call's
budget short; use a fake clock for precise late-completion boundary assertions.

Finally exercise sampled-state semantics through `runScenario`. Repeated reads
must not acquire occurrence identities or count as distinct events. An eventually
absent predicate can Pass after a conclusive missing-key sample; an outage never
proves absence. `never` and `exactlyOnce` must not Pass from these snapshots alone.
Verify expiry removes a previously present key on a later sample without inventing
historical evidence. M3 is accepted when all these controls pass through `just
test-redis`, with bounded completion and no changes to core coverage semantics.


### M4 — Integrate the supported adapter into ordinary checks and documentation


Add `test-redis` to `just check`. In `flake.module.nix`, add `pkgs.redis` to the
adapter derivation's `nativeBuildInputs` and invoke `scripts/test-redis --binaries
dist/build` in its existing `checkPhase`. Ensure any Python fixture and static test
assets are available in the Cabal source distribution and the native derivation.
CI already invokes `just check`; keep one required path rather than an optional
Redis-specific workflow. The native check must also fail if its server is missing.

Update `docs/adapters.md`, `docs/development.md`, `docs/dependencies.md`, and the
adapter summary in `README.md`. Include a compiling example drawn from the real
consumer, exact key mapping, the value limit, required ACL permissions, handling
of Unknown, and sampled-state limitations. Document Redis 6.0 as the feature floor
for username/ACL support and record the actual tested server version provided by
the pinned Nix package set. Do not describe untested versions as validated; a
minimum-supported-version claim needs a run against that version. Do not claim
cluster compatibility. Add the Hedis dependency to `mori.dhall` using
the existing typed-reference convention and its canonical package identity.

Record the implemented capability in `docs/capabilities/` using that bundle's
profile and allocated handle; maintain its index/log with the existing tooling.
Update ADR 0001's Redis tool deferral and distill the adapter's scope, transaction,
bounded-value, lifecycle, and sampled-evidence decisions into the relevant ADRs
or a new Redis ADR under the existing filesystem convention. Do not claim this
fixture satisfies the separate deployed-workflow acceptance gate.

M4 requires the focused Redis suite, full `just check` (including native flake
checks), and `just check-docs` to pass. Preserve any environment limitation as an
unfinished acceptance item instead of reporting it as a pass. Finish provenance,
progress, friction triage, and retrospective records only after this evidence exists.


## Concrete Steps

All commands run from the repository root. The new `test-redis` commands below
become available during M1; they do not exist at plan creation.

```bash
cd /Users/shinzui/Keikaku/bokuno/shoko
git status --short
mori registry search hedis
mori registry show informatikr/hedis --full
mori registry docs informatikr/hedis
mori path mori://informatikr/hedis/packages/hedis
curl -fsSL https://hackage.haskell.org/package/hedis/preferred.json
git ls-remote --tags https://github.com/informatikr/hedis.git 'refs/tags/v0.16.4*'
```

The registry must identify `informatikr/hedis:hedis`; compare release evidence
with the version/tag recorded above. Locate source only through Mori and read the
release's APIs before changing the dependency selection. Do not search `/nix/store`
or the filesystem root. No dependency lookup requires either traversal.

After adding dependency declarations, refresh the signed index, solve the graph,
and write the freeze only when the selected plan is compatible. If the existing
freeze prevents resolution, retain a backup and remove only constraints that the
new dependency graph demonstrably requires changing. Review the resulting diff.

```bash
nix develop --command cabal update
nix develop --command cabal build all --dry-run
nix develop --command cabal freeze
nix develop --command cabal build shoko-adapters:lib:shoko-adapters shoko-adapters:test:redis-adapter-test
nix develop --command just test-redis
```

The wrapper should print Tasty's successful test summary and a stable final line
such as `Redis adapter contracts passed; owned fixture stopped.` It must exit
nonzero for missing tools, a failed assertion, or unsuccessful teardown. New tests
must fail or be unavailable before the adapter is added; mock-only success is not
acceptance. Record actual suite counts and versions when milestones are accepted.

When the implementation is coherent, run the final checks once; repeat only those
whose evidence is invalidated by subsequent changes:

```bash
nix develop --command just fmt
nix develop --command just check
just check-docs
git diff --check
```

Git-backed Nix flakes only include tracked files. Stage the specific new adapter,
fixture, and metadata files before the native check; never stage unrelated work.
`just check` includes `nix flake check`, which exercises the native adapter
derivation. For a focused native diagnostic, use:

```bash
nix build .#shoko-adapters --no-link --no-write-lock-file
```

Implementation commits follow Conventional Commits and include both trailers:

```text
feat(adapters): add scoped Redis evidence through Hedis

ExecPlan: docs/plans/12-add-a-redis-evidence-adapter-using-hedis.md
Intention: intention_01m5wb8reveq6rzgxcxzn3kmnd
```


## Validation and Acceptance

The required early proof is the M1 public consumer: a fixture producer writes
`fixture:cache:<selected-business-key>` and a scenario reads that exact key through
Hedis and Shōko. A matching binary string yields Pass; a conclusive different value
yields Fail after the bounded polling window; a disconnected server yields Unknown.
Each result must be rendered through existing JSON/text report functions.

For `stringValue` correctness, missing returns `Nothing`, empty returns `Just ""`,
binary bytes round-trip unchanged, and exact-limit bytes succeed. Limit-plus-one and
wrong-type keys are unavailable, never truncated values or absence. Existence and
absence descriptors are type-independent: a list/hash key exists even though a
string read of it fails. Keys with other correlation values cannot satisfy the
expectation. Missing/mismatched correlation and oversized composed keys perform
no network IO; the 1024-byte bound applies after UTF-8 encoding. A short-lived value
can disappear between samples; this does not prove continuous absence or a count
of historical writes.

For boundaries, denied policy stops before acquisition, reader credentials reject
mutation, and missing permissions/authentication/transaction errors yield Unknown.
Invalid authentication/TLS combinations fail in the pure constructor, while valid
nonzero database and TCP/TLS settings reach the intended database and verified peer.
No raw key/value/credential/endpoint/error sentinel appears in inspection or either
report rendering. Successful consumer probes import exposed modules only;
negative compilation probes must fail specifically on the prohibited API access.

For lifecycle, controlled plain/TLS stalls, caller cancellation, delayed completion,
concurrent independent reads, and a healthy call after failure establish finite
completion and socket release, including pending-output and TLS shutdown paths.
Unavailable samples cannot pass an absence check;
sampled `never` and `exactlyOnce` cannot Pass. Failure tests must demonstrate these
outcomes using the public runner, not merely inspect adapter constructors.

Completion requires ordinary `just check` and native Nix execution to run the
same Redis suite with owned fixtures, plus `just check-docs` for catalog and
manifest integrity. New data structures, writes, durable Redis history, deployment
configuration, and performance claims would be separate scope decisions.


## Idempotence and Recovery

The test wrapper owns a fresh temporary directory, Redis process, Unix socket,
and credentials per run. It must disable persistence and never flush, stop, or
configure an existing server. Fixture data can be recreated on every invocation.
On failure, stop and reap the owned process in `finally`, close controlled peers,
and clean only that invocation's directory. Do not print secret-bearing server
logs; retain only sanitized diagnostic categories. Retries start a fresh fixture.

Each observation owns its connection scope, so an interrupted transaction is
discarded with its socket. The next sample starts clean without a retry of the
previous operation. No migrations, application-key mutation, or persistent Redis
configuration changes are needed. If a dependency build fails, keep the failing
evidence and adjust released dependency selection deliberately; do not bypass
bounds or copy local corpus edits. Restore only this plan's changed constraints
from a known backup if necessary, preserving other work.


## Interfaces and Dependencies

The proposed public shape below is implemented in the three public Redis modules
under `shoko-adapters/src/Shoko/Adapter/`, backed by the non-exposed
`Shoko.Adapter.Redis.Internal` module. Resource and descriptor types shown without
constructors remain opaque; error types are clarified below.
The umbrella `Shoko.Adapter.Redis` re-exports the descriptor/evidence
surface, like `Shoko.Adapter.Postgres`. Use qualified imports in consumers to avoid
the existing adapters' `Query`, `Sample`, and `runQuery` name collisions.

```haskell
-- Shoko.Adapter.Redis.Query
data Scope
data Query a
data ValueLimit
data QueryConfigError

keyScope :: BusinessKeyName -> ByteString -> ByteString -> Either QueryConfigError Scope
valueLimit :: Int -> Either QueryConfigError ValueLimit
keyExists :: Scope -> Query Bool
keyAbsent :: Scope -> Query Bool
stringValue :: Scope -> ValueLimit -> Query (Maybe ByteString)
queryScope :: Query a -> Scope
scopeBusinessKey :: Scope -> BusinessKeyName
queryDescription :: Query a -> Text

-- Shoko.Adapter.Redis.Evidence
data RedisFailure
  = CorrelationUnavailable
  | KeyLimitExceeded
  | ConnectionUnavailable
  | AuthenticationUnavailable
  | QueryUnavailable
  | DecodeUnavailable
  | ValueLimitExceeded
  | DeadlineExpired

failureCode :: RedisFailure -> Text
data Sample = Sample
  { started :: !MonotonicTime,
    finished :: !MonotonicTime,
    description :: !Text
  }

-- Shoko.Adapter.Redis
data Redis
data RedisConfigError
redis :: Hedis.ConnectInfo -> Either RedisConfigError Redis
redisSource :: SourceId -> Source Redis
redisObservation :: SourceId -> Query a -> Handler Redis a
runQuery :: CallContext -> Redis -> Query a -> IO (Either RedisFailure (a, Sample))
observeQuery :: CallContext -> Redis -> Query a -> IO (ObservationOutcome a)
```

`QueryConfigError` and `RedisConfigError` expose closed, payload-free error
constructors for the validation cases above, with safe `Eq`/`Show` instances.
The declarations above omit their constructor lists for brevity; these errors
are inspectable, whereas `Scope`, `Query`, `ValueLimit`, and `Redis` stay opaque.
`RedisFailure` maps to fixed
`redis-...` codes; a Redis command permission error may share `QueryUnavailable`
with other rejected commands. The public distinction required here is uncertainty
versus an observed absent value, not preservation of every server error class.
Internal command compilation must stay closed over the supported read descriptors;
do not export an arbitrary `Redis a` action runner or the acquired Hedis connection.
`queryDescription` returns only fixed operation names, never scope bytes.

Hedis is the only new direct production dependency. Its canonical identity is
`mori://informatikr/hedis/packages/hedis`; consume Hackage 0.16.4 in Cabal and Nix
with `>=0.16.4 && <0.17` bounds, a freeze, and any required hashed native override.
Redis is a development/test service supplied through `pkgs.redis`. Reuse existing
test dependencies for Tasty/Hedgehog and async/socket checks; verify their APIs
through Mori if new usage is needed. No Hedis dependency or Redis-specific types
enter `shoko-core`, and no changes to result schema v3 are expected.
