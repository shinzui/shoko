default:
    @just --list

build:
    cabal build all

# Explicit selection keeps future database suites out of unit-only checks.
test:
    cabal test shoko-core-test --test-show-details=direct

test-adapters:
    python3 scripts/test-adapters

test-cli:
    python3 scripts/test-cli

check: build test test-adapters test-cli
    python3 scripts/check-result-schema.py
    nix flake check

fmt:
    nix fmt -- --formatters cabal-gild
    nix fmt
