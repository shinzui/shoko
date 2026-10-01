---
type: Research Document
title: Validate the initial Shōko specification before planning
description: Assess whether the initial specification is internally consistent, bounded enough for a first milestone, and feasible against the services it names and the Haskell building blocks available locally.
generated:
  by: process:claude-code
  at: "2026-10-01T03:09:17Z"
researchId: RES-1
status: active
scope: The specification at docs/intial-spec.md as of 2026-09-30 (commit 73efafb plus the author's uncommitted completion, 4272 lines), the tan services its registration example names, and the Haskell libraries registered in the local mori registry. No code was written and no service was run; the author was still completing the specification while this record was produced. The platform-rewrite context was added on 2026-10-01 from the author's statement and the tan-platform modernization notes.
sources:
  - id: spec
    resource: docs/intial-spec.md
    title: Shōko initial specification
    author: human:nadeem
  - id: message-db
    resource: mori://message-db/message-db
    title: Message DB event store, metadata and category retrieval
  - id: research-profile
    resource: mori://shinzui/okf-profiles
    title: okf-profiles research-documents profile v0.19.0
  - id: effectful
    resource: mori://effectful/effectful
    title: effectful 2.7.1.0, dynamic dispatch and parameterised effects
  - id: message-db-hs
    resource: mori://tan/message-db-hs
    title: message-db-hs 0.2.0.0 category retrieval statements
  - id: kiroku
    resource: mori://shinzui/kiroku
    title: kiroku-store 0.9.0.1 read, subscription, and causation APIs
  - id: keiro
    resource: mori://shinzui/keiro
    title: keiro 0.19.0.0 event codec and process manager
  - id: shibuya
    resource: mori://shinzui/shibuya
    title: shibuya-core 0.10.0.0 adapters and acknowledgement semantics
  - id: kenshou
    resource: mori://shinzui/keiro-runtime-kenshou
    title: keiro-runtime-kenshou outcome, verdict, and run-result schemas
  - id: hs-opentelemetry
    resource: mori://iand675/hs-opentelemetry
    title: hs-opentelemetry 1.0.0.0 exporters and propagators
  - id: gogol
    resource: mori://brendanhay/gogol
    title: gogol 1.0 Cloud Trace, Pub/Sub, Monitoring, and Storage bindings
  - id: hedgehog
    resource: mori://hedgehogqa/haskell-hedgehog
    title: hedgehog 1.7 property monad and state-machine testing
  - id: tasty
    resource: mori://UnkindPartition/tasty
    title: tasty 1.5.4 test outcome model
  - id: hurl-workbench
    resource: mori://shinzui/hurl-workbench
    title: hurl-workbench run model
  - id: rs2
    resource: mori://tan/registration-service-v2
    title: registration-service-v2 events, streams, message metadata, observability, smoke stack, and staging validation plan
  - id: as2
    resource: mori://tan/account-service-v2
    title: account-service-v2 account and user events, read schema, and tracer configuration
  - id: mls2
    resource: mori://tan/mls-service-v2
    title: mls-service-v2 agent qualification events, lookup route, and Kafka publisher
  - id: nh
    resource: mori://tan/notification-hub
    title: notification-hub intake, acceptance stub, and recipient allowlist
  - id: ags
    resource: mori://tan/admin-graphql-server
    title: admin-graphql-server schema, clients, and session authentication
  - id: standards
    resource: mori://tan/haskell-service-standardization
    title: tan Haskell service standards, event sourcing and testing documents
  - id: tan-platform
    resource: mori://tan/tan-platform
    title: TAN platform modernization coverage and pilot retrospective
reviews:
  - kind: model
    reviewer: claude-code
    reviewed_at: "2026-10-01T03:09:17Z"
    document_timestamp: "2026-10-01T03:09:17Z"
    scope: content-and-metadata
    outcome: commented
    provider: Anthropic
    model: claude-fable-5-1
    effort: high
    context: >-
      Author self-review against the specification text, the Message DB documentation, and the survey reports gathered from the registered tan services and Haskell libraries; independent human review is pending and the specification was still being edited. Extended on 2026-10-01 with the platform-rewrite context and the matching specification sections.
---

# Validate the initial Shōko specification before planning

Evidence checked: 2026-09-30. This record assesses the specification as a requirement to plan from. It selects no design and writes no code.

## Question and boundary

Is the initial specification[^spec] a valid requirement to start planning against? Three sub-questions are answered:

1. Is the document internally consistent, and is its first milestone bounded?
2. Does its motivating example match the real services it names, so that the first milestone has a concrete target?
3. Do the Haskell building blocks it assumes exist in the local corpus, and where are the gaps?

Out of scope: team capacity, cost, performance targets, and any evaluation of competing tools beyond what the specification itself cites.

## Verdict

The requirement is valid to plan from. The central proposition is coherent: scenarios name the evidence that constitutes correct behavior, environment interpreters decide how that evidence is obtained, and results are three-valued so an unreachable evidence source is never reported as a system failure. The Initial Implementation Recommendation bounds the first milestone well: seven core concepts, three temporal operators, three adapters, one real workflow.

The motivating example, however, does not match the services as they are. The event names are approximations and the flow has human approval and OTP steps in it (S1), no correlation propagates across services (S2), Pub/Sub is not on the path (S3), GraphQL cannot be called by a machine (S5), and there is no email in the flow (S6). None of this invalidates the requirement, but the first scenario must be rewritten against the real registration flow, and Phase 1 must carry service-side prerequisites rather than assume them.

Four things must be settled before an ExecPlan is written. First, the document needs the hygiene fix in F1. Second, the DSL surface has to be made canonical (F3), because the examples currently disagree with each other. Third, correlation is a requirement on the system under test rather than on Shōko (F7), and in Phase 1 the only key the services share is `registrationId` (S2). Fourth, the first scenario has to be the real flow, with the staging OTP step and the staging read path resolved (S1, S5, S7).

The author then clarified that Shōko is the core verification tool for rewriting the TAN services onto keiro-runtime, and afterwards for feature development on the rewritten services. That reframes the first milestone as a parity run of one scenario against the legacy and keiro implementations, moves the primary evidence source to kiroku, and keeps legacy support thin and disposable. The rewrite findings below carry the detail.

## Findings on the document itself

**F1. A large block is duplicated.** Every section from "Suggested Package Structure" through "Open Questions" appears twice, at lines 1072 to 2196 and again at lines 2373 to 3780. The second copy is a revision of the first: it adds the ordering-versus-causation distinction, the four replay strategies, the evidence-persistence question, the observation-versus-expectation boundary, and the nondeterminism question. The first copy should be deleted and the second kept. The "first milestone" diagram at lines 1050 to 1063 is likewise a truncated copy immediately followed by the complete one. The filename misspells "initial". Resolved on 2026-10-01: the first copy and the truncated diagram header were removed, and the Long-Term Vision, Desired Properties, and Non-Goals sections that sat between the copies were placed after the revised Open Questions, where the first copy had them. The filename is unchanged.

## Findings on internal consistency

**F2. Two safety models coexist.** The Production Safety section puts a linear `Safety` rank on actions at the type level. The later Safety as Capabilities, Dry Run, and Configuration sections use a capability set with subset inclusion. The dry-run output and the YAML policy already speak capabilities, and a linear rank cannot express an action that is synthetic and also sends an external request. Recommendation: adopt the capability set from Phase 1 at the value level, drop the rank, and defer type-level enforcement as the Open Questions section already suggests.

**F3. The DSL surface is not canonical.** Examples disagree on whether an action is written bare or under `when`, whether `occurred` sits inside `expect` or at the top level, whether `scenario` takes one argument or an identifier plus a title, and whether the temporal operator is `consistently` or `consistentlyFor`. The "Initial DSL" list names `state`, which no example uses. The Full Registration Scenario example is the most complete form and should become the canonical shape. Separately, `when` collides with the function of the same name in the standard monad module that nearly every Haskell module imports, so the keyword will need qualification everywhere or a different name.

**F4. `never` has no window.** In a finite run, `never P` can only mean "P was not observed during the observation window", and the specification never says what that window is. Define it as a consistency check over a window that defaults to the scenario's total budget, and state that a passing `never` is only as strong as its window. Under the three-valued model an unreachable source makes `never` Unknown, not Pass.

**F5. The default `eventually` budget and polling policy are unspecified.** The `explain` output shows an "Estimated timeout" without saying how it is derived. Define a per-environment default `within` in configuration, and the composition rule for nested windows under concurrent expectations.

**F6. Observe-mode binding is undefined.** `observe @RegistrationSubmitted` yields a value whose downstream observations must be bound by the application's own correlation key, since no Shōko execution id exists. The specification says existing correlation ids should be reused "whenever possible" but does not state the binding rule. The `CorrelationLost` failure class already exists and is the right place to report a missing key.

**F7. Correlation propagation is a requirement on the system under test.** For `x-shoko-execution-id` to appear in event metadata, spans, logs, and message attributes, every service in the workflow must copy it forward. That is a change to the services, not to Shōko, and the specification should say so as an explicit compatibility contract. Two existing channels reduce the burden: W3C trace context is already propagated by any OpenTelemetry-instrumented service, and Message DB carries a native correlation stream name in message metadata and can retrieve a category filtered by it[^message-db]. The survey of the target services below reports which of these the services actually provide.

**F8. Unknown results have no CI mapping.** The three-valued model is right, but the specification does not say how Unknown maps to an exit status. Recommendation: Unknown fails local and CI runs with its own exit code, since those environments own their infrastructure, and is reported as its own state in staging and production.

**F9. Negative evidence is not modelled.** `Evidence a` records things that were found. Passing and failing `never` and `exactlyOnce` checks need a record of which sources were searched over which window and how many matches were found, otherwise a failure cannot show what was checked.

**F10. Environment is a closed enumeration.** `Local | CI | Staging | Production` conflicts with the YAML example, where environments are named configuration, and with the adapter tables, where Local and CI are identical. Environment should be a configuration value carrying a policy, with fail-closed behavior attached to a policy flag rather than to a constructor.

**F11. The application layer is missing from the package structure.** `occurred @RegistrationSubmitted agent` needs a typed event vocabulary and domain observations for the target system. The specification mentions "application-specific packages" but the seven-package layout has none, so the first milestone cannot be reached from the listed packages alone. Decide where scenarios live, in the service repository or in a central one. Portability argues for keeping the domain vocabulary beside the domain.

**F12. Synthetic production access is both permitted by default and opt-in.** The capability table marks Synthetic as permitted in production, while Phase 2 and the Initial Scope require explicit opt-in. Reconcile by making Synthetic a per-run opt-in on top of the policy.

**F13. The timeline baseline is undefined in Observe mode.** Offsets such as "+18ms" are relative to the action start in Run mode. In Observe mode there is no action, so the baseline should be the recorded time of the triggering event, with clock skew between the event store and the runner acknowledged.

**F14. Replay is resolved in the revised copy.** The first copy conflates re-verifying captured evidence with re-executing captured inputs. The revised copy separates four strategies and limits Phase 5 to evidence replay, which is the right first scope. Fixing F1 removes the conflict.

**F15. The scope is large but the first milestone is bounded.** Six phases and nine adapters are a multi-year surface, but the Initial Implementation Recommendation restricts the first milestone to three adapters and three operators, and the Development Strategy requires every abstraction to be justified by more than one concrete scenario. The remaining risk is starting with seven Cabal packages on day one; the plan can decide whether to begin with fewer.

## Findings against the target services

The registration example names real services, and the three core ones, registration-service-v2, account-service-v2, and mls-service-v2, are all event-sourced on Message DB through message-db-hs, so the first milestone has a concrete target. The example's details diverge from the services in ways that change the first scenario.

**S1. The event vocabulary is an approximation, and the flow is not linear.** The real flow is a two-phase, human-in-the-loop process on one `registration` stream. `RegistrationSubmitted` corresponds to `MembershipRequestSubmitted` for self-registration or `RegistrationStarted` for the completion form. `AccountCreated` and `UserCreated` are real and are written by account-service-v2 in its `account` and `user` categories, and registration-service-v2 records its own `AccountCreated` as well. `QualificationRequested` does not exist; the nearest facts are `QaReservationRequested` and the `mls_lookup` queue job. `AgentQualified` exists in mls-service-v2, but it is a per-chapter MLS transaction-volume qualification computed from feeds, not a response to a registration. The registration-side "qualified" fact is `ApprovalReceived` followed by `QualifiedAgentVerified`. Between submission and completion sit an admin approval step and an OTP step that needs a real code or the stub flag. The first scenario must be written against this vocabulary, and `expectFlow` as drawn in the specification cannot be satisfied as a straight chain.[^rs2][^as2][^mls2]

**S2. No cross-service correlation exists today.** Every API-originated write sets `correlationId` to the message's own id and `causationId` to null. Process managers set causation to the triggering message within a service, and Kafka consumers start fresh roots. No request-id or correlation header exists in tan-commons or in the service standards. The only header that propagates is W3C `traceparent`, which registration-service-v2 and mls-service-v2 extract and inject; propagators default to trace context plus baggage, so a baggage entry would transit HTTP hops, but nothing writes baggage or trace ids into event metadata, and message-db-hs's `otelHeaders` metadata support is unused by every service. The durable cross-service key that does exist is the business id `registrationId`: it is in the stream name, in every registration event, in the `tan.registration.id` span attribute, in account-service-v2's idempotency ledger, and in the Kafka payload. Consequence for F7: Phase 1 should correlate on `registrationId` and treat the execution id as a Shōko-side label, and the execution-id-in-metadata contract becomes a service-side improvement request, with `otelHeaders` or baggage as the cheapest landing place.[^rs2][^message-db-hs][^standards]

**S3. The transport is Message DB subscriptions, PGMQ, HTTP, and Kafka; Pub/Sub is not on the path.** The "qualification worker" is registration-service-v2's own pgmq-worker, which calls mls-service-v2 over HTTP. Admin approval returns through a Kafka topic. Completion calls account-service-v2, auth-service, and the legacy account service over HTTP, then publishes `RegistrationCompleted` to Kafka, which mls-service-v2 consumes. The Go qualified-agent service publishes to Pub/Sub but is outside this flow. Adapter priority should therefore be Message DB, PostgreSQL, and HTTP, then Kafka and PGMQ, with `shoko-pubsub` deferred.[^rs2][^mls2]

**S4. Observability is partial.** registration-service-v2 and mls-service-v2 are instrumented with hs-opentelemetry and tag spans with `tan.registration.id`. Local development uses otel-desktop-viewer, staging names SigNoz, and no production backend is fixed. account-service-v2 ships a no-op tracer provider, so the account step is invisible to traces, and the PGMQ hop breaks the trace. The specification's "qualification-worker executed" trace assertion is therefore only partly available, which reinforces deferring the OpenTelemetry adapter.[^rs2][^as2]

**S5. Read models exist, but GraphQL is not machine-callable.** Each service has a read schema (`registration_service_read`, `account_service_read`, `mls_service_read`), and registration-service-v2's read endpoint accepts a `minPosition` floor for read-your-writes. admin-graphql-server exposes registrations and accounts but requires a browser session cookie, forwards no headers, and has no service-account path, so the specification's "Staging → GraphQL API" interpreter is unavailable without a change to that server. Staging observations should use the services' REST read endpoints or PostgreSQL.[^ags][^rs2]

**S6. There is no welcome email, and no email at all, in the registration flow.** registration-service-v2 has a placeholder for a notification-hub publisher, and its open questions resolve the welcome email as an account-service-v2 `MemberInvited` event that does not exist in that service's event list. notification-hub provides a loopback acceptance stub and a recipient allowlist defaulting to `accepted@example.test`, which is the ready-made fake email adapter once a publisher exists. The only real outbound contact today is OTP via Twilio, gated by a stub flag and an allowlist. `welcomeEmailRequested` must leave the first scenario.[^rs2][^nh]

**S7. No cross-service test environment or suite exists.** Each service has a single-service smoke stack built on process-compose and Hurl with polling, with downstreams stubbed through environment flags, and CI is a Nix build only. The closest artifact to the specification's scenario is a manual staging validation plan with per-service SQL assertions against `message_store.messages` and `account_service_read.accounts`. That plan is the concrete first scenario, and the stub flags define what the Local and CI interpreters are. The plan also records that staging OTP is real Twilio, which is a prerequisite to solve before the staging leg of the first milestone.[^rs2][^as2]

**S8. No synthetic-identity concept exists.** Staging reads real MLS data, so a "unique agent" cannot be invented freely: the MLS member id must resolve. mls-service-v2 offers an endpoint to mint a test qualified agent with a controlled email, and the OTP and recipient allowlists are the nearest blast-radius controls. Phase 2's synthetic resources depend on service-side work.[^mls2][^rs2]

**S9. No production read replicas or read-only event-store replica were found.** The production rows in the specification's adapter tables have no backing today.

The services also provide things the specification does not use: the `minPosition` floor as a cheaper alternative to polling for `eventually`; `registrationId` as the correlation key; Kafka envelope headers for correlation id, trace parent, source service, and event type; message-db-hs `otelHeaders` with consumer-side span links; notification-hub's acceptance stub; and the staging validation plan as the first scenario.

Not determined: the production tracing backend, whether `MemberInvited` exists anywhere, literal Pub/Sub topic names, and staging read-replica availability.

## Findings against available building blocks

A survey of the local mori registry, at the versions checked out on 2026-09-30, gives the following picture. Only libraries present in the local corpus were considered.

**Ready to use.**

- **Interpreter foundation.** effectful 2.7.1.0 provides exactly the pattern the specification needs: one effect GADT, with the interpreter chosen at runtime. A phantom safety index on an effect is idiomatic, with the library's own `Labeled` effect as precedent. A production interpreter that provides no handler for a destructive index makes an unsafe scenario fail to typecheck. The cost is type applications or the effectful plugin, and one handler per index.[^effectful]
- **PostgreSQL and HTTP.** hasql 1.10.3.5 covers PostgreSQL observations. http-client 0.7.19 and servant-client 0.20.3.0 cover HTTP actions and header propagation. hurl-workbench shells out to the hurl binary with no header-injection hook, so it is a weak fit for `shoko-http`.[^hurl-workbench]
- **Message DB observations.** message-db-hs 0.2.0.0 exposes category retrieval with every Message DB parameter, including `correlation` and `condition`. One constraint shapes the correlation design: Message DB's `correlation` parameter filters on the *category* of `correlationStreamName`, never on a full stream name. A per-execution id therefore cannot be selected server-side. Shōko must either write `correlationStreamName` as `shoko-<executionId>` and filter client-side within the `shoko` category, or use `condition`, which requires `sql_condition` to be enabled on the server.[^message-db-hs][^message-db]
- **kiroku-backed systems.** kiroku-store 0.9.0.1 carries typed `correlationId` and `causationId`, offers lookup by correlation and by causation descendants, and provides category subscriptions with event-type filters whose checkpoints belong to the observer. That is a complete evidence source for `eventOccurred`, for `P causes Q`, and for Observe mode on kiroku systems. The caveat is that keiro 0.19.0.0's event encoder hard-codes both ids to `Nothing`, so keiro-based services do not populate them yet.[^kiroku][^keiro]
- **Structured results.** keiro-runtime-kenshou already models an outcome type with `Passed`, `Failed`, `Errored`, `Inconclusive`, and `InfrastructureFailure`, plus a verdict record with counterexamples and replay seeds, published as versioned JSON schemas. It is the nearest existing shape to the specification's three-valued result and failure classes and is worth adapting rather than reinventing.[^kenshou]
- **Property-based and runner integration.** hedgehog 1.7's `PropertyT IO` with `evalIO` can run a scenario under `forAll`; shrinking re-runs the IO scenario per candidate, so scenarios must be idempotent and cheap. tasty 1.5.4's outcome type is binary, so Unknown has to be projected onto it or reported through a custom reporter.[^hedgehog][^tasty]
- **Observe-mode consumers.** shibuya's Message DB and Kafka adapters are safe side-car consumers because they advance only their own checkpoint. The pgmq adapter deletes on acknowledgement and must never be used as an observer. keiro's process manager and router always dispatch commands and are not watch-only.[^shibuya]

**Absent from the local corpus.**

- **Trace querying.** hs-opentelemetry 1.0.0.0 is export-only. Its in-memory exporter allows in-process read-back, which serves Local and CI but nothing remote. gogol-cloudtrace is write-only. A staging or production `shoko-opentelemetry` adapter needs a Tempo, Jaeger, or Cloud Trace HTTP client written from scratch. There is also no baggage-to-span-attribute processor, so an execution id reaches spans only where a service records it.[^hs-opentelemetry][^gogol]
- **Prometheus querying.** No PromQL client exists locally. gogol-monitoring's time series listing covers GCP only.
- **Email sandbox inspection.** Nothing.
- **Pub/Sub inspection.** Only gogol-pubsub's raw pull and seek calls. The tan-gcp wrapper is publish-only.
- **Temporal operators and a scenario DSL.** Nothing. keiro's own research records a Given/When/Then DSL as a known gap, and hedgehog's state-machine `Ensure` callbacks are the nearest analogue. `eventually`, `never`, `consistentlyFor`, `within`, and `causes` must be written from scratch as polling, a deadline, and evidence accumulation.

| Specification requirement | Local building block | Gap or risk |
| --- | --- | --- |
| Action and Observation effects with environment interpreters | effectful `interpret` and `reinterpret` | None |
| Type-level safety index | effectful parameterised effects | One handler per index; type applications |
| Scenario DSL, Given/When/Then | None | Write; keep an inspectable GADT over effectful |
| Correlation id into events | kiroku typed ids; Message DB `correlationStreamName` | keiro encodes `Nothing`; Message DB filters by category only |
| `eventOccurred` on Message DB | message-db-hs category retrieval; shibuya Message DB adapter | Client-side filter per execution, or server `sql_condition` |
| `eventOccurred` and causation on kiroku | kiroku read, subscribe, and causation queries | None significant |
| PostgreSQL observations | hasql | None |
| HTTP actions and header propagation | http-client, servant-client | None |
| Trace queries in staging or production | None | New backend client |
| Trace assertions in Local and CI | hs-opentelemetry in-memory exporter | In-process only |
| Prometheus queries | None | New PromQL client |
| Pub/Sub inspection | gogol-pubsub raw pull | Unwrapped |
| Email sandbox | None | Needs a Mailpit-style client |
| Object storage | s3-effectful, gogol-storage | Thin, unvetted |
| Structured three-valued results | kenshou outcome and verdict | Adapt; tasty outcome is binary |
| Temporal operators | None | Hand-roll |
| Hedgehog integration | `PropertyT IO`, tasty-hedgehog | Idempotence under shrinking |

Consequence for the Initial Scope: every one of its ten items has a local building block, and the from-scratch work is confined to the DSL, the temporal operators, and the result model. The adapters the Initial Implementation Recommendation defers, OpenTelemetry and Prometheus, are exactly the ones with no local client, which supports the recommended ordering.

## Findings in the light of the platform rewrite

After this record was first produced, the author stated that Shōko is the core verification tool for rewriting the TAN services onto keiro-runtime, and afterwards for developing features in the keiro-runtime services and their bounded contexts. The modernization notes in tan-platform confirm the target: a Haskell backend on Keiro and Kiroku, Kafka integration events, a GraphQL gateway exception, and OpenTelemetry gates. notification-hub already meets that target and mls-service-v2 is flagged for event-store migration off message-db-hs.[^tan-platform] The services surveyed above are therefore the legacy side, and the findings shift as follows.

**M1. The thesis gets stronger and the first milestone changes.** "Same scenario, different interpreters" is a migration verifier once implementation is a third interpreter axis beside environment and mode. The same scenario bound to legacy adapters and to keiro adapters, passing on both, is behavioral parity for that workflow. That is a sharper first milestone than local versus staging, and it is what the rewrite needs.

**M2. The primary evidence source improves.** kiroku's typed correlation and causation ids, lookup by correlation, causation descendants, and observer-owned subscriptions back `eventOccurred`, `P causes Q`, and Observe mode completely. keiro's codec writing `Nothing` for both ids, while its roadmap claims correlation metadata on process-manager commands, is now a blocker for the rewrite's testability rather than a nicety. It is raised as [IR-52](mori://shinzui/keiro/okf/improvement-requests/concepts/IR-52).[^keiro]

**M3. Legacy support is required but should stay read-mostly, and for non-Haskell services it is a generic PostgreSQL verifier.** The author notes that some legacy services are not Haskell, which the tan-platform pilot confirms: the qualified-agent service is Go and gRPC, and auth-service and client-service are Node. For those the database is the only evidence, so a generic PostgreSQL verifier with row-exists, row-count, column-value, and row-absent observations, parameterized by schema, table, and predicate, is the whole legacy binding. The Haskell legacy services may add message-db-hs, http-client against REST, and Kafka on the existing topics where they exist. `registrationId` stays the key, and the only legacy-side change is a stubbed or allowlisted OTP in staging. Recommendation 5 below is re-targeted accordingly: correlation propagation, a real tracer, and machine-callable read access are requirements on the keiro rewrite, not changes to the legacy services. Legacy bindings are disposable at cutover.

**M4. Parity scenarios must use the domain layer only.** The legacy vocabulary is `MembershipRequestSubmitted`, `ApprovalReceived`, and `QualifiedAgentVerified`, and the rewrite will rename those, so `occurred @AccountCreated` is coupled to one implementation. Domain observations are the parity contract, and event-level assertions stay in implementation-specific invariant scenarios. This settles the specification's open question on domain-specific versus generic observations and sharpens F3 and F11: the vocabulary package is owned by the bounded context.

**M5. Correlation becomes two-mode by necessity.** Legacy correlates on a business key and keiro on an execution id once it is threaded through. The core should model an explicit correlation strategy, with the runner choosing the strongest one a binding supports, rather than assume a header lands everywhere.

**M6. Replay moves earlier.** Capturing legacy executions and replaying their inputs against a keiro stack gives a regression suite for the rewrite built from real traffic. That makes input replay valuable by Phase 2 or 3 rather than Phase 5, and raises the stakes on a store-neutral evidence model.

**M7. Kafka moves up and Pub/Sub stays deferred.** Both sides use Kafka for approval and completion, and it is the target integration transport.

**M8. Three new risks.** No composed local environment exists even for the legacy services, and a parity harness needs legacy and keiro stacks side by side. Vocabulary divergence can push parity scenarios to the lowest common denominator unless the bounded context owns the vocabulary. The first scenario depends on which workflow lands on keiro first; if registration is late in the rewrite order, a notification flow may be the first honest parity target.

The specification gained sections on the rewrite, the implementation axis, parity scenarios, the legacy support policy, correlation strategies, migration verification modes, keiro-native verification, and revised milestones on 2026-10-01 in response to these findings.

## Requirement validation per Initial Scope item


| Initial Scope item | Status | Depends on |
| --- | --- | --- |
| 1. Scenario definition | Needs a decision | Canonical DSL surface (F3); no local DSL to reuse, so written over effectful |
| 2. Actions | Ready | http-client or servant-client against registration-service-v2 REST; OTP stub flag in Local and CI (S7) |
| 3. Observations | Ready | hasql and message-db-hs; REST read endpoints in staging instead of GraphQL (S5) |
| 4. Environment-specific interpreters | Needs a decision | Environment as configuration (F10); implementation as a third axis (M1); Local and CI defined by the existing stub flags (S7); staging OTP (S7) |
| 5. Correlation IDs | Needs a prerequisite | Business-key strategy on legacy, keyed by `registrationId` (S2, M5); execution-id strategy on keiro once keiro threads correlation ids (M2) |
| 6. MessageDB observations | Ready with a constraint | Category-level correlation filter or `sql_condition`; the real event vocabulary (S1) |
| 7. PostgreSQL observations | Ready | hasql against the per-service read schemas (S5); the generic verifier is the entire legacy binding for non-Haskell services (M3) |
| 8. HTTP actions | Ready | http-client with `traceparent` injection (S2) |
| 9. Eventual assertions | Written from scratch | No local temporal operators; `never` window and budgets (F4, F5); `minPosition` floor available (S5) |
| 10. Structured verification results | Adapted | kenshou outcome and verdict shapes; Unknown exit mapping (F8) |

The first milestone is now a parity run: the same scenario passing against the legacy local stack and the keiro local stack (M1). It is feasible once the scenario is written on the domain layer against the real flow (S1, M4) and both composed local environments exist (M8). The staging leg still needs the REST or PostgreSQL read path (S5) and a stubbed or allowlisted OTP step (S7). The milestone diagram's production column has no backing yet (S9) and should be read as a later goal.

## Recommendations before planning

1. Apply F1 and commit the specification so later records can cite stable line numbers. Done on 2026-10-01; line numbers cited in F1 refer to the working copy before the cleanup.
2. Record the following as architecture decisions before the Phase 1 ExecPlan: the capability model (F2), the canonical DSL surface and the `when` naming (F3), temporal semantics including the `never` window and the Unknown exit mapping (F4, F5, F8), the correlation strategy and the compatibility contract on services (F7), environment as configuration (F10), and where application vocabularies live (F11).
3. Rewrite the specification's registration example against the real vocabulary and flow in S1, or mark it as illustrative, so the first scenario is not planned against events that do not exist.
4. Write the Phase 1 ExecPlan against the registration workflow only, taking the staging validation plan as the first scenario (S7), correlating on `registrationId` (S2), and reading staging state through REST or PostgreSQL (S5).
5. Place the requirements Shōko cannot meet itself on the keiro rewrite rather than on the legacy services: keiro must thread an inbound correlation id into every event and dispatched command (M2, raised as [IR-52](mori://shinzui/keiro/okf/improvement-requests/concepts/IR-52)), keiro services must export traces and offer machine-callable read access (S4, S5), and the legacy services get only the stubbed or allowlisted OTP path that staging runs need (S7, M3).
6. Order adapters as Message DB, PostgreSQL, HTTP, then Kafka and PGMQ, and defer Pub/Sub, OpenTelemetry, and Prometheus, which have neither a place in the flow nor a local client (S3, library findings).
7. Build the composed local environments for the legacy registration services and for the keiro implementation as the first ExecPlan prerequisite, since a parity run cannot happen without both (M8).
8. Choose the first parity workflow by rewrite order rather than by the specification's example, and keep parity scenarios on the domain layer with the vocabulary owned by the bounded context (M4, M8).

## Open items

- The author was still completing the specification when this record was produced. Findings reference the 4272-line working copy and should be re-checked once it is committed.
- Independent review of this record is pending; the `reviews` entry above is an author self-review and is deliberately not mirrored into `verified`.

[^spec]: The Shōko initial specification, read in full on 2026-09-30 in its uncommitted working state.
[^message-db]: Message DB documents `correlationStreamName` in message metadata and a `correlation` parameter on category retrieval.
[^research-profile]: This record is governed by the research-documents profile pinned at okf-profiles v0.19.0.
[^effectful]: effectful 2.7.1.0, dynamic dispatch module and the `Labeled` effect as precedent for an indexed effect.
[^hurl-workbench]: hurl-workbench runs the hurl binary through typed-process with an allowlist of arguments and no header-injection hook.
[^message-db-hs]: message-db-hs 0.2.0.0 category retrieval statement, which exposes `correlation`, `condition`, and consumer-group parameters.
[^kiroku]: kiroku-store 0.9.0.1 read, causation, and subscription modules.
[^keiro]: keiro 0.19.0.0 event codec in keiro-core, which writes `Nothing` for both correlation and causation ids.
[^kenshou]: keiro-runtime-kenshou outcome and verdict types and their versioned JSON schemas.
[^hedgehog]: hedgehog 1.7 property monad, `evalIO`, and the state-machine command API.
[^tasty]: tasty 1.5.4 core result and outcome types.
[^shibuya]: shibuya-core adapter and acknowledgement types, with the Message DB, Kafka, and pgmq adapters.
[^hs-opentelemetry]: hs-opentelemetry 1.0.0.0 span exporter interface, in-memory exporter, and propagator API.
[^gogol]: gogol 1.0 generated bindings for Cloud Trace batch write, Pub/Sub pull and seek, Monitoring time series, and Storage objects.
[^rs2]: registration-service-v2: `Registration/Event.hs` for the event vocabulary, `Registration/MessageWrite.hs` for metadata, `App/Server.hs` and `Observability.hs` for trace propagation, `MlsLookup/` and `Registration/CompletionProcess.hs` for transport, `Justfile` and `smoke/` for the local stack, and `docs/plans/2026-07-17-flow-2-staging-validation-plan.md` for the staging plan.
[^as2]: account-service-v2: `Domain/Account/AccountEvent.hs`, `Domain/User/UserEvent.hs`, `Api/Effectful.hs` for account creation, and `app/AccountService/Cli.hs` for the no-op tracer provider.
[^mls2]: mls-service-v2: `Domain/AgentQualification/AgentQualificationEvent.hs`, `Api/QualifiedAgentRoutes.hs`, `Subscription/QualifiedAgentKafkaPublisher.hs`, and `Kafka/RegistrationCompleted/Inbound.hs`.
[^nh]: notification-hub: `App/Config.hs` for the recipient allowlist and the acceptance stub, and the delivery worker that enforces it.
[^ags]: admin-graphql-server: `schema.graphql`, `src/clients/index.ts`, and `index.ts` for session authentication.
[^standards]: tan Haskell service standards: the event-sourcing standard for stream naming, and the absence of any correlation header convention in the standards and in tan-commons.
[^tan-platform]: tan-platform `docs/generated/platform-modernization.md` and `docs/assessments/pilot-retrospective.md`, which set the Keiro and Kiroku backend target and record the per-service migration assessments.
