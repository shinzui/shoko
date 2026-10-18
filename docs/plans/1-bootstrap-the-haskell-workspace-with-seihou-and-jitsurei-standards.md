---
id: 1
slug: bootstrap-the-haskell-workspace-with-seihou-and-jitsurei-standards
title: "Bootstrap the Haskell workspace with Seihou and Jitsurei standards"
kind: exec-plan
created_at: 2026-10-02T03:52:02Z
intention: "intention_01m3xdacr3exqajqfcgh9btgev"
master_plan: "docs/masterplans/1-bootstrap-shoko-for-evidence-based-workflow-parity.md"
provenance:
  created_by:
    model: "gpt-6-astra"
    harness: "codex-cli"
    at: 2026-10-02T03:52:02Z
  revisions:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-02T04:18:40Z
      mode: "update"
      note: "Associate the bootstrap plan with the shared Mina intention requested by the user."
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-18T17:14:48Z
      mode: "update"
      note: "Validate scaffold preview and clarify build versus fixture test gates."
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-10-18T17:41:49Z
      mode: "implement"
      note: "Generate released Seihou environment and implement reproducible core package and checks."
  reviews:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-18T17:14:48Z
      verdict: "approved"
      note: "Planning review after MVP update: dependencies, ownership, references, and observable acceptance checked; build and live staging proof remain implementation gates."
---

# Bootstrap the Haskell workspace with Seihou and Jitsurei standards


This ExecPlan is a living document. Keep its progress and decisions current, and promote durable discoveries into `docs/adr/`.

## Purpose / Big Picture


A contributor can enter a reproducible Haskell shell, build the first Shōko library, run its tests, and obtain the same formatting checks in CI. The foundation follows the user's required Seihou template and Haskell practices, while leaving application behavior to later plans.

## Progress


- [x] M1 (2026-10-18): Seihou 0.31.0 generated the environment with zero conflicts; `nix develop --command ghc --numeric-version` reports 9.12.4, evaluation leaves the generated lock unchanged, and `seihou diff` reports no drift.
- [x] M2 (2026-10-18): The library and separate public API consumer build and pass under Cabal and Nix. `nix develop --command just check` passed in both the primary tree and a clean detached checkout of commit `8cb274a`; all three flake checks passed. CI invokes the same command on Ubuntu.

The accepted local platform is aarch64-darwin. The clean checkout stayed clean and its lock did not change. `cabal check` reports no errors or warnings. CI is checked in but has not been pushed or executed on GitHub; no Linux runtime acceptance is claimed. This completes the foundation prerequisite for the remaining generic packages.

## Surprises & Discoveries


On 2026-10-18, the documented Seihou dry run succeeded with 11 files to write and zero conflicts. It warned about unrelated saved configuration keys; preserve those keys. No flake was generated and no solver/build was executed. The inspected local template README now reports 0.30.0; that observation is not a released-version selection.

Implementation on 2026-10-18 found the installed module at 0.31.0, matching the upstream descriptor at `cc1b70c70eddeec5155c1a5a723b63a4cfaba6d6` of `mori://shinzui/seihou-modules`. Mori's cached 0.26.0 and the local checkout's 0.30.0 README lag that published descriptor. The managed package set uses released Hedgehog 1.5 while Hackage has 1.7; the project deliberately selects 1.5 to keep direct Cabal/Nix test dependencies aligned. Saved Seihou Boolean settings must be textual `"true"`/`"false"` in its homogeneous config record.

## Decision Log


On 2026-10-01, choose one initial `shoko-core` package, expanding to adapters and CLI only as used. This follows RES-1 F15 and avoids seven empty packages. Use unmanaged `flake.module.nix` for the multi-package build rather than editing Seihou-owned modules.

## Outcomes & Retrospective


Completed 2026-10-18. Contributors can build, test, and format the public core package through the managed GHC 9.12.4 shell. Package metadata, frozen dependency resolution, an unmanaged Nix package/check module, explicit test recipes, CI, Mori metadata, and development/dependency guides are checked in. The acceptance consumer deliberately proves only the package boundary; it does not claim scenario semantics or live staging behavior. Existing ADR 0001 now records the durable build/solver convention. No unpublished dependency sources, shared pin changes, database server startup, or application mutations were needed.
## Context and Orientation


