# Acceptance and release evidence

## Release state

The repository has a compile- and HTTP-verified **Petstore profile**. It must not be described as a complete OpenAPI 3.0 implementation or as a measured real-world-corpus release: T12 corpus metrics are absent.

## Current acceptance gates

| Gate | Current evidence | Status |
|---|---|---|
| Generator/frontend/codegen tests | `python -m pytest tests -q` | Required for release; re-run for each candidate |
| Generated package format/check/test | `demo/petstore/run_demo.ps1`, steps 3–5 | Required; native target |
| Real local HTTP integration | Demo steps 6–11; strict Python fixture server, generated MoonBit client | Required |
| Deterministic regeneration | `tests/test_t13_determinism.py`; demo step 12 byte hashes | Required |
| Ubuntu and Windows hosted verification | [run 35177945624](https://github.com/Atman-Angle/oas2moon/actions/runs/35177945624), commit `040f488`: both jobs succeeded | Historical hosted evidence; rerun on release PR |
| Unsupported-feature diagnostics | negative `oneOf` fixtures and phase/CLI tests | Required; no silent fallback |

The hosted workflow is [cross-platform-ci.yml](../.github/workflows/cross-platform-ci.yml). It runs MoonBit formatting/checks, the core MoonBit test suite, determinism tests, `python -m pytest tests -q`, and the PowerShell Petstore HTTP demo on `ubuntu-latest` and `windows-latest`.

## Candidate verification commands

Run from the repository root in PowerShell:

```pwsh
python -m pytest tests -q
pwsh -NoProfile -File demo/petstore/run_demo.ps1
git diff --check
git status --short
```

The first two commands establish the current local test/demo result. The demo is the acceptance path that proves `moon fmt`, `moon check`, `moon test`, real HTTP calls, auth, response/error handling, and byte-identical regeneration.

## Release blockers and non-claims

- Do not record a test count, performance metric, or platform result unless it came from the candidate run or an accessible hosted run.
- A passing CaptureTransport test alone is insufficient; retain the real local HTTP demo.
- T12 real-world corpus metrics remain a release-evidence gap.
- Response enums and `UnsupportedMediaType` lack real-HTTP demo coverage.
- Any new supported feature needs parse/normalize, codegen, generated-package compilation, and real HTTP evidence when its wire semantics matter.

The detailed support classification is in [SUPPORTED_OPENAPI.md](SUPPORTED_OPENAPI.md).
