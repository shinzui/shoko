---
name: release
description: Publish Shoko's Hackage packages (shoko-core, shoko-cli) following the Haskell PVP, with per-package independent versions, tags, and GitHub releases.
argument-hint: "[major|minor|patch]"
disable-model-invocation: true
allowed-tools: Read, Bash, Edit, Glob, Grep, Write, AskUserQuestion
---

# Shoko Release Skill

Publish Shoko's Hackage-released packages following the Haskell **PVP**
(`A.B.C.D`). This repository versions each package **independently**, so a
release run may cut a new version of one package, the other, or both — only
the packages that actually changed since their last tag are released.

## Versioning Strategy (PVP)

The Haskell PVP version format is `A.B.C.D`:

- `A.B` — **major**: breaking API changes (removed/renamed exports, changed
  types, changed semantics).
- `C` — **minor**: backwards-compatible API additions (new exports, new
  modules, new instances).
- `D` — **patch**: bug fixes, documentation, internal-only changes,
  performance improvements.

**Packages version independently** — they do *not* share a version number.
`shoko-core` is ahead of `shoko-cli` (currently `0.3.0.0` vs `0.2.0.0`). Each
package gets its own tag and its own changelog entry; bump each package
according to *its own* changes only.

## Packages (in dependency order)

Publish in this order because of the inter-package dependency:

1. **shoko-core** (`shoko-core/`) — core framework, no internal deps.
2. **shoko-cli** (`shoko-cli/`) — depends on `shoko-core` (`>=0.3 && <0.4`).

The following package is **NOT released** to Hackage:

- **shoko-adapters** (`shoko-adapters/`) — its library depends on
  `rdkafka-hs`, which is a git `source-repository-package` distributed as a
  GitHub release and is **not on Hackage** (see `cabal.project`). A package
  cannot be built from Hackage unless all of its dependencies are on Hackage,
  so `shoko-adapters` is intentionally internal. Its `shoko-core` version
  bound must still be kept in sync (see step 3) so the workspace keeps
  building, but it is never uploaded.

## Arguments

`$ARGUMENTS` is optional:

- `major`, `minor`, or `patch` — forces the bump level for every package
  being released this run.
- If omitted, infer the bump level per package from its changes (step 2).

## Steps

### 1. Determine what changed since each package's last release

- Read each publishable package's current version from its `.cabal` file:
  - `shoko-core/shoko-core.cabal`
  - `shoko-cli/shoko-cli.cabal`
- Find the latest tag **per package**. Tags are per-package and annotated,
  formatted `<pkg>-v<version>` (e.g. `shoko-core-v0.3.0.0`):
  - `git tag --list 'shoko-core-v*'`
  - `git tag --list 'shoko-cli-v*'`
- **First release:** if a package has no matching tag yet, this is its
  initial Hackage release. Do **not** bump it — publish the version already in
  its `.cabal` as-is, and create its first tag at that version.
- For a package that already has a tag, run
  `git log --oneline <pkg>-v<last>..HEAD -- <pkg-dir>` to list the commits
  touching that package since its last release. If a package has no commits
  since its last tag, it has nothing to release — skip it.

Present a summary table:

| Package | Current version | Last tag | Commits since | Action |
|---------|-----------------|----------|---------------|--------|
| shoko-core | … | … or "none (first release)" | … | release / skip |
| shoko-cli | … | … or "none (first release)" | … | release / skip |

If nothing is releasable, tell the user and stop.

### 2. Determine the next version per package using PVP

For each package being released (skip packages on their first release — their
version is already set):

- If `$ARGUMENTS` is `major`, `minor`, or `patch`, use that bump level.
- Otherwise infer the bump from that package's commits:
  - "breaking", "remove", "rename", "change type", `feat!`/`fix!` → **major**
  - "add", "new", "feature", "export" → **minor**
  - "fix", "docs", "refactor", "internal", "test", "chore" → **patch**
- Increment:
  - **major**: bump `B`, reset `C`/`D` to 0 (`0.3.0.0` → `0.4.0.0`)
  - **minor**: bump `C`, reset `D` to 0 (`0.3.0.0` → `0.3.1.0`)
  - **patch**: bump `D` (`0.3.0.0` → `0.3.0.1`)

Present the proposed bump(s) and **ask the user to confirm** before editing
anything.

### 3. Update versions, internal bounds, and changelogs

#### Versions

- Edit each releasing package's `.cabal` `version:` field to the new value.

#### Internal dependency bounds

- `shoko-cli` and `shoko-adapters` both declare `shoko-core >=0.3 && <0.4`.
  If `shoko-core`'s **major** (`A.B`) changes this release, update that bound
  in **both** `shoko-cli/shoko-cli.cabal` and
  `shoko-adapters/shoko-adapters.cabal` (keep `shoko-adapters` building even
  though it is not published), to the new `>=A.B && <A.(B+1)` range.
