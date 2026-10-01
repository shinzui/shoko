# 証拠 (Shōko)

> **証拠（しょうこ） — evidence, proof**

Shōko is a Haskell DSL for specifying and verifying observable behavior across distributed systems.

Rather than treating testing as a sequence of implementation-specific operations, Shōko describes the **evidence that must exist for a system behavior to be considered correct**.

The same scenario should be usable across local development, CI, staging, and production by changing how actions and observations are interpreted.

Shōko is designed particularly for microservice and event-driven architectures where a single operation may produce side effects across multiple services, databases, event streams, queues, workers, external APIs, and asynchronous projections.

---

## Motivation

Testing an individual service is relatively straightforward.

Testing a distributed workflow is harder.

An operation such as:

```text
Register Agent
```

might cause:

```text
RegistrationSubmitted
        │
        ├── AccountCreated
        │
        ├── UserCreated
        │
        ├── QualificationRequested
        │       │
        │       └── AgentQualified
        │
        ├── WelcomeEmailRequested
        │
        └── ReadModelsUpdated
```

These effects may:

- occur asynchronously;
- span multiple services;
- use different persistence technologies;
- become visible at different times;
- fail independently;
- only be observable through telemetry;
- behave differently between local, staging, and production environments.

Traditional E2E tests often encode infrastructure details directly:

```text
POST /registration
SELECT FROM account_service_read
SELECT FROM user_service_read
QUERY message-db
CHECK pubsub
WAIT 5 seconds
CHECK email
```

This creates tests that are:

- tightly coupled to infrastructure;
- difficult to reuse across environments;
- brittle under architectural changes;
- unsafe to execute in production;
- poor representations of the actual business behavior being tested.

Shōko separates **what behavior should occur** from **how evidence of that behavior is obtained**.

---

## Core Idea

A Shōko scenario describes:

```text
Given
  some initial context

When
  an action occurs

Then
  evidence of the expected consequences should exist
```

For example:

```haskell
scenario "agent registration" $ do
  agent <- given uniqueAgent

  register agent

  eventually $ do
    accountExists agent
    userExists agent
    registrationCompleted agent
    welcomeEmailRequested agent
```

The scenario does not specify:

```text
query PostgreSQL
query MessageDB
search OpenTelemetry
call GraphQL
inspect Pub/Sub
```

Those decisions belong to environment-specific adapters.

---

## Design Principles

### Behavior Over Infrastructure

Scenarios describe domain behavior rather than implementation details.

Prefer:

```haskell
accountExists agent
```

over:

```haskell
query
  "SELECT * FROM account_service_read.accounts WHERE email = ?"
```

The infrastructure-specific implementation belongs in an adapter.

### Evidence Is the Fundamental Abstraction

A distributed operation is considered successful when sufficient evidence exists that its expected consequences occurred.

Conceptually:

```text
Action
  ↓
Distributed Side Effects
  ↓
Evidence
  ↓
Verification
```

Evidence may come from:

- domain events;
- service APIs;
- database state;
- read models;
- distributed traces;
- metrics;
- logs;
- queues;
- object storage;
- external systems.

The source of evidence should not be part of the scenario specification unless the scenario explicitly intends to verify that particular infrastructure.

---

## Actions and Observations

Shōko distinguishes between operations that modify the world and operations that observe it.

```haskell
data Action a

data Observation a
```

An `Action` may produce side effects.

An `Observation` must be read-only.

Example actions:

```haskell
registerAgent
createAccount
submitReferral
sendInvitation
```

Example observations:

```haskell
accountExists
agentIsQualified
emailWasRequested
eventOccurred
```

This distinction is especially important for production safety.

---

## Scenarios

A scenario is a portable specification of expected system behavior.

```haskell
scenario "qualified agent registration" $ do
  agent <- given uniqueAgent

  register agent

  eventually $ do
    accountExists agent
    userExists agent

  eventually $
    agentStatus agent `shouldBe` Qualified

  occurred @WelcomeEmailRequested agent
```

The scenario should contain as little knowledge about infrastructure as possible.

---

## Environment Interpreters

The same scenario may run against different environments.

```haskell
data Environment
  = Local
  | CI
  | Staging
  | Production
```

Each environment provides interpreters for actions and observations.

For example:

```text
accountExists

Local
  → PostgreSQL

CI
  → PostgreSQL

Staging
  → GraphQL API

Production
  → read-only production projection
```

Similarly:

```text
eventOccurred

Local
  → MessageDB

Staging
  → MessageDB

Production
  → read-only event-store replica
```

The scenario itself remains unchanged.

---

## Adapters

Adapters connect Shōko's semantic observations to actual infrastructure.

Initial adapters may include:

```text
shoko-http
shoko-graphql
shoko-postgres
shoko-messagedb
shoko-pubsub
shoko-opentelemetry
shoko-prometheus
shoko-email
shoko-object-storage
```

Adapters should expose capabilities that application-specific packages can translate into domain observations.

For example:

```haskell
data Observation a where
  AccountExists
    :: AgentRef
    -> Observation Account

  EventOccurred
    :: EventType a
    -> CorrelationId
    -> Observation a
```

An interpreter determines how that observation is satisfied.

---

## Types of Evidence

Shōko should support several categories of evidence.

### State

Verify current system state.

```haskell
eventually $
  agentStatus agent `shouldBe` Qualified
```

Examples include:

- account exists;
- membership is active;
- listing appears in a read model;
- agent belongs to a chapter.

### Events

Verify that domain events occurred.

```haskell
occurred @AgentQualified agent
```

Events are particularly valuable in event-sourced systems because they represent domain facts rather than implementation state.

### Interactions

Verify that an interaction occurred.

```haskell
called QualificationService

published QualificationRequested

requested WelcomeEmail
```

These observations may be backed by telemetry, message infrastructure, or recorded interactions.

### Causality

Verify relationships between events.

```haskell
expectFlow $
  RegistrationSubmitted
    --> AccountCreated
    --> UserCreated
    --> QualificationRequested
    --> AgentQualified
```

This allows Shōko to describe distributed workflows rather than isolated assertions.

---

## Temporal Assertions

Distributed systems are eventually consistent.

Timing semantics should therefore be first-class rather than implemented through arbitrary sleeps.

Shōko should eventually support operators such as:

```text
eventually P
always P
never P
P until Q
P within T
P causes Q
P exactlyOnce
```

Example:

```haskell
eventually (within $ seconds 30) $
  agentStatus agent `shouldBe` Qualified
```

Negative invariants should also be expressible:

```haskell
never $
  duplicateAccountExists agent
```

And invariants may need to hold for a period:

```haskell
consistentlyFor (seconds 10) $
  accountCount agent `shouldBe` 1
```

---

## Correlation

Reliable distributed verification requires correlation.

Every Shōko execution should have an identity such as:

```text
scenario_id
execution_id
correlation_id
```

When Shōko initiates an operation, the execution identity should propagate through the distributed system where possible.

For HTTP this might be:

```text
x-shoko-execution-id
```

The identifier may then propagate into:

- domain event metadata;
- OpenTelemetry spans;
- logs;
- Pub/Sub attributes;
- worker metadata;
- database audit records.

This allows Shōko to ask:

```text
Show me the evidence associated with execution X.
```

rather than trying to infer which activity belongs to the test.

Existing application correlation and causation IDs should be reused whenever possible.

---

## Execution Modes

A scenario should support multiple execution strategies.

```text
Scenario
   │
   ├── Run
   ├── Observe
   └── Replay
```

### Run

Shōko performs the scenario's actions and verifies their consequences.

```bash
shoko run registration --env staging
```

Typical environments include:

```text
local
CI
staging
```

Production execution may also be allowed when all required actions satisfy the environment's safety policy.

### Observe

Shōko does not initiate the operation.

Instead, it observes naturally occurring activity and verifies that the expected behavior follows.

```haskell
scenario "registration" $ do
  registration <- observe @RegistrationSubmitted

  eventually $ do
    accountCreated registration
    userCreated registration
    qualificationStarted registration
```

This enables production verification without generating synthetic traffic.

Conceptually:

```text
Production Traffic
       │
       ▼
RegistrationSubmitted
       │
       ▼
Shōko attaches
       │
       ▼
Observe consequences
       │
       ▼
Verify invariants
```

This turns scenarios into executable production invariants.

### Replay

Shōko can verify behavior from previously captured evidence.

For example:

```bash
shoko capture production --execution abc123

shoko replay abc123 --against local
```

A captured execution might contain normalized representations of:

```text
inputs
events
interactions
observations
timings
correlation
causation
trace information
```

Replay allows real system behavior to become reproducible test cases.

---

## Production Safety

Safe production verification is a fundamental design requirement.

Actions should declare their safety characteristics.

For example:

```haskell
data Safety
  = ReadOnly
  | Synthetic
  | Reversible
  | Destructive
```

An action may carry its safety level at the type level:

```haskell
createSyntheticAgent
  :: Action 'Synthetic AgentRef

readAgent
  :: AgentRef
  -> Action 'ReadOnly Agent

deleteAccount
  :: AgentRef
  -> Action 'Destructive ()
```

An environment declares which capabilities it permits.

Example:

