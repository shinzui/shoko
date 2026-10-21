"""Workflow-independent contracts and one bounded read-only staging gate."""

from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
from urllib.parse import urlsplit

from jsonschema import Draft202012Validator, FormatChecker

from workflow_contract import ContractError
from workflow_identity import IdentityError, Kubectl


def indexed(items):
    result = {item["id"]: item for item in items}
    if len(result) != len(items):
        raise ContractError("duplicate-contract-id")
    return result


def address(value, schemes):
    try:
        parsed = urlsplit(value)
        parsed.port
        if (parsed.scheme not in schemes or not parsed.hostname or parsed.username or parsed.password
                or parsed.query or parsed.fragment or any(c.isspace() or ord(c) < 32 for c in value)):
            raise ValueError()
        return parsed
    except ValueError:
        raise ContractError("invalid-contract-address") from None


def validate(value, schema):
    if not Draft202012Validator(schema, format_checker=FormatChecker()).is_valid(value):
        raise ContractError("invalid-workflow-v2-schema")
    target = value["target"]
    address(target["apiServer"], {"https"})
    if not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", target["namespace"]):
        raise ContractError("invalid-target-namespace")
    workloads = indexed(target["workloads"])
    if len(workloads) > 32 or len({(w["kind"], w["name"]) for w in workloads.values()}) != len(workloads):
        raise ContractError("ambiguous-or-unbounded-workloads")
    for workload in workloads.values():
        containers = workload["containers"]
        keys = {(c["kind"], c["name"]) for c in containers}
        if len(keys) != len(containers) or len({c["name"] for c in containers}) != len(containers):
            raise ContractError("duplicate-container-identity")
        if workload["state"] == "ready" and not any(c["kind"] == "application" for c in containers):
            raise ContractError("missing-application-container")
        for container in containers:
            if "@sha256:" in container["templateImage"] and container["templateImage"] != container["imageDigest"]:
                raise ContractError("pinned-template-runtime-mismatch")
    endpoints = indexed(target["endpoints"])
    for endpoint in endpoints.values():
        parsed = address(endpoint["address"], {"http", "https", "postgresql", "kafka"}) if endpoint["state"] == "ready" else None
        if "serviceName" in endpoint:
            if not set(endpoint["workloadIds"]) <= set(workloads):
                raise ContractError("unknown-endpoint-workload")
            service = endpoint["serviceName"]
            namespace = target["namespace"]
            if parsed and parsed.hostname not in {service, f"{service}.{namespace}", f"{service}.{namespace}.svc", f"{service}.{namespace}.svc.cluster.local"}:
                raise ContractError("service-address-association-mismatch")
    actions = indexed(value["actions"])
    negatives = indexed(value["negativeScenarios"])
    if value["scenarioId"] in negatives:
        raise ContractError("duplicate-positive-negative-scenario")
    scenarios = {value["scenarioId"], *negatives}
    if not set(value["positiveActionIds"]) <= set(actions):
        raise ContractError("unknown-positive-action")
    for action in actions.values():
        if action["endpointId"] not in endpoints:
            raise ContractError("unknown-action-endpoint")
        endpoint = endpoints[action["endpointId"]]
        if endpoint["state"] == "ready":
            address(endpoint["address"], {"http", "https"})
    sources = indexed(value["evidenceSources"])
    for source in sources.values():
        if source["endpointId"] not in endpoints or source["adapter"] not in value["requiredAdapters"]:
            raise ContractError("unknown-evidence-source-endpoint-or-adapter")
        allowed = {"http": {"http", "https"}, "kafka": {"kafka"}}.get(source["adapter"], {"postgresql"})
        endpoint = endpoints[source["endpointId"]]
        if endpoint["state"] == "ready":
            address(endpoint["address"], allowed)
        if source["coverage"] == "durable-history" and source["adapter"] not in {"kiroku", "message-db", "kafka"}:
            raise ContractError("unsupported-history-coverage")
    requirements = indexed(value["requirements"])
    pairs = set()
    for requirement in requirements.values():
        source = sources.get(requirement["evidenceSourceId"])
        if source is None or requirement["scenarioId"] not in scenarios:
            raise ContractError("unknown-requirement-source-or-scenario")
        pair = requirement["scenarioId"], requirement["expectationId"]
        if pair in pairs:
            raise ContractError("ambiguous-requirement-expectation")
        pairs.add(pair)
        if requirement["coverage"] == "durable-history" and source["coverage"] != "durable-history":
            raise ContractError("insufficient-source-coverage")
    for scenario in scenarios:
        if not any(r["scenarioId"] == scenario for r in requirements.values()):
            raise ContractError("unmapped-scenario")
    for negative in negatives.values():
        if not set(negative["actionIds"]) <= set(actions):
            raise ContractError("unknown-negative-action")
        outcomes = {tag for key in negative["actionIds"] for tag in actions[key]["allowedOutcomes"]}
        if not set(negative["allowedOutcomes"]) <= outcomes:
            raise ContractError("undeclared-negative-outcome")
    if set(indexed(value["excludedRequirements"])) & set(requirements):
        raise ContractError("covered-and-excluded-requirement")
    indexed(value["readiness"]["prerequisites"])
    probes = indexed(value["readiness"]["probes"])
    if len(probes) > 32:
        raise ContractError("unbounded-readiness-probes")
    for probe in probes.values():
        if probe["endpointId"] not in endpoints:
            raise ContractError("unknown-probe-endpoint")
        endpoint = endpoints[probe["endpointId"]]
        if endpoint["state"] == "ready":
            address(endpoint["address"], {"http", "https"})
    for check in indexed(target["configurationChecks"]).values():
        workload = workloads.get(check["workloadId"])
        if workload is None or (workload["state"] == "ready" and check["container"] not in {c["name"] for c in workload["containers"]}):
            raise ContractError("unknown-configuration-check-target")
        address(check["expectedValue"], {"http", "https"})
    host = value["host"]
    if not {host["project"], value["vocabularyOwner"], value["domainOwner"]} <= set(value["participants"]) or not host["package"].startswith(host["project"] + "/packages/"):
        raise ContractError("host-or-vocabulary-ownership-mismatch")
    if host["packageDirectory"].startswith("/") or any(p in ("", ".", "..") for p in host["packageDirectory"].split("/")):
        raise ContractError("invalid-host-project-path")
    return value