- If `shoko-cli` gains a dependency on the newest `shoko-core` API, raise its
  lower bound accordingly.

#### Changelogs

- `shoko-core/CHANGELOG.md` exists — add a new `# <version>` section at the
  **top**, above the previous entries, summarizing the changes.
- `shoko-cli` has **no** `CHANGELOG.md` yet — when releasing it, create
  `shoko-cli/CHANGELOG.md` with a `# <version>` section. Ensure
  `extra-doc-files: CHANGELOG.md` is listed in `shoko-cli.cabal` (add it if
  missing) so the changelog ships to Hackage.
- Match the existing changelog style: a `# <version>` heading followed by
  prose paragraphs (grouping breaking/new/fix/other as needed). Follow the
  tone of the existing `shoko-core/CHANGELOG.md` entries.

Show the user **all** changes (versions, bounds, changelog text) for review
before committing.

### 4. Verify (mandatory gates)

Run, in order, and stop on the first failure:

1. `just fmt` — formats everything (`nix fmt -- --formatters cabal-gild`
   then `nix fmt`: fourmolu + cabal-gild + nixpkgs-fmt). Ensure the tree is
   clean afterward.
2. `cabal build all` — must build (the workspace uses `-Werror`).
3. `nix flake check` — treefmt + pre-commit gates.
   - Newly created files (e.g. a brand-new `shoko-cli/CHANGELOG.md`) must be
     `git add`-ed first: Nix evaluates the git tree, so untracked files are
     invisible to the check.

> Optional but recommended: run the pure unit suites before publishing —
> `cabal test shoko-core-test` and, when releasing the CLI,
> `cabal test shoko-cli-test`. The adapter/kafka/event-store/email suites
> need external infrastructure and are **not** release gates.

If any gate fails, fix it before proceeding.

### 5. Commit, tag, and push

- Stage the modified `.cabal` and `CHANGELOG.md` files.
- Create one Conventional Commits commit. For a single package:
  `chore(release): shoko-core <version>`. For both:
  `chore(release): shoko-core <v>, shoko-cli <v>`. The body summarizes what's
  in each release and why the bump level was chosen.
- Create an **annotated** tag per released package, at that commit:
  - `git tag -a shoko-core-v<version> -m "shoko-core <version>"`
  - `git tag -a shoko-cli-v<version> -m "shoko-cli <version>"`
- Push: `git push && git push --tags`.

### 6. Publish to Hackage (in dependency order)

For **each released package**, in order (`shoko-core` → `shoko-cli`):

1. `cd <pkg-dir>`.
2. `cabal check` — verify no packaging issues.
3. `cabal sdist`, then
   `cabal upload --publish <dist-newstyle/sdist/<pkg>-<version>.tar.gz>` to
   publish the source distribution (**irreversible**).
4. `cabal haddock --haddock-for-hackage --haddock-hyperlink-source --haddock-quickjump`,
   then `cabal upload --publish --documentation <docs-tarball>` to publish
   the Haddock docs.
5. Report the Hackage URL:
   `https://hackage.haskell.org/package/<pkg>-<version>`.

> Requires Hackage upload rights for each package and credentials configured
> for `cabal upload` (`~/.config/cabal/config` or `HACKAGE_*` env). `--publish`
> cannot be undone.

After publishing, present:

| Package | Version | Hackage URL |
|---------|---------|-------------|
| shoko-core | … | https://hackage.haskell.org/package/shoko-core-… |
| shoko-cli | … | https://hackage.haskell.org/package/shoko-cli-… |

(Only the packages released this run.)

### 7. Create GitHub releases (one per published package)

After **all** Hackage uploads for this run succeed, create a GitHub release
for each released package's tag:

```bash
gh release create shoko-core-v<version> \
  --title "shoko-core <version>" \
  --notes "$(cat <<'EOF'
Hackage: https://hackage.haskell.org/package/shoko-core-<version>

<the new CHANGELOG.md section for this version>
EOF
)"
```

Use the package's own `CHANGELOG.md` section as the notes body, include the
Hackage link, and report each GitHub release URL.

## Important

- **Confirm the bump level and changelog text with the user before
  committing** — the commit and tags are created only after approval.
- Each package versions **independently**; bump, tag, and changelog them
  separately. Do not force a shared version.
- Always publish in dependency order: `shoko-core` → `shoko-cli`.
- Never skip the gates (`just fmt`, `cabal build all`, `nix flake check`).
- If any step fails, **stop and report** — do not continue.
- If a Hackage upload fails, do **not** continue publishing packages that
  depend on it (e.g. a failed `shoko-core` upload blocks `shoko-cli`).
- Never upload `shoko-adapters` — it is internal (non-Hackage `rdkafka-hs`
  dependency).
- `cabal upload --publish` is irreversible; a version number can never be
  reused on Hackage.