```text
Local
  ✓ ReadOnly
  ✓ Synthetic
  ✓ Reversible
  ✓ Destructive

Staging
  ✓ ReadOnly
  ✓ Synthetic
  ✓ Reversible
  ✓ Destructive

Production
  ✓ ReadOnly
  ✓ Synthetic
  ✗ Reversible
  ✗ Destructive
```

The production interpreter must reject scenarios requiring unavailable capabilities.

Production safety should therefore be enforced by the runner and, where practical, by the Haskell type system rather than convention.

---

## Synthetic Resources

Production-safe scenarios may create synthetic resources.

Synthetic resources should be:

- clearly identified;
- namespaced;
- correlated with a Shōko execution;
- rate-limited;
- automatically cleaned up where possible;
- excluded from analytics where appropriate;
- prevented from contacting real customers;
- prevented from triggering financial transactions;
- prevented from affecting business reporting.

Example:

```haskell
productionSafe $
  withSyntheticAgent $ \agent -> do
    register agent

    eventually $
      agentExists agent
```

Adapters should understand synthetic identities where relevant.

---

## Multiple Sources of Evidence

A major benefit of Shōko should be the ability to verify the same behavior through different sources.

For example:

```text
Domain Event
     │
     ├── MessageDB says AgentQualified occurred
     ├── OpenTelemetry says qualification worker ran
     └── Read Model says agent.status = Qualified
```

These observations verify different layers of the system.

This makes it possible to identify failures such as:

```text
event correct
projection incorrect
```

or:

```text
event emitted
worker never processed it
```

or:

```text
worker processed event
external side effect failed
```

Shōko should therefore avoid treating any single observation technology as the canonical representation of reality.

---

## Event-Sourced Systems

Event-sourced architectures are particularly well suited to Shōko.

Domain events provide semantic evidence of what occurred.

Given:

```text
RegistrationSubmitted
        ↓
AccountCreated
        ↓
QualificationRequested
        ↓
AgentQualified
```

Shōko can verify:

- event existence;
- event ordering;
- correlation;
- causation;
- cardinality;
- timing;
- resulting projections.

Example:

```haskell
expectFlow $ do
  RegistrationSubmitted
    `causes` AccountCreated

  AccountCreated
    `causes` QualificationRequested

  QualificationRequested
    `eventuallyCauses` AgentQualified
```

The event store can therefore act as one of Shōko's strongest sources of evidence.

---

## OpenTelemetry

OpenTelemetry provides a complementary structural view of distributed behavior.

Domain events answer:

> What happened in the domain?

Telemetry answers:

> How did the distributed system execute it?

For example:

```text
RegistrationSubmitted
        │
        ▼
registration-service
        │
        ▼
account-service
        │
        ▼
qualification-worker
        │
        ▼
MLS API
```

Shōko should allow assertions against traces when implementation-level behavior matters.

For example:

```haskell
eventually $
  spanOccurred "qualification-worker"

never $
  spanFailed "qualification-worker"
```

Domain events and OpenTelemetry should complement rather than replace each other.

---

## Scenario Results

Verification results should contain structured evidence rather than only pass/fail.

Example:

```text
Scenario: qualified agent registration
Execution: shoko_01J...

✓ RegistrationSubmitted
  MessageDB
  12ms

✓ AccountCreated
  MessageDB
  43ms

✓ Account visible
  account-service
  61ms

✓ QualificationRequested
  MessageDB
  84ms

✓ qualification-worker executed
  OpenTelemetry
  102ms

✓ AgentQualified
  MessageDB
  821ms

✓ Agent projection updated
  GraphQL
  940ms

Scenario passed in 940ms
```

Failures should preserve the evidence that was found.

For example:

```text
✗ AgentQualified

Expected within:
  30 seconds

Observed:

  ✓ QualificationRequested
  ✓ qualification-worker started
  ✗ MLS request returned 500
  ✗ AgentQualified not observed

Relevant correlation:
  shoko_01J...
```

A Shōko failure should help diagnose the distributed workflow rather than merely report a failed assertion.

---

## Architecture

```text
                         Scenario
                            │
                 ┌──────────┴──────────┐
                 │                     │
              Actions              Evidence
                 │                     │
          Capability DSL         Observation DSL
                 │                     │
                 └──────────┬──────────┘
                            │
                          Runner
                            │
            ┌───────────────┼───────────────┐
            │               │               │
          Local           Staging       Production
            │               │               │
       ┌────┴────┐     ┌────┴────┐     ┌────┴────┐
       │Adapters │     │Adapters │     │Safe     │
       │         │     │         │     │Adapters │
       └────┬────┘     └────┬────┘     └────┬────┘
            │               │               │
       PostgreSQL         GraphQL           OTel
       MessageDB          MessageDB       Metrics
       HTTP               Pub/Sub        Events
       Fake Email         OTel           Read Models
```

Orthogonal to the environment is the execution mode:

```text
                         Scenario
                            │
              ┌─────────────┼─────────────┐
              │             │             │
             Run          Observe       Replay
              │             │             │
         initiated       natural       recorded
         behavior        traffic       history
```

---

## Relationship to Existing Tools

Shōko is not intended to replace existing testing and observability tools.

### Hurl

Hurl remains useful for API-level integration and E2E tests.

Shōko operates at a higher semantic level and can use HTTP/Hurl-like interactions underneath its action adapters.

### Property-Based Testing

Hedgehog and QuickCheck verify properties over generated inputs.

Shōko may eventually use property-based generators for scenarios:

```haskell
forAll validAgent $ \agent ->
  scenario $ do
    register agent

    eventually $
      accountExists agent
```

Property generation and distributed verification are complementary.

### Pact

Pact verifies contracts between service consumers and providers.

Shōko verifies the consequences of distributed business operations.

Pact asks:

```text
Can service A correctly communicate with service B?
```

Shōko asks:

```text
Did business operation X produce all of the observable
consequences that constitute correct behavior?
```

### Tracetest

Tracetest verifies behavior through distributed traces.

Shōko generalizes the concept of evidence.

A trace is one possible source of evidence alongside:

```text
domain events
state
read models
metrics
logs
messages
external systems
```

### Synthetic Monitoring

Synthetic monitoring periodically performs known operations against production.

Shōko should support synthetic execution but also support:

```text
Run
Observe
Replay
```

allowing verification without necessarily generating production traffic.

---

## Initial DSL

The initial DSL should remain intentionally small.

Core constructs:

```haskell
scenario
given
when
expect

eventually
never
consistently

occurred
state
```

Example:

```haskell
scenario "agent registration" $ do
  agent <- given uniqueAgent

  when $
    register agent

  expect $ do
    occurred @RegistrationSubmitted agent

    eventually $
      accountExists agent

    eventually $
      userExists agent

    eventually $
      agentStatus agent `shouldBe` Qualified

    never $
      duplicateAccountExists agent
```

More sophisticated temporal and causal operators should only be introduced once concrete scenarios demonstrate their necessity.

---

## Initial Scope

The first implementation should prove that one meaningful scenario can execute unchanged against multiple environments.

A good initial target is a distributed registration or qualification workflow.

The first version should support:

1. scenario definition;
2. actions;
3. observations;
4. environment-specific interpreters;
5. correlation IDs;
6. MessageDB observations;
7. PostgreSQL observations;
8. HTTP actions;
9. eventual assertions;
10. structured verification results.

The first milestone should demonstrate:

```text
                       same scenario
                            │
                  ┌─────────┼─────────┐

                                         same scenario
                            │
                  ┌─────────┼─────────┐
                  │         │         │
                  ▼         ▼         ▼
                Local    Staging   Production
                  │         │         │
                  ▼         ▼         ▼
                Pass      Pass      Pass
```

Production should initially be restricted to read-only observation or explicitly synthetic operations.

---

## Suggested Package Structure

The project can begin as a monorepo containing a small core and separate adapters.

```text
shoko/
├── shoko-core/
├── shoko-runner/
├── shoko-http/
├── shoko-postgres/
├── shoko-messagedb/
├── shoko-opentelemetry/
└── shoko-cli/
```

### `shoko-core`

Contains the semantic DSL.

Responsibilities include:

- scenarios;
- actions;
- observations;
- expectations;
- temporal assertions;
- execution identity;
- correlation;
- safety capabilities;
- evidence representation.

It should have minimal infrastructure dependencies.

### `shoko-runner`

Interprets scenarios.

Responsibilities include:

- scenario execution;
- environment configuration;
- adapter selection;
- retries;
- timeouts;
- evidence collection;
- safety enforcement;
- structured results.

### `shoko-http`

Provides HTTP actions and observations.

For example:

```haskell
request
  :: Request
  -> Action safety Response
```

It may also be responsible for propagating Shōko execution metadata through HTTP headers.

### `shoko-postgres`

Provides PostgreSQL-backed observations.

This adapter should primarily provide low-level capabilities.

Application code can define semantic observations on top of them.

For example:

```haskell
accountExists agent =
  postgresObservation $ ...
```

The scenario itself should never need to know that the observation is implemented using PostgreSQL.

### `shoko-messagedb`

Provides event-store observations.

This is likely to be one of the most important initial adapters for event-sourced systems.

Capabilities should include:

```text
event occurred
event occurred exactly once
event ordering
event causation
event correlation
stream state
category observations
```

