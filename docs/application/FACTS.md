# FACTS.md — Repository Fact Audit

> Generated on 2026-09-13 by scanning the real repository at `D:\oas2moon`.

---

## 1. Repository Identity

| Field | Value |
|---|---|
| Remote | `https://github.com/Atman-Angle/oas2moon.git` |
| Branch | `main` (single branch, no open branches or topics) |
| Commits | **14** (all on `main`, all from 2026-09-13) |
| LICENSE | **ABSENT** — no LICENSE file exists |
| README | Present, describes project as "deterministic, compile-verified OpenAPI 3.0.x → typed MoonBit client SDK generator" |

---

## 2. Source Code Structure

### 2.1 MoonBit Production Packages (`src/`)

| Package | Files | Lines | Role |
|---|---|---|---|
| `src/frontend_adapter/` | `main.mbt`, `scan.mbt` | ~789 | OpenAPI 3.0.x parsing via `Han-Wentao/mooncontract` → versioned Frontend Model JSON |
| `src/core_moonbit/` | `main.mbt`, `core_test.mbt`, `core_wbtest.mbt` | ~519 | IR model parsing, validation, naming, type mapping, test support |
| `src/codegen_moonbit/` | `ir.mbt`, `main.mbt` | ~1,230 | Consumes canonical Client IR → generates MoonBit model code (structs, enums, JSON codecs) |
| **Total** | **7 files** | **~2,538** | |

### 2.2 Python Auxiliary Code (`tests/reference_python/oas2moon/`)

| File | Role |
|---|---|
| `__init__.py` | Package init |
| `frontend.py` | Frontend Model Python data classes |
| `ir.py` | Client IR Python data classes |
| `lower.py` | Frontend Model → Client IR normalizer |
| `support.py` | Support validation and diagnostics |
| `naming.py` | Naming conventions |
| `typemap.py` | Schema → type mapping |
| `pipeline.py` | Orchestration (adapter runner) |

**Status**: Moved from `src/oas2moon/` to `tests/reference_python/` in commit `e353355`. All Python code is now auxiliary — reference oracle, test harness, fixture server.

### 2.3 Tests (`tests/`)

| File | Count | Coverage |
|---|---|---|
| `test_phase1.py` | 7 tests | Frontend Model, local refs, IR ordering, naming collisions, diagnostics, unsupported features |
| `test_phase1_5.py` | 2 tests | Phase 1.5 IR authority |
| `test_phase2.py` | 1 test (14 fixtures) | Model generation, deterministic regen, compile, codec round-trip, invalid input |
| `core_moonbit/core_test.mbt` | 5 tests | Type mapping, naming, operation ordering, JSON determinism |
| **Total** | **10 pass + 5 core pass** | |

### 2.4 Fixtures (`fixtures/`)

| Category | Files | Purpose |
|---|---|---|
| `petstore/` | `openapi.json`, `openapi.yaml` | Main Petstore spec for all phases |
| `phase1_5/` | 5 normalized JSON files | Phase 1.5 test data |
| `phase2/` | 14 JSON files | Model generation test corpus |
| `regression/` | 1 JSON file | False positive regression |
| `unsupported/` | 1 JSON file | `oneOf` negative test |

---

## 3. Git Commit History (14 commits)

| # | SHA | Message | Type |
|---|---|---|---|
| 1 | `57b6c3e` | feat: establish oas2moon core and phase 1.5 verification | Core feature |
| 2 | `7f2a1a0` | ci: update MoonBit registry before checks | CI |
| 3 | `c029fb0` | docs: close phase 1.5 with hosted ubuntu verification | Docs |
| 4 | `7ea3597` | docs: remove legacy phase 1.5 verdict label | Docs |
| 5 | `b2bad1e` | feat: Phase 1.5 IR authority and Phase 2 model codegen | Core feature |
| 6 | `2ee009d` | test: Phase 2 fixture corpus and test harness | Test |
| 7 | `8c2c391` | ci: Phase 2 Ubuntu CI integration and report | CI |
| 8 | `ba3214a` | fix: trailing commas in record expressions for Ubuntu MoonBit formatter | Fix |
| 9 | `5531c42` | fix: add missing trailing comma in parse_enum_member record | Fix |
| 10 | `bc6017d` | docs: update PHASE2_REPORT.md with Ubuntu CI results | Docs |
| 11 | `e353355` | refactor: move Python reference pipeline out of production src | Refactor |
| 12 | `b78c23e` | chore: remove obsolete spike generator prototypes | Chore |
| 13 | `346b2c3` | fix: remove trailing commas in record expressions | Fix |
| 14 | `8b26901` | docs: add Phase 2.5 report — Python authority cleanup | Docs |

