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
