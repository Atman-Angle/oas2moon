"""T13: determinism and regression hardening.

The generator must be a pure function of *spec bytes* plus normalized config:
the same OpenAPI document must always produce the same file list, the same file
bytes, the same canonical IR, stable import order, stable diagnostics and no
timestamps, random ids or machine paths.

The comparisons here are deliberately raw. Sorting lines, dropping volatile
fields or normalizing whitespace would hide exactly the nondeterminism this
task exists to remove, so it is never done.
"""

from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path

import pytest

from test_t10_cli import FIXTURES_DIR, ROOT, run_cli

OUTPUT_ROOT = ROOT / "tests" / "_build" / "t13-determinism"
FRONTEND_DIR = ROOT / "src" / "frontend_adapter"
CORE_DIR = ROOT / "src" / "core_moonbit"
CODEGEN_DIR = ROOT / "src" / "codegen_moonbit"
ADAPTER_TIMEOUT = 180

# ── corpora ────────────────────────────────────────────────────────

#: Documents the CLI supports end to end: real OpenAPI JSON/YAML inputs plus
#: the negative fixtures whose diagnostics must also be deterministic.
SPEC_CORPUS: list[Path] = [
    FIXTURES_DIR / "petstore" / "openapi.json",
    FIXTURES_DIR / "petstore" / "openapi.yaml",
    FIXTURES_DIR / "petstore" / "openapi_crud.json",
    FIXTURES_DIR / "auth" / "anonymous.json",
    FIXTURES_DIR / "auth" / "api-key-header.json",
    FIXTURES_DIR / "auth" / "api-key-query.json",
    FIXTURES_DIR / "auth" / "basic.json",
    FIXTURES_DIR / "auth" / "bearer.json",
    FIXTURES_DIR / "unsupported" / "oneof.json",
    FIXTURES_DIR / "regression" / "scan_false_positive_input.json",
]

#: Canonical Client IR fixtures consumed directly by the codegen backend. They
#: cover model shapes (enums, additionalProperties, collisions, Int64) that the
#: end-to-end corpus does not reach.
IR_CORPUS: list[Path] = sorted((FIXTURES_DIR / "phase2").glob("*.json"))

#: Files the codegen backend always emits for a canonical IR document.
IR_FILE_SET: list[str] = ["models.mbt", "moon.mod", "moon.pkg"]


def ir_file_set_for(fixture: Path) -> list[str]:
    """`client.mbt` exists only when the IR declares at least one operation."""
    api = json.loads(fixture.read_text(encoding="utf-8"))
    files = list(IR_FILE_SET)
    if api.get("operations"):
        files.append("client.mbt")
    return sorted(files)


#: The fixed generated-package layout contract (see docs/EVIDENCE_MATRIX.md).
SDK_FILE_SET: list[str] = [
    "client.mbt",
    "config.mbt",
    "encoding.mbt",
    "http_transport.mbt",
    "models.mbt",
    "runtime.mbt",
]
META_FILE_SET: list[str] = ["moon.mod", "moon.pkg"]

#: Specs whose JSON object key order is shuffled, to prove no stage leaks map
#: iteration into the output. JSON is the authoritative input format; YAML is
#: covered by the end-to-end corpus and normalizes to the same raw tree.
REORDERED_SPECS: list[Path] = [
    FIXTURES_DIR / "petstore" / "openapi.json",
    FIXTURES_DIR / "auth" / "api-key-query.json",
    FIXTURES_DIR / "unsupported" / "oneof.json",
]

#: Negatives that record findings into the normalized Frontend Model.
DIAGNOSTIC_SPECS: list[Path] = [
    FIXTURES_DIR / "unsupported" / "oneof.json",
    FIXTURES_DIR / "regression" / "scan_false_positive_input.json",
    FIXTURES_DIR / "petstore" / "openapi.json",
]

