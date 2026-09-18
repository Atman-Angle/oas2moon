import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests" / "reference_python"))

from oas2moon import frontend, lower, naming, support


def adapter_fixture(tmp_path: Path, fixture: str = "fixtures/petstore/openapi.json") -> Path:
    # moonbitlang/x/fs on this Windows host cannot open non-ASCII path
    # components. pytest's temp directory inherits the Chinese user profile,
    # so keep adapter I/O in an ASCII workspace path and use a unique stem.
    safe_root = ROOT / "tests" / "_build" / "formal-tests"
    safe_root.mkdir(parents=True, exist_ok=True)
    stem = f"{os.getpid()}-{fixture.replace('/', '_').replace('\\', '_').replace('.', '_')}"
    out = safe_root / f"{stem}.normalized.json"
    subprocess.run(
        ["moon", "run", ".", "--target", "native", "--", str(ROOT / fixture), str(out)],
        cwd=ROOT / "src" / "frontend_adapter",
        check=True,
        capture_output=True,
        text=True,
    )
    return out


def test_frontend_model_version_and_petstore(tmp_path):
    model = frontend.load(adapter_fixture(tmp_path))
    assert model.frontend_model_version == 1
    assert model.version[:2] == (3, 0)
    assert [name for name, _ in model.schemas] == ["Pet", "PetStatus"]
    assert [op.operation_id for op in model.operations] == ["deletePet", "addPet", "getPetById"]
    pet = dict(model.schemas[0][1].properties)
    # Property order is canonicalized by the adapter, so look the field up by
    # name instead of by position: the position is not part of the contract.
    assert set(pet) == {"id", "name", "tags", "owner", "status", "nickname"}
    assert pet["status"].ref == "#/components/schemas/PetStatus"


def test_yaml_json_normalize_identical(tmp_path):
    json_model = adapter_fixture(tmp_path / "json")
    yaml_model = adapter_fixture(tmp_path / "yaml", "fixtures/petstore/openapi.yaml")
    assert json_model.read_bytes() == yaml_model.read_bytes()


def test_false_positive_not_rejected(tmp_path):
    model = frontend.load(adapter_fixture(tmp_path, "fixtures/regression/scan_false_positive_input.json"))
    report = support.validate(model)
    assert report.ok
    assert not any(d.code == "unsupported.keyword" for d in report.errors)


def test_oneof_rejected_with_stable_diagnostic(tmp_path):
    model = frontend.load(adapter_fixture(tmp_path, "fixtures/unsupported/oneof.json"))
    report = support.validate(model)
    assert not report.ok
    assert any(d.code == "unsupported.keyword" and d.json_pointer.endswith("/oneOf") for d in report.errors)
    assert not any(d.code == "ignored.keyword" and d.json_pointer.endswith("/oneOf") for d in report.warnings)
    assert all(d.json_pointer.startswith("#") for d in report.errors)
    assert support.validate(model).errors == report.errors


def test_ir_is_canonical_and_independent_of_mooncontract(tmp_path):
    model = frontend.load(adapter_fixture(tmp_path))
    report = support.validate(model)
    api = lower.lower(model, "oas2moon/petstore", report)
    assert [m.name for m in api.models] == ["PetStatus", "Pet"]
    assert [op.operation_id for op in api.operations] == ["deletePet", "addPet", "getPetById"]
    assert api.auth_schemes[0].kind == "bearer"
    assert all("mooncontract" not in type(value).__module__ for value in vars(api).values())


def test_naming_collision_and_reserved_word_are_deterministic():
    taken = set()
    assert naming.unique(naming.snake("type"), taken) == "type_"
    assert naming.unique(naming.snake("x-y"), taken) == "x_y"
    assert naming.unique(naming.snake("x_y"), taken) == "x_y_2"
    assert naming.pascal("123 pet") == "V123Pet"
    assert naming.pascal("error") == "ErrorValue"


def test_diagnostic_contract_keys(tmp_path):
    model = frontend.load(adapter_fixture(tmp_path, "fixtures/unsupported/oneof.json"))
    report = support.validate(model)
    d = report.errors[0]
    assert {"code", "severity", "json_pointer", "operation_id", "message", "suggestion"} <= set(vars(d)) | {"json_pointer"}
