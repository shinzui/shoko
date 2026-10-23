# API-backed email verification

Use `Shoko.Adapter.Email` and `Shoko.Adapter.Email.Resend` from `shoko-adapters` to
observe application email at a controlled receiving address or supply email as an
application input. The application may use any sending service. The first receiving
provider is Resend. A successful POST establishes submission acceptance; an independent
received-email read establishes arrival at that API-backed inbox. Neither proves a
person read it.

Run the complete offline demonstration from the repository root:

```bash
nix develop --command just test-email
```

This starts an owned loopback provider and fixture application, compiles a context-owned
consumer, and exercises the public runner with new, old, unrelated and unavailable mail.
It also tests controlled sending, an inbound ticket workflow, configuration and the
smoke wrapper. It needs no database, broker, API key, DNS change or external delivery.
The final summary names bounded receiving and controlled sending fixture acceptance.
Native Nix adapter checks run the same suite against packaged binaries.

## Describe first, acquire after preflight

The complete compiling consumer is
[`EmailSmoke/Scenario.hs`](../../shoko-adapters/example/EmailSmoke/Scenario.hs).
Its context-owned `SmokeOp` vocabulary distinguishes token allocation, sending an input,
and observing receipt. [`Email/Contract.hs`](../../shoko-adapters/test/Email/Contract.hs)
also demonstrates a separate application HTTP action producing welcome email and a typed
subject/text predicate; [`Email/Sending.hs`](../../shoko-adapters/test/Email/Sending.hs)
shows inbound email causing an independently observed ticket.

The scenario's receive portion uses the public correlation and observation APIs:

```haskell
correlationHandle <- correlate (CorrelationAlias "mailbox")
  (BusinessKeyName "testMailboxId") (fromRef token)
expect $ eventually "received" $ correlatedBy correlationHandle $
  observe "expected-input" (Receipt (fromRef token)) id
```

Construct an `Inbox` with `inbox sourceId accountLabel businessKey domain prefix limits`.
This is a validated pure descriptor, not a remote mailbox. The account label is a logical
public name for an explicitly approved team-listing scope. The domain and prefix determine
the allowed recipients. `EmailLimits` sets page size/count, candidate detail count,
per-response/aggregate scan bytes, outgoing JSON bytes, request duration and entire-scan
duration. Page size is 1–100; all counts/byte limits are positive. Request duration must
fit within scan duration. The host must also validate relationships to its execution and
receipt budgets. None of these settings grants a capability.

`emailObservationHandler inbox tokenInput decoder` returns a pure handler that owns its
source, baseline and `RequiresBusinessKey` contract. The decoder sees private
`ReceivedEmail` accessors for subject, text/HTML, actual HTML format, direct recipients,
headers and attachment metadata. Return a typed domain value for its predicate; decoder
failure is unavailable evidence. Nullable text and HTML are supported. Attachment bodies,
raw-message download URLs and authentication objects are never fetched or exposed.

Use `freshToken` for the public UUID business key. `recipient inbox token` derives an
address using the full token. Never resolve a correlation to an address, OTP or link:
resolved correlations are public report fields. Inputs must agree with the selected
correlation before poll IO. Separate correlation instances can share the same semantic
key while selecting independent mailboxes. Supported addresses are bare ASCII dot-atom
addresses; local-part case and plus tags are preserved, while domains are normalized.
Only direct parsed `to` metadata is matched. Bcc-only, envelope and forwarded-recipient
semantics are outside this contract.

After `resolveScenario` approves policy, resolve secrets at the host boundary, validate
`resendCredentials`, and acquire a fresh `newResendReader inbox maybeSend credentials`
inside the binding's acquisition action. Use the same descriptors for handlers and
acquisition. A descriptor mismatch prevents provider IO. Use `focus` for a reader inside
a larger binding resource. Finalization releases local ownership and returns `Retained`;
no remote mailbox provisioning or mail deletion occurs.

## Finite, sampled evidence

