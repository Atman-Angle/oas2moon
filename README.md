# oas2moon

> OpenAPI 3.0.x → typed MoonBit HTTP client SDK generator.

`oas2moon` converts supported OpenAPI 3.0.x documents into deterministic,
compile-verified MoonBit client SDKs.

## Outcome

```
openapi.yaml / openapi.json
        ↓
     oas2moon
        ↓
generated MoonBit client package
        ↓
moon fmt + moon check
        ↓
typed API calls
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
| Phase 3 | Operation/client emitter, HTTP runtime, auth wiring, CLI | 🔄 NOT STARTED |

### What works today

- **OpenAPI 3.0.0–3.0.3** JSON/YAML parsing via `Han-Wentao/mooncontract`
- **Model generation**: structs, enums, arrays, required/optional/nullable fields, tri-state `Presence[T]`, Int64 custom codecs, `additionalProperties`, naming collision avoidance, reserved-word escaping
- **JSON codecs**: deterministic `ToJson` / `FromJson` implementations for all generated types
- **Support validation**: automatic classification of supported, fallback, and unsupported features with stable diagnostics
- **Deterministic regeneration**: same input → byte-identical output every time
- **Compile verification**: all generated packages pass `moon fmt --check` and `moon check --deny-warn`
- **Test corpus**: 14 targeted fixtures covering all model surfaces

### What is not yet implemented

- Operation/client method generation (GET/POST/PUT/PATCH/DELETE)
- HTTP path/query/header parameter serialization
- Authentication wiring in generated code (Bearer, Basic, API key)
- HTTP runtime transport adapter
- CLI entry point (`oas2moon generate`)
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
├── src/                          # MoonBit production packages
│   ├── frontend_adapter/         # OpenAPI parsing → Frontend Model
│   ├── core_moonbit/             # IR authority, naming, type mapping
│   └── codegen_moonbit/          # Canonical IR → MoonBit code emission
├── tests/
│   ├── reference_python/         # Reference oracle (Python, auxiliary)
│   ├── test_phase1.py            # Frontend/IR/validation tests
│   ├── test_phase1_5.py          # IR authority tests
│   └── test_phase2.py            # Model codegen tests (14 fixtures)
├── fixtures/
│   ├── petstore/                 # Main Petstore spec
│   ├── phase2/                   # 14 model codegen fixtures
│   └── unsupported/              # Negative test fixtures
├── tools/
│   └── fixture_server.py         # Local HTTP server for integration tests
├── docs/
│   ├── PROJECT_SPEC.md           # Product definition
│   ├── ARCHITECTURE.md           # System architecture
│   ├── SUPPORTED_OPENAPI.md      # V1 supported profile
│   ├── ACCEPTANCE.md             # Acceptance criteria
│   └── application/              # Competition/hackathon application
├── LICENSE                       # MIT
└── README.md
```

## Implementation language

**MoonBit** is the primary production implementation language. All code in `src/`
is MoonBit (3 packages, ~2,500 lines). Python code in `tests/reference_python/`
serves an auxiliary role: test harness, reference oracle, fixture server.

## CI

| Platform | Workflow | Status |
|---|---|---|
| Ubuntu (GitHub Actions) | `phase2-ubuntu.yml` | ✅ PASS (moon fmt/check/test + pytest) |
| Windows | Not yet configured | ❌ |

Run tests locally (Windows PowerShell):

```powershell
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
