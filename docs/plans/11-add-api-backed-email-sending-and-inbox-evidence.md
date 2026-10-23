---
id: 11
slug: add-api-backed-email-sending-and-inbox-evidence
title: "Add API-backed email sending and inbox evidence"
kind: exec-plan
created_at: 2026-10-23T21:22:55Z
intention: "intention_01m5na8sg3erjsxb5fwxjvnznj"
provenance:
  created_by:
    model: "gpt-6.1-sol"
    harness: "codex-cli"
    at: 2026-10-23T21:22:55Z
  revisions:
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-10-23T21:34:40Z
      mode: "discuss"
      note: "Make Settei the host configuration and deferred secret-resolution boundary for email and smoke consumers"
    - model: "claude-opus-5-5"
      harness: "claude-code"
      at: 2026-10-23T21:40:37Z
      mode: "update"
      note: "Fix sampled exactlyOnce claim, public baseline cursor, gap rule, paths, Settei pins, Inboxes API and retention sizing"
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-10-23T22:03:55Z
      mode: "implement"
      note: "Implement bounded Resend evidence, controlled sending, host configuration and contract validation"
  reviews:
    - model: "claude-opus-5-5"
      harness: "claude-code"
      at: 2026-10-23T21:40:37Z
      verdict: "comments"
      note: "Verified core/runner, HTTP, Settei, Nix and Resend claims; findings applied in the same-session update revision"
---

# Add API-backed email sending and inbox evidence

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Add an email adapter so a context-owned Shōko scenario can verify that its application
sent an expected message to a supplied API-backed test inbox, and can send a controlled
message when inbound email is itself an application input. Resend is the first provider.
The application may use any mail delivery service: receipt is observed independently at
the test inbox. A successful send API call establishes acceptance for sending; a message
read from the receiving API establishes arrival at that inbox. Neither establishes that a
person read the message.

The user-visible demonstration is a compiled consumer scenario running through the public
runner against a loopback HTTP implementation of Resend's contract. A fixture application
produces a welcome email and a scenario checks its subject and a typed content predicate.
A second scenario sends an input email and verifies its arrival independently of the send
response. Run both, including negative and unavailable-source controls, with the new
`nix develop --command just test-email` command. A separately invoked live smoke command
will exercise the same provider implementation when the user supplies approved test mail
credentials and addresses; it is never part of ordinary CI.

This is one ExecPlan with four milestones. Receiving and sending share provider types,
transport limits, policy, and the fixture, so separate child plans would add coordination
without independent work streams. This plan has no parent MasterPlan and does not change
the outstanding registration staging acceptance gate.


## Progress

- [x] M1 — 2026-10-23: Actual HTTP list/detail reads and the public runner pass a fresh
  application welcome message; old and unrelated messages cannot satisfy it.
  `nix develop --command just test-email` passed the initial five consumer controls.
- [x] M2 — 2026-10-23: Bounded scans, isolation, policy, privacy, real socket cancellation,
  and fake-clock cutoff controls pass. Unavailable reads remain inconclusive; sampled
  `never`/`exactlyOnce` never Pass. Existing PostgreSQL/HTTP suites also pass.
- [x] M3 — 2026-10-23: Controlled sends, independent receipt, inbound ticket input,
  denied destinations, stable/conflicting keys, and one-attempt mutation timeout pass.
  `just test-email` passes 50 contracts plus offline smoke-host/wrapper process checks.
- [ ] M4 — The email checks run in local and native Nix validation, public documentation
  and a separately invoked live smoke path exist, and implemented claims have catalog evidence.

M1–M3 are verified. M4 documentation and native/repository integration validation remain.
Core acceptance: all 78 tests pass; existing PostgreSQL/HTTP consumer suites pass.
The authoritative intention ID remains in frontmatter.


## Surprises & Discoveries

2026-10-23 (implementation): Hackage now lists Settei 0.3.0.0. This work retains the
workspace-pinned 0.2.0.0 as planned; the smoke host compiles and passes against that release.
No dependency upgrade or bounds waiver is needed.

2026-10-23 (review): the runner never accumulates occurrence IDs for a `SampledState` source.
In `shoko-core/src/Shoko/Runner.hs`, `runExpectation` merges IDs only when both the batch and
the source are durable; otherwise the ID set stays empty. `exactlyOnce` therefore closes as
`CoverageIncomplete`/Unknown and can never Fail through this adapter, even when two distinct
matching messages are observed. Only `never` can Fail, on a witness that finishes by cutoff.

```haskell
( if durable then merged else ids, ...
ExactlyOnce | Set.size nextIds > 1 -> final next Mismatch Fail
```

2026-10-23 (review): `Baseline.cursor` is serialized into encoded results by `baselineValue`
in `shoko-core/src/Shoko/Result/Json.hs`, so whatever the adapter puts there is public.

2026-10-23 (review): Resend now documents an Inboxes API. `GET /inboxes/{inbox_id}/threads`
is scoped to one inbox (by ID or address) and returns threads, most recently active first.
`GET /emails/receiving` remains team-wide with no recipient filter, and its page does not
document ordering. The general pagination page says forward pagination runs newer to older.
The received-email detail response also carries nullable `raw` and `authentication` objects.