### `shoko-opentelemetry`

Provides trace-based evidence.

Capabilities may include:

```text
span occurred
span failed
span attributes
trace relationships
service participation
latency
```

### `shoko-cli`

Provides a command-line interface.

Potential commands:

```bash
shoko run registration --env staging

shoko observe registration --env production

shoko replay execution.json

shoko inspect execution-id

shoko list scenarios
```

---

## Evidence Model

Internally, Shōko should normalize observations into an evidence model.

For example:

```haskell
data Evidence a = Evidence
  { source      :: EvidenceSource
  , observedAt  :: UTCTime
  , executionId :: ExecutionId
  , value       :: a
  , metadata    :: EvidenceMetadata
  }
```

Possible evidence sources:

```haskell
data EvidenceSource
  = DomainEvent
  | Database
  | Http
  | Trace
  | Metric
  | Log
  | Message
  | ExternalSystem
```

The evidence model should preserve enough source information for debugging while keeping scenarios independent of the source.

This creates an important distinction:

```text
Observation
    │
    │ asks a question
    ▼
Adapter
    │
    │ discovers something
    ▼
Evidence
    │
    │ evaluated against
    ▼
Expectation
```

An observation is therefore not itself an assertion.

It is a request for evidence.

An expectation determines whether the evidence satisfies the scenario.

---

## Evidence Provenance

Evidence should retain provenance.

For example:

```text
AgentQualified

Source:
  MessageDB

Stream:
  agent-01H...

Global Position:
  18299182

Correlation:
  shoko_01J...

Causation:
  qualification-requested-01J...

Observed:
  2026-09-29T18:42:01Z
```

This is valuable both for debugging and for determining how trustworthy an observation is.

A future version of Shōko could potentially require corroborating evidence from multiple sources:

```haskell
corroborate $ do
  occurred @AgentQualified agent
  agentStatus agent `shouldBe` Qualified
```

This could verify that both the domain history and externally visible state agree.

---

## Scenario Identity

Scenarios should have stable identities independent of individual executions.

For example:

```haskell
scenario
  "agent-registration"
  "Agent registration"
  $ do
    ...
```

Each invocation creates an execution:

```text
Scenario ID:
  agent-registration

Execution ID:
  shoko_01J...

Environment:
  production

Mode:
  observe
```

Stable scenario identities make it possible to compare results over time.

For example:

```text
agent-registration

Last 100 executions:

98 passed
2 failed

p50 completion: 430ms
p95 completion: 1.8s
p99 completion: 4.2s
```

Shōko can therefore eventually provide useful production reliability information without becoming a general-purpose observability platform.

---

## Failure Semantics

Failures should distinguish between different classes of problems.

For example:

```haskell
data VerificationFailure
  = ExpectationFailed
  | ObservationUnavailable
  | ObservationTimedOut
  | ActionFailed
  | AdapterFailed
  | UnsafeActionRejected
  | CorrelationLost
```

These differences matter.

For example:

```text
AgentQualified was not observed
```

is fundamentally different from:

```text
Shōko could not connect to MessageDB
```

The former suggests a system behavior failure.

The latter means Shōko could not establish whether the behavior occurred.

The framework should avoid reporting both simply as:

```text
FAILED
```

---

## Unknown Results

Distributed verification benefits from a three-state model:

```text
Pass
Fail
Unknown
```

rather than only:

```text
Pass
Fail
```

For example:

```text
Expected:

  AgentQualified

Evidence source:

  MessageDB

Result:

  MessageDB unavailable
```

Shōko does not know that the system failed.

It knows that verification could not be completed.

The result should therefore be:

```text
UNKNOWN
```

rather than:

```text
FAIL
```

This distinction becomes particularly important for production verification.

---

## Production Verification Philosophy

Production should not merely be another environment.

It has fundamentally different constraints.

Shōko should assume:

- production contains real users;
- actions may have irreversible consequences;
- external integrations may charge money;
- notifications may reach real people;
- analytics may be polluted;
- synthetic data may trigger business processes;
- verification itself can create load;
- observation infrastructure can fail independently.

Production verification should therefore default to:

```text
observe, don't mutate
```

When mutation is necessary:

```text
synthetic before real
```

When synthetic mutation is used:

```text
constrain the blast radius
```

The production interpreter should always fail closed.

If Shōko cannot establish that an operation is permitted, it should not perform the operation.

---

## Safety as Capabilities

Rather than relying only on a linear safety classification, the framework may eventually model safety through capabilities.

For example:

```haskell
data Capability
  = ReadProduction
  | CreateSyntheticData
  | SendExternalRequest
  | SendEmail
  | ModifyRealData
  | DeleteData
  | FinancialSideEffect
```

A scenario declares what it requires.

An environment declares what it permits.

Execution is possible only when:

```text
required capabilities
        ⊆
permitted capabilities
```

For example:

```text
Scenario:

  ReadProduction
  CreateSyntheticData

Production Environment:

  ReadProduction
  CreateSyntheticData
  SendExternalRequest

Result:

  allowed
```

Whereas:

```text
Scenario:

  ReadProduction
  SendEmail

Production Environment:

  ReadProduction
  CreateSyntheticData

Result:

  rejected
```

This may ultimately provide a more expressive safety system than a single `Safety` enum.

---

## Dry Run

Production execution should support a dry-run mode.

For example:

```bash
shoko run registration \
  --env production \
  --dry-run
```

Output:

```text
Scenario:
  agent-registration

Required capabilities:

  ✓ ReadProduction
  ✓ CreateSyntheticData
  ✓ SendExternalRequest

Actions:

  1. Create synthetic agent
  2. POST /registration
  3. Observe RegistrationSubmitted
  4. Observe AccountCreated
  5. Observe AgentQualified

External effects:

  MLS API request

Suppressed effects:

  Welcome email

Production policy:

  ALLOWED
```

Dry runs make the safety model inspectable rather than implicit.

---

## Cleanup

Synthetic scenarios frequently require cleanup.

Cleanup should be part of the execution model rather than an ad-hoc final action.

For example:

```haskell
withSyntheticAgent $ \agent -> do
  register agent

  eventually $
    agentStatus agent `shouldBe` Qualified
```

The runner knows that `agent` is a managed synthetic resource.

It can therefore perform cleanup regardless of whether the scenario succeeds.

Conceptually:

```text
Acquire
   │
   ▼
Execute
   │
   ▼
Verify
   │
   ▼
Release
```

This resembles resource management through `bracket`.

Cleanup failure should also be reported independently from scenario verification failure.

---

## Concurrency

Distributed scenarios may contain independent expectations.

For example:

```haskell
expectConcurrently $ do
  accountExists agent
  userExists agent
  welcomeEmailRequested agent
```

There should be no requirement that these observations occur sequentially.

The execution engine should eventually be capable of constructing an expectation graph and evaluating independent observations concurrently.

For example:

```text
             RegistrationSubmitted
                      │
          ┌───────────┼───────────┐
          │           │           │
          ▼           ▼           ▼
    AccountCreated UserCreated EmailRequested
          │
          ▼
 QualificationRequested
          │
          ▼
    AgentQualified
```

This graph representation may eventually become useful for both execution and visualization.

---

## Scenario Graph

Although scenarios are written using `do` notation, internally Shōko may benefit from representing them as a graph rather than immediately interpreting them.

For example:

```text
Scenario
   │
   ▼
Scenario AST
   │
   ▼
Dependency Graph
   │
   ├── safety analysis
   ├── dry run
   ├── visualization
   ├── execution
   └── replay
```

This argues for a free or freer representation of the scenario language rather than directly embedding everything in `IO`.

The DSL should preserve enough structure to inspect a scenario before executing it.

That becomes particularly important for production safety.

---

## DSL Representation

An initial implementation might use a GADT describing scenario operations.

Conceptually:

```haskell
data ScenarioF next where
  Perform
    :: Action safety a
    -> (a -> next)
    -> ScenarioF next

  Observe
    :: Observation a
    -> (a -> next)
    -> ScenarioF next

  Expect
    :: Expectation
    -> next
    -> ScenarioF next
```

The exact representation should remain an implementation detail.

The important property is that scenarios remain inspectable.

Shōko should be able to answer:

```text
What actions will this scenario perform?

What capabilities does it require?

What external systems can it touch?

What observations will it make?

Can this scenario safely execute in production?
```

before executing anything.

---

## Configuration

Environment configuration should remain separate from scenario definitions.

For example:

```yaml
environment: production

adapters:
  events:
    type: message-db
    connection: production-read-replica

  accounts:
    type: graphql
    endpoint: account-service

  traces:
    type: opentelemetry

policy:
  capabilities:
    - ReadProduction
    - CreateSyntheticData

  max-concurrency: 2

  synthetic-prefix: "shoko-"
```

Secrets should come from the environment or an external secret provider rather than scenario configuration.

---

## CLI

Potential CLI design:

```text
shoko run <scenario>

shoko observe <scenario>

shoko replay <execution>

shoko inspect <execution>

shoko explain <scenario>

shoko list
```

Examples:

```bash
shoko run agent-registration --env local

shoko run agent-registration --env staging

shoko run agent-registration --env production --dry-run

shoko observe agent-registration --env production

shoko inspect shoko_01J...

shoko explain agent-registration
```

