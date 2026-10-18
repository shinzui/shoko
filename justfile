default:
    @just --list

build:
    cabal build all

# Explicit selection keeps future database suites out of unit-only checks.
test:
    cabal test shoko-core-test --test-show-details=direct

check: build test
    nix flake check

fmt:
    nix fmt