## Decision Log

2026-10-23 (implementation): Smoke inspection/preflight uses safe placeholder private
addresses, then resolves Secret values and repeats preflight with the actual descriptors
before acquisition. Explicit `--allow-synthetic` supplies per-run consent for execution;
`--inspect` performs no acquisition or private-value lookup. The shared compiled scenario
and configuration tests exercise the same host helpers. See [ADR 0006](../adr/0006-bound-email-evidence-and-separate-submission-from-receipt.md).

2026-10-23: Use one ExecPlan. This is an additive adapter with one provider and one shared
fixture; it needs no new core execution mode, provider SDK, or independently released service.

2026-10-23: Include both receiving and sending, implemented in that order. Receiving verifies
application output; sending supplies input to email-driven workflows. Both were requested
in the discussion leading to this plan. A send response must never satisfy a receipt assertion.

2026-10-23: Advertise `SampledState` coverage, meaning evidence from particular reads rather
than complete history over an interval. No provider retention, deletion exclusion, or
visibility-to-host-clock proof has been established. `never` and `exactlyOnce` therefore
cannot Pass with this adapter. A `never` witness observed by the cutoff still Fails. An
`exactlyOnce` expectation always ends Unknown, even with two distinct matching messages,
because the core runner does not accumulate IDs for sampled sources (see Surprises).
Changing that is a core change and is out of scope here.

2026-10-23: Use an explicitly approved test account/listing scope and a fresh recipient per
run. Resend's receiving list is team-wide; local recipient filtering is part of the declared
adapter contract, not an invented server-side recipient query. Keep correlation tokens
separate from actual email addresses because core reports serialize resolved correlations.

2026-10-23: Exclude webhooks, IMAP/SMTP clients, mailbox/domain/DNS provisioning, threads,
attachment downloads or sending, automatic link visits, and delivery/open tracking. Expose
attachment metadata and text/HTML for predicates only. Acquiring an OTP midway through a
scenario and feeding it to a later action requires a separately designed bounded action:
the current runner executes actions before expectations and does not return observation refs.

2026-10-23: Use Settei for email configuration and API-key resolution at the consuming
host boundary, including the smoke executable. This follows ADR 0002 and the existing
CLI's two-phase configuration/credential resolution. The adapter accepts validated typed
values; it does not read process environment variables, parse configuration files, or
depend on Settei. Settings resolution cannot grant sending permission.

2026-10-23 (review): Keep the team-wide `GET /emails/receiving` listing for the first version.
The inbox-scoped Inboxes API needs an inbox per fresh recipient, which means mailbox
provisioning (excluded here). It also returns a thread model, and threads are excluded too.
Revisit it as a separate decision if per-run inbox creation is approved.

2026-10-23 (review): Each baseline and poll scans the whole team listing, and messages are
never deleted. So the approved test account works only while its retained received count
fits within `pageSize × maxPages`. Beyond that, baselines fail before any action, which is
conservative and correct. The guide must state this retention-sizing requirement. Stopping
a scan early at the newest baseline ID would need a documented ordering guarantee for the
receiving list. Resend does not document one, so early stopping is deferred.

2026-10-23 (review): The smoke host resolves defaults, one optional `--config` YAML file,
and explicitly bound environment variables. It has no Settei command-line overrides, so it
needs only `settei`, `settei-env`, and `settei-yaml`, not `settei-optparse-applicative`.


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Shōko is a Haskell library that describes business operations as typed data, resolves each
operation to a binding handler, executes actions, and evaluates timed expectations. A
binding is the mapping from a context's vocabulary to concrete IO. A source is a named
evidence reader with a baseline captured before actions. A baseline identifies what was
already present so old messages cannot satisfy occurrence checks for this run.

`shoko-core/src/Shoko/Binding.hs` exposes `actionHandler`, `observationHandler`, `newSource`,
`sampledSource`, `resolveInput`, `guardCorrelation`, `sourceBaseline`, `requestDeadline`,
`evidenceUntil`, `callClock`, and `focus`. `sampledSource` captures only a timestamp with no
cursor. That is not enough here, so the email source uses
`newSource label SampledState capture` with its own ID-set capture. Handler descriptions
must be constructed without allocating resources; their
contracts participate in preflight before acquisition. A `BusinessKeyName` is the logical
kind of an identifier; an explicit correlation handle selects one particular instance of
that key. `shoko-core/src/Shoko/Observation.hs` defines `Baseline` (`source`, `capturedAt`,
and an optional `cursor` text that is serialized into reports), `Occurrence`, `Coverage`
(`strength`, `fromMicros`, `throughMicros`, `complete`), and `ObservationOutcome`.
`shoko-core/src/Shoko/Runner.hs` distinguishes positive sampled evidence from durable
interval coverage. For a sampled `eventually` expectation, the runner works as follows.
Each request deadline is the cutoff. A matching batch that finishes by the cutoff Passes.
At the cutoff, the result is Fail only if every poll returned a valid complete batch. A
single unavailable poll or incomplete batch sets a sticky gap flag, and the result becomes
Unknown. The runner rejects any coverage whose `throughMicros` is later than the poll's
finish time. `shoko-core/src/Shoko/Action.hs` defines typed
action results and accepted outcome tags. `shoko-core/src/Shoko/Environment.hs` already has
`SendHttp`, `ReadState`, `WriteState`, `ExternalSideEffect`, and `SyntheticResource`.

