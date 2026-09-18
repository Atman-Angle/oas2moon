# Changelog

## 0.1.0 — bounded V1 (2026-09-18)

- Rewrote the README around the MoonBit-first authority boundary, runnable quick start, real HTTP demo, support limits, and hosted CI evidence.
- Classified support claims by evidence and recorded known gaps instead of future plans.
- Added source installation instructions, release acceptance, third-party notices, and five-minute demo instructions.
- Removed two unreferenced broken Python editing helpers and three obsolete spike runners that invoked a deleted generator.
- Kept the remaining `spike/` sources as clearly labelled historical experiments.
- Serialized Petstore fixture capture writes and persist them before responses so repeated CI runs cannot observe stale or truncated wire evidence.
- Added a reproducible T12 corpus harness and manifest covering an official archived Petstore 3.0 sample plus curated GitHub/OpenAI/JSONPlaceholder subsets; the committed report records 5/5 real-world specs compiled and 12/12 operations supported.
- Fixed MoonBit PascalCase naming for the reserved type name `Error` (`ErrorValue`), found by the pinned official Petstore sample and covered by MoonBit/Python regressions.
- Fixed response-enum code generation and added real-HTTP coverage for distinct 200/201 success schemas.
- Added explicit `SdkError.Unsupported` handling when a declared JSON response arrives with a non-JSON `Content-Type`.
- Removed internal development reports, prompts, and the Python reference-oracle tests from the public worktree while retaining them locally; public CI and tests no longer depend on them.
- Published the MoonBit modules `oas2moon_runtime`, `oas2moon_core`, `oas2moon_codegen`, and `oas2moon_frontend` under the `Atman-Angle` Mooncakes namespace.

## Hosted evidence referenced by this release

- T12 corpus/metrics merged through [PR #3](https://github.com/Atman-Angle/oas2moon/pull/3) at merge commit `11acf9e`.
- Public release-hardening changes merged through the release-hardening pull requests.
- The latest public `main` commit is `5187939dd78d8af2d0707db7bab3de58b10ab1fa`; [cross-platform-ci run 35318618356](https://github.com/Atman-Angle/oas2moon/actions/runs/35318618356) completed successfully on Ubuntu and Windows.

This entry records package version 0.1.0. It does not imply complete OpenAPI 3.0 compatibility, full GitHub/OpenAI support, or a compatibility percentage.
