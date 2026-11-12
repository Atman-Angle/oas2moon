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
import shutil
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
    if out.exists():
        shutil.rmtree(out)
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


# ── defect B: top-level array/primitive components must decode legal wire ──

def test_component_array_and_primitive_aliases():
    """A top-level array/primitive component lowers to a transparent alias, not
    an empty struct. Before the fix the official OAI `Pets` array component
    became an empty struct and a legal list raised Decode("expected a JSON
    object"); compile_pass masked it. Proven here through the generated client
    over a local HTTP server.
    """
    bodies = {
        "/pets": b'[{"id":9007199254740993,"name":"Rex"}]',
        "/empty": b'[]',
        "/count": b'9223372036854775807',
        "/ids": b'[9007199254740993,9223372036854775807,-9223372036854775808]',
        "/names": b'["a","b"]',
        "/label": b'"hello"',
        "/flag": b'true',
        "/badids": b'["9007199254740993"]',
    }
    seen = []

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_GET(self):
            seen.append(self.path)
            body = bodies.get(self.path, b'null')
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body)

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        ref = lambda name: {"$ref": "#/components/schemas/" + name}
        doc = spec("Aliases", {
            "/pets": {"get": op(operation_id="listPets", responses={"200": json_response(ref("Pets"))})},
            "/empty": {"get": op(operation_id="listEmpty", responses={"200": json_response(ref("Pets"))})},
            "/count": {"get": op(operation_id="getCount", responses={"200": json_response(ref("Count"))})},
            "/ids": {"get": op(operation_id="getIds", responses={"200": json_response(ref("Ids"))})},
            "/names": {"get": op(operation_id="getNames", responses={"200": json_response(ref("Names"))})},
            "/label": {"get": op(operation_id="getLabel", responses={"200": json_response(ref("Label"))})},
            "/flag": {"get": op(operation_id="getFlag", responses={"200": json_response(ref("Flag"))})},
            "/badids": {"get": op(operation_id="getBadIds", responses={"200": json_response(ref("Ids"))})},
        }, schemas={
            "Pet": {"type": "object", "required": ["id", "name"],
                    "properties": {"id": {"type": "integer", "format": "int64"},
                                   "name": {"type": "string"}}},
            "Pets": {"type": "array", "items": ref("Pet")},
            "Count": {"type": "integer", "format": "int64"},
            "Ids": {"type": "array", "items": {"type": "integer", "format": "int64"}},
            "Names": {"type": "array", "items": {"type": "string"}},
            "Label": {"type": "string"},
            "Flag": {"type": "boolean"},
        })
        doc["servers"] = [{"url": "http://127.0.0.1:%d" % server.server_port}]
        result, out = generate(doc, "aliases")
        assert result.returncode == 0, result.stderr
        # the array component must be an alias, never an empty struct
        models = (out / "models.mbt").read_text(encoding="utf-8")
        assert "pub type Pets = Array[Pet]" in models, models

        (out / "alias_wbtest.mbt").write_text('''///|
async test "component aliases decode legal wire" {
  let c = Client::new()
  let pets = c.list_pets()
  assert_eq(pets.length(), 1)
  assert_eq(pets[0].id, 9007199254740993L)
  assert_eq(pets[0].name, "Rex")
  assert_eq(c.list_empty().length(), 0)
  assert_eq(c.get_count(), 9223372036854775807L)
  assert_eq(c.get_ids(), [9007199254740993L, 9223372036854775807L, -9223372036854775808L])
  assert_eq(c.get_names(), ["a", "b"])
  assert_eq(c.get_label(), "hello")
  assert_eq(c.get_flag(), true)
  try { ignore(c.get_bad_ids()); fail("string element accepted") }
  catch { Decode(_, _) => (); _ => fail("wrong error") }
}
''', encoding="utf-8")
        pkg = out / "moon.pkg"
        pkg.write_text(pkg.read_text(encoding="utf-8")
                       + '\nimport { "moonbitlang/async", } for "wbtest"\n', encoding="utf-8")
        for cmd in (["moon", "fmt"],
                    ["moon", "check", "--target", "native", "--deny-warn"],
                    ["moon", "test", "--target", "native", "--deny-warn"]):
            checked = run(cmd, out)
            assert checked.returncode == 0, checked.stdout + checked.stderr
        assert len(seen) == len(bodies), seen
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