`explain` should show the scenario without executing it:

```text
Scenario:
  agent-registration

Actions:
  CreateSyntheticAgent
  RegisterAgent

Expectations:
  RegistrationSubmitted
  AccountCreated
  UserCreated
  AgentQualified

Required capabilities:
  CreateSyntheticData
  SendExternalRequest

Production:
  Allowed

Estimated timeout:
  30 seconds
```

---

## What Shōko Is Not

Shōko should deliberately avoid becoming several adjacent tools.

It is not a unit testing framework.

Use:

```text
tasty
HUnit
Hedgehog
QuickCheck
```

for unit and property testing.

It is not primarily a contract testing framework.

Use Pact or schema-level compatibility testing for service contracts.

It is not a load-testing framework.

Use k6 or dedicated load-testing infrastructure.

It is not an observability platform.

Use OpenTelemetry, Prometheus, Grafana, and logging infrastructure.

It is not a workflow engine.

It observes and verifies workflows; it does not own their execution.

Shōko sits above these systems and asks:

> What evidence demonstrates that this distributed behavior is correct?

---

## Development Strategy

Shōko should be built from concrete distributed-system problems rather than designing the entire DSL up front.

The first implementation should choose one real workflow.

For example:

```text
Agent Registration
```

Implement only enough DSL to express that workflow cleanly.

Then add another substantially different workflow.

For example:

```text
MLS Qualification
```

Then another:

```text
Referral Creation
```

Every new abstraction should be justified by multiple concrete scenarios.

This should help prevent the DSL from becoming an overly general effect system before its semantics are understood.

---

## Phase 1 — Basic Distributed Verification

Goal:

> Verify one distributed workflow locally and in staging using the same scenario.

Implement:

- scenario DSL;
- HTTP actions;
- MessageDB observations;
- PostgreSQL observations;
- correlation IDs;
- `eventually`;
- structured results.

Example:

```haskell
scenario "agent registration" $ do
  agent <- given uniqueAgent

  register agent

  expect $
    occurred @RegistrationSubmitted agent

  eventually $
    accountExists agent

  eventually $
    agentStatus agent `shouldBe` Qualified
```

---

## Phase 2 — Production Safety

Goal:

> Safely execute or observe scenarios in production.

Implement:

- capability model;
- environment policies;
- dry-run;
- synthetic resources;
- cleanup;
- production read-only adapters;
- fail-closed execution.

Production execution should initially require explicit opt-in.

---

## Phase 3 — Production Observation

Goal:

> Verify naturally occurring production behavior without initiating it.

Implement:

```haskell
observe @RegistrationSubmitted
```

along with:

- correlation discovery;
- event subscriptions;
- observation windows;
- sampling;
- rate limits;
- continuous verification.

At this stage, Shōko begins functioning as an executable specification of production invariants.

---

## Phase 4 — Causal Verification

Goal:

> Verify distributed workflows rather than isolated outcomes.

Implement:

```text
P causes Q

P eventuallyCauses Q

P causesExactlyOnce Q
```

and workflow expressions such as:

```haskell
expectFlow $
  RegistrationSubmitted
    --> AccountCreated
    --> QualificationRequested
    --> AgentQualified
```

Use event correlation and causation metadata wherever available.

---

## Phase 5 — Capture and Replay

Goal:

> Turn real distributed executions into reproducible verification cases.

Implement:

```bash
shoko capture production --execution <id>

shoko replay <capture> --against local
```

Captured executions should use a normalized evidence format rather than storing infrastructure-specific responses wherever possible.

This enables production failures to become regression scenarios.

---

## Phase 6 — Property-Based Distributed Verification

Eventually Shōko may integrate with Hedgehog.

For example:

```haskell
property $ do
  agent <- forAll genValidAgent

  verify $
    scenario $ do
      register agent

      eventually $
        accountExists agent
```

This combines:

```text
generated inputs
       +
distributed verification
```

and could uncover system-level edge cases that example-based E2E tests miss.

Shrinking distributed failures would be particularly interesting but should not be an initial goal.

---

## Open Questions

Several architectural questions should remain deliberately unresolved until the first scenarios are implemented.

### How much should the type system enforce?

Potentially:

```text
environment safety
available adapters
action capabilities
observation capabilities
synthetic resources
```

could all appear in types.

This may provide excellent guarantees but could also make scenario authoring cumbersome.

The initial implementation should bias toward usability and move proven invariants into the type system later.

### Should observations be domain-specific or generic?

For example:

```haskell
accountExists agent
```

versus:

```haskell
postgres $
  rowExists "accounts" ...
```

The likely answer is both layers:

```text
Domain Observation
       │
       ▼
Infrastructure Observation
       │
       ▼
Adapter
```

Scenarios should normally use the domain layer.

### How much should OpenTelemetry matter?

OpenTelemetry provides rich structural evidence, but domain events are generally more semantically meaningful.

The likely hierarchy is:

```text
Domain Events
    ↓
Domain State / APIs
    ↓
Telemetry
    ↓
Logs
```

depending on the assertion being made.

Shōko should not require OpenTelemetry.

### Should continuous verification be part of Shōko?

Probably eventually.

A scenario such as:

```haskell
scenario "registration" ...
```

could potentially be:

```text
run during CI

run against staging

synthetically run against production

observe real production executions continuously
```

This is one of the strongest consequences of treating scenarios as portable specifications rather than tests.

---

## Long-Term Vision

Shōko should make distributed-system specifications executable across the entire software lifecycle.

A single scenario:

```haskell
scenario "agent registration" $ do
  ...
```

should eventually be usable for:

```text
development
      │
      ▼
local verification
      │
      ▼
CI
      │
      ▼
staging
      │
      ▼

      production verification
      │
      ▼
continuous observation
      │
      ▼
capture and replay
```

The same behavioral specification should survive across all of these contexts.

The long-term model is:

```text
                         Scenario
                            │
           ┌────────────────┼────────────────┐
           │                │                │
          Run            Observe          Replay
           │                │                │
           ▼                ▼                ▼
     Active execution   Real behavior   Recorded behavior
           │                │                │
           └────────────────┼────────────────┘
                            │
                            ▼
                         Evidence
                            │
                            ▼
                       Verification
```

This turns tests from disposable environment-specific scripts into durable descriptions of expected system behavior.

---

## Desired Properties

Shōko should aim for the following properties.

### Declarative

Scenarios describe expected behavior rather than execution mechanics.

```haskell
eventually $
  agentStatus agent `shouldBe` Qualified
```

rather than:

```haskell
threadDelay 5_000_000

status <- queryPostgres ...

status `shouldBe` "qualified"
```

### Portable

The same scenario should be executable across environments whenever the required capabilities are available.

```text
                Scenario
                   │
       ┌───────────┼───────────┐
       ▼           ▼           ▼
      Local      Staging    Production
```

### Observable

Verification should be based on evidence gathered from the distributed system.

### Correlated

Evidence should be attributable to the specific execution being verified whenever possible.

### Eventually Consistent

Asynchronous convergence should be represented directly rather than hidden behind sleeps.

### Production Safe

A scenario should be inspectable before execution and rejected when its required capabilities exceed the environment's policy.

### Diagnosable

Failures should explain the observed distributed behavior rather than simply report a failed assertion.

### Extensible

New evidence sources should be introduced through adapters without requiring changes to scenario semantics.

### Domain Oriented

Application scenarios should primarily speak in terms of domain concepts rather than infrastructure.

---

## Non-Goals

The initial project should explicitly avoid several tempting directions.

### General-Purpose Test Framework

Shōko does not need to replace Tasty, HUnit, Hedgehog, or QuickCheck.

It should integrate with them where useful.

### General-Purpose Effect System

The DSL should not attempt to model arbitrary application effects.

Only concepts necessary for distributed verification should enter the core language.

### Full Temporal Logic

Temporal operators are useful, but the initial implementation should not attempt to become a complete temporal-logic language or model checker.

Start with operations demanded by real scenarios:

```text
eventually
never
within
consistently
exactlyOnce
```

### Observability Backend

Shōko should consume telemetry rather than becoming a telemetry storage platform.

### Distributed Tracing Replacement

OpenTelemetry already solves propagation and trace representation.

Shōko should use it where useful.

### Production Workflow Engine

Shōko verifies production behavior.

It should not become responsible for orchestrating normal production business processes.

---

## Suggested Package Structure

The project can begin as a monorepo containing a small core and separate adapters.

```text
shoko/
├── shoko-core/
├── shoko-runner/
├── shoko-http/
├── shoko-postgres/
├── shoko-messagedb/
├── shoko-opentelemetry/
└── shoko-cli/
```

### `shoko-core`

Contains the semantic DSL.

Responsibilities include:

- scenarios;
- actions;
- observations;
- expectations;
- temporal assertions;
- execution identity;
- correlation;
- safety capabilities;
- evidence representation.

It should have minimal infrastructure dependencies.

### `shoko-runner`

Interprets scenarios.

Responsibilities include:

- scenario execution;
- environment configuration;
- adapter selection;
- retries;
- timeouts;
- evidence collection;
- safety enforcement;
- structured results.

### `shoko-http`

