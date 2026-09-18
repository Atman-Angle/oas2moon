"""T12: corpus manifest and metrics contract.

The corpus exists to prove generality without exaggerating it, so these tests
guard the *rules* rather than the current numbers:

- a remote source is only measurable when it is pinned;
- the metrics engine reports generated, refused and pending specs correctly;
- the committed real-world corpus covers Petstore, GitHub, OpenAI and one
  conventional REST API subset;
- its output is byte-deterministic;
- ``docs/CORPUS_REPORT.md`` is exactly what a fresh run produces, so no number
  in it can be hand-edited or stale.
"""

from __future__ import annotations

import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "corpus_metrics.py"
MANIFEST = ROOT / "corpus" / "sources.json"
REPORT = ROOT / "docs" / "CORPUS_REPORT.md"
OUTPUT_ROOT = ROOT / "tests" / "_build" / "t12-corpus"
TIMEOUT = 900


def run_metrics(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=TIMEOUT,
        cwd=str(ROOT),
    )


def fresh_dir(name: str) -> Path:
    path = OUTPUT_ROOT / name
    if path.exists():
        shutil.rmtree(str(path))
    path.mkdir(parents=True, exist_ok=True)
    return path


def write_manifest(path: Path, sources: list[dict]) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps({"manifestVersion": 1, "sources": sources}, indent=2),
        encoding="utf-8",
    )
    return path


def load_manifest() -> dict:
    return json.loads(MANIFEST.read_text(encoding="utf-8"))


def test_manifest_entries_are_pinned_or_pending() -> None:
    """Every source is either local, or remote and explicitly pinned/pending."""
    sources = load_manifest()["sources"]
    ids = [entry["id"] for entry in sources]
    assert len(ids) == len(set(ids)), f"duplicate corpus ids: {ids}"

    for entry in sources:
        label = entry["id"]
        assert entry.get("role") in {"real-world", "control"}, label
        if entry.get("kind") == "local":
            local_path = ROOT / entry["path"]
            assert local_path.is_file(), f"{label}: missing local path"
            assert entry.get("origin"), f"{label}: local source needs provenance"
            if entry.get("sha256"):
                actual = hashlib.sha256(local_path.read_bytes()).hexdigest()
                assert actual.lower() == str(entry["sha256"]).lower(), (
                    f"{label}: local fixture does not match its pinned sha256"
                )
            continue
        if entry.get("kind") == "planned":
            assert entry.get("note"), f"{label}: planned source needs a next step"
            assert not entry.get("url"), (
                f"{label}: a planned source has not chosen a document yet"
            )
            continue
        assert entry.get("kind") == "remote", label
        assert entry.get("url"), f"{label}: remote source needs a repository url"
        pinned = entry.get("commit") and entry.get("sha256")
        if entry.get("status") == "pending":
            assert not pinned, (
                f"{label}: a pinned source must leave the pending state so the "
                f"metrics can actually measure it"
            )
            assert entry.get("note"), f"{label}: pending source needs a next step"
        else:
            assert pinned, (
                f"{label}: remote sources must pin commit + sha256 before they "
                f"may be measured"
            )


def test_local_corpus_is_measurable() -> None:
    """The committed corpus must contain every required real-world subset."""
    sources = load_manifest()["sources"]
    measurable = {
        entry["id"]: entry
        for entry in sources
        if entry.get("role") == "real-world"
        and entry.get("kind") == "local"
        and (ROOT / str(entry.get("path", ""))).is_file()
    }
    assert {
        "petstore/openapi.json",
        "oai/petstore-3.0",
        "github-rest/subset",
        "openai/subset",
        "jsonplaceholder/subset",
    }.issubset(measurable), measurable.keys()
    assert not [
        entry["id"]
        for entry in sources
        if entry.get("role") == "real-world" and entry.get("status") == "pending"
    ], "real-world corpus still contains pending entries"


