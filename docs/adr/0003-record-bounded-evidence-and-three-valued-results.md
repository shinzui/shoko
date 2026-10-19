# Record bounded evidence and three-valued results

Date: 2026-10-01

Status: Accepted for bootstrap

## Context

[RES-1](../research/initial-specification-requirement-validation.md) requires finite negative assertions, explicit budgets, negative evidence, and a CI mapping (F4, F5, F8, F9). Repeated polls must not make one event look like several events, and source outages must not prove absence. Kenshou's [protocol decision](mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-3) separates assertion failures from inconclusive checks and owns its own versioned wire contract.

## Decision

The verification verdict is `Pass`, `Fail`, or `Unknown`, with typed reasons and retained evidence. Aggregate completed expectations using definite failure first, then unknown, then pass; retain every child verdict, so failure does not erase unavailable sources. Invalid configuration is a preflight error, not a system-under-test failure. Unexpected runner faults are reported separately from ordinary observation unavailability.

The runner uses a monotonic clock for deadlines and UTC timestamps for reports. A run begins before fixtures and actions; its execution budget bounds resource acquisition, baselines, fixtures, actions, and expectations. Default local/CI values are a 30-second execution budget, a 10-second `eventually` window, and a 100-millisecond poll interval, configurable as positive durations. Every request is bounded by the remaining deadline. Nested `within` windows take the earliest enclosing deadline; they never extend it. Sibling expectations activate together after their required actions and share the remaining run budget. A fake clock makes boundary cases deterministic in tests.

Capture each source's evidence baseline before the triggering fixture/action sequence. Polling starts when an expectation's dependencies are ready, but durable queries include evidence since that baseline, including events produced during the action before the first poll. A binding must distinguish this evidence interval from the expectation's polling interval and record both. History from before the baseline cannot satisfy occurrence expectations for this run.

`eventually` passes on a conclusive matching observation completed at or before its deadline. Its default state-observation contract is sampled: expiry fails when all required scheduled reads were conclusive non-matches, and is unknown when unresolved source gaps prevent that conclusion. The report states this sampled guarantee; it does not assert continuous state history. Durable-event observations can instead establish complete history coverage. `never` covers the evidence interval from its pre-action baseline to its effective deadline, defaulting to the scenario deadline, and fails immediately on a matching witness. It passes only with complete declared coverage of that finite interval. `exactlyOnce` counts distinct occurrence identities over that same kind of bounded evidence interval, waits for its close before passing with one, and fails upon seeing a second distinct occurrence. Zero at a complete close fails; incomplete coverage without a decisive violation is unknown. Observing the same event twice does not increment cardinality.

An observation records what the source returned; an expectation interprets it. Evidence includes declared and observed domain action outcomes, source/binding identity, correlation selection, request or cursor bounds, observation time, occurrence identity when available, and sanitized supporting data. Negative evidence records searched sources, query description, interval, coverage, match count, and gaps. Coverage describes whether an adapter can establish the requested interval. Polling snapshots of mutable rows cannot prove continuous absence between polls; such checks report sampled coverage and cannot satisfy an expectation requiring continuous/durable coverage. An immutable event history or an explicitly supported cumulative domain fact can prove interval cardinality. Never imply causal order from timestamps alone.

Shōko owns a versioned result JSON contract with explicit stable field and tag encodings. Adapt Kenshou's vocabulary conceptually: passed to Pass, failed to Fail, inconclusive/infrastructure problems to Unknown with reasons. Do not depend on its harness or claim wire compatibility. CLI exit codes are 0 for Pass, 1 for Fail, 2 for invalid invocation/configuration/policy rejection, 3 for Unknown (including an unavailable evidence source), and 4 for an unexpected runner fault. Unknown is nonzero in local, staging, and automated runs; CI invokes the same result contract. JSON stdout contains only the result; diagnostics go to stderr. A negative business scenario whose expected rejection and invariants are observed returns Pass/exit 0. Unexpected success or a conclusive mismatch returns Fail/exit 1; transport/source uncertainty cannot count as successful rejection. Document this projection so future catalog integration does not confuse it with Kenshou's infrastructure-failure exit code.