_SPEC_IDS = [f"{p.parent.name}/{p.name}" for p in SPEC_CORPUS]
_IR_IDS = [p.name for p in IR_CORPUS]
_REORDERED_IDS = [f"{p.parent.name}/{p.name}" for p in REORDERED_SPECS]
_DIAGNOSTIC_IDS = [f"{p.parent.name}/{p.name}" for p in DIAGNOSTIC_SPECS]


def fixture_id(path: Path) -> str:
    return f"{path.parent.name}/{path.name}"


def safe_name(path: Path) -> str:
    return fixture_id(path).replace("/", "-")


# ── artifact helpers ───────────────────────────────────────────────


def fresh_dir(*parts: str) -> Path:
    """Return an empty output directory under the T13 build root."""
    import shutil

    path = OUTPUT_ROOT.joinpath(*parts)
    if path.exists():
        shutil.rmtree(str(path))
    path.mkdir(parents=True, exist_ok=True)
    return path


def relative_files(root: Path) -> list[str]:
    """Every generated file, sorted, excluding build/registry scratch."""
    out: list[str] = []
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(root).as_posix()
        if rel.startswith("_build/") or rel.startswith(".mooncakes/"):
            continue
        out.append(rel)
    return sorted(out)


def relative_bytes(root: Path) -> dict[str, bytes]:
    return {rel: (root / rel).read_bytes() for rel in relative_files(root)}


def assert_artifacts_identical(
    out_a: Path, out_b: Path, label: str, expected_files: list[str] | None = None
) -> None:
    """Byte-for-byte comparison of two generated artifact trees."""
    files_a = relative_files(out_a)
    files_b = relative_files(out_b)
    assert files_a == files_b, (
        f"{label}: file lists differ\n"
        f"  only in A: {set(files_a) - set(files_b)}\n"
        f"  only in B: {set(files_b) - set(files_a)}"
    )
    if expected_files is not None:
        assert files_a == expected_files, (
            f"{label}: generated file set changed\n"
            f"  missing: {set(expected_files) - set(files_a)}\n"
            f"  unexpected: {set(files_a) - set(expected_files)}"
        )
    bytes_a = relative_bytes(out_a)
    bytes_b = relative_bytes(out_b)
    differing = [rel for rel in files_a if bytes_a[rel] != bytes_b[rel]]
    assert not differing, f"{label}: files differ between runs: {differing}"


def module_name_for(spec: Path) -> str:
    """A stable, valid MoonBit module name derived from the fixture path."""
    cleaned = re.sub(r"[^0-9a-zA-Z_]", "_", f"{spec.parent.name}_{spec.stem}")
    if not cleaned[0].isalpha() and cleaned[0] != "_":
        cleaned = "m" + cleaned
    return cleaned


def package_root_for(out_dir: Path) -> Path:
    """Walk up from a generated directory until the package root is found."""
    for candidate in (out_dir, *out_dir.parents):
        if (candidate / "moon.pkg").is_file():
            return candidate
    raise AssertionError(f"no moon.pkg found at or above {out_dir}")


# ── contract helpers ───────────────────────────────────────────────


def method_rank(method: str) -> int:
    return {"DELETE": 0, "GET": 1, "POST": 2, "PUT": 3, "PATCH": 4}.get(method, 9)


def shortlex_order(value: str) -> tuple[int, str]:
    """The comparator the generator actually sorts canonical keys with.

    MoonBit's ``String`` ``Compare`` impl is *shortlex* (shorter strings first,
    then UTF-16 code-unit order), not UTF-8 bytewise order. See
    ``docs/DECISIONS.md`` §10. Plain ``sorted()`` is codepoint order and
    disagrees with shortlex on inputs such as ``"b"`` vs ``"aa"``, so the
    canonical-order contract must be checked with this key.
    """
    return (len(value), value)


