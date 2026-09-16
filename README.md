# oas2moon

> OpenAPI 3.0.x → typed MoonBit HTTP client SDK generator.

`oas2moon` converts supported OpenAPI 3.0.x documents into deterministic,
compile-verified MoonBit client SDKs that make real HTTP calls.

## Implementation languages

This project is written in two languages, and the split is deliberate:

| Layer | Language | Location | Responsibility |
|---|---|---|---|
| Frontend adapter | **MoonBit** | `src/frontend_adapter/` | Parse OpenAPI 3.0.x JSON/YAML into the project-owned Frontend Model |
| Core / normalizer | **MoonBit** | `src/core_moonbit/` | Support validation, naming, type mapping, Canonical Client IR |
| Codegen | **MoonBit** | `src/codegen_moonbit/` | Emit `models.mbt` + `client.mbt` + `moon.mod` + `moon.pkg` from the IR |
| Runtime | **MoonBit** | `src/runtime_moonbit/` | `SdkError`, request/response, encoding, auth, HTTP transport |
| CLI orchestration | **Python** | `src/oas2moon/cli.py` | Invoke the three stages in order, copy runtime files, run `moon fmt`, map exit codes |
| Demo harness | Python + PowerShell | `demo/petstore/` | Fixture server, hermetic test emitter, end-to-end orchestration |

**The Python layer only orchestrates.** It launches the MoonBit stages as
subprocesses, copies files, and reports results. It does **not** parse OpenAPI,
build the IR, map types, name anything, or generate any SDK code — every one of
those decisions is made in MoonBit, and the generator consumes only the
Canonical Client IR. If the CLI is ever rewritten, the generated output must not
change.

## Outcome

```
openapi.yaml / openapi.json
        ↓
   oas2moon generate          (Python CLI driving three MoonBit stages)
        ↓
generated MoonBit client package  ─→  moon fmt + moon check + moon test  ─→  typed API calls
```

Target experience — this is the shape the generator actually emits today, as
executed by `demo/petstore/run_demo.ps1`:

```moonbit
let client = @petstore.Client::new(
  base_url="https://petstore.example.com",
  bearer_token=token,
)

// required parameters are positional, optional parameters are labelled
let pet = client.get_pet_by_id(42L, "trace-id", verbose=true)
println(pet.name)
```

Operation methods are `async` and report failure by raising `SdkError`; see
`docs/DECISIONS.md` §12 for the evidence behind both choices.

## Quick start

```pwsh
# Generate an SDK from an OpenAPI 3.0 spec
python oas2moon.py generate fixtures/petstore/openapi.json `
  --module oas2moon/petstore_demo --out ./generated/petstore `
  --ir-out ./generated/canonical.json

# The generated package is self-contained: compile and test it in place
cd generated/petstore
moon fmt --check
moon check --target native --deny-warn
moon test  --target native --deny-warn
```

### Requirements

