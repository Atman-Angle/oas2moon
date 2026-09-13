import json
import os
import subprocess
import sys
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# sys.path moved to tests/reference_python

FIXTURES_DIR = ROOT / "fixtures" / "phase2"
OUTPUT_ROOT = ROOT / "tests" / "_build" / "phase2-tests"
CODEGEN_DIR = ROOT / "src" / "codegen_moonbit"

SKIP_CHECK = os.environ.get("SKIP_MOON_CHECK", "0") == "1"


def codegen(fixture: Path, out_dir: Path) -> None:
    # Clean existing files before generating
    import shutil
    if out_dir.exists():
        for existing in list(out_dir.iterdir()):
            if existing.name == '_build':
                continue
            if existing.is_dir():
                shutil.rmtree(existing, ignore_errors=True)
            else:
                existing.unlink()
    out_dir.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["moon", "run", ".", "--target", "native", "--",
         str(fixture.resolve()), str(out_dir.resolve())],
        cwd=str(CODEGEN_DIR),
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )


def moon_fmt(pkg_dir: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["moon", "fmt"],
        cwd=str(pkg_dir),
        capture_output=True,
        text=True,
        encoding="utf-8",
    )


def moon_fmt_check(pkg_dir: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["moon", "fmt", "--check"],
        cwd=str(pkg_dir),
        capture_output=True,
        text=True,
        encoding="utf-8",
    )


def moon_check(pkg_dir: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["moon", "check", "--target", "native", "--deny-warn"],
        cwd=str(pkg_dir),
        capture_output=True,
        text=True,
        encoding="utf-8",
    )


def moon_test(pkg_dir: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["moon", "test", "--target", "native", "--deny-warn"],
        cwd=str(pkg_dir),
        capture_output=True,
        text=True,
        encoding="utf-8",
    )


def get_file_list(pkg_dir: Path) -> dict[str, str]:
    result = {}
    for f in sorted(pkg_dir.rglob("*")):
        if not f.is_file():
            continue
        rel = str(f.relative_to(pkg_dir)).replace("\\", "/")
        if rel.startswith("_build/") or rel.startswith(".mooncakes/") or rel == "":
            continue
        result[rel] = hashlib.sha256(f.read_bytes()).hexdigest()
    return result


def escape_moonbit_string(s: str) -> str:
    """Escape a Python string for use as a MoonBit double-quoted string literal."""
    result = []
    for ch in s:
        if ch == "\\":
            result.append("\\\\")
        elif ch == '"':
            result.append('\\"')
        elif ch == "\n":
            result.append("\\n")
        elif ch == "\r":
            result.append("\\r")
        elif ch == "\t":
            result.append("\\t")
        elif ord(ch) < 32:
            result.append(f"\\u{ord(ch):04x}")
        else:
            result.append(ch)
    return '"' + "".join(result) + '"'


def write_moonbit_json_value(val) -> str:
    """Write a Python value as a MoonBit Json expression.
    Returns MoonBit code that constructs the Json value directly."""
    if val is None:
        return "Json::null()"
    elif isinstance(val, bool):
        return "Json::true()" if val else "Json::false()"
    elif isinstance(val, int):
        return f"Json::number({val}.0, repr=\"{val}\")"
    elif isinstance(val, float):
        repr_str = str(val)
        return f"Json::number({val}, repr=\"{repr_str}\")"
    elif isinstance(val, str):
        return f"Json::string({escape_moonbit_string(val)})"
    elif isinstance(val, list):
        items = ", ".join(write_moonbit_json_value(v) for v in val)
        return f"Json::array([{items}])"
    elif isinstance(val, dict):
        entries = ", ".join(
            f"({escape_moonbit_string(k)}, {write_moonbit_json_value(v)})"
            for k, v in val.items()
        )
        return f"Json::object(Map([{entries}]))"
    else:
        return f"Json::null()"


