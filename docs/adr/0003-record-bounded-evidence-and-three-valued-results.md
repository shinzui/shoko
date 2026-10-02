# Record bounded evidence and three-valued results

Date: 2026-10-01

Status: Accepted for bootstrap

## Context

[RES-1](../research/initial-specification-requirement-validation.md) requires finite negative assertions, explicit budgets, negative evidence, and a CI mapping (F4, F5, F8, F9). Repeated polls must not make one event look like several events, and source outages must not prove absence. Kenshou's [protocol decision](mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-3) separates assertion failures from inconclusive checks and owns its own versioned wire contract.

## Decision

The verification verdict is `Pass`, `Fail`, or `Unknown`, with typed reasons and retained evidence. Aggregate completed expectations using definite failure first, then unknown, then pass; retain every child verdict, so failure does not erase unavailable sources. Invalid configuration is a preflight error, not a system-under-test failure. Unexpected runner faults are reported separately from ordinary observation unavailability.

The runner uses a monotonic clock for deadlines and UTC timestamps for reports. A run begins before fixtures and actions; its total budget bounds all work. Default local/CI values are a 30-second total budget, a 10-second `eventually` window, and a 100-millisecond poll interval, configurable as positive durations. Every request is bounded by the remaining deadline. Nested `within` windows take the earliest enclosing deadline; they never extend it. Sibling expectations activate together after their required actions and share the remaining run budget. A fake clock makes boundary cases deterministic in tests.

Capture each source's evidence baseline before the triggering fixture/action sequence. Polling starts when an expectation's dependencies are ready, but durable queries include evidence since that baseline, including events produced during the action before the first poll. A binding must distinguish this evidence interval from the expectation's polling interval and record both. History from before the baseline cannot satisfy occurrence expectations for this run.

`eventually` passes on a conclusive matching observation completed at or before its deadline. Its default state-observation contract is sampled: expiry fails when all required scheduled reads were conclusive non-matches, and is unknown when unresolved source gaps prevent that conclusion. The report states this sampled guarantee; it does not assert continuous state history. Durable-event observations can instead establish complete history coverage. `never` covers the evidence interval from its pre-action baseline to its effective deadline, defaulting to the scenario deadline, and fails immediately on a matching witness. It passes only with complete declared coverage of that finite interval. `exactlyOnce` counts distinct occurrence identities over that same kind of bounded evidence interval, waits for its close before passing with one, and fails upon seeing a second distinct occurrence. Zero at a complete close fails; incomplete coverage without a decisive violation is unknown. Observing the same event twice does not increment cardinality.

An observation records what the source returned; an expectation interprets it. Evidence includes source/binding identity, correlation selection, request or cursor bounds, observation time, occurrence identity when available, and sanitized supporting data. Negative evidence records searched sources, query description, interval, coverage, match count, and gaps. Coverage describes whether an adapter can establish the requested interval. Polling snapshots of mutable rows cannot prove continuous absence between polls; such checks report sampled coverage and cannot satisfy an expectation requiring continuous/durable coverage. An immutable event history or an explicitly supported cumulative domain fact can prove interval cardinality. Never imply causal order from timestamps alone.

Shōko owns a versioned result JSON contract with explicit stable field and tag encodings. Adapt Kenshou's vocabulary conceptually: passed to Pass, failed to Fail, inconclusive/infrastructure problems to Unknown with reasons. Do not depend on its harness or claim wire compatibility. CLI exit codes are 0 for Pass, 1 for Fail, 2 for invalid invocation/configuration/policy rejection, 3 for Unknown (including an unavailable evidence source), and 4 for an unexpected runner fault. Unknown is nonzero in local and CI runs. JSON stdout contains only the result; diagnostics go to stderr. Document this projection so future catalog integration does not confuse it with Kenshou's infrastructure-failure exit code.

## Consequences

The first runner implements only `eventually`, `never`, and `exactlyOnce` plus deadline composition. Results honestly distinguish missing observations, source failure, and a proven system defect. Negative guarantees are limited to the reported window and coverage. Capture/replay, performance claims, continuous monitoring, and a shared platform publication protocol are deferred.