Provides HTTP actions and observations.

For example:

```haskell
request
  :: Request
  -> Action safety Response
```

It may also be responsible for propagating Shōko execution metadata through HTTP headers.

### `shoko-postgres`

Provides PostgreSQL-backed observations.

This adapter should primarily provide low-level capabilities.

Application code can define semantic observations on top of them.

For example:

```haskell
accountExists agent =
  postgresObservation $ ...
```

The scenario itself should never need to know that the observation is implemented using PostgreSQL.

### `shoko-messagedb`

Provides event-store observations.

This is likely to be one of the most important initial adapters for event-sourced systems.

Capabilities should include:

```text
event occurred
event occurred exactly once
event ordering
event causation
event correlation
stream state
category observations
```

### `shoko-opentelemetry`

Provides trace-based evidence.

Capabilities may include:

```text
span occurred
span failed
span attributes
trace relationships
service participation
latency
```

### `shoko-cli`

Provides a command-line interface.

Potential commands:

```bash
shoko run registration --env staging

shoko observe registration --env production

shoko replay execution.json

shoko inspect execution-id

shoko list scenarios
```

---

## Evidence Model

Internally, Shōko should normalize observations into an evidence model.

For example:

```haskell
data Evidence a = Evidence
  { source      :: EvidenceSource
  , observedAt  :: UTCTime
  , executionId :: ExecutionId
  , value       :: a
  , metadata    :: EvidenceMetadata
  }
```

Possible evidence sources:

```haskell
data EvidenceSource
  = DomainEvent
  | Database
  | Http
  | Trace
  | Metric
  | Log
  | Message
  | ExternalSystem
```

The evidence model should preserve enough source information for debugging while keeping scenarios independent of the source.

This creates an important distinction:

```text
Observation
    │
    │ asks a question
    ▼
Adapter
    │
    │ discovers something
    ▼
Evidence
    │
    │ evaluated against
    ▼
Expectation
```

An observation is therefore not itself an assertion.

It is a request for evidence.

An expectation determines whether the evidence satisfies the scenario.

---

## Evidence Provenance

Evidence should retain provenance.

For example:

```text
AgentQualified

Source:
  MessageDB

Stream:
  agent-01H...

Global Position:
  18299182

Correlation:
  shoko_01J...

Causation:
  qualification-requested-01J...

Observed:
  2026-09-29T18:42:01Z
```

This is valuable both for debugging and for determining how trustworthy an observation is.

A future version of Shōko could potentially require corroborating evidence from multiple sources:

```haskell
corroborate $ do
  occurred @AgentQualified agent
  agentStatus agent `shouldBe` Qualified
```

This could verify that both the domain history and externally visible state agree.

---

## Scenario Identity

Scenarios should have stable identities independent of individual executions.

For example:

```haskell
scenario
  "agent-registration"
  "Agent registration"
  $ do
    ...
```

Each invocation creates an execution:

```text
Scenario ID:
  agent-registration

Execution ID:
  shoko_01J...

Environment:
  production

Mode:
  observe
```

Stable scenario identities make it possible to compare results over time.

For example:

```text
agent-registration

Last 100 executions:

98 passed
2 failed

p50 completion: 430ms
p95 completion: 1.8s
p99 completion: 4.2s
```

Shōko can therefore eventually provide useful production reliability information without becoming a general-purpose observability platform.

---

## Failure Semantics

Failures should distinguish between different classes of problems.

For example:

```haskell
data VerificationFailure
  = ExpectationFailed
  | ObservationUnavailable
  | ObservationTimedOut
  | ActionFailed
  | AdapterFailed
  | UnsafeActionRejected
  | CorrelationLost
```

These differences matter.

For example:

```text
AgentQualified was not observed
```

is fundamentally different from:

```text
Shōko could not connect to MessageDB
```

The former suggests a system behavior failure.

The latter means Shōko could not establish whether the behavior occurred.

The framework should avoid reporting both simply as:

```text
FAILED
```

---

## Unknown Results

Distributed verification benefits from a three-state model:

```text
Pass
Fail
Unknown
```

rather than only:

```text
Pass
Fail
```

For example:

```text
Expected:

  AgentQualified

Evidence source:

  MessageDB

Result:

  MessageDB unavailable
```

Shōko does not know that the system failed.

It knows that verification could not be completed.

The result should therefore be:

```text
UNKNOWN
```

rather than:

```text
FAIL
```

This distinction becomes particularly important for production verification.

---

## Production Verification Philosophy

Production should not merely be another environment.

It has fundamentally different constraints.

Shōko should assume:

- production contains real users;
- actions may have irreversible consequences;
- external integrations may charge money;
- notifications may reach real people;
- analytics may be polluted;
- synthetic data may trigger business processes;
- verification itself can create load;
- observation infrastructure can fail independently.

Production verification should therefore default to:

```text
observe, don't mutate
```

When mutation is necessary:

```text
synthetic before real
```

When synthetic mutation is used:

```text
constrain the blast radius
```

The production interpreter should always fail closed.

If Shōko cannot establish that an operation is permitted, it should not perform the operation.

---

## Safety as Capabilities

Rather than relying only on a linear safety classification, the framework may eventually model safety through capabilities.

For example:

```haskell
data Capability
  = ReadProduction
  | CreateSyntheticData
  | SendExternalRequest
  | SendEmail
  | ModifyRealData
  | DeleteData
  | FinancialSideEffect
```

A scenario declares what it requires.

An environment declares what it permits.

Execution is possible only when:

```text
required capabilities
        ⊆
permitted capabilities
```

For example:

```text
Scenario:

  ReadProduction
  CreateSyntheticData

Production Environment:

  ReadProduction
  CreateSyntheticData
  SendExternalRequest

Result:

  allowed
```

Whereas:

```text
Scenario:

  ReadProduction
  SendEmail

Production Environment:

  ReadProduction
  CreateSyntheticData

Result:

  rejected
```

This may ultimately provide a more expressive safety system than a single `Safety` enum.

---

## Dry Run

Production execution should support a dry-run mode.

For example:

```bash
shoko run registration \
  --env production \
  --dry-run
```

Output:

```text
Scenario:
  agent-registration

Required capabilities:

  ✓ ReadProduction
  ✓ CreateSyntheticData
  ✓ SendExternalRequest

Actions:

  1. Create synthetic agent
  2. POST /registration
  3. Observe RegistrationSubmitted
  4. Observe AccountCreated
  5. Observe AgentQualified

External effects:

  MLS API request

Suppressed effects:

  Welcome email

Production policy:

  ALLOWED
```

Dry runs make the safety model inspectable rather than implicit.

---

## Cleanup

Synthetic scenarios frequently require cleanup.

Cleanup should be part of the execution model rather than an ad-hoc final action.

For example:

```haskell
withSyntheticAgent $ \agent -> do
  register agent

  eventually $
    agentStatus agent `shouldBe` Qualified
```

The runner knows that `agent` is a managed synthetic resource.

It can therefore perform cleanup regardless of whether the scenario succeeds.

Conceptually:

```text
Acquire
   │
   ▼
Execute
   │
   ▼
Verify
   │
   ▼
Release
```

This resembles resource management through `bracket`.

Cleanup failure should also be reported independently from scenario verification failure.

---

## Concurrency

Distributed scenarios may contain independent expectations.

For example:

```haskell
expectConcurrently $ do
  accountExists agent
  userExists agent
  welcomeEmailRequested agent
```

There should be no requirement that these observations occur sequentially.

The execution engine should eventually be capable of constructing an expectation graph and evaluating independent observations concurrently.

For example:

```text
             RegistrationSubmitted
                      │
          ┌───────────┼───────────┐
          │           │           │
          ▼           ▼           ▼
    AccountCreated UserCreated EmailRequested
          │
          ▼
 QualificationRequested
          │
          ▼
    AgentQualified
```

This graph representation may eventually become useful for both execution and visualization.

---

## Scenario Graph

Although scenarios are written using `do` notation, internally Shōko may benefit from representing them as a graph rather than immediately interpreting them.

For example:

```text
Scenario
   │
   ▼
Scenario AST
   │
   ▼
Dependency Graph
   │
   ├── safety analysis
   ├── dry run
   ├── visualization
   ├── execution
   └── replay
```

This argues for an inspectable representation of the scenario language rather than directly embedding everything in `IO`.

The DSL should preserve enough structure to inspect a scenario before executing it.

That becomes particularly important for production safety.

---

## DSL Representation

An initial implementation might use a GADT describing scenario operations.

Conceptually:

```haskell
data ScenarioF next where
  Perform
    :: Action safety a
    -> (a -> next)
    -> ScenarioF next

  Observe
    :: Observation a
    -> (a -> next)
    -> ScenarioF next

  Expect
    :: Expectation
    -> next
    -> ScenarioF next
```

The exact representation should remain an implementation detail.

The important property is that scenarios remain inspectable.

Shōko should be able to answer:

```text
What actions will this scenario perform?

What capabilities does it require?

What external systems can it touch?

What observations will it make?

Can this scenario safely execute in production?
```

before executing anything.

---

## Configuration

Environment configuration should remain separate from scenario definitions.

For example:

