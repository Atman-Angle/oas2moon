# November contest acceptance fixes

The review baseline is GitHub `main` at `d41950a`, tagged `v0.1.1`. The contest snapshot is scheduled for November 30, 2026 at 23:59 as stated in the notice.

| Item | Baseline finding | Acceptance check |
|---|---|---|
| RC1 runtime and generated SDKs | The strict runtime check reports five deprecated derives. The model-only SDK regression is the sole failure in the RC1 pytest run. | Strict native runtime checks and the existing model-only SDK regression pass on RC1. |
| CI | Both hosted jobs used `moonc v0.10.22`. The source format gates rewrote files before checking them. | Windows and Ubuntu log the pinned RC1 compiler and pass format, build, test, corpus and HTTP demo checks. |
| Fixture licensing | The notices link to Apache-2.0. The trimmed Petstore fixture's recorded provenance lacks a source revision. | Include the license text and record the available provenance for the redistributed fixtures. |
| Reproduction docs | Quick start runs a test command with zero tests. Acceptance docs retain results from an earlier working tree. | Quick start generates and compiles a client. The Petstore demo runs the SDK tests. Evidence names the tested revision and toolchain. |
| Windows paths | The native stage filesystem API fails with Chinese input names and output directories. | Generate and check an SDK from JSON and YAML with non-ASCII paths, including a non-ASCII checkout. |
| Mooncakes | The five published modules are at `0.1.0`. The registry frontend and runtime resolve older dependencies than the source baseline. | Publish the updated components before the umbrella, then resolve and exercise the umbrella from a fresh consumer. |

Baseline evidence is available in the [hosted CI run](https://github.com/Atman-Angle/oas2moon/actions/runs/45749164797), [GitHub release](https://github.com/Atman-Angle/oas2moon/releases/tag/v0.1.1) and [Mooncakes registry](https://mooncakes.io/docs/Atman-Angle/oas2moon).

## Resolution evidence

| Item | Result on `codex/acceptance-rc1` | Evidence |
|---|---|---|
| RC1 runtime and generated SDKs | Migrated the deprecated derives in source and generated code. The model-only output regression passes in the full suite. | `moonc v1.0.0-rc1+3c0520448`; runtime has 34 passing tests; [CLI regression](../tests/test_generation_edge_cases.py) |
| CI | Pinned the install scripts to the RC1 build, corrected compiler version checks to use `moonc -v`, and made format jobs check-only. Added a Windows Unicode-checkout job. | [Hosted run 46003124284](https://github.com/Atman-Angle/oas2moon/actions/runs/46003124284) passed Ubuntu and Windows on commit `7524311a0069f48293775e1f28f106d453152d29` |
| Fixture licensing | Included the Apache-2.0 text with its verified SHA-256. Clarified that the minimal local Petstore fixture is project-authored and recorded the archived OAI sample's pinned provenance. | [third-party notices](../THIRD_PARTY_NOTICES.md); [corpus source manifest](../corpus/sources.json) |
| Reproduction docs | Quick start now checks the generated package; the Petstore demo is the test and HTTP acceptance path. | [README](../README.md); [acceptance evidence](ACCEPTANCE.md) |
| Windows paths | JSON and YAML generation and compilation pass with Unicode input/output names from an ASCII and a Unicode checkout. | `tests/test_t10_cli.py`: 10/10 in Unicode checkout |
| Mooncakes | Published frontend, core, runtime, codegen, then umbrella at `0.1.1`. A fresh consumer resolves the umbrella and prints version `0.1.1` and component count `4`. | `moon view --versions` shows `0.1.1` for all five modules; consumer `moon check` and `moon run cmd/main --target native` pass |

Local candidate verification on 2026-11-27 used `moonc v1.0.0-rc1+3c0520448`. The full Python suite passed 126 tests, the real-world corpus compiled 5/5 specs and supported 12/12 operations, and the Petstore demo passed 11 checks, 19 HTTP assertions and 12 requests with byte-identical regeneration. Hosted run 46003124284 passed all Ubuntu and Windows workflow steps, including the Windows Unicode-checkout test.

The Mooncakes 0.1.1 packages were published from [source commit `4bae49e62a0699992fcfcab4511c885ec7e6ad2f`](https://github.com/Atman-Angle/oas2moon/commit/4bae49e62a0699992fcfcab4511c885ec7e6ad2f) on `codex/acceptance-rc1`. The existing GitHub `v0.1.1` tag remains at baseline `d41950a`; it was not moved or overwritten. The commit link is the reproducible source for the Mooncakes 0.1.1 archive.
