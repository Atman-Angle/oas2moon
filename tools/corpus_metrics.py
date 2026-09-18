"""T12 corpus metrics.

Measures, per corpus spec, the numbers T12 has to publish:

* ``operations_total``      operations declared for that spec;
* ``operations_supported``  operations in specs that generated *and* compiled;
* ``operations_rejected``   ``operations_total - operations_supported``;
* ``rejection_reasons``     one entry per recorded unsupported keyword;
* ``compile_pass``          specs whose package passed ``moon fmt --check``
                            and ``moon check --target native --deny-warn``.

Metric definitions (deliberate — see ``corpus/README.md`` for the
provenance contract):

* ``operations_total`` is counted from the raw document for JSON specs (an
  independent stdlib-only count) and cross-checked against the number of
  operations the frontend modeled. YAML specs fall back to the modeled count
  and record ``operations_total_source: "modeled"``, because the repo does not
  depend on a Python YAML parser.
* ``operations_dropped`` is ``total - modeled``: operations the adapter never
  produced IR for. These are reported, never hidden, and count as rejected.
* V1 refuses a *spec*, not an operation, so a refused spec contributes 0
  supported operations. The report states that granularity instead of implying
  per-operation precision the pipeline does not have.

Output is deterministic: specs sort by id, JSON is sorted, and neither
timestamps nor absolute paths are written.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
FRONTEND_DIR = ROOT / "src" / "frontend_adapter"
CLI_SCRIPT = ROOT / "oas2moon.py"

HTTP_METHODS = frozenset(
    {"get", "put", "post", "delete", "options", "head", "patch", "trace"}
)
PATH_ITEM_NON_OPERATIONS = frozenset(
    {"parameters", "summary", "description", "servers", "$ref"}
)

#: Exit code the CLI uses for "unsupported OpenAPI contract".
EXIT_UNSUPPORTED = 4


def _run(
    cmd: list[str], cwd: Path | None = None, timeout: int = 900
) -> subprocess.CompletedProcess:
    """Run a helper process, decoding output leniently."""
    result = subprocess.run(
        [str(part) for part in cmd],
        cwd=None if cwd is None else str(cwd),
        capture_output=True,
        timeout=timeout,
    )
    return subprocess.CompletedProcess(
        cmd,
        result.returncode,
        result.stdout.decode("utf-8", errors="replace"),
        result.stderr.decode("utf-8", errors="replace"),
    )


def repo_relative(path: Path) -> str:
    """A repo-relative POSIX path, so reports never carry machine paths."""
    resolved = Path(path).resolve()
    try:
        return resolved.relative_to(ROOT).as_posix()
    except ValueError:
        return resolved.name


def module_name_for(spec_id: str) -> str:
    """A stable, valid MoonBit module name derived from the corpus id."""
    cleaned = re.sub(r"[^0-9a-zA-Z_]", "_", spec_id)
    if not cleaned or not (cleaned[0].isalpha() or cleaned[0] == "_"):
        cleaned = "m" + cleaned
    return cleaned


def raw_operation_count(path: Path) -> int | None:
    """Count ``paths.<path>.<method>`` in a JSON document, or ``None``.

    Only JSON is counted here on purpose: this is the independent cross-check
    of the frontend, and it must not reuse the frontend's own parser.
    """
    if path.suffix.lower() != ".json":
        return None
    document = json.loads(path.read_text(encoding="utf-8"))
    paths = document.get("paths")
    if not isinstance(paths, dict):
        return None
    total = 0
    for item in paths.values():
        if not isinstance(item, dict):
            continue
        for key in item:
            if key.lower() in HTTP_METHODS:
                total += 1
    return total


def _rejection_reasons(model: dict[str, Any]) -> list[dict[str, str]]:
    """Sorted, machine-stable reasons for one refused spec."""
    reasons: list[dict[str, str]] = []
    for finding in sorted(
        model.get("issues") or [],
        key=lambda item: (
            str(item.get("pointer", "input")),
            str(item.get("keyword", "")),
        ),
    ):
        reasons.append(
            {
                "code": "unsupported.keyword",
                "pointer": str(finding.get("pointer", "input")),
                "keyword": str(finding.get("keyword", "")),
            }
        )
    return reasons


def _compile_generated(package_dir: Path) -> tuple[bool, str | None]:
    """``moon fmt --check`` then ``moon check``; returns (ok, failing stage)."""
    fmt = _run(["moon", "fmt", "--check"], cwd=package_dir)
    if fmt.returncode != 0:
        return False, "fmt"
    check = _run(
        ["moon", "check", "--target", "native", "--deny-warn"], cwd=package_dir
    )
    if check.returncode != 0:
        return False, "check"
    return True, None


def resolve_spec(entry: dict[str, Any]) -> Path | None:
    """Locate a manifest entry's document, or ``None`` when pending/absent."""
    if entry.get("status") == "pending" or entry.get("kind") == "planned":
        return None
    if entry.get("kind") == "local":
        candidate = ROOT / str(entry["path"])
    else:
        candidate = ROOT / "corpus" / "_downloads" / str(entry["id"])
    return candidate if candidate.is_file() else None