```yaml
environment: production

adapters:
  events:
    type: message-db
    connection: production-read-replica

  accounts:
    type: graphql
    endpoint: account-service

  traces:
    type: opentelemetry

policy:
  capabilities:
    - ReadProduction
    - CreateSyntheticData

  max-concurrency: 2

  synthetic-prefix: "shoko-"
```

Secrets should come from the environment or an external secret provider rather than scenario configuration.

---

## CLI

Potential CLI design:

```text
shoko run <scenario>

shoko observe <scenario>

shoko replay <execution>

shoko inspect <execution>

shoko explain <scenario>

shoko list
```

Examples:

```bash
shoko run agent-registration --env local

shoko run agent-registration --env staging

shoko run agent-registration --env production --dry-run

shoko observe agent-registration --env production

shoko inspect shoko_01J...

shoko explain agent-registration
```

`explain` should show the scenario without executing it:

```text
Scenario:
  agent-registration

Actions:
  CreateSyntheticAgent
  RegisterAgent

Expectations:
  RegistrationSubmitted
  AccountCreated
  UserCreated
  AgentQualified

Required capabilities:
  CreateSyntheticData
  SendExternalRequest

Production:
  Allowed

Estimated timeout:
  30 seconds
```

---

## What Shōko Is Not

Shōko should deliberately avoid becoming several adjacent tools.

It is not a unit testing framework.

Use:

```text
tasty
HUnit
Hedgehog
QuickCheck
```

for unit and property testing.

It is not primarily a contract testing framework.

Use Pact or schema-level compatibility testing for service contracts.

It is not a load-testing framework.

Use k6 or dedicated load-testing infrastructure.

It is not an observability platform.

Use OpenTelemetry, Prometheus, Grafana, and logging infrastructure.

It is not a workflow engine.

It observes and verifies workflows; it does not own their execution.

Shōko sits above these systems and asks:

> What evidence demonstrates that this distributed behavior is correct?

---

## Development Strategy

Shōko should be built from concrete distributed-system problems rather than designing the entire DSL up front.

The first implementation should choose one real workflow.

For example:

```text
Agent Registration
```

Implement only enough DSL to express that workflow cleanly.

Then add another substantially different workflow.

For example:

```text
MLS Qualification
```

Then another:

```text
Referral Creation
```

Every new abstraction should be justified by multiple concrete scenarios.

This should help prevent the DSL from becoming an overly general effect system before its semantics are understood.

---

## Phase 1 — Basic Distributed Verification

Goal:

> Verify one distributed workflow locally and in staging using the same scenario.

Implement:

- scenario DSL;
- HTTP actions;
- MessageDB observations;
- PostgreSQL observations;
- correlation IDs;
- `eventually`;
- structured results.

Example:

```haskell
scenario "agent registration" $ do
  agent <- given uniqueAgent

  register agent

  expect $
    occurred @RegistrationSubmitted agent

  eventually $
    accountExists agent

  eventually $
    agentStatus agent `shouldBe` Qualified
```

The important proof is:

```text
                     Same Scenario
                          │
                 ┌────────┴────────┐
                 ▼                 ▼
               Local            Staging
                 │                 │
                 ▼                 ▼
             Adapters          Adapters
                 │                 │
                 └────────┬────────┘
                          ▼
                    Same Semantics
```

---

## Phase 2 — Production Safety

Goal:

> Safely execute or observe scenarios in production.

Implement:

- capability model;
- environment policies;
- dry-run;
- synthetic resources;
- cleanup;
- production read-only adapters;
- fail-closed execution.

Production execution should initially require explicit opt-in.

---

## Phase 3 — Production Observation

Goal:

> Verify naturally occurring production behavior without initiating it.

Implement:

```haskell
observe @RegistrationSubmitted
```

along with:

- correlation discovery;
- event subscriptions;
- observation windows;
- sampling;
- rate limits;
- continuous verification.

At this stage, Shōko begins functioning as an executable specification of production invariants.

---

## Phase 4 — Causal Verification

Goal:

> Verify distributed workflows rather than isolated outcomes.

Implement:

```text
P causes Q

P eventuallyCauses Q

P causesExactlyOnce Q
```

and workflow expressions such as:

```haskell
expect

expectFlow $
  RegistrationSubmitted
    --> AccountCreated
    --> QualificationRequested
    --> AgentQualified
```

Use event correlation and causation metadata wherever available.

The important distinction is between:

```text
A happened before B
```

and:

```text
A caused B
```

Shōko should prefer explicit causation metadata when the platform provides it rather than infer causality solely from timing.

---

## Phase 5 — Capture and Replay

Goal:

> Turn real distributed executions into reproducible verification cases.

Implement:

```bash
shoko capture production --execution <id>

shoko replay <capture> --against local
```

Captured executions should contain a normalized representation of the evidence associated with an execution.

For example:

```text
Execution
├── inputs
├── actions
├── domain events
├── interactions
├── observations
├── timings
├── correlation
├── causation
└── traces
```

The capture format should avoid storing infrastructure-specific representations where a stable semantic representation is possible.

For example, prefer:

```text
AgentQualified
agent_id = 123
```

over storing a raw MessageDB row unless the raw representation is specifically needed.

Replay does not necessarily mean reproducing every external interaction.

Different replay strategies may eventually exist:

```text
Evidence Replay
  Verify a recorded execution against a scenario.

Input Replay
  Re-execute the original inputs against another environment.

Event Replay
  Feed recorded domain events into a local environment.

Interaction Replay
  Replace external dependencies with recorded interactions.
```

These should not all be part of the first implementation.

The initial goal should simply be:

> Preserve enough evidence from a real execution to evaluate a scenario later.

This allows a production failure to become a durable regression case.

---

## Phase 6 — Property-Based Distributed Verification

Eventually Shōko may integrate with Hedgehog.

For example:

```haskell
property $ do
  agent <- forAll genValidAgent

  verify $
    scenario $ do
      register agent

      eventually $
        accountExists agent
```

This combines:

```text
generated inputs
       +
distributed verification
```

and could uncover system-level edge cases that example-based E2E tests miss.

A more interesting future direction would be generating entire sequences of domain operations:

```haskell
property $ do
  operations <- forAll genAgentLifecycle

  verify $
    execute operations
```

For example:

```text
Register
   ↓
Endorse
   ↓
Qualify
   ↓
Join Chapter
   ↓
Update Profile
```

Shōko could then verify invariants after every transition.

Shrinking distributed failures would be particularly valuable:

```text
Register
Endorse
Qualify
Join Chapter
Update Profile
Remove Endorsement
Change Chapter
...
```

might shrink to:

```text
Register
Qualify
Change Chapter
```

However, distributed shrinking introduces substantial complexity around state, cleanup, replay, and nondeterminism.

It should not be an initial goal.

---

## Open Questions

Several architectural questions should remain deliberately unresolved until the first scenarios are implemented.

### How Much Should the Type System Enforce?

Potentially:

```text
environment safety
available adapters
action capabilities
observation capabilities
synthetic resources
```

could all appear in types.

This may provide excellent guarantees but could also make scenario authoring cumbersome.

The initial implementation should bias toward usability and move proven invariants into the type system later.

The type system should primarily prevent dangerous or nonsensical operations rather than attempt to prove the entire scenario correct.

### Should Observations Be Domain-Specific or Generic?

For example:

```haskell
accountExists agent
```

versus:

```haskell
postgres $
  rowExists "accounts" ...
```

The likely answer is both layers:

```text
Domain Observation
       │
       ▼
Infrastructure Observation
       │
       ▼
Adapter
```

Infrastructure packages provide reusable primitives.

Application packages build semantic observations from those primitives.

Scenarios should normally use the domain layer.

For example:

```haskell
accountExists agent
```

could internally use:

```haskell
postgresObservation ...
```

in one environment and:

```haskell
graphqlObservation ...
```

in another.

### How Much Should OpenTelemetry Matter?

OpenTelemetry provides rich structural evidence, but domain events are generally more semantically meaningful.

The likely hierarchy is:

```text
Domain Events
     │
     ▼
Domain State / APIs
     │
     ▼
Telemetry
     │
     ▼
Logs
```

depending on the assertion being made.

This is not a strict hierarchy of trust.

Different evidence answers different questions.

For example:

```text
Domain Event:
  Did qualification happen?

Read Model:
  Is qualification externally visible?

Trace:
  Which services participated?

Metric:
  Is this behavior degrading across many executions?

Log:
  What implementation detail explains the failure?
```

Shōko should not require OpenTelemetry.

### Should Continuous Verification Be Part of Shōko?

Probably eventually.

A scenario such as:

```haskell
scenario "registration" ...
```

could potentially be:

```text
run during CI

run against staging

synthetically run against production

observe real production executions continuously
```

This is one of the strongest consequences of treating scenarios as portable specifications rather than tests.

The same specification becomes useful throughout the lifecycle of the system.

### Should Evidence Be Persisted?

Probably.

Persisted evidence would enable:

- debugging;
- replay;
- historical comparisons;
- regression analysis;
- latency analysis;
- production verification history.

However, Shōko should avoid becoming a large telemetry database.

An execution record could instead contain references to external evidence where appropriate.

For example:

