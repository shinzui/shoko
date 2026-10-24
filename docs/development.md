# Development

The workspace contains `shoko-core`, its typed descriptions and bounded runner,
`shoko-adapters`, and the reusable `shoko-cli` host with separately compiled consumers.
See the [core](core.md), [adapter](adapters.md), and [host](scenario-hosts.md) guides.
No staging credentials are needed for local checks.

The [capability catalog](capabilities/index.md) records implemented consumer surfaces;
the [terminology catalog](terminology/index.md) defines their vocabulary; the
[improvement requests](improvement-requests/index.md) record cross-repository requests
raised against Shoko with stable IR handles. Run `just check-docs` after editing any of them. This target requires `okf` 0.9.0.0
or later and Mori with `capabilities validate` and `terms validate`; it checks the
manifest, pinned profiles, catalog metadata, local term relations, and anchors.
These authoring tools are separate from the managed Haskell build environment;
run this gate alongside `just check` when changing the catalogs. Keep the terminology
index grouped by topic rather than replacing it with the default type-grouped OKF index.

From the repository root, with Nix installed:

```bash
nix develop --command cabal update
nix develop --command just build
nix develop --command just test
nix develop --command just check
nix develop --command just fmt
```

`check` builds all workspace components, runs core, real adapter, and CLI process tests,
validates the result schema against checked-in examples, and runs
`nix flake check`, including formatting, schema validation, and the Nix library/test build.
The CLI process suite also checks configuration schema/declaration keys, layered
provenance, all exit classes, safe credentials, and atomic persistence.
`just test-scenario-catalog` adds strict catalog and dispatcher process checks
against the independent compiled host. See [catalog inspection](scenario-catalog.md).
The offline workflow contract suite checks source/coverage mappings, canonical
host ownership, readiness prerequisites, and rejection of synthetic manifests
as staging contracts. It runs in both `just check` and `nix flake check`.
The same target includes offline identity-discovery process tests. They provide
their own fake `kubectl`, verify explicit targeting and sanitized private
artifacts, and exercise mismatches, deployment changes, response limits, and
timeouts. They never use the developer's kubeconfig or contact a cluster. See
the [generic v2 contract](workflows/generic-staging-contract.md) for the packaged
workflow-independent gate and its private fake-cluster/loopback-HTTP process checks.
See
the [workflow guide](workflows/first-staging-workflow.md) for the guarded live
identity command and its remaining readiness limits.
The event-store suite uses pinned real Kiroku and Message DB schemas, separate
writer/reader roles, and the public core runner. `just test-event-stores` requires
both stores; `just test-event-store kiroku` and `just test-event-store message-db`
select one explicitly. Its Unix-only cluster is owned by that invocation, and
checkpoint rows must remain unchanged. No staging access is required.
`just test-kafka` boots an owned single-node Apache Kafka 4.3.1 broker (from
`pkgs.apacheKafka` in the shell) on two free loopback ports, seeds an inactive
`application-worker` group, runs `kafka-adapter-test`, and checks that no
`shoko-observer-` group, no topic outside the `fixture-` prefix, and no change to
the application's committed offsets resulted. Sanitized broker log tails from a
failed run are kept under the ignored `.dev/kafka-tests/`. The suite combines
controlled scanner checks, a direct released-client spike, and public-runner
contracts against the real broker. `rdkafka-hs` 1.0.0.1 fixes the header-order
regression found by the spike. The shell enables `nix.kafka = true` for librdkafka
and adds `c2hs` for the client's FFI build. Every executable linking `rdkafka-hs`
must use `-threaded` (see [dependency evidence](dependencies.md)).
First-party code treats warnings as errors through `cabal.project` and the Nix
package definition. Dependencies retain their own warning policy. CI invokes the
same commands on Ubuntu; local acceptance is also checked on Apple Silicon macOS.
Linux CI execution is reported by GitHub Actions after the change is pushed.

`just fmt` formats Cabal metadata before the full formatter pass. Fourmolu reads
Cabal defaults, so this order avoids reading a file while Cabal-gild rewrites it.
The complete pass still formats Haskell, Cabal, and Nix with the managed tools.

The signed Hackage index is bounded by `index-state` in `cabal.project`;
`cabal.project.freeze` retains the complete solver selection. See
[dependency evidence](dependencies.md). A normal `cabal update` refreshes the index
cache without changing that selection. Revisit the solver selection when adding
each package, including consistency with the managed Nix package set.

The environment comes from
[Seihou nix-haskell-flake](mori://shinzui/seihou-modules/templates/nix-haskell-flake)
0.35.0. The module descriptor in the installed registry declares that version;
upstream has no module release tags. GHC remains 9.12.4. The managed base revision
is `21933607e80ec4660a28a125a6f4c0707e358caf` of
[the shared toolchain](mori://shinzui/haskell-nix-dev); the managed Haskell runtime
revision is `d13245db8a3e2c1c559185c0adf87285259b7ab2` of
[the shared runtime](mori://shinzui/haskell-nix). All transitive Nix pins live in
the generated `flake.lock`. The 0.35.0 migration makes `.envrc` trackable.

Seihou owns `flake.nix`, `flake.lock`, `nix/`, `fourmolu.yaml`, the example module,
and local service scaffolding. `flake.module.nix` defines Shōko's packages and
checks without editing generated files. Saved variables are in
`.seihou/config.dhall`. Preview reapplication and inspect drift with:

```bash
seihou run nix-haskell-flake --dry-run --no-commands --no-save-prompted
seihou diff
```

Upgrade deliberately with `seihou update nix-haskell-flake`, inspect the generated
changes, and repeat `just check`. Keep generated inputs tracked before evaluating
a Git-backed flake. Do not edit generated pins or run a blanket flake update.

The template prepares a local PostgreSQL data directory under ignored `db/` when
entering the shell. It does not start the server. Core checks never connect to it.
`just test-adapters` creates its own temporary Unix-only cluster and HTTP server,
without depending on the generated `process-compose.yaml` or any running database.
It provisions only owned local fixture data and cleans up on test failure.


`just test-email` is a focused loopback check requiring Python and the compiled Haskell
components, with no PostgreSQL, Kafka or live credentials. It tests receiving, controlled
sending, sampled coverage, isolation, cancellation, Settei configuration and offline
smoke-host/wrapper processes. It is included in `just check` and the native adapter
`checkPhase`; `scripts/test-email --binaries dist/build` uses packaged test and smoke
executables. The wrapper locates `exe:shoko-email-smoke` with Cabal for explicit live use.
See [email verification](workflows/email-verification.md). External mail is never part of CI.
