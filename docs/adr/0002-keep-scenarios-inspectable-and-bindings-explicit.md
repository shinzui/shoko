# Keep scenarios inspectable and bindings explicit

Date: 2026-10-01

Status: Accepted for bootstrap

## Context

[RES-1](../research/initial-specification-requirement-validation.md) identifies inconsistent DSL examples (F3), competing safety models (F2), a closed environment enumeration (F10), and implementation-dependent correlation (M5). Inspection cannot be trustworthy if collecting an action list executes arbitrary scenario IO.

## Decision

Use an inspectable, typed scenario description with an effectful interpreter. A description is data identifying operations and their dependencies; an interpreter supplies how those operations execute. The canonical surface is `scenario id title`, `given`, `act`, `expect`, `eventually`, `never`, `exactlyOnce`, and `within`. Use `act` instead of the conflicting `when`. Fixture and action results are typed symbolic references (`Ref a`), resolved during execution. Constructing the description never performs IO; runtime values cannot choose hidden branches that were absent from inspection. Initial composition is a fixed action sequence followed by an expectation group, with explicit reference dependencies. Arbitrary runtime branching, a general workflow graph, and user-defined scheduling are deferred.

The scenario declares the complete required operation set. Each binding maps those typed operation descriptions to handlers and contributes its actual capability requirements, evidence-source identity, and supported correlation strategies. Preflight checks their union before acquiring external resources or running fixtures. The runner also enforces the resolved plan so a binding cannot quietly dispatch an undeclared operation. This checks supported Shōko code, not arbitrary untrusted Haskell supplied by an attacker.

Capabilities are value-level sets rather than a linear safety rank. The initial vocabulary is `ReadState`, `ReadEvents`, `WriteState`, `SendHttp`, `ExternalSideEffect`, and `SyntheticResource`. Fixtures, actions, and cleanup declare their capabilities. An environment is a named configuration value with an allowed set, durations, polling policy, endpoints, and an explicit fail-closed policy. Implementation is a separate binding identifier for the actual deployed system, with `legacy` and `keiro` as possible later comparison bindings, and never widens environment permissions. A production-labelled environment denies mutation by default; synthetic mutation requires both policy permission and per-run opt-in. The first real execution target is the existing complete staging system in a Kubernetes test namespace. CI is an optional caller of the same runner. Production execution itself is outside this bootstrap.

Use [Settei](mori://shinzui/settei/packages/settei) for typed configuration declarations, resolution, defaults, provenance, and secret-safe diagnostics at the CLI/host boundary. Use its [YAML](mori://shinzui/settei/packages/settei-yaml), [environment](mori://shinzui/settei/packages/settei-env), and [optparse-applicative](mori://shinzui/settei/packages/settei-optparse-applicative) adapters. The low-to-high precedence is declared defaults, one explicit YAML file, explicitly bound environment variables, then supported named CLI options. Invalid winning values are errors, never reasons to fall back to a lower layer. Reject unknown keys. Keep the configuration declaration authoritative; a documented JSON Schema artifact must agree with it rather than define an independent decoder.

Environment/CLI bindings expose only approved operational settings; they cannot override capability grants. Keep `--allow-synthetic` as explicit per-run consent, not a value a config file or ambient environment can turn on. Declare credential values Secret in Settei and use its safe error/report renderers. Resolve non-secret configuration and credential references for inspection; resolve required credential values only for a live run, so inspection remains useful without secrets. Settei feeds typed values into Shōko's environment and policy types; capability checks and scenario semantics remain owned by `shoko-core`, whose API does not depend on a file format or on Settei.

Correlation is explicit. Use `ByBusinessKey` with a named key and value for legacy; for registration that key is `registrationId`. Use `ByExecutionId` only when a binding proves propagation into durable evidence. A runner-generated execution identifier always labels its own report, but does not prove remote propagation. Prefer execution correlation only from declared and tested binding support; report the selected strategy. Missing required correlation yields `Unknown/CorrelationLost`, not a broad uncorrelated search or silent fallback. A business-key fallback can be selected before execution when the scenario permits it.

Named scenarios may describe positive and negative behavior. A declared operation response contract can expose a specific domain rejection as a typed result, with sanitized response evidence attached to its symbolic reference. Expectations can then assert that the rejection occurred and that downstream invariants hold. Such a negative scenario returns Pass when the expected behavior is established. Unexpected success/rejection yields Fail; transport or decoding uncertainty yields Unknown. There is no global error-inversion switch and no assumption that any non-2xx HTTP response is the intended rejection.

The host integration resolves actual staging target/deployment identity and passes typed metadata into core. Core owns scenario policy; it does not discover Kubernetes resources or manage application deployments. A namespace name or staging label alone cannot establish that configured databases, brokers, or external endpoints are permitted. Match them to the explicit target contract before mutating actions.

## Consequences

Inspection and execution consume the same scenario and resolved binding plan. The implementation starts with runtime policy validation; type-level capability enforcement is deferred. `observe` mode, replay, and causality operators remain future work. If a later feature requires runtime branching, its inspection and capability rules must be designed explicitly before it enters the public DSL.

Revision 2026-10-01: select Settei explicitly after the configuration discussion, replacing the unspecified configuration implementation with its typed resolver and existing source adapters. The capability-policy boundary is unchanged.

Revision 2026-10-01: make existing Kubernetes staging the first execution target and define explicit typed outcomes for positive and negative scenarios.
