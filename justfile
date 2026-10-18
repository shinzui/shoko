default:
    @just --list

build:
    cabal build all

# Explicit selection keeps future database suites out of unit-only checks.
test:
    cabal test shoko-core-test --test-show-details=direct

check: build test
    python3 scripts/check-result-schema.py
    nix flake check

fmt:
    nix fmt -- --formatters cabal-gild
    nix fmt
