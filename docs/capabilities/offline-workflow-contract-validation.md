---
type: "Capability"
title: "Offline staging workflow contract validation"
description: "Validate explicit staging workflow manifests for schema and relationship consistency before any target access."
generated:
  by: "openai/gpt-6.1-sol"
  at: "2026-10-21T23:13:53Z"
capabilityId: "CAP-9"
provider: "mori://shinzui/shoko"
status: "shipped"
stability: "experimental"
since: "unreleased"
packages:
  - "scripts/workflow-env"
  - "schemas/workflow-v1.schema.json"
interface:
  - "shoko-workflow validate --structure-only --manifest PATH"
  - "schemas/workflow-v2.schema.json"
  - "python3 scripts/workflow-env validate --manifest PATH"
  - "scripts/workflow_contract.py"
evidence:
  - kind: "test"
    resource: "scripts/test-workflow-contract"
    proves: "Schema relationships, source coverage, prerequisites, secret-safe errors, and synthetic-manifest rejection."
  - kind: "conformance"
    resource: "schemas/workflow-v1.schema.json"
    proves: "Strict workflow contract v1 format."
---

# Offline staging workflow contract validation

The offline validator checks stable requirement/scenario references, declared endpoints and evidence adapters, coverage compatibility, correlation/baseline requirements, canonical host ownership, and prerequisite declarations. A negative scenario needs a precise rejection requirement and a downstream invariant. Durable sources require an explicit append-only history policy.

The command rejects synthetic examples as staging contracts and pending prerequisites without contacting Kubernetes or resolving credentials.

## Limits

The [generic v2 path](../workflows/generic-staging-contract.md) accepts workflow-owned
requirements, explicit pending workloads/endpoints and structure-only validation
without target IO. It preserves the v1 registration checks rather than relabeling
their example. `scripts/test-workflow-v2` exercises both paths.

A structurally valid manifest and owner declarations do not prove live readiness or successful business behavior. The repository does not yet contain the accepted real staging manifest or an implemented independent smoke workflow.

## Use and evidence

See the [first staging workflow guide](../workflows/first-staging-workflow.md) and [synthetic format example](../../integration/examples/workflow.example.json).
