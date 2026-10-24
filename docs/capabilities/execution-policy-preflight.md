---
type: "Capability"
title: "Execution policy preflight"
description: "Reject invalid bindings, denied permissions, unsupported correlation, production execution, and missing synthetic consent before acquiring scenario resources."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
capabilityId: "CAP-2"
provider: "mori://shinzui/shoko"
status: "shipped"
stability: "experimental"
since: "unreleased"
packages:
  - "shoko-core"
interface:
  - "Shoko.resolveScenario"
  - "Shoko.Binding"
  - "Shoko.BindingContract"
  - "Shoko.Environment"
  - "Shoko.RunOptions"
requires:
  - "CAP-1"
evidence:
  - kind: "test"
    resource: "shoko-core/test/PolicySpec.hs"
    proves: "Policy denials and missing contracts produce no resource acquisition."
  - kind: "module"
    resource: "shoko-core/src/Shoko/Binding.hs"
    proves: "Pure resolution collects operation, substep, lifecycle, and cleanup requirements."
---

# Execution policy preflight

Resolution combines scenario requirements with the selected binding's declarations and checks the environment's permitted capability set. Synthetic operations also require per-run consent. Concurrent action members require explicit handler opt-in before acquisition. Missing handlers or sources and unsupported correlation fail before scenario resource acquisition.

## Limits

Bindings are trusted Haskell code and must declare their complete effects. This is a declared permission check, not an operating-system sandbox. Production execution is rejected even if grants would otherwise permit it.

## Use and evidence

See [binding and policy construction](../core.md).

## Builds on

- [Inspectable typed scenarios](inspectable-typed-scenarios.md)
