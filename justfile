default:
    @just --list

build:
    cabal build all

# Explicit selection keeps future database suites out of unit-only checks.
test:
    cabal test shoko-core-test --test-show-details=direct

test-adapters:
    python3 scripts/test-adapters

test-email:
    python3 scripts/test-email

test-event-stores:
    python3 scripts/test-event-stores

test-event-store store:
    python3 scripts/test-event-stores --store {{store}}

test-kafka:
    python3 scripts/test-kafka

test-cli:
    python3 scripts/test-cli

test-scenario-catalog:
    python3 scripts/test-scenario-catalog

test-workflow-contract:
    python3 scripts/test-workflow-contract
    python3 scripts/test-workflow-identity
    python3 scripts/test-workflow-v2

workflow-validate:
    python3 scripts/workflow-env validate --manifest integration/workflow.json

workflow-check:
    python3 scripts/workflow-env check --manifest integration/workflow.json

workflow-smoke:
    python3 scripts/workflow-env smoke --manifest integration/workflow.json

# Requires okf >= 0.9.0.0 and Mori with local capability/terminology validation.
check-docs:
    mori validate
    okf validate docs/capabilities --profile docs/capabilities/profile.dhall --profile-enforce --log-enforce
    okf validate docs/terminology --strict --profile docs/terminology/profile.dhall --profile-enforce --log-enforce
    okf validate docs/improvement-requests --strict --profile docs/improvement-requests/profile.dhall --profile-enforce --log-enforce
    mori capabilities validate --path .
    mori terms validate --path .

check: build test test-email test-adapters test-event-stores test-kafka test-cli test-scenario-catalog test-workflow-contract
    python3 scripts/test-core-types
    python3 scripts/check-result-schema.py
    nix flake check

fmt:
    nix fmt -- --formatters cabal-gild
    nix fmt
