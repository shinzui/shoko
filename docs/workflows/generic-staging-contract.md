# Generic staging workflow contract v2

`schemas/workflow-v2.schema.json` generalizes declaration and read-only readiness
without changing the registration v1 schema, validator or `workflow-env` command.
`shoko-workflow validate --structure-only` accepts either version and reports
`liveReadinessChecked: false`, including for pending prerequisites or a labelled
synthetic example. It performs no credential lookup or target call. The existing
v1 command retains its original stricter pending/synthetic behavior.

```bash
nix run .#shoko-workflow -- validate --manifest integration/examples/notification-workflow.example.json --structure-only
nix run .#shoko-workflow -- check --manifest /path/to/approved/workflow.json --artifacts /private/qa/observations
nix run .#shoko-workflow -- observe --manifest /path/to/approved/workflow.json --artifacts /private/qa/observations
```

V2 declares workflow/scenario identities and revisions, canonical owners and
participants, fixture/cleanup recipes, permitted actions, requirements mapped to
expectations and evidence strength, explicit exclusions, an immutable host identity
before execution, and a target. Workflow-specific prerequisite sets belong in
the manifest. Registration keeps OTP/completion requirements in its v1 declaration;
the generic v2 validator has no registration or notification requirement set.

Each positive and negative wrapper declares its own scenario revision. Semantic
business-key names retain their domain spelling, such as `notificationId`; they
are not normalized into catalog ID slugs.

Targets name context, cluster, credential-free HTTPS API server, namespace and
namespace UID. Every ready workload declares its UID and each named application
and init container's exact template reference and expected runtime digest. Pending
workloads/endpoints carry explicit reasons and cannot clear readiness. Unknown
endpoint addresses are `null`, not invented examples. HTTP Service endpoints
declare service UID and workload associations; external endpoints cite owner
evidence. A digest observed in a pod is not automatically an accepted expected pin:
the consumer must reconcile it with infrastructure and obtain the owner's stable
window/identity acceptance. Source revisions remain null without digest provenance.

Prerequisites have owner, status, reason and clearing check. Confirmation requires
a canonical evidence reference and expiry. This is an explicit owner declaration,
not independent verification of its source document. Consumers must check the
owner evidence before confirming it. Credential presence alone confirms nothing.
Pending, expired, incomplete or synthetic contracts return blockers before any
Kubernetes or HTTP call; no real fixture data is created by this command.

Both `check` and `observe` call the same gate and emit the same artifact protocol,
`schemas/target-observation-v1.schema.json`. Explicit Kubernetes reads verify TLS,
namespace/controller identity, rollout, pod readiness and controller ownership,
all application/init/restartable-sidecar template/runtime image identities,
Service selectors and ready EndpointSlice membership, and literal public endpoint
configuration checks. Before/after snapshots must match. ConfigMap/Secret-backed
runtime environment values are not inferred from their current source; unsupported
public config checks block. No Secret, log, exec, write or deployment API is used.

Declared HTTP readiness probes issue GET only, disable redirects/proxies and TLS
bypass, bound the body to 64 KiB, and discard it. One optional bearer reference
is resolved inside an owned child; values never enter arguments or diagnostics.
The entire request, including a slow header/body stream, has a finite process
deadline. Kubernetes uses the existing bounded reader (4 MiB per response,
15-second child limit and explicit API request timeout); the total gate budget is
60 seconds. Cancellation reaps verifier-owned processes. Targets are limited to
32 workloads, 64 pods per workload, and 32 probes.

Readiness means these configured checks plus the nonexpired owner prerequisites.
It does not independently certify domain fixtures, prove provider absence over an
interval, or establish business success. The consumer must declare the probes
and owner evidence needed for its domain readiness; an omitted check is not an
observed fact. Before/after agreement does not prove continuous deployment stability.

The private artifact retains only contract hash, workflow/time, public blocker
codes, observed UIDs/generations/runtime digests and successful check IDs. It omits
API/endpoint addresses, kubeconfig, raw objects, credential values, response bodies
and transport errors. Each observation is fresh; its private directory is 0700 and
file is 0600. A past artifact is evidence, never a pass token. Host callbacks and
suite wrappers must invoke `observe` again before acquisition/execution.

Exits: 0 structural validity or contracted readiness; 2 input/prerequisite/target
blocker; 4 observation-protocol/persistence fault or interruption. No mode emits
a Shoko workflow Pass. The fake-cluster and loopback-HTTP process gates live in
`scripts/test-workflow-v2`; old registration tests remain unchanged. Actual
notification-host and suite-executor integration is still an acceptance task for
the consumer of `mori://tan/tan-platform-qa/plans/2-establish-the-staging-workflow-contract-and-live-readiness-gate`.