`shoko-adapters/src/Shoko/Adapter/Http.hs` implements bounded HTTP requests with verified
TLS, no ambient proxy or redirects, no connection retry, zero idle connections, bounded
response bodies, and sanitized failures. Its public observation helper requires one
business-key query parameter on a fixed GET URL. Its `HttpPayload`, in
`shoko-adapters/src/Shoko/Adapter/Http/Request.hs`, has no idempotency header or pagination
parameters. A Resend implementation cannot simply declare a fictional recipient query or
smuggle new headers through this helper. Add a dedicated private email HTTP transport using
the existing libraries; preserve these protections. Extract a shared private helper only
if it simplifies real duplicated behavior and keeps existing HTTP consumers compatible.

`shoko-adapters/test/AdapterTests.hs` demonstrates actual HTTP IO followed by public runner
verification. `scripts/test-adapters` owns temporary fixtures and accepts `--binaries` for
Nix-built suites. `shoko-adapters/shoko-adapters.cabal` lists exposed modules and suites;
`justfile` groups checks; `flake.module.nix` runs adapter suites in its native `checkPhase`.
`docs/adapters.md`, `docs/scenario-hosts.md`, and `docs/development.md` describe the public
consumer surface. `shoko-cli/test/ConsumerHost/Registration.hs` illustrates context-owned
vocabulary, typed inputs, and explicit correlation handles; it is an example, not a live
registration implementation.

`shoko-cli/src/Shoko/Cli/Config.hs` is the current Settei boundary: `declaration` describes
ordinary settings and credential references, `loadConfig` resolves explicit sources with
unknown-key rejection, and `resolveCredentials` uses a separate `secretSetting` declaration
for required nonempty credentials. `shoko-cli/src/Shoko/Cli.hs` runs policy preflight before
resolving credentials and acquiring resources. Email hosts follow this sequence. The
existing generic host exposes only fixed configuration keys; native consumers needing
email-specific settings declare those with Settei rather than assuming arbitrary new
keys already work in `Shoko.Cli.Config`.

Relevant local decisions are
[ADR 0002](../adr/0002-keep-scenarios-inspectable-and-bindings-explicit.md), which requires
pure inspection, explicit binding capabilities, correlation checks, and secret resolution
at the host boundary;
[ADR 0003](../adr/0003-record-bounded-evidence-and-three-valued-results.md), which requires
pre-action baselines, finite budgets, private values, and honest Pass/Fail/Unknown evidence;
and [ADR 0004](../adr/0004-gate-parity-on-real-workflows-and-context-owned-vocabulary.md),
which keeps vocabulary and real staging acceptance owned by the consuming context. In
particular, successful local adapter checks do not establish registration readiness or
an approved OTP acquisition facility.
[ADR 0005](../adr/0005-version-generic-readiness-without-relabeling-registration.md) keeps
workflow v1/v2 manifests and result v2 unchanged. This plan follows it and does not extend
the manifest schema. There is no existing email-specific ADR. Preserve the plain
filesystem ADR convention. The next free number is `0006`. Add or revise durable decisions
during implementation.

