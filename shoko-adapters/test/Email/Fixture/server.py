"""An owned loopback provider contract plus a separate fixture application."""
import copy
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import sys
import select
import socket
import threading
import time
import uuid
from urllib.parse import urlparse, parse_qs

accounts = {}
lock = threading.RLock()


def message(recipient, subject="Welcome", identity=None):
    return dict(id=identity or str(uuid.uuid4()), to=[recipient],
                **{"from": "FROM-PRIVATE@example.invalid"}, subject=subject,
                text="CONTENT-PRIVATE welcome", html="<p>HTML-PRIVATE</p>", html_format="cid",
                headers={"x-private": "HEADER-PRIVATE"},
                attachments=[dict(id="attachment-id", filename="FILENAME-PRIVATE", content_type="text/plain", size=3)],
                raw={"download_url": "https://URL-PRIVATE.invalid/raw"}, authentication=None)


def account(name):
    return accounts.setdefault(name, dict(messages=[], mutations=0, sends=0, details=0, lists=0,
                                         keys={}, requests=0, fault="", deliver=True, tickets=[], disconnects=0))


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def reply(self, status, value, raw=False):
        data = value if raw else json.dumps(value).encode()
        try:
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            if hasattr(self, "owned"):
                self.owned["disconnects"] += 1

    def do_GET(self):
        self.handle_request(False)

    def do_POST(self):
        self.handle_request(True)

    def handle_request(self, post):
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)
        body = self.rfile.read(int(self.headers.get("Content-Length", "0"))) if post else b""
        if parsed.path.startswith("/control/"):
            name = parsed.path.split("/")[-1]
            with lock:
                state = account(name)
                if post:
                    data = json.loads(body)
                    state.update(data)
                    if "seed" in data:
                        state["messages"] = [message(x) for x in data["seed"]]
                return self.reply(200, {k: state[k] for k in ("mutations", "sends", "details", "lists", "requests", "disconnects")})
        if parsed.path.startswith("/app/"):
            data = json.loads(body)
            with lock:
                state = account(data["account"])
                state["mutations"] += 1
                state["fault"] = data.get("fault", "")
                for token in data.get("tokens", []):
                    state["messages"].append(message("test-" + token + "@fixture.invalid", data.get("subject", "Welcome")))
                if state["fault"] == "duplicate":
                    state["messages"].append(copy.deepcopy(state["messages"][-1]))
            return self.reply(201, {"ok": True})
        if parsed.path == "/ticket":
            token = query.get("id", [""])[0]
            with lock:
                present = any(token in s["tickets"] for s in accounts.values())
            return self.reply(200, present)
        name = self.headers.get("Authorization", "").removeprefix("Bearer ")
        with lock:
            state = account(name)
            self.owned = state
            state["requests"] += 1
            fault = state["fault"]
        if parsed.path == "/emails" and post:
            with lock:
                state["sends"] += 1
                data = json.loads(body)
                key = self.headers.get("Idempotency-Key")
                if not key:
                    return self.reply(400, {"message": "ERROR-PRIVATE missing key"})
                previous = state["keys"].get(key)
                if previous and previous[0] != data:
                    return self.reply(409, {"message": "ERROR-PRIVATE conflicting key"})
                identity = previous[1] if previous else str(uuid.uuid4())
                if not previous:
                    state["keys"][key] = (data, identity)
                    if state["deliver"]:
                        for destination in data["to"]:
                            state["messages"].append(message(destination, data["subject"]))
                    if data["subject"] == "Ticket":
                        state["tickets"].extend(x.split("@", 1)[0].removeprefix("test-") for x in data["to"])
            if fault == "send-slow":
                time.sleep(0.4)
            if fault == "send-invalid":
                return self.reply(200, b'{"ERROR-PRIVATE":', True)
            return self.reply(200, {"id": identity})
        if parsed.path == "/emails/receiving":
            with lock:
                state["lists"] += 1
                messages = copy.deepcopy(state["messages"])
                if fault == "once429":
                    state["fault"] = ""
            if fault in ("once429", "401", "403", "429", "500"):
                return self.reply(429 if fault == "once429" else int(fault), {"message": "ERROR-PRIVATE"})
            if fault == "slow":
                time.sleep(0.4)
                if select.select([self.connection], [], [], 0)[0] and self.connection.recv(1, socket.MSG_PEEK) == b"":
                    with lock:
                        state["disconnects"] += 1
            if fault == "invalid":
                return self.reply(200, b'{"ERROR-PRIVATE":', True)
            if fault == "large":
                return self.reply(200, b"CONTENT-PRIVATE" * 20000, True)
            limit = int(query.get("limit", ["0"])[0])
            if limit < 1 or limit > 100:
                return self.reply(400, {"message": "must send limit"})
            after = query.get("after", [None])[0]
            ids = [m["id"] for m in messages]
            start = ids.index(after) + 1 if after in ids else 0
            refs = [dict(id=m["id"], to=m["to"]) for m in messages[start:start + limit]]
            more = start + limit < len(messages)
            if fault == "loop":
                refs, more = [dict(id="repeated", to=["other@fixture.invalid"])], True
            if fault == "empty":
                refs, more = [], True
            if fault == "missing-to":
                refs = [dict(id="missing-to")]
            if fault == "missing-id":
                refs = [dict(to=["other@fixture.invalid"])]
            if fault == "path-id":
                refs = [dict(id="https://URL-PRIVATE.invalid/raw", to=["other@fixture.invalid"])]
            return self.reply(200, dict(data=refs, has_more=more))
        if parsed.path.startswith("/emails/receiving/"):
            with lock:
                state["details"] += 1
                identity = parsed.path.split("/")[-1]
                found = next((copy.deepcopy(m) for m in state["messages"] if m["id"] == identity), None)
            if query.get("html_format") != ["cid"]:
                return self.reply(400, {"message": "must request cid"})
            if not found or fault == "detail-missing":
                return self.reply(404, {"message": "ERROR-PRIVATE"})
            if fault == "detail-id":
                found["id"] = "different"
            if fault == "detail-to":
                found["to"] = ["other@fixture.invalid"]
            if fault == "nullable":
                found["text"], found["html"] = None, None
            if fault == "detail-invalid":
                del found["subject"]
            return self.reply(200, found)
        return self.reply(404, {"message": "ERROR-PRIVATE"})


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
server.daemon_threads = True
Path(sys.argv[1]).write_text(str(server.server_port))
server.serve_forever()