def measure(
    entry: dict[str, Any],
    *,
    cache_dir: Path,
    generated_root: Path,
    compile_packages: bool,
) -> dict[str, Any]:
    """Measure one manifest entry. Never raises for a rejected spec."""
    spec_id = str(entry["id"])
    record: dict[str, Any] = {
        "id": spec_id,
        "kind": entry.get("kind", "local"),
        "role": entry.get("role", "control"),
        "operations_total": 0,
        "operations_modeled": 0,
        "operations_dropped": 0,
        "operations_supported": 0,
        "operations_rejected": 0,
        "rejection_reasons": [],
        "compile_pass": None,
        "compile_stage": None,
    }

    spec = resolve_spec(entry)
    if spec is None:
        record["status"] = "not_fetched"
        record["path"] = None
        return record
    record["path"] = repo_relative(spec)

    normalized = cache_dir / f"{module_name_for(spec_id)}.normalized.json"
    normalized.parent.mkdir(parents=True, exist_ok=True)
    adapted = _run(
        ["moon", "run", ".", "--target", "native", "--", spec, normalized],
        cwd=FRONTEND_DIR,
    )
    if adapted.returncode != 0 or not normalized.is_file():
        record["status"] = "adapter_error"
        record["rejection_reasons"] = [
            {
                "code": "frontend.adapter_error",
                "pointer": "input",
                "keyword": "",
            }
        ]
        return record

    model = json.loads(normalized.read_text(encoding="utf-8"))
    raw_total = raw_operation_count(spec)
    modeled = len(model.get("operations") or [])
    total = modeled if raw_total is None else raw_total
    record["operations_total_source"] = "modeled" if raw_total is None else "raw"
    record["operations_total"] = total
    record["operations_modeled"] = modeled
    record["operations_dropped"] = max(total - modeled, 0)

    reasons = _rejection_reasons(model)
    if reasons:
        record["status"] = "rejected"
        record["rejection_reasons"] = reasons
        record["operations_rejected"] = total
        return record

    out_dir = generated_root / module_name_for(spec_id)
    if out_dir.exists():
        shutil.rmtree(out_dir)
    generated = _run(
        [
            sys.executable,
            CLI_SCRIPT,
            "generate",
            spec,
            "--module",
            module_name_for(spec_id),
            "--out",
            out_dir,
        ]
    )
    if generated.returncode != 0:
        record["status"] = (
            "rejected" if generated.returncode == EXIT_UNSUPPORTED else "cli_error"
        )
        record["rejection_reasons"] = [
            {"code": f"cli.exit_{generated.returncode}", "pointer": "input", "keyword": ""}
        ]
        record["operations_rejected"] = total
        return record

    record["status"] = "generated"
    if compile_packages:
        ok, stage = _compile_generated(out_dir)
        record["compile_pass"] = ok
        record["compile_stage"] = stage
    if record["compile_pass"] is False:
        record["operations_rejected"] = total
        return record

    record["operations_supported"] = modeled
    record["operations_rejected"] = total - modeled
    return record


def _block(rows: list[dict[str, Any]]) -> dict[str, Any]:
    """Headline numbers for one set of specs."""
    def total(field: str) -> int:
        return sum(int(r.get(field) or 0) for r in rows)

    compiled = [r for r in rows if r.get("compile_pass") is not None]
    passed = [r for r in compiled if r.get("compile_pass")]
    reason_counts: dict[str, int] = {}
    for record in rows:
        for reason in record.get("rejection_reasons") or []:
            code = str(reason.get("code", "unknown"))
            reason_counts[code] = reason_counts.get(code, 0) + 1
    return {
        "specs_total": len(rows),
        "specs_generated": sum(1 for r in rows if r["status"] == "generated"),
        "specs_rejected": sum(1 for r in rows if r["status"] == "rejected"),
        "specs_error": sum(
            1 for r in rows if r["status"] in {"adapter_error", "cli_error"}
        ),
        "specs_pending": sum(1 for r in rows if r["status"] == "not_fetched"),
        "operations_total": total("operations_total"),
        "operations_modeled": total("operations_modeled"),
        "operations_dropped": total("operations_dropped"),
        "operations_supported": total("operations_supported"),
        "operations_rejected": total("operations_rejected"),
        "compile_pass": f"{len(passed)}/{len(compiled)}",
        "rejection_reasons": {
            code: reason_counts[code] for code in sorted(reason_counts)
        },
    }


