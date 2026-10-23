---
type: "Capability"
title: "API-backed email evidence and controlled input"
description: "Observe new correlated mail through bounded Resend reads and submit approved input mail with independent receipt evidence."
generated:
  by: "openai/gpt-6.1-sol"
  at: "2026-10-23T22:15:00Z"
capabilityId: "CAP-12"
provider: "mori://shinzui/shoko"
status: "shipped"
stability: "experimental"
since: "unreleased"
packages:
  - "shoko-adapters"
interface:
  - "Shoko.Adapter.Email"
  - "Shoko.Adapter.Email.Resend"
  - "shoko-email-smoke"
evidence:
  - kind: "test"
    resource: "shoko-adapters/test/Email/Contract.hs"
    proves: "Actual HTTP receiving with pre-action baselines, token correlation, finite bounds, sampled outcomes, cancellation, isolation and private reports."
  - kind: "test"
    resource: "shoko-adapters/test/Email/Sending.hs"
    proves: "Controlled sends, independent receipt, denied destinations, one-attempt timeout, explicit idempotency and inbound ticket input."
  - kind: "test"
    resource: "shoko-adapters/test/Email/Config.hs"
    proves: "Settei source precedence, fail-closed invalid winners and deferred private input resolution."
  - kind: "example"
    resource: "shoko-adapters/example/EmailSmoke/Scenario.hs"
    proves: "Compiling context-owned smoke scenario exercised against loopback through the public runner."
  - kind: "test"
    resource: "scripts/test-email-host"
    proves: "Offline real-host inspection and missing-input failures plus wrapper delegation and private diagnostics."
---

# API-backed email evidence and controlled input

Describe an approved team listing scope and token-derived recipients with pure descriptors,
then acquire a fresh Resend reader with explicit credentials after policy preflight. Bounded
full scans exclude baseline IDs and independently verify candidate details. Content remains
private typed data with no automatic rendering path. Public baselines and occurrences use
random handles.

Controlled sends require approved sender/recipient destinations, explicit mutation/external
effect capabilities and a stable idempotency key. Only successful provider acceptance emits
`accepted`; a separate receiving observation proves inbox arrival. The transport makes one
mutation attempt and preserves uncertainty on timeout.

## Limits

Coverage is sampled. `never` and `exactlyOnce` cannot Pass, and sampled `exactlyOnce` is always
Unknown under the current runner. Incomplete scans cannot establish a match or absence.
The retained team received count must fit `pageSize × maxPages` and byte/time bounds.
Only direct `to` recipients are supported. Provisioning, deletion, attachment bodies, OTP
extraction into later actions and durable delivery guarantees are excluded. Fixture checks
do not establish live provider delivery or deployed staging acceptance. Live smoke is separate
and needs authorized approved inputs.

See [email verification](../workflows/email-verification.md) and
[ADR 0006](../adr/0006-bound-email-evidence-and-separate-submission-from-receipt.md).
