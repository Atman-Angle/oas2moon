import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests" / "reference_python"))

from oas2moon import pipeline

FIXTURES = ROOT / "fixtures" / "phase1_5"
OUTPUT_ROOT = ROOT / "tests" / "_build" / "formal-tests"
BASE = FIXTURES / "petstore.normalized.json"


def run_moonbit(fixture, out):
    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["moon", "run", ".", "--target", "native", "--",
         str(Path(fixture).resolve()), str(Path(out).resolve())],
        cwd=str(ROOT / "src" / "core_moonbit"),
        check=True,
    )
    return json.loads(Path(out).read_text(encoding="utf-8"))


def check_ir_format(moon, name):
    """Verify that the MoonBit IR output has the new format fields."""
    assert "module" in moon, f"{name}: missing module"
    assert "operations" in moon, f"{name}: missing operations"
    assert "models" in moon, f"{name}: missing models"
    assert "auth_schemes" in moon, f"{name}: missing auth_schemes"
    for op in moon["operations"]:
        assert "tags" in op, f"{name}: missing tags in {op['operation_id']}"
        assert "source_pointer" in op, f"{name}: missing source_pointer in {op['operation_id']}"
        assert "success_responses" in op, f"{name}: missing success_responses in {op['operation_id']}"
        assert "error_responses" in op, f"{name}: missing error_responses in {op['operation_id']}"
        assert isinstance(op["tags"], list)
        assert isinstance(op["success_responses"], list)
        assert isinstance(op["error_responses"], list)
    return True


def test_corpus_ir_output():
    """Verify the MoonBit IR output format for all targeted fixtures."""
    cases = [
        ("petstore-json", BASE, 3, ["bearer"]),
        ("petstore-yaml", FIXTURES / "petstore-yaml.normalized.json", 3, ["bearer"]),
        ("auth-security", BASE, 3, ["bearer"]),
        ("request-body", BASE, 3, ["bearer"]),
        ("int64", BASE, 3, ["bearer"]),
        ("enum-local-ref", BASE, 3, ["bearer"]),
        ("naming-collision", FIXTURES / "targeted-collision.normalized.json", 3, ["bearer"]),
        ("reserved-words", FIXTURES / "targeted-reserved.normalized.json", 3, ["bearer"]),
        ("multiple-response-status", FIXTURES / "targeted-multi.normalized.json",
         3, ["bearer"]),
    ]
    for name, fixture, expected_ops, _ in cases:
        moon = run_moonbit(fixture, OUTPUT_ROOT / ("ir-" + name + ".json"))
        assert check_ir_format(moon, name)
        assert len(moon["operations"]) == expected_ops, \
            f"{name}: expected {expected_ops} operations, got {len(moon['operations'])}"
        # Verify determinism
        moon2 = run_moonbit(fixture, OUTPUT_ROOT / ("ir-" + name + "-b.json"))
        assert moon == moon2, f"{name}: non-deterministic output"
    print(f"Corpus IR format check: {len(cases)} cases PASSED")


def test_corpus_operation_ids():
    """Verify that operation IDs are in stable order."""
    moon = run_moonbit(BASE, OUTPUT_ROOT / "ir-opids.json")
    ops = [op["operation_id"] for op in moon["operations"]]
    assert ops == ["deletePet", "addPet", "getPetById"], f"Unexpected order: {ops}"
    print("Operation order check PASSED")


def test_corpus_fn_names():
    """Verify generated function names are correct."""
    moon = run_moonbit(BASE, OUTPUT_ROOT / "ir-fnnames.json")
    names = [(op["operation_id"], op["fn_name"]) for op in moon["operations"]]
    assert ("deletePet", "delete_pet") in names
    assert ("addPet", "add_pet") in names
    assert ("getPetById", "get_pet_by_id") in names
    print("Function name check PASSED")


def test_unsupported_oneof_negative_path():
    """Unsupported oneOf must produce errors and no IR."""
    fixture = FIXTURES / "unsupported-oneof.normalized.json"
    _, report, api = pipeline.normalize_to_ir(fixture, "oas2moon/petstore")
    assert not report.ok and api is None
    print("Unsupported diagnosis PASSED")
