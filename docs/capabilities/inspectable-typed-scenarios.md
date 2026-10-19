---
type: "Capability"
title: "Inspectable typed scenarios"
description: "Define typed workflow scenarios and inspect their declared operations, dependencies, outcomes, and expectations without executing them."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
capabilityId: "CAP-1"
provider: "mori://shinzui/shoko"
status: "shipped"
stability: "experimental"
since: "unreleased"
packages:
  - "shoko-core"
interface:
  - "Shoko.scenario"
  - "Shoko.given"
  - "Shoko.act"
  - "Shoko.expect"
  - "Shoko.inspectScenario"
  - "Shoko.Vocabulary"
  - "Shoko.namespace"
  - "Shoko.expectAfterActions"
  - "Shoko.hoistScenarioBuilder"
  - "Shoko.combineBindings"
  - "Shoko.correlate"
  - "Shoko.correlatedBy"
evidence:
  - kind: "test"
    resource: "shoko-core/test/ScenarioSpec.hs"
    proves: "Definition checks, dependency validation, and stable public inspection."
  - kind: "example"
    resource: "shoko-core/test/Consumer/Account.hs"
    proves: "One typed scenario interpreted by two different storage bindings."
  - kind: "example"
    resource: "shoko-cli/test/ConsumerHost/Registration.hs"
    proves: "One reusable workflow used independently and twice inside a namespaced composition with an accounts vocabulary and combined bindings."
---

# Inspectable typed scenarios

Consumers describe operations in a typed vocabulary and assemble a fixed sequence of fixtures and actions followed by temporal expectations. Named references carry typed outputs into later operations; inspection exposes public identifiers and requirements without running handlers.

Reusable `ScenarioBuilder` blocks support lexical namespaces, named predicate composition, and deferred expectation declarations. Vocabulary sums and result-preserving hoists embed existing blocks; `combineBindings` combines component resource lifetimes. Scenario-owned correlation handles distinguish repeated instances of the same semantic business key.

## Limits

The scenario structure is fixed before execution. Runtime branching and per-stage expectation activation remain future work. Every expectation activates after the final action. Predicates are Haskell functions: authors must advance each wrapper’s scenario revision when shared recipe or predicate meaning changes. A context owner supplies the actual business operations.

## Use and evidence

See the [core guide](../core.md) and [account consumer](../../shoko-core/test/Consumer/Account.hs).