Provider research checked on 2026-10-23: the
[receiving guide](https://resend.com/docs/dashboard/receiving/introduction) supports a
Resend-managed receiving domain or a configured custom domain. The
[list endpoint](https://resend.com/docs/api-reference/emails/list-received-emails) is
`GET /emails/receiving`, returning team received-message references. The
[pagination contract](https://resend.com/docs/api-reference/pagination) explicitly includes
receiving: supply `limit` (1–100), inspect `has_more`, and use the last ID as `after`.
Without `limit`, this older list endpoint can return all messages, so always set it.
No recipient filter is established by these references. These three references establish
the provider setup, list scope, and page traversal used here. The receiving list page does
not document sort order, so correctness must not depend on it. A separate Inboxes API
(`GET /inboxes/{inbox_id}/threads`) is inbox-scoped but is not used; see the Decision Log.

The [detail endpoint](https://resend.com/docs/api-reference/emails/retrieve-received-email)
is `GET /emails/receiving/{id}` and supplies text, HTML, headers, and attachment metadata.
Request `html_format=cid` to retain inline-image references rather than embedding images;
still enforce response limits. The response's own `html_format` may differ from the request.
Ignore the nullable `raw` and `authentication` objects: never follow, store, or expose them. The [send endpoint](https://resend.com/docs/api-reference/emails/send-email)
is `POST /emails`, returning a provider ID. Its
[idempotency contract](https://resend.com/docs/dashboard/emails/idempotency-keys) deduplicates
the same request key for 24 hours; this does not prove exactly-once delivery. Recheck these
HTTP contracts when implementing, without sending real mail merely to research the API.


## Plan of Work

### M1 — Receive application output through a real HTTP boundary


Create `shoko-adapters/src/Shoko/Adapter/Email.hs` for provider-neutral descriptors,
non-renderable content values, and handlers; create
`shoko-adapters/src/Shoko/Adapter/Email/Resend.hs` for Resend configuration and construction,
and `shoko-adapters/src/Shoko/Adapter/Email/Internal.hs` for private transport and reader
state. Add an `email-adapter-test` suite to `shoko-adapters/shoko-adapters.cabal`, shaped
like `http-adapter-test` (`hs-source-dirs: test`, `-threaded`). Its files are
`shoko-adapters/test/EmailMain.hs`, `shoko-adapters/test/Email/Contract.hs`, and
`shoko-adapters/test/Email/Fixture/server.py`. List the fixture under `extra-source-files`
now, as `test/Fixture/server.py` already is. Add an owned fixture runner
`scripts/test-email`, modelled on `scripts/test-adapters`, and expose it as
`just test-email`. The fixture implements real list/detail
requests with pagination plus a distinct fixture-application trigger. The scenario triggers
that application over the existing HTTP adapter and observes the email via the new adapter.
It must traverse the production Resend decoder and transport, not only a fake Haskell callback.

Construct a pure inbox descriptor with a public source ID, approved test-account listing
scope, approved recipient domain/prefix, semantic business-key name, page size/count,
detail-request cap, byte limits, and per-request limit. Secrets enter the acquired reader
only. Capture the bounded list of all existing provider message IDs before actions; retain
it in run-owned memory behind an opaque baseline token. The token goes in `Baseline.cursor`,
which is public in reports. It must therefore be a fresh random run-local handle that
encodes no provider ID, count, or address. A baseline that cannot finish within limits
fails before any application mutation. No baseline timestamps or provider
sequence numbers stand in for the complete ID set.

Use fresh random opaque tokens as public mailbox business keys, for example the semantic
key `testMailboxId`. Resolve a token to a controlled recipient using the declared test
domain/prefix, or a private binding-owned map; the token itself is safe to report. Do not
use an actual email address, OTP, or verification URL as the resolved correlation value.
The example allocates the token as a fixture value without provisioning a remote inbox.
Capture can list the authorized account before that value exists. At observation time,
require the typed token input to agree with the selected correlation before network IO.
Retain the full token when deriving an address so parallel runs do not collide. Distinct
correlation instances in composed workflows must remain independent.

Each poll starts a new bounded list scan, checks direct recipient metadata against the
selected test address, excludes baseline IDs, and fetches details only for candidates.
Handle provider IDs as opaque validated path segments, never URLs. Recheck identity and
recipient in the detail response before decoding the context value. Initially support
direct deliveries with matching parsed `to` metadata; do not claim envelope-recipient,
Bcc-only, or forwarded-recipient semantics. Validate supported bare address syntax without
lowercasing local parts or stripping plus tags. Domain comparisons may be case-insensitive.
Treat missing or malformed necessary metadata as unavailable evidence rather than a miss.

At the end, the runner passes a welcome-mail expectation after the fixture application's
message appears, ignores a matching pre-baseline message, and ignores mail for another
run token. Verify with `nix develop --command just test-email` before expanding variants.

### M2 — Make coverage, isolation, bounds, and reports trustworthy


Observation handlers contribute `SendHttp` and `ReadState`, declare their source and
`RequiresBusinessKey`, and advertise `SampledState`. `ObservedWithDetails` contains stable
occurrence IDs and only public counts/flags or fixed choices, such as provider, page count,
and operation kind. Produce one occurrence per distinct provider message ID and retain
fresh matching evidence for overlapping polls without multiplying repeated IDs. Serialize
access to any shared mutable reader/cache state, honor cancellation while waiting for it,
and never share state across independent run acquisitions. Include source/account/query
descriptor checks before capture and observation, as existing adapters do.

Read every required list page within explicit bounds; reject repeated cursors, empty pages
with `has_more`, malformed bodies, or exhausted page/detail/byte budgets. Baseline failure
prevents actions. An incomplete poll returns `ObservationUnavailable`, even if one partial
page contained a candidate: the initial implementation favors a simple conservative
contract over mixing partial witnesses with incomplete scans. A complete sample with no
match is a conclusive sampled non-match. Report each complete scan as
`Coverage SampledState pollStart pollFinish True`, with both times read from `callClock`
and `pollFinish` no later than the time the batch is returned. Thus an `eventually`
deadline with only successful non-matching samples returns Fail. Any one unavailable poll
before the cutoff makes the result Unknown, unless a later poll finds a match and Passes.
Neither outcome claims continuous absence. Do not set durable coverage or invent a new
runner result schema. `never` and `exactlyOnce` cannot succeed without durable coverage;
tests must show Unknown when no decisive violating witness exists.

Apply the smaller of remaining call deadline and request limit to every request and the
entire scan. Preserve asynchronous cancellation, do not spend cleanup time on observation,
and close response sockets on overflow, decoding failure, timeout, and cancellation. Keep
verified TLS and disable redirects, ambient proxies, automatic connection retries, and
idle connections. A 401/403, 429, 5xx, malformed reply, missing detail, or timeout is
unavailability. Do not sleep through `Retry-After`; later runner polls provide bounded
read retries. Production requests use the fixed approved Resend origin; tests may inject
an explicit loopback origin through a private transport seam, never a runtime message URL.

Typed text, HTML, headers, subject, recipients, and attachment metadata exist only in memory
for context-owned decoders/predicates, with no automatic `Show` or JSON rendering. Decode
required fields strictly and tolerate unrelated additive provider fields. Attach fixed
sanitized failure codes, never raw exceptions or provider error messages. Predicate and
source labels must be logical public names. Test sentinels in secrets, addresses, content,
headers, URLs, filenames, and errors against encoded reports and captured stdout/stderr.
Also assert public resolved correlations contain tokens rather than addresses.

M2 passes when the fixture contract suite exercises policy denial before allocation,
correlation failure before requests, source-descriptor mismatch, page/detail limits,
unavailable-source controls, cutoff behavior, concurrent runs, composed repeated semantic
keys, cancellation, and private reporting. Existing HTTP checks must still pass.

### M3 — Send controlled inputs and distinguish acceptance from receipt


Add non-renderable `EmailPayload`, opaque `EmailSubmission`, a pure send descriptor, and
`emailActionHandler` alongside `emailObservationHandler`. Use the provider abstraction
already exercised by receiving; implement Resend `POST /emails` with JSON encoding and an
`Idempotency-Key` HTTP header. The payload supports a controlled sender, direct recipients,
subject, text and/or HTML. Attachment bodies, CC/Bcc, arbitrary transport headers,
scheduling, and template APIs remain outside this first version. Limits apply to outgoing
body bytes as well as responses. Reject invalid addresses and control characters before IO.

The handler contract always adds `SendHttp`, `WriteState`, and `ExternalSideEffect`;
synthetic allocation uses `SyntheticResource` wherever the scenario actually creates such
resources and remains subject to the existing per-run consent rule. The pure descriptor
fixes allowed sender identities and approved recipient destinations; every payload is
checked against them before sending. Domain approval is an explicit policy input, not a
consequence of a staging label. Check acquired and declared descriptors as for reads.

Require an explicit opaque idempotency key derived by the context from a fresh run-owned
token and a stable action identifier. Repeated submissions of the same logical action use
the same key and payload; distinct action instances use distinct keys. The payload builder
is deterministic for a logical action, not a source of fresh keys per attempt. Enforce
Resend's 256-character limit and reject line breaks. The adapter makes one POST attempt
only. A timeout after possible acceptance returns `ActionUnavailable`; it does not generate
a new key, resend, or pretend the mail was rejected. Provider configuration/authentication,
rate-limit, transport, and decode failures also remain unavailable. Only a well-formed
successful provider acceptance returns the `accepted` outcome tag and private submission
ID. Do not classify arbitrary provider errors as expected business rejections.

Extend the HTTP fixture with a send log and an idempotency table: acceptance and arrival
are separate fixture operations, so accepted-but-undelivered mail cannot pass a receipt
expectation. Demonstrate send followed by independent receiving through the public runner,
and a controlled inbound-workflow fixture where input mail results in a ticket/state
observation. Assert denied effects and forbidden destinations produce zero POSTs, and a
timeout after fixture acceptance still produces just one POST. Test repeated identical
keys/payloads and conflicting payloads directly against the fixture without attributing
the fixture's deduplication behavior to a live provider test. M3 is accepted by the same
`just test-email` command with both observation-only and sending scenarios passing.

### M4 — Integrate checks, documentation, and an explicit live path


Wire `test-email` into `just check` and the adapter `checkPhase` in `flake.module.nix`, with
`scripts/test-email --binaries dist/build` using the already compiled suite and packaged
fixture. Keep the runner independent of PostgreSQL and Kafka so email checks are focused
and cheap. Ordinary checks use loopback only and need no Resend key or external delivery.
Update Cabal module/fixture packaging and run existing core/HTTP checks after integration.

Document acquisition, pure handler construction, token-to-recipient correlation, sampled
semantics, allowed sending effects, and private content decoding in `docs/adapters.md`.
Add `docs/workflows/email-verification.md` with a compiling context-owned example, required
test account and recipient controls, and baseline/scan sizing. The sizing section must
state that the retained received count has to stay within `pageSize × maxPages`, or every
run ends Unknown at baseline. Also cover retention disposition and how
to distinguish acceptance from receipt. Explicitly document that an observation predicate
cannot feed an OTP into a later action under the current runner. Update `README.md`,
`docs/development.md`, and `docs/dependencies.md` only for implemented surfaces and checks.
The general workflow-manifest schema is not expanded: native host bindings accept the
typed email adapter directly. Any later staging contract extension needs its own concrete
consumer requirements.

Add `shoko-adapters/example/EmailSmoke.hs` as the `shoko-email-smoke` Cabal executable,
using a small context-owned vocabulary and the public runner for submission and receipt.
Add `shoko-adapters/example/EmailSmoke/Config.hs` for the example host's typed Settei
declarations and source resolution, with executable-only dependencies on the already
workspace-pinned Settei packages: `settei ==0.2.0.0`, `settei-env ==0.2.0.0`, and
`settei-yaml ==0.2.0.0`, matching `shoko-cli/shoko-cli.cabal` and the `cabal.project`
constraints. The `shoko-adapters` package derivation gains these build inputs, but its
library does not. Keep Settei out of the adapter library and core. `shoko-cli` does not
depend on `shoko-adapters`, and the adapter package must not depend on `shoko-cli`. So copy,
rather than import, the declaration, environment-binding, and Secret patterns from
`shoko-cli/src/Shoko/Cli/Config.hs`. This work requires no Settei upgrade.

The host resolves provider selection, account/source labels, recipient domain/prefix,
page/detail/byte bounds, and request/run/poll budgets through Settei before constructing
adapter descriptors. Credential settings contain environment-variable references, never
raw API keys in YAML or command-line arguments. For sending, private sender-address
values follow the same protected-value path so configuration provenance cannot expose
mailbox addresses. Ordinary settings use declared defaults, then one explicit
`--config` file when supplied, then explicitly bound operational environment variables, in
that precedence order. There are no Settei command-line overrides. Reject unknown configuration keys, invalid winning
values, missing required fields, and empty credentials without falling back. Validate
relationships such as request limits fitting within execution budgets before acquisition.
Settei resolves operational values; approved destinations, capability grants, and synthetic
consent remain governed by host policy and cannot be widened by operational overrides.

Inspection resolves declarations and credential reference names without reading secret
values or contacting Resend. After successful policy preflight, resolve only the API keys
and private values needed by the selected operations through separate Settei Secret
declarations, then construct the acquired reader. Receiving-only scenarios must not
require sender settings. Pass validated values into the adapter explicitly. The Python
wrapper delegates configuration resolution to this Haskell host and never implements a
parallel environment/config parser.

Provide `scripts/smoke-email` as a separately invoked Python wrapper which locates that
executable through `cabal list-bin exe:shoko-email-smoke` and delegates without printing
inputs. Define its input contract in the new guide. These are the default names of the
environment variables that the credential and private-value references point to.
Configuration may rename a reference but never holds a value. `SHOKO_EMAIL_RESEND_API_KEY`
is a secret. `SHOKO_EMAIL_SENDER` is an already approved and verified sender.
`SHOKO_EMAIL_RECEIVING_DOMAIN` is an approved receiving test domain. All three are resolved
through Secret declarations after preflight, and receiving-only runs skip the sender. Use a 30-second
execution budget, a 20-second receipt window, 1-second polling, and 3-second request limits
as finite smoke defaults, validated if the host exposes overrides. These values are test
budgets, not provider delivery promises. A new random token supplies the run's recipient
and correlation. The smoke command sends one message and waits for independently observed
receipt; reports contain only public tokens and safe summaries. Missing inputs fail with a
fixed diagnostic and nonzero exit; they never skip to success. It must not provision DNS,
create provider accounts, delete mail, or substitute Resend's simulated delivery addresses
for a real receiving inbox. Keep this outside CI and run it only with session authorization
and supplied live inputs. No such inputs were supplied when this plan was created.

Add an implemented capability record under `docs/capabilities/` using the next available
handle printed by
`okf id next docs/capabilities CAP --profile docs/capabilities/profile.dhall`, not a guessed
CAP number. At review time it printed `CAP-12`; rerun it, because another plan may claim it
first. Add the row to `docs/capabilities/index.md`. Preserve its profile and log convention
and cite actual consumer evidence. Update `mori.dhall` package descriptions and doc entries
if appropriate without claiming a Resend SDK dependency. Record durable adapter boundaries
and coverage decisions in a new local ADR or relevant existing ADRs. M4 acceptance requires
local and native fixture checks, documentation validation, and an executable tested smoke
path; an actual external smoke result is recorded separately and remains pending until
credentials and authorization exist. Plan completion establishes the adapter contract,
not live Resend account readiness or deployed workflow acceptance.


## Concrete Steps

Run commands from the repository root `/Users/shinzui/Keikaku/bokuno/shoko`. Before using a
dependency API, use Mori to locate its registered source/docs and read the relevant public
definitions. Resend has no local registry entry as of creation; its authoritative HTTP
documentation above is the source for this integration. The existing HTTP dependencies
suffice; this plan chooses no new version bounds or pins. If implementation needs one,
verify the current release against Hackage and upstream release tags before selecting it.

```bash
mori registry search http-client
mori registry show snoyberg/http-client --full
mori registry docs snoyberg/http-client
nix develop --command cabal build shoko-adapters
```

After M1 creates the new suite and command, develop and accept milestones with:

```bash
nix develop --command just test-email
nix develop --command cabal test shoko-core-test --test-show-details=direct
nix develop --command just test-adapters
```

`test-email` must exit 0 only after actual loopback requests and public-runner checks pass.
Its final summary should identify bounded receiving and controlled sending fixture
acceptance. During M1/M2, label the summary receiving-only until sending is implemented.
Fixture startup failure, a failed control, or a missing binary exits nonzero.

At M4, validate the native build and documentation:

```bash
nix build .#checks.aarch64-darwin.shoko-adapters
just check-docs
git diff --check
```

Use the native system's corresponding check attribute on Linux. Run the complete
`nix develop --command just check` once at integration when the workspace's other adapter
prerequisites are available; identify unrelated failures rather than weakening those checks
or treating them as email acceptance. No live credentials are needed for these commands.

Only when live inputs and session authorization are present, invoke the new path from the
same directory, with secret values already set privately in the environment:

```bash
nix develop --command cabal build exe:shoko-email-smoke
nix develop --command python3 scripts/smoke-email --allow-synthetic
```

The guide documents the environment variables named in M4 and the command must report Pass
only after a message arrives. Keep raw payloads, credentials, and actual mailbox addresses out
of saved transcripts. Do not run this live command as part of plan creation.


## Validation and Acceptance

The M1 producer/consumer proof is required early: a context-owned action triggers the
fixture application, the new adapter lists and fetches the resulting mail over HTTP, and
the core runner evaluates the decoded expectation. This catches integration mistakes in
baseline timing, inputs, source registration, and HTTP decoding before variants accumulate.

For receiving, seed an old welcome message before baseline, then create a fresh one for
token A during the action. Only the fresh message can Pass. Add a message for token B and
ensure A cannot consume it. Include candidates appearing during the action, repeated IDs
across pages/polls, nullable text/HTML, and attachment metadata. A content mismatch with
otherwise conclusive samples produces Fail at the sampled deadline; a source failure or
limit breach that prevents a conclusion produces Unknown. An unsuccessful baseline leaves
the fixture application's mutation counter at zero. One fixture-injected 429 followed by
conclusive non-matching polls ends Unknown, not Fail. Repeated runs use fresh resources
and tokens; composed correlations using the same semantic key still select separate mail.

For evidence limits, `never` over an empty inbox and `exactlyOnce` over one received message
return Unknown because this source advertises sampled coverage. `exactlyOnce` over two
distinct matching messages also returns Unknown, because the runner does not accumulate
sampled IDs. Assert this explicitly so that a later core change shows up as a deliberate
test update. A `never` expectation with a matching message observed by the cutoff Fails. Exercise positive reads completing after cutoff and cancellation
of a blocked request using controlled clock tests where possible and actual HTTP delay
tests for socket cleanup. Responses exceeding configured limits never become successful
non-matches. Detail/list disagreement, missing identity, authorization failure, 429,
malformed JSON, cursor loops, and truncated scans all remain inconclusive.

For sending, verify allowed destinations yield one accepted submission with an opaque
provider ID. A successful POST without arrival cannot satisfy receiving. A timed-out POST
after server acceptance yields Unknown and exactly one observed send attempt. Different
logical sends use distinct keys; repeated identical logical submissions use the same key.
Denied capabilities, mismatched descriptors, missing correlation, or unapproved recipients
cause zero prohibited requests. A context-owned inbound-ticket example demonstrates why
sending is an action rather than a substitute for observing application output.

Secret sentinel checks inspect encoded results and process streams for content, address,
credential, header, URL, attachment-name, and raw-exception leaks. Intentionally place
sentinels in provider errors as well as successful payloads. Inspection must work without
secrets and with allocation/request counters at zero. Test the smoke wrapper's missing
input failure and executable delegation with a test-owned stand-in executable; the earlier
real-HTTP scenarios already prove provider transport and runner integration. Exercise the
smoke scenario definition against the loopback provider through a shared consumer helper
with injected acquired reader construction. Keep that test injection outside production
environment/CLI settings; never claim fixture acceptance proves external delivery. Preserve
current result schemas and HTTP adapter behavior.

Exercise the email host's Settei declarations with missing/empty API keys, invalid bounds,
unknown keys, and invalid winning overrides. Verify documented source precedence,
required-setting differences between receiving-only and sending scenarios, and redacted
configuration diagnostics/provenance. Inspection and denied-policy execution must perform
zero credential-value lookups and zero provider requests. Invalid operational configuration
is a preflight/configuration error, not an unavailable inbox result. Run these checks in
the email suite with executable-component Settei dependencies where necessary; adapter
library consumers still receive plain typed configuration.

Completion requires the four milestone outcomes, green focused email/core/HTTP and native
email checks, and valid documentation/catalog updates. Record external smoke evidence if
available, otherwise explicitly state that live provider acceptance and real application
staging verification remain untested. Adding durable coverage, OTP-as-input actions, more
providers, or webhook infrastructure is a scope extension, not a reason to silently widen
these acceptance criteria.


## Idempotence and Recovery

The loopback fixture runner owns a temporary directory, dynamically selected loopback
port, child process, and synthetic account data. It must stop only its own process and
remove only its owned temporary files on success, failure, and interruption. Repeated
checks create fresh tokens and cannot access external inboxes. Never reset or delete
mail in an existing provider account as test setup or cleanup.

Readers are acquired per run. Baseline tokens refer to that run's in-memory state and are
not persistent replay cursors. On a baseline failure, no application action runs; create a
fresh run after correcting credentials or bounds. Never resume a later action by reusing
an unproven baseline. Configuration changes require a fresh acquired reader and compatible
pure handler descriptor.

An uncertain live send might already have produced mail. Preserve the original key and
payload for operator investigation; do not automatically repeat the scenario or make a
new key for the same action. A new intentional run receives a new token and is a new
external effect. Resend's 24-hour deduplication expiry is not a permanent recovery record.
Retain test messages under an explicit owner-agreed provider retention policy, with reader
finalization releasing only local resources. A host must represent that retained
disposition honestly; no mail deletion privilege is required by this adapter.


## Interfaces and Dependencies

`Shoko.Adapter.Email` owns provider-neutral opaque types for the inbox description,
`EmailReader`, `ReceivedEmail`, `EmailPayload`, `EmailSubmission`, and send description.
It exports pure constructors returning validated descriptors and handler helpers shaped
like the existing adapter helpers: an observation helper returns
`Either HandlerBuildError (Handler EmailReader a)` from a descriptor, typed token input,
and context decoder; a sending helper returns a handler from a pure send descriptor and
an effectful payload builder using `resolveInput`. The source belongs to the observation
handler, not a separately invented host source table. Use existing typed construction
causes where they are meaningful; if a new cause is unavoidable, update the closed result
codec, schema, and tests together instead of smuggling private diagnostics into it.

`Shoko.Adapter.Email.Internal` owns the small provider interface: bounded page listing,
detail retrieval, and one-attempt submission, all constrained by the active call deadline.
Both production Resend and the controlled tests consume the same neutral message model.
Keep this interface private until another real provider needs a public extension contract.
It is not a general mail client framework. `Shoko.Adapter.Email.Resend` owns the Resend
request/response mapping, credentials, fixed origin, and acquired transport. Pure descriptor
construction and inspection do not allocate a manager or resolve credentials. A compiled
host resolves required secrets through its existing configuration boundary before acquiring
the run's reader; no email-specific global CLI parser is required.

Configuration belongs to the consuming host and uses
[Settei](mori://shinzui/settei/packages/settei), its
[environment source](mori://shinzui/settei/packages/settei-env), and, for an explicit config
file, its [YAML source](mori://shinzui/settei/packages/settei-yaml). The inspected dependency
source is `mori://shinzui/settei`, project-relative `settei/src/Settei/Setting.hs` and
`settei-env/src/Settei/Env.hs`; artifact-level URIs are pending. These provide explicit
public/Secret setting metadata and environment bindings. Reuse the workspace's current
Settei pins and only APIs already used by `Shoko.Cli.Config`; newer corpus-only features
are not prerequisites. `EmailSmoke.Config` owns the example declaration and safe resolution
reports. A context-owned host may compose equivalent declarations into its own startup.
Neither `Shoko.Adapter.Email` nor `Shoko.Adapter.Email.Resend` imports Settei or performs
ambient configuration discovery.

The library reuses existing `aeson`, `bytestring`, `containers`, `text`, `time`,
`http-client`, `http-client-tls`, and `http-types` dependencies. Fresh run tokens and
baseline handles use the already-declared `uuid` package (`Data.UUID.V4.nextRandom`). The HTTP client was located through Mori
as [mori://snoyberg/http-client/packages/http-client](mori://snoyberg/http-client/packages/http-client).
Its public API defines scoped responses, manager retry policy, proxy overrides, and idle
connection settings. For source lookup, the owning project is
`mori://snoyberg/http-client`, with project-relative
`http-client/http-client/Network/HTTP/Client.hs` and
`http-client/http-client/Network/HTTP/Client/Manager.hs`; artifact-level URIs are pending.
These paths were inspected during creation. Use the registry's current location rather
than assuming the same absolute corpus path on another machine. No SDK release or
compatibility workaround is selected by this plan.

This work uses the existing public core handler/correlation contracts and has no hard
dependency on the unfinished Kafka adapter or registration staging plan. Preserve the
existing permission and result vocabularies unless implementation demonstrates a necessary
compatible change. Before marking this plan complete, distill durable email policy,
privacy, listing scope, and sampled-coverage decisions into the local ADR corpus and keep
the plan's living sections accurate. Any implementation commit includes the local
`ExecPlan:` trailer for this file and the `Intention:` trailer from its frontmatter, using
Conventional Commits on the current branch.

Revision 2026-10-23: make Settei ownership explicit for all email settings, deferred API
keys, and the smoke host; add configuration precedence, redaction, validation, and
receiving-only credential checks while preserving the adapter's typed boundary.

Revision 2026-10-23 (review against the working tree and Resend docs): correct the
`exactlyOnce` claim (sampled IDs are not accumulated, so it is always Unknown). Make the
public `Baseline.cursor`, the sticky gap rule, and the coverage construction explicit. Name
full test paths and fixture packaging. Record the Inboxes API and the retention-sizing
limit of full listing scans. Drop smoke command-line overrides, and pin the Settei build
inputs. Give the exact `okf id next` command, and cite ADR 0005.
