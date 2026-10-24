---
type: "Capability"
title: "Versioned result contract with explicit public summaries"
description: "Encode and decode versioned verification results with explicit safe summaries, description identity, and partial evidence for faults."
generated:
  by: "openai/gpt-6"
  at: "2026-10-19T02:45:50Z"
capabilityId: "CAP-4"
provider: "mori://shinzui/shoko"
status: "shipped"
stability: "experimental"
since: "unreleased"
packages:
  - "shoko-core"
interface:
  - "Shoko.Result"
  - "Shoko.Result.Json.encodeRunResult"
  - "Shoko.Result.Json.decodeRunResult"
  - "Shoko.Observation.PublicValue"
evidence:
  - kind: "test"
    resource: "shoko-core/test/ResultSpec.hs"
    proves: "Round trips, strict decoding, description digest checks, and secret-sentinel exclusions."
  - kind: "conformance"
    resource: "schemas/run-result-v3.schema.json"
    proves: "The public version 2 JSON structure."
  - kind: "example"
    resource: "shoko-core/test/golden/unknown.json"
    proves: "A retained uncertain verification report with evidence."
---

# Versioned result contract with explicit public summaries

The v2 result format separates verification, preflight failure, and runner fault. Reports retain action outcomes, expectation reasons, source and correlation information, timing, cleanup disposition, and available partial evidence. A digest identifies the public scenario description separately from logical input and build identity.

Only explicit public choices, counts, and flags cross the result boundary. Raw typed operation values have no automatic serialization path. The decoder checks versions, known fields and tags, typed values, and description digest consistency.

## Limits

A binding or host author must choose non-secret public identifiers and summaries. An allowlisted text field can still disclose a secret if the author puts one there. A report run ID does not establish downstream execution-ID propagation.

## Use and evidence

See the [core report guide](../core.md), [schema](../../schemas/run-result-v3.schema.json), and [golden fixtures](../../shoko-core/test/golden/README.md).
