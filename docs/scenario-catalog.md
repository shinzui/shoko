# Scenario catalog

`shoko-suite` validates and inspects explicitly selected compiled scenarios. The
catalog is governed by `schemas/scenario-catalog-v1.schema.json`; semantic checks
also reject duplicate IDs, conflicting artifact declarations and paths escaping
the workspace through traversal or symlinks. This is catalog metadata, not a
service inventory or live deployment observation.

```bash
nix build .#shoko-suite .#shoko-cli
nix run .#shoko-suite -- --workspace /path/to/consumer --catalog /path/to/consumer/config/scenarios.json list
```

All commands take `--workspace` and `--catalog`. `catalog-check` returns JSON with
structural validity, pending IDs and `liveReadinessChecked: false`. `list` shows
each scenario's state, suites and pending reason; `--format json` retains its full
declaration. `explain ID` and `check ID` invoke the matching compiled host with
its catalog-selected configuration, environment and scenario ID. `check` validates
policy only. Neither command reads credentials or performs live target checks.

A ready entry has an immutable 40-character source revision, an owning project
and participants, role (`required` or `control`), suites, environment, revision,
configuration and host artifact. Its workflow path is required for staging;
an offline consumer may use `null`. Paths are relative to the explicit workspace
and must name existing files. A pending entry has a public missing-artifact
reason and no runnable host/configuration/workflow fields. Pending selections
return exit 2, while structural validation and listing remain usable.

Resolve a host with `--host ARTIFACT=/absolute/path/to/declared-executable`.
Duplicate or unknown bindings are rejected. The dispatcher checks the executable's
basename and never searches PATH, executes a catalog shell string or compiles
Haskell. The caller owns binding that artifact to its pinned package output;
the catalog's source declaration alone does not attest executable contents.

Only `local` and `staging` are supported. `--environment`, when supplied, must
match the entry. An ambient `SHOKO_ENVIRONMENT` alias/production spelling is
rejected; a conflicting supported value is rejected for selection. The host gets
an explicit environment and cannot switch binding via `SHOKO_IMPLEMENTATION`.
Configuration/capability/target overrides are not accepted by this dispatcher.
Host factories must follow the existing [pure inspection contract](scenario-hosts.md).

The tool preserves host exits 0 through 4. Its own invalid inputs and unresolved
prerequisites exit 2 with fixed diagnostics that omit supplied values. `run` is
reserved and refuses execution in this release; suite execution, live readiness,
retained envelopes and offline envelope verification belong to later extensions.
No catalog inspection establishes a staging Pass.

`just test-scenario-catalog` uses the real independent consumer with missing and
sentinel credentials. A counter instruments metadata, acquisition, actions,
observations and cleanup; inspection leaves it absent and a real control run
proves the instrumentation works. The process checks also cover invalid schemas,
duplicate JSON keys and IDs, unsafe paths, environment aliases and all host exits.

The first downstream consumer is
`mori://tan/tan-platform-qa/plans/1-establish-the-qa-workspace-and-explicit-scenario-catalog`.