def test_metrics_report_generated_refused_and_pending() -> None:
    """One generated spec, one refused spec, one pending source."""
    work = fresh_dir("contract")
    manifest = write_manifest(
        work / "sources.json",
        [
            {
                "id": "petstore/openapi.json",
                "kind": "local",
                "role": "real-world",
                "path": "fixtures/petstore/openapi.json",
                "origin": "test",
                "license": "test",
            },
            {
                "id": "control/unsupported-oneof.json",
                "kind": "local",
                "role": "control",
                "path": "fixtures/unsupported/oneof.json",
                "origin": "test",
                "license": "test",
            },
            {
                "id": "remote/pending",
                "kind": "remote",
                "role": "real-world",
                "status": "pending",
                "url": "https://example.invalid/spec",
                "commit": None,
                "sha256": None,
                "note": "test placeholder",
            },
        ],
    )
    out = work / "summary.json"
    completed = run_metrics(
        "--manifest", str(manifest), "--skip-compile", "--json-out", str(out)
    )
    assert completed.returncode == 0, f"metrics failed:\n{completed.stderr}"

    payload = json.loads(out.read_text(encoding="utf-8"))
    by_id = {record["id"]: record for record in payload["specs"]}

    generated = by_id["petstore/openapi.json"]
    assert generated["status"] == "generated", generated
    # JSON specs are cross-checked against a stdlib count of paths.<method>.
    assert generated["operations_total_source"] == "raw"
    assert generated["operations_total"] == 3
    assert generated["operations_modeled"] == 3
    assert generated["operations_dropped"] == 0
    assert generated["operations_supported"] == 3
    assert generated["operations_rejected"] == 0

    refused = by_id["control/unsupported-oneof.json"]
    assert refused["status"] == "rejected", refused
    assert refused["operations_supported"] == 0
    assert refused["operations_rejected"] == refused["operations_total"] == 1
    assert [reason["code"] for reason in refused["rejection_reasons"]] == [
        "unsupported.keyword"
    ]
    assert refused["rejection_reasons"][0]["pointer"] == (
        "#/components/schemas/Choice/oneOf"
    )

    pending = by_id["remote/pending"]
    assert pending["status"] == "not_fetched"
    assert pending["operations_total"] == 0

    summary = payload["summary"]
    assert summary["all"]["specs_total"] == 3
    assert summary["all"]["specs_generated"] == 1
    assert summary["all"]["specs_rejected"] == 1
    assert summary["all"]["specs_pending"] == 1
    # Only the real-world entry may contribute to the headline block.
    assert summary["real_world"]["specs_total"] == 2
    assert summary["real_world"]["operations_supported"] == 3
    assert summary["real_world"]["specs_pending"] == 1


def test_metrics_output_is_byte_deterministic() -> None:
    """The same corpus must produce byte-identical metrics and reports."""
    work = fresh_dir("determinism")
    runs = []
    for run in ("a", "b"):
        out = work / f"{run}.json"
        report = work / f"{run}.md"
        completed = run_metrics(
            "--manifest",
            str(MANIFEST),
            "--skip-compile",
            "--json-out",
            str(out),
            "--report-out",
            str(report),
        )
        assert completed.returncode == 0, f"metrics failed:\n{completed.stderr}"
        runs.append((out.read_bytes(), report.read_bytes()))
    assert runs[0][0] == runs[1][0], "metrics JSON is not byte-deterministic"
    assert runs[0][1] == runs[1][1], "metrics report is not byte-deterministic"
    for text in (runs[0][0].decode("utf-8"), runs[0][1].decode("utf-8")):
        for forbidden in ("D:\\", "C:\\", "/home/", "/Users/"):
            assert forbidden not in text, (
                f"metrics output leaked a machine path: {forbidden!r}"
            )
        assert not re.search(r"\b20\d\d-\d\d-\d\d\b", text), (
            "metrics output contains a timestamp"
        )


@pytest.mark.skipif(
    shutil.which("moon") is None, reason="MoonBit toolchain is required"
)
def test_committed_report_matches_a_fresh_run() -> None:
    """`docs/CORPUS_REPORT.md` must be the output of the committed manifest.

    This is the anti-drift check for T12: it fails if the report was edited by
    hand, or if it was not regenerated after the corpus or the pipeline changed.
    """
    work = fresh_dir("committed")
    out = work / "summary.json"
    report = work / "CORPUS_REPORT.md"
    completed = run_metrics(
        "--manifest",
        str(MANIFEST),
        "--json-out",
        str(out),
        "--report-out",
        str(report),
    )
    assert completed.returncode == 0, f"metrics failed:\n{completed.stderr}"
    assert report.read_text(encoding="utf-8") == REPORT.read_text(encoding="utf-8"), (
        "docs/CORPUS_REPORT.md is stale; regenerate it with "
        "`python tools/corpus_metrics.py --json-out "
        "tests/_build/corpus-metrics/summary.json --report-out docs/CORPUS_REPORT.md`"
    )
