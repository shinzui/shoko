---
type: "Capability"
title: "Compiled scenario CLI hosts"
description: "Embed typed scenarios in a compiled CLI with inspection, policy checks, strict layered configuration, classified exits, and atomic JSON report output."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
capabilityId: "CAP-8"
provider: "mori://shinzui/shoko"
status: "shipped"
stability: "experimental"
since: "unreleased"
packages:
  - "shoko-cli"
interface:
  - "Shoko.Cli.runShokoCli"
  - "Shoko.Cli.executeCli"
  - "Shoko.Cli.Registry"
  - "list"
  - "explain"
  - "check"
  - "run"
  - "--output PATH"
requires:
  - "CAP-1"
  - "CAP-2"
  - "CAP-3"
  - "CAP-4"
evidence:
  - kind: "example"
    resource: "shoko-cli/test/ConsumerHost/Main.hs"
    proves: "An independently compiled domain host and binding registry."
  - kind: "test"
    resource: "shoko-cli/test/UnitMain.hs"
    proves: "CLI host unit checks."
  - kind: "test"
    resource: "scripts/test-cli"
    proves: "Process checks for configuration, credentials, exits, output, and concurrent no-clobber persistence."
---

# Compiled scenario CLI hosts

A host registers compiled scenarios, pure binding factories, credential references, safe logical inputs, and a live metadata callback. Callers can list scenarios, explain descriptions and configuration provenance, validate policy without resource IO, or execute one run. Configuration precedence is defaults, one explicit YAML file, declared environment variables, and named options.

JSON stdout is one core v1 result. Exit classes distinguish Pass (0), Fail (1), invocation/configuration/policy/target errors (2), Unknown (3), and runner/command faults (4). `--output` atomically publishes a completed JSON file without replacing an existing file; persistence failure retains stdout and returns exit 4.

## Limits

The generic executable contains labelled in-memory demos. Real business scenarios and target checks come from a context-owned application. `check` does not resolve credential values or establish live readiness. Observe, Replay, runtime Haskell compilation, and production execution are unsupported. The output parent directory must already exist.

## Use and evidence

See [compiled scenario hosts](../scenario-hosts.md).

## Builds on

- [Inspectable typed scenarios](inspectable-typed-scenarios.md)
- [Execution policy preflight](execution-policy-preflight.md)
- [Bounded evidence verification](bounded-evidence-verification.md)
- [Versioned result contract with explicit public summaries](versioned-private-result-contract.md)
