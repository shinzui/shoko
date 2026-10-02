---
id: 6
slug: expose-scenario-inspection-execution-and-structured-reports
title: "Expose scenario inspection execution and structured reports"
kind: exec-plan
created_at: 2026-10-02T03:52:03Z
intention: "intention_01m3xdacr3exqajqfcgh9btgev"
master_plan: "docs/masterplans/1-bootstrap-shoko-for-evidence-based-workflow-parity.md"
provenance:
  created_by:
    model: "gpt-6-astra"
    harness: "codex-cli"
    at: 2026-10-02T03:52:03Z
  revisions:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-02T04:14:56Z
      mode: "discuss"
      note: "Select Settei for typed YAML, environment, and CLI configuration with provenance and secret-safe diagnostics."
---

# Expose scenario inspection execution and structured reports


This ExecPlan is a living document. Keep CLI behavior and protocol examples aligned with the core contract.

## Purpose / Big Picture


A user can list, inspect, and run compiled scenarios with named environment/implementation bindings and receive readable or machine-readable evidence. CI can distinguish a failed system expectation from an inconclusive observation using stable exit codes, and application owners can build their own scenario host without modifying Shōko's generic CLI.

## Progress


- [ ] M1: The CLI lists and explains a compiled scenario registry and validates configuration/policy without running actions.
- [ ] M2: Run produces stable text/JSON reports and exit codes, with bounded execution, correlation disclosure, and redaction.
- [ ] M3: A separate application-style host imports the CLI library and runs its own registry through the same command protocol.

## Surprises & Discoveries


## Decision Log


On 2026-10-01, use compiled scenario registries and a reusable CLI host function. Runtime loading/compiling arbitrary Haskell is unnecessary for bootstrap and would obscure ownership of domain vocabularies. The bundled executable contains labelled demos only.

On 2026-10-01, select Settei and its YAML/environment/optparse adapters for configuration resolution, provenance, defaults, and secret-safe diagnostics. Keep configuration loading in the CLI/host package and pass typed environment/policy values to core. Do not write a competing layering or YAML-decoding framework.

On 2026-10-01, make the configured existing staging deployment the first real Run target. CI denotes optional invocation automation; inspection remains effect-free and live target checks stay in the integration layer. Support separately named positive/negative scenarios through the same registry and exit contract.

## Outcomes & Retrospective


## Context and Orientation


`docs/plans/3-implement-inspectable-scenarios-and-the-bounded-verification-runner.md` supplies the inspection/resolution/runner API and result codecs. It is the sole hard dependency. The foundation already defines Nix, Cabal, CI, and style conventions. SQL/HTTP and event-store work are soft dependencies for richer demos; deterministic in-memory handlers can fully prove this CLI contract.

