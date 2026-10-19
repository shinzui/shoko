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
evidence:
  - kind: "test"
    resource: "shoko-core/test/ScenarioSpec.hs"
    proves: "Definition checks, dependency validation, and stable public inspection."
  - kind: "example"
    resource: "shoko-core/test/Consumer/Account.hs"
    proves: "One typed scenario interpreted by two different storage bindings."
---

# Inspectable typed scenarios

Consumers describe operations in a typed vocabulary and assemble a fixed sequence of fixtures and actions followed by temporal expectations. Named references carry typed outputs into later operations; inspection exposes public identifiers and requirements without running handlers.

## Limits

The scenario structure is fixed before execution. Runtime branching, reusable scenario fragments, and composed vocabulary or binding blocks are future work. Predicates are Haskell functions: authors must advance the scenario revision when their meaning changes. A context owner supplies the actual business operations.

## Use and evidence

See the [core guide](../core.md) and [account consumer](../../shoko-core/test/Consumer/Account.hs).
