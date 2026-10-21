# First staging workflow: registration completion

The selected workflow completes registration for an already-qualified agent and
checks real registration, account, user, and account/user-association outcomes.
Qualification and other registration flows are excluded. The target is an existing
Kubernetes staging deployment: the user identified cluster `sennari`, namespace
`test`, on 2026-10-18. Its complete access/workflow contract is still pending;
no staging readiness or workflow acceptance has been established.

The local contract tooling is available now:

```bash
nix develop --command just test-workflow-contract
nix develop --command just workflow-validate
nix develop --command just workflow-check
nix develop --command just workflow-smoke
```

`test-workflow-contract` runs offline schema, relationship, and process checks.
The other commands explicitly select `integration/workflow.json`. That file is
intentionally absent until the environment owner supplies the target contract.
They exit 2 for a missing/invalid manifest or pending prerequisite. `validate`
can establish structural validity only; it never contacts Kubernetes, resolves
credentials, or submits a workflow. `check` now implements read-only Kubernetes
identity discovery for an explicit, confirmed contract. Full readiness and the
independent `smoke` workflow remain unfinished EP-2 work. The environment/domain
owners confirmed on 2026-10-18 that the concrete inputs are still being prepared.

## Target discovery checkpoint

After the user identified `sennari` / `test`, read-only discovery on 2026-10-18
confirmed that the existing `sennari` context maps to kubeconfig cluster
`gke_tan-cluster_us-west1-a_sennari` and can access namespace `test`. The
[application infrastructure](mori://tan/tan-app-infrastructure/packages/registration-service-v2)
provides the current registration deployment and Service definitions.

Four named Deployments were observed: `registration-service-v2-server`,
`registration-service-v2-worker`, `registration-service-v2-kafka-consumer`, and
`registration-service-v2-pgmq-worker`. Each reported one ready replica. Their
application templates and the selected pods' application image IDs shared digest
`32328d77b5795fb965b0f541339bba8cd16cab1ba1574164e2ba22a70cf83398`.
The API Service `registration-service-v2-server` is `ClusterIP`, exposing HTTP
port 80 to container port 10001; this alone does not establish a route from the
verification host.

The full inventory also found native init-sidecars: Cloud SQL Proxy is configured
by a version tag, and the worker/Kafka consumer additionally use a Kafka auth
sidecar with a `latest` tag. The integration contract now separates optional
`templateImages` (the exact configured refs, including tags) from `imageDigests`
(expected runtime digests for all containers). When `templateImages` is absent,
it defaults to `imageDigests`. This represents the deployment without omitting
sidecars or changing application resources. Pinned template refs must also have
runtime digest expectations. The identity-only check compares template refs;
runtime image verification and pod/controller ownership remain explicit readiness
obligations, even when the template references match.

An ignored private `.shoko/runs/<uuid>/target-discovery.json` records the API
server, namespace/workload UIDs, generations, complete template image references,
Service metadata, and selected pod runtime image IDs. Two namespace/workload
observations matched during discovery. This artifact is labelled target discovery
and readiness unverified; pod selection by label is not verified controller
ownership or a stable-window guarantee. No workflow actions, OTP requests,
Secret resource reads, or workload mutations occurred.

## Read-only identity discovery

After the owners supply the real manifest and confirm its prerequisites, run:

```bash
nix develop --command python3 scripts/workflow-env check --identity-only
```

This requires an installed `kubectl` compatible with the approved cluster and
its documented authentication/access route. The tool does not install a client,
open tunnels, select an ambient current context, or change kubeconfig. It uses
an explicit context and namespace on every command, checks the minified local
configuration's cluster name and HTTPS server before any API request, rejects
disabled TLS verification, and pins the server on each GET. Only the approved
namespace object and individually named workloads are requested. A mismatch or
missing identity stops discovery. The implementation follows the official
[`config view`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_config/kubectl_config_view/)
and [`get`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_get/)
interfaces; it never requests secrets or logs.

Two observations compare namespace/workload UIDs, controller generations, and
the exact set of image references in container and init-container templates. Changes
between the observations block the identity check. These are controller template
images, not running pod image IDs, rollout readiness, source revision provenance,
or proof of continuous deployment stability. Runtime images and the deployment
owner's stable window still require verification before acceptance.

`--identity-only` exits 0 only for matching identity observations; its message
and artifact still say full readiness is blocked. Plain `check` always exits 2
until runtime image identity, endpoint authorization/connectivity, evidence access,
and permitted domain test setup have live checks. `smoke` still exits 2 without calls. Neither command
can turn a declaration or identity match into workflow acceptance.

Each attempted identity discovery creates
`.shoko/runs/<fresh-uuid>/identity.json` (ignored by Git), or a fresh directory
under `--artifacts <parent>`. The directory is private (0700) and the file is
0600. The record includes the exact manifest's SHA-256, check time, separate
identity/readiness statuses, stable blocker codes, and allowlisted before/after
identity fields. Raw kubeconfig, resource responses, process errors, environment
values, endpoint credentials, payloads, and unexpected mismatching identities
are not retained. Artifact write failure is a failing command. Missing/invalid
manifests, synthetic examples, and pending prerequisites prevent all Kubernetes
calls and create no identity artifact. Discovery has a 60-second overall budget,
10-second API request timeouts, a 15-second process cap, and a 4 MiB response cap;
timeout cleanup kills the owned command group, including credential-plugin children.

## Inputs needed to finish the contract

### Qualified-agent database discovery

On 2026-10-18 the user supplied read access to the MLS staging database:

```bash
PGCONNECT_TIMEOUT=10 \
PGOPTIONS='-c default_transaction_read_only=on -c statement_timeout=10000 -c lock_timeout=2000' \
psql -X -w -v ON_ERROR_STOP=1 \
  -U claude \
  -h /tmp/tan-ng:us-west1:stage-master-database \
  -d mls-service-v2
```

The connection succeeded and reported `transaction_read_only=on`. This identifies
an available MLS read route; it does not establish the connection targets for
registration, account or user evidence, or authorize database writes. The supplied
socket was already available; no proxy or infrastructure changes were made.

The qualified-agent read model is `mls_service_read.qualified_agents`. Schema and
aggregate-only queries observed 127 rows, of which 122 had null `tan_account_id`,
`tan_user_id`, and `tan_registered_at`. Among those, 119 also had nonblank manual
first/last names and email, and 14 of those had a nonblank override phone. These
are point-in-time discovery counts, not certified eligible or approved fixtures.
No agent IDs, names, emails, phone numbers, notes, or payloads were selected into
reports, and no records were changed.

The [MLS core package](mori://tan/mls-service-v2/packages/mls-service-v2), inspected
at revision `42aaa82ee64d93ebf8e33d02dafb8fcf76e4a9d9`, reads this table and
joins member phone fields from `mls_service_read.members`. Its project-relative
`mls-service-v2-core/src/MlsService/Repository/Tables/QualifiedAgent.hs`
(artifact-level URI pending) shows that registration state, manual contacts,
and linked member contacts are distinct. Nonblank manual fields are only a
discovery filter; actual API payload validation remains necessary.

The [registration implementation](mori://tan/registration-service-v2) at revision
`6cd07aa8b9f032fc850fed4b2ba1022537da8c91`, project-relative
`registration-service-v2/src/RegistrationServiceV2/Api/Handlers/FromQualifiedAgent.hs`
(artifact-level URI pending), rejects already-registered or incomplete MLS
payloads and requires an on-file QA email for this specific route. It also claims
a QA for a registration and can resume the existing holder. Therefore, a row with
null MLS registration markers does not prove it is fresh or reusable for two
isolated runs. Identify test-owned agents and approved on-file recipients, check
their actual API/claim state, and establish automated OTP retrieval before use.

### Remaining owner inputs

The user selected fresh QA creation for the test fixture on 2026-10-18. Use the
supported `POST /v1/qualified-agents/no-mls-member` endpoint on the MLS service,
with a unique synthetic `mlsMemberId` per run/scenario and an ownership note
containing the run identifier. This creates the qualified precondition; it does
not add qualification behavior to the registration slice's claimed coverage.
Supply the configured real staging chapter, automation/admin identity,
`qualifiedAt`, `overrideReason: {"type":"NoMlsMember"}`, synthetic names/brokerage,
and the controlled on-file email. Do not reuse arbitrary existing agent rows or
insert directly into the read model. The endpoint mints the QA ID and reserves
its member/chapter natural key; a conflict or ambiguous timeout requires
inspection of that key, not blind POST retries. Its optimistic creation response
must be followed by bounded read-model/API visibility checks.

The MLS `ClusterIP` Service `mls-service-v2` exposes port 80 to 10001. An explicitly
targeted, verifier-owned loopback-only port-forward successfully reached
`GET /v1/qualified-agents/invalid`, which returned the source-documented 400
`Invalid qualified agent ID format`; the tunnel was then stopped. This proves
an available MLS access route, not successful creation or registration. No QA
has been created yet because its controlled on-file recipient and OTP retrieval
route remain unspecified. No application deployment was changed.

The registration Deployment explicitly declares `RS2_OTP_TARGET_POLICY=allowlist`.
The inspected template did not explicitly declare `OTP_SERVICE_STUB` or
`RS2_COMPLETION_ACL_STUB`, and imports a Twilio Secret through `envFrom`. No Secret
values were read; effective OTP/completion mode and an automated code retrieval
facility are therefore still unverified. Do not infer stub behavior from the
test namespace or use a fake on-file email as if it could complete real OTP.

The cluster and namespace names are now supplied, and discovery has observed the
context/API server, namespace UID, and registration workload identities. The
environment owner must still establish the complete accepted identity/image
contract, access route, and action/evidence endpoints. Each endpoint needs
an explicit association with the approved deployment, including external
databases. Historical values from another task are discovery context, not approval
to select a cluster or use an endpoint.

The MLS read route, qualified-agent table and supported fresh-QA creation route
are now known. The remaining fixture configuration includes a valid staging
chapter/automation identity, approved controlled-recipient references and external
effects, repeatable bounded OTP
retrieval, the deployed completion mode, and scoped reads proving actual account
and user writes and association. Confirm one precise negative response contract
and its downstream invariant independently. A generic HTTP error does not prove
that contract. Record the cleanup API or bounded retention period and owner, and
the deployment owner's stable test window. Credential fields contain environment
variable names only. Keep credential values, recipient details, fixture payloads,
OTP values, and verification SIDs out of the manifest and retained reports.

The required prerequisite IDs are `cluster-access`, `controlled-fixtures`,
`otp-path`, `real-completion`, `evidence-access`, `negative-contract`,
`endpoint-authorization`, `cleanup-retention`, and `stable-window`. Each record
has an owner, pending/confirmed status, reason, and the check that clears it.
Confirmation in the manifest is a declaration; M2 still needs live evidence.

## Contract format

[`schemas/workflow-v1.schema.json`](../../schemas/workflow-v1.schema.json)
defines a strict v1 contract. Every requirement has a stable ID, business
invariant, scenario/expectation pair, evidence source, and coverage strength.
Each positive/negative scenario must have its own ID; each negative scenario
needs both a rejection requirement and a downstream invariant. Sources and
actions resolve through explicitly declared endpoints. The validator rejects
unknown references, duplicate IDs, missing baseline requirements, contradictory
coverage, and undeclared adapters. A sampled row count cannot be labelled durable
history or exactly-once delivery. Durable history selects `message-db`,
`kiroku`, or `kafka` and therefore adds the corresponding reader's acceptance
gate. A `kafka` source must use a `kafka://host:port` endpoint naming one
credential-free bootstrap broker; the topic belongs to the context binding. The
Kafka reader's client binding is still pending (see the
[adapter guide](../adapters.md#kafka-topic-reader)), so a contract selecting it
cannot yet run live.
Durable sources also require `historyPolicy: append-only-during-run`, backed by
the source owner's exclusion of deletion, truncation, and rewriting during the
finite run. A store with active retention or a compacted topic cannot silently
claim complete history.

The host contract names its canonical owning project/package, project-relative
package directory, public module, executable, and build/invocation recipes.
`sourceRevision` can be null while its location is being agreed in M1; EP-7 must
record the actual immutable revision once the context-owned host is implemented.
Configured workload identities are expectations; future live identity records
must remain separate from these declarations.

[`integration/examples/workflow.example.json`](../../integration/examples/workflow.example.json)
is a synthetic format fixture with reserved `.invalid` endpoints, synthetic
identities, invented action paths, and pending prerequisites. Its intended host
package/location illustrates ownership only and does not assert that a host
exists. The `purpose: synthetic-example` marker makes the command reject it as
a staging contract. It must never be copied into use by merely changing that
marker or marking its prerequisites confirmed. Fill the actual contract from
verified owner inputs and current service definitions.

## Source-grounded workflow sequence

The owning project is [registration-service-v2](mori://tan/registration-service-v2).
Its [API package](mori://tan/registration-service-v2/packages/registration-service-v2-api)
was inspected at source revision `6cd07aa8b9f032fc850fed4b2ba1022537da8c91`.
The project-relative files
`registration-service-v2-api/src/RegistrationServiceV2/Api/Routes.hs` and
`registration-service-v2-api/src/RegistrationServiceV2/Api/Types/UserView.hs`
are source context (artifact-level URIs pending), not proof of deployed state.

Start with `POST /v1/registrations/from-qualified-agent`. Read
`GET /v1/registrations/{id}` for available OTP channels, submit
`POST /v1/registrations/{id}/otp/request`, and read the same registration for its
verification SID. Obtain the code through the approved automated facility and
submit `POST /v1/registrations/{id}/otp/verify`. Mutation acknowledgements do not
replace those state reads. Poll bounded reads for actual completion and check
the real downstream consequences by the correlated `registrationId`.

The historical manual reference is the same canonical project plus
`docs/plans/2026-07-17-flow-2-staging-validation-plan.md` (artifact-level URI
pending). It describes important test-identity and stub-mode pitfalls. Recheck
them against the actual deployment; neither that reference nor local defaults
establish its current OTP/completion mode or authorize its old access paths.

## Remaining acceptance

M1 requires a concrete positive/negative target contract accepted against the
schema and domain definitions. M2 then implements read-only discovery and
independent real smoke checks, retains sanitized before/after identities, and
demonstrates two positive runs with isolated business keys plus the documented
negative case. Identity discovery artifacts are separate from future workflow
acceptance envelopes. No live identity, workflow artifacts, or retention
acceptance are claimed by the offline tests.

See [EP-2](../plans/2-establish-the-first-workflow-contract-and-composed-local-environments.md)
and [ADR 0004](../adr/0004-gate-parity-on-real-workflows-and-context-owned-vocabulary.md).
# Workflow v2 compatibility

The registration v1 schema, `workflow-env` command and existing tests retain their
original behavior. New consumers use the [workflow-independent v2 contract](generic-staging-contract.md)
and packaged `shoko-workflow`; `validate --structure-only` also inspects v1 without
changing its declaration. V2 does not complete registration OTP/smoke readiness.
