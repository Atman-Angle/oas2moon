import json, os, shutil, subprocess, sys, hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AUTH_FIXTURES_DIR = ROOT / "fixtures" / "auth"
OUTPUT_ROOT = ROOT / "tests" / "_build" / "t09-auth"
FRONTEND_DIR = ROOT / "src" / "frontend_adapter"
CORE_DIR = ROOT / "src" / "core_moonbit"
CODEGEN_DIR = ROOT / "src" / "codegen_moonbit"
RUNTIME_DIR = ROOT / "src" / "runtime_moonbit"

def run(cmd, cwd=None):
    result = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, encoding="utf-8")
    return result

def check(label, ok, detail=""):
    s = "PASS" if ok else "FAIL"
    print(f"  [{s}] {label}")
    if detail:
        for l in detail.splitlines()[:5]:
            print(f"    {l}")
    return ok

def get_file_list(pkg_dir):
    result = {}
    for f in sorted(pkg_dir.rglob("*")):
        if not f.is_file():
            continue
        rel = str(f.relative_to(pkg_dir)).replace("\\", "/")
        if rel.startswith("_build/") or rel.startswith(".mooncakes/"):
            continue
        with open(f, "rb") as fp:
            result[rel] = hashlib.sha256(fp.read()).hexdigest()
    return result

def write_file(p, content):
    with open(p, "w", encoding="utf-8", newline="\n") as f:
        f.write(content)

def read_file_normalized(p):
    with open(p, "rb") as f:
        content = f.read().decode("utf-8")
    return content.replace("\r\n", "\n")

def find_model_schemas(data):
    """Extract model type name to type info mapping from canonical IR."""
    models_map = {}
    for m in data.get("models", []):
        name = m.get("name", "")
        kind = m.get("kind", "")
        if kind == "enum":
            models_map[name] = {"kind": "enum", "members": m.get("members", [])}
        elif kind == "struct":
            models_map[name] = {"kind": "struct", "fields": m.get("fields", [])}
    return models_map

def type_to_moon(tr, models_map):
    if not tr:
        return "Unit"
    kind = tr.get("kind", "")
    name = tr.get("name", "")
    item = tr.get("item")
    if kind == "scalar":
        return {"String": "String", "Int": "Int", "Int64": "Int64", "Bool": "Bool", "Double": "Double", "Json": "Json"}.get(name, "String")
    if kind == "named":
        if name in models_map:
            return name
        return "Json"
    if kind == "array":
        return f"Array[{type_to_moon(item, models_map) if item else 'Json'}]"
    return "String"

def build_path_expr(path, params):
    parts = []
    i = 0
    while i < len(path):
        brace = path.find("{", i)
        if brace < 0:
            parts.append(("text", path[i:]))
            break
        if brace > i:
            parts.append(("text", path[i:brace]))
        end = path.find("}", brace)
        if end < 0:
            parts.append(("text", path[i:]))
            break
        pname = path[brace + 1:end]
        found = None
        for p in params:
            if p.get("wire_name", "") == pname:
                found = p.get("name", "")
                break
        parts.append(("var", found) if found else ("text", "{" + pname + "}"))
        i = end + 1
    if len(parts) == 1 and parts[0][0] == "text":
        return f'"{parts[0][1]}"'
    exprs = []
    for k, v in parts:
        if k == "text" and v:
            exprs.append(f'"{v}"')
        elif k == "var":
            exprs.append(f"{v}.to_string()")
    return " + ".join(exprs) if exprs else '""'