Terminal unexpected or uncertain action outcomes stop subsequent mutations; dependent expectations retain an explicit unavailable-prerequisite reason. Expected typed rejections remain values for negative expectations. Resource finalization has a separate finite cleanup grace budget, default five seconds, and cannot extend execution or restart actions. Record cleanup/disposition separately; failed required cleanup makes an otherwise passing invocation Unknown, while preserving a primary Fail. A contracted retention policy can satisfy disposition without deletion. This bounds execution plus cleanup rather than promising unlimited finalization after cancellation.

Results contain an allowlisted logical-input summary and recipe revision, separate from generated business/run identities. Raw fixture values, OTPs, credentials, and personal payloads are excluded; hashing low-entropy secrets is not redaction. Stable expectation IDs let integration reports map evidence to named business requirements.

Implementation clarification, 2026-10-18: keep the evidence cutoff separate from the request deadline. A final durable-history read may finish after a shorter `within` cutoff while the total execution budget remains; it must establish the requested interval without including later occurrences or inventing future coverage. No evidence read uses cleanup grace. A window consuming the entire execution budget can honestly remain Unknown when closure cannot be established in time. Source adapters own the cursor/visibility proof, including any mapping from the host cutoff to store bounds. Host monotonic times are not automatically comparable to a remote event timestamp.

Bindings receive a finalizer registrar during acquisition so partial acquisitions and later fixtures can register owned resources. Completed release and registered finalizers share one finite grace. Source handlers preserve asynchronous cancellation. Terminal outcomes stop later mutations; action evidence, expectation evidence, cleanup status, and partial unexpected-fault reports remain distinct.

The v1 codec uses explicit `verification`, `runner-fault`, and `preflight-error` envelopes. Public primitive summaries (`PublicChoice`, `PublicCount`, and `PublicFlag`) are deliberately attached to action/observation evidence; typed raw results have no automatic rendering path. Logical-input metadata is validated before acquisition. A versioned fixed-order array of public description fields supplies its SHA-256 identity; scenario revision, binary identity, and logical recipe identity remain separate. The schema and consumer goldens are checked independently from codec round trips.

## Consequences

The first runner implements only `eventually`, `never`, and `exactlyOnce` plus deadline composition. Results honestly distinguish missing observations, source failure, and a proven system defect. Negative guarantees are limited to the reported window and coverage. Capture/replay, performance claims, continuous monitoring, and a shared platform publication protocol are deferred.

Revision 2026-10-01: retain action-outcome evidence and clarify that a correctly rejected negative scenario is Pass, while unavailable evidence remains Unknown in staging and automation.

Revision 2026-10-18: specify terminal action handling, finite cleanup grace/disposition, and sanitized logical-input identity for repeatable rewrite verification.

Implementation clarification, 2026-10-18: SQL snapshots use independent read-only
transactions with server and host deadlines. A column descriptor verifies its
actual PostgreSQL type before Hasql 1.9 decodes bytes, since successful binary
decoding alone can accept an incompatible type. HTTP disables redirects and
automatic connection retries, limits response bytes, and uses response scopes
with zero idle connections. Both adapters report sampled coverage. Secret-bearing
transport errors and payloads have no result rendering path; exact domain
status/body classification remains in the context binding.

Implementation clarification, 2026-10-18: the CLI projects the core result directly
to its stable exits and JSON stdout; persistence errors preserve that primary
report while returning command exit 4. Requested evidence files use a completed
temporary inode plus an exclusive hard link in the destination directory. Existing
files are never replaced, and interruption before publication cannot label a partial
file complete. Additional host redactions only remove named public summary fields;
they cannot enable raw payload rendering.

Invocation failures use a fixed usage diagnostic: optparse's detailed failure
renderer echoes unexpected argument values, which could contain an accidentally
supplied secret. Successful help/version rendering remains detailed. A real
process sentinel test protects this error path alongside Secret resolution.

