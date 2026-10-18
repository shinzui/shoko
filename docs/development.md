# Development

The workspace contains `shoko-core`, its typed descriptions and bounded runner,
and separately compiled consumers. See the [core guide](core.md) for the public
API. Adapters and the CLI follow in the child plans. No staging credentials or
running database are needed for core checks.

From the repository root, with Nix installed:

```bash
nix develop --command cabal update
nix develop --command just build
nix develop --command just test
nix develop --command just check
nix develop --command just fmt
```

`check` builds all workspace components, runs the explicitly selected core test,
validates the result schema against checked-in examples, and runs
`nix flake check`, including formatting, schema validation, and the Nix library/test build.
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
The generated `process-compose.yaml` is only for later local adapter fixtures;
it is independent of the running staging application.
