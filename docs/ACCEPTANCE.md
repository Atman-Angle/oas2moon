# Acceptance and release evidence

## Release state

The repository has a compile- and HTTP-verified **bounded V1 profile**, plus generated/compiled corpus measurements for an official archived Petstore 3.0 sample and project/curated subsets. It must not be described as a complete OpenAPI 3.0 implementation or as evidence of full GitHub/OpenAI support.

## Current acceptance gates

| Gate | Current evidence | Status |
|---|---|---|
| Generator/frontend/codegen tests | `python -m pytest tests -q` | Required for release; re-run for each candidate |
| Generated package format/check/test | `demo/petstore/run_demo.ps1`, steps 3–5 | Required; native target |
| Real local HTTP integration | Demo steps 6–11; strict Python fixture server, generated MoonBit client | Required |
| Deterministic regeneration | `tests/test_t13_determinism.py`; demo step 12 byte hashes | Required |
| Ubuntu and Windows hosted verification | [run 35177945624](https://github.com/Atman-Angle/oas2moon/actions/runs/35177945624), commit `040f488`: both jobs succeeded | Historical hosted evidence; rerun on release PR |
| Bounded real-world corpus | `python tools/corpus_metrics.py --json-out tests/_build/corpus-metrics/summary.json --report-out docs/CORPUS_REPORT.md`; see [CORPUS_REPORT.md](CORPUS_REPORT.md) | 5/5 real-world specs compiled; 12/12 real-world operations supported; one expected control rejection |
| Unsupported-feature diagnostics | negative `oneOf` fixtures and phase/CLI tests | Required; no silent fallback |

The hosted workflow is [cross-platform-ci.yml](../.github/workflows/cross-platform-ci.yml). It runs MoonBit formatting/checks, the core MoonBit test suite, determinism tests, `python -m pytest tests -q`, and the PowerShell Petstore HTTP demo on `ubuntu-latest` and `windows-latest`.

## Candidate verification commands

Run from the repository root in PowerShell:

```pwsh
python -m pytest tests -q
python tools/corpus_metrics.py `
  --json-out tests/_build/corpus-metrics/summary.json `
  --report-out docs/CORPUS_REPORT.md
pwsh -NoProfile -File demo/petstore/run_demo.ps1
git diff --check
git status --short
```

The first two commands establish the current local test/demo result. The demo is the acceptance path that proves `moon fmt`, `moon check`, `moon test`, real HTTP calls, auth, response/error handling, and byte-identical regeneration.

## Release blockers and non-claims

- Do not record a test count, performance metric, or platform result unless it came from the candidate run or an accessible hosted run.
- A passing CaptureTransport test alone is insufficient; retain the real local HTTP demo.
- Corpus evidence is bounded: one full 3-operation archived OAI Petstore sample plus project/curated subsets; it is not a full-document population study.
- Response enums and `UnsupportedMediaType` lack real-HTTP demo coverage.
- Any new supported feature needs parse/normalize, codegen, generated-package compilation, and real HTTP evidence when its wire semantics matter.

The detailed support classification is in [SUPPORTED_OPENAPI.md](SUPPORTED_OPENAPI.md).
