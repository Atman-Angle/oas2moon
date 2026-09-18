# Five-minute defence demo

This script is executable on a machine with Python 3.12+, MoonBit, a native C toolchain, and PowerShell 7. The timings are presenter guidance, not measured performance claims.

## 0:00–0:30 — goal and scope

Say: “oas2moon turns the supported OpenAPI 3.0.x JSON/YAML profile into a typed MoonBit HTTP client. This is a Petstore-profile demonstration, not full OpenAPI compatibility.” Show `demo/petstore/openapi.json` and [`SUPPORTED_OPENAPI.md`](SUPPORTED_OPENAPI.md).

## 0:30–1:00 — generate and explain authority

```pwsh
python oas2moon.py generate demo/petstore/openapi.json `
  --module oas2moon/petstore_demo --out demo/petstore/_out/generated `
  --ir-out demo/petstore/_out/canonical.json
Get-Content demo/petstore/_out/canonical.json -TotalCount 20
```

Explain the Mermaid diagram in the README: the parser model is input fact only; the Canonical Client IR is the only codegen input; MoonBit owns normalization, naming, type mapping, codegen, and runtime semantics.

## 1:00–1:30 — show generated typed SDK

```pwsh
Get-Content demo/petstore/_out/generated/models.mbt -TotalCount 80
Get-Content demo/petstore/_out/generated/client.mbt -TotalCount 120
```

Point out the `Pet` type, typed async API, and that operations call the runtime boundary rather than an HTTP library directly.

## 1:30–2:00 — format, compile, and test

```pwsh
python demo/petstore/gen_tests.py demo/petstore/_out/canonical.json demo/petstore/_out/generated
Push-Location demo/petstore/_out/generated
moon fmt --check
moon check --target native --deny-warn
moon test --target native --deny-warn
Pop-Location
```

These commands are also performed by the end-to-end script. If a toolchain is unavailable, state that limitation and do not claim this portion passed.

## 2:00–3:30 — real HTTP, typed calls, auth, and errors

```pwsh
pwsh -NoProfile -File demo/petstore/run_demo.ps1
Get-Content demo/petstore/_out/server_capture.json -Raw
```

The script starts the strict local Python fixture server and drives it with the generated MoonBit client. Its pass/fail checks cover typed GET/POST/DELETE plus 204, a response enum for distinct 200/201 schemas, bearer/basic/API-key header/API-key query, a rejected credential, non-2xx `SdkError.Http`, missing-credential `SdkError.Configuration`, and explicit rejection of a declared-JSON response delivered as `text/plain`. It also runs the package `moon fmt`, `moon check`, and `moon test`.

## 3:30–4:00 — determinism

Point to the demo's final “byte-identical regeneration” result and its two generated trees under `demo/petstore/_out/`. The script compares SHA-256 hashes for every generator-owned package-root file. `tests/test_t13_determinism.py` adds corpus/IR ordering regressions.

## 4:00–4:30 — hosted CI

Open [cross-platform-ci run 35302482785](https://github.com/Atman-Angle/oas2moon/actions/runs/35302482785). Its API-accessible result is `success` for `Verify (Ubuntu)` and `Verify (Windows)` on `main` commit `686b91b`. The workflow runs the same test and demo gates. If the link is unavailable during a presentation, say so and show the workflow file; do not substitute a guessed result.

## 4:30–5:00 — limits and next steps

State the non-goals: no OpenAPI 3.1, external refs, unions/discriminator, multipart/XML, callbacks/webhooks, OAuth authorization flows, or arbitrary parameter styles. Unsupported input must diagnose rather than silently generate incorrect wire behaviour. The bounded corpus remains deliberately limited, and no Mooncakes package is published yet.
