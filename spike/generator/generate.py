#!/usr/bin/env python3
"""Generate a MoonBit client SDK from a normalized Frontend Model.

Usage::

    python spike/generator/generate.py \
        --input spike/build/normalized.json \
        --out spike/build/generated \
        --module oas2moon_spike/petstore

The generator reads nothing but the normalized Frontend Model produced by
``spike/frontend``; it never opens the original OpenAPI document. Diagnostics
are emitted in a stable order and the build report contains no timestamps and
no absolute paths.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from oas2moon import emit, formatter, frontend, ir, lower, support  # noqa: E402


def _digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def build(model: frontend.FrontendModel, module_name: str):
    """Run Support Validation, then lower to the Client IR when it passes."""

    report = support.validate(model)
    if not report.ok:
        return report, None
    return report, lower.lower(model, module_name, report)


def build_report(api: ir.ApiIr, files: dict[str, str], report: support.SupportReport):
    """A deterministic, path-free description of what was generated."""

    entries = [
        {
            "path": path.replace("\\", "/"),
            "bytes": len(text.encode("utf-8")),
            "sha256": _digest(text.encode("utf-8")),
        }
        for path, text in sorted(files.items())
    ]
    aggregate = _digest(
        "".join(f"{entry['path']}\0{entry['sha256']}\n" for entry in entries).encode("utf-8")
    )
    return {
        "module": api.module_name,
        "title": api.title,
        "openapi": api.version,
        "files": entries,
        "aggregate_sha256": aggregate,
        "formatter": "moonfmt",
        "models": [
            {
                "name": model.name,
                "kind": "enum" if isinstance(model, ir.EnumIr) else "struct",
                "members": [wire for _constructor, wire in model.members]
                if isinstance(model, ir.EnumIr)
                else None,
                "fields": [
                    {
                        "name": field.name,
                        "wire_name": field.wire_name,
                        "type": field.moon_type,
                        "required": field.required,
                        "nullable": field.nullable,
                    }
                    for field in model.fields
                ]
                if isinstance(model, ir.StructIr)
                else None,
            }
            for model in api.models
        ],
        "operations": [
            {
                "operationId": operation.operation_id,
                "fn": f"Client::{operation.fn_name}",
                "method": operation.method,
                "path": operation.path,
                "parameters": [
                    {
                        "name": parameter.name,
                        "wire_name": parameter.wire_name,
                        "in": parameter.location,
                        "type": parameter.moon_type,
                    }
                    for parameter in operation.params
                ],
                "body": None
                if operation.body is None
                else {"name": operation.body_name, "type": operation.body.render()},
                "success_status": operation.success_status,
                "response": None
                if operation.response is None
                else operation.response.render(),
                "security": list(operation.security),
            }
            for operation in api.operations
        ],
        "warnings": [warning.render() for warning in report.warnings],
        "errors": [],
    }


def failure_report(report: support.SupportReport):
    return {
        "errors": [error.render() for error in report.errors],
        "warnings": [warning.render() for warning in report.warnings],
        "files": [],
        "aggregate_sha256": None,
    }


def write_files(out_dir: Path, files: dict[str, str]) -> None:
    """Write every generated file with LF line endings."""

    for path, text in sorted(files.items()):
        target = out_dir / path
        target.parent.mkdir(parents=True, exist_ok=True)
        with open(target, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, help="normalized Frontend Model JSON")
    parser.add_argument("--out", required=True, help="output module directory")
    parser.add_argument("--module", required=True, help="generated module name")
    parser.add_argument("--report", help="write the build report JSON here")
    args = parser.parse_args(argv)

    model = frontend.load(args.input)
    report, api = build(model, args.module)

    if api is None:
        payload = failure_report(report)
        for error in report.errors:
            print(error.render(), file=sys.stderr)
        if args.report:
            Path(args.report).parent.mkdir(parents=True, exist_ok=True)
            Path(args.report).write_text(
                json.dumps(payload, indent=2, sort_keys=False) + "\n", encoding="utf-8"
            )
        print(json.dumps(payload, indent=2), file=sys.stdout)
        return 1

    try:
        files = emit.emit(api)
    except formatter.FormatterUnavailable as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    write_files(Path(args.out), files)
    payload = build_report(api, files, report)
    if args.report:
        Path(args.report).parent.mkdir(parents=True, exist_ok=True)
        Path(args.report).write_text(
            json.dumps(payload, indent=2, sort_keys=False) + "\n", encoding="utf-8"
        )
    print(json.dumps(payload, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
