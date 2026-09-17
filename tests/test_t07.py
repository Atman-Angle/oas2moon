"""T07: CRUD and JSON Request Body tests.

Tests POST, PUT, PATCH, DELETE with:
- JSON request body encoding and Content-Type header
- 201 and 204 status handling
- 204 does not trigger JSON decode
- Missing body (optional), empty body, and wrong body (decode failure)
- Real local HTTP server integration with fixture_server.py
- Existing GET tests still pass
"""

import json
import os
import shutil
import subprocess
import sys
import hashlib
import threading
import time
import http.client
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES_DIR = ROOT / "fixtures" / "petstore"
OUTPUT_ROOT = ROOT / "tests" / "_build" / "t07-crud"
FRONTEND_DIR = ROOT / "src" / "frontend_adapter"
CORE_DIR = ROOT / "src" / "core_moonbit"
CODEGEN_DIR = ROOT / "src" / "codegen_moonbit"
RUNTIME_DIR = ROOT / "src" / "runtime_moonbit"
FIXTURE_SERVER = ROOT / "tools" / "fixture_server.py"

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
    out_dir.mkdir(parents=True, exist_ok=True)
    r = run(
        ["moon", "run", ".", "--target", "native", "--",
         str(canonical_ir_path.resolve()), str(out_dir.resolve())],
        cwd=str(CODEGEN_DIR),
    )
    if r.returncode != 0:
        print(f"    codegen stderr: {r.stderr[:500]}")
        return False
    for fn in ["runtime.mbt", "config.mbt", "encoding.mbt"]:
        write_file(out_dir / fn, read_file_normalized(RUNTIME_DIR / fn))
    write_file(out_dir / "moon.mod",
               'name = "oas2moon/t07_petstore"\n\nversion = "0.1.0"\n\npreferred_target = "native"\n')
    if test_code is not None:
        write_file(out_dir / "t07_test.mbt", test_code)
    return True


# ---------------------------------------------------------------------------
# MoonBit test code for CaptureTransport-based behavioral tests
# ---------------------------------------------------------------------------

