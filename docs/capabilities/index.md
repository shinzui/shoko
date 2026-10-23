---
okf_version: "0.2"
---

# Shoko capabilities

Shoko provides typed workflow descriptions, bounded verification, evidence adapters,
and a compiled scenario host for application developers. These records describe
implemented surfaces in this experimental, unreleased repository. Each states its
consumer interface, evidence, and limits. They do not establish staging workflow acceptance.

Runtime permission grants such as `ReadState` have a separate meaning; see
[capability in the terminology catalog](../terminology/capability.md).

| ID | Capability | What it provides |
| --- | --- | --- |
| CAP-1 | [Inspectable typed scenarios](inspectable-typed-scenarios.md) | Define typed workflow scenarios and inspect their declared operations, dependencies, outcomes, and expectations without executing them. |
| CAP-2 | [Execution policy preflight](execution-policy-preflight.md) | Reject invalid bindings, denied permissions, unsupported correlation, production execution, and missing synthetic consent before acquiring scenario resources. |
| CAP-3 | [Bounded evidence verification](bounded-evidence-verification.md) | Execute scenarios with finite deadlines, correlated evidence, three temporal assertions, and bounded cleanup while preserving uncertain outcomes. |
| CAP-4 | [Versioned result contract with explicit public summaries](versioned-private-result-contract.md) | Encode and decode versioned verification results with explicit safe summaries, description identity, and partial evidence for faults. |
| CAP-5 | [Scoped PostgreSQL evidence](scoped-postgresql-evidence.md) | Observe business-key-scoped PostgreSQL state through typed parameterized queries and read-only transactions bounded by the remaining run budget. |
| CAP-6 | [Allowlisted HTTP operations](allowlisted-http-operations.md) | Perform declared HTTP actions and business-key-scoped GET observations with explicit domain decoding, finite limits, and safe evidence. |
| CAP-7 | [Bounded durable event evidence](bounded-durable-event-evidence.md) | Read correlated Kiroku or Message DB events in finite stream or category scopes without advancing application checkpoints. |
| CAP-8 | [Compiled scenario CLI hosts](compiled-scenario-cli-hosts.md) | Embed typed scenarios in a compiled CLI with inspection, policy checks, strict layered configuration, classified exits, and atomic JSON report output. |
| CAP-9 | [Offline staging workflow contract validation](offline-workflow-contract-validation.md) | Validate explicit staging workflow manifests for schema and relationship consistency before any target access. |
| CAP-10 | [Explicit Kubernetes target identity checks](explicit-kubernetes-target-identity.md) | Check declared Kubernetes namespace and workload identities twice through explicit read-only targeting and retain a sanitized private identity artifact. |
| CAP-11 | [Declarative scenario catalog inspection](declarative-scenario-catalog-inspection.md) | Validate ready and pending entries and delegate pure inspection to explicitly bound compiled hosts. |
| CAP-12 | [API-backed email evidence and controlled input](api-backed-email-evidence.md) | Observe new correlated mail through bounded Resend reads and send approved inputs with independent receipt. |

## Maintenance

The [profile](profile.dhall) selects
[mori://shinzui/okf-profiles/profiles/capabilities](mori://shinzui/okf-profiles/profiles/capabilities)
at frozen v0.21.0. Preserve CAP handles when updating claims. New claims need
existing, readable evidence; missing behavior belongs in plans or improvement requests.
`since: unreleased` reflects the absence of Shoko release tags at adoption.

Run `just check-docs` to enforce both catalogs. Capability records are agent-authored
and have no independent review attestation; the profile's recommended `reviews`
field stays absent until a review actually occurs.

See the [core guide](../core.md), [adapter guide](../adapters.md),
[host guide](../scenario-hosts.md), and [update log](log.md).
