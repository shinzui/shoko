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
The offline workflow contract suite checks source/coverage mappings, canonical
host ownership, readiness prerequisites, and rejection of synthetic manifests
as staging contracts. It runs in both `just check` and `nix flake check`.
The same target includes offline identity-discovery process tests. They provide
their own fake `kubectl`, verify explicit targeting and sanitized private
artifacts, and exercise mismatches, deployment changes, response limits, and
timeouts. They never use the developer's kubeconfig or contact a cluster. See
the [workflow guide](workflows/first-staging-workflow.md) for the guarded live
identity command and its remaining readiness limits.
The event-store suite uses pinned real Kiroku and Message DB schemas, separate
writer/reader roles, and the public core runner. `just test-event-stores` requires
both stores; `just test-event-store kiroku` and `just test-event-store message-db`
select one explicitly. Its Unix-only cluster is owned by that invocation, and
checkpoint rows must remain unchanged. No staging access is required.
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
0.31.0, published in the upstream registry at immutable revision
`cc1b70c70eddeec5155c1a5a723b63a4cfaba6d6`. Upstream has no release tags for
this module; the registry entry and module descriptor declare its release.
The installed descriptor matches that revision byte for byte. GHC is 9.12.4;
the managed base revision is `206ecd25bcb4a07581210bdae3e6f43c8fd179d8` of
[the shared toolchain](mori://shinzui/haskell-nix-dev). All transitive Nix pins live
in the generated `flake.lock`.

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
