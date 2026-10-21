"""Shoko-owned catalog validation and offline compiled-host dispatch."""

import argparse
import json
import os
from pathlib import Path, PurePosixPath
import subprocess
import sys

from jsonschema import Draft202012Validator


class CatalogError(Exception):
    """A public classification; never includes catalog or argument values."""


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise CatalogError("duplicate-json-key")
        result[key] = value
    return result


def workspace_path(root, value):
    path = PurePosixPath(value)
    if path.is_absolute() or any(part in (".", "..") for part in value.split("/")) or "\\" in value:
        raise CatalogError("invalid-workspace-path")
    result = (root / value).resolve()
    if not result.is_relative_to(root) or not result.is_file():
        raise CatalogError("unavailable-workspace-path")
    return result


def load_catalog(path, root):
    with path.open() as handle:
        catalog = json.load(handle, object_pairs_hook=unique_object)
    schema = Path(__file__).resolve().parent.parent / "schemas/scenario-catalog-v1.schema.json"
    with schema.open() as handle:
        validator = Draft202012Validator(json.load(handle))
    if not validator.is_valid(catalog):
        raise CatalogError("invalid-catalog-schema")
    seen = set()
    artifacts = {}
    for entry in catalog["scenarios"]:
        if entry["id"] in seen:
            raise CatalogError("duplicate-scenario-id")
        seen.add(entry["id"])
        if entry["state"] == "ready":
            workspace_path(root, entry["config"])
            if entry["workflow"] is not None:
                workspace_path(root, entry["workflow"])
            host = entry["host"]
            prior = artifacts.setdefault(host["artifact"], host)
            if prior != host:
                raise CatalogError("ambiguous-host-artifact")
    return catalog


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise CatalogError("invalid-command-line")


def main(argv=None):
    try:
        parser = Parser(description="Inspect an explicit Shoko catalog; no live readiness or suite execution.")
        parser.add_argument("--workspace", required=True, type=Path)
        parser.add_argument("--catalog", required=True, type=Path)
        parser.add_argument("--host", action="append", default=[], metavar="ARTIFACT=ABSOLUTE_EXECUTABLE")
        parser.add_argument("--environment", choices=["local", "staging"])
        parser.add_argument("--format", choices=["text", "json"], default="text")
        parser.add_argument("command", choices=["catalog-check", "list", "explain", "check", "run"])
        parser.add_argument("scenario", nargs="?")
        args = parser.parse_args(argv)
        if (args.command in ("explain", "check", "run")) != (args.scenario is not None):
            raise CatalogError("invalid-selection")
        # Ambient host environment overrides cannot select an alias or production.
        ambient = os.environ.get("SHOKO_ENVIRONMENT")
        if ambient is not None and ambient not in ("local", "staging"):
            raise CatalogError("unsupported-environment")
        root = args.workspace.resolve(strict=True)
        catalog_path = args.catalog.resolve(strict=True)
        if not root.is_dir() or not catalog_path.is_relative_to(root):
            raise CatalogError("invalid-workspace-path")
        catalog = load_catalog(catalog_path, root)
        bindings = {}
        artifacts = {e["host"]["artifact"] for e in catalog["scenarios"] if e["state"] == "ready"}
        for binding in args.host:
            artifact, separator, executable = binding.partition("=")
            if not separator or artifact not in artifacts or artifact in bindings or not Path(executable).is_absolute():
                raise CatalogError("invalid-host-binding")
            bindings[artifact] = Path(executable)
        if args.command == "catalog-check":
            print(json.dumps({"kind": "catalog-check", "valid": True, "liveReadinessChecked": False,
                              "scenarios": len(catalog["scenarios"]),
                              "pending": [e["id"] for e in catalog["scenarios"] if e["state"] == "pending"]}))
            return 0
        if args.command == "list":
            entries = catalog["scenarios"]
            if args.environment:
                entries = [e for e in entries if e["environment"] == args.environment]
            if args.format == "json":
                print(json.dumps(entries))
            else:
                for entry in entries:
                    print(f'{entry["id"]}\t{entry["state"]}\t{",".join(entry["suites"])}\t{entry.get("reason", "")}')
            return 0
        entry = next((e for e in catalog["scenarios"] if e["id"] == args.scenario), None)
        if entry is None:
            raise CatalogError("unknown-scenario")
        if any(env is not None and env != entry["environment"] for env in (args.environment, ambient)):
            raise CatalogError("environment-mismatch")
        if entry["state"] == "pending":
            print(json.dumps({"kind": "unresolved-prerequisite", "scenario": entry["id"], "reason": entry["reason"], "liveReadinessChecked": False}))
            return 2
        if args.command == "run":
            raise CatalogError("suite-execution-unavailable")
        host = entry["host"]
        executable = bindings.get(host["artifact"])
        if executable is None or executable.name != host["executable"] or not executable.is_file() or not os.access(executable, os.X_OK):
            raise CatalogError("unresolved-host-artifact")
        # Explicit artifact binding, no PATH search or shell expansion. The host owns
        # pure binding factories, credential-safe diagnostics and policy inspection.
        command = [str(executable), args.command, entry["id"], "--config", str(workspace_path(root, entry["config"])),
                   "--environment", entry["environment"], "--format", args.format]
        environment = dict(os.environ)
        environment.pop("SHOKO_IMPLEMENTATION", None)
        result = subprocess.run(command, cwd=root, env=environment, check=False)
        return result.returncode if result.returncode in range(5) else 4
    except CatalogError as error:
        print(f"Catalog rejected: {error}", file=sys.stderr)
        return 2
    except (OSError, ValueError, RecursionError):
        print("Catalog rejected: unreadable-or-invalid-input", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
