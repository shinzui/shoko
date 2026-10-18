default:
    @just --list

build:
    cabal build all

# Explicit selection keeps future database suites out of unit-only checks.
test:
    cabal test shoko-core-test --test-show-details=direct

test-adapters:
    python3 scripts/test-adapters

test-event-stores:
    python3 scripts/test-event-stores

test-event-store store:
    python3 scripts/test-event-stores --store {{store}}

test-cli:
    python3 scripts/test-cli

test-workflow-contract:
    python3 scripts/test-workflow-contract
    python3 scripts/test-workflow-identity

workflow-validate:
    python3 scripts/workflow-env validate --manifest integration/workflow.json

workflow-check:
    python3 scripts/workflow-env check --manifest integration/workflow.json

workflow-smoke:
    python3 scripts/workflow-env smoke --manifest integration/workflow.json

check: build test test-adapters test-event-stores test-cli test-workflow-contract
    python3 scripts/check-result-schema.py
    nix flake check

fmt:
    nix fmt -- --formatters cabal-gild
    nix fmt
