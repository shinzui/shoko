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

The first public implementation uses `scenario id title revision`. Context-owned `Vocabulary op` GADTs describe each operation's public identifier, capability set, symbolic dependencies, and composite substep inventory. Applicative `Input` values combine typed references without inspecting runtime fixture values; inspection omits literal payloads. Named fixture/action nodes carry explicit allowed outcome tags. The scenario revision must change when predicate or recipe semantics change, because functions and secret inputs do not belong in the canonical public description. Binding metadata contributes additional capabilities, cleanup requirements, sources, and correlation support before acquisition.

The effectful dynamic interpreter belongs below the description. A binding's typed resource encloses acquisition, pre-action baselines, fixed actions, concurrent sibling expectations, and finalization. Symbolic values are stored with `Typeable` and resolved by checked `Dynamic` lookup; a missing value never creates an uncorrelated fallback. The text-valued result of a named action can supply business-key correlation through `businessKeyFromResult`. See the [public core guide](../core.md) and compiling consumers for the accepted interface.

Binding contracts are role-aware: supporting an operation as an observation does not advertise a fixture/action handler for it. Resolution checks the requested role before acquisition. Native bindings must also enforce that requested input keys agree with the selected correlation, rather than silently broadening the query.

Revision 2026-10-01: select Settei explicitly after the configuration discussion, replacing the unspecified configuration implementation with its typed resolver and existing source adapters. The capability-policy boundary is unchanged.

Revision 2026-10-01: make existing Kubernetes staging the first execution target and define explicit typed outcomes for positive and negative scenarios.

Implementation clarification, 2026-10-18: generic SQL descriptors always add a
selected business-key predicate; REST reads inject that key through a declared
query parameter. Neither transport provides a broad-read fallback. HTTP endpoint
allowlists fix destinations and methods before acquisition; metadata adds mutation
and explicit external-effect capabilities. Native transport records without
`Generic` use their library's public record API at this boundary. No orphan
`Generic` or rendering instance is introduced for third-party resources.

Implementation clarification, 2026-10-18: compiled registry entries package their
context-owned GADT, scenario, logical recipe, correlation, implementation factories,
and a live target-metadata callback. Factories are pure and called without secrets
for inspection. Resolve only explicitly mapped operational variables during
inspection; resolve referenced credential values through a separate Settei Secret
declaration only after live policy preflight. Recheck the resulting binding before
acquisition. YAML can declare grants, while environment/named CLI sources cannot
enlarge them. Synthetic consent is a separate CLI-only flag.

Host configuration accepts one explicit YAML file and rejects unknown keys.
Default/source mechanics remain Settei-owned, including invalid-winner behavior
and safe provenance. The JSON Schema artifact is checked against declared keys
and protocol examples, rather than supplying a second application decoder.

Event-reader integration, 2026-10-18: reader contract helpers consume only the
public source identity and pure query description. They must not require an
allocated reader. A compiled CLI factory can therefore resolve policy and
inspect without credentials or resource allocation, then create a fresh reader
inside `Binding.acquire`. Message DB's pure contract rejects unsupported
execution metadata before acquisition. The actual adapter consumer checks denied
policy leaves reader allocation at zero.

Planned API refinement, 2026-10-19: [ExecPlan 8](../plans/8-compose-verifications-from-reusable-scenario-vocabulary-and-binding-blocks.md)
adds namespaced fragments and deferred expectation declarations while retaining
the fixed action sequence and common expectation activation. Abstract handlers
own contract, source, and correlation metadata exposed through pure accessors.
Runtime input resolution becomes explicitly effectful so an undeclared access
is recorded even when its caller ignores the error; inspection remains pure.

Source-label equality is an author assertion about the same acquired reader,
not proof that capture functions or reader state are interchangeable. Composed
bindings must use distinct source labels, checked before acquisition. Resource
projection must also project source capture. Composition registers both children's
completed cleanup before returning, preserving reverse acquisition order and the
finite cleanup grace period without an extra composite disposition. Lifecycle
capabilities include unconditional cleanup even for unused components.

Scenario-owned business keys are global and have typed inputs; namespaces affect
node identifiers, not key names. Reserve `execution-id` for the execution strategy.
Its declaration makes the ID available to actions separately from an observation's
selected correlation. Declaring or transmitting it does not prove durable
propagation; that remains a tested binding/target contract. These refinements
are planned, not implemented by this ADR revision.

Composition refinement, 2026-10-19: the follow-up to ExecPlan 8 supersedes the
one-global-declaration-per-business-key restriction above. A correlation instance
has a namespaced ID and an abstract handle, separate from its unchanged semantic
key name. Observations explicitly select the handle; preflight checks its presence
and compatibility with the handler. Two reused registration blocks may therefore
select distinct entities with the same `registrationId` key. The execution handle
remains a single run-wide declaration, requested idempotently by reusable blocks.

