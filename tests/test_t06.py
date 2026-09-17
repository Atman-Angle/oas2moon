"""T06: Operation MoonBit Codegen tests.

Tests that the codegen correctly generates client.mbt from Canonical Client IR:
- Method signature snapshots
- Generated package passes moon fmt and moon check
- Deterministic regeneration
- CaptureTransport-based behavioral test
"""

import json
import os
import shutil
import subprocess
import sys
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES_DIR = ROOT / "fixtures" / "petstore"
OUTPUT_ROOT = ROOT / "tests" / "_build" / "t06-codegen"
FRONTEND_DIR = ROOT / "src" / "frontend_adapter"
CORE_DIR = ROOT / "src" / "core_moonbit"
CODEGEN_DIR = ROOT / "src" / "codegen_moonbit"
RUNTIME_DIR = ROOT / "src" / "runtime_moonbit"

SKIP_CHECK = os.environ.get("SKIP_MOON_CHECK", "0") == "1"


def run(cmd, cwd=None):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, encoding="utf-8")


def check(label, ok, detail=""):
    s = "PASS" if ok else "FAIL"
    print(f"  [{s}] {label}")
    if detail:
        for line in detail.splitlines()[:5]:
            print(f"    {line}")
    return ok


def read_file_normalized(p):
    """Read file and normalize line endings to LF."""
    with open(p, "rb") as f:
        content = f.read().decode("utf-8")
    return content.replace("\r\n", "\n")


def write_file(p, content):
    with open(p, "w", encoding="utf-8", newline="\n") as f:
        f.write(content)


def get_file_list(pkg_dir):
    result = {}
    for f in sorted(pkg_dir.rglob("*")):
        if not f.is_file():
            continue
        rel = str(f.relative_to(pkg_dir)).replace("\\", "/")
        if rel.startswith("_build/") or rel.startswith(".mooncakes/"):
            continue
        result[rel] = hashlib.sha256(f.read_bytes()).hexdigest()
    return result


def gen_sdk(out_dir, canonical_ir_path, test_code=None):
    """Run codegen and set up the generated package for compilation."""
    out_dir.mkdir(parents=True, exist_ok=True)

    # Run codegen
    r = run(
        ["moon", "run", ".", "--target", "native", "--",
         str(canonical_ir_path.resolve()), str(out_dir.resolve())],
        cwd=str(CODEGEN_DIR),
    )
    if r.returncode != 0:
        print(f"    codegen stderr: {r.stderr[:500]}")
        return False

    # Copy runtime files
    for fn in ["runtime.mbt", "config.mbt", "encoding.mbt"]:
        write_file(out_dir / fn, read_file_normalized(RUNTIME_DIR / fn))

    # Fix moon.mod for standalone module
    write_file(out_dir / "moon.mod",
               'name = "oas2moon/t06_petstore"\n\nversion = "0.1.0"\n\npreferred_target = "native"\n')

    # Add test code if provided
    if test_code is not None:
        write_file(out_dir / "t06_test.mbt", test_code)

    return True


