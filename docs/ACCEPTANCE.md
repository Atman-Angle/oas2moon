# Acceptance and release evidence

## Release state

The bounded V1 development scope is complete and passed its post-merge release gate on `main` commit `11acf9e` (`cross-platform-ci` run `35298853128`; Ubuntu and Windows both succeeded). "Complete" here means the documented profile in this file and [SUPPORTED_OPENAPI.md](SUPPORTED_OPENAPI.md), not complete OpenAPI 3.0 support, full GitHub/OpenAI compatibility, or arbitrary-document acceptance.

## Current acceptance gates

| Gate | Current evidence | Status |
|---|---|---|
| Generator/frontend/codegen tests | `python -m pytest tests -q` | Required for release; re-run for each candidate |
| Generated package format/check/test | `demo/petstore/run_demo.ps1`, steps 3–5 | Required; native target |
| Real local HTTP integration | Demo steps 6–11; strict Python fixture server, generated MoonBit client | Required |
| Deterministic regeneration | `tests/test_t13_determinism.py`; demo step 12 byte hashes | Required |
| Ubuntu and Windows hosted verification | [run 35298853128](https://github.com/Atman-Angle/oas2moon/actions/runs/35298853128), commit `11acf9e`: both jobs succeeded | Current post-merge release evidence |
| Bounded real-world corpus | `python tools/corpus_metrics.py --json-out tests/_build/corpus-metrics/summary.json --report-out docs/CORPUS_REPORT.md`; see [CORPUS_REPORT.md](CORPUS_REPORT.md) | 5/5 real-world specs compiled; 12/12 real-world operations supported; one expected control rejection |
| Unsupported-feature diagnostics | negative `oneOf` fixtures and phase/CLI tests | Required; no silent fallback |

The hosted workflow is [cross-platform-ci.yml](../.github/workflows/cross-platform-ci.yml). It runs MoonBit formatting/checks, the core MoonBit test suite, determinism tests, `python -m pytest tests -q`, and the PowerShell Petstore HTTP demo on `ubuntu-latest` and `windows-latest`.

## Project Spec completion mapping

| `PROJECT_SPEC.md` completion criterion | Current evidence |
|---|---|
| Supported real inputs normalize correctly | Frontend/IR tests plus the committed corpus manifest and generated/compiled corpus report |
| Generated packages compile | 7/7 generated corpus specs compile; real-world corpus `compile_pass=5/5` |
| Generated clients send correct HTTP requests | Post-merge Petstore HTTP demo on Ubuntu and Windows: `ALL PASS (11 checks)`, 19 e2e checks and 12 wire requests per platform |
| Typed decoding works | Same generated-client HTTP demo, including CRUD, typed responses, 204, and structured errors |
| Unsupported semantics fail explicitly | Expected `oneOf` control rejection with stable diagnostic `unsupported.keyword@#/components/schemas/Choice/oneOf` |
| Deterministic regeneration passes | 37 determinism tests on Ubuntu and Windows plus byte-hash comparison in the demo |
| Real-world coverage is measured and published | [CORPUS_REPORT.md](CORPUS_REPORT.md): 5/5 real-world specs compiled; 12/12 real-world operations supported; one expected control rejection |

## Reproduction commands

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

The first three commands establish the current local test, corpus, and demo results. The demo is the acceptance path that proves `moon fmt`, `moon check`, `moon test`, real HTTP calls, response enums, unexpected response media type handling, auth, response/error handling, and byte-identical regeneration.

## Non-claims and remaining limited-verification items

- Do not record a test count, performance metric, or platform result unless it came from the candidate run or an accessible hosted run.
- A passing CaptureTransport test alone is insufficient; retain the real local HTTP demo.
- Corpus evidence is bounded: one full 3-operation archived OAI Petstore sample plus project/curated subsets; it is not a full-document population study.
- Any new supported feature needs parse/normalize, codegen, generated-package compilation, and real HTTP evidence when its wire semantics matter.

The detailed support classification is in [SUPPORTED_OPENAPI.md](SUPPORTED_OPENAPI.md).