def assert_ir_ordering(ir: dict, label: str) -> None:
    """Canonical IR collections must be in their documented canonical order."""
    models = ir["models"]
    names = [m["name"] for m in models]
    kinds = [m["kind"] for m in models]
    assert kinds == sorted(kinds, key=lambda k: 0 if k == "enum" else 1), (
        f"{label}: enums must precede structs: {list(zip(names, kinds))}"
    )
    enum_names = [n for n, k in zip(names, kinds) if k == "enum"]
    struct_names = [n for n, k in zip(names, kinds) if k != "enum"]
    assert enum_names == sorted(enum_names, key=shortlex_order), (
        f"{label}: enum models are not sorted by name: {enum_names}"
    )
    assert struct_names == sorted(struct_names, key=shortlex_order), (
        f"{label}: struct models are not sorted by name: {struct_names}"
    )

    operations = ir["operations"]
    op_keys = [
        (op["path"], method_rank(op["http_method"]), op["operation_id"])
        for op in operations
    ]
    assert op_keys == sorted(
        op_keys,
        key=lambda k: (shortlex_order(k[0]), k[1], shortlex_order(k[2])),
    ), f"{label}: operations are not in canonical order: {op_keys}"

    schemes = [s["name"] for s in ir["auth_schemes"]]
    assert schemes == sorted(schemes, key=shortlex_order), (
        f"{label}: auth schemes are not sorted by name: {schemes}"
    )

    for model in models:
        if model["kind"] != "struct":
            continue
        fields = model["fields"]
        required = [f for f in fields if f["presence"].startswith("required")]
        optional = [f for f in fields if not f["presence"].startswith("required")]
        assert fields == required + optional, (
            f"{label}: {model['name']} interleaves required/optional fields"
        )
        wire_names = [f["wire_name"] for f in fields]
        assert len(wire_names) == len(set(wire_names)), (
            f"{label}: {model['name']} has duplicate wire names: {wire_names}"
        )


#: Relative import order the package emitter guarantees. An emitted block must
#: be a subsequence of this order: fixed for a given IR, never machine
#: dependent. It is not alphabetical on purpose (core before async runtime).
_PKG_IMPORT_ORDER = [
    "moonbitlang/core/json",
    "moonbitlang/core/encoding/utf8",
    "moonbitlang/async/http",
    "moonbitlang/async/io",
    "moonbitlang/async",
    "moonbitlang/core/string",
]


def assert_imports_are_stable(out_dir: Path, label: str) -> None:
    """`moon.pkg` must declare imports in one fixed, non-machine-dependent order."""
    pkg_dir = package_root_for(out_dir)
    text = (pkg_dir / "moon.pkg").read_text(encoding="utf-8")
    match = re.search(r"import\s*\{(?P<body>.*?)\}", text, re.DOTALL)
    assert match is not None, f"{label}: moon.pkg has no import block:\n{text}"
    imports = re.findall(r'"([^"]+)"', match.group("body"))
    assert imports, f"{label}: moon.pkg import block is empty"
    assert len(imports) == len(set(imports)), (
        f"{label}: moon.pkg has duplicate imports: {imports}"
    )
    indices = []
    for name in imports:
        assert name in _PKG_IMPORT_ORDER, (
            f"{label}: unexpected import {name!r}; extend _PKG_IMPORT_ORDER "
            f"deliberately if this is intended"
        )
        indices.append(_PKG_IMPORT_ORDER.index(name))
    assert indices == sorted(indices), (
        f"{label}: moon.pkg imports are out of the fixed order: {imports}"
    )


#: A pure hex digest / UUID / generated scratch name is never part of a stable
#: contract and must never reach an emitted artifact.
_RANDOM_ID = re.compile(
    r"[0-9a-f]{32}"
    r"|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
    r"|\bgenerate-\d+"
)
#: ``a:/``/``e:/`` inside ordinary words such as ``"type":`` are not drives, so
#: a drive letter must be followed by a backslash or a lowercase path segment.
_ABS_PATH = re.compile(
    r"(?:^|[^A-Za-z0-9_])[A-Za-z]:\\"
    r"|(?:^|[^A-Za-z0-9_])[A-Za-z]:/(?=[a-zA-Z_.~])"
    r"|(?<![\w:])/(?:home|Users|root|tmp|var|opt|mnt|private|workspace)/"
    r"|\\\\[A-Za-z0-9_.-]+\\"
)
_TIMESTAMP = re.compile(
    r"\b20[0-9]{2}-[0-9]{2}-[0-9]{2}[T ]"
    r"|\b1[6-9][0-9]{8}\b"
)

