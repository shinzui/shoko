# Dependency selection

Verified on 2026-10-18 against Hackage JSON release listings and upstream tags,
after locating APIs through Mori. Hackage is authoritative for released Cabal
metadata; local corpus checkouts are API research, not pins. Package bounds in
the Cabal manifest express supported release families; the project constraints,
freeze file, and Nix lock establish the accepted selection.

| Package | Selected | Latest Hackage release observed | Canonical owner | Upstream release revision |
| --- | --- | --- | --- | --- |
| text | 2.1.4 (GHC boot package) | 2.1.4 | [text](mori://haskell/text/packages/text) | `423fd981e576bd17a8b5fa48d0ad6b9a0c370e77` (2.1.4) |
| containers | 0.7 (GHC boot package) | 0.8.1 | [containers](mori://haskell/containers/packages/containers) | `4fda06c43ea14f808748aa8988158946c3ce0caf` (v0.7) |
| tasty | 1.5.4 | 1.5.4 | [Tasty](mori://UnkindPartition/tasty/packages/tasty) | `0394c73e647834829e7f500c9dab0be3ff9e4f11` (core-1.5.4) |
| hedgehog | 1.5 | 1.7 | [Hedgehog](mori://hedgehogqa/haskell-hedgehog/packages/hedgehog) | `4c5424db30eee67423ddd80745d03e487a223ade` (1.5); latest 1.7 is `947e0806579778fb2e28d62afb30d6e61214244c` |
| tasty-hedgehog | 1.4.0.2 | 1.4.0.2 | [Tasty Hedgehog](mori://UnkindPartition/tasty/packages/tasty-hedgehog) | `3d46b53a00b39722627a7697cff93240f21d4cb1` (1.4.0.2) |
| effectful-core | 2.6.1.0 | 2.7.1.2 | [Effectful core](mori://effectful/effectful/packages/effectful-core) | `70f2b865e2f35cfd9f2e901fe5d2a9b1014c5e34` (effectful-core-2.6.1.0); latest tag `1c91cf4987ee8249fb54e2f50ad3e69fb56df162` |
| aeson | 2.2.4.1 | 2.3.2.0 | [Aeson](mori://haskell/aeson/packages/aeson) | Selected Hackage release has no matching upstream tag; upstream v2.3.2.0 is `682162c66d26a770fbfb6271c797e646bc5c4f2e` |
| async | 2.2.6 | 2.2.6 | [Async](mori://simonmar/async/packages/async) | No matching upstream 2.2.6 tag; Hackage is the selected source. Last listed 2.2.5 tag is `4a70b53c1ba90d8a59d6ec41a89337645c55b4cd` |
| cryptohash-sha256 | 0.11.102.1 | 0.11.102.1 | [SHA-256](mori://haskell-hvr/cryptohash-sha256/packages/cryptohash-sha256) | `89c1b9030989cc914d057061d90933628481abb2` (v0.11.102.1) |
| bytestring | 0.12.2.0 (GHC boot package) | 0.12.2.0 | [ByteString](mori://haskell/bytestring/packages/bytestring) | `d984ad00644c0157bad04900434b9d36f23633c5` (0.12.2.0) |
| time | 1.14 (GHC boot package) | 1.16.0.1 | [Time](mori://haskell/time/packages/time) | `e5c5d1987011efe88a21ab6ded45aaa33a16274f` (1.14) |
| hasql | 1.10.3.7 | 2.0.1.0 | [Hasql](mori://hasql/hasql/packages/hasql) | `cde5581845d51413d34c1847454df05073f33bc4` (selected); `ef3e361ced8ad62652f1a8e7a77b3d0d0e2b9065` (latest) |
| http-client | 0.7.19 | 0.7.19 | [HTTP client](mori://snoyberg/http-client/packages/http-client) | `a0b418c12ff3c9878f21bff92bb174c239a9cfe3` (http-client-0.7.19) |
| http-client-tls | 0.3.6.4 | 0.4.0 | [TLS backend](mori://snoyberg/http-client/packages/http-client-tls) | No matching upstream release tag; selected Hackage archive inspected |
| http-types | 0.12.4 | 0.12.6 | [HTTP types](mori://Vlix/http-types/packages/http-types) | `6c4f373c4d3ea00f824c5ed417ff4c20c8825d05` (v0.12.4); latest `3cbf2ab6d075a54de699884c5183b44535575b9b` |

Registry release listings: [text](https://hackage.haskell.org/package/text.json),
[tasty](https://hackage.haskell.org/package/tasty.json),
[hedgehog](https://hackage.haskell.org/package/hedgehog.json), and
[tasty-hedgehog](https://hackage.haskell.org/package/tasty-hedgehog.json).
Upstream repositories: [text](https://github.com/haskell/text),
[tasty](https://github.com/UnkindPartition/tasty),
[hedgehog](https://github.com/hedgehogqa/haskell-hedgehog), and
[tasty-hedgehog](https://github.com/qfpl/tasty-hedgehog).

Hedgehog 1.5 deliberately matches the released version in the managed GHC 9.12.4
Nix package set. Its public property API is sufficient for this foundation. This
avoids a divergent Cabal/Nix dependency selection; it is not an unpublished
patch or an `allow-newer` exception. No compatibility workaround is required.
The requested Cabal snapshot is `2026-10-18T00:00:00Z`, verified reachable by
`cabal update`; the freeze file records the last actual index event before it,
`2026-10-17T17:19:18Z`.

API inspection used the Mori-indexed Tasty `Test.Tasty` and
`Test.Tasty.Hedgehog` source, Hedgehog's public `Hedgehog` module, and the
Jitsurei prelude guidance. The local source revisions inspected were
`2ef0bba406c24fcb6745515530ee5370934f329e` for the Tasty corpus,
`4ba91e4a16804885694e4b123a10613ac581194d` for the Hedgehog corpus, and
`f684a0be02a2ef65e0da21421e70dda60b5fc899` for the text corpus. Actual builds
consume released Hackage sources, never another checkout's working tree.

The foundation depends on `base` and `text`; its tests introduce Tasty/Hedgehog.
The scenario description milestone adds GHC's boot `containers` for reference and
capability sets. Its [release listing](https://hackage.haskell.org/package/containers.json)
was checked before selecting the boot version. Lens and generic-lens will be
added when code uses them; constructor pattern matching already follows the
record standard. Database, HTTP, event store, and Settei dependencies belong to
their later package introductions and need fresh release/compatibility checks.

The runner adds Effectful's dynamic dispatch, Async's concurrent expectation
workers, Aeson codecs, SHA-256 description identity, and boot ByteString/Time.
Its selected direct versions match the managed Nix package set. The newer
Effectful, Aeson, and Time releases above are observed releases, not untested
upgrades. No bounds waiver or working-tree dependency is used. Additional API
inspection revisions were `9e54de5a3f57a682427e62ab87c95eda5b97849d` for Effectful,
`a33d84642424f6feb3151b8108e79a3bcbb3f23d` for Aeson,
`c319daf29c99b48d01e1251807631876d995b597` for Async, and
`fa11a8c99e11739d3410c62575da3ec1be2a73db` for SHA-256.

Registry evidence: [effectful-core](https://hackage.haskell.org/package/effectful-core.json),
[aeson](https://hackage.haskell.org/package/aeson.json),
[async](https://hackage.haskell.org/package/async.json),
[cryptohash-sha256](https://hackage.haskell.org/package/cryptohash-sha256.json),
[bytestring](https://hackage.haskell.org/package/bytestring.json), and
[time](https://hackage.haskell.org/package/time.json). Missing matching tags for
Aeson 2.2.4.1 and Async 2.2.6 are recorded rather than replaced with guessed
revisions; Cabal consumes their released Hackage archives.

The independent schema check uses Python jsonschema 4.26.0 from the managed
Nixpkgs pin; PyPI also reports 4.26.0. Upstream tag v4.26.0 resolves to
`a7277432b0f7bcd0551f6e589d30457017125df4`. It is a development tool, not a
Haskell runtime dependency. Mori has no registered jsonschema project; API
lookup therefore used the [official validator documentation](https://python-jsonschema.readthedocs.io/en/stable/validate/)
and the [PyPI registry](https://pypi.org/pypi/jsonschema/json).

The initial SQL adapter selected Hasql 1.9.3.1 from the managed package set.
EP-5 deliberately upgrades it to **1.10.3.7**, the latest compatible 1.10
release observed, because released Kiroku 0.11 requires `hasql >=1.10 && <1.11`.
Hasql 2.0 remains outside Kiroku's supported bounds. The SQL adapter now uses
`Connection.use`, `Session.script`, closed statement constructors, and explicit
error types from the [migration guide](mori://hasql/hasql/docs/hasql-1.10-migration).
Hasql 1.10 validates PostgreSQL column OIDs itself; the real wrong-column-type
regression remains required. Malformed/empty connection strings are rejected
before Hasql's settings parser can turn them into ambient defaults.

Release evidence: [Hasql](https://hackage.haskell.org/package/hasql/preferred.json),
[HTTP client](https://hackage.haskell.org/package/http-client/preferred.json),
[TLS](https://hackage.haskell.org/package/http-client-tls/preferred.json), and
[HTTP types](https://hackage.haskell.org/package/http-types/preferred.json).
Mori has no registered HTTP-types project; its intended canonical URI above is
pending registry coverage. Lookup fell back to the released Hackage archive,
whose metadata identifies [the upstream owner](https://github.com/Vlix/http-types).
The released TLS archive confirms `tlsManagerSettings`; HTTP client source
confirms automatic reused-connection retries are configurable and `closeManager`
is a deprecated no-op. Response scopes and zero idle connections bound owned
socket lifetime. PostgreSQL's [type-information reference](https://www.postgresql.org/docs/current/functions-info.html)
documents the column metadata that distinguishes PostgreSQL types.

The CLI selects all four Settei packages at released **0.2.0.0**, also the latest
Hackage release observed on 2026-10-18: [core](https://hackage.haskell.org/package/settei/preferred.json),
[YAML](https://hackage.haskell.org/package/settei-yaml/preferred.json),
[environment](https://hackage.haskell.org/package/settei-env/preferred.json), and
[optparse](https://hackage.haskell.org/package/settei-optparse-applicative/preferred.json).
Upstream v0.2.0.0 resolves to `1bf62b0af110b4f42fe2528e9d459e0ccf12d626`;
the Mori-located source for those four packages has no code differences from
that release. Public typed declarations, strict resolution, source adapters,
Secret settings, and safe renderers were inspected directly.

Its released optparse adapter requires **optparse-applicative 0.19.0.0**, also
the latest registry release; upstream tag 0.19.0 is
`5377a34d280bf847588b443b25a581803f484259`. The managed Nix set's older 0.18
is deliberately replaced with this released version. Settei is absent from that
Nix snapshot. `flake.module.nix` uses `callHackageDirect` with fixed unpacked
archive hashes for these five released packages. This preserves generated pins
and applies no bounds waiver or source patch. Cabal consumes the same releases.
The API source for `callHackageDirect` was checked against the pinned Nixpkgs
revision after Mori had no matching Nixpkgs project.

Build identity uses **githash 0.1.7.0** (latest), release revision
`d351f1441dc47e0096ffbf87a87e17b14778bbe7`. Mori has no registered githash
project, so lookup fell back to the [released archive](https://hackage.haskell.org/package/githash-0.1.7.0)
and [upstream](https://github.com/snoyberg/githash). Local Cabal builds embed the
actual revision/dirtiness at compile time. Nix injects its source identity with
the documented CPP build extension; a source-less archive reports its unknown
identity honestly.

The CLI also uses GHC's boot **directory 1.3.10.1**, **filepath 1.5.5.0**, and
**unix 2.8.8.0** for atomic evidence persistence. The latest registry versions
observed are 1.3.11.0, 1.5.5.0, and 2.8.8.0 respectively. Selected upstream
revisions are `8c712e834f277544fc03e96dfbbb769126dc0a7c`,
`baac7d7e76449f76fc6785e77206edb5530b6bfb`, and
`60f432b76871bd7787df07dd3e2a567caba393f5`. Mori located directory source;
unix/filepath were absent, so released Hackage archives supplied the inspected
`createLink` and path APIs. These selections follow the managed GHC boot set.
Registry evidence: [directory](https://hackage.haskell.org/package/directory/preferred.json),
[filepath](https://hackage.haskell.org/package/filepath/preferred.json),
[unix](https://hackage.haskell.org/package/unix/preferred.json),
[optparse](https://hackage.haskell.org/package/optparse-applicative/preferred.json),
and [githash](https://hackage.haskell.org/package/githash/preferred.json).

## Event-store selection

EP-5 selects released **kiroku-store 0.11.0.0**, the latest Hackage release
observed, at upstream revision `7394055de458bef8f6ec2e68231f3ca7932bb9be`.
The matching **kiroku-store-migrations 0.7.1.0** release has the same revision.
[The owning project](mori://shinzui/kiroku) supplies both releases. Fixtures vendor
its complete ordered migration set verbatim, with license and per-file SHA-256
hashes in `shoko-adapters/test/EventStore/Fixture/sources.json`; those bytes were
compared with the selected upstream tag. No migration is applied to an existing
application database.

The coherent Hasql 1.10 family uses **hasql-pool 1.4.2.3** (tag revision
`aa55681c21e4b5183878ae2a9959b59a936cbb3e`), **hasql-transaction 1.2.3.1**
(`81adf1ad3d8cc60d64a1354eda58d4c46b705532`), and **hasql-notifications
0.2.5.0**. No upstream 0.2.5.0 notification tag exists; Hackage supplies that
fixed-hash release. The newer pool 1.5 and notifications 0.2.6 families require
Hasql 2 and do not satisfy Kiroku's bounds. These packages belong to
[the Hasql corpus](mori://hasql/hasql).

Supporting releases are **postgresql-binary 0.15.0.1**, upstream revision
`ba03818cb1d94a3df496c445cea974e921bd7314`; **streamly-core 0.3.1**, revision
`e36596a2741a053d2cf3ee9efb32c6a823c0b89c`; and **mmzk-typeid 0.7.1.2**,
revision `2a39f4c7f252730e50284346a8f50133dcc06c75`. The latter two are owned by
[Streamly](mori://composewell/streamly) and [TypeID](mori://MMZK1526/mmzk-typeid).
PostgreSQL binary's intended project URI is `mori://nikita-volkov/postgresql-binary`
(registry coverage pending). The existing **postgresql-connection-string
0.1.0.6** supports explicit parse validation at the adapter boundary. All selected
release metadata was read from Hackage; upstream tag checks are recorded above.
`flake.module.nix` fixes unpacked hashes, while `cabal.project` and its regenerated
freeze file select the same direct event-store/Hasql family. Transitive versions
remain recorded separately by each build system: the new connection-string
parser uses Megaparsec 9.8.3 in Cabal and 9.7.0 in the managed Nix set, both
within its released bounds and exercised by the two builds. No generated Nix pin, dependency
source patch, or bounds waiver is used. External database-dependent suites are
not run by these library derivations; Shoko's native fixture checks exercise the
actual supported public append/read APIs. External test-only package arguments
are excluded from those library inputs.

The [Message DB server](mori://message-db/message-db) fixture vendors its
1.3.0 schema, public functions, indexes, and license from upstream revision
`e6999a6bd95ace6e8d70ec62a00c66b27ce8bf3b`, also checked by per-file hashes.
The actual `message_store_version()` result must equal 1.3.0. The adapter uses
those public stream/category read functions with no arbitrary SQL condition.

The [Haskell client](mori://tan/message-db-hs/packages/message-db-hs) has a
0.2.0.0 upstream tag at `8db65db221343c23fec49f5288ee6716b9d4e7bc`, but no
Hackage release listing. Its `hasql-migration` dependency cannot use the public
Hackage 0.3.1 release with Hasql 1.10: that release constructs `Statement`
directly, which 1.10 no longer exports. The local fork has migrated APIs, but
copying its unpublished changes or downgrading Kiroku is not a coherent released
selection. The plan's allowed thin SQL bridge avoids that dependency and is
verified against the exact real server functions. It introduces no observer
subscription, consumer-group position, or runtime service dependency.

Direct event records also use the already frozen **uuid 1.3.16.1** and
**vector 0.13.2.0**, both the latest Hackage releases observed. Their upstream
release revisions are `cacb242660a8e441e4d9179237b5a42054fbe581` and
`d9d0d46623fdecce7652f59caa4a28849292a0e7`. UUID is owned by
`mori://haskell-hvr/uuid/packages/uuid`; Vector's intended handle is
`mori://haskell/vector/packages/vector` (registry coverage pending). No new
version divergence from the existing freeze is introduced for these two packages.

## Kafka selection

Plan 10 (`docs/plans/10-implement-the-kafka-topic-evidence-adapter.md`) adds a
bounded Kafka topic reader. Rechecked on 2026-10-21, the newest Hackage release of
[hw-kafka-client](mori://haskell-works/hw-kafka-client/packages/hw-kafka-client) is
5.3.0 (uploaded 2023-08-05, upstream tag `v5.3.0` at
`e80c3220c46f4b6b2a1cd5007fca5e6df7f22ba1`). It cannot build a read-only observer:
`newConsumer` always subscribes, and librdkafka rejects an empty subscription;
per-message errors, including partition EOF, lose their partition; and the client is
destroyed only by a garbage-collector finalizer. Its internal modules are hidden. No
other Hackage package is viable: `librdkafka` and `kafka` are 0.0.0.0 placeholders,
`kafka-client` dates from 2015, `haskakafka` from 2016, and `kafka-interchange`
only encodes the wire protocol.

The owner selected the fork [shinzui/hw-kafka-client](mori://shinzui/hw-kafka-client),
pinned by immutable commit through a `source-repository-package` stanza, the
convention [kafka-effectful](mori://shinzui/kafka-effectful) already uses. This is a
scoped, owner-authorized exception to the released-dependency rule in ADR 0001. It
applies only once the fork carries
[IR-2](mori://shinzui/hw-kafka-client/okf/improvement-requests/concepts/IR-2), and it
ends when a released version carries the same API. Until then no Shōko package
depends on a Kafka client, the managed shell keeps `nix.kafka = false`, and
librdkafka is not linked. Enabling `nix.kafka` currently forces a
`nix-haskell-flake` upgrade from 0.31.0 to 0.34.0 that replaces the managed
`flake.lock`. That upgrade is deferred to the client binding step, where the
regenerated pins must be reverified.

The development and test tool **Apache Kafka 2.13-4.3.1** (JRE 17.0.19) comes from
the pinned Nixpkgs revision `d5dfd8e6716dde34398bc14bc87c10dece9c8c68` as
`pkgs.apacheKafka`, in the dev shell and the adapter derivation's checks. Upstream
tag `4.3.1` peels to `26b251a451ce941d3d7a55e6487bcb7f16b5ad48`; Mori has no
registered project, so the Nixpkgs attribute is the reference. The
`kafka-adapter-test` suite adds only the already frozen **process 1.6.26.1**.
When the client lands, every executable linking it must be built with
`-threaded` for its callback machinery; all adapter test suites already are.
