# oas2moon

> OpenAPI 3.0.x → typed MoonBit HTTP client SDK generator.

`oas2moon` converts supported OpenAPI 3.0.x documents into deterministic,
compile-verified MoonBit client SDKs.

## Outcome

```
openapi.yaml / openapi.json
        ↓
     oas2moon generate
        ↓
generated MoonBit client package  ─→  moon fmt + moon check  ─→  typed API calls
```

Target experience:

```moonbit
let client = @petstore.Client::new(
  base_url="https://petstore.example.com",
  auth=@petstore.Auth::bearer(token),
)

let pet = client.get_pet_by_id(id=42)
println(pet.name)
```

## Quick start

```bash
# Generate an SDK from an OpenAPI 3.0 spec
python oas2moon.py generate fixtures/petstore/openapi.json --module petstore --out ./generated/petstore

# The generated package can be compiled and checked
cd generated/petstore
moon fmt --check
moon check --target native --deny-warn
```

### Requirements

- [MoonBit toolchain](https://www.moonbitlang.com/) (`moon` in PATH)
- Python 3.10+
- The three MoonBit packages in `src/` must be built (`moon check` passes)

### CLI usage

```
usage: oas2moon generate [-h] --module MODULE --out OUT input

positional arguments:
  input                  Path to the OpenAPI spec file (.json / .yaml / .yml)

options:
  -h, --help             show this help message and exit
  --module MODULE        MoonBit module name (e.g. 'petstore')
  --out, -o OUT          Output directory for the generated package
```

**Exit codes:**

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Input file not found |
| 2 | Invalid module name |
| 3 | Frontend adapter error (invalid/unparseable spec) |
| 5 | Codegen pipeline failure |
| 6 | Output path is a file, not a directory |

Diagnostics are printed to stderr. The generation summary is printed to stderr
on success.

### What gets generated

For a valid OpenAPI 3.0.x input, `oas2moon generate` produces a MoonBit package
containing:

- `moon.mod` — package metadata
- `moon.pkg` — imports
- `models.mbt` — generated model structs, enums, and JSON codec implementations
- `runtime.mbt` — runtime transport, request/response types, error model
- `config.mbt` — client configuration (base URL, auth credentials)
- `encoding.mbt` — parameter serialization helpers (path, query, header)

## Status

**Stage: V1 in progress** — model generation complete, operation/runtime generation
under development.

| Phase | Scope | Status |
|---|---|---|
| Spike | Feasibility: end-to-end Petstore vertical slice (Python prototype) | ✅ GO |
| Phase 1 | Formal MoonBit frontend adapter + Frontend Model + Support Validation + Canonical Client IR | ✅ COMPLETE |
| Phase 1.5 | MoonBit core IR authority: IR model parsing, validation, naming, type mapping | ✅ COMPLETE |
| Phase 2 | MoonBit model codegen: structs, enums, JSON codecs, Presence[T], Int64, additionalProperties, deterministic regeneration | ✅ COMPLETE |
| Phase 2.5 | Python authority cleanup: MoonBit production path established, Python moved to tests/ | ✅ COMPLETE |
| Phase 3 | Operation/client emitter, HTTP runtime, auth wiring, CLI | 🔄 IN PROGRESS |
| T10 | CLI generate command with input validation, diagnostics, exit codes | ✅ COMPLETE |

### What works today

- **OpenAPI 3.0.0–3.0.3** JSON/YAML parsing via `Han-Wentao/mooncontract`
- **CLI**: `oas2moon generate <input> --module <name> --out <dir>` with
  input validation, stable exit codes, diagnostics to stderr, and generation
  summary
- **Model generation**: structs, enums, arrays, required/optional/nullable fields,
  tri-state `Presence[T]`, Int64 custom codecs, `additionalProperties`, naming
  collision avoidance, reserved-word escaping
- **JSON codecs**: deterministic `ToJson` / `FromJson` implementations for all
  generated types
- **Support validation**: automatic classification of supported, fallback, and
  unsupported features with stable diagnostics
- **Deterministic regeneration**: same input → byte-identical output every time
- **Compile verification**: all generated packages pass `moon fmt --check` and
  `moon check --deny-warn`
- **Test corpus**: 14 targeted model fixtures + 7 CLI integration tests

### What is not yet implemented

- Operation/client method generation (GET/POST/PUT/PATCH/DELETE)
- HTTP path/query/header parameter serialization
- Authentication wiring in generated code (Bearer, Basic, API key)
- HTTP runtime transport adapter
- Real-world API corpus (3+ public specs)
- Windows CI

These are planned V1 features; see `docs/SUPPORTED_OPENAPI.md` for the full
target profile.

## Principles

1. Correct before broad.
2. Generated code must compile.
3. Same input must produce byte-identical output.
4. Generated APIs should feel MoonBit-native.
5. Reuse mature ecosystem components instead of rebuilding infrastructure.
6. Keep a small stable runtime boundary around HTTP transport.

## Repository layout

```
oas2moon/
├── oas2moon.py                    # CLI entry point
├── src/
│   ├── oas2moon/                  # CLI implementation (Python)
│   │   ├── __init__.py
│   │   └── cli.py
│   ├── frontend_adapter/          # OpenAPI parsing → Frontend Model (MoonBit)
│   ├── core_moonbit/              # IR authority, naming, type mapping (MoonBit)
│   ├── codegen_moonbit/           # Canonical IR → MoonBit code emission (MoonBit)
│   └── runtime_moonbit/           # SDK runtime library (MoonBit)
├── tests/
│   ├── reference_python/          # Reference oracle (Python, auxiliary)
│   ├── test_phase1.py             # Frontend/IR/validation tests
│   ├── test_phase1_5.py           # IR authority tests
│   ├── test_phase2.py             # Model codegen tests (14 fixtures)
│   ├── test_t03.py                # GET vertical slice tests
│   └── test_t10_cli.py            # CLI integration tests (7 tests)
├── fixtures/
│   ├── petstore/                  # Main Petstore spec
│   ├── phase2/                    # 14 model codegen fixtures
│   └── unsupported/               # Negative test fixtures
├── tools/
│   └── fixture_server.py          # Local HTTP server for integration tests
├── docs/
│   ├── PROJECT_SPEC.md            # Product definition
│   ├── ARCHITECTURE.md            # System architecture
│   ├── SUPPORTED_OPENAPI.md       # V1 supported profile
│   ├── ACCEPTANCE.md              # Acceptance criteria
│   └── application/               # Competition/hackathon application
├── LICENSE                        # MIT
└── README.md
```

## Implementation language

**MoonBit** is the primary production implementation language. Most code in `src/`
is MoonBit (3 packages, ~2,500 lines). Python code in `src/oas2moon/` serves as
the CLI orchestration layer. Python code in `tests/` serves as test harness,
reference oracle, and fixture server.

## CI

| Platform | Workflow | Status |
|---|---|---|
| Ubuntu (GitHub Actions) | `phase2-ubuntu.yml` | ✅ PASS (moon fmt/check/test + pytest) |
| Windows | Not yet configured | ❌ |

Run tests locally (Windows PowerShell):

```powershell
# CLI integration tests
python tests\test_t10_cli.py

# All Python tests
pytest -q tests

# Individual MoonBit packages
cd src/frontend_adapter && moon fmt --check && moon check --deny-warn && cd ../..
cd src/core_moonbit     && moon fmt --check && moon check --deny-warn && moon test --deny-warn && cd ../..
cd src/codegen_moonbit  && moon fmt --check && moon check --deny-warn && cd ../..
```

## Documents

- [Project Spec](docs/PROJECT_SPEC.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Supported OpenAPI Profile](docs/SUPPORTED_OPENAPI.md)
- [Acceptance Criteria](docs/ACCEPTANCE.md)
- [Feasibility Spike Report](docs/SPIKE_REPORT.md)
- [Phase 1 Report](docs/PHASE1_REPORT.md)
- [Phase 2 Report](docs/PHASE2_REPORT.md)
- [Phase 2.5 Report](docs/PHASE2_5_REPORT.md)
- [Development Plan](docs/DEVELOPMENT_PLAN.md)
- [AGENTS.md](AGENTS.md)

## License

MIT — see [LICENSE](LICENSE).