FORBIDDEN_PATTERNS = {
    "timestamp": _TIMESTAMP,
    "random_id": _RANDOM_ID,
    "absolute_path": _ABS_PATH,
    "generator_scratch_dir": re.compile(r"\bsrc[\\/]_work\b"),
}


def scan_forbidden(text: str, label: str) -> None:
    """Assert that emitted text contains no machine-specific or volatile value."""
    for name, pattern in FORBIDDEN_PATTERNS.items():
        for match in pattern.finditer(text):
            start = max(0, match.start() - 60)
            end = min(len(text), match.end() + 60)
            raise AssertionError(
                f"{label}: forbidden {name} {match.group(0)!r} in ..."
                f"{text[start:end]!r}..."
            )


def scan_tree(out_dir: Path, label: str) -> None:
    for rel in relative_files(out_dir):
        payload = (out_dir / rel).read_bytes()
        scan_forbidden(payload.decode("utf-8", errors="replace"), f"{label}:{rel}")


# ── end-to-end spec determinism ────────────────────────────────────


@pytest.mark.parametrize("spec", SPEC_CORPUS, ids=_SPEC_IDS)
def test_spec_generation_is_byte_deterministic(spec: Path) -> None:
    """Two generations of one spec must agree on file list, bytes and IR."""
    assert spec.is_file(), f"missing fixture: {spec}"
    module = module_name_for(spec)
    label = fixture_id(spec)
    stem = safe_name(spec)

    out_a = fresh_dir("spec", stem, "a")
    out_b = fresh_dir("spec", stem, "b")
    ir_a = out_a.parent / "ir-a.json"
    ir_b = out_b.parent / "ir-b.json"
    for stale in (ir_a, ir_b):
        if stale.exists():
            stale.unlink()

    first = run_cli(
        "generate", str(spec), "--module", module, "--out", str(out_a),
        "--ir-out", str(ir_a),
    )
    assert first.returncode == 0, f"{label}: generation 1 failed:\n{first.stderr}"
    second = run_cli(
        "generate", str(spec), "--module", module, "--out", str(out_b),
        "--ir-out", str(ir_b),
    )
    assert second.returncode == 0, f"{label}: generation 2 failed:\n{second.stderr}"

    assert_artifacts_identical(out_a, out_b, label)
    assert ir_a.read_bytes() == ir_b.read_bytes(), (
        f"{label}: canonical IR bytes differ between two generations"
    )
    ir = json.loads(ir_a.read_text(encoding="utf-8"))
    assert_ir_ordering(ir, label)
    assert_imports_are_stable(out_a, label)

    scan_tree(out_a, label)
    scan_forbidden(ir_a.read_text(encoding="utf-8"), f"{label}:canonical_ir.json")

    # The generation summary lists the output directory and the model count, so
    # only its stable fields are compared. Its per-file lines are the emitted SDK
    # sources in sorted order and must match the fixed layout contract.
    summary_files = [
        line.strip()
        for line in first.stderr.splitlines()
        if line.startswith("    ") and line.strip()
    ]
    assert summary_files == sorted(summary_files), (
        f"{label}: CLI summary does not list files in sorted order: {summary_files}"
    )
    assert summary_files == SDK_FILE_SET, (
        f"{label}: CLI summary file list does not match the fixed layout: "
        f"{summary_files}"
    )
    assert set(relative_files(out_a)) == set(SDK_FILE_SET) | set(META_FILE_SET), (
        f"{label}: generated tree is not the fixed layout: {relative_files(out_a)}"
    )




# ── canonical IR codegen determinism ───────────────────────────────