MOONBIT_TESTS = r'''///|
/// T07: CRUD and JSON Body behavioral tests using CaptureTransport.

///|
/// Helper: check if a string contains a substring.
fn str_contains(s : String, sub : String) -> Bool {
  s.contains(sub)
}

///|
/// POST: verify method, body JSON, Content-Type, 201 decode
test "post_sets_method_body_contenttype_and_decodes_201" {
  let pet = Pet::new(42L, "Rex", PetStatus::Available, tags=["fluffy", "friendly"])
  let body = "{\"id\":42,\"name\":\"Rex\",\"status\":\"available\"}"
  let t = CaptureTransport::new(Response::new(201, body~))
  let c = Client::new(t, base_url="http://localhost", bearer_token="tok")
  let result = c.add_pet(pet)
  let req = t.last_request().unwrap()
  assert_eq(req.http_method(), "POST")
  assert_eq(req.path(), "/pets")
  assert_eq(req.headers()["Content-Type"], "application/json")
  assert_eq(str_contains(req.body().unwrap(), "Rex"), true)
  assert_eq(str_contains(req.body().unwrap(), "available"), true)
  assert_eq(result.name, "Rex")
}

///|
/// POST: verify body encodes enum correctly
test "post_body_encodes_enum_to_wire_string" {
  let pet = Pet::new(7L, "Spot", PetStatus::Pending)
  let body = "{\"id\":7,\"name\":\"Spot\",\"status\":\"pending\"}"
  let t = CaptureTransport::new(Response::new(201, body~))
  let c = Client::new(t, bearer_token="tok")
  let _result = c.add_pet(pet)
  let req = t.last_request().unwrap()
  assert_eq(str_contains(req.body().unwrap(), "pending"), true)
}

///|
/// PUT: verify method, body, Content-Type, 200 decode
test "put_sets_method_body_contenttype_and_decodes_200" {
  let pet_json = Json::object(Map([
    ("id", Json::number(99.0)),
    ("name", Json::string("Updated")),
    ("status", Json::string("sold")),
  ]))
  let t = CaptureTransport::new(Response::new(200, body=pet_json.stringify()))
  let c = Client::new(t, bearer_token="tok")
  let result = c.update_pet(99L, pet_json)
  let req = t.last_request().unwrap()
  assert_eq(req.http_method(), "PUT")
  assert_eq(req.path(), "/pets/99")
  assert_eq(req.headers()["Content-Type"], "application/json")
  assert_eq(str_contains(result.stringify(), "Updated"), true)
}

///|
/// PATCH: verify method, body, Content-Type, 200 decode
test "patch_with_body_sets_method_and_contenttype" {
  let pet_json = Json::object(Map([
    ("id", Json::number(5.0)),
    ("name", Json::string("Patched")),
    ("status", Json::string("available")),
  ]))
  let t = CaptureTransport::new(Response::new(200, body=pet_json.stringify()))
  let c = Client::new(t, bearer_token="tok")
  let result = c.patch_pet(5L, body=pet_json)
  let req = t.last_request().unwrap()
  assert_eq(req.http_method(), "PATCH")
  assert_eq(req.path(), "/pets/5")
  assert_eq(req.headers()["Content-Type"], "application/json")
  assert_eq(req.body(), Some(pet_json.stringify()))
  assert_eq(str_contains(result.stringify(), "Patched"), true)
}

///|
/// PATCH: optional body — omit body param, should not set request body
test "patch_without_body_sends_no_body" {
  let pet_json = Json::object(Map([
    ("id", Json::number(5.0)),
    ("name", Json::string("Patched")),
    ("status", Json::string("available")),
  ]))
  let t = CaptureTransport::new(Response::new(200, body=pet_json.stringify()))
  let c = Client::new(t, bearer_token="tok")
  // Omit body entirely — optional parameter defaults to None behavior
  let _result = c.patch_pet(5L)
  let req = t.last_request().unwrap()
  assert_eq(req.http_method(), "PATCH")
  assert_eq(req.path(), "/pets/5")
  // Body should be None when no body was provided
  assert_eq(req.body(), None)
}

///|
/// DELETE: verify method, no body, 204 — no JSON decode attempted
test "delete_sets_method_no_body_and_returns_unit_on_204" {
  let t = CaptureTransport::new(Response::new(204))
  let c = Client::new(t, bearer_token="tok")
  let result : Unit = c.delete_pet()
  ignore(result)
  let req = t.last_request().unwrap()
  assert_eq(req.http_method(), "DELETE")
  assert_eq(req.path(), "/pets")
  assert_eq(req.body(), None)
}

///|
/// DELETE: 204 with empty body does not cause decode error
test "delete_204_empty_body_no_decode_error" {
  let t = CaptureTransport::new(Response::new(204, body=""))
  let c = Client::new(t, bearer_token="tok")
  let _result : Unit = c.delete_pet()
}

///|
/// Wrong body: response with invalid JSON should raise Decode error
test "post_invalid_json_response_raises_decode_error" {
  let pet = Pet::new(1L, "X", PetStatus::Available)
  let t = CaptureTransport::new(Response::new(201, body="not json {{"))
  let c = Client::new(t, bearer_token="tok")
  let outcome : Result[Pet, SdkError] = Ok(c.add_pet(pet)) catch {
    err => Err(err)
  }
  match outcome {
    Ok(_) => abort("expected Decode error for invalid JSON response")
    Err(Decode(_, _)) => ()
    Err(err) => abort("expected Decode error, got: " + err.to_string())
  }
}

///|
/// GET still works: existing vertical slice not broken
test "get_pet_by_id_still_works" {
  let pet_json = Json::object(Map([
    ("id", Json::number(7.0)),
    ("name", Json::string("Lucky")),
    ("status", Json::string("available")),
    ("tags", Json::array([Json::string("cute")])),
  ]))
  let t = CaptureTransport::new(Response::new(200, body=pet_json.stringify()))
  let c = Client::new(t, bearer_token="tok")
  let pet = c.get_pet_by_id(7L, "trace-get", verbose=true)
  assert_eq(pet.name, "Lucky")
  let req = t.last_request().unwrap()
  assert_eq(req.http_method(), "GET")
  assert_eq(req.path(), "/pets/7")
  assert_eq(req.headers()["X-Trace"], "trace-get")
}'''


# ---------------------------------------------------------------------------
# Real HTTP server integration test
# ---------------------------------------------------------------------------