**Valid functional commits**: 14 (all are meaningful; no merge, WIP, or squash commits). However, commits 3, 4, 10, 14 are purely documentation; commits 2, 7 are CI configuration. Core implementation commits: 1, 5, 6, 8, 9, 11, 12, 13 = **8 core implementation commits**.

---

## 4. CI / GitHub Actions

| Workflow | File | Status |
|---|---|---|
| `phase2-ubuntu` | `.github/workflows/phase2-ubuntu.yml` | ✅ Verified (last run: 34748149239, Ubuntu 24.04) |
| Windows CI | **Not configured** | ❌ |

CI steps executed:
- MoonBit adapter: `moon fmt --check` + `moon check --deny-warn`
- Core authority: `moon fmt --check` + `moon check --deny-warn` + `moon test --deny-warn`
- Codegen emitter: `moon fmt --check` + `moon check --deny-warn`
- pytest all tests: 10 passed on Ubuntu

---

## 5. Implementation Status (VERIFIED / PLANNED / UNKNOWN)

Per `docs/ACCEPTANCE.md` and `docs/SUPPORTED_OPENAPI.md`:

### 5.1 VERIFIED (code exists and passes tests)

- [x] OpenAPI 3.0.0–3.0.3 JSON parsing (via mooncontract)
- [x] Common YAML parsing
- [x] Local `$ref` resolution
- [x] Object → struct generation with JSON codec
- [x] Enum → typed enum with `to_wire()` mapping
- [x] Array typed fields
- [x] Required / Optional / Nullable / Required+Nullable
- [x] Tri-state `Presence[T]` for optional+nullable
- [x] Int64 scalar and array custom codec
- [x] `additionalProperties: true/false` → `Map[String, Json]`
- [x] Primitive scalar mapping (String, Bool, Int, Double, Json)
- [x] Naming collision and reserved word handling
- [x] Deterministic generation (same input → byte-identical output)
- [x] Frontend Model with support validation & diagnostics
- [x] Canonical Client IR
- [x] Diagnostics: `unsupported.keyword`, `ignored.keyword`, `typed_additional_properties.json_fallback`
- [x] Unsupported `oneOf` → stable diagnostic, no code emitted

### 5.2 PLANNED (documented in ACCEPTANCE.md/SUPPORTED_OPENAPI.md, not yet implemented)

- [ ] GET / POST / PUT / PATCH / DELETE operation emitter
- [ ] Path / query / header parameter serialization
- [ ] JSON request body in generated code
- [ ] 200 / 201 / 204 / multiple success status handling
- [ ] Structured non-2xx error
- [ ] Bearer / Basic / API key authentication wiring
- [ ] HTTP runtime transport adapter
- [ ] CLI entry point (`oas2moon generate`)
- [ ] Real-world corpus (3+ public API specs)
- [ ] Cross-platform CI (Windows)
- [ ] HEAD/OPTIONS operations
- [ ] `allOf` support
- [ ] typed `additionalProperties` schema

### 5.3 UNKNOWN / UNCLEAR

- README states "stage: phase1_complete" — but Phase 2 (model codegen) is also complete per `docs/PHASE2_REPORT.md`

---

## 6. Python vs MoonBit Role Summary

| Aspect | MoonBit | Python |
|---|---|---|
| Production location | `src/` | `tests/reference_python/` (auxiliary) |
| Role | **Primary generator** — parsing, IR modeling, code emission | Reference oracle, test harness, support validation |
| Lines of code | ~2,538 (7 files) | ~98,363 bytes (12 files) |
| Final output decision | ✅ MoonBit `codegen_moonbit/main.mbt` generates final `.mbt` files | Python validates/cross-checks but does not generate production code |
| Can the project function without Python? | No — Python runs tests and support validation in the current pipeline | Python is needed for testing, but MoonBit is the production authority |

**Verdict**: MoonBit is the primary implementation language. Python is auxiliary (test harness, reference oracle, support validation). The final MoonBit SDK is generated by MoonBit code.
