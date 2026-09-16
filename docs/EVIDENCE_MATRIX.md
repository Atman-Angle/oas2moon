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
| deterministic ordering | UTF-8 bytewise map keys; canonical sort for derived collections; stable bytes | generate twice, compare files/hashes | FROZEN + TEST-T13 |

## Known unresolved API questions

- Exact installed MoonBit async/HTTP request and response types, error propagation, and body APIs (T02).
- Exact MoonBit representation for optional-plus-nullable fields and generated response enums (T01/T02).
- Exact CLI argument parser and subprocess conventions on Windows (T10).
- Final package/module layout accepted by the real MoonBit toolchain (T06).

## Contradiction check

Reviewed against `PROJECT_SPEC.md`, `ARCHITECTURE.md`, `SUPPORTED_OPENAPI.md`, `ACCEPTANCE.md`, `DEVELOPMENT_SPEC.md`, and `DEVELOPMENT_TASKS.md` on 2026-09-16. No intentional scope expansion was introduced. The only intentionally unresolved details are marked SPIKE; implementation must not present them as verified capabilities.
