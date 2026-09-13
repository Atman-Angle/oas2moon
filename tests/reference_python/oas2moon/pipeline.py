"""Formal Phase 1 pipeline entry points.

The adapter is an executable boundary.  This module consumes only the
versioned project-owned Frontend Model JSON and produces the canonical Client
IR after support validation; it never imports mooncontract or walks raw OpenAPI.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path
from . import frontend, lower, support


class FrontendAdapterError(RuntimeError):
    pass


def run_adapter(spec: str | Path, normalized: str | Path, adapter_dir: str | Path) -> None:
    """Run the real MoonBit adapter against JSON or YAML input."""

    spec_path = Path(spec).resolve()
    normalized_path = Path(normalized).resolve()
    cwd = Path(adapter_dir).resolve()
    result = subprocess.run(
        ["moon", "run", ".", "--target", "native", "--", str(spec_path), str(normalized_path)],
        cwd=cwd,
        text=True,
        capture_output=True,
    )
    if result.returncode:
        detail = (result.stdout + result.stderr).strip()
        raise FrontendAdapterError(detail or f"moon adapter exited {result.returncode}")


def load_and_validate(normalized: str | Path) -> tuple[frontend.FrontendModel, support.SupportReport]:
    model = frontend.load(normalized)
    if model.frontend_model_version != frontend.FRONTEND_MODEL_VERSION:
        raise frontend.FrontendModelError(
            f"unsupported frontend model version {model.frontend_model_version}; "
            f"expected {frontend.FRONTEND_MODEL_VERSION}"
        )
    return model, support.validate(model)


def normalize_to_ir(normalized: str | Path, module_name: str):
    model, report = load_and_validate(normalized)
    return model, report, None if not report.ok else lower.lower(model, module_name, report)


def diagnostics_json(report: support.SupportReport) -> str:
    """Stable machine-readable diagnostics, sorted by the validator contract."""

    values = [*report.errors, *report.warnings]
    payload = [
        {
            "code": item.code,
            "severity": item.severity,
            "json_pointer": item.json_pointer,
            "operation_id": item.operation_id,
            "message": item.message,
            "suggestion": item.suggestion,
        }
        for item in values
    ]
    return json.dumps(payload, ensure_ascii=False, indent=2, separators=(",", ": ")) + "\n"
