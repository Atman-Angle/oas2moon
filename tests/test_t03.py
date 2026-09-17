import json,os,shutil,subprocess,sys,hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES_DIR = ROOT / "fixtures" / "petstore"
OUTPUT_ROOT = ROOT / "tests" / "_build" / "t03-slice"
FRONTEND_DIR = ROOT / "src" / "frontend_adapter"
CORE_DIR = ROOT / "src" / "core_moonbit"
CODEGEN_DIR = ROOT / "src" / "codegen_moonbit"
RUNTIME_DIR = ROOT / "src" / "runtime_moonbit"

def run(cmd, cwd=None):
    result = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, encoding="utf-8")
    return result

def check(label, ok, detail=""):
    s = "PASS" if ok else "FAIL"; print(f"  [{s}] {label}")
    if detail:
        for l in detail.splitlines()[:5]: print(f"    {l}")
    return ok

def get_file_list(pkg_dir):
    result = {}
    for f in sorted(pkg_dir.rglob("*")):
        if not f.is_file(): continue
        rel = str(f.relative_to(pkg_dir)).replace("\\","/")
        if rel.startswith("_build/") or rel.startswith(".mooncakes/"): continue
        with open(f, "rb") as fp: result[rel] = hashlib.sha256(fp.read()).hexdigest()
    return result

def write_file(p, content):
    with open(p, "w", encoding="utf-8", newline="\n") as f: f.write(content)

def read_file_normalized(p):
    """Read file and normalize line endings to LF for deterministic output."""
    with open(p, "rb") as f:
        content = f.read().decode("utf-8")
    return content.replace("\r\n", "\n")

def gen_sdk(out_dir, data, test_code=None):
    out_dir.mkdir(parents=True, exist_ok=True)
    write_file(out_dir / "canonical_ir.json", json.dumps(data, indent=2) + "\n")
    r = run(["moon","run",".","--target","native","--",str(out_dir/"canonical_ir.json"),str(out_dir)], cwd=CODEGEN_DIR)
    if r.returncode != 0: return False
    # Normalize line endings from source for determinism
    for fn in ["runtime.mbt", "config.mbt", "encoding.mbt"]:
        write_file(out_dir / fn, read_file_normalized(RUNTIME_DIR / fn))
    if test_code is not None:
        write_file(out_dir / "t03_test.mbt", test_code)
    return True

def build_path_expr(path, params):
    parts = []; i = 0
    while i < len(path):
        brace = path.find("{", i)
        if brace < 0: parts.append(("text", path[i:])); break
        if brace > i: parts.append(("text", path[i:brace]))
        end = path.find("}", brace)
        if end < 0: parts.append(("text", path[i:])); break
        pname = path[brace+1:end]
        found = None
        for p in params:
            if p.get("wire_name","") == pname: found = p.get("name",""); break
        parts.append(("var", found) if found else ("text", "{"+pname+"}"))
        i = end + 1
    if len(parts) == 1 and parts[0][0] == "text": return f'"{parts[0][1]}"'
    exprs = []
    for k, v in parts:
        if k == "text" and v: exprs.append(f'"{v}"')
        elif k == "var": exprs.append(f"{v}.to_string()")
    return " + ".join(exprs) if exprs else '""'

def gen_client(data):
    ops = data.get("operations", [])
    lines = ["///|","/// Generated typed API client.","","///|","pub struct Client {","  transport : CaptureTransport","} derive(Debug)","","///|","pub fn Client::new(transport : CaptureTransport) -> Client {","  { transport, }","}",""]
    for op in ops:
        fn_name = op.get("fn_name","unknown")
        method = op.get("method","GET")
        path = op.get("path","/")
        params = op.get("parameters",[])
        lines.append("///|")
        lines.append(f"pub fn Client::{fn_name}(self : Client,")
        for i, p in enumerate(params):
            pn = p.get("name","p")
            pt = type_to_moon(p.get("type",{}), data.get("models",[]))
            req = p.get("required",True)
            lines.append(f'  {pn} : {pt}{"" if req else "?"}{"," if i < len(params)-1 else ""}')
        lines.append(") -> Response raise SdkError {")
        lines.append('  let headers : Map[String, String] = Map([])')
        for p in params:
            pn = p.get("name","p"); wn = p.get("wire_name",pn)
            loc = p.get("location",""); req = p.get("required",True)
            if loc == "header":
                if req: lines.append(f'  headers["{wn}"] = {pn}')
                else: lines.append(f'  match {pn} {{ Some(v) => headers["{wn}"] = v; None => () }}')
        path_expr = build_path_expr(path, params)
        query_items = []
        for p in params:
            if p.get("location") == "query":
                pn = p.get("name",""); wn = p.get("wire_name",pn); req = p.get("required",True)
                if req: query_items.append(f'("{wn}", {pn}.to_string())')
                else: query_items.append(f'match {pn} {{ Some(v) => ("{wn}", v.to_string()); None => ("", "") }}')
        qa = f", query=[{', '.join(query_items)}]" if query_items else ""
        lines.append(f'  let req = Request::new("{method}", {path_expr}{qa}, headers=headers)')
        lines.append("  send(self.transport, req)")
        lines.append("}")
        lines.append("")
    return "\n".join(lines)