def gen_client(data):
    ops = data.get("operations", [])
    auth_schemes = data.get("auth_schemes", [])
    models_map = find_model_schemas(data)
    
    lines = [
        '///|',
        '/// Generated typed API client. Do not edit by hand.',
        '',
        '///|',
        'pub struct Client {',
        '  transport : CaptureTransport',
        '  config : Config',
        '} derive(Debug)',
        '',
        '///|',
        'pub fn Client::new(',
        '  transport : CaptureTransport,',
        '  base_url? : String = "",',
        '  bearer_token? : String,',
        '  basic_username? : String,',
        '  basic_password? : String,',
        '  api_key_name? : String,',
        '  api_key_value? : String,',
        '  api_key_location? : String,',
        ') -> Client {',
        '  { transport, config: Config::new(',
        '    base_url,',
        '    bearer_token?,',
        '    basic_username?,',
        '    basic_password?,',
        '    api_key_name?,',
        '    api_key_value?,',
        '    api_key_location?,',
        '  ) }',
        '}',
        '',
    ]
    
    for op in ops:
        fn_name = op.get("fn_name", "unknown")
        method = op.get("http_method", "GET")
        path = op.get("path", "/")
        params = op.get("parameters", [])
        security = op.get("security", [])
        
        lines.append("///|")
        lines.append(f"pub fn Client::{fn_name}(self : Client,")
        sig_params = []
        for i, p in enumerate(params):
            pn = p.get("name", "p")
            pt = type_to_moon(p.get("type", {}), models_map)
            req = p.get("required", True)
            sig_params.append(f"{pn} : {pt}{'' if req else '?'}")
        if sig_params:
            for i, sp in enumerate(sig_params):
                comma = "," if i < len(sig_params) - 1 else ""
                lines.append(f"  {sp}{comma}")
        lines.append(") -> Unit raise SdkError {")
        
        # Build auth
        if security:
            sec_list = json.dumps(security)
            lines.append(f'  let headers = auth_headers(self.config, {sec_list})')
            lines.append(f'  let query = auth_query(self.config, {sec_list})')
        else:
            lines.append('  let headers : Map[String, String] = Map([])')
            lines.append('  let query : Array[(String, String)] = []')
        
        # Add operation-specific params to headers
        for p in params:
            pn = p.get("name", "p")
            wn = p.get("wire_name", pn)
            loc = p.get("location", "")
            req = p.get("required", True)
            if loc == "header":
                if req:
                    lines.append(f'  headers["{wn}"] = {pn}')
                else:
                    lines.append(f'  match {pn} {{ Some(v) => headers["{wn}"] = v; None => () }}')
            elif loc == "query":
                if req:
                    lines.append(f'  query.push(("{wn}", {pn}.to_string()))')
                else:
                    lines.append(f'  match {pn} {{ Some(v) => query.push(("{wn}", v.to_string())); None => () }}')
        
        path_expr = build_path_expr(path, params)
        lines.append(f'  let request = Request::new("{method}", {path_expr}, query~, headers~)')
        lines.append("  let _ = send(self.transport, request)")
        lines.append("}")
        lines.append("")
    
    return "\n".join(lines)

def gen_sdk(out_dir, data):
    out_dir.mkdir(parents=True, exist_ok=True)
    write_file(out_dir / "canonical_ir.json", json.dumps(data, indent=2) + "\n")
    r = run(["moon", "run", ".", "--target", "native", "--",
             str(out_dir / "canonical_ir.json"), str(out_dir)], cwd=CODEGEN_DIR)
    if r.returncode != 0:
        print(f"  Codegen run failed: {r.stderr[:500]}")
        return False
    write_file(out_dir / "moon.pkg",
        'import {\n'
        '  "moonbitlang/core/encoding/utf8",\n'
        '  "moonbitlang/core/json",\n'
        '}\n'
        '\n'
        'supported_targets = "+native"\n')
    write_file(out_dir / "moon.mod",
        'name = "oas2moon/t09_auth"\n'
        '\n'
        'version = "0.1.0"\n'
        '\n'
        'preferred_target = "native"\n')
    for fn in ["runtime.mbt", "config.mbt", "encoding.mbt"]:
        write_file(out_dir / fn, read_file_normalized(RUNTIME_DIR / fn))
    write_file(out_dir / "client.mbt", gen_client(data))
    return True

