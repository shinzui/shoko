# Version generic readiness without relabeling registration

Date: 2026-10-21

Status: Accepted for the workflow v2 contribution

## Context

The notification consumer at
`mori://tan/tan-platform-qa/plans/2-establish-the-staging-workflow-contract-and-live-readiness-gate`
needs generic contract/readiness mechanics. V1 deliberately describes registration,
including its OTP/completion prerequisites. Relabeling that example or removing
its domain checks would weaken the existing bootstrap.

## Decision

Preserve v1 and its command as a compatibility path. Introduce a strict v2 schema
with workflow-owned prerequisite/requirement sets, explicit pending declarations,
and separate structure-only validation. One read-only gate backs both `check` and
fresh `observe`; its versioned observation protocol is shared by host callbacks
and suite wrappers. Core scenarios and result v2 are unchanged.

The gate verifies declared Kubernetes runtime identity and configured bounded GET
probes. Owner evidence supplies properties that cannot be independently established
read-only, with explicit scope and expiry. Runtime configuration sourced indirectly
from a ConfigMap or Secret is not inferred from its present source. No deployment,
Secret, log or application mutation is performed. Observations omit raw API objects,
addresses, transport errors, bodies and credentials. Past observations cannot grant
fresh action permission or replace owner-controlled fixture approval.

## Consequences

A structurally valid contract can be useful while prerequisites are pending.
Readiness means the checks actually declared and the scoped owner prerequisites;
it is distinct from business acceptance and continuous stability. Consumer evidence
must show the real host and executor parse this protocol before the entire upstream
request is complete. A synthetic test or a healthy renderer alone cannot establish
the notification producer/consumer boundary.