def generate_roundtrip_test(model: dict, data: dict) -> list[str]:
    """Generate a round-trip test for a struct model.
    
    Returns list of MoonBit lines for the test.
    """
    name = model.get("name", "Unknown")
    fields = model.get("fields", [])
    additional_props = model.get("additional_properties", False)
    lines = []
    
    test_name = "roundtrip_" + name
    lines.append(f'test "{test_name}" {{')
    
    json_input = {}
    has_optional_nullable = False
    for f in fields:
        fname = f.get("wire_name")
        presence = f.get("presence")
        ftype = f.get("type", {})
        fkind = ftype.get("kind")
        ftypename = ftype.get("name")

        if presence in ("required", "required_nullable"):
            if fkind == "scalar":
                if ftypename == "String":
                    json_input[fname] = "test_value"
                elif ftypename == "Int":
                    json_input[fname] = 42
                elif ftypename == "Int64":
                    json_input[fname] = 1234567890123
                elif ftypename == "Double":
                    json_input[fname] = 3.14
                elif ftypename == "Bool":
                    json_input[fname] = True
                elif ftypename == "Json":
                    json_input[fname] = {"key": "val"}
            elif fkind == "array":
                item = ftype.get("item", {})
                ikind = item.get("kind")
                iname = item.get("name")
                if ikind == "scalar" and iname == "Int64":
                    json_input[fname] = [100, 200]
                elif ikind == "scalar" and iname == "String":
                    json_input[fname] = ["a", "b"]
                elif ikind == "scalar" and iname == "Int":
                    json_input[fname] = [1, 2]
                elif ikind == "scalar" and iname == "Double":
                    json_input[fname] = [1.0, 2.0]
                else:
                    json_input[fname] = []
            elif fkind == "named":
                ref_name = ftypename
                for m2 in data.get("models", []):
                    if m2.get("name") == ref_name and m2.get("kind") == "enum":
                        members = m2.get("members", [])
                        if members:
                            json_input[fname] = members[0][1]
                        break
                    elif m2.get("name") == ref_name and m2.get("kind") == "struct":
                        sub_json = {}
                        for sf in m2.get("fields", []):
                            sfname = sf.get("wire_name")
                            sfpresence = sf.get("presence")
                            if sfpresence in ("required", "required_nullable"):
                                sub_json[sfname] = "nested_val" if sf.get("type", {}).get("name") == "String" else 0
                        json_input[fname] = sub_json
                        break
        elif presence == "required_nullable":
            if fkind == "scalar" and ftypename == "String":
                json_input[fname] = "present"
            elif fkind == "array":
                json_input[fname] = ["x"]
        elif presence == "optional":
            if fkind == "scalar":
                if ftypename == "Int64":
                    json_input[fname] = 999
                elif ftypename == "String":
                    json_input[fname] = "opt_val"
                elif ftypename in ("Int",):
                    json_input[fname] = 99
                elif ftypename == "Double":
                    json_input[fname] = 2.5
                elif ftypename == "Bool":
                    json_input[fname] = True
        elif presence == "optional_nullable":
            has_optional_nullable = True
            if fkind == "scalar" and ftypename == "String":
                json_input[fname] = "nick_val"
    
    json_str = json.dumps(json_input, ensure_ascii=False, separators=(",", ":"))
    
    lines.append(f"  let json_str : String = {escape_moonbit_string(json_str)}")
    lines.append(f"  let json_val = @json.parse(json_str)")
    lines.append(f"  let parsed : {name} = @json.from_json(json_val)")
    lines.append(f"  let re_val = @json.to_json(parsed)")
    lines.append(f"  let re_str = re_val.stringify()")
    lines.append(f"  let re_parsed : {name} = @json.from_json(@json.parse(re_str))")
    lines.append(f"  assert_eq(parsed, re_parsed)")
    lines.append("}")
    lines.append("")
    
    return lines


