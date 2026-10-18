#!/usr/bin/env python3
"""Validate checked-in public result examples without network access."""

import json
from pathlib import Path
import sys

from jsonschema import Draft202012Validator


def main():
    root = Path(__file__).resolve().parent.parent
    schema_path = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "schemas/run-result-v1.schema.json"
    examples = Path(sys.argv[2]) if len(sys.argv) > 2 else root / "shoko-core/test/golden"
    schema = json.loads(schema_path.read_text())
    Draft202012Validator.check_schema(schema)
    validator = Draft202012Validator(schema, format_checker=Draft202012Validator.FORMAT_CHECKER)
    files = sorted(examples.glob("*.json"))
    if not files:
        raise SystemExit("No run-result golden examples found")
    for path in files:
        encoded = path.read_text()
        if "SECRET-" in encoded:
            raise SystemExit(f"Secret sentinel found in {path.name}")
        value = json.loads(encoded)
        validator.validate(value)
        wrong_version = dict(value, schemaVersion=999)
        if validator.is_valid(wrong_version):
            raise SystemExit("Schema accepted an unsupported version")
        if validator.is_valid(dict(value, undeclaredField=True)):
            raise SystemExit("Schema accepted an undeclared field")
    print(f"Validated {len(files)} run-result examples against schema v1")


if __name__ == "__main__":
    main()
