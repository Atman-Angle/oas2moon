"""Spike-only HTTP fixture server for the oas2moon feasibility spike.

Serves the Petstore fixture described by ``fixtures/petstore/openapi.json`` and
asserts the wire behaviour the generated client is expected to produce. Every
request is recorded to a capture file so the spike report can quote real
evidence instead of assuming the client behaved correctly.

The server is deliberately strict: any deviation from the expected
method/path/query/header/body is recorded in ``errors`` and the capture file is
rewritten after every request. The spike fails if ``errors`` is not empty.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

STATE_LOCK = threading.Lock()
STATE: dict[str, list] = {"requests": [], "errors": [], "checks": []}


def _record(record: dict) -> None:
    with STATE_LOCK:
        STATE["requests"].append(record)


def _fail(message: str) -> None:
    with STATE_LOCK:
        STATE["errors"].append(message)


def _check(name: str) -> None:
    with STATE_LOCK:
        STATE["checks"].append(name)


class PetstoreHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "oas2moon-spike-fixture"
    sys_version = ""

    # ---------------------------------------------------------------- helpers

    def log_message(self, fmt: str, *args) -> None:  # noqa: A003
        sys.stderr.write("fixture: " + (fmt % args) + "\n")
        sys.stderr.flush()

    def _body(self) -> str:
        length = self.headers.get("Content-Length")
        if not length:
            return ""
        return self.rfile.read(int(length)).decode("utf-8")

    def _respond(self, status: int, payload: str | None) -> None:
        body = b"" if payload is None else payload.encode("utf-8")
        self.send_response(status)
        if payload is not None:
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
        else:
            self.send_header("Content-Length", "0")
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _dispatch(self, method: str) -> None:
        parsed = urlparse(self.path)
        body = self._body()
        record = {
            "method": method,
            "path": parsed.path,
            "raw_target": self.path,
            "query": parse_qs(parsed.query, keep_blank_values=True),
            "headers": {k.lower(): v for k, v in self.headers.items()},
            "body": body,
        }
        _record(record)
        try:
            handler = getattr(self, f"_handle_{method.lower()}", None)
            if handler is None:
                _fail(f"unsupported method {method}")
                self._respond(405, json.dumps({"error": "unsupported method"}))
            else:
                handler(parsed, body, record)
        except Exception as exc:  # pragma: no cover - fixture failure path
            _fail(f"handler crash for {method} {self.path}: {exc!r}")
            self._respond(500, json.dumps({"error": "fixture crash"}))
        finally:
            self._capture()

    def _capture(self) -> None:
        target = self.server.capture_path  # type: ignore[attr-defined]
        with STATE_LOCK:
            snapshot = {
                "requests": list(STATE["requests"]),
                "errors": list(STATE["errors"]),
                "checks": list(STATE["checks"]),
            }
        tmp = target + ".tmp"
        with open(tmp, "w", encoding="utf-8", newline="\n") as handle:
            json.dump(snapshot, handle, ensure_ascii=False, indent=2, sort_keys=True)
            handle.write("\n")
        os.replace(tmp, target)

    def _auth_ok(self) -> bool:
        expected = f"Bearer {self.server.expected_token}"  # type: ignore[attr-defined]
        actual = self.headers.get("Authorization")
        if actual != expected:
            _fail(
                "authorization header mismatch: expected "
                f"{expected!r}, received {actual!r}",
            )
            self._respond(401, json.dumps({"error": "unauthorized"}))
            return False
        _check("authorization")
        return True

    # --------------------------------------------------------------- handlers

    def _handle_get(self, parsed, body, record) -> None:
        if not self._auth_ok():
            return
        prefix = "/pets/"
        if not parsed.path.startswith(prefix):
            _fail(f"unexpected path for GET: {parsed.path}")
            self._respond(404, json.dumps({"error": "not found"}))
            return
        raw_id = parsed.path[len(prefix) :]
        try:
            pet_id = int(raw_id)
        except ValueError:
            _fail(f"path parameter is not an integer: {raw_id!r}")
            self._respond(400, json.dumps({"error": "bad path parameter"}))
            return
        _check("get.path_parameter")
        trace = self.headers.get("X-Trace")
        if trace != "trace-get":
            _fail(f"X-Trace header mismatch: {trace!r}")
            self._respond(400, json.dumps({"error": "bad header"}))
            return
        _check("get.header_parameter")
        query = parse_qs(parsed.query, keep_blank_values=True)
        if query.get("verbose") != ["true"]:
            _fail(f"query mismatch: {query!r}")
            self._respond(400, json.dumps({"error": "bad query"}))
            return
        _check("get.query_parameter")
        if body:
            _fail(f"GET must not carry a body, received {body!r}")
        payload = json.dumps(
            {
                "id": pet_id,
                "name": "Spike",
                "status": "available",
                "tags": ["fluffy", "friendly"],
                "nickname": None,
            },
            ensure_ascii=False,
        )
        self._respond(200, payload)

    def _handle_post(self, parsed, body, record) -> None:
        if not self._auth_ok():
            return
        if parsed.path != "/pets":
            _fail(f"unexpected path for POST: {parsed.path}")
            self._respond(404, json.dumps({"error": "not found"}))
            return
        _check("post.path")
        content_type = self.headers.get("Content-Type") or ""
        if not content_type.startswith("application/json"):
            _fail(f"POST Content-Type mismatch: {content_type!r}")
            self._respond(415, json.dumps({"error": "bad media type"}))
            return
        _check("post.content_type")
        try:
            parsed_body = json.loads(body)
        except ValueError as exc:
            _fail(f"POST body is not JSON: {exc!r}")
            self._respond(400, json.dumps({"error": "bad body"}))
            return
        if not isinstance(parsed_body, dict):
            _fail("POST body is not a JSON object")
            self._respond(400, json.dumps({"error": "bad body"}))
            return
        _check("post.json_body")
        record["parsed_body"] = parsed_body
        for key in ("id", "name", "status"):
            if key not in parsed_body:
                _fail(f"POST body is missing required key {key!r}")
        if parsed_body.get("status") not in ("available", "pending", "sold"):
            _fail(f"POST body has an unknown enum value: {parsed_body.get('status')!r}")
        if "nickname" in parsed_body:
            _fail("POST body contains the optional key 'nickname' although it was never set")
        if parsed_body.get("tags") != ["a", "b"]:
            _fail(f"POST body tags mismatch: {parsed_body.get('tags')!r}")
        _check("post.optional_omitted")
        self._respond(201, json.dumps(parsed_body, ensure_ascii=False))

    def _handle_delete(self, parsed, body, record) -> None:
        if not self._auth_ok():
            return
        if parsed.path != "/pets":
            _fail(f"unexpected path for DELETE: {parsed.path}")
            self._respond(404, json.dumps({"error": "not found"}))
            return
        if body:
            _fail(f"DELETE must not carry a body, received {body!r}")
        _check("delete.path")
        self._respond(204, None)

    def do_GET(self) -> None:  # noqa: N802
        self._dispatch("GET")

    def do_POST(self) -> None:  # noqa: N802
        self._dispatch("POST")

    def do_DELETE(self) -> None:  # noqa: N802
        self._dispatch("DELETE")

    def do_PUT(self) -> None:  # noqa: N802
        self._dispatch("PUT")

    def do_PATCH(self) -> None:  # noqa: N802
        self._dispatch("PATCH")


class FixtureServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    capture_path: str
    expected_token: str


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18080)
    parser.add_argument("--token", default="spike-token")
    parser.add_argument("--capture", required=True)
    args = parser.parse_args()
    server = FixtureServer((args.host, args.port), PetstoreHandler)
    server.capture_path = args.capture  # type: ignore[attr-defined]
    server.expected_token = args.token  # type: ignore[attr-defined]
    with STATE_LOCK:
        STATE["requests"].clear()
        STATE["errors"].clear()
        STATE["checks"].clear()
    print(
        f"fixture server listening on http://{args.host}:{args.port} "
        f"(capture={args.capture})",
        flush=True,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
