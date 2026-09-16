import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

FIXTURES = ROOT / "fixtures" / "phase1_5"
OUTPUT_ROOT = ROOT / "tests" / "_build" / "formal-tests"


def run_moonbit(fixture, out):
    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["moon", "run", ".", "--target", "native", "--",
         str(Path(fixture).resolve()), str(Path(out).resolve())],
        cwd=str(ROOT / "src" / "core_moonbit"),
        check=True,
    )
    return json.loads(Path(out).read_text(encoding="utf-8"))


def check_strategy(ir, op_id, expected_kind, expected_type=None, expected_variants=None):
    ops = {op["operation_id"]: op for op in ir["operations"]}
    assert op_id in ops, f"Missing operation: {op_id}"
    strat = ops[op_id]["response_strategy"]
    assert strat["kind"] == expected_kind, \
        f"{op_id}: expected kind={expected_kind}, got {strat}"
    if expected_type is not None:
        assert strat.get("type", {}).get("name") == expected_type, \
            f"{op_id}: expected type={expected_type}, got {strat}"
    if expected_variants is not None:
        variants = strat.get("variants", [])
        assert len(variants) == len(expected_variants), \
            f"{op_id}: expected {len(expected_variants)} variants, got {len(variants)}"
        for i, (status, tname) in enumerate(expected_variants):
            assert variants[i]["status"] == status, \
                f"{op_id}: variant[{i}] expected status {status}, got {variants[i]}"
            assert variants[i]["type"]["name"] == tname, \
                f"{op_id}: variant[{i}] expected type {tname}, got {variants[i]}"
    print(f"  {op_id}: {strat['kind']} PASS")


def test_response_strategies():
    """Verify all response strategy cases."""
    ir = run_moonbit(FIXTURES / "response-matrix.normalized.json",
                     OUTPUT_ROOT / "ir-strategy-matrix.json")
    
    # 1. 200 with Pet body -> single_result(Pet)
    check_strategy(ir, "getPetById", "single_result", "Pet")
    
    # 2. 204 only -> unit_result
    check_strategy(ir, "deletePet", "unit_result")
    
    # 3. 201 with Pet body -> single_result(Pet)
    check_strategy(ir, "addPet", "single_result", "Pet")
    
    # 4. 200 + 201 with same Pet schema -> single_result(Pet)
    check_strategy(ir, "updatePet", "single_result", "Pet")
    
    # 5. 200 (Pet) + 201 (CreatedResponse, different) -> response_enum
    check_strategy(ir, "createPets", "response_enum",
                   expected_variants=[(200, "Pet"), (201, "CreatedResponse")])
    
    # 6. 200 with no body -> no_content
    check_strategy(ir, "healthCheck", "no_content")
    
    # 7. Unsupported media type (text/plain) -> unsupported_media_type
    check_strategy(ir, "getRaw", "unsupported_media_type")
    
    # 8. Non-2xx response only -> no_content (no success responses)
    check_strategy(ir, "getError", "no_content")
    
    print()
    print("All response strategy tests PASSED")


if __name__ == "__main__":
    test_response_strategies()
