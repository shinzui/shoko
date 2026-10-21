---
type: "Capability"
title: "Explicit Kubernetes target identity checks"
description: "Check declared Kubernetes namespace and workload identities twice through explicit read-only targeting and retain a sanitized private identity artifact."
generated:
  by: "openai/gpt-6.1-sol"
  at: "2026-10-21T23:13:53Z"
capabilityId: "CAP-10"
provider: "mori://shinzui/shoko"
status: "shipped"
stability: "experimental"
since: "unreleased"
packages:
  - "scripts/workflow-env"
  - "scripts/workflow_identity.py"
interface:
  - "shoko-workflow check --manifest PATH"
  - "shoko-workflow observe --manifest PATH"
  - "schemas/target-observation-v1.schema.json"
  - "python3 scripts/workflow-env check --identity-only --manifest PATH"
requires:
  - "CAP-9"
evidence:
  - kind: "test"
    resource: "scripts/test-workflow-identity"
    proves: "Fake-kubectl process tests for explicit targeting, mismatches, bounds, private artifacts, and identity/readiness separation."
  - kind: "module"
    resource: "scripts/workflow_identity.py"
    proves: "Read-only discovery, bounded subprocesses, allowlisted fields, and artifact permissions."
---

# Explicit Kubernetes target identity checks

The identity check first validates local kubeconfig selection against the explicit cluster and HTTPS server, rejects insecure TLS, and pins context, namespace, and server on API reads. It requests only the named namespace and workloads. Two observations compare UIDs, generations, and exact container/init-container template references.

Each attempted discovery after contract/prerequisite checks produces a private run directory and sanitized identity record tied to the manifest hash. Overall, API, subprocess, and response bounds apply; timeout cleanup targets the owned command group.

## Limits

The separate [generic v2 gate](../workflows/generic-staging-contract.md) adds
runtime application/init/sidecar images, rollout/pod/controller checks, Service
and EndpointSlice association, public endpoint configuration and configured GET
probes. `check` and `observe` share one implementation and artifact schema. Its
readiness is scoped to those declared checks and nonexpired owner prerequisites;
domain fixture/evidence acceptance remains with the consumer. The limits below
still apply to the original v1 identity-only command.

Matching identities establish only this check's observations. Runtime image digests, pod/controller ownership, endpoint and evidence access, domain readiness, and a continuous stable window remain outside it. Plain `check` still exits 2 and `smoke` remains unimplemented. Offline tests use a fake client and do not certify a live cluster.

## Use and evidence

See [identity discovery](../workflows/first-staging-workflow.md).

## Builds on

- [Offline staging workflow contract validation](offline-workflow-contract-validation.md)
