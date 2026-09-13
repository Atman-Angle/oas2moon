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


def run_moonbit(fixture: Path, out: Path):
    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["moon", "run", ".", "--target", "native", "--", str(fixture.resolve()), str(out.resolve())],
        cwd=ROOT / "src" / "core_moonbit",
        check=True,
    )
    return json.loads(out.read_text(encoding="utf-8"))


def test_python_vs_moonbit_targeted_differential_corpus(tmp_path):
    cases = [
        ("petstore-json", BASE),
        ("petstore-yaml", FIXTURES / "petstore-yaml.normalized.json"),
        ("auth-security", BASE),
        ("request-body", BASE),
        ("int64", BASE),
        ("enum-local-ref", BASE),
        ("naming-collision", FIXTURES / "targeted-collision.normalized.json"),
        ("reserved-words", FIXTURES / "targeted-reserved.normalized.json"),
        ("multiple-response-status", FIXTURES / "targeted-multi.normalized.json"),
    ]
    results = []
    for name, fixture in cases:
        _, report, api = pipeline.normalize_to_ir(fixture, "oas2moon/petstore")
        assert report.ok, name
        moon = run_moonbit(fixture, OUTPUT_ROOT / ("diff-targeted-" + name + ".json"))
        results.append(json.loads(api.canonical_json()) == moon)
    summary = {
        "cases_total": len(results),
        "cases_equal": sum(results),
        "cases_failed": len(results) - sum(results),
    }
    assert summary == {"cases_total": 9, "cases_equal": 9, "cases_failed": 0}


def test_unsupported_oneof_negative_path():
    fixture = FIXTURES / "unsupported-oneof.normalized.json"
    _, report, api = pipeline.normalize_to_ir(fixture, "oas2moon/petstore")
    assert not report.ok and api is None