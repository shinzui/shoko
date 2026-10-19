---
okf_version: "0.2"
---

# Shoko terminology

For developers familiar with distributed systems who are new to Shoko. These terms
define the project's current vocabulary, with links to authoritative implementations
and guides. Start with [scenario](scenario.md), [vocabulary](vocabulary.md),
[binding](binding.md), [observation](observation.md), and [expectation](expectation.md).

The [capability catalog](../capabilities/index.md) describes what consumers can adopt.
Here, [capability](capability.md) means a runtime permission grant. Planned Observe,
Replay, production execution, and reusable composition blocks are outside this
current vocabulary catalog.

## Scenario authoring

- [action](action.md) — A scenario operation that may change the system and declares which domain outcomes are acceptable.
- [composite action](composite-action.md) — An action implemented through named substeps declared in its operation description.
- [expectation](expectation.md) — A named requirement that applies a temporal rule to an observation.
- [fixture](fixture.md) — A scenario step that establishes a declared precondition before the workflow actions.
- [input](input.md) — A typed description of a value supplied to an operation, possibly depending on earlier step results.
- [observation](observation.md) — A read-only operation paired with a named predicate for deciding whether returned values match.
- [operation](operation.md) — A typed request that a binding handles as a fixture, action, or observation.
- [reference](reference.md) — An opaque typed handle to the result of an earlier named fixture or action.
- [scenario](scenario.md) — A named, revisioned description of a workflow and its expected observable consequences.
- [vocabulary](vocabulary.md) — The context-owned set of typed operations from which scenarios are written.

## Evidence and temporal assertions

- [AppendOnlyDuringRun](append-only-during-run.md) — The source owner's promise that scoped event history will not be deleted, truncated, or rewritten during the finite run.
- [baseline](baseline.md) — The source boundary captured before fixtures and actions to separate existing evidence from the current run.
- [business key](business-key.md) — A non-secret domain identifier shared by the actions and evidence reads for a workflow.
- [closing read](closing-read.md) — A final history observation that establishes coverage through a fixed evidence cutoff.
- [correlation](correlation.md) — The rule that attributes observed evidence to the business activity being verified.
- [coverage](coverage.md) — A source's claim about the evidence interval it establishes, its strength, and whether it is complete.
- [durable history](durable-history.md) — Evidence that can establish all relevant occurrences over a finite interval when its completeness conditions hold.
- [eventually](eventually.md) — A temporal assertion requiring a matching observation completed within its finite deadline.
- [evidence](evidence.md) — The retained public record of what was observed, where, when, and under which correlation and coverage.
- [evidence source](evidence-source.md) — A named read surface from which a binding obtains observations for a finite run.
- [exactlyOnce](exactly-once.md) — A temporal assertion requiring exactly one distinct matching occurrence in a completely covered bounded interval.
- [execution ID](execution-id.md) — A run identity propagated through the target system and used to select that run's evidence.
- [never](never.md) — A temporal assertion requiring no matching occurrence throughout a bounded evidence interval.
- [occurrence](occurrence.md) — One observed domain value with an optional stable identity used to recognize repeated reads of the same fact.
- [sampled state](sampled-state.md) — Evidence about mutable state at observation samples rather than all changes during an interval.

## Execution and policy

- [binding](binding.md) — The implementation-specific handlers and contracts that give a scenario's operations their runtime meaning.
- [binding contract](binding-contract.md) — The pure declaration of a handler's capability and cleanup requirements.
- [capability](capability.md) — A declared permission category required by an operation or resource lifecycle and granted by an environment.
- [cleanup grace](cleanup-grace.md) — The separate finite period available to release resources and run registered finalizers after execution.
- [disposition](disposition.md) — The recorded outcome of a resource's contracted cleanup or retention.
- [environment](environment.md) — The named target policy that declares permitted capabilities and finite execution limits.
- [evidence cutoff](evidence-cutoff.md) — The fixed end of the interval whose evidence an expectation is allowed to evaluate.
- [execution budget](execution-budget.md) — The finite total time available for acquisition, baselines, scenario operations, and evidence evaluation.
- [policy](policy.md) — The configured permissions and finite timing rules under which a scenario may execute.
- [preflight](preflight.md) — Validation that rejects an invalid definition, policy, binding, or target before scenario resources are acquired.
- [runner](runner.md) — The interpreter that executes a resolved scenario, gathers evidence, evaluates expectations, and attempts resource finalization.
- [synthetic consent](synthetic-consent.md) — Explicit per-run permission to perform operations requiring synthetic-resource creation or use.

## Results and identity

- [description digest](description-digest.md) — The SHA-256 identity of a versioned encoding of a scenario's public description.
- [domain outcome](domain-outcome.md) — The typed result of an action, labelled with a public tag that the scenario can accept or reject.
- [logical input](logical-input.md) — The recipe revision and allowlisted logical parameters that identify a run's test setup without storing raw fixture values.
- [negative scenario](negative-scenario.md) — A scenario that expects a documented rejection or invariant to hold under a specific adverse input or condition.
- [public summary](public-summary.md) — An explicitly selected choice, count, or flag that may be retained in a report.
- [run ID](run-id.md) — The report identity assigned to one Shoko execution.
- [scenario revision](scenario-revision.md) — The author-controlled version of a scenario's predicates and recipe meaning.
- [verdict](verdict.md) — The three-valued conclusion that evidence satisfies, violates, or cannot establish an expectation.

## Compiled hosts

- [registry](registry.md) — The scenario host's inventory of supported environment names and compiled scenario entries.
- [scenario host](scenario-host.md) — A compiled application that registers domain scenarios and bindings and exposes them through Shoko's CLI.

## Staging contracts

- [target identity](target-identity.md) — The observed identity of the deployment a host is about to verify.
- [workflow contract](workflow-contract.md) — The explicit agreement describing a staging workflow's target, requirements, evidence, prerequisites, access, and cleanup or retention.

## Maintenance

The [profile](profile.dhall) selects
[mori://shinzui/okf-profiles/profiles/terminology](mori://shinzui/okf-profiles/profiles/terminology)
at frozen v0.21.0. Keep TERM handles stable, allocate additions with `okf id next`,
and retain this topic grouping when reconciling the index. Tags carry the same
classification for tools. Definitions and anchors describe Shoko's usage; no external
term equivalence or independent verification is asserted.

Run `just check-docs` after edits and record meaningful changes in the [log](log.md).
