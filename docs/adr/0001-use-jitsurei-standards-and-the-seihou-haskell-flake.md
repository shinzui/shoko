# Use Jitsurei standards and the Seihou Haskell flake

Date: 2026-10-01

Status: Accepted for bootstrap

## Context

Shōko currently contains a specification, research, Mori metadata, and planning skills, but no Haskell packages or build. The user requires the practices in [haskell-jitsurei](mori://shinzui/haskell-jitsurei) and the [nix-haskell-flake Seihou template](mori://shinzui/seihou-modules/templates/nix-haskell-flake). Research finding F15 cautions against creating seven packages before their boundaries are useful.

## Decision

Use Seihou to generate and track the Nix development environment. Keep generated `flake.nix`, `flake.lock`, and `nix/*.nix` under Seihou ownership; put Shōko's package graph, extra tools, checks, and outputs in unmanaged `flake.module.nix`. Disable the template's built-in root-package output, since the workspace has multiple packages. Enable process-compose, PostgreSQL, treefmt, and pre-commit support. Leave Redis, ClickHouse, Kafka clients, and private Redpanda disabled until a selected workflow requires them. Preserve the template's shared toolchain pins and track its generated lock before evaluating the flake.

Begin with `shoko-core` (definitions and runner), `shoko-adapters` (HTTP, SQL, and event-store bindings), and `shoko-cli` (command-line host and demo). Create adapter and CLI packages only when their work starts. Production domain vocabularies belong to their bounded contexts; a bounded context is the application boundary that owns the meaning of its business operations. Shōko may contain a clearly labelled toy vocabulary for its own tests, not the production registration vocabulary.

Apply [core standards](mori://shinzui/haskell-jitsurei/docs/core-standards), [record patterns](mori://shinzui/haskell-jitsurei/docs/core-record-patterns), [custom prelude](mori://shinzui/haskell-jitsurei/docs/core-custom-prelude), and [multiline strings](mori://shinzui/haskell-jitsurei/docs/core-multiline-strings). Use GHC 9.12 or newer and GHC2024, with a common Cabal stanza enabling `DeriveAnyClass`, `DuplicateRecordFields`, `OverloadedLabels`, and `OverloadedStrings`. Every component imports it. Records have strict, unprefixed fields and explicit deriving strategies; record access and updates use generic-lens or constructor pattern matches. Qualified imports are postpositive. Keep `PackageImports` local to `Shoko.Prelude`; keep `Data.Generics.Labels ()` out of the prelude and public type-only modules, importing it only where needed. Keep operators unqualified and hide conflicting prelude names at the import site. Use `MultilineStrings` for embedded SQL when appropriate.

Look up dependencies with Mori before using their APIs. Before choosing bounds or pins, check the authoritative package registry and upstream release tags, then record compatible selections and immutable source revisions in the build documentation. Local corpus versions and research survey versions are evidence of inspected APIs, not dependency pins. Do not copy unpublished working-tree edits or introduce blanket `allow-newer` exceptions.

## Consequences

The bootstrap reuses the shared toolchain and remains upgradeable through Seihou. The core stays independent of databases and application services; one adapter package is sufficient initially. GHC2024 does not itself enforce every coding practice, so format checks and focused review accompany compiler warnings. Package extraction is justified later by an actual independent consumer, dependency conflict, or release requirement.

Implementation baseline, 2026-10-18: use Seihou nix-haskell-flake 0.31.0 and GHC 9.12.4. The unmanaged package module exports the core library as both a package and a test-bearing flake check. `cabal.project` and the Nix package definition apply `-Werror` only to first-party code. Keep the complete Cabal solver selection in `cabal.project.freeze` and select direct dependencies coherent with the managed Nix package set; upgrading to a newer Hackage release is deliberate work, not an implicit solver change. See [dependency evidence](../dependencies.md) and [development commands](../development.md).

Keep source/test directories named `Result` trackable on case-insensitive filesystems: the template's unanchored Nix `result` ignore rule otherwise hides them from Git-backed flakes. Preserve the generated rules and append source-directory exceptions. `just fmt` formats Cabal metadata before the complete pass because Fourmolu reads that metadata while Cabal-gild may rewrite it.

Event-reader integration, 2026-10-18: released Kiroku 0.11 requires Hasql 1.10,
so upgrade the adapter's shared Hasql API deliberately and pin a compatible
released family in the unmanaged package module and Cabal freeze. Preserve the
managed toolchain pins. Validate SQL/HTTP again across this shared upgrade.
The Message DB observer uses the plan's allowed public-function SQL bridge:
its tagged Haskell client is not published on Hackage, and its public migration
dependency still uses the removed pre-1.10 statement constructor. Do not solve
that conflict with unpublished source edits or relaxed bounds. Pinned upstream
SQL fixtures retain licenses and per-file source hashes and exercise actual
stores in both Cabal and native Nix checks. See [dependency evidence](../dependencies.md).

Kafka client selection, revised 2026-10-23: enable the managed `nix.kafka`
option through Seihou 0.35.0. The selected client is
[rdkafka-hs](mori://shinzui/rdkafka-hs/packages/rdkafka-hs) 1.0.0.1, the maintained
successor to hw-kafka-client. Its published GitHub tag completes
[IR-2](mori://shinzui/rdkafka-hs/okf/improvement-requests/concepts/IR-2), providing
assign-only construction, partition-attributed EOF, synchronous destruction, and
read-committed visibility bounds. The owner-authorized exception to the
released-dependency rule is limited to tag-only distribution until a Hackage
release supplies these APIs. Pin the tag's immutable commit in Cabal and the
matching hashed Nix source override. No branch pins, copied working-tree edits,
or bounds waivers are permitted. Apache Kafka is a development/test fixture;
private Redpanda stays disabled. See [dependency evidence](../dependencies.md).

Promote a Kafka client into the public adapter only after its broker-backed
spike passes, including ordered duplicate headers. Version 1.0.0.0 reversed
consumed header order; [IR-3](mori://shinzui/rdkafka-hs/okf/improvement-requests/concepts/IR-3)
was completed by the 1.0.0.1 release. Keep that regression in the normal suite.
Preserve the wire order supplied by the fixed client; do not compensate with a
local reversal or patch the dependency.
