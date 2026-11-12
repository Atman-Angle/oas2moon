"""Acceptance regression coverage for the defects found in the 2026-11-11
independent acceptance review (Codex thread 01a1cb1c).

Every case asserts user-visible behavior, not internal IR:

* unsupported semantics stop the CLI with a non-zero exit, a stable diagnostic
  code/pointer, and no generated SDK;
* the Int64 cases decode through the generated client over a local HTTP server,
  so precision and type rejection are proven on the wire, not by reading code.

These cases fail on the pre-fix candidate 563702a (silent acceptance, empty
structs, codegen panic, or a MoonBit panic) and pass after the remediation.
"""
import json
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "tests/_build/acceptance-regressions"


def run(args, cwd=ROOT):
    return subprocess.run(
        args, cwd=cwd, capture_output=True, text=True,
        encoding="utf-8", errors="replace", timeout=180,
    )


def generate(spec, label):
    work = BUILD / label
    work.mkdir(parents=True, exist_ok=True)
    source, out = work / "spec.json", work / "sdk"
    source.write_text(json.dumps(spec), encoding="utf-8")
    result = run([
        sys.executable, str(ROOT / "oas2moon.py"), "generate", str(source),
        "--module", "acceptance/sdk", "--out", str(out),
    ])
    return result, out


def spec(title, paths, schemas=None):
    doc = {"openapi": "3.0.3", "info": {"title": title, "version": "1"},
           "paths": paths}
    if schemas is not None:
        doc["components"] = {"schemas": schemas}
    return doc


def json_response(schema):
    return {"description": "ok",
            "content": {"application/json": {"schema": schema}}}


def media_response(media):
    return {"description": "ok", "content": {media: {"schema": {"type": "string"}}}}


def media_request(media):
    return {"required": True, "content": {media: {"schema": {"type": "string"}}}}


def op(responses=None, request_body=None, operation_id="getX"):
    body = {"operationId": operation_id}
    if responses is not None:
        body["responses"] = responses
    if request_body is not None:
        body["requestBody"] = request_body
    return body


# ── unsupported semantics: must reject, never silently generate ──────────

NEGATIVE_CASES = [
    # P1: unclassified request media types (body silently dropped before fix)
    ("request-multipart",
     spec("m", {"/u": {"post": op(request_body=media_request("multipart/form-data"),
                                  responses={"200": json_response({"type": "string"})})}}),
     "unsupported.media_type", "requestBody/content/multipart~1form-data"),
    ("request-xml",
     spec("m", {"/u": {"post": op(request_body=media_request("application/xml"),
                                  responses={"200": json_response({"type": "string"})})}}),
     "unsupported.media_type", "requestBody/content/application~1xml"),
    ("request-octet-stream",
     spec("m", {"/u": {"post": op(request_body=media_request("application/octet-stream"),
                                  responses={"200": json_response({"type": "string"})})}}),
     "unsupported.media_type", "requestBody/content/application~1octet-stream"),
    ("request-form-urlencoded",
     spec("m", {"/u": {"post": op(request_body=media_request("application/x-www-form-urlencoded"),
                                  responses={"200": json_response({"type": "string"})})}}),
     "unsupported.media_type", "requestBody/content/application~1x-www-form-urlencoded"),
    # P1: unclassified response media types (IR became no_content before fix)
    ("response-text",
     spec("m", {"/x": {"get": op(responses={"200": media_response("text/plain")})}}),
     "unsupported.media_type", "responses/200/content/text~1plain"),
    ("response-xml",
     spec("m", {"/x": {"get": op(responses={"200": media_response("application/xml")})}}),
     "unsupported.media_type", "responses/200/content/application~1xml"),
    ("response-multipart",
     spec("m", {"/x": {"get": op(responses={"200": media_response("multipart/form-data")})}}),
     "unsupported.media_type", "responses/200/content/multipart~1form-data"),
    # P1: external / cyclic / missing local refs
    ("ref-external",
     spec("r", {"/x": {"get": op(responses={"200": json_response({"$ref": "#/components/schemas/Thing"})})}},
          schemas={"Thing": {"$ref": "./other.json#/components/schemas/Thing"}}),
     "unsupported.ref", "#/components/schemas/Thing/$ref"),
    ("ref-cycle",
     spec("r", {"/x": {"get": op(responses={"200": json_response({"$ref": "#/components/schemas/Node"})})}},
          schemas={"Node": {"type": "object", "properties": {"next": {"$ref": "#/components/schemas/Node"}}}}),
     "unsupported.ref", "#/components/schemas/Node"),
    ("ref-missing",
     spec("r", {"/x": {"get": op(responses={"200": json_response({"$ref": "#/components/schemas/Nope"})})}}),
     "unsupported.ref", "Missing local schema reference"),
    # P1: root-level webhooks and operation callbacks
    ("webhooks",
     {"openapi": "3.0.3", "info": {"title": "w", "version": "1"}, "paths": {},
      "webhooks": {"hook": {"post": {"operationId": "postX", "responses": {"204": {"description": "ok"}}}}}},
     "unsupported.keyword", "#/webhooks"),
    ("callbacks",
     spec("c", {"/x": {"post": {"operationId": "postX", "callbacks": {"cb": {}},
                                "responses": {"204": {"description": "ok"}}}}}),
     "unsupported.keyword", "callbacks"),
    # P1: non-string enums (empty struct before fix) and duplicate wires (panic)
    ("enum-integer",
     spec("e", {"/x": {"get": op(responses={"200": json_response({"$ref": "#/components/schemas/Choice"})})}},
          schemas={"Choice": {"type": "integer", "enum": [1, 2]}}),
     "unsupported.enum", "#/components/schemas/Choice/enum"),
    ("enum-boolean",
     spec("e", {"/x": {"get": op(responses={"200": json_response({"$ref": "#/components/schemas/Choice"})})}},
          schemas={"Choice": {"type": "boolean", "enum": [True, False]}}),
     "unsupported.enum", "#/components/schemas/Choice/enum"),
    ("enum-duplicate",
     spec("e", {"/x": {"get": op(responses={"200": json_response({"$ref": "#/components/schemas/Choice"})})}},
          schemas={"Choice": {"type": "string", "enum": ["a", "a"]}}),
     "unsupported.enum", "Duplicate enum value"),
]


