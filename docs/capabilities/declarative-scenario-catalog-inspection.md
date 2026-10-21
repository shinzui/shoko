---
type: Capability
title: Declarative scenario catalog inspection
description: Validate explicit ready and pending scenarios and delegate pure explanation and policy checking to pinned compiled hosts without a consumer-owned parser.
generated:
  by: openai/gpt-6.1-sol
  at: "2026-10-21T22:53:03Z"
capabilityId: CAP-11
provider: mori://shinzui/shoko
status: shipped
stability: experimental
since: unreleased
packages:
  - shoko-cli
interface:
  - shoko-suite catalog-check
  - shoko-suite list
  - shoko-suite explain
  - shoko-suite check
  - schemas/scenario-catalog-v1.schema.json
requires:
  - CAP-8
evidence:
  - kind: test
    resource: scripts/test-scenario-catalog
    proves: Real compiled consumer inspection leaves metadata and resource instrumentation untouched, rejects invalid declarations, and preserves subprocess exits.
  - kind: module
    resource: scripts/scenario_catalog.py
    proves: Strict schema and semantic validation and explicit argument-vector host dispatch.
---

# Declarative scenario catalog inspection

The [catalog guide](../scenario-catalog.md) defines the v1 declaration and explicit
artifact binding. Consumers own catalog data and their pins; Shoko owns validation
and dispatch. Pending entries are listable but cannot execute. `check` reports
policy validity with live readiness unchecked. Production and arbitrary aliases,
path escape and ambiguous artifact resolution are rejected before host invocation.

Suite execution, readiness, envelopes, arbitrary executable discovery and runtime
compilation are excluded. A source revision in metadata is not a binary attestation.

Builds on [compiled hosts](compiled-scenario-cli-hosts.md).
