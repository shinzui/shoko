# 証拠 (Shōko)

Shōko is a Haskell DSL for specifying and verifying observable behavior across distributed systems. A scenario describes the evidence that establishes correct behavior; adapters determine how to obtain that evidence from a particular implementation and environment.

**Status:** experimental, at the specification and requirement-validation stage. This repository currently contains design documents and research. The DSL, runner, adapters, and CLI described here are planned; there is no runnable Shōko package yet.

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

The following illustrates the proposed DSL and domain vocabulary. It is a design sketch, not a compilable example or a settled API.

```haskell
registrationParity :: Scenario
registrationParity =
  scenario "registration-parity" $ do
    agent <- given syntheticAgent

    when $
      register agent

    expect $ do
      eventually $
        registrationApproved agent

      eventually $
        accountExists agent

      eventually $
        userExists agent

      eventually $
        qualificationVerified agent
```

The real registration workflow includes approval and one-time-password steps. An executable scenario must arrange those steps and valid test identities; the outline omits that setup. The [requirement validation](docs/research/initial-specification-requirement-validation.md) explains the actual flow and the gaps in the specification's earlier examples.

Parity scenarios use domain observations such as `qualificationVerified`. Each implementation can satisfy them through its own events, state, and APIs. The bounded context owns this vocabulary in an application package beside the domain. Assertions about specific event names or internal causal chains belong in scenarios for that implementation.

Passing on both implementations establishes parity for the behavior covered by the scenario.

## How verification works

The proposed core separates seven concepts:

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
| Environment | Local development, CI, staging, production |
| Implementation | Legacy or Keiro |
| Execution mode | Run, Observe, Replay |

An environment paired with an implementation forms a **binding**, which selects the adapters. Production policy continues to apply whichever implementation is selected.

- **Run** performs actions and verifies their consequences.
- **Observe** attaches expectations to naturally occurring activity without initiating the business operation. During migration, this can support shadow verification.
- **Replay** evaluates recorded evidence or re-executes captured inputs against another environment. These are distinct strategies; input replay is particularly useful for turning legacy executions into regression cases for the rewrite.

Temporal assertions should express asynchronous behavior directly. The initial recommendation is to start with `eventually`, `never`, and `exactlyOnce`, with explicit deadlines and observation windows. A finite `never` assertion can establish absence only within its window and the coverage of its evidence sources. Exact timeout, polling, and composition rules remain design work.

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

Reports should retain collected evidence even when verification fails: source identifiers, timestamps, correlation and causation details, and the expectation that could not be satisfied. This should help locate a broken projection, missing event, or failed interaction. The mapping of `Unknown` into CI outcomes remains to be decided.

## Initial scope and milestones

The first milestone is **one domain-level scenario passing against both a legacy local stack and a Keiro local stack**. Registration is the motivating example; the actual first workflow should be whichever exists on both sides first. This revised milestone takes precedence over the specification's earlier local-versus-staging milestone.

The initial implementation should provide the small core above, bounded assertions, correlation, structured results, and HTTP, PostgreSQL, and Message DB adapters. Kiroku is the primary target evidence source for the rewrite. Kafka observations follow the integration transport used by both sides.

Legacy support stays thin and primarily read-only. Generic PostgreSQL observations—row existence, count, column value, and absence—provide the baseline for services whose database is their only evidence source. Existing event stores and REST endpoints can supply additional evidence where available. Legacy bindings can be removed after cutover.

The first parity run needs composed local environments for both implementations, a shared domain vocabulary, and a usable correlation strategy. The validation also identified staging prerequisites, including a controlled OTP path and machine-callable REST or PostgreSQL reads. Several early examples assume events, GraphQL access, or email effects that the surveyed workflow does not provide.

Later milestones add inspection and production safety, observation of live workflows, stronger causal verification, and capture/replay. Input replay moves earlier when it helps verify the migration. Remote trace and metrics adapters, property-based generation, complex temporal logic, and visualization remain outside the first implementation.

## Production safety

Production verification is designed to default to observation. Active execution must be explicitly permitted by the environment's policy, and the runner must reject an operation when it cannot establish permission.

The validation recommends a capability set: a scenario's required capabilities must be a subset of those permitted by the environment. Planned safeguards include inspection before execution, dry runs, rate limits, explicit opt-in for synthetic operations, controlled external effects, and managed cleanup. These are requirements for future implementation, not safety guarantees already provided by this repository.

Shōko's scope is application behavior across services. Existing unit tests, property tests, contract tests, load tests, and observability systems remain complementary; Shōko consumes their useful evidence and integrations without owning normal production workflows.

## Design documents

- [Initial specification](docs/intial-spec.md) — the full design, examples, open questions, and revised migration milestones.
- [Initial specification requirement validation](docs/research/initial-specification-requirement-validation.md) — consistency findings, service and library surveys, prerequisites, and recommendations before implementation planning.
- [Research index](docs/research/index.md) — the repository's research records.

The specification describes the intended direction. The validation records where examples differ from the surveyed systems and which decisions remain open, including the canonical DSL, capability enforcement, temporal budgets, and CI result handling.