Capture scans the whole approved team received listing before any action and retains all
existing provider IDs in run-owned memory. The public baseline cursor is a random handle,
not an ID set or replay token. Every poll performs another complete bounded scan, excludes
baseline IDs, filters recipients locally, and verifies candidate detail identities and
recipients. IDs are opaque validated path segments. Repeated IDs are deduplicated and
public occurrence handles are random and stable within that reader. The production origin
is fixed to verified TLS at `api.resend.com`; the loopback seam is private test code.
Redirects, ambient proxies, connection retries and idle connections are disabled.

The retained received count must stay within **`pageSize × maxPages`**. Leave headroom for
messages arriving during the run. All required response, aggregate byte, detail and time
limits must fit too. A team account that exceeds baseline bounds yields Unknown before
any application mutation. The receiving endpoint has no assumed sort order or server-side
recipient filter; scans never stop early at an old ID. Account owners must agree on
retention outside Shōko. The adapter neither resets nor deletes existing mail.

Each successful batch advertises `SampledState` over its host-clock start/finish, not
complete interval history. A timely matching sample can Pass `eventually`. Conclusive
misses throughout the scheduled samples Fail at its deadline. Any unavailable or incomplete
poll leaves a sticky gap and produces Unknown unless a later match passes. A partial scan
never supplies a successful witness. Authorization errors, 429, malformed JSON, missing
metadata/detail, cursor loops, timeouts and exhausted bounds are unavailable evidence.
The reader does not wait through `Retry-After`; the runner schedules later bounded reads.

`never` cannot Pass with sampled coverage; a timely matching witness Fails. `exactlyOnce`
always ends Unknown, including two distinct matching messages, because the current core
does not accumulate IDs for sampled sources. No claim of continuous absence or exactly-once
delivery is made. Reads completing after cutoff cannot establish a positive result.

## Controlled input sending

Construct a `SendDescriptor` with `sendDescriptor inbox approvedSenders` and acquire the
reader with that descriptor. `emailActionHandler` adds `SendHttp`, `WriteState` and
`ExternalSideEffect` to preflight. The example token fixture adds `SyntheticResource`,
which also requires explicit per-run consent. A staging label does not approve destinations.

The payload builder resolves typed inputs with `resolveInput`, derives recipients from the
run token, and calls `emailPayload sender recipients subject text html idempotencyKey`.
The descriptor restricts exact sender identities and recipient domain/prefix with valid
UUID tokens. Unsupported destinations fail before POST. Arbitrary headers, attachments,
CC/Bcc, scheduling and templates are excluded. Outgoing JSON is bounded. Supply a stable
key derived from the run-owned token and stable action ID, such as `token <> ":send-input"`;
keys are nonempty printable ASCII without spaces and at most 256 characters. Keep key and
payload unchanged for the same logical action; distinct action instances need distinct keys.