Event-reader integration, 2026-10-18: a durable `eventually` miss requires a
complete closing history read, using remaining execution time after its cutoff.
Sampled-state behavior remains unchanged. A positive observation completed after
the cutoff cannot Pass; closing source failures remain Unknown. Complete catch-up
can repair gaps only through the finite evidence cutoff, without claiming future
coverage. A request beginning before the cutoff and finishing after it may
contain an older snapshot, so the runner obtains one fresh closing read while
execution time remains. Adapters report visibility only through a conservative
request-start lower bound, capped by the evidence cutoff. A sampled-state
witness obtained after a negative cutoff cannot establish a violation inside
that earlier window; historical witnesses still rely on the source's explicit
interval-membership contract.

The event adapters re-scan the entire bounded source scope under repeatable-read
snapshots and exclude pre-action occurrence IDs. This avoids treating a visible
global high position as a committed prefix. The baseline token refers to run-owned
memory. Matching events first seen after the host cutoff have uncertain membership
in the window: exclude them from the count and return incomplete coverage. Do not
compare host monotonic time with event timestamps to resolve this uncertainty.

Complete-history claims require an explicit source-owner append-only guarantee
for the selected scope and finite run, excluding truncation, rewriting, and
retention. Unverified history supplies witnesses but cannot prove a negative or
accepted exactly-once result. A page cap, missing correlation, decoding error,
disappearing previously seen ID, or source outage cannot establish complete
history. Store-read credentials do not grant application writes, subscription
checkpoints, queue acknowledgements, or migration privileges.

Planned result refinement, 2026-10-19: [ExecPlan 8](../plans/8-compose-verifications-from-reusable-scenario-vocabulary-and-binding-blocks.md)
introduces run-result v2 and a versioned description digest containing public
correlation declarations without their input values. After successful actions,
an unresolved required key makes only dependent expectations
`Unknown/CorrelationLost`; other keyed expectations continue. Terminal action
failures still suppress all expectations. Reports list successfully resolved
correlations in declaration order; descriptions retain every declaration.
Workflow-manifest and identity-artifact schemas retain their independent versions.
This records the planned contract; current v1 behavior remains until implementation.

Correlation-instance refinement, 2026-10-19: the ExecPlan 8 follow-up requires
both declarations and resolved report entries to identify their correlation
instance, independently of the semantic business-key name. Each expectation's
selected instance is part of inspection and the description digest. Two instances
using the same key name may resolve differently; one instance's failure affects
only its dependent expectations. Schema v2 records successful resolutions as
`correlationId`/`resolvedCorrelation` pairs and retains failed declarations and
selections in the description. Selection omission and incompatibility are preflight
errors, never grounds for choosing another instance implicitly.

Typed-boundary refinement, 2026-10-19: ExecPlan 8's identifier and timestamp
newtypes retain existing string and integer-microsecond JSON representations.
The new handler-construction preflight failure contains an operation ID and a
closed, typed cause containing only public identifiers. Input-resolution errors
carry node IDs, never dynamic values or raw transport diagnostics, and map to
the existing runtime reason vocabulary. Unknown cause codes and fields are
rejected by the v2 decoder/schema. Newtypes alone do not change the description
digest or temporal evidence semantics.

Handler implementation revision, 2026-10-19: run-result v2 replaces v1; the decoder
accepts v2 only. Source consistency and typed handler-construction failures have
closed preflight encodings with public identifiers and no transport diagnostics.
Timestamp and identifier wrappers retain integer-microsecond and string encodings.
Workflow manifests and identity artifacts retain their independent versions.

Correlation implementation revision, 2026-10-19: the v2 description digest includes
ordered declarations (instance ID, semantic key, strategy, dependencies) and each
expectation's selected ID. Typed declaration inputs remain private. Reports retain
successful `correlationId`/`resolvedCorrelation` pairs in declaration order and
descriptions retain every declaration. An empty/unresolved instance produces
`Unknown/CorrelationLost` only for its selected expectations; resolved siblings
continue even when they share a semantic key. Terminal action failures retain
`PrerequisiteUnavailable` for all expectations. Policy strategies include unused
declarations.

Completion revision, 2026-10-19: each tagged v2 decoder alternative has its own
closed field inventory, including construction causes and correlation values.
Fields valid under another tag are rejected rather than silently discarded.
Public type probes and internal malformed-reference/handle/digest probes preserve
the typed and private-value boundaries without exposing internal constructors.
The independent host emits schema-valid v2 reports for standalone and composed
workflows; its successful resolutions retain entity-instance attribution.
