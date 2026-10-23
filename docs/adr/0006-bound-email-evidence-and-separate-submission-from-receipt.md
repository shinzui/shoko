# Bound email evidence and separate submission from receipt

Date: 2026-10-23

Status: Accepted

## Context

Email can be application output or an input to an email-driven workflow. Provider
submission is not proof of arrival. The receiving API has finite, mutable visibility;
it cannot establish complete history over a host-clock interval. Mail also contains
private addresses, credentials, verification links, content and attachments.

## Decision

`Shoko.Adapter.Email` owns typed descriptors and handlers. The first provider is
Resend, accessed over its fixed verified TLS origin without an SDK. Pure handler
construction performs no allocation or secret lookup. Hosts use Settei for operational
configuration and defer API keys, sender addresses and receiving domains to separate
Secret declarations after policy preflight. The example uses safe placeholder
addresses for initial preflight, validates private descriptors afterward, and repeats
preflight with the actual descriptors before acquisition. Operational overrides cannot
grant capabilities or synthetic consent.

Read the team-wide received-email listing with explicit finite pagination. Account
approval therefore covers that listing scope, even though matching and detail retrieval
are restricted locally to direct `to` recipients. Scan every page; no undocumented
provider ordering is assumed. A baseline captures all existing IDs before actions.
Its public cursor is a random run-local handle into private memory, not an encoded
ID set, address or count. Every poll excludes those IDs, checks the selected opaque
UUID token against typed input, and rechecks detail identity and recipients. Preserve
local-part case and plus tags; normalize domains only. Bcc-only and forwarded-recipient
semantics are excluded. No provisioning, mail deletion, attachment downloads or link
visits belong to this adapter.

A complete bounded sample advertises `SampledState`, with host-clock start and finish.
Any incomplete scan is unavailable evidence, including a scan that found a partial
witness. A matching sample completed by cutoff can Pass `eventually`; all conclusive
sampled misses can Fail at its deadline. Any unavailable poll leaves a gap unless a
later match passes. `never` cannot Pass, but a timely matching witness Fails. The current
core does not accumulate sampled occurrence IDs, so `exactlyOnce` is always Unknown,
even for two observed matches. Stronger cardinality needs a separate core decision.

Sending always requires `SendHttp`, `WriteState` and `ExternalSideEffect`. Synthetic
fixtures additionally require `SyntheticResource` and per-run consent. The descriptor
fixes allowed sender identities and recipient domain/prefix; destinations must contain
a valid run token. Contexts supply a stable idempotency key for each logical action.
One POST attempt produces either accepted submission evidence or uncertainty. Never
retry a timed-out mutation. Resend's finite deduplication window does not establish
exactly-once delivery. Receipt is independently observed through the receiving API.

Content-bearing types have no rendering or generic serialization instances. Public
reports contain opaque tokens, random occurrence handles, counts and fixed diagnostic
codes. Transport errors and decoder failures discard provider text. Each acquisition
owns its baseline and occurrence maps, with cancellable serialized access; response
scopes and zero idle connections close sockets on failure and cancellation.

## Consequences

The retained team received count must fit within `pageSize × maxPages`, with additional
byte/detail limits. Oversized baselines prevent actions and yield Unknown. Account
owners need an explicit retention policy; finalization releases local resources and
honestly reports Retained. The adapter has no deletion privilege.

The compiled fixture application, consumer and smoke scenario demonstrate the public
runner contract through real loopback HTTP. These checks require no live credentials
and do not establish live Resend readiness or deployed application acceptance. Live
smoke is separate and requires approved inputs and session authorization. An uncertain
submission must be investigated with its original key/payload; a fresh run is a new
effect. The current actions-before-expectations runner cannot extract an OTP from an
observation and feed it to a later action.

See [the email guide](../workflows/email-verification.md) and
[ExecPlan 11](../plans/11-add-api-backed-email-sending-and-inbox-evidence.md).