The adapter makes **one POST attempt**. Only a well-formed successful provider response
produces the `accepted` action tag and a private `EmailSubmission`. A timeout, including
one after server acceptance, remains unavailable/Unknown without retry. Investigate an
uncertain send using its original key/payload; starting a new run creates a new effect.
[Resend's idempotency window](https://resend.com/docs/dashboard/emails/idempotency-keys)
is finite and does not prove exactly-once delivery. The fixture's deduplication tests do
not establish live provider behavior.

Reports retain only explicit public tokens, handles, counts and fixed codes. Content,
credentials, addresses, headers, URLs, filenames and raw exceptions have no automatic
rendering path. Keep operation/source/predicate labels public. Private typed values have
no `Show` or JSON instances; context code remains responsible for any explicit logging.
An observation predicate cannot return an OTP for a later action: the current runner
executes actions before expectations. That needs a separately designed bounded action.

## Explicit live smoke

[`EmailSmoke.hs`](../../shoko-adapters/example/EmailSmoke.hs) is a separately compiled
native host. [`EmailSmoke/Config.hs`](../../shoko-adapters/example/EmailSmoke/Config.hs)
uses the workspace-pinned Settei 0.2.0.0 packages. The adapter library and core do not
import Settei. [`scripts/smoke-email`](../../scripts/smoke-email) locates the executable
with `cabal list-bin` and delegates arguments without parsing configuration or printing
inputs. Build and inspect without any private values:

```bash
nix develop --command cabal build exe:shoko-email-smoke
nix develop --command python3 scripts/smoke-email --inspect
```

For an authorized live run, privately supply an approved test account's API key, a verified
sender, and an actual receiving test domain. Default reference names are:

| Environment variable | Private value |
| --- | --- |
| `SHOKO_EMAIL_RESEND_API_KEY` | API key permitted to list/read receiving mail and submit the controlled send |
| `SHOKO_EMAIL_SENDER` | Already approved, verified bare sender address |
| `SHOKO_EMAIL_RECEIVING_DOMAIN` | Already approved receiving test domain |

Do not put these values in YAML, command arguments or saved transcripts. The host resolves
them through separate Settei Secret declarations after policy preflight. The helper's
receiving-only scenario (`smokeScenario False`) skips sender resolution when embedded in
a host that supplies its own application producer; the standalone `--receive-only` option
only observes and does not trigger an application. Initial inspection/preflight uses safe
placeholder private addresses, then the live host validates the resolved descriptors and
repeats preflight before acquisition. Inspection does not read private values or allocate
a reader. Missing inputs fail with a fixed diagnostic and nonzero exit; they never skip.

Only with session authorization and those approved inputs already in the environment:

```bash
nix develop --command python3 scripts/smoke-email --allow-synthetic
```

This sends one controlled message to a fresh token-derived recipient and waits for independent
receipt. Default budgets are 30 seconds execution, 20 seconds receipt, 1 second polling,
3 seconds per request and 5 seconds per scan. These are finite test budgets, not delivery
promises. It prints a sanitized result and exits zero only for Pass. The specialized smoke
host uses nonzero for every other outcome; inspect the result's verdict for Fail/Unknown.
It does not provision accounts/DNS, delete messages or use simulated-delivery addresses.
Do not retry an uncertain live invocation automatically.

Operational precedence is defaults, one explicit `--config path.yaml`, then explicitly
bound operational variables. Unknown YAML keys and invalid winning overrides fail without
falling back. There are no Settei CLI overrides or ambient configuration search.

| YAML keys | Operational environment variables |
| --- | --- |
| `bounds.pageSize`, `bounds.maxPages`, `bounds.maxDetails` | `SHOKO_EMAIL_PAGE_SIZE`, `SHOKO_EMAIL_MAX_PAGES`, `SHOKO_EMAIL_MAX_DETAILS` |
| `bounds.responseBytes`, `bounds.scanBytes`, `bounds.payloadBytes` | `SHOKO_EMAIL_RESPONSE_BYTES`, `SHOKO_EMAIL_SCAN_BYTES`, `SHOKO_EMAIL_PAYLOAD_BYTES` |
| `bounds.requestMs`, `bounds.scanMs` | `SHOKO_EMAIL_REQUEST_MS`, `SHOKO_EMAIL_SCAN_MS` |
| `policy.executionMs`, `policy.receiptMs`, `policy.pollMs` | `SHOKO_EMAIL_EXECUTION_MS`, `SHOKO_EMAIL_RECEIPT_MS`, `SHOKO_EMAIL_POLL_MS` |

YAML additionally permits `provider` (only `resend`), public `source` and `account` labels,
`recipient.prefix` (default `shoko-`), and reference names `access.apiKeyEnv`,
`access.domainEnv`, `access.senderEnv`. Configuration contains reference names, never
private values. It cannot change the fixed origin, capability grants or synthetic consent.
A request must fit the receipt budget, a scan the execution budget, polling the receipt
window, and the receipt window must be shorter than execution.

No live Resend delivery or deployed application staging acceptance was performed for this
implementation. See [ADR 0006](../adr/0006-bound-email-evidence-and-separate-submission-from-receipt.md)
for durable boundaries and [the capability record](../capabilities/api-backed-email-evidence.md)
for implemented evidence.