# ── red-team BUG-1/2: top-level Int/Double must decode strictly ───────────

def test_top_level_scalar_strict_decode():
    """Core Int::from_json truncates fractions and Double::from_json accepts the
    string "NaN"; top-level responses must reject both. Proven over local HTTP.
    """
    bodies = {
        "/int_frac": b"1.5", "/int_over": b"2147483648", "/int_ok": b"42",
        "/dbl_nan": b'"NaN"', "/dbl_inf": b'"Infinity"', "/dbl_ok": b"3.5",
    }
    seen = []

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_GET(self):
            seen.append(self.path)
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(bodies.get(self.path, b"null"))

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        integer = {"type": "integer"}
        double = {"type": "number", "format": "double"}
        doc = spec("Scalars", {
            "/int_frac": {"get": op(operation_id="getIntFrac", responses={"200": json_response(integer)})},
            "/int_over": {"get": op(operation_id="getIntOver", responses={"200": json_response(integer)})},
            "/int_ok": {"get": op(operation_id="getIntOk", responses={"200": json_response(integer)})},
            "/dbl_nan": {"get": op(operation_id="getDblNan", responses={"200": json_response(double)})},
            "/dbl_inf": {"get": op(operation_id="getDblInf", responses={"200": json_response(double)})},
            "/dbl_ok": {"get": op(operation_id="getDblOk", responses={"200": json_response(double)})},
        })
        doc["servers"] = [{"url": "http://127.0.0.1:%d" % server.server_port}]
        result, out = generate(doc, "strict-scalars")
        assert result.returncode == 0, result.stderr
        (out / "s_wbtest.mbt").write_text('''///|
async test "strict top-level scalars" {
  let c = Client::new()
  try { ignore(c.get_int_frac()); fail("fractional int accepted") } catch { Decode(_, _) => (); _ => fail("wrong error") }
  try { ignore(c.get_int_over()); fail("overflow int accepted") } catch { Decode(_, _) => (); _ => fail("wrong error") }
  assert_eq(c.get_int_ok(), 42)
  try { ignore(c.get_dbl_nan()); fail("NaN string accepted") } catch { Decode(_, _) => (); _ => fail("wrong error") }
  try { ignore(c.get_dbl_inf()); fail("Infinity string accepted") } catch { Decode(_, _) => (); _ => fail("wrong error") }
  assert_eq(c.get_dbl_ok(), 3.5)
}
''', encoding="utf-8")
        pkg = out / "moon.pkg"
        pkg.write_text(pkg.read_text(encoding="utf-8")
                       + '\nimport { "moonbitlang/async", } for "wbtest"\n', encoding="utf-8")
        for cmd in (["moon", "fmt"],
                    ["moon", "check", "--target", "native", "--deny-warn"],
                    ["moon", "test", "--target", "native", "--deny-warn"]):
            checked = run(cmd, out)
            assert checked.returncode == 0, checked.stdout + checked.stderr
        assert len(seen) == len(bodies), seen
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


# ── red-team BUG-3: component names colliding with generated/core types ───