@pytest.mark.parametrize("label,doc,code,pointer", NEGATIVE_CASES,
                         ids=[c[0] for c in NEGATIVE_CASES])
def test_unsupported_rejected(label, doc, code, pointer):
    result, out = generate(doc, label)
    assert result.returncode == 4, result.stderr
    assert code in result.stderr, result.stderr
    assert pointer in result.stderr, result.stderr
    assert not (out / "models.mbt").exists()
    assert not (out / "client.mbt").exists()


def test_json_media_and_valid_enum_still_generate():
    """Positive controls: the rejection must not over-fire on supported input."""
    media = spec("ok", {"/x": {"get": op(responses={"200": json_response({"type": "string"})})}})
    result, out = generate(media, "positive-media")
    assert result.returncode == 0, result.stderr
    assert (out / "client.mbt").exists()

    enum = spec("ok", {"/x": {"get": op(responses={"200": json_response({"$ref": "#/components/schemas/Choice"})})}},
                schemas={"Choice": {"type": "string", "enum": ["a", "b"]}})
    result, out = generate(enum, "positive-enum")
    assert result.returncode == 0, result.stderr
    assert (out / "models.mbt").exists()


# ── Int64 precision and type rejection through the generated client ──────

# (raw JSON body, expected Int64 value or None for a required decode error)
INT64_CASES = [
    ("0", 0),
    ("1", 1),
    ("9007199254740991", 9007199254740991),
    ("9007199254740992", 9007199254740992),
    ("9007199254740993", 9007199254740993),   # must NOT round to ...992
    ("9223372036854775807", 9223372036854775807),   # Int64 max
    ("-9223372036854775808", -9223372036854775808),  # Int64 min
    ("9223372036854775808", None),             # max + 1
    ("-9223372036854775809", None),            # min - 1
    ("1.0", 1),                                # integral decimal
    ("1e3", 1000),                             # integral exponent
    ("true", None),                            # boolean
    ('"9007199254740993"', None),               # JSON string must be rejected
]


def test_int64_wire_decode():
    bodies = [c[0] for c in INT64_CASES]
    state = {"i": 0}
    seen = []

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_GET(self):
            seen.append(self.path)
            if self.path.endswith("/thing"):
                body = b'{"id":9007199254740993}'
            else:
                body = bodies[state["i"]].encode()
                state["i"] += 1
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body)

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        doc = spec("Int64", {
            "/value": {"get": op(operation_id="getValue",
                                 responses={"200": json_response({"type": "integer", "format": "int64"})})},
            "/thing": {"get": op(operation_id="getThing",
                                 responses={"200": json_response({"$ref": "#/components/schemas/Thing"})})},
        }, schemas={"Thing": {"type": "object", "required": ["id"],
                              "properties": {"id": {"type": "integer", "format": "int64"}}}})
        doc["servers"] = [{"url": "http://127.0.0.1:%d" % server.server_port}]
        result, out = generate(doc, "int64")
        assert result.returncode == 0, result.stderr

        lines = ['///|', 'async test "int64 boundary decode" {', '  let c = Client::new()']
        for i, (_raw, expected) in enumerate(INT64_CASES):
            if expected is None:
                lines.append(
                    '  try { ignore(c.get_value()); fail("case %d accepted") } '
                    'catch { Decode(_, _) => (); _ => fail("case %d wrong error") }' % (i, i))
            else:
                lines.append('  assert_eq(c.get_value(), %dL) // case %d' % (expected, i))
        # field-level Int64 must be exact too (exercises the generated __dec_i64)
        lines.append('  assert_eq(c.get_thing().id, 9007199254740993L)')
        lines.append('}')
        (out / "int64_wbtest.mbt").write_text("\n".join(lines) + "\n", encoding="utf-8")
        pkg = out / "moon.pkg"
        pkg.write_text(pkg.read_text(encoding="utf-8")
                       + '\nimport { "moonbitlang/async", } for "wbtest"\n', encoding="utf-8")
        for cmd in (["moon", "fmt"],
                    ["moon", "check", "--target", "native", "--deny-warn"],
                    ["moon", "test", "--target", "native", "--deny-warn"]):
            checked = run(cmd, out)
            assert checked.returncode == 0, checked.stdout + checked.stderr
        # one /value request per scalar case, plus one /thing request
        assert len(seen) == len(INT64_CASES) + 1, seen
    finally:
        server.shutdown()
        server.server_close()
        thread.join()