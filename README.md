# 証拠 (Shōko)

Shōko is a Haskell DSL for specifying and verifying observable behavior across distributed systems. A scenario describes the evidence that establishes correct behavior; adapters determine how to obtain that evidence from a particular implementation and environment.

**Status:** experimental. `shoko-core` provides reusable typed workflow blocks, composed vocabularies/bindings, explicit correlation instances, and bounded Pass/Fail/Unknown evidence on GHC 9.12.4. `shoko-adapters` supplies SQL/HTTP transport and bounded Kiroku/Message DB readers with real local IO checks, plus a bounded Kafka topic scanner whose client binding awaits a pinned `hw-kafka-client` fork. `shoko-cli` supplies compiled registries, strict configuration, inspection, execution, and atomic reports. Real registration staging acceptance remains outstanding. See the [core](docs/core.md), [adapters](docs/adapters.md), and [scenario-host guide](docs/scenario-hosts.md).

Build and check the foundation from the repository root:

```bash
nix develop --command cabal update
nix develop --command just check
nix run . -- list
nix run . -- run demo-account-created --config config/demo.yaml --format json
```

Use `nix develop --command just fmt` to format Haskell, Cabal, and Nix sources. See [development](docs/development.md) and [dependency evidence](docs/dependencies.md). Foundation checks establish library/build usability; real staging workflow acceptance remains outstanding.

The [first staging workflow guide](docs/workflows/first-staging-workflow.md)
describes the contract schema, offline validation, and target/access inputs still
needed before live registration checks can run.

## Why the name?

**証拠（しょうこ, Shōko）** is Japanese for **evidence** or **proof**. The name expresses the project's central question:

> What evidence would demonstrate that this distributed system behaved correctly?

A successful HTTP response is only one part of a distributed operation. Its consequences may appear later in domain events, database state, read models, messages, or external interactions. Shōko aims to collect that evidence, preserve where it came from, and evaluate it against an explicit behavioral specification.

The repository uses the plain ASCII spelling `shoko`.

## What Shōko is for

A business operation can span several services, queues, workers, and databases. Each part may complete at a different time or fail independently. Tests that embed SQL queries, transport details, and fixed sleeps become difficult to maintain as those systems change.

Shōko separates the expected business behavior from the mechanisms used to verify it. A domain observation such as `accountExists` could be backed by a PostgreSQL query in one binding and a service's read endpoint in another. The scenario keeps the same meaning.

