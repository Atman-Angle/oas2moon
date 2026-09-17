# Petstore end-to-end demo

This demo takes one OpenAPI 3.0.3 document through the **product entry point**
(`oas2moon generate`) and proves the result works: the generated MoonBit package
compiles, its unit tests pass, and the generated client performs correct HTTP
against a real local server.

It is the T11 gate. It fails loudly instead of printing a happy summary when a
wire contract is violated.

## Prerequisites

| Tool | Notes |
|------|-------|
| MoonBit toolchain (`moon`) | Fetches `moonbitlang/async@0.20.2` |
| Python 3.12+ (`python`) | Runs the CLI, the fixture server, and the test emitter |
| PowerShell 7 (`pwsh`) | Runs the orchestrator |

Every path is derived from the script's own location, so the demo can be
launched from any working directory and contains no machine-specific paths.

## Run it

```pwsh
pwsh -NoProfile -File demo/petstore/run_demo.ps1
```

Optional knobs:

```pwsh
pwsh -NoProfile -File demo/petstore/run_demo.ps1 -Port 18090 -Token my-token
```

Exit code is `0` when every check passes, `1` otherwise.

## What the demo proves

| # | Stage | Evidence |
|---|-------|----------|
| 1 | `generate` | `oas2moon generate` runs frontend → Canonical Client IR → codegen |
| 2 | tests | hermetic unit tests are added to the generated package |
| 3 | `moon fmt` | `moon fmt --check` is clean |
| 4 | `moon check` | `moon check --target native --deny-warn` is clean |
| 5 | `moon test` | 7 generated tests pass through `CaptureTransport`, no sockets |
| 6 | local server | strict fixture server records every request |
| 7 | typed GET | path + query + header asserted by the server, typed `Pet` returned |
| 8 | JSON POST | `Content-Type`, body shape, enum wire value and omitted optionals asserted |
| 9 | DELETE + 204 | empty body accepted, client returns `Unit` |
| 10 | auth | **bearer, basic, api-key header and api-key query** all accepted on the wire |
| 11 | errors | 404 → `Http(op, 404, …)`, 401 → `Http(op, 401, …)`, missing credential → `Configuration` |
| 12 | determinism | a second generation hashes byte-identically |

The HTTP steps are performed by the **generated MoonBit client**, not by a
Python HTTP client. The server independently validates the wire shape, so a bug
in code generation cannot be masked by a permissive test.

## Layout

```
demo/petstore/
├── openapi.json        OpenAPI 3.0.3 input (Petstore CRUD + one op per auth scheme)
├── fixture_server.py   strict local HTTP server with request capture
├── gen_tests.py        adds hermetic unit tests to a generated package
├── integration/        MoonBit driver that imports the generated SDK
│   ├── moon.pkg
│   └── main.mbt
├── run_demo.ps1        orchestrator (steps 1-12 above)
└── README.md
```

`_out/` is created at run time and is git-ignored:

```
_out/
├── canonical.json              canonical Client IR, via `--ir-out`
├── generated/                  the generated SDK package
│   ├── moon.mod  moon.pkg      owned by the codegen
│   ├── models.mbt              structs, enums, JSON codecs
│   ├── client.mbt              typed async operations
│   ├── runtime.mbt             errors, request/response, CaptureTransport
│   ├── config.mbt              base URL and credentials
│   ├── encoding.mbt            path/query/header serialization
│   ├── http_transport.mbt      the only file that touches async/http
│   ├── petstore_test.mbt       hermetic unit tests
│   └── integration/            copied driver (not generator output)
├── determinism/                second generation used for the hash diff
├── server_capture.json         every request the server actually received
└── logs/                       per-command output, kept for review
```

## Architecture notes

**Parser models never reach codegen.** The CLI wires `frontend_adapter` →
`core_moonbit` → `codegen_moonbit`; the emitter consumes only the Canonical
Client IR.

**Transport stays behind one boundary.** Generated operations call
`Client::send_request`, which either replays an injected `CaptureTransport`
(hermetic tests, no sockets) or delegates to `transmit` in
`http_transport.mbt`. Generated code never imports `moonbitlang/async/http`.

**Tests belong to whoever wants them.** The generator ships no test files, so a
package without tests cannot carry an unused test-only import;
`gen_tests.py` adds both the tests and the import they need.

**Determinism.** Each generation starts from a clean directory. The orchestrator
hashes every file the generator writes at the package root (the IR copy
included) and compares two runs byte for byte. Build output and the copied
driver are never hashed, because they are not generator artifacts.

## Reproducing a single stage by hand

```pwsh
# generate through the product entry point
python oas2moon.py generate demo/petstore/openapi.json `
  --module oas2moon/petstore_demo --out demo/petstore/_out/generated `
  --ir-out demo/petstore/_out/canonical.json

# add hermetic tests, then compile and run them
python demo/petstore/gen_tests.py demo/petstore/_out/canonical.json demo/petstore/_out/generated
cd demo/petstore/_out/generated
moon fmt --check
moon check --target native --deny-warn
moon test  --target native --deny-warn

# run only the real-HTTP driver (server must already be listening)
moon run integration --target native -- `
  http://127.0.0.1:18080 demo-token demo-user demo-pass demo-api-key
```

To run the fixture server on its own:

```pwsh
python demo/petstore/fixture_server.py --port 18080 --token demo-token `
  --capture demo/petstore/_out/manual_capture.json
```

## Reading the capture

`server_capture.json` separates three kinds of fact:

| Field | Meaning |
|-------|---------|
| `checks` | wire expectations the server verified |
| `errors` | contract violations — the demo fails if this is non-empty |
| `rejections` | credentials the server deliberately refused |

The demo asserts `errors` is empty and `rejections` has exactly one entry: the
wrong-token probe, which exists to prove a rejected credential becomes
`SdkError.Http` instead of crashing.

## Known limitations

- The demo covers the Petstore subset only: CRUD on `/pets` plus one operation
  per auth scheme. It is not a coverage claim for the whole V1 profile.
- The fixture server binds to loopback; it is not a general mock server.
- The generated package targets `native` only, matching
  `src/runtime_moonbit/moon.pkg`.
- Hosted CI is `.github/workflows/cross-platform-ci.yml`. The accessible run
  for commit `040f488` passed `Verify (Ubuntu)` and `Verify (Windows)`:
  https://github.com/Atman-Angle/oas2moon/actions/runs/35177945624. It verifies
  this checked fixture profile, not every OpenAPI document.