[ADR 0002](../adr/0002-keep-scenarios-inspectable-and-bindings-explicit.md) requires configuration-based environments, separate implementation bindings, and policy preflight. [ADR 0003](../adr/0003-record-bounded-evidence-and-three-valued-results.md) fixes verdicts and process exits. [ADR 0004](../adr/0004-gate-parity-on-real-workflows-and-context-owned-vocabulary.md) keeps production domain vocabulary outside the generic executable. Follow [ADR 0001](../adr/0001-use-jitsurei-standards-and-the-seihou-haskell-flake.md) and select relevant [Jitsurei CLI patterns](mori://shinzui/haskell-jitsurei/docs/cli-overview), especially help, option groups, and [version identity](mori://shinzui/haskell-jitsurei/docs/cli-version-git-sha); do not add interactive fuzzy finding or agent-assist commands unrelated to this task.

[Settei](mori://shinzui/settei) supplies the configuration implementation. Its inspected `Settei.Resolve` API resolves sources from low to high precedence, defaults to warning on unknown keys, and provides `RejectUnknownKeys` for strict resolution. Its `Settei.Yaml` loader preserves file locations and rejects duplicate/dotted mapping keys. `Settei.Env` supports explicit variable bindings and injectable snapshots; `Settei.Optparse` supplies named option sources and safe origin labels. Use those public modules, resolving their current sources through Mori before coding. Check Hackage and upstream release tags before selecting compatible package bounds; no version is pinned by this plan.

## Plan of Work


### M1 — Host and inspect a typed registry


Create `shoko-cli/shoko-cli.cabal`, with a library exposing `Shoko.Cli` and `Shoko.Cli.Registry`, and executable `shoko` with `shoko-cli/app/Main.hs`. Add internal modules `Shoko.Cli.Options`, `Config`, and `Report` under `shoko-cli/src/`. Use a verified optparse-applicative API located through Mori and select released dependency bounds through the established dependency process. A registry contains stable scenario IDs, descriptions, versions, binding factories, and supported environment names. Export `runShokoCli` accepting that registry so a domain owner can compile its own host. Do not use unsafe dynamic module loading.

Implement `list`, `explain SCENARIO`, `check SCENARIO`, and `run SCENARIO`. `explain` renders the static description, binding-selected source/correlation/capability requirements, effective budgets, and unsupported requirements without acquiring resources. `check` validates the resolved policy and configured binding compatibility, with no action, fixture, or cleanup execution and no live service-readiness claim. The separate staging integration checker owns live target identity, connectivity, and service readiness.

Declare a typed `Settei.Config ShokoConfig` in `Shoko.Cli.Config`, using `settei`, `settei-yaml`, `settei-env`, and `settei-optparse-applicative`. Keep `schemas/config-v1.schema.json` as a checked documentation/validation artifact matching the declaration, with examples in `config/demo.yaml`; do not assume Settei's own description format is JSON Schema. The declaration names environments, implementation binding names, expected target identity/access references, endpoint/connection environment-variable references, policy sets, total/eventually/poll durations, and redaction configuration. Resolve declared defaults, one explicit `--config` YAML source, explicitly mapped environment variables, and supported named CLI option sources in that low-to-high order. Do not search for ambient config files, interpolate arbitrary environment strings in YAML, or add unrelated formats. Use nested YAML mappings, `readYamlSource`, and strict `RejectUnknownKeys`; invalid winning values fail instead of falling back. Update `docs/dependencies.md` with the selected released package family and registry/tag evidence when adding bounds.

Keep optparse-applicative for subcommands and adapt supported named configuration options through Settei. `--environment`, `--implementation`, and `--format text|json` may override their corresponding operational settings. Only explicitly bound operational environment variables participate. Capability grants cannot be overridden by either source, and no unrestricted generic `--set` surface is required. Keep `--allow-synthetic` as a separate explicit per-run consent flag which still requires policy permission; neither YAML nor an environment variable can supply that consent. Checked demo defaults are local-only.

Separate non-secret configuration/credential-reference resolution from live credential resolution. Inspection/check can show missing credential variable names without reading secret values or acquiring adapter resources; a live run requires its credentials. Mark resolved credential values with Settei's Secret sensitivity and use its safe error/report renderers, never `Show` on the typed config or raw YAML/environment input. Include redacted winning and shadowed source origins in the scenario explanation. Source-loading, decoding, and resolution errors map to Shōko exit 2; do not copy the example Settei CLI's distinct exit codes into this application's verification protocol. Reject invalid durations, unsupported modes, and unknown environment/implementation names before runner effects.

### M2 — Execute once and report truthful outcomes


Run exactly the resolved scenario from core. Keep action retry, polling, aggregation, and coverage semantics in core. Text reports lead with Pass/Fail/Unknown and show per-expectation reasons, correlation mode, actual source/binding, and searched intervals. JSON uses the core codec with no stdout banners/logs; diagnostics use stderr. `--output PATH` atomically persists the same result if requested, without overwriting a different run's evidence implicitly. A killed run must not leave a partial file labelled as a complete result.

Use exits 0 Pass, 1 Fail, 2 usage/configuration/policy error, 3 Unknown including unavailable evidence, and 4 unexpected runner faults. A typed Unknown must never be projected to Pass by a CI wrapper. Include stable scenario ID/version and the running binary's version/source revision; report dirty builds honestly. Redact credentials/OTP/personal payloads consistently with binding rules. Staging Run mode is supported against the configured approved target; operator and optional CI invocations use the same host and result semantics. Production execution, continuous Observe, Replay, and input capture remain unsupported and fail with an explicit message before effects.

### M3 — Prove the downstream host boundary


Provide demo scenarios `demo-account-created`, `demo-missing-evidence`, and `demo-source-unavailable` using the core toy vocabulary or equivalent labelled test fixtures. Add a test consumer executable under `shoko-cli/test/ConsumerHost/` with its own registry and domain operation vocabulary; it links the public libraries exactly as a future context-owned host would. Add `shoko-cli-test` and `scripts/test-cli`, exposed as `just test-cli`, to capture stdout/stderr, parse JSON, and assert actual process exits. Document host integration in `docs/scenario-hosts.md`, and update the README's quickstart.

## Concrete Steps


At the repository root after core acceptance:

```bash
mori registry search optparse-applicative
mori registry show shinzui/settei --full
mori registry docs shinzui/settei
mori path mori://shinzui/settei/packages/settei
mori path mori://shinzui/settei/packages/settei-yaml
mori path mori://shinzui/haskell-jitsurei/docs/cli-overview
mori path mori://shinzui/haskell-jitsurei/docs/cli-version-git-sha
nix develop --command cabal run shoko -- list
nix develop --command cabal run shoko -- explain demo-account-created --config config/demo.yaml --environment local --implementation demo
nix develop --command cabal run shoko -- run demo-account-created --config config/demo.yaml --environment local --implementation demo --format json
nix develop --command just test-cli
nix develop --command just check
```

The demo run emits a versioned JSON result with Pass. Tests invoke the built binary directly (for example, locate it with `cabal list-bin shoko`) to assert process exit codes without Cabal progress output. The missing-evidence demo returns Fail/1; the unavailable-source demo returns Unknown/3. The registry labels every fixture/demo clearly.

## Validation and Acceptance


Inspect/check with all handler counters installed: no fixture, HTTP, SQL, or cleanup call occurs. Reject a policy mismatch before effects. Parse stdout as exactly one JSON document for all report modes; diagnostics never contaminate it. Test actual exit codes for all five classes, invalid config/unknown keys, unavailable sources, credential redaction, interrupted output, and per-run synthetic opt-in without policy escalation. A second compiled host lists and runs its own scenario using `runShokoCli`; this is the early producer/consumer check for the final application integration. `--help` explains environment/implementation/mode distinctions and `--version` identifies the actual build. A demo pass must not use a real workflow ID or claim staging acceptance or TAN parity. A consumer registry must list/select independent positive and negative scenarios: expected typed rejection produces Pass, an unexpected response produces Fail, and unavailable evidence produces Unknown without a catch-all failure inversion.

Exercise the actual Settei producer/consumer path with a YAML fixture, injected environment snapshot, and parsed named CLI overrides: verify the documented precedence, retained safe provenance, and failure on an invalid highest-precedence value. Reject unknown and duplicate YAML keys and keep absent versus empty environment values distinct. A secret sentinel must be absent from stdout, stderr, errors, warnings, and all explanation/report artifacts, including failed resolution. Prove inspection succeeds with unresolved credential references while the corresponding live run fails preflight with exit 2. YAML or environment input cannot supply per-run synthetic consent; unsupported YAML keys/CLI options are rejected and unmapped environment variables have no effect. The file may define capability grants, but environment/CLI sources cannot override them. Check the schema artifact and examples against the typed declaration to catch drift.

## Idempotence and Recovery


CLI tests use temporary output directories and in-memory handlers by default. Never overwrite another run's result; use unique IDs and atomic file replacement only for the current run's temporary file. Re-run failed invocations without implicitly retrying mutations. Preserve primary results when report persistence fails and return a clear nonzero command error. Configuration errors require a corrected input, not a broadened policy.

## Interfaces and Dependencies


Hard dependency: Complete `docs/plans/3-implement-inspectable-scenarios-and-the-bounded-verification-runner.md`. Soft dependencies: `docs/plans/4-implement-postgresql-and-http-evidence-bindings.md` and `docs/plans/5-implement-kiroku-and-message-db-evidence-bindings.md` for optional concrete registrations. Core owns result JSON and runner semantics; this plan owns CLI command syntax, config decoding, scenario registry/host API, text reports, exit-code projection, and config schema. The final staging plan consumes `runShokoCli` from a context-owned host and adds no TAN types to the generic CLI. Shared Cabal/Nix/CI files extend the foundation's conventions.

Settei's four selected packages are dependencies of `shoko-cli`, not of `shoko-core`. The reusable host API supplies the same declaration/resolution path to downstream applications, so the final staging host does not implement a second YAML loader or change precedence. Settei owns parsing/layering/provenance mechanics; Shōko owns settings, validation rules, allowed override surfaces, policy enforcement, and verification exit codes.

Revision 2026-10-01: make Settei the explicit configuration dependency and add precedence, secret handling, and consumer acceptance checks following the configuration discussion. CLI scope and child dependencies are unchanged.

Revision 2026-10-01: support the existing staging target and independently named positive/negative scenarios; CI invokes the same host rather than defining another target environment.