```text
Execution
  ID: shoko_01J...

Evidence
  MessageDB:
    global_position: 18299182

  OpenTelemetry:
    trace_id: abc123

  PostgreSQL:
    observation captured at 18:42:01

  GraphQL:
    response snapshot
```

### What Is the Correct Boundary Between Observation and Expectation?

This distinction should remain explicit.

For example:

```haskell
agentStatus agent
```

is an observation.

```haskell
agentStatus agent `shouldBe` Qualified
```

is an expectation.

Likewise:

```haskell
events @AgentQualified agent
```

returns evidence.

```haskell
occurred @AgentQualified agent
```

is an expectation built on that evidence.

Keeping these concepts separate should make adapters more reusable.

### How Should Nondeterminism Be Represented?

Some distributed workflows legitimately permit multiple outcomes.

For example:

```text
QualificationRequested
        │
        ├── AgentQualified
        │
        └── AgentRejected
```

The DSL may eventually need constructs such as:

```haskell
oneOf $ do
  occurred @AgentQualified agent
  occurred @AgentRejected agent
```

or richer state-machine specifications.

This should be driven by concrete scenarios rather than designed prematurely.

---

## Example: Full Registration Scenario

A mature Shōko scenario might eventually look something like:

```haskell
registrationScenario :: Scenario
registrationScenario =
  scenario "agent-registration" $ do
    agent <-
      given $
        syntheticAgent
          { market = LosAngeles
          }

    when $
      register agent

    expect $ do
      occurredExactlyOnce @RegistrationSubmitted agent

      eventually $
        accountExists agent

      eventually $
        userExists agent

      eventually $
        occurredExactlyOnce @QualificationRequested agent

      eventually (within $ seconds 30) $
        agentStatus agent `shouldBe` Qualified

      consistentlyFor (seconds 5) $
        accountCount agent `shouldBe` 1

      never $
        duplicateUserExists agent
```

The same specification could then be used as:

```bash
shoko run agent-registration --env local

shoko run agent-registration --env staging

shoko run agent-registration --env production --dry-run

shoko run agent-registration --env production

shoko observe agent-registration --env production
```

The semantics remain:

```text
Register this agent and establish sufficient evidence
that the distributed registration workflow behaved correctly.
```

Only the mechanism for obtaining that evidence changes.

---

## Example: Production Observation

A production-only observation scenario might be:

```haskell
registrationInvariant :: Scenario
registrationInvariant =
  scenario "registration-invariant" $ do
    registration <-
      observe @RegistrationSubmitted

    expect $ do
      eventually (within $ seconds 10) $
        occurred @AccountCreated registration

      eventually (within $ seconds 10) $
        occurred @UserCreated registration

      eventually (within $ seconds 30) $
        occurred @QualificationRequested registration

      never $
        duplicateAccountCreated registration
```

Shōko could attach this specification to sampled real production registrations.

For each observed registration:

```text
RegistrationSubmitted
        │
        ▼
Start verification
        │
        ├── AccountCreated?
        ├── UserCreated?
        ├── QualificationRequested?
        └── Duplicate AccountCreated?
```

No synthetic transaction is required.

The production system itself generates the scenario input.

---

## Example: Diagnosing a Failure

Suppose registration fails because the qualification worker cannot reach an external API.

Instead of:

```text
agent-registration FAILED
```

Shōko should ideally produce something closer to:

```text
Scenario:
  agent-registration

Execution:
  shoko_01JABC...

Result:
  FAILED

Timeline:

  +0ms
  ✓ RegistrationSubmitted

  +18ms
  ✓ AccountCreated

  +31ms
  ✓ UserCreated

  +47ms
  ✓ QualificationRequested

  +53ms
  ✓ qualification-worker started

  +241ms
  ✗ external MLS request returned 500

  +30s
  ✗ AgentQualified not observed

Failed expectation:

  eventually within 30s:
    AgentQualified

Correlation:

  shoko_01JABC...

Evidence:

  MessageDB:
    RegistrationSubmitted
    AccountCreated
    UserCreated
    QualificationRequested

  OpenTelemetry:
    qualification-worker
      → MLS API
      ← HTTP 500
```

The verification result becomes a compact explanation of the distributed execution.

This is substantially more useful than an assertion failure tied to one service.

---

## Example: Detecting Projection Failure

Consider a workflow where the domain behavior succeeds but a projection worker fails.

Shōko observes:

```text
✓ AgentQualified event occurred

✓ qualification-worker completed

✗ GraphQL still reports:
    status = Pending
```

The scenario might contain:

```haskell
eventually $
  occurred @AgentQualified agent

eventually $
  agentStatus agent `shouldBe` Qualified
```

The first expectation succeeds.

The second fails.

This immediately distinguishes:

```text
domain failure
```

from:

```text
projection failure
```

Multiple evidence sources therefore provide diagnostic value beyond redundant verification.

---

## Example: Duplicate Side Effect

Some of the most dangerous distributed-system failures involve something happening more than once.

Shōko should make cardinality easy to express.

For example:

```haskell
occurredExactlyOnce @AccountCreated agent
```

or:

```haskell
count @WelcomeEmailRequested agent
  `shouldBe` 1
```

This is especially important for:

- at-least-once message processing;
- worker retries;
- subscription restarts;
- race conditions;
- duplicate event handling;
- idempotency failures.

Negative and cardinality assertions should therefore be first-class rather than afterthoughts.

---

## Example: Cross-Service Invariant

Shōko should be particularly useful when correctness cannot be established from one service.

For example:

```haskell
scenario "qualified member consistency" $ do
  agent <- given qualifiedAgent

  expect $ do
    accountStatus agent
      `shouldBe` Active

    userExists agent

    membershipStatus agent
      `shouldBe` Member

    qualificationStatus agent
      `shouldBe` Qualified
```

Each observation may come from a different service.

```text
accountStatus
      │
      ▼
Account Service

userExists
      │
      ▼
User Service

membershipStatus
      │
      ▼
Membership Service

qualificationStatus
      │
      ▼
MLS Service
```

Shōko verifies the invariant across the platform rather than treating each service independently.

This is one of the primary problems the project exists to solve.

---

## Initial Implementation Recommendation

The first implementation should be deliberately smaller than the full design in this document.

Start with:

```text
Scenario
Action
Observation
Expectation
Evidence
Environment
Runner
```

and only:

```text
eventually
never
exactlyOnce
```

for temporal/cardinality semantics.

Build three adapters:

```text
HTTP
PostgreSQL
MessageDB
```

Ignore initially:

```text
OpenTelemetry
Prometheus
capture/replay
continuous production verification
property-based generation
complex temporal logic
scenario visualization
```

Use one real distributed workflow as the forcing function.

The first meaningful milestone is:

> The exact same Haskell scenario verifies a distributed workflow locally and in staging using different adapters.

The second milestone is:

> The same scenario can be inspected and proven safe before being allowed to run against production.

The third milestone is:

> The behavioral expectations from that scenario can be attached to naturally occurring production executions without generating traffic.

If those three properties work cleanly, the central architecture is validated.

---

## Success Criteria

Shōko is successful if a developer can express:

```haskell
scenario "agent registration" $ do
  agent <- given syntheticAgent

  register agent

  eventually $
    agentStatus agent `shouldBe` Qualified
```

without needing to know whether verification happens through:

```text
PostgreSQL
MessageDB
GraphQL
OpenTelemetry
Pub/Sub
```

and then execute the same behavioral specification against:

```text
local
CI
staging
production
```

subject to explicit environment safety policies.

More broadly, Shōko succeeds if distributed-system verification changes from:

> Write scripts that poke several services and hope the expected side effects occurred.

to:

> Specify the evidence that constitutes correct behavior and let the environment determine how that evidence can safely be established.

---

## Role in the Platform Rewrite

Shōko is being built for a specific purpose first.

The TAN platform is being rewritten onto keiro-runtime: Keiro and Kiroku as the backend and event store, Kafka as the integration transport, and services reorganized into bounded contexts.

Shōko is the core verification tool for that rewrite, and afterwards for developing features in the keiro-runtime-backed services.

That gives the project two horizons:

```text
Horizon 1 — Migration verification

  Does the keiro implementation of a workflow
  produce the same observable consequences
  as the legacy implementation?

Horizon 2 — Keiro-native verification

  Does a feature in a keiro-runtime bounded context
  produce the evidence that constitutes correct behavior?
```

The same DSL, runner, and evidence model serve both. What differs is which bindings exist and which scenarios are written.

"Legacy" means the services being replaced. Some are Haskell services on MessageDB, such as registration-service-v2, account-service-v2, and mls-service-v2, with their read schemas, REST read endpoints, and Kafka topics. Others are not Haskell at all, such as the Go qualified-agent service and the Node services, and for those the PostgreSQL database is the only evidence available.

"Target" means a keiro-runtime service: a Kiroku event store, Keiro process managers and workflows, Kafka integration events, and keiro-owned read models.

---

## Implementation as an Interpreter Axis

Environment and execution mode are already orthogonal axes.

The rewrite adds a third: implementation.

```text
Environment        Mode            Implementation
  local              run             legacy
  CI                 observe         keiro
  staging            replay
  production
```

A binding is an environment paired with an implementation. The binding selects the adapters.

