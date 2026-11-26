"""Regression tests for valid generated identifiers and reused output paths."""

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


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


def generate(spec, output):
    source = output.parent / "spec.json"
    source.write_text(json.dumps(spec), encoding="utf-8")
    return run(
        [
            sys.executable,
            str(ROOT / "oas2moon.py"),
            "generate",
            str(source),
            "--module",
            "edgecases/sdk",
            "--out",
            str(output),
        ]
    )


def test_leading_digit_identifiers_compile():
    output = ROOT / "tests/_build/generation-edge-cases/leading-digit/sdk"
    output.parent.mkdir(parents=True, exist_ok=True)
    spec = {
        "openapi": "3.0.3",
        "info": {"title": "Digit names", "version": "1"},
        "paths": {
            "/items": {
                "get": {
                    "operationId": "200Response",
                    "responses": {
                        "200": {
                            "description": "ok",
                            "content": {
                                "application/json": {
                                    "schema": {"$ref": "#/components/schemas/Item"}
                                }
                            },
                        }
                    },
                }
            }
        },
        "components": {
            "schemas": {
                "Item": {
                    "type": "object",
                    "required": ["200"],
                    "properties": {"200": {"type": "string"}},
                }
            }
        },
    }

    generated = generate(spec, output)
    assert generated.returncode == 0, generated.stdout + generated.stderr
    client = (output / "client.mbt").read_text(encoding="utf-8")
    models = (output / "models.mbt").read_text(encoding="utf-8")
    assert "Client::n_200response" in client
    assert "n_200 : String" in models

    checked = run(["moon", "check", "--target", "native", "--deny-warn"], output)
    assert checked.returncode == 0, checked.stdout + checked.stderr


def test_reused_output_directory_produces_compilable_model_only_package():
    output = ROOT / "tests/_build/generation-edge-cases/reused/sdk"
    output.parent.mkdir(parents=True, exist_ok=True)
    common = {
        "openapi": "3.0.3",
        "info": {"title": "Output reuse", "version": "1"},
    }
    with_operation = {
        **common,
        "paths": {
            "/x": {
                "get": {
                    "operationId": "getX",
                        "responses": {
                            "200": {
                                "description": "ok",
                                "content": {
                                    "application/json": {"schema": {"type": "string"}}
                                },
                            }
                        },
                }
            }
        },
    }
    first = generate(with_operation, output)
    assert first.returncode == 0, first.stdout + first.stderr
    assert (output / "client.mbt").is_file()

    model_only = {
        **common,
        "paths": {},
        "components": {"schemas": {"Item": {"type": "string"}}},
    }
    second = generate(model_only, output)
    assert second.returncode == 0, second.stdout + second.stderr
    assert not (output / "client.mbt").exists()
    assert not (output / "http_transport.mbt").exists()
    assert (output / "encoding.mbt").exists()

    checked = run(["moon", "check", "--target", "native", "--deny-warn"], output)
    assert checked.returncode == 0, checked.stdout + checked.stderr