def write_test_file(out_dir, fixture_name, data):
    """Write MoonBit test file that tests auth behavior using CaptureTransport."""
    ops = data.get("operations", [])
    security_map = {}
    for op in ops:
        security_map[op.get("operation_id", "")] = op.get("security", [])
    
    lines = [
        '///|',
        '/// T09: Authentication behavioral tests.',
        '',
    ]
    
    if fixture_name == "bearer":
        lines.extend([
            '///|',
            '/// Helper: check if a string contains a substring.',
            'fn str_contains(s : String, sub : String) -> Bool {',
            '  s.contains(sub)',
            '}',
            '',
            '///|',
            'test "bearer_auth_sets_authorization_header" {',
            '  let t = CaptureTransport::new(Response::new(200, body="[]"))',
            '  let c = Client::new(t, bearer_token="my-token")',
            '  let _ = c.get_items()',
            '  let req = t.last_request().unwrap()',
            '  assert_eq(req.headers()["Authorization"], "Bearer my-token")',
            '}',
            '',
            '///|',
            'test "bearer_auth_missing_token_raises_error" {',
            '  let t = CaptureTransport::new(Response::new(200))',
            '  let c = Client::new(t)',
            '  let outcome : Result[Unit, SdkError] = Ok(c.get_items()) catch {',
            '    err => Err(err)',
            '  }',
            '  match outcome {',
            '    Ok(_) => abort("expected InvalidRequest for missing bearer token")',
            '    Err(InvalidRequest(msg)) => assert_eq(str_contains(msg, "bearer"), true)',
            '    Err(err) => abort("expected InvalidRequest, got: " + err.to_string())',
            '  }',
            '}',
            '',
        ])
    elif fixture_name == "basic":
        lines.extend([
            '///|',
            'test "basic_auth_sets_authorization_header" {',
            '  let t = CaptureTransport::new(Response::new(200, body="[]"))',
            '  let c = Client::new(t, basic_username="alice", basic_password="secret")',
            '  let _ = c.get_items()',
            '  let req = t.last_request().unwrap()',
            '  let auth = req.headers()["Authorization"]',
            '  assert_eq(str_contains(auth, "Basic "), true)',
            '  assert_eq(str_contains(auth, "Basic YWxpY2U6c2VjcmV0"), true)',
            '}',
            '',
            '///|',
            'test "basic_auth_missing_username_raises_error" {',
            '  let t = CaptureTransport::new(Response::new(200))',
            '  let c = Client::new(t, basic_password="secret")',
            '  let outcome : Result[Unit, SdkError] = Ok(c.get_items()) catch {',
            '    err => Err(err)',
            '  }',
            '  match outcome {',
            '    Ok(_) => abort("expected InvalidRequest for missing basic username")',
            '    Err(InvalidRequest(msg)) => assert_eq(str_contains(msg, "username"), true)',
            '    Err(err) => abort("expected InvalidRequest, got: " + err.to_string())',
            '  }',
            '}',
            '',
            '///|',
            'test "basic_auth_missing_password_raises_error" {',
            '  let t = CaptureTransport::new(Response::new(200))',
            '  let c = Client::new(t, basic_username="alice")',
            '  let outcome : Result[Unit, SdkError] = Ok(c.get_items()) catch {',
            '    err => Err(err)',
            '  }',
            '  match outcome {',
            '    Ok(_) => abort("expected InvalidRequest for missing basic password")',
            '    Err(InvalidRequest(msg)) => assert_eq(str_contains(msg, "password"), true)',
            '    Err(err) => abort("expected InvalidRequest, got: " + err.to_string())',
            '  }',
            '}',
            '',
        ])
    elif fixture_name == "api-key-header":
        lines.extend([
            '///|',
            'test "api_key_header_sets_custom_header" {',
            '  let t = CaptureTransport::new(Response::new(200, body="[]"))',
            '  let c = Client::new(t, api_key_name="X-API-Key", api_key_value="abcd1234", api_key_location="header")',
            '  let _ = c.get_items()',
            '  let req = t.last_request().unwrap()',
            '  assert_eq(req.headers()["X-API-Key"], "abcd1234")',
            '}',
            '',
            '///|',
            'test "api_key_header_missing_name_raises_error" {',
            '  let t = CaptureTransport::new(Response::new(200))',
            '  let c = Client::new(t, api_key_value="val", api_key_location="header")',
            '  let outcome : Result[Unit, SdkError] = Ok(c.get_items()) catch {',
            '    err => Err(err)',
            '  }',
            '  match outcome {',
            '    Ok(_) => abort("expected InvalidRequest for missing apiKey name")',
            '    Err(InvalidRequest(msg)) => assert_eq(str_contains(msg, "name"), true)',
            '    Err(err) => abort("expected InvalidRequest, got: " + err.to_string())',
            '  }',
            '}',
            '',
            '///|',
            'test "api_key_header_missing_value_raises_error" {',
            '  let t = CaptureTransport::new(Response::new(200))',
            '  let c = Client::new(t, api_key_name="X-API-Key", api_key_location="header")',
            '  let outcome : Result[Unit, SdkError] = Ok(c.get_items()) catch {',
            '    err => Err(err)',
            '  }',
            '  match outcome {',
            '    Ok(_) => abort("expected InvalidRequest for missing apiKey value")',
            '    Err(InvalidRequest(msg)) => assert_eq(str_contains(msg, "value"), true)',
            '    Err(err) => abort("expected InvalidRequest, got: " + err.to_string())',
            '  }',
            '}',
            '',
        ])
    elif fixture_name == "api-key-query":
        lines.extend([
            '///|',
            'test "api_key_query_sets_query_parameter" {',
            '  let t = CaptureTransport::new(Response::new(200, body="[]"))',
            '  let c = Client::new(t, api_key_name="api_key", api_key_value="secret", api_key_location="query")',
            '  let _ = c.get_items()',
            '  let req = t.last_request().unwrap()',
            '  assert_eq(req.query().length(), 1)',
            '  let (k, v) = req.query()[0]',
            '  assert_eq(k, "api_key")',
            '  assert_eq(v, "secret")',
            '  // apiKey query should NOT set Authorization header',
            '  let h = req.headers()',
            '  match h.get("Authorization") {',
            '    None => ()',
            '    Some(_) => abort("apiKey query must not set Authorization header")',
            '  }',
            '}',
            '',
            '///|',
            'test "api_key_query_missing_value_raises_error" {',
            '  let t = CaptureTransport::new(Response::new(200))',
            '  let c = Client::new(t, api_key_name="api_key", api_key_location="query")',
            '  let outcome : Result[Unit, SdkError] = Ok(c.get_items()) catch {',
            '    err => Err(err)',
            '  }',
            '  match outcome {',
            '    Ok(_) => abort("expected InvalidRequest for missing apiKey value")',
            '    Err(InvalidRequest(msg)) => assert_eq(str_contains(msg, "value"), true)',
            '    Err(err) => abort("expected InvalidRequest, got: " + err.to_string())',
            '  }',
            '}',
            '',
        ])
    elif fixture_name == "anonymous":
        lines.extend([
            '///|',
            'test "anonymous_operation_no_auth_headers" {',
            '  let t = CaptureTransport::new(Response::new(200, body="[]"))',
            '  let c = Client::new(t)',
            '  let _ = c.get_items()',
            '  let req = t.last_request().unwrap()',
            '  // No auth headers should be set',
            '  match req.headers().get("Authorization") {',
            '    None => ()',
            '    Some(_) => abort("anonymous operation must not set Authorization")',
            '  }',
            '  // No query params from auth',
            '  assert_eq(req.query().length(), 0)',
            '}',
            '',
            '///|',
            'test "anonymous_operation_succeeds_without_credentials" {',
            '  let t = CaptureTransport::new(Response::new(200, body="[]"))',
            '  let c = Client::new(t)',
            '  c.get_items()',
            '}',
            '',
        ])
    
    test_file_name = f"t09_{fixture_name}_test.mbt"
    test_path = out_dir / test_file_name
    content = "\n".join(lines)
    write_file(test_path, content)
    return test_path