```text
accountExists

  (local, legacy)    → PostgreSQL account_service_read
  (local, keiro)     → Kiroku read model
  (staging, legacy)  → account-service-v2 REST
  (staging, keiro)   → keiro service read endpoint
```

Configuration names the implementation alongside the environment:

```yaml
environment: local
implementation: keiro

adapters:
  events:
    type: kiroku
    connection: local

  accounts:
    type: postgres
    schema: account_read
```

The scenario itself names neither.

Production policy remains attached to the environment. Implementation never relaxes it.

---

## Parity Scenarios

A parity scenario is one scenario that passes against both implementations of the same workflow.

```text
                  registration scenario
                           │
              ┌────────────┴────────────┐
              ▼                         ▼
       (local, legacy)           (local, keiro)
              │                         │
              ▼                         ▼
            Pass                      Pass
                           │
                           ▼
            behavioral parity for this scenario
```

Parity is the primary evidence that a rewritten workflow is safe to cut over.

### Parity Scenarios Use the Domain Layer Only

The legacy and keiro implementations will not share an event vocabulary.

The legacy registration flow records `MembershipRequestSubmitted`, `ApprovalReceived`, and `QualifiedAgentVerified`. The rewrite is free to name its events differently, and will.

An assertion such as:

```haskell
occurred @AccountCreated agent
```

is therefore coupled to one implementation.

Parity scenarios use domain observations only:

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

      never $
        duplicateAccountExists agent
```

Each domain observation has one implementation per binding.

Event-level assertions remain available, but they belong in implementation-specific invariant scenarios:

```haskell
registrationCausality :: Scenario
registrationCausality =
  scenario "registration-causality" $ do
    requires Keiro

    agent <- given syntheticAgent

    when $
      register agent

    expect $
      expectFlow $
        RegistrationSubmitted
          `causes` AccountCreated
```

A scenario that requires an implementation is rejected by a binding that does not provide it, in the same way that a scenario requiring a capability is rejected by an environment that does not permit it.

### The Domain Vocabulary Belongs to the Bounded Context

The observations a parity scenario uses form a vocabulary.

That vocabulary is owned by the bounded context being rewritten. It lives in an application package beside the context, not in Shōko and not in the legacy service.

The legacy binding implements the vocabulary against legacy infrastructure. The keiro binding implements it against keiro infrastructure. Neither implementation defines it.

```text
                 domain vocabulary
             (owned by the bounded context)
                          │
            ┌─────────────┴─────────────┐
            ▼                           ▼
     legacy binding                keiro binding
            │                           │
     MessageDB, REST,            Kiroku, Kafka,
     read schemas                keiro read models
```

---

## Legacy Support Policy

Legacy bindings exist to verify the migration, not to improve the legacy services.

Legacy support is therefore read-mostly and deliberately thin.

The baseline is a generic PostgreSQL verifier:

```text
row exists
row count
column value
row absent
```

parameterized by schema, table, and predicate, with the domain vocabulary mapped onto it per service.

For non-Haskell legacy services that is the whole binding. There is no event store to read, no instrumentation to rely on, and no reason to add any. The database is the evidence.

```haskell
-- legacy binding for a non-Haskell service
qualificationVerified agent =
  postgres $
    rowExists "qualified_agent_service" "qualified_agents"
      [ "email" .== agent.email
      , "status" .== "verified"
      ]
```

For the Haskell legacy services the binding may add, where they already exist:

- MessageDB observations through message-db-hs;
- HTTP actions against the existing REST endpoints;
- Kafka observations on the existing integration topics.

Correlation is always by business key.

Legacy services receive no new instrumentation for Shōko's benefit.

The exceptions are changes without which a scenario cannot run at all, such as a stubbed or allowlisted OTP step in staging.

Legacy bindings are disposable. They are deleted when the workflow they verify is cut over.

---

## Correlation Strategies

Legacy and target differ in what they can correlate on.

```text
ByExecutionId
  The Shōko execution id propagates into event metadata.
  Available where the implementation threads it through.

ByBusinessKey
  A domain identifier every participant already carries,
  such as a registration id.
  Available everywhere, including legacy.
```

A scenario asks for correlation abstractly. A binding declares which strategies it supports, and the runner chooses the strongest one available.

Kiroku already stores typed correlation and causation ids on every event and can retrieve events by correlation and by causation descendants.

Keiro does not yet populate them. `ByExecutionId` on the keiro side depends on keiro threading an inbound correlation id into every event and dispatched command. That is a requirement on keiro-runtime, raised as an improvement request. Until it lands, keiro bindings also use `ByBusinessKey`.

Legacy services set each message's correlation id to its own id, so legacy bindings always use `ByBusinessKey`.

---

## Migration Verification Modes

Each execution mode has a migration use.

### Parity Run

Run mode against both implementations in local and CI.

```bash
shoko run registration-parity --env local --impl legacy

shoko run registration-parity --env local --impl keiro
```

A parity suite that passes on both bindings is the cutover gate for that workflow.

### Shadow Observation

Observe mode against legacy production traffic while the keiro implementation runs in shadow.

```text
legacy production
       │
       ▼
RegistrationSubmitted (legacy)
       │
       ├── legacy consequences observed
       │
       └── keiro consequences observed
                │
                ▼
         same business key
                │
                ▼
        compare evidence
```

Correlation is by business key, because nothing else spans both implementations.

### Input Replay

Capture legacy executions and replay their inputs against a keiro stack.

```bash
shoko capture staging --impl legacy --execution abc123

shoko replay abc123 --env local --impl keiro
```

The evidence captured from the legacy execution becomes the expected evidence for the keiro execution.

This moves input replay earlier than the phase plan suggests. The rewrite makes it valuable as soon as a workflow exists on both sides.

### Cutover Gates

Conceptually:

```text
parity suite green on legacy and keiro
             │
             ▼
shadow observation shows no divergence
             │
             ▼
          cutover
             │
             ▼
observe mode runs the same scenarios
as production invariants on keiro
```

---

## Keiro-Native Verification

After a workflow is cut over, the same scenarios continue as the verification tool for developing features in the keiro-runtime service.

Keiro-runtime provides evidence that legacy could not:

```text
typed correlation and causation ids
events by correlation
causation descendants and ancestors
process-manager state streams
workflow effects
Kafka integration events between contexts
keiro-owned read models
```

This lets the causal operators be exact rather than inferred from timing:

```haskell
expectFlow $ do
  RegistrationSubmitted
    `causes` AccountCreated

  AccountCreated
    `causes` QualificationRequested
```

### Bounded Contexts

A keiro-native scenario normally lives with one bounded context and speaks that context's vocabulary.

A cross-context scenario verifies integration events, which are producer-owned contracts:

```haskell
scenario "registration completes membership" $ do
  agent <- given syntheticAgent

  when $
    register agent

  expect $ do
    eventually $
      published @RegistrationCompleted agent

    eventually $
      membershipStatus agent `shouldBe` Member
```

The cross-service invariant example earlier in this document becomes a cross-context invariant.

### Relationship to kenshou

keiro-runtime-kenshou verifies the runtime itself: correctness properties, concurrency, fault injection, and benchmarks.

Shōko verifies the applications built on the runtime.

The two should share result vocabulary. kenshou's outcomes already distinguish a failed system from an inconclusive verification, and Shōko's results should be publishable as verification evidence in the platform's catalogs.

---

## Revised Milestones

The rewrite changes the first milestone and leaves the others in place.

The first milestone becomes:

> The same parity scenario verifies the registration workflow against the legacy local stack and against the keiro local stack.

The second milestone is unchanged:

> The same scenario can be inspected and proven safe before being allowed to run against production.

The third milestone is unchanged in form and gains a migration use:

> The behavioral expectations from that scenario can be attached to naturally occurring production executions, including legacy traffic observed during shadow operation.

Prerequisites the first milestone depends on:

- a composed local environment that runs the legacy services together, which does not exist today;
- a composed local environment for the keiro implementation of the same workflow;
- the domain vocabulary package for the registration context;
- keiro threading correlation ids, or the business-key strategy in the meantime.

The workflow chosen for the first milestone should be whichever one exists on both sides first.

---

## Summary

**Shōko (証拠)** means **evidence** or **proof**.

That name reflects the central idea of the project.

Shōko does not primarily ask:

> Did this test pass?

It asks:

> What evidence would demonstrate that this distributed system behaved correctly?

A scenario describes that evidence.

Adapters determine how it can be observed.

Environment policies determine what actions are safe.

The runner collects evidence and evaluates the specification.

This creates a common verification model across:

```text
development
CI
staging
production
```

and across:

```text
active execution
production observation
recorded replay
```

The resulting architecture is:

```text
                    Behavioral Specification
                             │
                             ▼
                           Shōko
                             │
             ┌───────────────┼───────────────┐
             │               │               │
             ▼               ▼               ▼
           Action        Observation      Expectation
             │               │               │
             └───────────────┼───────────────┘
                             │
                             ▼
                          Evidence
                             │
                             ▼
                        Verification
                             │
             ┌───────────────┼───────────────┐
             ▼               ▼               ▼
           Local          Staging        Production
```

The long-term goal is for a distributed-system behavior to be specified **once** and then continuously useful throughout the lifecycle of the system.

That is the core proposition of **証拠 / Shōko**.