At the 2026-10-18 validation the repository has `README.md`, `docs/intial-spec.md`, `docs/research/initial-specification-requirement-validation.md`, `mori.dhall`, `.seihou/config.dhall`, `.seihou/manifest.json`, and planning skills. It has no Cabal package, Nix flake, application source, tests, or CI. Existing Seihou applications are Git initialization and the planning skills; preserve them. Commands below run at the Shōko repository root. Paths described as new are deliverables, not existing code.

[ADR 0001](../adr/0001-use-jitsurei-standards-and-the-seihou-haskell-flake.md) requires the [Seihou template](mori://shinzui/seihou-modules/templates/nix-haskell-flake) and the [Jitsurei core standard](mori://shinzui/haskell-jitsurei/docs/core-standards), [records](mori://shinzui/haskell-jitsurei/docs/core-record-patterns), and [prelude](mori://shinzui/haskell-jitsurei/docs/core-custom-prelude). The concrete rules are GHC >= 9.12, GHC2024, a shared common stanza with `DeriveAnyClass`, `DuplicateRecordFields`, `OverloadedLabels`, and `OverloadedStrings`, strict unprefixed record fields, explicit deriving, postpositive qualified imports, and lens-based access/update. `PackageImports` is local to `Shoko.Prelude`; generic-lens's orphan label instance stays out of that prelude and public type modules.

The template dry run was accepted during planning and reported 11 files, zero conflicts. Mori indexed template version 0.14.0, whereas upstream HEAD `07bae55c1dc2d1678bc985c1402b97758292a13f` declares 0.26.0; the local source also had unrelated uncommitted changes. These are observations, not pins. Use the installed template only after checking its published registry source and immutable revision; do not copy another checkout's working changes. Its supported default at inspection was `ghc9124` (GHC 9.12.4). Recheck support at implementation time, retaining Jitsurei's minimum.

## Plan of Work


### M1 — Load the shared development environment


Resolve the template with Mori, inspect its README and module variables, and preview generation. Apply `nix-haskell-flake` itself, with process-compose and PostgreSQL enabled, optional Redis/ClickHouse/Kafka/Redpanda disabled, treefmt and pre-commit enabled, and `nix.builtin-package=false`. A Nix flake records reproducible build inputs; process-compose manages local services. Keep the generated flake and `nix/` modules managed. Copy `flake.module.nix.example` to the unmanaged `flake.module.nix` and add Shōko-specific outputs there. Save resolved variables in `.seihou/config.dhall` without removing existing keys. Do not use Seihou's automatic commit option.

Track the generated lock and modules before Nix evaluation, since Git-based flakes omit untracked inputs. Verify compiler and Cabal availability. Confirm evaluation does not rewrite the lock. Record template origin/version and selected compiler in new `docs/development.md`; the document should explain how to reapply or upgrade through Seihou.

### M2 — Build a real library workspace and run checks


Create `cabal.project`, `shoko-core/shoko-core.cabal`, `shoko-core/src/Shoko/Prelude.hs`, `shoko-core/src/Shoko.hs`, and `shoko-core/test/Main.hs`; name the test suite `shoko-core-test`. Establish `-Wall`, `-Wcompat`, `-Widentities`, `-Wincomplete-uni-patterns`, `-Wincomplete-record-updates`, and `-Wredundant-constraints`; first-party CI treats warnings as errors without globally imposing that on third-party builds. All components import the same common stanza. Keep the prelude small and do not invent placeholder scenario semantics. A minimal public build/version value and a compiled test consumer are sufficient to prove package visibility; the core plan replaces this scaffold with meaningful behavioral tests.

Use Tasty/Hedgehog for later deterministic and property checks, obtaining APIs and source locations with Mori before adding dependencies. Verify current Hackage versions and upstream tags before selecting compatible bounds; establish an exact reachable Cabal `index-state` and a reproducible solver selection. Add `docs/dependencies.md` with registry URLs, canonical Mori owners, inspected upstream revisions, and the rationale for any deviation from released versions. Recheck dependencies again when later plans introduce them. Do not bake the research's surveyed versions into the build or silently relax bounds when legacy Message DB and Kiroku constrain different Hasql versions.

Define the multi-package Nix build in `flake.module.nix`, initially containing only core, plus a check that runs its tests. Add a `justfile` with `build`, `test`, `check`, and `fmt` recipes. Here `check` runs the build, tests, and `nix flake check`; `fmt` runs `nix fmt`. Add `.github/workflows/ci.yml` for a supported Linux runner using these same checks, and document the local macOS path. Do not depend on a developer's checkout paths. Register the package and relevant canonical dependency references in `mori.dhall`, preserving the research bundle. Update the existing `README.md` with the exact contributor commands and the bootstrap scope.

As later packages add integration suites, `just test`/`just check` must explicitly select self-contained unit/consumer suites; do not accidentally execute database-dependent tests through an unqualified `cabal test all` without their fixtures. EP-4 owns `just test-adapters`, EP-5 owns `just test-event-stores`, and EP-6 owns `just test-cli`; each recipe must set up its prerequisites and report real execution. CI runs the applicable local fixture recipes as they land. Staging acceptance is a separate explicit command and is never silently skipped or represented by a local check. Each package addition must prove a coherent Cabal solver selection and matching Nix package versions before acceptance; a successful core-only bootstrap does not certify later adapters or the host.

## Concrete Steps


Preview at the repository root; the same command without `--dry-run` performs M1 after the preview is reviewed by the implementer.

```bash
mori registry show shinzui/seihou-modules --full
mori path mori://shinzui/seihou-modules/templates/nix-haskell-flake
seihou run nix-haskell-flake --dry-run --no-commands --no-save-prompted \
  --var project.name=shoko \
  --var 'project.description=Evidence-based distributed behavior verification' \
  --var ghc.version=ghc9124 \
  --var nix.process-compose=true --var nix.postgresql=true \
  --var nix.redis=false --var nix.clickhouse=false \
  --var nix.kafka=false --var nix.redpanda=false \
  --var nix.treefmt=true --var nix.pre-commit=true \
  --var nix.builtin-package=false
```

After generation and package creation, stage only the new build inputs and run:

```bash
git add flake.nix flake.lock nix/ flake.module.nix cabal.project shoko-core/
nix develop --command ghc --numeric-version
nix develop --command cabal build all
nix develop --command cabal test all --test-show-details=direct
nix flake check
seihou diff
git diff -- flake.lock
```

The compiler meets the selected supported baseline, the library and test compile, all tests pass, and flake checks succeed. The final lock diff is empty after evaluation. Seihou reports no unexplained edits to generated Nix files; existing skill customization may appear separately and must be preserved.

## Validation and Acceptance


M1 passes when a fresh shell uses the intended compiler and Nix inputs without regenerating toolchain pins. M2 passes when the external test component imports the exposed core module, `just check` succeeds, and CI invokes the same commands. No database is required merely to import or test core. Verify formatting includes Haskell, Cabal, and Nix. Exercise documented commands from a clean checkout or a clean worktree with tracked flake inputs; an existing shell alone is insufficient proof of bootstrap usability. No live service acceptance belongs to this plan.

## Idempotence and Recovery


Use `seihou run ... --dry-run` and `seihou diff` before reapplication. Preserve the manifest/baselines and resolve only relevant generation conflicts; never force-overwrite unrelated files. Keep the current branch. Do not run a blanket flake update or modify toolchain revisions in generated files. If dependency resolution fails, record the conflicting bounds and solve a coherent released set or document a narrowly evidenced exception before continuing. Do not search `/nix/store` for source or patches.

## Interfaces and Dependencies


There are no child-plan prerequisites. This plan owns `cabal.project`, `flake.module.nix`, `justfile`, CI, `mori.dhall`, `docs/development.md`, `docs/dependencies.md`, and the shared style/common-stanza convention. Later plans add their own package modules and test targets through these extension points. The intended direction is `shoko-core` <- `shoko-adapters` <- `shoko-cli`, with the CLI also importing core. Production scenario hosts may import the libraries without taking the bundled CLI. Do not add database or HTTP dependencies to core.

Revision 2026-10-18: validate the scaffold preview, correct existing README context, and separate unit checks from fixture-backed suites as packages are introduced.
