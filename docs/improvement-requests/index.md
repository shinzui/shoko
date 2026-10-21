---
okf_version: "0.2"
---

# Files

- [profile.dhall](profile.dhall)

# Improvement Request

- [Select compiled scenarios through a declarative catalog with shared inspection](1-select-compiled-scenarios-through-a-declarative-catalog.md) - Give consumers a versioned scenario catalog schema and a packaged list, explain and check dispatcher so a QA repository can select compiled scenarios by stable ID without forking Shoko's inspection mechanics.
- [Generalize the staging workflow contract and readiness checks beyond registration](2-generalize-the-staging-workflow-contract-and-readiness-checks.md) - Factor the registration-specific workflow contract and identity checks into a workflow-independent schema and a packaged validate, check and observe command so a second workflow can declare its target, prerequisites and evidence without relabeling the registration example.
- [Execute a catalog suite with Shoko-owned acceptance envelopes and offline verification](3-execute-a-catalog-suite-with-shoko-owned-acceptance-envelopes.md) - Provide shared run and verify commands so any consumer can execute a catalog suite against an observed target, retain per-scenario acceptance envelopes atomically, aggregate exits with a fixed precedence, and verify bundle integrity offline without a consumer-local executor.

