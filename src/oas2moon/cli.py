"""oas2moon CLI — generate command.

Usage:
  oas2moon generate <input> --module <module> --out <directory>

Runs the full pipeline:
  1. Frontend adapter (MoonBit) — parse OpenAPI → normalized Frontend Model
  2. IR builder (MoonBit) — normalized model → canonical Client IR
  3. Codegen (MoonBit) — canonical IR → MoonBit SDK files
  4. Runtime files are copied to the output
  5. moon fmt is run on the generated package

Exit codes:
  0  Success
  1  Input file not found
  2  Invalid module name
  3  Frontend adapter error (invalid/unparseable spec)
  4  Unsupported spec features (diagnostics emitted)
  5  Codegen pipeline failure
  6  Output path is a file, not a directory
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

# ── paths relative to this file (project root) ──────────────────────
_HERE = Path(__file__).resolve().parent
_PROJECT_ROOT = _HERE.parent.parent  # src/oas2moon/__init__.py -> src/ -> project root

_FRONTEND_DIR = _PROJECT_ROOT / "src" / "frontend_adapter"
_CORE_DIR = _PROJECT_ROOT / "src" / "core_moonbit"
_CODEGEN_DIR = _PROJECT_ROOT / "src" / "codegen_moonbit"
_RUNTIME_DIR = _PROJECT_ROOT / "src" / "runtime_moonbit"

_MBT_MODULE_RE = re.compile(r"^[a-zA-Z_][a-zA-Z0-9_]*(\/[a-zA-Z_][a-zA-Z0-9_]*)*$")


def _module_ok(name: str) -> bool:
    """Validate a MoonBit module name (e.g. ``petstore`` or ``oas2moon/petstore``)."""
    return bool(_MBT_MODULE_RE.match(name)) and "//" not in name


def _run(cmd: list[str], cwd: str | Path, timeout: int = 120) -> subprocess.CompletedProcess:
    """Run a command, handling non-UTF-8 output gracefully."""
    try:
        r = subprocess.run(
            cmd,
            cwd=str(cwd),
            capture_output=True,
            timeout=timeout,
        )
        # Decode manually with error replacement
        stdout = r.stdout.decode("utf-8", errors="replace") if r.stdout else ""
        stderr = r.stderr.decode("utf-8", errors="replace") if r.stderr else ""
        return subprocess.CompletedProcess(
            cmd, r.returncode, stdout, stderr,
        )
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(
            cmd, -1, "", f"timeout after {timeout}s",
        )


def _moon_run(cwd: Path, *args: str, timeout: int = 120) -> subprocess.CompletedProcess:
    """Run the current MoonBit package at *cwd* with *args*."""
    cmd = ["moon", "run", ".", "--target", "native", "--", *args]
    return _run(cmd, cwd, timeout=timeout)


def _moon_fmt(cwd: Path) -> subprocess.CompletedProcess:
    return _run(["moon", "fmt"], cwd)


def _moon_fmt_check(cwd: Path) -> subprocess.CompletedProcess:
    return _run(["moon", "fmt", "--check"], cwd)


# ── Runtime files to copy into generated packages ──────────────────
_RUNTIME_FILES = [
    "runtime.mbt",
    "config.mbt",
    "encoding.mbt",
    "http_transport.mbt",
]

_RUNTIME_PKG = """import {
  "moonbitlang/core/encoding/utf8",
  "moonbitlang/core/json",
  "moonbitlang/core/string",
}

