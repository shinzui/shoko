# Verify the running staging system with context-owned scenarios

Date: 2026-10-01

Status: Accepted for bootstrap; revised after the user's staging clarification

## Context

[RES-1](../research/initial-specification-requirement-validation.md) identified migration parity as a useful application, and the first plan inferred a requirement to compose local legacy/Keiro stacks. The user clarified that the actual target is a complete system already running in a Kubernetes test namespace and explicitly chose verification of this staging system first. Local paired environments are therefore not bootstrap prerequisites. The existing ADR path remains stable.

The [platform rewrite-gates decision](mori://tan/tan-platform/docs/adr-0002-track-infrastructure-and-observability-as-rewrite-gates) distinguishes declarations from operational evidence. Kenshou's [resolved-identity decision](mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-2) motivates identifying the implementations actually tested. Both apply to staging acceptance without requiring a second deployment.

## Decision

The bootstrap builds the reusable verifier and demonstrates a real positive workflow and a documented negative scenario against the existing staging system. A negative scenario passes when its expected rejection or invariant is observed; separate controls demonstrate Fail and Unknown. Local fixtures test Shōko's library/adapters. CI may launch the same staging command, but is neither a target environment nor required to provision application services. Production execution remains deferred.

Registration completion from an already-qualified agent is the researched reference. The accepted workflow contract must match the deployed system and may select another available workflow with a documented reason. Record controlled inputs, real public actions, downstream consequences, evidence strength, business-key correlation, external-effect policy, and cleanup/retention. Qualification/admin approval is a precondition of the narrower registration slice. OTP behavior and controlled recipients must be verified in staging; do not assume the local stub is configured or that a completion acknowledgement establishes real account/user writes.

The integration layer records the expected and observed Kubernetes cluster/namespace identity, deployed workload image digests and available source revisions, actual action/evidence endpoints, credential references, and access route. Record identities before and after verification; mismatch, missing identity, or deployment change prevents an accepted Pass while preserving individual workflow evidence. Kubernetes metadata is supplied to generic core types by the host; core does not discover resources or manage workloads.

Selecting a test namespace does not automatically isolate databases, brokers, external providers, or recipients. Match those resources to the explicit staging contract. Use scoped evidence credentials, approved test identities/effects, endpoint allowlists, bounded operations, and run-owned data. Shōko does not deploy, scale, restart, migrate, reset, or remove the application environment. Cleanup covers only owned test records and verifier access resources; unsupported deletion has explicit bounded retention.

The bounded context owns business vocabulary and scenarios beside its domain code. Bindings translate domain operations and observations to a selected environment and implementation. Shōko owns the generic HTTP, PostgreSQL, Message DB, and Kiroku adapters; the actual staging binding uses only the stores present. Legacy support stays thin and business-key correlated, without added instrumentation. Use machine-callable REST or PostgreSQL rather than assuming browser-session GraphQL access. Do not assert the nonexistent registration welcome email.

[Keiro IR-52](mori://shinzui/keiro/okf/improvement-requests/concepts/IR-52) owns durable execution-correlation propagation; business-key correlation is sufficient until that capability is demonstrated. Generic Kafka observation, destructive queue consumers, trace/metrics querying, continuous Observe, Replay, and causality remain deferred. Existing application transports continue to operate as deployed.

## Consequences

Completion requires attributable staging results, a correctly passing negative scenario, Fail/Unknown controls, repeated isolated runs, and reproducible operator instructions. Missing access or a skipped staging run cannot complete the initiative. No second implementation or paired-result schema is required in this bootstrap.

The same scenario/binding architecture supports later legacy/Keiro comparison. Such parity will require equivalent logical inputs, compatible scenario identities, two actual implementation results, and its own comparison acceptance. A staging Pass establishes the named expectations for the recorded deployment/window; it does not establish migration parity, production safety, or platform cutover readiness.

Revision 2026-10-01: supersede the initial local-pair gate with the user's existing Kubernetes staging target and add explicit negative-scenario acceptance.
