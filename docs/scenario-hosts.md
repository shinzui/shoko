# Compiled scenario hosts

The generic `shoko` executable contains labelled in-memory demos. A domain owner
defines its own vocabulary, scenarios, and implementation bindings in a separate
application that imports `Shoko.Cli`. No runtime Haskell compilation is involved.
The independently compiled example is `shoko-cli/test/ConsumerHost/Main.hs`.

The host exports a `Registry` of supported environment names and `Entry` values.
Each entry packages a typed scenario with its own correlation declarations, a safe logical-input
summary, named binding factories, and a live metadata callback. `SomeBinding`
hides each implementation's resource type while preserving its operation GADT.
The application's `main` calls `runShokoCli registry`; embedders can instead use
`executeCli registry arguments` to receive a captured `CliRun`.

The independent host also registers `registration-alone`, `registration-reused`,
and `composed-registration` from
[`Registration.hs`](../shoko-cli/test/ConsumerHost/Registration.hs). One concrete
`registrationBlock` backs both standalone scenarios and appears twice under
namespaces in the composed scenario. `hoistScenarioBuilder` preserves its returned
reference and correlation handle while lifting it into a registration/accounts
vocabulary sum. `combineBindings` acquires fresh state for both contexts.

```bash
nix develop --command cabal run shoko-consumer-host -- explain composed-registration
nix develop --command cabal run shoko-consumer-host -- run composed-registration --format json
nix develop --command cabal run shoko-consumer-host -- run registration-alone --format json
nix develop --command cabal run shoko-consumer-host -- run registration-reused --format json
```

Explanation shows `inviter.qualified`, `invitee.qualified`, the correlation IDs
`inviter.registration`, `invitee.registration`, and `account`, their semantic keys,
and each expectation's selection. Runs exit 0 with schema-valid v2 reports. The
composed report resolves two distinct registrations and the invitee's account.
Each standalone process starts its fixture allocation at one, with independent
scenario and run IDs. These are in-memory verifier examples.

To reuse a workflow from an existing scenario, extract the builder definition and
retain an explicit `scenario id title revision (block >> pure ())` wrapper for
each verification. Update each wrapper's revision when the shared recipe changes.
A finalized scenario is not concatenated with another scenario. Deferred
expectations all activate after the last action in the finished scenario.

Factories are pure: they construct binding metadata without acquiring resources,
reading credentials, or discovering targets. Inspection calls them with `Nothing`
for credentials. For live execution, the CLI first checks configuration and policy,
resolves declared credential references, calls the host metadata preflight, and
resolves the credential-backed binding again before acquiring resources. Put
resource IO in the binding's scoped acquisition/handlers. Extra requirements in a
live binding still undergo core policy resolution.

The metadata callback runs only for `run`. It returns observed implementation and
target identity, or rejects the target. Configured `target` fields are expectations,
never evidence of the actual deployment. If provided, they must match the callback's
observed identity before any scenario resources are acquired. The staging host must
also verify approved endpoints/access, workload digests, and before/after identity
under its integration contract. Generic `check` does not perform live readiness
checks. Core and the CLI do not manage application deployments.

Use opaque, non-secret business identifiers for correlation. Never use an OTP,
credential, email address, or personal payload as an automatically retained identity.
Handlers expose only explicitly safe `PublicValue` summaries. The core never
serializes raw typed inputs or outcomes.

From the workspace root:

```bash
nix run . -- list
nix run . -- explain demo-account-created --config config/demo.yaml
nix run . -- check demo-account-created --config config/demo.yaml
nix run . -- run demo-account-created --config config/demo.yaml --format json
nix develop --command just test-cli
```

Commands select one compiled scenario. `explain` shows the description, binding
requirements, sources/coverage, correlation, budgets, and winning/shadowed configuration
origins. `check` validates the same policy without fixtures, baselines, actions,
observations, cleanup, live metadata callbacks, or credential-value lookups.
`run` executes the core runner once. Observe, Replay, and production are unsupported.

Configuration uses Settei 0.2.0.0. Its authoritative declaration is
`Shoko.Cli.Config.declaration`; `schemas/config-v1.schema.json` documents the same
keys and types and is checked by the process suite. Low-to-high precedence is
declared defaults, one explicit `--config` YAML file, explicitly bound operational
environment variables, and supported named options. Unknown/duplicate/dotted YAML
keys and invalid winning values are errors. There is no ambient config discovery,
arbitrary string interpolation, or generic `--set` option.

| Configuration | Operational environment variable | Named option |
| --- | --- | --- |
| `runtime.environment` | `SHOKO_ENVIRONMENT` | `--environment` |
| `runtime.implementation` | `SHOKO_IMPLEMENTATION` | `--implementation` |
| `output.format` | `SHOKO_FORMAT` | `--format text\|json` |
| `policy.executionMs` | `SHOKO_EXECUTION_MS` | — |
| `policy.eventuallyMs` | `SHOKO_EVENTUALLY_MS` | — |
| `policy.pollMs` | `SHOKO_POLL_MS` | — |
| `policy.cleanupMs` | `SHOKO_CLEANUP_MS` | — |

YAML's `policy.capabilities` contains capability names such as `ReadState` and
`WriteState`. Environment variables and named options cannot enlarge this set.
Synthetic operations require both its `SyntheticResource` grant and the explicit
per-run `--allow-synthetic` flag. YAML and ambient environment cannot supply consent.

Optional `access.endpointEnv`, `access.connectionEnv`, and `access.tokenEnv` contain
environment-variable names. A live run requires each referenced value to be present
and nonempty. Values resolve through a separate Settei `Secret` declaration;
inspection reports reference names without looking up their values. The binding
uses `credential variableName credentials` inside acquisition to obtain a value.
Do not put secret values directly into YAML. Optional `target.name`,
`target.namespaceUid`, and `target.deploymentRevision` must be supplied together.
`redaction.extraFields` can remove additional logical-parameter/supporting-data
fields by name; it cannot enable raw payload rendering or disable mandatory secrecy.

JSON run output is exactly one core v2 document on stdout; diagnostics use stderr.
Text output starts with the verdict and retains expectation reasons, source,
correlation, searched intervals, and disposition. Exit codes are 0 Pass, 1 Fail,
2 usage/configuration/policy/target preflight, 3 Unknown, and 4 runner/command fault.
Expected domain rejection returns Pass when its negative expectations hold.

`--output PATH` creates a completed JSON result file atomically using a temporary
file in the target directory and an exclusive hard link. The parent directory must
exist. It never replaces an existing file, including under concurrent writers.
Interrupted execution leaves no completed evidence file. Persistence failure keeps
the primary report on stdout and returns exit 4. Build identity includes package
version and source revision with explicit dirty/unrecorded status; dirty local
builds should not be treated as pinned release builds.

Revision 2026-10-19: move correlation declarations into scenarios, use handler-based
compiled bindings, and demonstrate shared concrete workflows in independent and
combined hosts with v2 reports.
