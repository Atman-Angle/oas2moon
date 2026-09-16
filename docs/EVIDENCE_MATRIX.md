# Evidence Matrix (T00)

Date: 2026-09-16  
Legend: **FROZEN** = documented contract; **SPIKE** = must be verified before implementation; **TEST** = required executable evidence.

| Contract | Decision | Evidence required | Status |
|---|---|---|---|
| Runtime request/response | adapter boundary with method, URL, headers, body and status/headers/body response | minimal MoonBit transport compile spike + local HTTP server | SPIKE-T02 |
| `SdkError` | structured transport/http/decode/encode/configuration/unsupported categories | MoonBit type compile spike; error tests | SPIKE-T02 |
| Status policy | typed success, `Unit` 204, response enum for differing schemas, structured non-2xx | status matrix fixtures + local HTTP assertions | FROZEN + TEST-T05 |
| optional/nullable | absence distinct from explicit null | IR/codegen fixtures and JSON round-trip tests | FROZEN + SPIKE-T01/T02 |
| path/query/header encoding | percent-encoded path; repeated supported query arrays; stable order; reject unsupported styles | byte-exact local server assertions | FROZEN + SPIKE-T04 |
| authentication | API key/Bearer/Basic in client config; operation override; empty security unauthenticated | local HTTP header/query assertions | FROZEN + SPIKE-T09 |
| CLI exit codes | 0, 2, 3, 4, 5, 6 semantics | subprocess tests on Windows and Linux | FROZEN + SPIKE-T10 |
| generated layout | package root with stable model/operation/client ownership | generated fixture + `moon fmt`/`moon check` | FROZEN + SPIKE-T06 |
| diagnostics | `DIAG code severity location: message`, sorted and path-safe | negative fixtures and byte comparison | FROZEN + TEST-T01/T13 |
| real HTTP transport | one runtime boundary that owns `moonbitlang/async/http`; generated code never imports it | `src/runtime_moonbit/http_transport.mbt` + generated-package compile + local HTTP assertions | TEST-T11 |
| end-to-end demo | `oas2moon generate` -> compile -> real server -> typed calls | `demo/petstore/run_demo.ps1` (11 checks, exit 0 on Windows) | TEST-T11 |
| auth on the wire | bearer, basic, api-key header and api-key query all validated by a real server | `demo/petstore/fixture_server.py` + `demo/petstore/integration/main.mbt` | TEST-T11 |
| error surfacing | non-2xx -> `Http(op, status, ...)`; missing credential -> `Configuration` | generated client assertions in the T11 driver | TEST-T11 |
| regeneration determinism | two generations byte-identical, including the emitted IR | `run_demo.ps1` step 12 (SHA-256 per file) | TEST-T11 |
| generated call shape | required params positional, optional labelled, async + `raise SdkError` | `docs/DECISIONS.md` §12 + ecosystem reference + generated package compile | FROZEN + TEST-T11 |
| deterministic ordering | UTF-8 bytewise map keys; canonical sort for derived collections; stable bytes | generate twice, compare files/hashes | FROZEN + TEST-T13 |

## Resolved by T11

- Real HTTP transport API and body handling: verified end to end by driving the
  generated client against the local fixture server.
- Generated operation call shape: positional required parameters, labelled
  optional parameters, async methods raising `SdkError`.
- Deterministic regeneration: verified by hashing two independent generations.
- Capture-vs-network split: one generated method body serves both, selected by
  whether `Client::new` received a `capture` transport.

## Known unresolved API questions

- Exact installed MoonBit async/HTTP request and response types, error propagation, and body APIs (T02).
- Exact MoonBit representation for optional-plus-nullable fields and generated response enums (T01/T02).
- Exact CLI argument parser and subprocess conventions on Windows (T10).
- Final package/module layout accepted by the real MoonBit toolchain (T06).

## Contradiction check

Reviewed against `PROJECT_SPEC.md`, `ARCHITECTURE.md`, `SUPPORTED_OPENAPI.md`, `ACCEPTANCE.md`, `DEVELOPMENT_SPEC.md`, and `DEVELOPMENT_TASKS.md` on 2026-09-16. No intentional scope expansion was introduced. The only intentionally unresolved details are marked SPIKE; implementation must not present them as verified capabilities.