def generate_invalid_input_tests(model: dict, data: dict, fixture_name: str) -> list[str]:
    """Generate invalid input tests for a struct model.
    
    Tests: missing required property, wrong primitive type, invalid enum value.
    """
    name = model.get("name", "Unknown")
    fields = model.get("fields", [])
    lines = []
    
    # Find required fields
    required_fields = [f for f in fields if f.get("presence") in ("required", "required_nullable")]
    has_enum_field = any(
        f.get("type", {}).get("kind") == "named"
        for f in fields
    )
    
    # 1. Missing required property
    if required_fields:
        missing_field = required_fields[0]["wire_name"]
        test_name = f"invalid_missing_required_{missing_field}"
        lines.append(f'test "{test_name}" {{')
        lines.append("  let caught = try {")
        
        # Build JSON missing the required field
        partial_json = {}
        for f in fields:
            fname = f.get("wire_name")
            presence = f.get("presence")
            ftype = f.get("type", {})
            fkind = ftype.get("kind")
            ftypename = ftype.get("name")
            
            if presence in ("required", "required_nullable"):
                if fname != missing_field:
                    if fkind == "scalar" and ftypename == "String":
                        partial_json[fname] = "val"
                    elif fkind == "scalar" and ftypename == "Int":
                        partial_json[fname] = 0
                    elif fkind == "scalar" and ftypename == "Bool":
                        partial_json[fname] = False
                    elif fkind == "scalar" and ftypename == "Double":
                        partial_json[fname] = 0.0
                    elif fkind == "scalar" and ftypename == "Int64":
                        partial_json[fname] = 0
                    elif fkind == "scalar" and ftypename == "Json":
                        partial_json[fname] = None
                    elif fkind == "array":
                        partial_json[fname] = []
                    elif fkind == "named":
                        partial_json[fname] = "red"
            elif presence == "optional":
                if fkind == "scalar" and ftypename == "String":
                    partial_json[fname] = "opt"
            elif presence == "optional_nullable":
                if fkind == "scalar" and ftypename == "String":
                    partial_json[fname] = "val"
        
        partial_str = json.dumps(partial_json, ensure_ascii=False, separators=(",", ":"))
        lines.append(f"    let _ : {name} = @json.from_json(@json.parse({escape_moonbit_string(partial_str)}))")
        lines.append("    false")
        lines.append("  } catch {")
        lines.append('    _ => true')
        lines.append("  }")
        lines.append('  assert_eq(caught, true)')
        lines.append("}")
        lines.append("")
    
    # 2. Wrong primitive type - send a string where Int is expected
    for f in fields:
        ftype = f.get("type", {})
        fkind = ftype.get("kind")
        ftypename = ftype.get("name")
        fname = f.get("wire_name")
        presence = f.get("presence")
        
        if fkind == "scalar" and ftypename == "Int" and presence in ("required", "required_nullable"):
            test_name = f"invalid_wrong_type_{fname}"
            lines.append(f'test "{test_name}" {{')
            lines.append("  let caught = try {")
            
            wrong_json = {}
            for f2 in fields:
                f2name = f2.get("wire_name")
                f2presence = f2.get("presence")
                f2type = f2.get("type", {})
                f2kind = f2type.get("kind")
                f2typename = f2type.get("name")
                
                if f2name == fname:
                    wrong_json[f2name] = "not_an_int"
                elif f2presence in ("required", "required_nullable"):
                    if f2kind == "scalar" and f2typename == "String":
                        wrong_json[f2name] = "val"
                    elif f2kind == "scalar" and f2typename == "Bool":
                        wrong_json[f2name] = True
                    elif f2kind == "scalar" and f2typename == "Int":
                        wrong_json[f2name] = 0
                    elif f2kind == "scalar" and f2typename == "Double":
                        wrong_json[f2name] = 0.0
                    elif f2kind == "scalar" and f2typename == "Int64":
                        wrong_json[f2name] = 0
                    elif f2kind == "array":
                        wrong_json[f2name] = []
                    elif f2kind == "named":
                        wrong_json[f2name] = "red"
            
            wrong_str = json.dumps(wrong_json, ensure_ascii=False, separators=(",", ":"))
            lines.append(f"    let _ : {name} = @json.from_json(@json.parse({escape_moonbit_string(wrong_str)}))")
            lines.append("    false")
            lines.append("  } catch {")
            lines.append('    _ => true')
            lines.append("  }")
            lines.append('  assert_eq(caught, true)')
            lines.append("}")
            lines.append("")
            break  # Just test one field
    
    # 3. Invalid enum value (if model contains an enum-typed field)
    for f in fields:
        ftype = f.get("type", {})
        if ftype.get("kind") == "named":
            ref_name = ftype.get("name")
            # Check if ref is an enum
            for m2 in data.get("models", []):
                if m2.get("name") == ref_name and m2.get("kind") == "enum":
                    fname = f.get("wire_name")
                    test_name = f"invalid_enum_{fname}"
                    lines.append(f'test "{test_name}" {{')
                    lines.append("  let caught = try {")
                    
                    enum_json = {}
                    for f2 in fields:
                        f2name = f2.get("wire_name")
                        f2presence = f2.get("presence")
                        f2type = f2.get("type", {})
                        f2kind = f2type.get("kind")
                        f2typename = f2type.get("name")
                        
                        if f2name == fname:
                            enum_json[f2name] = "invalid_enum_value"
                        elif f2presence in ("required", "required_nullable"):
                            if f2kind == "scalar" and f2typename == "String":
                                enum_json[f2name] = "val"
                            elif f2kind == "scalar" and f2typename == "Int":
                                enum_json[f2name] = 0
                            elif f2kind == "scalar" and f2typename == "Bool":
                                enum_json[f2name] = True
                            elif f2kind == "scalar" and f2typename == "Double":
                                enum_json[f2name] = 0.0
                            elif f2kind == "scalar" and f2typename == "Int64":
                                enum_json[f2name] = 0
                            elif f2kind == "array":
                                enum_json[f2name] = []
                        elif f2presence == "optional":
                            if f2kind == "scalar" and f2typename == "String":
                                enum_json[f2name] = "opt"
                    
                    enum_str = json.dumps(enum_json, ensure_ascii=False, separators=(",", ":"))
                    lines.append(f"    let _ : {name} = @json.from_json(@json.parse({escape_moonbit_string(enum_str)}))")
                    lines.append("    false")
                    lines.append("  } catch {")
                    lines.append('    _ => true')
                    lines.append("  }")
                    lines.append('  assert_eq(caught, true)')
                    lines.append("}")
                    lines.append("")
                    break
            break  # Only test one enum field
    
    return lines



