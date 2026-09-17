# Historical feasibility material

This directory contains pre-production MoonBit experiments retained as a historical record. It is not a production generator, a supported CLI path, or current release evidence.

The former PowerShell spike runners were removed in T15 because they invoked the deleted `spike/generator/generate.py`. Current verification uses `demo/petstore/run_demo.ps1`, `python -m pytest tests -q`, and `.github/workflows/cross-platform-ci.yml`.

The remaining `frontend/`, `probe/`, `probe_tests/`, and `prototype/` files are read-only reference experiments. Do not import them from production packages or use them to substantiate current support claims.
