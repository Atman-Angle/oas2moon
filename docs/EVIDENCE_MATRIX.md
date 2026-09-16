# Evidence Matrix (T00)

Date: 2026-09-16  
Legend: **FROZEN** = documented contract; **SPIKE** = must be verified before implementation; **TEST** = required executable evidence.

| Contract | Decision | Evidence required | Status |
|---|---|---|---|
| Runtime request/response | adapter boundary with method, URL, headers, body and status/headers/body response | runtime/unit tests + generated-package compile + local HTTP server | FROZEN + TEST-T07/T11 |
| `SdkError` | six variants: transport/http/decode/encode/configuration/unsupported; all carry `operation_id`; HTTP carries status/headers/body | `runtime_wbtest.mbt` + generated-client assertions + stable display tests | FROZEN + TEST-T07 |
| Status policy | typed success, `Unit` 204, response enum for differing schemas, structured non-2xx | status matrix fixtures + local HTTP assertions | FROZEN + TEST-T05 |
| optional/nullable | absence distinct from explicit null | IR/codegen fixtures and JSON round-trip tests | FROZEN + TEST-T01/T07 |
| path/query/header encoding | percent-encoded path; repeated supported query arrays; stable order; reject unsupported styles | byte-exact local server assertions | FROZEN + TEST-T07/T11 |
| authentication | API key/Bearer/Basic in client config; operation override; empty security unauthenticated | real-server header/query assertions in the T11 demo | FROZEN + TEST-T11 |
| CLI exit codes | 0, 1, 2, 3, 5, 6 semantics; 4 is unused/reserved | `tests/test_t10_cli.py` on Windows; Linux CI remains T14 | FROZEN + TEST-T10 |
| generated layout | self-contained flat package: `client.mbt`, `config.mbt`, `encoding.mbt`, `http_transport.mbt`, `models.mbt`, `runtime.mbt`, `moon.mod`, `moon.pkg` | generated fixture + `moon fmt`/`moon check`/`moon test` + T11 hash check | FROZEN + TEST-T06/T10/T11 |
| diagnostics | `DIAG code severity location: message`, sorted and path-safe | negative fixtures and byte comparison | FROZEN + TEST-T01/T13 |
| real HTTP transport | one runtime boundary that owns `moonbitlang/async/http`; generated code never imports it | `src/runtime_moonbit/http_transport.mbt` + generated-package compile + T07/T11 local HTTP assertions | TEST-T07/T11 |
| end-to-end demo | `oas2moon generate` -> compile -> real server -> typed calls | `demo/petstore/run_demo.ps1` (11 checks, exit 0 on Windows) | TEST-T11 |
| auth on the wire | bearer, basic, api-key header and api-key query all validated by a real server | `demo/petstore/fixture_server.py` + `demo/petstore/integration/main.mbt` | TEST-T11 |
| error surfacing | non-2xx -> `Http(op, status, ...)`; missing credential -> `Configuration` | generated client assertions in the T11 driver | TEST-T11 |
| regeneration determinism | two generations byte-identical, including the emitted IR | `run_demo.ps1` step 12 (SHA-256 per file); `tests/test_t13_determinism.py` over the spec + IR corpus | TEST-T11/T13 |
| generated call shape | required params positional, optional labelled, async + `raise SdkError` | `docs/DECISIONS.md` §12 + ecosystem reference + generated package compile | FROZEN + TEST-T11 |
| deterministic ordering | one deterministic key order for unordered maps (MoonBit `String` shortlex: shorter first, then code unit); canonical sort for derived collections; stable bytes | `tests/test_t13_determinism.py`: repeated runs, reversed spec key order, reversed normalized-model key order, canonical IR collection order, fixed `moon.pkg` import order | FROZEN + TEST-T13 |

## Resolved by T11

- Real HTTP transport API and body handling: verified end to end by driving the
  generated client against the local fixture server.
- Generated operation call shape: positional required parameters, labelled
  optional parameters, async methods raising `SdkError`.
- Deterministic regeneration: verified by hashing two independent generations.
- Capture-vs-network split: one generated method body serves both, selected by
  whether `Client::new` received a `capture` transport.

## Known unresolved evidence gaps

- T12 has not run the generator across a real-world corpus or measured
  supported/rejected operation rates.
- T14 has a Windows workflow file, but it has not yet run on GitHub and there is
  no Linux job.
- Response enums and `UnsupportedMediaType` are modeled but lack an end-to-end
  demo case.

## Contradiction check

Reviewed against `PROJECT_SPEC.md`, `ARCHITECTURE.md`, `SUPPORTED_OPENAPI.md`, `ACCEPTANCE.md`, `DEVELOPMENT_SPEC.md`, and `DEVELOPMENT_TASKS.md` on 2026-09-16. No intentional scope expansion was introduced. The only intentionally unresolved details are marked SPIKE; implementation must not present them as verified capabilities.