def run_all():
    print("="*60)
    print("T03: GET Minimal Complete Vertical Slice")
    print("="*60)
    results = []
    if OUTPUT_ROOT.exists(): shutil.rmtree(str(OUTPUT_ROOT))
    OUTPUT_ROOT.mkdir(parents=True)
    
    spec = FIXTURES_DIR / "openapi.json"
    norm = OUTPUT_ROOT / "normalized.json"
    r = run(["moon","run",".","--target","native","--",str(spec),str(norm)], cwd=FRONTEND_DIR)
    ok = r.returncode == 0 and norm.exists()
    results.append(("frontend", ok, "")); check("frontend: petstore normalized", ok)
    
    canon_path = OUTPUT_ROOT / "canonical.json"
    r = run(["moon","run",".","--target","native","--",str(norm),str(canon_path)], cwd=CORE_DIR)
    ok = r.returncode == 0 and canon_path.exists()
    results.append(("core", ok, "")); check("core: canonical IR", ok)
    if not ok:
        return results
    data = json.load(open(canon_path))
    
    gen = OUTPUT_ROOT / "generated"
    test_code = "\n".join(["///|",'test "client_constructs" {',"  let t = CaptureTransport::new(Response::new(200))","  let _c = Client::new(t)","}",""])
    ok = gen_sdk(gen, data, test_code=test_code)
    results.append(("codegen", ok, "")); check("codegen: SDK generation", ok)
    if not ok:
        return results
    for f in sorted(gen.iterdir()):
        if not f.name.startswith("_"): print(f"    {f.name} ({f.stat().st_size}b)")
    
    run(["moon","fmt"], cwd=gen)
    r = run(["moon","fmt","--check"], cwd=gen)
    ok = r.returncode == 0
    results.append(("fmt", ok, "")); check("moon fmt --check", ok)
    
    r = run(["moon","check","--target","native"], cwd=gen)
    ok = r.returncode == 0
    results.append(("check", ok, r.stderr[:500] if not ok else "")); check("moon check", ok)
    if not ok and r.stderr:
        for l in r.stderr.splitlines()[:25]: print(f"    {l}")
    
    if ok:
        r = run(["moon","test","--target","native"], cwd=gen)
        ok2 = r.returncode == 0
        results.append(("test", ok2, "")); check("moon test", ok2)
        if r.stdout:
            for l in r.stdout.splitlines()[-5:]: print(f"    {l}")
    
    gen2 = OUTPUT_ROOT / "generated2"
    ok = gen_sdk(gen2, data, test_code=test_code)
    if ok:
        run(["moon","fmt"], cwd=gen2)
        f1 = {k:v for k,v in get_file_list(gen).items() if k != "canonical_ir.json"}
        f2 = {k:v for k,v in get_file_list(gen2).items() if k != "canonical_ir.json"}
        ok = f1 == f2
        if not ok:
            for k in sorted(set(f1.keys()) ^ set(f2.keys())): print(f"  Missing: {k}")
            for k in sorted(set(f1.keys()) & set(f2.keys())):
                if f1[k] != f2[k]:
                    p1 = gen / k; p2 = gen2 / k
                    c1 = open(p1,"rb").read()[:80]; c2 = open(p2,"rb").read()[:80]
                    print(f"  Diff: {k}")
                    print(f"    run1: {c1[:60]}")
                    print(f"    run2: {c2[:60]}")
    results.append(("determinism", ok, "")); check(f"deterministic ({len(f1)} files)", ok)
    
    print(f"\n{'='*60}")
    all_pass = True
    for name, passed, _ in results:
        s = "PASS" if passed else "FAIL"
        if not passed: all_pass = False
        print(f"  [{s}] {name}")
    print(f"\nOverall: {'ALL PASS' if all_pass else 'SOME FAILED'}")
    return results

if __name__ == "__main__":
    r = run_all()
    sys.exit(0 if all(x[1] for x in r) else 1)
