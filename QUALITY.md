# Quality and Acceptance Evidence

This document explains what is publicly verifiable for the current `oas2moon`
release. The nine activity requirements are baseline gates; passing them does not
claim full OpenAPI compatibility.

## Project status

- Release: `0.1.0` bounded V1
- GitHub: [Atman-Angle/oas2moon](https://github.com/Atman-Angle/oas2moon)
- Latest public `main` commit: `5187939dd78d8af2d0707db7bab3de58b10ab1fa`
- Mooncakes: [Atman-Angle/oas2moon@0.1.0](https://mooncakes.io/docs/Atman-Angle/oas2moon)
- License: [MIT](LICENSE)

## Baseline requirements

| Requirement | Public evidence | Result |
|---|---|---|
| MoonBit is the primary implementation language | `src/frontend_adapter`, `src/core_moonbit`, `src/codegen_moonbit`, `src/runtime_moonbit`, and `umbrella` | Pass |
| Public GitHub repository and reviewable history | Public repository, `main` history, pull requests, and release-hardening commits | Pass |
| Clear structure and working core | Frontend adapter -> canonical IR -> codegen -> runtime pipeline | Pass |
| README with goal, installation, usage, and example | `README.md` and `demo/petstore/README.md` | Pass |
| Continuous integration | [cross-platform workflow](.github/workflows/cross-platform-ci.yml) on Ubuntu and Windows | Pass |
| Runnable example | `pwsh -NoProfile -File demo/petstore/run_demo.ps1` | Pass |
| Core test coverage | `tests/`, MoonBit package tests, generated-package checks, and HTTP E2E demo | Pass |
| Mooncakes publication | Umbrella and four implementation packages at `0.1.0`, all build successfully | Pass |
| OSI-approved open-source license | `LICENSE`, README, and package metadata use MIT | Pass |

## Engineering evidence

The latest hosted run is [cross-platform-ci run 35318618356](https://github.com/Atman-Angle/oas2moon/actions/runs/35318618356), for commit `5187939dd78d8af2d0707db7bab3de58b10ab1fa`. Both Ubuntu and Windows jobs succeeded. The workflow covers:

- MoonBit formatting, native checks, and package tests;
- deterministic regeneration;
- the Python fixture and generator test suite;
- the generated Petstore package;
- real local HTTP request/response assertions;
- authentication, response/error handling, and generated output comparison.

The local acceptance run also recorded `67 passed` for the Python suite and passing
MoonBit package tests. The Petstore demo reports `ALL PASS (11 checks)`, including
19 end-to-end assertions and 12 captured HTTP requests. These numbers are evidence
for this release candidate, not permanent compatibility guarantees.

## Scope and limitations

This is a deliberately bounded OpenAPI 3.0.x profile. Supported and unsupported
features are listed in [docs/SUPPORTED_OPENAPI.md](docs/SUPPORTED_OPENAPI.md).
In particular, OpenAPI 3.1, external/network references, `oneOf`/`anyOf`,
multipart, XML, callbacks, OAuth flows, and arbitrary parameter serialization are
outside V1. Unsupported semantics must produce diagnostics rather than silently
generating incorrect wire behavior.

The measured corpus is deliberately bounded and must not be read as a whole-spec
compatibility percentage. The project prefers explicit limits and reproducible
evidence over broad unsupported claims.

## Reproduce the evidence

From a fresh checkout with Python 3.12+, MoonBit, PowerShell 7, and a native C
toolchain installed:

```pwsh
python -m pytest tests -q
pwsh -NoProfile -File demo/petstore/run_demo.ps1
git diff --check
```

The hosted workflow is the authoritative cross-platform check. Local generated
outputs and test build directories are intentionally ignored and are not release
artifacts.
