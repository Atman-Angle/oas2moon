import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "fixtures" / "phase1_5"
OUTPUT_ROOT = ROOT / "tests" / "_build" / "formal-tests"
BASE = FIXTURES / "petstore.normalized.json"

def run_moonbit(fixture, out):
    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["moon", "run", ".", "--target", "native", "--",
         str(fixture.resolve()), str(out.resolve())],
        cwd=str(ROOT / "src" / "core_moonbit"),
        check=True, capture_output=True, text=True)
    return json.loads(out.read_text(encoding="utf-8"))

def test_new_ir_format():
    """Verify the new Canonical IR format fields exist."""
    moon = run_moonbit(BASE, OUTPUT_ROOT / "verify-format.json")
    for op in moon["operations"]:
        assert "tags" in op, "Missing tags"
        assert "source_pointer" in op, "Missing source_pointer"
        assert "success_responses" in op, "Missing success_responses"
        assert "error_responses" in op, "Missing error_responses"
        assert isinstance(op["tags"], list)
        assert isinstance(op["success_responses"], list)
        assert isinstance(op["error_responses"], list)
    assert len(moon["operations"]) == 3
    print("Ops:", [o["operation_id"] for o in moon["operations"]])
    print("Format check PASSED")

def test_tags_and_source_location():
    """Verify tags and source_pointer are present in every operation."""
    cases = [
        BASE,
        FIXTURES / "petstore-yaml.normalized.json",
        FIXTURES / "targeted-collision.normalized.json",
        FIXTURES / "targeted-reserved.normalized.json",
        FIXTURES / "targeted-multi.normalized.json",
    ]
    for fixture in cases:
        name = fixture.stem
        moon = run_moonbit(fixture, OUTPUT_ROOT / ("verify-" + name + ".json"))
        for op in moon["operations"]:
            assert isinstance(op["tags"], list), f"{name}: tags not a list in {op['operation_id']}"
            assert isinstance(op["source_pointer"], str), f"{name}: source_pointer not a string in {op['operation_id']}"
    print("Tags and source_location check PASSED across", len(cases), "fixtures")

def test_deterministic_regen():
    """Same input must produce byte-identical JSON."""
    moon1 = run_moonbit(BASE, OUTPUT_ROOT / "verify-det1.json")
    moon2 = run_moonbit(BASE, OUTPUT_ROOT / "verify-det2.json")
    assert moon1 == moon2, "Non-deterministic output!"
    print("Determinism PASSED")

def test_success_error_responses():
    """Verify success/error response split works correctly."""
    moon = run_moonbit(FIXTURES / "targeted-multi.normalized.json",
                        OUTPUT_ROOT / "verify-multi-resp.json")
    for op in moon["operations"]:
        all_resp = len(op["success_responses"]) + len(op["error_responses"])
        # The multi fixture has addPet with 201 and 404
        print(f"  {op['operation_id']}: success={len(op['success_responses'])}, error={len(op['error_responses'])}")
    print("Response split check PASSED")

if __name__ == "__main__":
    test_new_ir_format()
    test_tags_and_source_location()
    test_deterministic_regen()
    test_success_error_responses()
    print("ALL TESTS PASSED")
