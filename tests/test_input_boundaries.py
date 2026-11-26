"""Regression coverage for input versioning and component-reference wiring."""

import json
import shutil
import subprocess
import sys

import pytest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "tests/_build/input-boundaries"


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


def write_spec(name, document, suffix=".json"):
    path = BUILD / f"{name}{suffix}"
    path.parent.mkdir(parents=True, exist_ok=True)
    if isinstance(document, str):
        path.write_text(document, encoding="utf-8")
    else:
        path.write_text(json.dumps(document), encoding="utf-8")
    return path


def generate(path, output, ir_path=None):
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        shutil.rmtree(output)
    command = [
        sys.executable,
        str(ROOT / "oas2moon.py"),
        "generate",
        str(path),
        "--module",
        "boundary/sdk",
        "--out",
        str(output),
    ]
    if ir_path is not None:
        command.extend(["--ir-out", str(ir_path)])
    return run(command)


def test_only_openapi_300_through_303_are_accepted():
    for version in ("3.0.4", "3.1.0"):
        path = write_spec(
            f"version-{version}",
            {
                "openapi": version,
                "info": {"title": "Version", "version": "1"},
                "paths": {},
            },
        )
        output = BUILD / f"version-{version}-out"
        result = generate(path, output)
        assert result.returncode == 3, result.stdout + result.stderr
        assert "error[unsupported.version] /openapi" in result.stderr


def test_yaml_extension_is_case_insensitive():
    path = write_spec(
        "upper-case-yaml",
        """openapi: 3.0.3
info:
  title: YAML boundary
  version: '1'
paths: {}
""",
        suffix=".YAML",
    )
    result = generate(path, BUILD / "upper-case-yaml-out")
    assert result.returncode == 0, result.stdout + result.stderr


def test_component_parameter_body_response_refs_preserve_schema_and_nullable():
    document = {
        "openapi": "3.0.3",
        "info": {"title": "Component refs", "version": "1"},
        "paths": {
            "/items": {
                "get": {
                    "operationId": "getItem",
                    "parameters": [{"$ref": "#/components/parameters/Item~1Id~01"}],
                    "responses": {
                        "200": {"$ref": "#/components/responses/Maybe~1Item~01"}
                    },
                },
                "post": {
                    "operationId": "putItem",
                    "requestBody": {"$ref": "#/components/requestBodies/Item~1Body~01"},
                    "responses": {
                        "200": {"$ref": "#/components/responses/Maybe~1Item~01"}
                    },
                },
            }
        },
        "components": {
            "parameters": {
                "Item/Id~1": {
                    "name": "item_id",
                    "in": "query",
                    "required": True,
                    "schema": {"type": "integer"},
                }
            },
            "requestBodies": {
                "Item/Body~1": {
                    "required": True,
                    "content": {
                        "application/json": {
                            "schema": {"$ref": "#/components/schemas/Item"}
                        }
                    },
                }
            },
            "responses": {
                "Maybe/Item~1": {
                    "description": "nullable item",
                    "content": {
                        "application/json": {
                            "schema": {"$ref": "#/components/schemas/Item"}
                        }
                    },
                }
            },
            "schemas": {
                "Item": {
                    "type": "object",
                    "nullable": True,
                    "properties": {"name": {"type": "string"}},
                }
            },
        },
    }
    spec_path = write_spec("component-refs", document)
    output = BUILD / "component-refs-sdk"
    ir_path = BUILD / "component-refs-ir.json"
    result = generate(spec_path, output, ir_path)
    assert result.returncode == 0, result.stdout + result.stderr

    ir = json.loads(ir_path.read_text(encoding="utf-8"))
    get_item, put_item = ir["operations"]
    assert get_item["parameters"][0]["wire_name"] == "item_id"
    assert get_item["parameters"][0]["type"] == {"kind": "scalar", "name": "Int"}
    assert get_item["success_responses"][0]["type"] == {
        "kind": "nullable",
        "item": {"kind": "named", "name": "Item"},
    }
    assert put_item["request_body"]["type"] == {
        "kind": "nullable",
        "item": {"kind": "named", "name": "Item"},
    }

    pkg = output / "moon.pkg"
    pkg.write_text(pkg.read_text(encoding="utf-8")
                   + '\nimport { "moonbitlang/async", } for "wbtest"\n', encoding="utf-8")
    (output / "refs_wbtest.mbt").write_text(r'''///|
async test "nullable component response uses bare values and null" {
  let body = CaptureTransport::new(Response::new(200, body="{\"name\":\"Ada\"}"))
  let null_body = CaptureTransport::new(Response::new(200, body="null"))
  assert_eq(Client::new(capture=body).get_item(1).unwrap().name, Some("Ada"))
  assert_eq(Client::new(capture=null_body).put_item(None), None)
  assert_eq(null_body.last_request().unwrap().body, Some("null"))
}
''', encoding="utf-8")
    for command in (["moon", "fmt"],
                    ["moon", "check", "--target", "native", "--deny-warn"],
                    ["moon", "test", "--target", "native", "--deny-warn"]):
        checked = run(command, output)
        assert checked.returncode == 0, checked.stdout + checked.stderr