def blockers(value):
    result = []
    now = datetime.now(timezone.utc)
    for prerequisite in value["readiness"]["prerequisites"]:
        if prerequisite["status"] != "confirmed":
            result.append("prerequisite-" + prerequisite["id"])
        else:
            expiry = datetime.fromisoformat(prerequisite["expiresAt"].replace("Z", "+00:00"))
            if expiry <= now:
                result.append("expired-prerequisite-" + prerequisite["id"])
    for workload in value["target"]["workloads"]:
        if workload["state"] != "ready":
            result.append("pending-workload-" + workload["id"])
    for endpoint in value["target"]["endpoints"]:
        if endpoint["state"] != "ready":
            result.append("pending-endpoint-" + endpoint["id"])
        if "serviceUid" in endpoint and endpoint["serviceUid"] is None:
            result.append("pending-service-" + endpoint["id"])
    return result


def require(condition, code):
    if not condition:
        raise IdentityError(code)


def metadata(value, kind, name, namespace, uid=None):
    meta = value["metadata"]
    require(value["kind"] == kind and meta["name"] == name and (kind == "Namespace" or meta.get("namespace") == namespace)
            and not meta.get("deletionTimestamp") and (uid is None or meta["uid"] == uid), "resource-identity-mismatch")
    return meta


