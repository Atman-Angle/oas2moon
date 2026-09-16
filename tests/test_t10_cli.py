"""T10: CLI generate — integration tests.

Tests the ``oas2moon generate`` command end-to-end, covering:

- successful generation from JSON and YAML
- nonexistent input
- invalid module name
- unsupported spec (oneOf)
- repeated generation (determinism)
- compiled output (moon fmt + moon check)
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLI_SCRIPT = ROOT / "oas2moon.py"
FIXTURES_DIR = ROOT / "fixtures"
OUTPUT_ROOT = ROOT / "tests" / "_build" / "t10-cli"

SKIP_CHECK = os.environ.get("SKIP_MOON_CHECK", "0") == "1"


def run_cli(*args: str) -> subprocess.CompletedProcess:
    """Run the oas2moon CLI with the given arguments."""
    return subprocess.run(
        [sys.executable, str(CLI_SCRIPT), *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=120,
    )


def moon_fmt_check(pkg_dir: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["moon", "fmt", "--check"],
        cwd=str(pkg_dir),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )


def moon_check(pkg_dir: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["moon", "check", "--target", "native", "--deny-warn"],
        cwd=str(pkg_dir),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )


def get_file_hashes(pkg_dir: Path) -> dict[str, str]:
    """Return a dict of relative path → sha256 hash, excluding build artifacts."""
    result: dict[str, str] = {}
    for p in sorted(pkg_dir.rglob("*")):
        if not p.is_file():
            continue
        rel = str(p.relative_to(pkg_dir))
        if rel.startswith("_build") or ".mooncakes" in rel:
            continue
        result[rel] = hashlib.sha256(p.read_bytes()).hexdigest()
    return result


# ═══════════════════════════════════════════════════════════════════
#  Tests
# ═══════════════════════════════════════════════════════════════════


def _out(name: str) -> Path:
    p = OUTPUT_ROOT / name
    if p.exists():
        shutil.rmtree(str(p))
    return p


def test_input_not_found() -> None:
    r = run_cli("generate", "nonexistent.json", "--module", "x", "--out", str(_out("notfound")))
    assert r.returncode == 1, f"expected exit 1, got {r.returncode}"
    assert "does not exist" in r.stderr.lower()


def test_invalid_module() -> None:
    r = run_cli("generate", str(FIXTURES_DIR / "petstore" / "openapi.json"),
                "--module", "invalid!!", "--out", str(_out("badmodule")))
    assert r.returncode == 2, f"expected exit 2, got {r.returncode}"
    assert "invalid moonbit module name" in r.stderr.lower()


def test_success_json() -> None:
    out_dir = _out("success-json")
    r = run_cli("generate", str(FIXTURES_DIR / "petstore" / "openapi.json"),
                "--module", "petstore", "--out", str(out_dir))
    assert r.returncode == 0, f"CLI failed:\n{r.stderr}"
    # Check key output files exist
    assert (out_dir / "moon.mod").is_file()
    assert (out_dir / "moon.pkg").is_file()
    assert (out_dir / "models.mbt").is_file()
    assert (out_dir / "runtime.mbt").is_file()
    assert (out_dir / "config.mbt").is_file()
    assert (out_dir / "encoding.mbt").is_file()


def test_success_yaml() -> None:
    out_dir = _out("success-yaml")
    r = run_cli("generate", str(FIXTURES_DIR / "petstore" / "openapi.yaml"),
                "--module", "petstore", "--out", str(out_dir))
    assert r.returncode == 0, f"CLI failed:\n{r.stderr}"
    assert (out_dir / "models.mbt").is_file()


def test_unsupported_spec() -> None:
    """oneOf is unsupported; the CLI should still run without crashing."""
    out_dir = _out("unsupported")
    r = run_cli("generate", str(FIXTURES_DIR / "unsupported" / "oneof.json"),
                "--module", "test", "--out", str(out_dir))
    assert r.returncode == 0, f"CLI failed:\n{r.stderr}"
    assert (out_dir / "models.mbt").is_file()


def test_determinism() -> None:
    """Two consecutive runs must produce identical source files."""
    out_a = _out("det-a")
    out_b = _out("det-b")

    r1 = run_cli("generate", str(FIXTURES_DIR / "petstore" / "openapi.json"),
                 "--module", "petstore", "--out", str(out_a))
    assert r1.returncode == 0, f"Run 1 failed:\n{r1.stderr}"

    r2 = run_cli("generate", str(FIXTURES_DIR / "petstore" / "openapi.json"),
                 "--module", "petstore", "--out", str(out_b))
    assert r2.returncode == 0, f"Run 2 failed:\n{r2.stderr}"

    h1 = get_file_hashes(out_a)
    h2 = get_file_hashes(out_b)

    assert h1.keys() == h2.keys(), (
        f"File lists differ:\n"
        f"  only in A: {set(h1.keys()) - set(h2.keys())}\n"
        f"  only in B: {set(h2.keys()) - set(h1.keys())}"
    )

    for key in sorted(h1.keys()):
        assert h1[key] == h2[key], f"Content differs for {key}"


def test_compiled_output() -> None:
    """Generated package must pass moon fmt --check and moon check --deny-warn."""
    if SKIP_CHECK:
        return

    out_dir = _out("compiled")
    r = run_cli("generate", str(FIXTURES_DIR / "petstore" / "openapi.json"),
                "--module", "petstore", "--out", str(out_dir))
    assert r.returncode == 0, f"CLI failed:\n{r.stderr}"

    # moon fmt --check
    fmt_r = moon_fmt_check(out_dir)
    assert fmt_r.returncode == 0, (
        f"moon fmt --check failed:\n{fmt_r.stderr}"
    )

    # moon check --deny-warn
    check_r = moon_check(out_dir)
    assert check_r.returncode == 0, (
        f"moon check --deny-warn failed:\n{check_r.stderr[-2000:]}"
    )


if __name__ == "__main__":
    tests = [
        ("input not found", test_input_not_found),
        ("invalid module", test_invalid_module),
        ("success JSON", test_success_json),
        ("success YAML", test_success_yaml),
        ("unsupported spec", test_unsupported_spec),
        ("determinism", test_determinism),
        ("compiled output", test_compiled_output),
    ]
    failures = 0
    for name, fn in tests:
        print(f"  [{name}] ", end="", flush=True)
        try:
            fn()
            print("PASS")
        except Exception as e:
            print(f"FAIL: {e}")
            failures += 1

    print(f"\n{'='*48}")
    print(f"  {len(tests) - failures}/{len(tests)} passed")
    if failures:
        print(f"  {failures} FAILURES")
    sys.exit(1 if failures else 0)