def test_nullable_primitive_component_refs_use_one_nullable_layer():
    document = {
        "openapi": "3.0.3",
        "info": {"title": "Nullable primitive refs", "version": "1"},
        "paths": {
            "/count": {
                "get": {
                    "operationId": "getCount",
                    "responses": {
                        "200": {
                            "description": "nullable count",
                            "content": {"application/json": {
                                "schema": {"$ref": "#/components/schemas/MaybeCount"},
                            }},
                        }
                    },
                }
            },
            "/box": {
                "get": {
                    "operationId": "getBox",
                    "responses": {
                        "200": {
                            "description": "box with nullable count",
                            "content": {"application/json": {
                                "schema": {"$ref": "#/components/schemas/Box"},
                            }},
                        }
                    },
                }
            },
        },
        "components": {
            "schemas": {
                "MaybeCount": {"type": "integer", "nullable": True},
                "Box": {
                    "type": "object",
                    "required": ["count"],
                    "properties": {
                        "count": {
                            "$ref": "#/components/schemas/MaybeCount",
                            "nullable": True,
                        }
                    },
                },
            }
        },
    }
    spec_path = write_spec("nullable-primitive-component-refs", document)
    output = BUILD / "nullable-primitive-component-refs-sdk"
    ir_path = BUILD / "nullable-primitive-component-refs-ir.json"
    result = generate(spec_path, output, ir_path)
    assert result.returncode == 0, result.stdout + result.stderr

    ir = json.loads(ir_path.read_text(encoding="utf-8"))
    nullable_count = {"kind": "nullable", "item": {"kind": "named", "name": "MaybeCount"}}
    count_operation = next(op for op in ir["operations"] if op["operation_id"] == "getCount")
    assert count_operation["response_strategy"]["type"] == nullable_count
    box = next(model for model in ir["models"] if model["name"] == "Box")
    assert box["fields"][0]["presence"] == "required_nullable"
    assert box["fields"][0]["type"] == {"kind": "named", "name": "MaybeCount"}

    pkg = output / "moon.pkg"
    pkg.write_text(pkg.read_text(encoding="utf-8")
                   + '\nimport { "moonbitlang/async", } for "wbtest"\n', encoding="utf-8")
    (output / "nullable_refs_wbtest.mbt").write_text(r'''///|
async test "nullable primitive component refs decode numeric and null values" {
  let numeric = CaptureTransport::new(Response::new(200, body="7"))
  let null_value = CaptureTransport::new(Response::new(200, body="null"))
  let box_numeric = CaptureTransport::new(Response::new(200, body="{\"count\":7}"))
  let box_null = CaptureTransport::new(Response::new(200, body="{\"count\":null}"))
  assert_eq(Client::new(capture=numeric).get_count(), Some(7))
  assert_eq(Client::new(capture=null_value).get_count(), None)
  assert_eq(Client::new(capture=box_numeric).get_box().count, Some(7))
  assert_eq(Client::new(capture=box_null).get_box().count, None)
}
''', encoding="utf-8")
    for command in (["moon", "fmt"],
                    ["moon", "check", "--target", "native", "--deny-warn"],
                    ["moon", "test", "--target", "native", "--deny-warn"]):
        checked = run(command, output)
        assert checked.returncode == 0, checked.stdout + checked.stderr


