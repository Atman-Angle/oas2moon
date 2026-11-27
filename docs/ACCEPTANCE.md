# Acceptance and release evidence

## Release state

The bounded V1 scope is maintained against the current candidate commit. Hosted CI status must be checked on that exact commit; historical run links are not evidence for a newer candidate. "Complete" means the documented profile in this file and [SUPPORTED_OPENAPI.md](SUPPORTED_OPENAPI.md), not complete OpenAPI 3.0 support.

## Current acceptance gates

| Gate | Current evidence | Status |
|---|---|---|
| Generator/frontend/codegen tests | `python -m pytest tests -q` | Required for release; re-run for each candidate |
| Generated package format/check/test | `demo/petstore/run_demo.ps1`, steps 3–5 | Required; native target |
| Real local HTTP integration | Demo steps 6–11; strict Python fixture server, generated MoonBit client | Required |
| Deterministic regeneration | `tests/test_t13_determinism.py`; demo step 12 byte hashes | Required |
| Ubuntu and Windows hosted verification | [Run 46003124284](https://github.com/Atman-Angle/oas2moon/actions/runs/46003124284), candidate commit `7524311a0069f48293775e1f28f106d453152d29` | Pass |
| Bounded real-world corpus | `python tools/corpus_metrics.py --json-out tests/_build/corpus-metrics/summary.json --report-out docs/CORPUS_REPORT.md`; see [CORPUS_REPORT.md](CORPUS_REPORT.md) | 4/5 real-world specs compiled; the official OAI sample is rejected for unsupported `default` responses |
| Unsupported-feature diagnostics | negative `oneOf` fixtures and phase/CLI tests | Required; no silent fallback |

Local verification of branch `codex/acceptance-rc1` at source commit
`4bae49e62a0699992fcfcab4511c885ec7e6ad2f` completed on 2026-11-27 with
`moonc v1.0.0-rc1+3c0520448`. `python -m pytest tests -q`
passed 126 tests in 202.33 seconds. The Unicode-checkout CLI suite passed 10
tests. Frontend, core, codegen and runtime passed `moon fmt --check` and native
checks/builds; core passed 8 tests and runtime passed 34 tests. The bounded
corpus compiled 7/7 generated packages and 5/5 real-world specs, supporting
12/12 real-world operations with one expected `oneOf` control rejection.
Petstore E2E passed all 11 checks and 19 assertions, recorded 12 HTTP requests,
and regenerated 9 files byte-identically. The Mooncakes 0.1.1 umbrella and four
components were published from the source snapshot at that commit, then resolved
and exercised from a fresh consumer,
which printed `0.1.1` and `4`. Hosted run [46003124284](https://github.com/Atman-Angle/oas2moon/actions/runs/46003124284) passed both Ubuntu and Windows on commit `7524311a0069f48293775e1f28f106d453152d29`, including the Unicode-checkout suite. The GitHub `v0.1.1` tag still points to the earlier baseline `d41950a` and was not rewritten; use source commit `4bae49e62a0699992fcfcab4511c885ec7e6ad2f` to reproduce the Mooncakes package source.

Local verification of candidate commit `4685320` on 2026-11-27 passed
`python -m pytest tests -q` with 127 tests, core MoonBit checks with 8 tests,
and the Petstore demo with all 11 checks. The corpus compiled 6/6 generated
packages and 4/5 real-world specs. The official OAI sample was rejected with
`unsupported.response_status` because its operations declare unsupported
`default` responses. The Amap example generated and passed native format/check;
its live request requires a user-provided Amap key and was not verified here.

The hosted workflow is [cross-platform-ci.yml](../.github/workflows/cross-platform-ci.yml). It runs MoonBit formatting/checks, the core MoonBit test suite, determinism tests, `python -m pytest tests -q`, and the PowerShell Petstore HTTP demo on `ubuntu-latest` and `windows-latest`.

## Project Spec completion mapping

| `PROJECT_SPEC.md` completion criterion | Current evidence |
|---|---|
| Supported real inputs normalize correctly | Frontend/IR tests plus the committed corpus manifest and generated/compiled corpus report |
| Generated packages compile | 6/6 generated corpus specs compile; real-world corpus `compile_pass=4/4` for generated specs |
| Generated clients send correct HTTP requests | Local and hosted Petstore HTTP demos: `ALL PASS (11 checks)`, 19 e2e checks and 12 wire requests |
| Typed decoding works | Same generated-client HTTP demo, including CRUD, typed responses, 204, and structured errors |
| Unsupported semantics fail explicitly | Expected `oneOf` control rejection and OAI Petstore `default` response rejection with stable diagnostics |
| Deterministic regeneration passes | Local Python determinism tests and byte-identical 9-file comparison in the local and hosted Petstore demos |
| Real-world coverage is measured and published | [CORPUS_REPORT.md](CORPUS_REPORT.md): 4/5 real-world specs compile; the remaining official sample is rejected for an unsupported response construct |

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

The first three commands establish the current local test, corpus, and demo results. The hosted workflow is still required to verify this candidate on Ubuntu and Windows. The demo proves `moon fmt`, `moon check`, `moon test`, real HTTP calls, response enums, unexpected response media type handling, auth, response/error handling, and byte-identical regeneration.

## Non-claims and remaining limited-verification items

- Do not record a test count, performance metric, or platform result unless it came from the candidate run or an accessible hosted run.
- A passing CaptureTransport test alone is insufficient; retain the real local HTTP demo.
- Corpus evidence is bounded: one full 3-operation archived OAI Petstore sample plus project/curated subsets; it is not a full-document population study.
- Any new supported feature needs parse/normalize, codegen, generated-package compilation, and real HTTP evidence when its wire semantics matter.

The detailed support classification is in [SUPPORTED_OPENAPI.md](SUPPORTED_OPENAPI.md).
