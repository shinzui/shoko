"""Read-only Kubernetes identity observations; no endpoint or workflow claims."""

from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import signal
import selectors
import subprocess
import time
import uuid


class IdentityError(Exception):
    """A stable, safe error code; never includes process output or API values."""


class Kubectl:
    def __init__(self, target, budget_seconds=60):
        self.target = target
        self.deadline = time.monotonic() + budget_seconds

    def read(self, arguments, *, local=False):
        remaining = min(15, self.deadline - time.monotonic())
        if remaining <= 0:
            raise IdentityError("identity-deadline-exceeded")
        target = self.target
        command = ["kubectl", "--context=" + target["context"],
                   "--namespace=" + target["namespace"], "--request-timeout=10s"]
        if not local:
            # Pin the server for every call, even if kubeconfig is edited between
            # discovery and the next GET. Keep TLS verification enabled.
            command += ["--server=" + target["apiServer"], "--insecure-skip-tls-verify=false"]
        command += arguments
        try:
            process = subprocess.Popen(command, stdin=subprocess.DEVNULL,
                                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                       start_new_session=True)
        except OSError:
            raise IdentityError("kubectl-unavailable") from None
        output = bytearray()
        try:
            call_deadline = time.monotonic() + remaining
            with selectors.DefaultSelector() as selector:
                selector.register(process.stdout, selectors.EVENT_READ)
                while True:
                    left = call_deadline - time.monotonic()
                    if left <= 0 or not selector.select(left):
                        raise IdentityError("kubectl-timeout")
                    chunk = os.read(process.stdout.fileno(), 65536)
                    if not chunk:
                        break
                    output.extend(chunk)
                    if len(output) > 4 * 1024 * 1024:
                        raise IdentityError("kubectl-response-too-large")
            try:
                process.wait(timeout=max(0, call_deadline - time.monotonic()))
            except subprocess.TimeoutExpired:
                raise IdentityError("kubectl-timeout") from None
        except BaseException:
            # Credential plugins may create children; do not leave them running
            # after the finite discovery operation times out or is interrupted.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
            raise
        finally:
            process.stdout.close()
        if process.returncode:
            raise IdentityError("kubectl-read-failed")
        try:
            value = json.loads(output)
        except (ValueError, UnicodeError):
            raise IdentityError("kubectl-invalid-json") from None
        if not isinstance(value, dict):
            raise IdentityError("kubectl-invalid-object")
        return value

    def configuration(self):
        # Never use --raw or persist kubeconfig. Even redacted configuration and
        # resource responses are discarded after extracting the allowlist below.
        value = self.read(["config", "view", "--minify", "--output=json"], local=True)
        try:
            contexts, clusters = value["contexts"], value["clusters"]
            if len(contexts) != 1 or len(clusters) != 1:
                raise IdentityError("kubeconfig-identity-mismatch")
            context, cluster = contexts[0], clusters[0]
            if (context["name"] != self.target["context"]
                    or context["context"]["cluster"] != self.target["cluster"]
                    or cluster["name"] != self.target["cluster"]
                    or cluster["cluster"]["server"] != self.target["apiServer"]):
                raise IdentityError("kubeconfig-identity-mismatch")
            if cluster["cluster"].get("insecure-skip-tls-verify", False):
                raise IdentityError("kubeconfig-insecure-tls")
        except (KeyError, TypeError, IndexError):
            raise IdentityError("kubeconfig-identity-missing") from None

    def snapshot(self):
        target = self.target
        namespace = self.read(["get", "namespaces", target["namespace"], "--output=json"])
        try:
            meta = namespace["metadata"]
            if (namespace["kind"] != "Namespace" or meta["name"] != target["namespace"]
                    or meta["uid"] != target["namespaceUid"] or meta.get("deletionTimestamp")):
                raise IdentityError("namespace-identity-mismatch")
            result = {key: target[key] for key in
                      ("context", "cluster", "apiServer", "namespace", "namespaceUid")}
            result["workloads"] = []
            for expected in target["workloads"]:
                resource = {"Deployment": "deployments.apps", "StatefulSet": "statefulsets.apps",
                            "DaemonSet": "daemonsets.apps"}[expected["kind"]]
                observed = self.read(["get", resource, expected["name"], "--output=json"])
                meta = observed["metadata"]
                if (observed["kind"] != expected["kind"] or meta["name"] != expected["name"]
                        or meta["namespace"] != target["namespace"] or meta["uid"] != expected["uid"]
                        or meta.get("deletionTimestamp")):
                    raise IdentityError("workload-identity-mismatch")
                spec = observed["spec"]["template"]["spec"]
                containers = spec["containers"] + spec.get("initContainers", [])
                images = [container["image"] for container in containers]
                if not images or set(images) != set(expected["imageDigests"]):
                    raise IdentityError("workload-template-images-mismatch")
                generation = meta["generation"]
                if type(generation) is not int or generation < 1:
                    raise IdentityError("workload-generation-missing")
                # This observes the controller's template, NOT runtime imageIDs,
                # pod readiness, rollout completion, or continuous stability.
                result["workloads"].append({
                    **{key: expected[key] for key in ("id", "kind", "name", "uid")},
                    "generation": generation, "templateImageDigests": sorted(set(images)),
                })
            return result
        except (KeyError, TypeError, IndexError):
            raise IdentityError("kubernetes-identity-missing") from None


def check_identity(contract, manifest_bytes, *, client=None):
    record = {
        "schemaVersion": 1,
        "purpose": "staging-identity-check",
        "contractSha256": hashlib.sha256(manifest_bytes).hexdigest(),
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "identityStatus": "blocked",
        "readinessStatus": "blocked",
        "observations": {},
        "blockers": ["endpoint-evidence-and-domain-readiness-unverified"],
    }
    try:
        client = client or Kubectl(contract["target"])
        client.configuration()
        record["observations"]["before"] = client.snapshot()
        record["observations"]["after"] = client.snapshot()
        if record["observations"]["before"] != record["observations"]["after"]:
            raise IdentityError("target-changed-during-discovery")
        record["identityStatus"] = "matched"
    except IdentityError as error:
        record["blockers"].insert(0, str(error))
    return record


def write_record(record, directory):
    """Create an isolated private artifact without replacing a previous run."""
    try:
        run_directory = Path(directory) / str(uuid.uuid4())
        run_directory.mkdir(mode=0o700, parents=True)
        path = run_directory / "identity.json"
        with path.open("x", encoding="utf-8") as handle:
            os.chmod(path, 0o600)
            json.dump(record, handle, indent=2)
            handle.write("\n")
        return path
    except OSError:
        raise IdentityError("identity-artifact-write-failed") from None
