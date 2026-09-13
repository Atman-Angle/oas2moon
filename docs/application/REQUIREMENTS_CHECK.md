# REQUIREMENTS_CHECK.md — Competition Requirement Audit

> Generated on 2026-09-13 based on real repository evidence.
> Each requirement is tagged ✅ / ⚠️ / ❌ / ❓ with supporting evidence.

---

## 1. 项目名称 (Project Name)

**Status**: ✅ 满足

**Evidence**: 
- `docs/PROJECT_SPEC.md` title: "Project Spec — oas2moon"
- `README.md` title: "# oas2moon"
- Repository URL: `https://github.com/Atman-Angle/oas2moon`
- `moon.mod` files use `oas2moon/...` naming

**Fixes needed**: README states "Working name" — consider removing this clause if the name is final.

---

## 2. 项目简介 (Project Description)

**Status**: ✅ 满足

**Evidence**:
- `README.md`: "deterministic, compile-verified **OpenAPI 3.0.x → typed MoonBit client SDK generator**"
- `docs/PROJECT_SPEC.md` §1: "converts supported OpenAPI 3.0.x documents into usable typed MoonBit HTTP client SDKs"

The description is concise and clear.

---

## 3. 项目方向与通用性 (Direction & Generality)

**Status**: ✅ 满足

**Evidence**:
- **Not** bound to a specific API — the generator accepts any OpenAPI 3.0.x document
- `docs/SUPPORTED_OPENAPI.md` defines a generic supported profile
- Tested with Petstore fixture (industry-standard OpenAPI example)
- 14 diverse fixture specs in `fixtures/phase2/` test various schema patterns
- Architecture (`docs/ARCHITECTURE.md`) is designed for generic OpenAPI → MoonBit transformation

**Risk**: V1 scope is deliberately narrow. The current implementation only covers model generation. Operation/client generation is not yet started. This doesn't affect generality direction, only completeness.

---

## 4. 至少 3 个完整使用场景 (≥3 Complete Use Cases)

**Status**: ⚠️ 部分满足

**Evidence**:
- `docs/PROJECT_SPEC.md` §2 describes one use case (developer manually implementing REST client)
- The generated Petstore SDK demonstrates one scenario (Petstore CRUD)
- No dedicated "Use Cases" section exists in any document

**Gap**: The project has one implicit use case. For a competition application, at least 3 **distinct** scenarios need to be described (e.g., consuming a cloud API, generating a microservice client, creating a type-safe SDK for a startup's API). These exist conceptually but are not documented.

---

## 5. 核心功能 (Core Features)

**Status**: ⚠️ 部分满足 (what's documented ≠ what's implemented)

**Documented in `docs/SUPPORTED_OPENAPI.md`**:
- Versions, input format, schema, operations, parameters, request body, responses, authentication, servers

**Actually implemented (VERIFIED by code)**:
- ✅ OpenAPI 3.0.x JSON/YAML parsing
- ✅ Object/enum/array struct generation with JSON codec
- ✅ Required/optional/nullable/tri-state
- ✅ Int64, naming collision, additionalProperties
- ✅ Support validation and diagnostics
- ✅ Deterministic generation
- ✅ Canonical Client IR

**Not yet implemented (listed as V1 scope but code absent)**:
- ❌ Operation/client method generation (GET/POST/PUT/PATCH/DELETE)
- ❌ HTTP parameter serialization
- ❌ Auth wiring in generated code
- ❌ CLI tool
- ❌ HTTP runtime transport

**Risk**: The documented V1 scope is broader than current implementation. The application must clearly distinguish what is implemented vs planned.

---

## 6. 原创 / 移植 / 参考说明 (Originality / Port / Reference)

**Status**: ❌ 不满足

**Evidence**:
- No LICENSE file exists
- No "Open Source References" or "Acknowledgments" section exists in the repository
- Dependencies with open-source licenses are not documented:
  - `Han-Wentao/mooncontract` (OpenAPI parser)
  - `moonbitlang/async` (HTTP)
  - `moonbitlang/x` (stdlib)
  - `moonbit-community/yaml` (YAML parser)
- The project uses a **distinct architecture** (Frontend Model → Support Validation → Canonical Client IR → Codegen) that differs from OpenAPI Generator's approach
- No statement about whether the project is original or references existing tools

**Required**: Add a LICENSE file and a references section documenting all dependencies and any architectural inspiration.

---

## 7. 参考项目、链接与许可证 (Reference Projects, Links & Licenses)

**Status**: ❌ 不满足

**Evidence**:
- **No LICENSE file** in repository root
- Dependencies used:
  | Dependency | License (per mooncakes/pkg.go.dev) |
  |---|---|
  | `Han-Wentao/mooncontract` | Not declared in repo |
  | `moonbitlang/async` | MIT (moonbitlang standard) |
  | `moonbitlang/x` | MIT |
  | `moonbit-community/yaml` | Not declared |
- No dependency license documentation in the repository

---

## 8. GitHub 仓库 (GitHub Repository)

**Status**: ✅ 满足

**Evidence**:
```
git remote -v
origin  https://github.com/Atman-Angle/oas2moon.git (fetch)
origin  https://github.com/Atman-Angle/oas2moon.git (push)
```

Repository URL: `https://github.com/Atman-Angle/oas2moon`

---

## 9. 不少于 10 个有效 commits (≥10 Meaningful Commits)

**Status**: ✅ 满足

**Evidence**:
```
14 commits total on main branch (2026-09-13)
```
All 14 commits are functional/meaningful:
- 2 core feature commits
- 2 CI commits  
- 3 fix commits
- 1 refactor commit
- 1 chore commit
- 5 docs commits

No merge commits, WIP commits, or squash commits found.

---

## 10. MoonBit 为项目主要实现语言 (MoonBit as Primary Language)

**Status**: ✅ 满足

**Evidence**:
- **Production code** (`src/`): 100% MoonBit (7 `.mbt` files, ~2,538 lines)
- **Python code**: Located in `tests/reference_python/` (auxiliary — test harness, reference oracle)
- Python code moved out of `src/` to `tests/` in commit `e353355` specifically to clarify MoonBit as the primary language
- After Phase 2.5 cleanup: MoonBit ≈ 106 KB > Python ≈ 98 KB in tracked bytes
- GitHub language detection expected to show MoonBit as primary after push
- The final code generation is done by `src/codegen_moonbit/main.mbt` (MoonBit), not by Python

**Risk**: GitHub may temporarily show Python as primary until the latest commits are pushed and re-scanned.

---

## Summary Table

| # | Requirement | Status | Notes |
|---|---|---|---|
| 1 | Project name | ✅ | "oas2moon" |
| 2 | Project description | ✅ | Clear and concise |
| 3 | Direction & generality | ✅ | Generic OpenAPI → MoonBit, not API-specific |
| 4 | ≥3 use cases | ⚠️ | Only 1 implicit; needs documentation |
| 5 | Core features | ⚠️ | Documented scope > implemented scope |
| 6 | Originality/port statement | ❌ | No statement, no LICENSE |
| 7 | References & licenses | ❌ | No LICENSE, no dependency license docs |
| 8 | GitHub repo | ✅ | Public, correctly configured |
| 9 | ≥10 commits | ✅ | 14 meaningful commits |
| 10 | MoonBit primary | ✅ | MoonBit in `src/`, Python in `tests/` |