Result-preserving vocabulary maps let a concrete `ScenarioBuilder f a` become
`ScenarioBuilder g a` without changing its producer or losing symbolic outputs.
They preserve namespaces, predicates, temporal windows, and correlation selections.
The reusable unit is the builder definition; finished scenarios retain separate
identities, revisions, lifecycles, and reports. Export a block beside a thin scenario
wrapper, then compose blocks before finalization. Finished-scenario concatenation
and intermediate verification checkpoints remain outside this API. These are
planned interfaces, with public consumer and process checks required by ExecPlan 8.

Haskell API refinement, 2026-10-19: ExecPlan 8 now distinguishes correlation
aliases, semantic business-key names, correlation IDs, source IDs, and absolute
monotonic timestamps with newtypes. Existing `Duration` represents relative
budgets. These are category distinctions, with explicit constructors and no
implicit string/numeric instances; validation remains responsible for contents.
Runtime reference failures have an `InputResolutionError` algebra, and pure
adapter construction failures have a `HandlerBuildError` algebra. Binding lookup
preserves both invalid construction (`Left`) and unsupported operations
(`Right Nothing`), so preflight retains the actual construction cause.

Vocabulary transformations are named `hoistAction`, `hoistObservation`,
`hoistExpectations`, and `hoistScenarioBuilder`. They preserve result types while
changing operations; ordinary `fmap` changes result values. Explicit sum injection
remains the foundation, with `Member` as optional convenience. These refinements
are planned and must pass the plan's public-consumer and type-boundary checks.

Implementation revision, 2026-10-19: namespaced builder blocks and named predicate
composition are implemented. `expectAfterActions` permits a block to declare its
consequences before later actions; it retains the fixed action sequence and starts
all observations after the last action. Strict `expect` retains its ordering check.
Namespace collection assigns symbolic references lexically, preserving returned
and external references without renaming operation or predicate identifiers.

Handler implementation revision, 2026-10-19: bindings are constructed from abstract
per-operation handlers. An observation handler owns its evidence source, baseline
capture, semantic correlation requirement, and contract; `focus` projects capture
and execution together. Equal labels within one binding assert shared reader
identity; coverage equality cannot prove equal closures. Preflight retains typed
handler-construction failures and validates role, source consistency, lifecycle,
and cleanup requirements before acquisition. Effectful input resolution records
undeclared accesses even when a handler ignores the returned error. Distinct
source/business-key identifiers and absolute monotonic timestamps prevent category
mistakes while preserving scalar wire representations.

Vocabulary composition revision, 2026-10-19: `(:+:)` combines context-owned
vocabularies; result-preserving `hoistAction`, `hoistObservation`,
`hoistExpectations`, and `hoistScenarioBuilder` lift concrete workflow definitions.
`Member` is optional convenience for distinct vocabularies in right-nested sums;
explicit `InL`/`InR` selects repeated vocabularies or other sum shapes. A workflow
block remains a builder returning symbolic values, while finalized scenarios own
independent identity, revision, resources, and reports.

`combineBindings` acquires both component resources, unions unconditional lifecycle
requirements, and registers completed leaf releases under masking. Cleanup runs
in reverse registration order under one shared grace deadline, including partial
acquisition failure and cancellation. Structural source-owner paths reject labels
shared by independently acquired components even when their coverage agrees.
Operation IDs with differing capability or substep inventories are definition
errors; per-use input dependencies may differ. Context owners remain responsible
for stable, meaningful operation IDs and shared reader identities.

Correlation implementation revision, 2026-10-19: scenarios now own their typed
correlation declarations. Each business declaration has a namespaced instance ID
and a separate semantic `BusinessKeyName`; observations explicitly select an
abstract `CorrelationRef`. There is no external correlation plan or implicit
unique-key/first-match fallback. Missing, undeclared, or incompatible selections
fail before acquisition. Shared sources retain one baseline while distinct
instances resolve independently, including repeated semantic key names.

The run-wide `execution-id` declaration is idempotent across namespaces and makes
`executionId` available to action contexts separately from observation selection.
Native handlers transport it explicitly; HTTP wrappers populate the payload label,
reject conflicts, and honor endpoint opt-in. This mechanism establishes transport,
not durable remote propagation or target-compatible ID formats. Those remain the
context owner's responsibility.

Completion revision, 2026-10-19: the `0.2.0.0` composition API is implemented and
exercised by independent finalized scenarios and repeated blocks in one host.
Composition occurs before finalization; it does not merge completed scenarios or
introduce intermediate verification checkpoints. After descriptor compatibility
checks, adapters execute the declared endpoint/query and retain the same acquired
reader state for capture and observation. Decoder identity remains the author's
query-sharing obligation. The former external correlation plan and separate
adapter contract/baseline helpers have been removed without compatibility aliases.
The public core, adapter, and scenario-host guides describe the current API.

Result-check implementation, 2026-10-24: `holds` declares a named predicate over
an applicative `Input`; `agreeOn` compares an explicitly labelled projection of
at least two references. Both are source-free expectations activated once after
all actions, including deferred declarations. Inspection retains their ordered
node dependencies, predicate identity, and windows without evaluating values.
They require no handler, source, capability, baseline, or correlation selection.