def run_auth_fixture(fixture_name):
    print(f"\n--- {fixture_name} ---")
    results = []
    fixture_path = AUTH_FIXTURES_DIR / f"{fixture_name}.json"
    out_dir = OUTPUT_ROOT / fixture_name
    
    if out_dir.exists():
        shutil.rmtree(str(out_dir))
    out_dir.mkdir(parents=True)
    
    # Step 1: Frontend adapter
    norm = out_dir / "normalized.json"
    r = run(["moon", "run", ".", "--target", "native", "--",
             str(fixture_path), str(norm)], cwd=FRONTEND_DIR)
    ok = r.returncode == 0 and norm.exists()
    check("frontend: normalize spec", ok, r.stderr[:300] if not ok else "")
    results.append(("frontend", ok))
    if not ok:
        return results
    
    # Step 2: Core lowering
    canon = out_dir / "canonical.json"
    r = run(["moon", "run", ".", "--target", "native", "--",
             str(norm), str(canon)], cwd=CORE_DIR)
    ok = r.returncode == 0 and canon.exists()
    check("core: canonical IR", ok, r.stderr[:300] if not ok else "")
    results.append(("core", ok))
    if not ok:
        return results
    
    data = json.load(open(canon))
    
    # Verify auth_schemes in canonical IR
    schemes = data.get("auth_schemes", [])
    ops = data.get("operations", [])
    print(f"  Auth schemes: {[s.get('kind') for s in schemes]}")
    print(f"  Operations: {[{'id': o.get('operation_id'), 'security': o.get('security')} for o in ops]}")
    
    # Step 3: Generate SDK
    gen = out_dir / "generated"
    ok = gen_sdk(gen, data)
    check("codegen: SDK generation", ok)
    results.append(("codegen", ok))
    if not ok:
        return results
    
    # Step 4: Write test file
    test_file = write_test_file(gen, fixture_name, data)
    check(f"test file: {test_file.name}", True)
    
    # Step 5: moon fmt
    r = run(["moon", "fmt"], cwd=gen)
    r = run(["moon", "fmt", "--check"], cwd=gen)
    ok = r.returncode == 0
    check("moon fmt --check", ok)
    results.append(("fmt", ok))
    
    # Step 6: moon check
    r = run(["moon", "check", "--target", "native", "--deny-warn"], cwd=gen)
    ok = r.returncode == 0
    check("moon check", ok, r.stderr[:500] if not ok else "")
    results.append(("check", ok))
    
    # Step 7: moon test
    if ok:
        r = run(["moon", "test", "--target", "native", "--deny-warn"], cwd=gen)
        ok = r.returncode == 0
        check("moon test", ok)
        if r.stdout:
            for l in r.stdout.splitlines()[-10:]:
                print(f"    {l}")
        results.append(("test", ok))
    else:
        results.append(("test", False))
    
    # Step 8: Determinism check
    gen2 = out_dir / "generated2"
    ok2 = gen_sdk(gen2, data)
    if ok2:
        write_test_file(gen2, fixture_name, data)
        run(["moon", "fmt"], cwd=gen2)
        # Compare file lists excluding canonical_ir.json
        f1 = {k: v for k, v in get_file_list(gen).items() if k != "canonical_ir.json"}
        f2 = {k: v for k, v in get_file_list(gen2).items() if k != "canonical_ir.json"}
        ok = f1 == f2
        if not ok:
            for k in sorted(set(f1.keys()) ^ set(f2.keys())):
                print(f"    Missing: {k}")
            for k in sorted(set(f1.keys()) & set(f2.keys())):
                if f1[k] != f2[k]:
                    c1 = open(gen / k, "rb").read()[:80]
                    c2 = open(gen2 / k, "rb").read()[:80]
                    print(f"    Diff for {k}:")
                    print(f"      run1: {c1[:60]}")
                    print(f"      run2: {c2[:60]}")
    else:
        ok = False
    check(f"deterministic ({len(f1) if ok2 else 0} files)", ok)
    results.append(("determinism", ok))
    
    return results

def test_all():
    print("=" * 60)
    print("T09: Authentication")
    print("=" * 60)
    
    fixture_names = ["bearer", "basic", "api-key-header", "api-key-query", "anonymous"]
    all_results = {}
    
    for name in fixture_names:
        all_results[name] = run_auth_fixture(name)
    
    print(f"\n{'=' * 60}")
    print("Summary:")
    print(f"{'=' * 60}")
    all_pass = True
    for name, results in all_results.items():
        passed = all(v for _, v in results)
        status = "PASS" if passed else "FAIL"
        if not passed:
            all_pass = False
        details = " ".join(f"{k}:{'PASS' if v else 'FAIL'}" for k, v in results)
        print(f"  {name:20s} {status:6s}  [{details}]")
    
    print(f"\nOverall: {'ALL PASS' if all_pass else 'SOME FAILED'}")
    return all_pass

if __name__ == "__main__":
    ok = test_all()
    sys.exit(0 if ok else 1)
