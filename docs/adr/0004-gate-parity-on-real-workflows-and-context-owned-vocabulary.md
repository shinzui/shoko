# Gate parity on real workflows and context-owned vocabulary

Date: 2026-10-01

Status: Accepted for bootstrap

## Context

[RES-1](../research/initial-specification-requirement-validation.md), especially S1–S9 and M1–M8, changes the first meaningful milestone from environment portability to a parity run across legacy and Keiro implementations. No composed local pair was demonstrated by the research. Registration includes approval and OTP; the illustrative event chain and welcome email are not a runnable contract.

No Shōko ADR corpus existed before these bootstrap decisions. The platform's [rewrite-gates decision](mori://tan/tan-platform/docs/adr-0002-track-infrastructure-and-observability-as-rewrite-gates) also distinguishes declared infrastructure from observed operational evidence. Kenshou's [resolved-identity decision](mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-2) motivates recording the implementations actually tested rather than their intended labels.

## Decision

The bootstrap builds a reusable verification library and CLI, then proves one real local workflow with the same domain scenario on both implementations. Registration completion from an already-qualified agent is the researched reference slice, using a controlled qualification fixture, OTP, and real downstream account/user creation. The manual source cited by RES-1 recommends this route over the longer self-registration/admin-approval variant. Qualification is a fixture precondition for this slice, not a claim that the run tested admin approval. Select another workflow only after showing that both actual implementations exist and documenting the replacement domain contract in the plans. Do not infer a matching legacy/target pair from the fact that one service uses Keiro.

Before domain integration, record each implementation's immutable source revision, owner, startup and readiness commands, business-key mapping, controlled input identities, dependencies, and approved local substitutes for external side effects. Compose local stacks and demonstrate the business operation through their public entry points. Keep absent rewritten services as explicit upstream prerequisites; Shōko's bootstrap does not include implementing their rewrites. A fixture demonstration proves the verifier, not TAN parity. A skipped or unavailable parity test cannot complete the initiative.

The bounded context owns production vocabulary and scenario packages beside its domain code. Bindings translate domain observations to each implementation's evidence without changing the scenario. Shōko owns generic adapters: PostgreSQL row existence/count/value/absence, HTTP actions and reads, thin Message DB reads, and Kiroku reads. Legacy bindings are disposable, read-mostly, business-key correlated, and add no instrumentation. Use REST or PostgreSQL instead of assuming a machine-callable GraphQL session. Do not assert the nonexistent registration welcome email. Staging OTP, machine access, and production replicas remain later prerequisites.

[Keiro IR-52](mori://shinzui/keiro/okf/improvement-requests/concepts/IR-52) owns durable execution-correlation propagation. It was still proposed at planning time. Business-key correlation permits bootstrap without waiting for it; execution-id correlation and causality claims require separate accepted evidence. Kafka may be needed to run an application's approval/completion path, but a general Kafka observation adapter, destructive PGMQ consumers, Pub/Sub, OpenTelemetry querying, and Prometheus querying are outside this bootstrap. The application fixture can use its existing Kafka producer without adding a generic Shōko Kafka API.

## Consequences

Framework work can proceed while service prerequisites are unresolved. Full completion still requires an actual two-implementation run with retained individual results and a paired summary, including the tested scenario identity, normalized logical inputs, selected correlation strategies, and implementation revisions. Parity proves only the named expectations and bounded evidence windows; it is one migration gate, not proof that the entire platform is ready for cutover.