@pytest.mark.parametrize("name", ["Client", "Response", "String", "Config", "Presence"])
def test_component_name_collisions_compile(name):
    """A component whose name pascalizes to a generated/runtime/core type must
    be renamed, not emit a duplicate type. Before the fix these generated exit 0
    but failed moon check (duplicate definition)."""
    obj = {"type": "object", "required": ["id"],
           "properties": {"id": {"type": "integer"}}}
    doc = spec("Collision", {
        "/x": {"get": op(operation_id="getX",
                         responses={"200": json_response({"$ref": "#/components/schemas/" + name})})},
    }, schemas={name: obj})
    result, out = generate(doc, "collision-" + name)
    assert result.returncode == 0, result.stderr
    checked = run(["moon", "check", "--target", "native", "--deny-warn"], out)
    assert checked.returncode == 0, checked.stdout + checked.stderr
    (out / "c_wbtest.mbt").write_text('''///|
async test "collision model decodes" {
  let c = Client::new(capture=CaptureTransport::new(Response::new(200, body="{\\"id\\":7}")))
  assert_eq(c.get_x().id, 7)
}
''', encoding="utf-8")
    pkg = out / "moon.pkg"
    pkg.write_text(pkg.read_text(encoding="utf-8")
                   + '\nimport { "moonbitlang/async", } for "wbtest"\n', encoding="utf-8")
    for cmd in (["moon", "fmt"], ["moon", "test", "--target", "native", "--deny-warn"]):
        checked = run(cmd, out)
        assert checked.returncode == 0, checked.stdout + checked.stderr


# ── red-team BUG-4: nullable array items (decode + generated encode) ──────

def test_nullable_array_items():
    """A nullable array item must decode null -> None and a bare value -> Some,
    and encode back to the OpenAPI bare-value/null wire form (not MoonBit's
    `[value]` Option convention). Covers Int, String, and Int64 elements.
    """
    bodies = {
        "/ni": b"[9007199254740993,null,9223372036854775807]",
        "/ns": b'["a",null,"b"]',
        "/nint": b"[1,null,3]",
    }
    seen = []
    post_bodies = []

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_GET(self):
            seen.append(self.path)
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(bodies.get(self.path, b"null"))

        def do_POST(self):
            seen.append(self.path)
            post_bodies.append(self.rfile.read(int(self.headers["Content-Length"])))
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'"ok"')

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        ni = {"type": "array", "items": {"type": "integer", "format": "int64", "nullable": True}}
        ns = {"type": "array", "items": {"type": "string", "nullable": True}}
        nint = {"type": "array", "items": {"type": "integer", "nullable": True}}
        doc = spec("Nullable", {
            "/ni": {
                "get": op(operation_id="getNi", responses={"200": json_response(ni)}),
                "post": {"operationId": "postNi",
                         "requestBody": {"required": True, "content": {"application/json": {"schema": ni}}},
                         "responses": {"200": json_response({"type": "string"})}},
            },
            "/ns": {"get": op(operation_id="getNs", responses={"200": json_response(ns)})},
            "/nint": {"get": op(operation_id="getNint", responses={"200": json_response(nint)})},
        })
        doc["servers"] = [{"url": "http://127.0.0.1:%d" % server.server_port}]
        result, out = generate(doc, "nullable-items")
        assert result.returncode == 0, result.stderr
        (out / "n_wbtest.mbt").write_text('''///|
async test "nullable array items decode and encode" {
  let c = Client::new()
  let vi = c.get_ni()
  assert_eq(vi[0], Some(9007199254740993L))
  assert_eq(vi[1], None)
  assert_eq(vi[2], Some(9223372036854775807L))
  let vs = c.get_ns()
  assert_eq(vs[0], Some("a"))
  assert_eq(vs[1], None)
  let vn = c.get_nint()
  assert_eq(vn, [Some(1), None, Some(3)])
  assert_eq(c.post_ni([Some(9007199254740993L), None]), "ok")
}
''', encoding="utf-8")
        pkg = out / "moon.pkg"
        pkg.write_text(pkg.read_text(encoding="utf-8")
                       + '\nimport { "moonbitlang/async", } for "wbtest"\n', encoding="utf-8")
        for cmd in (["moon", "fmt"],
                    ["moon", "check", "--target", "native", "--deny-warn"],
                    ["moon", "test", "--target", "native", "--deny-warn"]):
            checked = run(cmd, out)
            assert checked.returncode == 0, checked.stdout + checked.stderr
        # the POST body must use the bare-value/null wire form
        assert seen.count("/ni") == 2, seen
        assert post_bodies == [b"[9007199254740993,null]"], post_bodies
    finally:
        server.shutdown()
        server.server_close()
        thread.join()