def has_codec(model: dict) -> bool:
    """Check if a model struct has ToJson/FromJson codec support.
    
    Empty structs with no fields and no additional_properties
    do not get codec generation (the emitter skips them).
    """
    if model.get("kind") != "struct":
        return True  # enums always have codec
    fields = model.get("fields", [])
    additional_props = model.get("additional_properties", False)
    if not fields and not additional_props:
        return False  # Closed-like: no fields, no additional_properties
    return True


def write_test_file(pkg_dir: Path, fixture_name: str, data: dict) -> Path:
    """Generate a MoonBit test file with round-trip and invalid-input tests."""
    lines = []
    lines.append("///|")
    lines.append("/// Phase 2 round-trip and invalid-input tests for " + fixture_name)
    lines.append("")

    for model in data.get("models", []):
        kind = model.get("kind")
        
        if kind == "struct":
            if not has_codec(model):
                continue  # Skip Closed-like structs without codec
            rt_lines = generate_roundtrip_test(model, data)
            lines.extend(rt_lines)
            
            inv_lines = generate_invalid_input_tests(model, data, fixture_name)
            lines.extend(inv_lines)

    test_path = pkg_dir / "models_test.mbt"
    test_path.write_text("\n".join(lines), encoding="utf-8")
    return test_path


def test_all_fixtures():
    fixtures = sorted(FIXTURES_DIR.glob("*.json"))
    assert len(fixtures) > 0, f"No fixtures found in {FIXTURES_DIR}"

    results = []

    for fixture in fixtures:
        name = fixture.stem
        print(f"\n{'='*60}")
        print(f"Fixture: {name}")
        print(f"{'='*60}")

        out_dir = OUTPUT_ROOT / name / "generated"
        out_dir2 = OUTPUT_ROOT / name / "generated2"

        data = json.loads(fixture.read_text(encoding="utf-8"))

        print(f"  Generating (run 1)...")
        codegen(fixture, out_dir)
        print(f"  Generating (run 2)...")
        codegen(fixture, out_dir2)

        files1 = get_file_list(out_dir)
        files2 = get_file_list(out_dir2)
        assert files1.keys() == files2.keys(), \
            f"File lists differ for {name}: {set(files1.keys()) ^ set(files2.keys())}"
        for fpath, hash1 in files1.items():
            hash2 = files2[fpath]
            assert hash1 == hash2, f"Content differs for {name}/{fpath}"
        print(f"  Determinism: PASS (files={len(files1)})")

        # Run moon fmt first
        moon_fmt(out_dir)
        fmt_result = moon_fmt_check(out_dir)
        fmt_ok = fmt_result.returncode == 0
        if fmt_ok:
            print(f"  moon fmt --check: PASS")
        else:
            print(f"  moon fmt --check: FAIL")
            print(f"    {fmt_result.stderr[:500] if fmt_result.stderr else '(no stderr)'}")

        check_ok = True
        if not SKIP_CHECK:
            check_result = moon_check(out_dir)
            check_ok = check_result.returncode == 0
            if check_ok:
                print(f"  moon check --deny-warn: PASS")
            else:
                print(f"  moon check --deny-warn: FAIL")
                err = check_result.stderr or "(no stderr)"
                print(f"    {err[:500]}")
        else:
            print(f"  moon check: SKIPPED")

        # Write test file
        test_file = write_test_file(out_dir, name, data)
        print(f"  Test file: {test_file.name}")

        # Format again after test file addition
        moon_fmt(out_dir)

        check_with_tests_ok = True
        if not SKIP_CHECK:
            check_with_test = moon_check(out_dir)
            check_with_tests_ok = check_with_test.returncode == 0
            if check_with_tests_ok:
                print(f"  moon check (with tests): PASS")
            else:
                print(f"  moon check (with tests): FAIL")
                err = check_with_test.stderr or "(no stderr)"
                print(f"    {err[:500]}")
        else:
            print(f"  moon check (with tests): SKIPPED")

        test_ok = True
        if not SKIP_CHECK:
            test_result = moon_test(out_dir)
            test_ok = test_result.returncode == 0
            if test_ok:
                print(f"  moon test --deny-warn: PASS")
            else:
                print(f"  moon test --deny-warn: FAIL")
                output = (test_result.stdout or "") + (test_result.stderr or "")
                for line in output.splitlines():
                    if "fail" in line.lower() or "error" in line.lower():
                        print(f"    {line}")
        else:
            print(f"  moon test: SKIPPED")

        results.append({
            "fixture": name,
            "determinism": True,
            "fmt": fmt_ok,
            "check": check_ok,
            "check_with_tests": check_with_tests_ok,
            "test": test_ok,
        })

    print(f"\n{'='*60}")
    print("Summary:")
    print(f"{'='*60}")
    all_pass = True
    for r in results:
        status = "PASS" if all(v == True for k, v in r.items() if k != "fixture") else "FAIL"
        if status == "FAIL":
            all_pass = False
        print(f"  {r['fixture']:40s} {status}")
    print(f"\nAll {len(results)} fixtures {'PASS' if all_pass else 'FAIL'}")
    assert all_pass, f"Some fixtures failed"
    print(f"\nAll {len(results)} fixtures PASS")