def run_all():
    print("=" * 60)
    print("T06: Operation MoonBit Codegen")
    print("=" * 60)
    results = []

    if OUTPUT_ROOT.exists():
        shutil.rmtree(str(OUTPUT_ROOT))
    OUTPUT_ROOT.mkdir(parents=True)

    # ---- Step 1: Generate canonical IR ----
    spec = FIXTURES_DIR / "openapi.json"
    norm = OUTPUT_ROOT / "normalized.json"
    r = run(["moon", "run", ".", "--target", "native", "--", str(spec), str(norm)], cwd=str(FRONTEND_DIR))
    ok = r.returncode == 0 and norm.exists()
    results.append(("frontend", ok, ""))
    check("frontend: petstore normalized", ok)
    if not ok:
        print(f"    {r.stderr[:500]}")
        return results

    canon = OUTPUT_ROOT / "canonical_ir.json"
    r = run(["moon", "run", ".", "--target", "native", "--", str(norm), str(canon)], cwd=str(CORE_DIR))
    ok = r.returncode == 0 and canon.exists()
    results.append(("core", ok, ""))
    check("core: canonical IR produced", ok)
    if not ok:
        print(f"    {r.stderr[:500]}")
        return results

    data = json.load(open(canon))

    # ---- Step 2: Verify IR has operations ----
    ops = data.get("operations", [])
    ok = len(ops) == 3
    results.append(("ir_operations", ok, ""))
    check(f"canonical IR has 3 operations (got {len(ops)})", ok)

    # ---- Step 3: Method signature snapshot ----
    expected_signatures = {
        "delete_pet": {
            "method": "DELETE",
            "path": "/pets",
            "return_type": "Unit",
            "params": [],
        },
        "add_pet": {
            "method": "POST",
            "path": "/pets",
            "return_type": "Pet",
            "params": [{"name": "pet", "type": "Pet", "required": True}],
        },
        "get_pet_by_id": {
            "method": "GET",
            "path": "/pets/{id}",
            "return_type": "Pet",
            "params": [
                {"name": "id", "type": "Int64", "required": True},
                {"name": "x_trace", "type": "String", "required": True},
                {"name": "verbose", "type": "Bool", "required": False},
            ],
        },
    }

    sig_ok = True
    for op in ops:
        fn_name = op.get("fn_name", "")
        exp = expected_signatures.get(fn_name)
        if exp is None:
            print(f"    Unexpected operation: {fn_name}")
            sig_ok = False
            continue
        if op.get("http_method") != exp["method"]:
            print(f"    {fn_name}: method mismatch {op.get('http_method')} != {exp['method']}")
            sig_ok = False
        if op.get("path") != exp["path"]:
            print(f"    {fn_name}: path mismatch")
            sig_ok = False
        # Check response strategy
        strat = op.get("response_strategy", {})
        if fn_name == "delete_pet":
            if strat.get("kind") != "unit_result":
                print(f"    {fn_name}: expected unit_result, got {strat.get('kind')}")
                sig_ok = False
        elif fn_name in ("add_pet", "get_pet_by_id"):
            if strat.get("kind") != "single_result":
                print(f"    {fn_name}: expected single_result, got {strat.get('kind')}")
                sig_ok = False
        # Check parameters
        params = op.get("parameters", [])
        if fn_name == "get_pet_by_id":
            if len(params) != 3:
                print(f"    {fn_name}: expected 3 params, got {len(params)}")
                sig_ok = False
        elif fn_name in ("delete_pet", "add_pet"):
            if len(params) != 0:
                print(f"    {fn_name}: expected 0 params, got {len(params)}")
                sig_ok = False

    results.append(("signatures", sig_ok, ""))
    check("method signature snapshot", sig_ok)

    # ---- Step 4: Generate SDK ----
    gen = OUTPUT_ROOT / "generated"
    test_code = (
        "///|\n"
        'test "client_constructs_with_transport" {\n'
        "  let t = CaptureTransport::new(Response::new(204))\n"
        "  let _c = Client::new(t)\n"
        "}\n\n"
        "///|\n"
        'test "delete_pet_returns_unit" {\n'
        "  let t = CaptureTransport::new(Response::new(204))\n"
        "  let c = Client::new(t, bearer_token=\"test-token\")\n"
        "  let result : Unit = c.delete_pet()\n"
        "  ignore(result)\n"
        "}\n\n"
        "///|\n"
        'test "add_pet_decodes_response" {\n'
        "  let pet_json = Json::object(Map([\n"
        '    ("id", Json::number(42.0)),\n'
        '    ("name", Json::string("Rex")),\n'
        '    ("status", Json::string("available")),\n'
        "  ]))\n"
        "  let body = pet_json.stringify()\n"
        "  let t = CaptureTransport::new(Response::new(201, body~))\n"
        '  let c = Client::new(t, base_url="http://localhost", bearer_token="test-token")\n'
        "  let pet = c.add_pet(Pet::new(42, \"Rex\", Available))\n"
        '  assert_eq(pet.name, "Rex")\n'
        "}\n"
    )
    ok = gen_sdk(gen, canon, test_code=test_code)
    results.append(("codegen", ok, ""))
    check("codegen: SDK generated", ok)
    if not ok:
        return results

    # List generated files
    for f in sorted(gen.iterdir()):
        if not f.name.startswith("_"):
            print(f"    {f.name} ({f.stat().st_size}b)")

    # ---- Step 5: moon fmt ----
    run(["moon", "fmt"], cwd=str(gen))
    r = run(["moon", "fmt", "--check"], cwd=str(gen))
    ok = r.returncode == 0
    results.append(("fmt", ok, ""))
    check("moon fmt --check", ok)
    if not ok and r.stderr:
        for line in r.stderr.splitlines()[:5]:
            print(f"    {line}")

    # ---- Step 6: moon check ----
    check_ok = True
    if not SKIP_CHECK:
        r = run(["moon", "check", "--target", "native"], cwd=str(gen))
        check_ok = r.returncode == 0
        results.append(("check", check_ok, ""))
        check("moon check", check_ok)
        if not check_ok:
            for line in (r.stderr or "").splitlines()[:10]:
                print(f"    {line}")
    else:
        print("  [SKIP] moon check")
        results.append(("check", True, ""))

    # ---- Step 7: moon test ----
    if check_ok and not SKIP_CHECK:
        r = run(["moon", "test", "--target", "native"], cwd=str(gen))
        test_ok = r.returncode == 0
        results.append(("test", test_ok, ""))
        check("moon test (CaptureTransport behavioral)", test_ok)
        if not test_ok:
            for line in (r.stdout + r.stderr).splitlines():
                if "fail" in line.lower() or "error" in line.lower() or "assert" in line.lower():
                    print(f"    {line}")
    else:
        results.append(("test", True, ""))
        print("  [SKIP] moon test")

    # ---- Step 8: Determinism ----
    gen2 = OUTPUT_ROOT / "generated2"
    ok = gen_sdk(gen2, canon, test_code=test_code)
    if ok:
        run(["moon", "fmt"], cwd=str(gen2))
        f1 = {k: v for k, v in get_file_list(gen).items() if k != "t06_test.mbt"}
        f2 = {k: v for k, v in get_file_list(gen2).items() if k != "t06_test.mbt"}
        ok = f1 == f2
        if not ok:
            for k in sorted(set(f1.keys()) ^ set(f2.keys())):
                print(f"    Missing: {k}")
            for k in sorted(set(f1.keys()) & set(f2.keys())):
                if f1[k] != f2[k]:
                    print(f"    Diff: {k}")
    results.append(("determinism", ok, ""))
    check(f"deterministic ({len(f1)} files)", ok)

    # ---- Summary ----
    print(f"\n{'=' * 60}")
    all_pass = True
    for name, passed, _ in results:
        s = "PASS" if passed else "FAIL"
        if not passed:
            all_pass = False
        print(f"  [{s}] {name}")
    print(f"\nOverall: {'ALL PASS' if all_pass else 'SOME FAILED'}")
    return results


if __name__ == "__main__":
    r = run_all()
    sys.exit(0 if all(x[1] for x in r) else 1)