The first application is the [TAN platform](mori://tan/tan-platform) rewrite onto [Keiro](mori://shinzui/keiro) and [Kiroku](mori://shinzui/kiroku), with Kafka carrying integration events. Shōko has two roles:

- **Migration verification:** establish that a legacy workflow and its replacement satisfy the same observable expectations.
- **Feature verification:** keep those scenarios useful as the rewritten services and their bounded contexts evolve.

## A scenario in outline

The compiling [in-memory registration consumer](shoko-cli/test/ConsumerHost/Registration.hs)
exports a reusable workflow definition and thin scenario wrappers. Real staging
operations remain owned by their bounded context.

```haskell
registrationBlock :: ScenarioBuilder Registration (Ref Text, CorrelationRef)
registrationBlock = do
  qualified <- given "qualified" (accept ["ready"] Qualified)
  registered <- act "complete" (accept ["completed"] (Complete (fromRef qualified)))
  selected <- correlate (CorrelationAlias "registration")
    (BusinessKeyName "registrationId") (fromRef registered)
  expectAfterActions $ eventually "registered" $ correlatedBy selected $
    observeThat (Registered (fromRef registered)) (predicate "exists" id)
  pure (registered, selected)

composedRegistration :: Scenario (Registration :+: Accounts)
composedRegistration =
  scenario "composed-registration" "Register two entities and check an account" "v1" $ do
    _ <- namespace "inviter" (hoistScenarioBuilder InL registrationBlock)
    (invitee, _) <- namespace "invitee" (hoistScenarioBuilder InL registrationBlock)
    hoistScenarioBuilder InR (accountBlock invitee)
```

The two registrations use separate namespaced correlation handles with the same
semantic key; the account block selects its own `accountId`. All expectations run
after the last action. The same concrete block also backs `registration-alone`
and `registration-reused`, each with its own scenario identity and fresh resources.
Try `nix develop --command cabal run shoko-consumer-host -- run composed-registration --format json`.

Parity scenarios use domain observations such as `qualificationVerified`. Each implementation can satisfy them through its own events, state, and APIs. The bounded context owns this vocabulary in an application package beside the domain. Assertions about specific event names or internal causal chains belong in scenarios for that implementation.

Passing on both implementations establishes parity for the behavior covered by the scenario.

## How verification works

The core separates seven concepts:

| Concept | Responsibility |
| --- | --- |
| Scenario | Describe a behavior and its expected consequences. |
| Action | Perform an operation that may change the system. |
| Observation | Make a read-only request for evidence. |
| Expectation | Decide whether the evidence satisfies a requirement. |
| Evidence | Retain the observed value, source, timing, and correlation metadata. |
| Environment | Configure adapters, limits, and permitted capabilities. |
| Runner | Execute the scenario, collect evidence, enforce policy, and report results. |

Three independent choices determine how a scenario is used:

| Axis | Intended choices |
| --- | --- |
| Target environment | Existing Kubernetes staging system first; local fixtures for library development; production later |
| Implementation | Legacy or Keiro |
| Execution mode | Run, Observe, Replay |

CI means an automated caller of the verifier. The same staging command can run from an operator shell or automation with the approved access; the application remains deployed in its test namespace.

An environment paired with an implementation forms a **binding**, which selects the adapters. Production policy continues to apply whichever implementation is selected.

- **Run** performs actions and verifies their consequences.
- **Observe** attaches expectations to naturally occurring activity without initiating the business operation. During migration, this can support shadow verification.
- **Replay** evaluates recorded evidence or re-executes captured inputs against another environment. These are distinct strategies; input replay is particularly useful for turning legacy executions into regression cases for the rewrite.

Temporal assertions should express asynchronous behavior directly. The initial recommendation is to start with `eventually`, `never`, and `exactlyOnce`, with explicit deadlines and observation windows. A finite `never` assertion can establish absence only within its window and the coverage of its evidence sources. The bootstrap ADRs define finite budgets, polling, and composition rules; staging settings are chosen explicitly for the accepted workflow.

## Evidence and results

Evidence must be attributable to the execution being verified. The design provides two correlation strategies:

- **Business key:** use an identifier already shared by participants, such as `registrationId`. This is the baseline for legacy bindings.
- **Execution ID:** propagate a Shōko execution identity through events and commands where the system supports it. A runner cannot supply this guarantee without cooperation from the services.

The validation identified propagation work on the Keiro side as a prerequisite for execution-ID correlation. Until that is available, target bindings also need business-key correlation.

Results are intended to distinguish three outcomes:

| Result | Meaning |
| --- | --- |
| Pass | The evidence satisfies the expectations within their defined scope. |
| Fail | Verification establishes that an expectation was violated. |
| Unknown | Verification cannot establish the outcome, for example because an evidence source is unavailable. |

Reports should retain collected evidence even when verification fails: source identifiers, timestamps, correlation and causation details, and the expectation that could not be satisfied. This should help locate a broken projection, missing event, or failed interaction. Exit codes are 0 Pass, 1 Fail, 2 invalid invocation/configuration/policy, 3 Unknown, and 4 unexpected runner faults. CI preserves those outcomes.

## Initial scope and milestones

The first milestone is **verification of the complete system already running in a Kubernetes test namespace**. It includes a real successful workflow and a documented negative scenario, with attributable evidence of their downstream effects. Registration completion from an already-qualified agent is the selected MVP workflow; its accepted contract must match the actual deployment.

A negative scenario passes when the expected rejection or invariant holds: for example, a documented invalid-input rejection with unchanged domain state, or duplicate prevention under the service's contract. An unexpected success/rejection is Fail; a timeout or unavailable evidence is Unknown. Expected rejection must be typed evidence, not a rule that turns any error into success. Continuous absence and exactly-once claims require suitable durable coverage, rather than mutable-state snapshots alone.

The first usable MVP provides the small core, inspection, capability enforcement, bounded assertions, correlation, structured results, HTTP/PostgreSQL adapters, and any event reader required by the registration assertions. Both Message DB and Kiroku adapters remain full-bootstrap deliverables; an unused reader does not delay first use. A context-owned host supplies the actual staging scenarios and bindings. Haskell practices follow Jitsurei, Nix tooling comes from the Seihou template, and Settei owns configuration resolution at the CLI boundary.

Each accepted run maps business requirements to actual expectation evidence, identifies the deployed rewrite revision, and lists excluded coverage. Rewrite owners can rerun the same scenario contract after a deployment with fresh test identities and retain separate positive/negative reports. This supports registration regression reviews; it does not certify all registration flows or implement automated legacy/candidate comparison.

The staging contract records the approved cluster/namespace, observed deployment identities, access route, controlled test inputs, evidence credentials, permitted external effects, and run-owned cleanup or retention. Shōko connects to the existing system; it does not create, reset, or tear down the application namespace. Local fixtures validate Shōko's own implementation. CI may invoke the same staging command later and must not silently skip unavailable staging.

Legacy/Keiro comparison remains a later application of the same scenario/binding architecture. A second implementation is not required for first staging acceptance. Production execution, continuous observation, stronger causal verification, capture/replay, and generic transport/trace/metrics extensions remain later work.

## Production safety

Production verification is designed to default to observation. Active execution must be explicitly permitted by the environment's policy, and the runner must reject an operation when it cannot establish permission.

The validation recommends a capability set: a scenario's required capabilities must be a subset of those permitted by the environment. Planned safeguards include inspection before execution, dry runs, rate limits, explicit opt-in for synthetic operations, controlled external effects, and managed cleanup. These are requirements for future implementation, not safety guarantees already provided by this repository.

Shōko's scope is application behavior across services. Existing unit tests, property tests, contract tests, load tests, and observability systems remain complementary; Shōko consumes their useful evidence and integrations without owning normal production workflows.

## Design documents

- [Capability catalog](docs/capabilities/index.md) — implemented consumer capabilities, evidence, and limits.
- [Terminology](docs/terminology/index.md) — the current vocabulary for scenarios, evidence, execution, and hosts.
- [Improvement requests](docs/improvement-requests/index.md) — cross-repository requests raised against Shoko, with stable IR handles.
- [Bootstrap MasterPlan](docs/masterplans/1-bootstrap-shoko-for-evidence-based-workflow-parity.md) — the current staging-first scope and seven implementation plans.
- [Implementation explainer](docs/artifacts/shoko-bootstrap-explainer.html) — a light-themed visual guide with interactive evidence examples.
- [Initial specification](docs/intial-spec.md) — the full design, examples, open questions, and revised migration milestones.
- [Initial specification requirement validation](docs/research/initial-specification-requirement-validation.md) — consistency findings, service and library surveys, prerequisites, and recommendations before implementation planning.
- [Research index](docs/research/index.md) — the repository's research records.

The specification describes the broader direction and the validation records the surveyed evidence. The MasterPlan and bootstrap ADRs resolve implementation decisions and carry the user’s later staging-first scope correction.

Revision 2026-10-19: add reusable, namespaced workflow composition and explicit
correlation selection to the public API outline.
