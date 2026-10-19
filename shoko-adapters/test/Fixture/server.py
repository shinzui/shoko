"""Local adapter fixture only; its database is created by scripts/test-adapters."""
import http.server
import json
import os
import pathlib
import subprocess
import sys
import threading
import time
import urllib.parse

counts = {}
lock = threading.Lock()


def sql(statement, key):
    return subprocess.run(
        ["psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1", "-v", f"key={key}"],
        input=statement, text=True, capture_output=True, check=True,
    ).stdout.strip()


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def send(self, status, body):
        self.send_response(status)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_POST(self):
        key = self.rfile.read(int(self.headers.get("Content-Length", "0"))).decode()
        with lock:
            counts[self.path] = counts.get(self.path, 0) + 1
        if self.path == "/create":
            sql("INSERT INTO fixture.accounts(id, value) VALUES (:'key', NULL);", key)
            self.send(201, key.encode())
        elif self.path == "/invalid":
            self.send(422, b"invalid-input")
        elif self.path == "/different":
            self.send(409, b"duplicate")
        elif self.path == "/undecodable":
            self.send(500, b"OTP-ADAPTER-SECRET-SENTINEL")
        elif self.path == "/slow":
            time.sleep(0.4)
            self.send(201, key.encode())
        elif self.path == "/redirect":
            self.send_response(307)
            self.send_header("Location", "/create")
            self.send_header("Content-Length", "0")
            self.end_headers()
        elif self.path == "/large":
            self.send(200, b"x" * 8192)
        elif self.path == "/execution":
            self.send(200, self.headers.get("x-shoko-execution-id", "none").encode())
        elif self.path == "/headers":
            okay = (self.headers.get("traceparent") == "00-0123456789abcdef0123456789abcdef-0123456789abcdef-01"
                    and self.headers.get("x-shoko-execution-id") == "adapter-run")
            self.send(200, b"true" if okay else b"false")
        else:
            self.send(201, key.encode())

    def do_GET(self):
        parsed = urllib.parse.urlsplit(self.path)
        if parsed.path == "/metrics":
            with lock:
                self.send(200, json.dumps(counts).encode())
        elif parsed.path == "/read":
            key = urllib.parse.parse_qs(parsed.query).get("id", [""])[0]
            exists = sql("SELECT EXISTS(SELECT 1 FROM fixture.accounts WHERE id = :'key');", key)
            self.send(200, b"true" if exists == "t" else b"false")
        else:
            self.send(404, b"missing")


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
pathlib.Path(sys.argv[1]).write_text(str(server.server_port))
server.serve_forever()
