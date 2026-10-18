# First staging workflow: registration completion

The selected workflow completes registration for an already-qualified agent and
checks real registration, account, user, and account/user-association outcomes.
Qualification and other registration flows are excluded. The target is an existing
Kubernetes staging deployment. Its concrete access contract is still pending;
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
credentials, or submits a workflow. Live `check` and `smoke` are reserved interfaces
and currently fail with an unavailable message even for a valid manifest.
Their actual access and independent workflow implementations remain EP-2 work.

## Inputs needed to finish the contract

The environment owner must supply the approved context, cluster name and API
server, namespace and namespace UID, actual workloads and their UIDs/immutable
image digests, access route, and action/evidence endpoints. Each endpoint needs
an explicit association with the approved deployment, including external
databases. Historical values from another task are discovery context, not approval
to select a cluster or use an endpoint.

The domain owner must supply a supported fresh qualified-agent recipe, approved
controlled-recipient references and external effects, repeatable bounded OTP
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
history or exactly-once delivery. Durable history selects `message-db` or
`kiroku` and therefore adds the corresponding EP-5 acceptance gate.

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
negative case. Store future run artifacts under an ignored, run-specific
directory once the access implementation defines it. No such artifacts or
retention acceptance are claimed by the offline tests.

See [EP-2](../plans/2-establish-the-first-workflow-contract-and-composed-local-environments.md)
and [ADR 0004](../adr/0004-gate-parity-on-real-workflows-and-context-owned-vocabulary.md).