- [MoonBit toolchain](https://www.moonbitlang.com/) (`moon` in `PATH`)
- Python 3.12+
- A C toolchain for the `native` target (MSVC on Windows, `cc` on Linux)

### CLI usage

```
usage: oas2moon generate [-h] --module MODULE --out OUT [--ir-out IR_OUT] input

positional arguments:
  input                  Path to the OpenAPI spec file (.json / .yaml / .yml)

options:
  -h, --help             show this help message and exit
  --module MODULE        MoonBit module name (e.g. 'petstore' or 'my_org/petstore')
  --out, -o OUT          Output directory for the generated package
  --ir-out IR_OUT        Also write the canonical Client IR to this path
```

Both `--input` and `--out` are resolved against the caller's working directory
before any MoonBit stage runs, so relative paths work from anywhere.

**Exit codes** (see `docs/DECISIONS.md` §7):

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Input file missing, or extension is not `.json`/`.yaml`/`.yml` |
| 2 | Invalid MoonBit module name |
| 3 | Frontend adapter error (invalid/unparseable spec) |
| 5 | IR building, codegen, or `moon fmt` failure |
| 6 | `--out` exists and is a file, not a directory |

Diagnostics go to stderr; the generation summary goes to stdout.

### What gets generated

`oas2moon generate` produces a self-contained, flat MoonBit package (see
`docs/DECISIONS.md` §8 for why the runtime is inlined rather than referenced):

| File | Contents |
|---|---|
| `moon.mod` | module name, plus the `moonbitlang/async` dependency when the API has operations |
| `moon.pkg` | imports; owned by the codegen and never rewritten downstream |
| `models.mbt` | generated structs, enums, `Presence[T]`, JSON codecs |
| `client.mbt` | public `Client` and every generated operation method (async) |
| `runtime.mbt` | `SdkError`, `Request`/`Response`, `Transport`, `CaptureTransport` |
| `config.mbt` | base URL and credentials |
| `encoding.mbt` | path/query/header serialization |
| `http_transport.mbt` | the only file that touches `moonbitlang/async/http` |

Generated operations never import the HTTP library: they call
`Client::send_request`, which either replays an injected `CaptureTransport`
(hermetic tests) or performs real HTTP through the runtime transport.

## Status

**Stage: V1 verified for the Petstore profile.** The full pipeline is
implemented and exercised end to end on Windows.

| Task | Scope | Status |
|---|---|---|
| T00 | Contract freeze (`DECISIONS.md`, `EVIDENCE_MATRIX.md`) | ✅ COMPLETE |
| T01 | Canonical Client IR | ✅ COMPLETE |
| T02 | Runtime request/response/transport | ✅ COMPLETE |
| T03 | GET vertical slice | ✅ COMPLETE |
| T04 | Parameter serialization | ✅ COMPLETE |
| T05 | Response strategy | ✅ COMPLETE |
| T06 | Operation codegen | ✅ COMPLETE |
| T07 | CRUD + JSON body | ✅ COMPLETE |
| T08 | Structured errors | ✅ COVERED BY T07 (see `docs/DEVELOPMENT_TASKS.md` §6.1) |
| T09 | Authentication (bearer/basic/apiKey) | ✅ COMPLETE |
| T10 | CLI `generate` | ✅ COMPLETE |
| T11 | Petstore end-to-end demo | ✅ COMPLETE |
| T12 | Real-world corpus & metrics | 🔄 IN PROGRESS (harness done, 3 subsets pending) |
| T13 | Determinism hardening (corpus-wide) | ✅ COMPLETE |
| T14 | Cross-platform CI | 🔄 IN PROGRESS |
| T15 | Release documentation | ⬜ NOT STARTED |

### What works today

- **OpenAPI 3.0.0–3.0.3** JSON/YAML parsing via `Han-Wentao/mooncontract`, with
  local `$ref` resolution
- **CLI**: `oas2moon generate` with input validation, stable exit codes,
  diagnostics, `--ir-out`, and a generation summary
- **Models**: structs, enums, arrays, required/optional/nullable, tri-state
  `Presence[T]`, Int64 codecs, `additionalProperties`, collision avoidance,
  reserved-word escaping
- **Operations**: `async` typed methods for GET/POST/PUT/PATCH/DELETE, path,
  query and header parameters, JSON request bodies, 200/201/204 and multiple
  success statuses
- **Errors**: six-variant `SdkError` carrying `operation_id`; non-2xx becomes
  `Http(op, status, headers, body)`, a missing credential becomes
  `Configuration`
- **Auth**: bearer, basic, API key in header, API key in query — all verified
  against a real server
- **Deterministic regeneration**: same input → byte-identical output
- **Verification**: generated packages pass `moon fmt --check`,
  `moon check --target native --deny-warn`, and `moon test --deny-warn`

### Evidence

The claim above is backed by the demo, not by inspection:

```pwsh
pwsh -NoProfile -File demo/petstore/run_demo.ps1     # 11/11 checks, exit 0
python -m pytest tests -q                            # 69 passed
```

The demo generates through the real CLI, compiles the generated package, runs
its hermetic tests, then drives the generated client against a strict local HTTP
server that validates CRUD, all four auth schemes, and the 404/401/configuration
error paths on the wire. Logs and the raw capture land in
`demo/petstore/_out/`.

### What is not yet implemented

- **Real-world corpus**: the manifest, metrics harness and report exist
  (`corpus/`, `tools/corpus_metrics.py`, `docs/CORPUS_REPORT.md`), but the
  GitHub REST, OpenAI and third-party subsets are still pending, so no
  real-world support rate is claimed yet.
- **Cross-platform CI**: `.github/workflows/demo-windows.yml` runs the demo on
  Windows runners but has not yet executed on GitHub; there is no Linux job yet.
- **Response enums and `UnsupportedMediaType`** are modelled in the IR but have
  no end-to-end demo coverage.
- **Streaming/binary** responses, multipart, XML, OAuth flows, and
  `oneOf`/`anyOf` are out of V1 scope (`docs/SUPPORTED_OPENAPI.md`).

## Principles

1. Correct before broad.
2. Generated code must compile.
3. Same input must produce byte-identical output.
4. Generated APIs should feel MoonBit-native.
5. Reuse mature ecosystem components instead of rebuilding infrastructure.
6. Keep a small stable runtime boundary around HTTP transport.