@pytest.mark.parametrize("fixture", IR_CORPUS, ids=_IR_IDS)
def test_codegen_is_byte_deterministic(fixture: Path) -> None:
    """The codegen backend is a pure function of canonical IR bytes."""
    assert fixture.is_file(), f"missing fixture: {fixture}"
    label = f"phase2/{fixture.name}"

    def generate(out_dir: Path) -> None:
        result = subprocess.run(
            [
                "moon", "run", ".", "--target", "native", "--",
                str(fixture), str(out_dir),
            ],
            cwd=str(CODEGEN_DIR),
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=ADAPTER_TIMEOUT,
        )
        assert result.returncode == 0, (
            f"{label}: codegen failed\n{result.stdout}\n{result.stderr}"
        )

    out_a = fresh_dir("ir", fixture.stem, "a", "sdk")
    out_b = fresh_dir("ir", fixture.stem, "b", "sdk")
    generate(out_a)
    generate(out_b)

    assert_artifacts_identical(
        out_a, out_b, label, expected_files=ir_file_set_for(fixture)
    )
    assert_imports_are_stable(out_a, label)
    scan_tree(out_a, label)





# ── map-iteration hardening ────────────────────────────────────────


def reorder_json_keys(value: object) -> object:
    """Reverse every JSON object's key order, leaving arrays untouched."""
    if isinstance(value, dict):
        return {key: reorder_json_keys(value[key]) for key in reversed(list(value))}
    if isinstance(value, list):
        return [reorder_json_keys(item) for item in value]
    return value


