"""Add hermetic unit tests to a generated Petstore SDK package.

Usage:
    python gen_tests.py <canonical-ir.json> <generated-package-dir>

The generator itself ships no tests, because a package without tests would
otherwise carry an unused test-only import. This demo adds the tests it wants,
and with them the test-only import they need.

Every test injects a `CaptureTransport`, so the suite is deterministic and
needs neither a server nor a socket; the real-HTTP evidence comes from
`integration/main.mbt` instead.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

TEST_IMPORT = 'import {\n  "moonbitlang/async",\n} for "test"\n'

SCALAR_MOCK = {
    "String": "test",
    "Int": 0,
    "Int64": 0,
    "Double": 0.0,
    "Bool": True,
    "Json": None,
}

SCALAR_DEFAULT = {
    "String": '"test"',
    "Int": "42",
    "Int64": "42L",
    "Double": "0.0",
    "Bool": "true",
    "Json": "Json::null()",
}


def model_map(ir):
    return {model["name"]: model for model in ir.get("models", [])}


def moon_type(tr, models):
    if not tr:
        return "Unit"
    kind = tr.get("kind")
    if kind == "scalar":
        return tr.get("name", "String")
    if kind == "named":
        return tr["name"] if tr["name"] in models else "Json"
    if kind == "array":
        return "Array[%s]" % moon_type(tr.get("item"), models)
    return "Json"


def mock_json(tr, models, seen=frozenset()):
    """Build a JSON-encodable value that satisfies the declared type."""
    if not tr:
        return None
    kind = tr.get("kind")
    if kind == "scalar":
        return SCALAR_MOCK.get(tr.get("name"), "test")
    if kind == "array":
        return []
    if kind == "named":
        name = tr.get("name")
        model = models.get(name)
        if model is None:
            return None
        if model.get("kind") == "enum":
            members = model.get("members") or []
            return members[0][1] if members else "test"
        if name in seen:
            return None
        nested = seen | {name}
        return {
            field["wire_name"]: mock_json(field.get("type"), models, nested)
            for field in model.get("fields", [])
            if field.get("presence") in ("required", "required_nullable")
        }
    return None


def moon_string(text):
    escaped = (
        text.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
    )
    return '"%s"' % escaped


def json_literal(value):
    text = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    return moon_string(text)


def success_status(operation):
    for response in operation.get("success_responses", []):
        status = response.get("status")
        if isinstance(status, int) and 200 <= status < 300:
            return status
    return 200


def success_type(operation):
    for response in operation.get("success_responses", []):
        if response.get("type"):
            return response["type"]
    return None


def argument(param, models):
    """Return (kind, text) for one call-site argument."""
    name = param["name"]
    rendered = moon_type(param.get("type"), models)
    value = SCALAR_DEFAULT.get(rendered, "42")
    if rendered.startswith("Array"):
        value = "[]"
    if param.get("location") == "header":
        value = '"trace-get"' if rendered == "String" else value
    if not param.get("required", True):
        return ("labelled", "%s=%s" % (name, value))
    return ("positional", value)


def emit_tests(ir):
    models = model_map(ir)
    lines = [
        "///|",
        "/// Hermetic tests for the generated client.",
        "///",
        "/// Each operation is driven through a `CaptureTransport`, so these run",
        "/// without a network. Real HTTP is covered by the demo driver.",
        "",
    ]
    for operation in ir.get("operations", []):
        fn_name = operation["fn_name"]
        method = operation["http_method"]
        path = operation["path"]
        params = operation.get("parameters", [])
        body = operation.get("request_body")
        response_type = success_type(operation)
        status = success_status(operation)
        body_mock = mock_json(response_type, models) if response_type else None

        lines.append("///|")
        lines.append('async test "%s_sends_expected_request" {' % fn_name)
        if body_mock is None:
            lines.append(
                "  let transport = CaptureTransport::new(Response::new(%d))" % status
            )
        else:
            lines.append(
                "  let transport = CaptureTransport::new(Response::new(%d, "
                "body=%s))" % (status, json_literal(body_mock))
            )
        lines.append("  let client = Client::new(")
        lines.append("    capture=transport,")
        lines.append('    bearer_token="test-token",')
        lines.append('    basic_username="test-user",')
        lines.append('    basic_password="test-pass",')
        lines.append('    api_key_name="X-Api-Key",')
        lines.append('    api_key_value="test-key",')
        lines.append('    api_key_location="header",')
        lines.append("  )")

        positional = []
        labelled = []
        for param in params:
            kind, text = argument(param, models)
            (positional if kind == "positional" else labelled).append(text)

        if body and body.get("type"):
            rendered = moon_type(body["type"], models)
            body_name = rendered[0].lower() + rendered[1:]
            payload = mock_json(body["type"], models)
            lines.append(
                "  let %s : %s = @json.from_json(@json.parse(%s))"
                % (body_name, rendered, json_literal(payload))
            )
            if body.get("required", True):
                positional.append(body_name)
            else:
                labelled.append("%s=%s" % (body_name, body_name))

        call_args = positional + labelled
        lines.append("  let _ = client.%s(%s)" % (fn_name, ", ".join(call_args)))
        lines.append("  let request = transport.last_request().unwrap()")
        lines.append("  assert_eq(request.http_method(), %s)" % moon_string(method))
        if "{" in path:
            prefix = path.split("{")[0]
            lines.append(
                "  assert_eq(request.path().has_prefix(%s), true)" % moon_string(prefix)
            )
        else:
            lines.append("  assert_eq(request.path(), %s)" % moon_string(path))
        lines.append("}")
        lines.append("")
    return "\n".join(lines)


def ensure_test_import(package_dir):
    pkg = package_dir / "moon.pkg"
    text = pkg.read_text(encoding="utf-8").replace("\r\n", "\n")
    if '"moonbitlang/async",\n} for "test"' in text:
        return False
    pkg.write_text(text.rstrip("\n") + "\n\n" + TEST_IMPORT, encoding="utf-8", newline="\n")
    return True


def main(argv):
    if len(argv) != 3:
        print(__doc__.strip())
        return 2
    ir_path = Path(argv[1]).resolve()
    package_dir = Path(argv[2]).resolve()
    if not ir_path.is_file():
        print("error: canonical IR not found: %s" % ir_path, file=sys.stderr)
        return 1
    if not (package_dir / "moon.pkg").is_file():
        print("error: %s is not a generated MoonBit package" % package_dir, file=sys.stderr)
        return 1

    ir = json.loads(ir_path.read_text(encoding="utf-8"))
    (package_dir / "petstore_test.mbt").write_text(
        emit_tests(ir), encoding="utf-8", newline="\n"
    )
    added = ensure_test_import(package_dir)
    print(
        "wrote %d hermetic tests to %s (test-only async import %s)"
        % (
            len(ir.get("operations", [])),
            package_dir / "petstore_test.mbt",
            "added" if added else "already present",
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
