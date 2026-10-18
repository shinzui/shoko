# Verify the running staging system with context-owned scenarios

Date: 2026-10-01

Status: Accepted for bootstrap; revised after the user's staging clarification

## Context

[RES-1](../research/initial-specification-requirement-validation.md) identified migration parity as a useful application, and the first plan inferred a requirement to compose local legacy/Keiro stacks. The user clarified that the actual target is a complete system already running in a Kubernetes test namespace and explicitly chose verification of this staging system first. Local paired environments are therefore not bootstrap prerequisites. The existing ADR path remains stable.

The [platform rewrite-gates decision](mori://tan/tan-platform/docs/adr-0002-track-infrastructure-and-observability-as-rewrite-gates) distinguishes declarations from operational evidence. Kenshou's [resolved-identity decision](mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-2) motivates identifying the implementations actually tested. Both apply to staging acceptance without requiring a second deployment.

## Decision

The bootstrap builds the reusable verifier and demonstrates a real positive workflow and a documented negative scenario against the existing staging system. A negative scenario passes when its expected rejection or invariant is observed; separate controls demonstrate Fail and Unknown. Local fixtures test Shōko's library/adapters. CI may launch the same staging command, but is neither a target environment nor required to provision application services. Production execution remains deferred.

Registration completion from an already-qualified agent is the first MVP workflow, selected by the user on 2026-10-18. Its contract must match the deployed system; choosing another workflow requires an explicit scope revision. Record controlled inputs, real public actions, downstream consequences, evidence strength, business-key correlation, external-effect policy, and cleanup/retention. Qualification/admin approval is a precondition of the narrower registration slice. OTP behavior and controlled recipients must be verified in staging; do not assume the local stub is configured or that a completion acknowledgement establishes real account/user writes.

The integration layer records the expected and observed Kubernetes cluster/namespace identity, deployed workload image digests and available source revisions, actual action/evidence endpoints, credential references, and access route. Record identities before and after verification; mismatch, missing identity, or deployment change prevents an accepted Pass while preserving individual workflow evidence. Kubernetes metadata is supplied to generic core types by the host; core does not discover resources or manage workloads.

Selecting a test namespace does not automatically isolate databases, brokers, external providers, or recipients. Match those resources to the explicit staging contract. Use scoped evidence credentials, approved test identities/effects, endpoint allowlists, bounded operations, and run-owned data. Shōko does not deploy, scale, restart, migrate, reset, or remove the application environment. Cleanup covers only owned test records and verifier access resources; unsupported deletion has explicit bounded retention.

The bounded context owns business vocabulary and scenarios beside its domain code, including a small verification host package with an explicit build target and immutable consumed revision. A transport client need not link the service executable or its full runtime dependency graph. Bindings translate domain operations and observations to a selected environment and implementation. Shōko owns the generic HTTP, PostgreSQL, Message DB, and Kiroku adapters; the actual staging binding uses only the stores present. Legacy support stays thin and business-key correlated, without added instrumentation. Use machine-callable REST or PostgreSQL rather than assuming browser-session GraphQL access. Do not assert the nonexistent registration welcome email.

[Keiro IR-52](mori://shinzui/keiro/okf/improvement-requests/concepts/IR-52) owns durable execution-correlation propagation; business-key correlation is sufficient until that capability is demonstrated. Generic Kafka observation, destructive queue consumers, trace/metrics querying, continuous Observe, Replay, and causality remain deferred. Existing application transports continue to operate as deployed.

First use is an earlier release gate than full bootstrap completion. Build HTTP/PostgreSQL and only those event readers required by the accepted workflow’s assertions before staging acceptance. Both generic event readers remain full-bootstrap deliverables. A reader is required when an assertion needs its durable history; unused adapter work must not delay the MVP, and missing coverage must not silently weaken an assertion.

The workflow contract maps stable requirement IDs to scenario/expectation IDs, sources, coverage strength, and selected adapters, and lists untested requirements explicitly. Retained reports identify the deployed rewrite revisions and exact contract digest, so owners can rerun that contract after independently managed deployments using fresh identities and equivalent logical inputs. This is bounded regression evidence, not automatic comparative parity or certification of an entire microservice.

Each scenario run has a distinct artifact directory. Write a schema-validated acceptance envelope last, covering the individual result and before/after target evidence by digest; missing or partial artifacts are not acceptance. A suite summary references separate positive/negative runs and preserves errors, skips, and nonzero outcomes. Controls remain labelled separately. Before/after identity snapshots establish observations at those points; they do not prove uninterrupted deployment stability, so acceptance also uses a deployment-owner stable window and records observed rollout changes.

Readiness includes the actual completion mode, real account/user writes, and a repeatable bounded OTP acquisition path using an existing approved test facility or controlled-recipient automation. A source default or historical staging note does not establish deployed behavior. Missing facilities remain explicit prerequisites with owners.

## Consequences

Completion requires attributable staging results, a correctly passing negative scenario, Fail/Unknown controls, repeated isolated runs, and reproducible operator instructions. Missing access or a skipped staging run cannot complete the initiative. No second implementation or paired-result schema is required in this bootstrap.

The same scenario/binding architecture supports later legacy/Keiro comparison. Such parity will require equivalent logical inputs, compatible scenario identities, two actual implementation results, and its own comparison acceptance. A staging Pass establishes the named expectations for the recorded deployment/window; it does not establish migration parity, production safety, or platform cutover readiness.

Revision 2026-10-01: supersede the initial local-pair gate with the user's existing Kubernetes staging target and add explicit negative-scenario acceptance.

Revision 2026-10-18: fix registration as the MVP target, separate first use from full adapter completion, and define host packaging, rewrite requirement coverage, OTP readiness, and isolated acceptance artifacts.

Implementation clarification, 2026-10-18: generic `check` validates configuration
and binding policy without invoking the host's live metadata callback. Configured
target identity remains an expectation; a live run requires the callback's observed
identity to match it before scenario resources are acquired. Integration owns full
Kubernetes/workload identity, endpoint authorization, and before/after acceptance.
The reusable host and demo process checks establish no staging readiness claim.

Implementation clarification, 2026-10-18: workflow schema validation checks
declarations and their relationships only. It cannot establish endpoint ownership,
deployed identity, available test facilities, or real workflow success. Keep the
synthetic format example separate from the default staging manifest and reject
it for staging commands. Live discovery and independent smoke evidence remain
required even after all declared prerequisites are confirmed.

Implementation clarification, 2026-10-18: the read-only integration identity
check distinguishes controller-template observations from full staging readiness.
It pins an explicitly declared context/server/namespace, compares namespace and
workload UIDs, generations and template digests before/after discovery, and retains
only allowlisted identities with the exact contract digest. A successful explicit
identity-only command still records readiness blocked. Runtime pod image identity,
rollout readiness, endpoint/evidence access, domain test setup and real workflow
outcomes remain live acceptance obligations. Controller templates may use tagged
sidecars: retain their exact template refs separately from required runtime digest
expectations, include init containers, and do not change the deployed system merely
to satisfy the verifier's manifest format. A matching template does not verify its
running digest or pod/controller ownership. Discovery performs no manifest recipe
execution or workload lifecycle operations.