if __name__ == "__main__":
    test_all_fixtures()

def sample_value_for_type(type_ref, models):
    kind = type_ref.get("kind", "")
    name = type_ref.get("name", "")
    if kind == "scalar": return SAMPLE_VALUES.get(name, None)
    elif kind == "named":
        m = find_model_by_name(models, name)
        if m is None: return {}
        if m.get("kind") == "enum":
            mems = m.get("members", [])
            return mems[0][1] if mems else "unknown"
        elif m.get("kind") == "struct": return sample_struct_data(m, models)
        return {}
    elif kind == "array":
        item = type_ref.get("item", {})
        iv = sample_value_for_type(item, models)
        return [iv] if iv is not None else []
    return None

def sample_struct_data(model, models):
    result = {}
    for field in model.get("fields", []):
        wire = field["wire_name"]
        req = field.get("required", False)
        null = field.get("nullable", False)
        pres = field.get("presence", "optional")
        if pres in ("required", "required_nullable"):
            result[wire] = sample_value_for_type(field["type"], models)
        elif pres == "optional" and not null:
            if field["type"].get("kind") == "scalar":
                result[wire] = sample_value_for_type(field["type"], models)
        elif pres == "optional_nullable":
            if field["type"].get("kind") == "scalar":
                result[wire] = sample_value_for_type(field["type"], models)
    return result

def find_model_by_name(models, name):
    for m in models:
        if m.get("name") == name: return m
    return None
