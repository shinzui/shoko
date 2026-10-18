"""Offline workflow-contract validation; never resolves credentials or targets."""

import json
from pathlib import Path
from urllib.parse import urlsplit

from jsonschema import Draft202012Validator


class ContractError(ValueError):
    pass


def load_json(path):
    def unique_keys(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ContractError("duplicate JSON object key")
            result[key] = value
        return result

    try:
        return json.loads(Path(path).read_text(), object_pairs_hook=unique_keys)
    except (OSError, UnicodeError, ValueError):
        # Neither JSON parse errors nor invalid values are safe to echo: a
        # mistaken manifest can contain credentials or personal test payloads.
        raise ContractError("manifest missing, unreadable, or invalid JSON") from None


def validate_contract(value, schema):
    Draft202012Validator.check_schema(schema)
    validator = Draft202012Validator(schema)
    if not validator.is_valid(value):
        raise ContractError("manifest does not conform to workflow schema v1")

    def indexed(items, label):
        result = {item["id"]: item for item in items}
        if len(result) != len(items):
            raise ContractError("duplicate " + label + " ID")
        return result

    endpoints = indexed(value["target"]["endpoints"], "endpoint")
    sources = indexed(value["evidenceSources"], "evidence source")
    requirements = indexed(value["requirements"], "requirement")
    negatives = indexed(value["negativeScenarios"], "negative scenario")
    indexed(value["target"]["workloads"], "workload")
    prerequisites = indexed(value["readiness"]["prerequisites"], "prerequisite")
    if not {"cluster-access", "controlled-fixtures", "otp-path", "real-completion",
            "evidence-access", "negative-contract", "endpoint-authorization",
            "cleanup-retention", "stable-window"} <= set(prerequisites):
        raise ContractError("required staging readiness prerequisites are missing")
    actions = indexed(value["actions"], "action")
    if value["scenarioId"] in negatives:
        raise ContractError("positive and negative scenario IDs must differ")
    scenarios = {value["scenarioId"], *negatives}
    adapters = set(value["requiredAdapters"])
    if not {"http", "postgresql"} <= adapters:
        raise ContractError("registration baseline requires HTTP and PostgreSQL")

    for endpoint in endpoints.values():
        try:
            parsed = urlsplit(endpoint["address"])
            hostname = parsed.hostname
            parsed.port
        except ValueError:
            raise ContractError("endpoint address is invalid") from None
        if (parsed.scheme not in {"http", "https", "postgresql"}
                or not hostname or parsed.username or parsed.password
                or parsed.query or parsed.fragment):
            raise ContractError("endpoint must be a credential-free absolute address")
    for action in actions.values():
        if action["endpointId"] not in endpoints:
            raise ContractError("action references an unknown endpoint")
        if urlsplit(endpoints[action["endpointId"]]["address"]).scheme not in {"http", "https"}:
            raise ContractError("HTTP action requires an HTTP endpoint")
    if not set(value["positiveActionIds"]) <= set(actions):
        raise ContractError("positive scenario references an unknown action")
    for source in sources.values():
        if source["endpointId"] not in endpoints:
            raise ContractError("evidence source references an unknown endpoint")
        if source["adapter"] not in adapters:
            raise ContractError("evidence source adapter is not selected")
        scheme = urlsplit(endpoints[source["endpointId"]]["address"]).scheme
        allowed_schemes = {"http", "https"} if source["adapter"] == "http" else {"postgresql"}
        if scheme not in allowed_schemes:
            raise ContractError("evidence source adapter does not match its endpoint protocol")
        if source["coverage"] == "durable-history" and source["adapter"] not in {"kiroku", "message-db"}:
            raise ContractError("durable history requires a selected event reader")

    expectation_pairs = set()
    for requirement in requirements.values():
        source = sources.get(requirement["evidenceSourceId"])
        if source is None or requirement["scenarioId"] not in scenarios:
            raise ContractError("requirement references an unknown source or scenario")
        if requirement["coverage"] == "durable-history" and source["coverage"] != "durable-history":
            raise ContractError("requirement needs stronger coverage than its source")
        pair = (requirement["scenarioId"], requirement["expectationId"])
        if pair in expectation_pairs:
            raise ContractError("expectation must map to one stable requirement")
        expectation_pairs.add(pair)

    positive_kinds = {r["kind"] for r in requirements.values() if r["scenarioId"] == value["scenarioId"]}
    if not {"registration-completed", "account-created", "user-created", "account-user-associated", "duplicate-prevention"} <= positive_kinds:
        raise ContractError("positive registration requirements are incomplete")
    for negative in negatives.values():
        if not set(negative["actionIds"]) <= set(actions):
            raise ContractError("negative scenario references an unknown action")
        outcomes = {tag for key in negative["actionIds"] for tag in actions[key]["allowedOutcomes"]}
        if not set(negative["allowedOutcomes"]) <= outcomes:
            raise ContractError("negative outcomes are not declared by its actions")
        mapped = [r for r in requirements.values() if r["scenarioId"] == negative["id"]]
        if not any(r["kind"] == "negative-contract" for r in mapped):
            raise ContractError("negative scenario lacks its rejection requirement")
        if not any(r["kind"] != "negative-contract" for r in mapped):
            raise ContractError("negative scenario lacks a downstream invariant")
    excluded = indexed(value["excludedRequirements"], "excluded requirement")
    if set(excluded) & set(requirements):
        raise ContractError("a requirement cannot be both covered and excluded")
    if not {"qualification", "other-registration-flows"} <= {r["scope"] for r in excluded.values()}:
        raise ContractError("qualification and other registration flows must be excluded explicitly")

    host = value["host"]
    if host["project"] != value["vocabularyOwner"]:
        raise ContractError("verification host must belong to the vocabulary owner")
    if not host["package"].startswith(host["project"] + "/packages/"):
        raise ContractError("host package must belong to the canonical owning project")
    for path in (host["packageDirectory"],):
        if path.startswith("/") or ".." in path.split("/"):
            raise ContractError("host directory must be project-relative")
    return value


def readiness_blockers(value):
    """Local blockers only. An empty list does not establish live readiness."""
    blockers = [p for p in value["readiness"]["prerequisites"] if p["status"] != "confirmed"]
    return [{"id": p["id"], "owner": p["owner"], "reason": p["reason"], "clearedBy": p["clearedBy"]}
            for p in blockers]