def summarize(records: list[dict[str, Any]]) -> dict[str, Any]:
    """Aggregate records overall and for the real-world subsets alone.

    The project must not claim more than it measured, so the published
    headline numbers are the ``real_world`` block; the local control fixtures
    are reported separately instead of padding the totals.
    """
    real_world = [r for r in records if r.get("role") == "real-world"]
    return {"all": _block(records), "real_world": _block(real_world)}


def _totals_block(title: str, block: dict[str, Any]) -> list[str]:
    return [
        f"### {title}",
        "",
        "```text",
        f"specs_total            {block['specs_total']}",
        f"specs_generated        {block['specs_generated']}",
        f"specs_rejected         {block['specs_rejected']}",
        f"specs_error            {block['specs_error']}",
        f"specs_pending          {block['specs_pending']}",
        f"operations_total       {block['operations_total']}",
        f"operations_supported   {block['operations_supported']}",
        f"operations_rejected    {block['operations_rejected']}",
        f"operations_dropped     {block['operations_dropped']}",
        f"compile_pass           {block['compile_pass']}",
        "```",
        "",
    ]


def render_report(summary: dict[str, Any], records: list[dict[str, Any]]) -> str:
    """Render the deterministic markdown report."""
    lines = [
        "# Corpus Report (T12)",
        "",
        "Generated by `tools/corpus_metrics.py`; do not edit numbers by hand.",
        "Only measured values appear here — pending sources are listed as pending.",
        "",
        "Regenerate with:",
        "",
        "```pwsh",
        "python tools/corpus_metrics.py --json-out tests/_build/corpus-metrics/summary.json --report-out tests/_build/corpus-metrics/report.md",
        "```",
        "",
        "Metric definitions and granularity caveats: the module docstring in",
        "`tools/corpus_metrics.py`. Corpus layout and provenance rules:",
        "`corpus/README.md`.",
        "",
        "## Totals",
        "",
        "Granularity: V1 refuses a spec, not an operation, so a refused spec",
        "contributes 0 supported operations. Headline claims must come from the",
        "`real-world` block; the `control` fixtures only guard the machinery.",
        "",
    ]
    lines += _totals_block("All specs", summary["all"])
    lines += _totals_block("Real-world specs only", summary["real_world"])
    lines += [
        "## Per spec",
        "",
        "| Spec | Role | Status | Ops total | Ops supported | Ops dropped | Compile | Reasons |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for record in records:
        reasons = ", ".join(
            sorted(
                {
                    f"{reason['code']}@{reason['pointer']}"
                    for reason in record.get("rejection_reasons") or []
                }
            )
        )
        compile_cell = (
            "n/a"
            if record.get("compile_pass") is None
            else ("pass" if record["compile_pass"] else f"fail:{record['compile_stage']}")
        )
        lines.append(
            f"| `{record['id']}` | {record['role']} | {record['status']} | "
            f"{record['operations_total']} | {record['operations_supported']} | "
            f"{record['operations_dropped']} | {compile_cell} | {reasons or '-'} |"
        )
    lines += ["", "## Rejection reasons", ""]
    reason_counts = summary["all"]["rejection_reasons"]
    if reason_counts:
        for code, count in reason_counts.items():
            lines.append(f"- `{code}`: {count}")
    else:
        lines.append("- none")
    pending = [r for r in records if r["status"] == "not_fetched"]
    lines += ["", "## Pending sources", ""]
    if pending:
        for record in pending:
            lines.append(f"- `{record['id']}`")
    else:
        lines.append("- none")
    lines.append("")
    return "\n".join(lines)


def load_manifest(path: Path) -> list[dict[str, Any]]:
    document = json.loads(path.read_text(encoding="utf-8"))
    sources = document.get("sources")
    if not isinstance(sources, list):
        raise SystemExit(f"{path}: manifest has no 'sources' array")
    return sources


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Measure the T12 corpus.")
    parser.add_argument(
        "--manifest", default=str(ROOT / "corpus" / "sources.json")
    )
    parser.add_argument(
        "--cache-dir", default=str(ROOT / "tests" / "_build" / "corpus-metrics")
    )
    parser.add_argument("--skip-compile", action="store_true")
    parser.add_argument("--json-out")
    parser.add_argument("--report-out")
    args = parser.parse_args(argv)

    cache_dir = Path(args.cache_dir)
    entries = sorted(load_manifest(Path(args.manifest)), key=lambda e: str(e["id"]))
    records = [
        measure(
            entry,
            cache_dir=cache_dir / "normalized",
            generated_root=cache_dir / "generated",
            compile_packages=not args.skip_compile,
        )
        for entry in entries
    ]
    summary = summarize(records)

    payload = json.dumps(
        {"summary": summary, "specs": records}, indent=2, sort_keys=True
    )
    if args.json_out:
        target = Path(args.json_out)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(payload + "\n", encoding="utf-8")
    else:
        print(payload)
    if args.report_out:
        target = Path(args.report_out)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(render_report(summary, records), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