def test_suffix_json_media_type_is_rejected_stably():
    document = {
        "openapi": "3.0.3",
        "info": {"title": "Media boundary", "version": "1"},
        "paths": {
            "/items": {
                "get": {
                    "operationId": "getItem",
                    "responses": {
                        "200": {
                            "description": "problem",
                            "content": {
                                "application/problem+json": {
                                    "schema": {"type": "object"}
                                }
                            },
                        }
                    },
                }
            }
        },
    }
    path = write_spec("suffix-json-media", document)
    output = BUILD / "suffix-json-media-sdk"
    result = generate(path, output)
    assert result.returncode == 4, result.stdout + result.stderr
    assert "unsupported.media_type" in result.stderr
    assert "application~1problem+json" in result.stderr
    assert not (output / "client.mbt").exists()


@pytest.mark.parametrize("kind", ["media-response", "media-body", "missing", "cycle", "style", "oneof", "numeric-enum"])
def test_component_uses_reject_unsupported_semantics(kind):
    document = {
        "openapi": "3.0.3",
        "info": {"title": "Reference boundary", "version": "1"},
        "paths": {"/x": {"post": {"responses": {"200": {"description": "ok"}}}}},
        "components": {},
    }
    operation = document["paths"]["/x"]["post"]
    components = document["components"]
    if kind == "media-response":
        operation["responses"]["200"] = {"$ref": "#/components/responses/R"}
        components["responses"] = {"R": {"description": "text", "content": {
            "text/plain": {"schema": {"type": "string"}},
        }}}
        code, pointer = "unsupported.media_type", "/responses/200/content/text~1plain"
    elif kind == "media-body":
        operation["requestBody"] = {"$ref": "#/components/requestBodies/B"}
        components["requestBodies"] = {"B": {"content": {
            "text/plain": {"schema": {"type": "string"}},
        }}}
        code, pointer = "unsupported.media_type", "/requestBody/content/text~1plain"
    elif kind == "style":
        operation["parameters"] = [{"$ref": "#/components/parameters/Q"}]
        components["parameters"] = {"Q": {"name": "q", "in": "query",
            "style": "pipeDelimited", "schema": {"type": "array", "items": {"type": "string"}}}}
        code, pointer = "unsupported.serialization", "/parameters/0"
    elif kind == "numeric-enum":
        operation["responses"]["200"] = {"description": "ok", "content": {
            "application/json": {"schema": {"type": "integer", "enum": [1, 2]}},
        }}
        code, pointer = "unsupported.enum", "/responses/200/content/application~1json/schema/enum"
    elif kind == "oneof":
        operation["responses"]["200"] = {"$ref": "#/components/responses/R"}
        components["responses"] = {"R": {"description": "ok", "content": {
            "application/json": {"schema": {"oneOf": [{"type": "string"}, {"type": "integer"}]}},
        }}}
        code, pointer = "unsupported.keyword", "#/components/responses/R/content/application~1json/schema/oneOf"
    else:
        operation["responses"]["200"] = {"$ref": "#/components/responses/R"}
        if kind == "cycle":
            components["responses"] = {"R": {"$ref": "#/components/responses/R"}}
        code, pointer = "unsupported.ref", "/responses/200/$ref"

    path = write_spec(f"component-{kind}", document)
    result = generate(path, BUILD / f"component-{kind}-sdk")
    assert result.returncode == 4, result.stdout + result.stderr
    assert code in result.stderr and pointer in result.stderr, result.stderr
