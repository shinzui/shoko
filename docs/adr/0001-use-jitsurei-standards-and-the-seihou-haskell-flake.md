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