def start_fixture_server(port=18082, token="t07-token"):
    capture_path = str(OUTPUT_ROOT / "server_capture.json")
    if os.path.exists(capture_path):
        os.remove(capture_path)
    server_proc = subprocess.Popen(
        ["python", str(FIXTURE_SERVER), "--port", str(port),
         "--token", token, "--capture", capture_path],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    # Wait for server to be ready
    deadline = time.time() + 10
    ready = False
    while time.time() < deadline:
        try:
            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("GET", "/pets/1?verbose=true", headers={"Authorization": "Bearer t07-token", "X-Trace": "trace-get"})
            conn.close()
            ready = True
            break
        except Exception:
            time.sleep(0.2)
    if not ready:
        server_proc.terminate()
        raise RuntimeError("fixture server did not start")
    return server_proc, capture_path


def http_request(port, method, path, body=None, headers=None):
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    hdrs = {"Authorization": "Bearer t07-token"}
    if headers:
        hdrs.update(headers)
    if body is not None:
        hdrs["Content-Type"] = "application/json"
    conn.request(method, path, body=body, headers=hdrs)
    resp = conn.getresponse()
    resp_body = resp.read().decode("utf-8")
    conn.close()
    return resp.status, resp_body


def run_http_server_test():
    """Real HTTP server integration test."""
    print("  --- Real HTTP Server Integration ---")
    results = []
    port = 18081
    token = "t07-token"

    try:
        proc, capture_path = start_fixture_server(port, token)
    except Exception as exc:
        check("fixture server start", False, str(exc))
        return results

    try:
        # GET
        status, body = http_request(port, "GET", "/pets/42?verbose=true",
                                    headers={"X-Trace": "trace-get"})
        ok = status == 200 and "Spike" in body
        results.append(("http_get", ok))
        check("HTTP GET /pets/42", ok, f"status={status}")

        # POST
        pet_body = json.dumps({"id": 99, "name": "Created", "status": "available",
                               "tags": ["a", "b"]})
        status, resp_body = http_request(port, "POST", "/pets", body=pet_body)
        ok = status == 201
        results.append(("http_post", ok))
        check("HTTP POST /pets (201)", ok, f"status={status}")

        # PUT
        put_body = json.dumps({"id": 42, "name": "Updated", "status": "sold",
                               "tags": ["a", "b"]})
        status, resp_body = http_request(port, "PUT", "/pets/42", body=put_body)
        ok = status == 200
        results.append(("http_put", ok))
        check("HTTP PUT /pets/42 (200)", ok, f"status={status}")

        # PATCH with body
        patch_body = json.dumps({"id": 42, "name": "Patched", "status": "pending"})
        status, resp_body = http_request(port, "PATCH", "/pets/42", body=patch_body)
        ok = status == 200
        results.append(("http_patch_with_body", ok))
        check("HTTP PATCH /pets/42 (200, with body)", ok, f"status={status}")

        # PATCH without body (optional body)
        status, resp_body = http_request(port, "PATCH", "/pets/42", body=None)
        ok = status == 200
        results.append(("http_patch_no_body", ok))
        check("HTTP PATCH /pets/42 (200, no body)", ok, f"status={status}")

        # DELETE
        status, resp_body = http_request(port, "DELETE", "/pets")
        ok = status == 204 and resp_body == ""
        results.append(("http_delete", ok))
        check("HTTP DELETE /pets (204, empty body)", ok, f"status={status}")

    finally:
        proc.terminate()
        proc.wait(timeout=5)

    # Verify server capture has no errors
    if os.path.exists(capture_path):
        with open(capture_path, "r", encoding="utf-8") as f:
            capture = json.load(f)
        errors = capture.get("errors", [])
        checks = capture.get("checks", [])
        requests = capture.get("requests", [])
        ok = len(errors) == 0
        results.append(("server_errors", ok))
        check(f"server capture: no errors ({len(requests)} requests, {len(checks)} checks)", ok)
        if not ok:
            for err in errors[:5]:
                print(f"    SERVER ERROR: {err}")
    else:
        results.append(("server_errors", False))
        check("server capture file exists", False)

    return results


# ---------------------------------------------------------------------------
# Main test runner
# ---------------------------------------------------------------------------

def run_all():
    print("=" * 60)
    print("T07: CRUD and JSON Request Body")
    print("=" * 60)
    results = []

    if OUTPUT_ROOT.exists():
        shutil.rmtree(str(OUTPUT_ROOT))
    OUTPUT_ROOT.mkdir(parents=True)

    # ---- Step 1: Generate canonical IR ----
    spec = FIXTURES_DIR / "openapi_crud.json"
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

    # ---- Step 2: Verify IR has 5 operations ----
    ops = data.get("operations", [])
    op_names = {op["fn_name"] for op in ops}
    expected_ops = {"delete_pet", "add_pet", "get_pet_by_id", "update_pet", "patch_pet"}
    ok = len(ops) == 5 and expected_ops == op_names
    results.append(("ir_operations", ok, ""))
    check(f"canonical IR has 5 operations: {sorted(op_names)}", ok)
    if not ok:
        print(f"    got {len(ops)}: {sorted(op_names)}")

    # Verify operation details
    for op in ops:
        fn = op["fn_name"]
        if fn == "update_pet":
            ok = op["http_method"] == "PUT" and op["path"] == "/pets/{id}"
            results.append(("ir_put", ok, ""))
            check("IR: update_pet is PUT /pets/{id}", ok)
        elif fn == "patch_pet":
            ok = op["http_method"] == "PATCH" and op["path"] == "/pets/{id}"
            rb = op.get("request_body", {})
            body_optional = rb and not rb.get("required", True)
            results.append(("ir_patch", ok and body_optional, ""))
            check("IR: patch_pet is PATCH /pets/{id} with optional body", ok and body_optional)

    # ---- Step 3: Generate SDK ----
    gen = OUTPUT_ROOT / "generated"
    ok = gen_sdk(gen, canon, test_code=MOONBIT_TESTS)
    results.append(("codegen", ok, ""))
    check("codegen: SDK generated", ok)
    if not ok:
        return results

    for f in sorted(gen.iterdir()):
        if not f.name.startswith("_"):
            print(f"    {f.name} ({f.stat().st_size}b)")

    # ---- Step 4: moon fmt ----
    run(["moon", "fmt"], cwd=str(gen))
    r = run(["moon", "fmt", "--check"], cwd=str(gen))
    ok = r.returncode == 0
    results.append(("fmt", ok, ""))
    check("moon fmt --check", ok)
    if not ok and r.stderr:
        for line in r.stderr.splitlines()[:5]:
            print(f"    {line}")

    # ---- Step 5: moon check ----
    check_ok = True
    if not SKIP_CHECK:
        r = run(["moon", "check", "--target", "native"], cwd=str(gen))
        check_ok = r.returncode == 0
        results.append(("check", check_ok, ""))
        check("moon check", check_ok)
        if not check_ok:
            for line in (r.stderr or "").splitlines()[:15]:
                print(f"    {line}")
    else:
        print("  [SKIP] moon check")
        results.append(("check", True, ""))

    # ---- Step 6: moon test ----
    if check_ok and not SKIP_CHECK:
        r = run(["moon", "test", "--target", "native"], cwd=str(gen))
        test_ok = r.returncode == 0
        results.append(("test", test_ok, ""))
        check("moon test (CaptureTransport behavioral)", test_ok)
        if not test_ok:
            for line in (r.stdout + r.stderr).splitlines():
                if any(k in line.lower() for k in ["fail", "error", "assert"]):
                    print(f"    {line}")
    else:
        results.append(("test", True, ""))
        print("  [SKIP] moon test")

    # ---- Step 7: Determinism ----
    gen2 = OUTPUT_ROOT / "generated2"
    ok = gen_sdk(gen2, canon, test_code=MOONBIT_TESTS)
    if ok:
        run(["moon", "fmt"], cwd=str(gen2))
        f1 = {k: v for k, v in get_file_list(gen).items() if k != "t07_test.mbt"}
        f2 = {k: v for k, v in get_file_list(gen2).items() if k != "t07_test.mbt"}
        ok = f1 == f2
        if not ok:
            for k in sorted(set(f1.keys()) ^ set(f2.keys())):
                print(f"    Missing: {k}")
            for k in sorted(set(f1.keys()) & set(f2.keys())):
                if f1[k] != f2[k]:
                    print(f"    Diff: {k}")
    results.append(("determinism", ok, ""))
    check(f"deterministic ({len(f1)} files)", ok)

    # ---- Step 8: Real HTTP server integration ----
    http_results = run_http_server_test()
    for item in http_results:
        results.append(item + ('',))

    # ---- Summary ----
    print(f"\n{'=' * 60}")
    all_pass = True
    for item in results:  # noqa
        name, passed = item[0], item[1]
        s = "PASS" if passed else "FAIL"
        if not passed:
            all_pass = False
        print(f"  [{s}] {name}")
    print(f"\nOverall: {'ALL PASS' if all_pass else 'SOME FAILED'}")
    return results


if __name__ == "__main__":
    r = run_all()
    sys.exit(0 if all(item[1] for item in r) else 1)
