"""Strict HTTP fixture server for the Petstore end-to-end demo.

The generated MoonBit client drives this server. Every request is recorded and
checked against the wire contract declared in ``openapi.json``; deviations are
written to the capture file so the demo fails on evidence rather than on a
printed log.

Endpoints
    GET    /pets/{id}?verbose=true     -> 200 Pet        (bearer, X-Trace required)
    POST   /pets                       -> 201 Pet        (bearer, JSON body)
    DELETE /pets                       -> 204 (no body)  (bearer)
    GET    /auth/bearer                -> 200 AuthEcho   (bearer)
    GET    /auth/basic                 -> 200 AuthEcho   (basic)
    GET    /auth/api-key-header        -> 200 AuthEcho   (apiKey in X-Api-Key)
    GET    /auth/api-key-query         -> 200 AuthEcho   (apiKey in ?api_key=)
    anything else                      -> 404 JSON error

Capture files separate three kinds of fact:

``checks``      wire expectations that were met
``errors``      contract violations (the demo fails when this is non-empty)
``rejections``  credentials the server deliberately refused; the demo asserts a
                specific count, because a refused credential is an expected
                response for the negative probes rather than a bug
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

STATE_LOCK = threading.Lock()
STATE: dict[str, list] = {
    "requests": [],
    "errors": [],
    "checks": [],
    "rejections": [],
}

PET_STATUSES = ("available", "pending", "sold")


def _record(entry: dict) -> None:
    with STATE_LOCK:
        STATE["requests"].append(entry)


def _fail(message: str) -> None:
    with STATE_LOCK:
        STATE["errors"].append(message)


def _check(name: str) -> None:
    with STATE_LOCK:
        STATE["checks"].append(name)


def _reject(message: str) -> None:
    with STATE_LOCK:
        STATE["rejections"].append(message)


class PetstoreHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "oas2moon-demo-fixture"
    sys_version = ""

    # ------------------------------------------------------------------ utils
    def log_message(self, fmt: str, *args) -> None:  # noqa: A003
        sys.stderr.write("fixture: " + (fmt % args) + "\n")
        sys.stderr.flush()

    def _read_body(self) -> str:
        length = self.headers.get("Content-Length")
        if not length:
            return ""
        return self.rfile.read(int(length)).decode("utf-8")

    def _respond(self, status: int, payload: dict | None) -> None:
        # Persist the completed request state before releasing the response.
        # Otherwise the client can finish and the demo can stop this process
        # while the final capture write is still pending.
        self._write_capture()
        body = b"" if payload is None else json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        if body:
            self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _deny(self, scheme: str, actual: str | None) -> None:
        _reject("rejected %s credential: %r" % (scheme, actual))
        self._respond(401, {"error": "unauthorized", "scheme": scheme})

    # -------------------------------------------------------------- auth checks
    def _require_bearer(self) -> bool:
        expected = "Bearer " + self.server.bearer_token  # type: ignore[attr-defined]
        actual = self.headers.get("Authorization")
        if actual != expected:
            self._deny("bearer", actual)
            return False
        _check("auth.bearer")
        return True

    def _require_basic(self) -> bool:
        raw = "%s:%s" % (
            self.server.basic_user,  # type: ignore[attr-defined]
            self.server.basic_password,  # type: ignore[attr-defined]
        )
        expected = "Basic " + base64.b64encode(raw.encode("utf-8")).decode("ascii")
        actual = self.headers.get("Authorization")
        if actual != expected:
            self._deny("basic", actual)
            return False
        _check("auth.basic")
        return True

    def _require_api_key(self, source: str) -> bool:
        expected = self.server.api_key  # type: ignore[attr-defined]
        if source == "header":
            actual = self.headers.get("X-Api-Key")
        else:
            actual = parse_qs(urlparse(self.path).query, keep_blank_values=True).get(
                "api_key", [None]
            )[0]
        if actual != expected:
            self._deny("apiKey(%s)" % source, actual)
            return False
        _check("auth.apiKey." + source)
        return True

    # ---------------------------------------------------------------- dispatch
    def _dispatch(self, method: str) -> None:
        parsed = urlparse(self.path)
        body = self._read_body()
        _record(
            {
                "method": method,
                "path": parsed.path,
                "raw_target": self.path,
                "query": parse_qs(parsed.query, keep_blank_values=True),
                "headers": {k.lower(): v for k, v in self.headers.items()},
                "body": body,
            }
        )
        try:
            handler = getattr(self, "_handle_" + method.lower(), None)
            if handler is None:
                _fail("unsupported method: %s" % method)
                self._respond(405, {"error": "method not allowed"})
            else:
                handler(parsed, body)
        except Exception as exc:  # pragma: no cover - defensive
            _fail("handler crash for %s %s: %r" % (method, self.path, exc))
            self._respond(500, {"error": "fixture crash"})

    def _write_capture(self) -> None:
        target = self.server.capture_path  # type: ignore[attr-defined]
        # Serialize the complete write. Concurrent handlers share one temporary
        # path, so taking only a state snapshot under the lock can let a delayed
        # older snapshot overwrite a newer complete capture.
        with STATE_LOCK:
            snapshot = {
                "requests": list(STATE["requests"]),
                "errors": list(STATE["errors"]),
                "checks": list(STATE["checks"]),
                "rejections": list(STATE["rejections"]),
            }
            tmp = target + ".tmp"
            with open(tmp, "w", encoding="utf-8", newline="\n") as handle:
                json.dump(snapshot, handle, ensure_ascii=False, indent=2, sort_keys=True)
                handle.write("\n")
            os.replace(tmp, target)

    # --------------------------------------------------------------- handlers
    def _handle_get(self, parsed, body) -> None:
        auth_routes = {
            "/auth/bearer": ("bearer", lambda: self._require_bearer()),
            "/auth/basic": ("basic", lambda: self._require_basic()),
            "/auth/api-key-header": (
                "apiKey(header)",
                lambda: self._require_api_key("header"),
            ),
            "/auth/api-key-query": (
                "apiKey(query)",
                lambda: self._require_api_key("query"),
            ),
        }
        route = auth_routes.get(parsed.path)
        if route is not None:
            label, check = route
            if not check():
                return
            self._respond(200, {"scheme": label})
            return

        if not self._require_bearer():
            return
        prefix = "/pets/"
        if not parsed.path.startswith(prefix):
            # Deliberate error-path probe from the generated client.
            self._respond(404, {"error": "not found", "path": parsed.path})
            return
        raw_id = parsed.path[len(prefix) :]
        try:
            pet_id = int(raw_id)
        except ValueError:
            _fail("path parameter is not an integer: %r" % raw_id)
            self._respond(400, {"error": "bad path parameter"})
            return
        _check("get.path_parameter")

        trace = self.headers.get("X-Trace")
        if trace != "trace-get":
            _fail("X-Trace header mismatch: %r" % trace)
            self._respond(400, {"error": "bad header"})
            return
        _check("get.header_parameter")

        query = parse_qs(parsed.query, keep_blank_values=True)
        if query.get("verbose") != ["true"]:
            _fail("query parameter mismatch: %r" % query)
            self._respond(400, {"error": "bad query"})
            return
        _check("get.query_parameter")

        if body:
            _fail("GET must not carry a body, received %r" % body)
        self._respond(
            200,
            {
                "id": pet_id,
                "name": "Spike",
                "status": "available",
                "tags": ["fluffy", "friendly"],
                "nickname": None,
            },
        )

    def _handle_post(self, parsed, body) -> None:
        if not self._require_bearer():
            return
        if parsed.path != "/pets":
            self._respond(404, {"error": "not found", "path": parsed.path})
            return
        _check("post.path")

        content_type = self.headers.get("Content-Type") or ""
        if not content_type.startswith("application/json"):
            _fail("POST Content-Type mismatch: %r" % content_type)
            self._respond(415, {"error": "bad media type"})
            return
        _check("post.content_type")

        try:
            payload = json.loads(body)
        except ValueError as exc:
            _fail("POST body is not JSON: %r" % exc)
            self._respond(400, {"error": "bad body"})
            return
        if not isinstance(payload, dict):
            _fail("POST body is not a JSON object")
            self._respond(400, {"error": "bad body"})
            return
        _check("post.json_body")

        for key in ("id", "name", "status"):
            if key not in payload:
                _fail("POST body is missing required key %r" % key)
        if payload.get("status") not in PET_STATUSES:
            _fail("POST body has unknown enum value: %r" % payload.get("status"))
        if payload.get("tags") != ["a", "b"]:
            _fail("POST body tags mismatch: %r" % payload.get("tags"))
        if "nickname" in payload:
            _fail("POST body set an optional nullable field it never assigned")
        _check("post.optional_omitted")

        self._respond(201, payload)

    def _handle_delete(self, parsed, body) -> None:
        if not self._require_bearer():
            return
        if parsed.path != "/pets":
            self._respond(404, {"error": "not found", "path": parsed.path})
            return
        _check("delete.path")
        if body:
            _fail("DELETE must not carry a body, received %r" % body)
        self._respond(204, None)

    def do_GET(self) -> None:  # noqa: N802
        self._dispatch("GET")

    def do_POST(self) -> None:  # noqa: N802
        self._dispatch("POST")

    def do_DELETE(self) -> None:  # noqa: N802
        self._dispatch("DELETE")


class FixtureServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    capture_path: str
    bearer_token: str
    basic_user: str
    basic_password: str
    api_key: str


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18080)
    parser.add_argument("--token", default="demo-token")
    parser.add_argument("--basic-user", default="demo-user")
    parser.add_argument("--basic-password", default="demo-pass")
    parser.add_argument("--api-key", default="demo-api-key")
    parser.add_argument("--capture", required=True)
    args = parser.parse_args()

    with STATE_LOCK:
        for value in STATE.values():
            value.clear()

    server = FixtureServer((args.host, args.port), PetstoreHandler)
    server.capture_path = args.capture  # type: ignore[attr-defined]
    server.bearer_token = args.token  # type: ignore[attr-defined]
    server.basic_user = args.basic_user  # type: ignore[attr-defined]
    server.basic_password = args.basic_password  # type: ignore[attr-defined]
    server.api_key = args.api_key  # type: ignore[attr-defined]
    print(
        "fixture server listening on http://%s:%d (capture=%s)"
        % (args.host, args.port, args.capture),
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