def write_reordered_json(source: Path, target: Path) -> None:
    data = json.loads(source.read_text(encoding="utf-8"))
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(
        json.dumps(reorder_json_keys(data), indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


@pytest.mark.parametrize("spec", REORDERED_SPECS, ids=_REORDERED_IDS)
def test_object_key_order_does_not_change_output(spec: Path) -> None:
    """JSON object key order carries no meaning and must not reach the output.

    The same document with every object's keys reversed must still produce
    byte-identical artifacts. A failure means some stage drives its output from
    map/filesystem iteration order instead of a canonical sort.
    """
    assert spec.is_file(), f"missing fixture: {spec}"
    assert spec.suffix == ".json", f"reorder cases must be JSON: {spec}"
    module = module_name_for(spec)
    label = fixture_id(spec)
    stem = safe_name(spec)

    reordered = OUTPUT_ROOT / "reordered-input" / stem / "reordered.json"
    write_reordered_json(spec, reordered)

    out_original = fresh_dir("reordered", stem, "original")
    out_reordered = fresh_dir("reordered", stem, "reordered")
    ir_original = out_original.parent / "ir-original.json"
    ir_reordered = out_reordered.parent / "ir-reordered.json"

    first = run_cli(
        "generate", str(spec), "--module", module, "--out", str(out_original),
        "--ir-out", str(ir_original),
    )
    assert first.returncode == 0, f"{label}: original generation failed:\n{first.stderr}"
    second = run_cli(
        "generate", str(reordered), "--module", module, "--out", str(out_reordered),
        "--ir-out", str(ir_reordered),
    )
    assert second.returncode == 0, (
        f"{label}: reordered generation failed:\n{second.stderr}"
    )

    assert_artifacts_identical(out_original, out_reordered, f"{label} (reordered)")
    assert ir_original.read_bytes() == ir_reordered.read_bytes(), (
        f"{label}: object key order changed the canonical IR"
    )


# ── diagnostics ordering ───────────────────────────────────────────


@pytest.mark.parametrize("spec", DIAGNOSTIC_SPECS, ids=_DIAGNOSTIC_IDS)
def test_diagnostics_are_ordered_and_deterministic(spec: Path) -> None:
    """Recorded findings must be in location order and repeat byte-for-byte."""
    assert spec.is_file(), f"missing fixture: {spec}"
    out_dir = fresh_dir("diagnostics", safe_name(spec))

    runs: list[bytes] = []
    for run in ("a", "b"):
        target = out_dir / f"{run}.json"
        completed = subprocess.run(
            [
                "moon", "run", ".", "--target", "native", "--",
                str(spec), str(target),
            ],
            cwd=str(FRONTEND_DIR),
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=ADAPTER_TIMEOUT,
        )
        assert completed.returncode == 0, (
            f"{spec.name}: frontend adapter failed\n"
            f"{completed.stdout}\n{completed.stderr}"
        )
        assert target.is_file(), f"{spec.name}: adapter wrote no output"
        runs.append(target.read_bytes())

    assert runs[0] == runs[1], (
        f"{spec.name}: normalized Frontend Model is not byte-deterministic"
    )
    model = json.loads(runs[0].decode("utf-8"))

    for group in ("issues", "ignored"):
        findings = model.get(group, [])
        pointers = [entry["pointer"] for entry in findings]
        assert pointers == sorted(pointers), (
            f"{spec.name}: {group} are not in location order: {pointers}"
        )
        for entry in findings:
            pointer = entry["pointer"]
            assert pointer.startswith("#/"), (
                f"{spec.name}: {group} pointer is not a JSON pointer: {pointer}"
            )
            assert "\\" not in pointer, (
                f"{spec.name}: {group} pointer uses a Windows separator: {pointer}"
            )
            assert not pointer.startswith("//"), (
                f"{spec.name}: {group} pointer looks like a UNC path: {pointer}"
            )
            scan_forbidden(json.dumps(entry), f"{spec.name}:{group}")

    # The regression fixture deliberately embeds `oneOf` inside an `example`
    # value. Findings are location-only and must not descend into example data.
    if spec.name == "scan_false_positive_input.json":
        assert model["issues"] == [], (
            "scan descended into example data and produced a false positive: "
            f"{model['issues']}"
        )


# ── IR ordering is independent of upstream key order ───────────────


def run_moon_package(package_dir: Path, *args: str) -> subprocess.CompletedProcess:
    """Run one MoonBit pipeline stage in place and capture its text output."""
    return subprocess.run(
        ["moon", "run", ".", "--target", "native", "--", *args],
        cwd=str(package_dir),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=ADAPTER_TIMEOUT,
    )


@pytest.mark.parametrize("spec", REORDERED_SPECS, ids=_REORDERED_IDS)
def test_ir_ordering_is_independent_of_normalized_key_order(spec: Path) -> None:
    """The IR builder must canonicalize its own input, not inherit its order.

    The normalized Frontend Model is JSON, so the key order of its objects
    carries no meaning. Lowering the same model with every object's keys
    reversed must still produce byte-identical canonical IR. A failure means
    ``lower`` walks an unordered map directly, so the canonical order of struct
    fields or auth schemes would be inherited from whatever key order the
    upstream stage happened to emit instead of from the IR contract.
    """
    assert spec.is_file(), f"missing fixture: {spec}"
    label = fixture_id(spec)
    module = module_name_for(spec)
    work = fresh_dir("ir-order", safe_name(spec))

    normalized = work / "normalized.json"
    adapter = run_moon_package(FRONTEND_DIR, str(spec), str(normalized))
    assert adapter.returncode == 0, (
        f"{label}: frontend adapter failed\n{adapter.stdout}\n{adapter.stderr}"
    )
    assert normalized.is_file(), f"{label}: adapter wrote no normalized model"

    reversed_model = work / "normalized-reversed.json"
    write_reordered_json(normalized, reversed_model)
    assert reversed_model.read_bytes() != normalized.read_bytes(), (
        f"{label}: key reversal produced an identical file, so the probe is "
        f"vacuous"
    )

    ir_original = work / "ir-original.json"
    ir_reversed = work / "ir-reversed.json"
    for source, target in ((normalized, ir_original), (reversed_model, ir_reversed)):
        lowered = run_moon_package(CORE_DIR, str(source), str(target), module)
        assert lowered.returncode == 0, (
            f"{label}: core IR builder failed on {source.name}\n"
            f"{lowered.stdout}\n{lowered.stderr}"
        )
        assert target.is_file(), f"{label}: core wrote no IR for {source.name}"

    assert ir_original.read_bytes() == ir_reversed.read_bytes(), (
        f"{label}: normalized-model key order changed the canonical IR"
    )