supported_targets = "+native"
"""


def _copy_runtime_files(out_dir: Path) -> None:
    """Copy runtime MBT sources into the generated output directory."""
    for name in _RUNTIME_FILES:
        src = _RUNTIME_DIR / name
        if src.is_file():
            shutil.copy2(str(src), str(out_dir / name))


def _write_moon_pkg(out_dir: Path) -> None:
    """Write the moon.pkg with appropriate imports."""
    (out_dir / "moon.pkg").write_text(_RUNTIME_PKG, encoding="utf-8")


def _write_moon_mod(out_dir: Path, module_name: str) -> None:
    """Write moon.mod for the generated package."""
    content = (
        f'name = "{module_name}"\n'
        f'\n'
        f'version = "0.1.0"\n'
        f'\n'
        f'preferred_target = "native"\n'
    )
    (out_dir / "moon.mod").write_text(content, encoding="utf-8")


def _detect_input_format(path: Path) -> str | None:
    """Return ``json`` or ``yaml`` based on the file extension."""
    suffix = path.suffix.lower()
    if suffix in (".json",):
        return "json"
    if suffix in (".yaml", ".yml"):
        return "yaml"
    return None


def _step_label(step: str, ok: bool) -> str:
    return f"  {'✓' if ok else '✗'} {step}"


def _fetch_output(r: subprocess.CompletedProcess) -> str:
    """Get combined output, handling None gracefully."""
    parts = []
    if r.stdout:
        parts.append(r.stdout)
    if r.stderr:
        parts.append(r.stderr)
    return "\n".join(parts)


# ═══════════════════════════════════════════════════════════════════
#  generate command
# ═══════════════════════════════════════════════════════════════════


def cmd_generate(args: argparse.Namespace) -> int:
    """Execute ``oas2moon generate``."""
    # Resolve against the caller's cwd: the MoonBit stages run with their own
    # working directory, so a relative path would not survive the hand-off.
    input_path = Path(args.input).resolve()
    if not input_path.is_file():
        print(f"error: input file does not exist: {input_path}", file=sys.stderr)
        return 1

    fmt = _detect_input_format(input_path)
    if fmt is None:
        print(
            f"error: unsupported input format; expected .json, .yaml, or .yml, "
            f"got {input_path.suffix}",
            file=sys.stderr,
        )
        return 1

    module_name = args.module
    if not _module_ok(module_name):
        print(
            f"error: invalid MoonBit module name {module_name!r}; "
            f"use a valid identifier like 'petstore' or 'my_org/petstore'",
            file=sys.stderr,
        )
        return 2

    # Same reasoning as the input path: every MoonBit stage runs with its own
    # working directory, so the output path must be absolute before hand-off.
    out_dir = Path(args.out).resolve()
    if out_dir.exists() and not out_dir.is_dir():
        print(f"error: output path is not a directory: {out_dir}", file=sys.stderr)
        return 6

    # Use a work directory under the project's _build to avoid
    # system temp paths that may contain non-ASCII characters
    # which can cause issues with MoonBit's filesystem library.
    work_dir = _PROJECT_ROOT / "src" / "_work" / "generate"
    work_dir.mkdir(parents=True, exist_ok=True)

    normalized_path = work_dir / "normalized.json"
    canonical_path = work_dir / "canonical.json"

    # ── Step 1: Frontend adapter ────────────────────────────
    step = "frontend: parse OpenAPI → normalized model"
    r1 = _moon_run(_FRONTEND_DIR, str(input_path), str(normalized_path))
    if r1.returncode != 0 or not normalized_path.is_file():
        detail = _fetch_output(r1)
        if detail:
            print(detail, file=sys.stderr)
        print(_step_label(step, False), file=sys.stderr)
        return 3
    normalized_size = normalized_path.stat().st_size
    print(_step_label(step, True), file=sys.stderr)

    # ── Step 2: IR builder ──────────────────────────────────
    step = "core: normalized model → canonical IR"
    r2 = _moon_run(
        _CORE_DIR, str(normalized_path), str(canonical_path), module_name,
    )
    if r2.returncode != 0 or not canonical_path.is_file():
        detail = _fetch_output(r2)
        if detail:
            print(detail, file=sys.stderr)
        print(_step_label(step, False), file=sys.stderr)
        return 5
    canonical_size = canonical_path.stat().st_size
    print(_step_label(step, True), file=sys.stderr)

    if getattr(args, "ir_out", None):
        ir_target = Path(args.ir_out).resolve()
        ir_target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(str(canonical_path), str(ir_target))

    # ── Load canonical IR for inspection ────────────────────
    try:
        api: dict[str, Any] = json.loads(canonical_path.read_text(encoding="utf-8"))
    except Exception as exc:
        print(f"error: failed to parse canonical IR: {exc}", file=sys.stderr)
        return 5

    # ── Step 3: Codegen ─────────────────────────────────────
    step = "codegen: canonical IR → MoonBit SDK"
    out_dir.mkdir(parents=True, exist_ok=True)
    r3 = _moon_run(_CODEGEN_DIR, str(canonical_path), str(out_dir))
    if r3.returncode != 0:
        detail = _fetch_output(r3)
        if detail:
            print(detail, file=sys.stderr)
        print(_step_label(step, False), file=sys.stderr)
        return 5
    print(_step_label(step, True), file=sys.stderr)

    # ── Step 4: Copy runtime files ──────────────────────────
    step = "runtime: copy runtime sources"
    _copy_runtime_files(out_dir)
    print(_step_label(step, True), file=sys.stderr)

    # ── Step 5: moon fmt ────────────────────────────────────
    step = "moon fmt"
    r4 = _moon_fmt(out_dir)
    if r4.returncode != 0:
        detail = _fetch_output(r4)
        if detail:
            print(detail, file=sys.stderr)
        print(_step_label(step, False), file=sys.stderr)
        return 5
    print(_step_label(step, True), file=sys.stderr)

    # ── Clean up work dir ──────────────────────────────────
    if work_dir.exists():
        shutil.rmtree(str(work_dir), ignore_errors=True)

    # ── Summary ─────────────────────────────────────────────
    _print_summary(
        api,
        out_dir=out_dir,
        normalized_size=normalized_size,
        canonical_size=canonical_size,
    )

    return 0


def _print_summary(
    api: dict,
    out_dir: Path,
    normalized_size: int,
    canonical_size: int,
) -> None:
    """Print a human-readable generation summary to stdout."""
    models = api.get("models", [])
    operations = api.get("operations", [])
    op_count = len(operations)
    model_count = len(models)

    # Count generated files (excluding build artifacts)
    gen_files: list[str] = []
    for p in sorted(out_dir.rglob("*")):
        if not p.is_file():
            continue
        rel = str(p.relative_to(out_dir)).replace("\\", "/")
        if rel.startswith("_build/") or rel.startswith(".mooncakes/"):
            continue
        gen_files.append(rel)

    print(file=sys.stderr)
    print("=" * 48, file=sys.stderr)
    print("  oas2moon generate — summary", file=sys.stderr)
    print("=" * 48, file=sys.stderr)
    print(f"  Module      : {api.get('module', '?')}", file=sys.stderr)
    print(f"  Output dir  : {out_dir.resolve()}", file=sys.stderr)
    print(f"  Models      : {model_count}", file=sys.stderr)
    print(f"  Operations  : {op_count}", file=sys.stderr)
    print(f"  Files       : {len(gen_files)}", file=sys.stderr)
    for f in gen_files:
        if f not in ("moon.mod", "moon.pkg", "canonical_ir.json"):
            print(f"    {f}", file=sys.stderr)
    print(f"  IR size     : {normalized_size} B normalized, {canonical_size} B canonical", file=sys.stderr)
    print("=" * 48, file=sys.stderr)


# ═══════════════════════════════════════════════════════════════════
#  entry point
# ═══════════════════════════════════════════════════════════════════


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="oas2moon",
        description="OpenAPI 3.0.x → typed MoonBit client SDK generator.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    gen = sub.add_parser("generate", help="Generate a MoonBit SDK from an OpenAPI spec")
    gen.add_argument("input", help="Path to the OpenAPI spec file (.json / .yaml / .yml)")
    gen.add_argument("--module", required=True, help="MoonBit module name (e.g. 'petstore')")
    gen.add_argument("--out", "-o", required=True, help="Output directory for the generated package")
    gen.add_argument(
        "--ir-out",
        default=None,
        help="Also write the canonical Client IR to this path (useful for tooling and review)",
    )

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.command == "generate":
        return cmd_generate(args)

    parser.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())