class Gate(Kubectl):
    def __init__(self, target):
        super().__init__(target, budget_seconds=60)

    def snapshot(self):
        target = self.target
        namespace = self.read(["get", "namespaces", target["namespace"], "--output=json"])
        metadata(namespace, "Namespace", target["namespace"], target["namespace"], target["namespaceUid"])
        result = {"namespaceUid": target["namespaceUid"], "workloads": [], "endpoints": [], "configurationChecks": []}
        podsets = {}
        labels_by_workload = {}
        ports_by_workload = {}
        for expected in target["workloads"]:
            kind = expected["kind"]
            resource = {"Deployment": "deployments.apps", "StatefulSet": "statefulsets.apps", "DaemonSet": "daemonsets.apps"}[kind]
            observed = self.read(["get", resource, expected["name"], "--output=json"])
            meta = metadata(observed, kind, expected["name"], target["namespace"], expected["uid"])
            spec, status = observed["spec"], observed["status"]
            require(type(meta["generation"]) is int and meta["generation"] > 0 and status["observedGeneration"] >= meta["generation"], "workload-generation-unobserved")
            desired = status["desiredNumberScheduled"] if kind == "DaemonSet" else spec["replicas"]
            require(type(desired) is int and 0 < desired <= 64, "workload-replica-budget")
            if kind == "DaemonSet":
                require(status["numberReady"] == desired and status["numberAvailable"] == desired and status["updatedNumberScheduled"] == desired and status.get("numberUnavailable", 0) == 0, "workload-rollout-incomplete")
            else:
                require(status["readyReplicas"] == desired and status["updatedReplicas"] == desired and status.get("unavailableReplicas", 0) == 0, "workload-rollout-incomplete")
                if kind == "Deployment":
                    require(status["availableReplicas"] == desired and any(c["type"] == "Available" and c["status"] == "True" for c in status["conditions"])
                            and not any(c["type"] == "Progressing" and c["status"] == "False" for c in status["conditions"]), "workload-rollout-incomplete")
                else:
                    require(status["currentRevision"] == status["updateRevision"], "workload-rollout-incomplete")
            template = spec["template"]
            selector = spec["selector"]
            require(not selector.get("matchExpressions") and bool(selector["matchLabels"]), "unsupported-workload-selector")
            require(all(template["metadata"]["labels"].get(k) == v for k, v in selector["matchLabels"].items()), "workload-selector-mismatch")
            labels_by_workload[expected["id"]] = template["metadata"]["labels"]
            ports_by_workload[expected["id"]] = [p for c in template["spec"]["containers"] + template["spec"].get("initContainers", []) for p in c.get("ports", [])]
            expected_containers = {(c["kind"], c["name"]): c for c in expected["containers"]}
            self.check_template(template["spec"], expected_containers)
            checks = [c for c in target["configurationChecks"] if c["workloadId"] == expected["id"]]
            self.check_configuration(template["spec"], checks)
            query = ",".join(f"{key}={value}" for key, value in sorted(selector["matchLabels"].items()))
            pods = self.read(["get", "pods", "--selector=" + query, "--output=json"])["items"]
            require(len(pods) == desired, "workload-pod-count-mismatch")
            sanitized = []
            for pod in pods:
                pm = metadata(pod, "Pod", pod["metadata"]["name"], target["namespace"])
                require(pod["status"]["phase"] == "Running" and any(c["type"] == "Ready" and c["status"] == "True" for c in pod["status"]["conditions"]), "pod-not-ready")
                owners = [o for o in pm["ownerReferences"] if o.get("controller")]
                require(len(owners) == 1, "pod-controller-mismatch")
                owner = owners[0]
                if kind == "Deployment":
                    require(owner["kind"] == "ReplicaSet", "pod-controller-mismatch")
                    replica = self.read(["get", "replicasets.apps", owner["name"], "--output=json"])
                    rm = metadata(replica, "ReplicaSet", owner["name"], target["namespace"], owner["uid"])
                    parents = [o for o in rm["ownerReferences"] if o.get("controller")]
                    require(len(parents) == 1 and parents[0]["kind"] == kind and parents[0]["uid"] == expected["uid"] and parents[0]["name"] == expected["name"], "replicaset-controller-mismatch")
                else:
                    require(owner["kind"] == kind and owner["uid"] == expected["uid"] and owner["name"] == expected["name"], "pod-controller-mismatch")
                self.check_template(pod["spec"], expected_containers)
                self.check_configuration(pod["spec"], checks)
                statuses = {}
                for group, key in (("application", "containerStatuses"), ("init", "initContainerStatuses")):
                    for container in pod["status"].get(key, []):
                        identity = group, container["name"]
                        require(identity not in statuses, "duplicate-runtime-container")
                        statuses[identity] = container
                require(set(statuses) == set(expected_containers), "runtime-container-set-mismatch")
                public_containers = []
                for identity, expected_container in expected_containers.items():
                    runtime = statuses[identity]
                    image_id = runtime["imageID"].removeprefix("docker-pullable://").removeprefix("containerd://")
                    require(image_id == expected_container["imageDigest"], "runtime-image-mismatch")
                    init_spec = next((c for c in pod["spec"].get("initContainers", []) if c["name"] == identity[1]), {})
                    if identity[0] == "application" or init_spec.get("restartPolicy") == "Always":
                        require(runtime["ready"] is True and "running" in runtime["state"], "container-not-running-ready")
                    else:
                        require(runtime["state"].get("terminated", {}).get("exitCode") == 0, "init-container-not-complete")
                    public_containers.append({"name": identity[1], "kind": identity[0], "imageDigest": image_id, "restartCount": runtime["restartCount"]})
                sanitized.append({"uid": pm["uid"], "containers": sorted(public_containers, key=lambda c: (c["kind"], c["name"]))})
            podsets[expected["id"]] = {p["uid"] for p in sanitized}
            result["workloads"].append({"id": expected["id"], "uid": meta["uid"], "generation": meta["generation"], "pods": sorted(sanitized, key=lambda p: p["uid"])})
            result["configurationChecks"].extend(c["id"] for c in checks)
        for endpoint in target["endpoints"]:
            if "serviceName" not in endpoint:
                continue
            service = self.read(["get", "services", endpoint["serviceName"], "--output=json"])
            sm = metadata(service, "Service", endpoint["serviceName"], target["namespace"], endpoint["serviceUid"])
            selector = service["spec"]["selector"]
            require(bool(selector), "service-selector-missing")
            for workload_id in endpoint["workloadIds"]:
                require(all(labels_by_workload[workload_id].get(k) == v for k, v in selector.items()), "endpoint-workload-association-mismatch")
            parsed = urlsplit(endpoint["address"])
            port = parsed.port or (443 if parsed.scheme == "https" else 80)
            service_ports = [p for p in service["spec"]["ports"] if p["port"] == port and p.get("protocol", "TCP") == "TCP"]
            require(len(service_ports) == 1, "endpoint-service-port-mismatch")
            target_port = service_ports[0].get("targetPort", port)
            resolved_ports = set()
            for workload_id in endpoint["workloadIds"]:
                declared = ports_by_workload[workload_id]
                resolved = {p["containerPort"] for p in declared if (p["containerPort"] == target_port if type(target_port) is int else p.get("name") == target_port) and p.get("protocol", "TCP") == "TCP"}
                require(len(resolved) == 1, "endpoint-target-port-unverified")
                resolved_ports.update(resolved)
            slices = self.read(["get", "endpointslices.discovery.k8s.io", "--selector=kubernetes.io/service-name=" + endpoint["serviceName"], "--output=json"])["items"]
            require(len(slices) <= 64, "endpoint-slice-budget")
            wanted = set().union(*(podsets[w] for w in endpoint["workloadIds"]))
            seen = set()
            for endpoint_slice in slices:
                slice_meta = metadata(endpoint_slice, "EndpointSlice", endpoint_slice["metadata"]["name"], target["namespace"])
                require(any(o["kind"] == "Service" and o["uid"] == sm["uid"] and o["name"] == endpoint["serviceName"] for o in slice_meta.get("ownerReferences", [])), "endpoint-slice-owner-mismatch")
                require({p["port"] for p in endpoint_slice["ports"] if p.get("protocol", "TCP") == "TCP"} >= resolved_ports, "endpoint-slice-port-mismatch")
                for peer in endpoint_slice["endpoints"]:
                    ref = peer.get("targetRef", {})
                    require(peer.get("conditions", {}).get("ready") is True and ref.get("kind") == "Pod"
                            and ref.get("namespace") == target["namespace"] and ref.get("uid") in wanted, "endpoint-pod-association-mismatch")
                    seen.add(ref["uid"])
            require(seen == wanted and bool(seen), "endpoint-pods-unavailable")
            result["endpoints"].append({"id": endpoint["id"], "serviceUid": sm["uid"]})
        return result

    @staticmethod
    def check_configuration(spec, checks):
        containers = {c["name"]: c for c in spec["containers"] + spec.get("initContainers", [])}
        for check in checks:
            entries = [e for e in containers[check["container"]].get("env", []) if e["name"] == check["environmentName"]]
            require(len(entries) == 1 and entries[0].get("value") == check["expectedValue"] and "valueFrom" not in entries[0], "public-configuration-expectation-mismatch")

    @staticmethod
    def check_template(spec, expected):
        require(not spec.get("ephemeralContainers"), "unapproved-ephemeral-container")
        actual = {}
        for group, key in (("application", "containers"), ("init", "initContainers")):
            for container in spec.get(key, []):
                identity = group, container["name"]
                require(identity not in actual, "duplicate-template-container")
                actual[identity] = container["image"]
        require(actual == {key: value["templateImage"] for key, value in expected.items()}, "template-container-set-or-image-mismatch")

    def probe(self, endpoint, probe):
        remaining = min(10, self.deadline - time.monotonic())
        require(remaining > 0, "readiness-deadline-exceeded")
        # Bound the entire HTTP operation, including slow response bodies/header
        # streams, in an owned child. Secret values never appear in its argv.
        try:
            process = subprocess.Popen([sys.executable, str(Path(__file__).with_name("workflow_probe.py"))], stdin=subprocess.PIPE,
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        except OSError:
            raise IdentityError("readiness-probe-unavailable") from None
        try:
            process.communicate(json.dumps({"endpoint": endpoint, "probe": probe}).encode(), timeout=remaining)
            require(process.returncode == 0, "readiness-probe-unavailable")
        except BaseException as error:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
            if isinstance(error, subprocess.TimeoutExpired):
                raise IdentityError("readiness-probe-timeout") from None
            raise


def observe(value, manifest_bytes, *, client=None):
    record = {"schemaVersion": 1, "kind": "staging-target-observation", "workflowId": value["workflowId"],
              "contractSha256": hashlib.sha256(manifest_bytes).hexdigest(),
              "checkedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
              "identityStatus": "blocked", "readinessStatus": "blocked", "observations": {},
              "blockers": blockers(value), "probes": []}
    if value["purpose"] != "staging-contract":
        record["blockers"].insert(0, "synthetic-contract-live-refused")
    if record["blockers"]:
        return record
    try:
        client = client or Gate(value["target"])
        client.configuration()
        record["observations"]["before"] = client.snapshot()
        endpoints = indexed(value["target"]["endpoints"])
        for probe in value["readiness"]["probes"]:
            client.probe(endpoints[probe["endpointId"]], probe)
            record["probes"].append(probe["id"])
        record["observations"]["after"] = client.snapshot()
        require(record["observations"]["before"] == record["observations"]["after"], "target-changed-during-observation")
        record["identityStatus"] = "matched"
        record["readinessStatus"] = "ready"
    except IdentityError as error:
        record["blockers"].append(str(error))
    except (KeyError, TypeError, ValueError, IndexError):
        record["blockers"].append("incomplete-target-observation")
    return record
