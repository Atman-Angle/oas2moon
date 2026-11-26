"""End-to-end auth normalization and unsupported-combination regressions."""

import json
import shutil
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "tests/_build/auth-regressions"


def run(args, cwd=ROOT):
    return subprocess.run(
        args,
        cwd=cwd,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=180,
    )


def make_spec(security, schemes):
    return {
        "openapi": "3.0.3",
        "info": {"title": "Auth regression", "version": "1"},
        "paths": {
            "/x": {
                "get": {
                    "operationId": "getX",
                    "security": [security],
                    "responses": {"200": {"description": "ok"}},
                }
            }
        },
        "components": {"securitySchemes": schemes},
    }


def generate(doc, label):
    work = BUILD / label
    work.mkdir(parents=True, exist_ok=True)
    source, out = work / "spec.json", work / "sdk"
    source.write_text(json.dumps(doc), encoding="utf-8")
    if out.exists():
        shutil.rmtree(out)
    result = run(
        [
            sys.executable,
            str(ROOT / "oas2moon.py"),
            "generate",
            str(source),
            "--module",
            "auth/regression",
            "--out",
            str(out),
        ]
    )
    return result, out


@pytest.mark.parametrize(
    "label,http_scheme,scheme_name,credential_kwargs,expected_header",
    [
        (
            "mixed-case-bearer",
            "BeArEr",
            "BearerToken",
            'bearer_token="demo-token"',
            "Bearer demo-token",
        ),
        (
            "mixed-case-basic",
            "BaSiC",
            "BasicAuth",
            'basic_username="demo-user", basic_password="demo-pass"',
            "Basic ZGVtby11c2VyOmRlbW8tcGFzcw==",
        ),
    ],
)
def test_http_auth_scheme_tokens_are_case_insensitive(
    label, http_scheme, scheme_name, credential_kwargs, expected_header
):
    observed = []

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_GET(self):
            observed.append((self.path, self.headers.get("Authorization")))
            self.send_response(200)
            self.send_header("Content-Length", "0")
            self.end_headers()

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        doc = make_spec(
            {scheme_name: []},
            {scheme_name: {"type": "http", "scheme": http_scheme}},
        )
        doc["servers"] = [{"url": f"http://127.0.0.1:{server.server_port}"}]
        result, out = generate(doc, label)
        assert result.returncode == 0, result.stderr
        (out / "auth_wbtest.mbt").write_text(
            f'''///|
async test "mixed-case HTTP auth scheme emits auth header" {{
  let client = Client::new({credential_kwargs})
  client.get_x()
}}
''',
            encoding="utf-8",
        )
        pkg = out / "moon.pkg"
        pkg.write_text(
            pkg.read_text(encoding="utf-8")
            + '\nimport { "moonbitlang/async", } for "wbtest"\n',
            encoding="utf-8",
        )
        for cmd in (
            ["moon", "fmt"],
            ["moon", "check", "--target", "native", "--deny-warn"],
            ["moon", "test", "--target", "native", "--deny-warn"],
        ):
            checked = run(cmd, out)
            assert checked.returncode == 0, checked.stdout + checked.stderr
        assert observed == [("/x", expected_header)], observed
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


@pytest.mark.parametrize(
    "label,auth_scheme,key_name",
    [
        ("authorization-api-key-bearer", "bearer", "Authorization"),
        ("authorization-api-key-basic", "basic", "authorization"),
    ],
)
def test_authorization_api_key_cannot_be_and_combined_with_http_auth(
    label, auth_scheme, key_name
):
    schemes = {
        "HttpAuth": {"type": "http", "scheme": auth_scheme},
        "ApiKey": {"type": "apiKey", "in": "header", "name": key_name},
    }
    result, out = generate(make_spec({"HttpAuth": [], "ApiKey": []}, schemes), label)
    assert result.returncode == 4, result.stderr
    assert "unsupported.auth" in result.stderr
    assert "#/paths/~1x/get/security" in result.stderr
    assert "Authorization API key cannot be combined" in result.stderr
    assert not (out / "client.mbt").exists()


def test_undeclared_security_scheme_has_stable_diagnostic():
    result, out = generate(make_spec({"Typo": []}, {}), "missing-security-scheme")
    assert result.returncode == 4, result.stderr
    assert "unsupported.auth" in result.stderr
    assert "#/paths/~1x/get/security/Typo" in result.stderr
    assert not (out / "client.mbt").exists()
