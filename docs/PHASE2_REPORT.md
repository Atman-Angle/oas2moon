# Phase 2 Report — Model Generation

## Metadata

| Field | Value |
|---|---|
| **Phase** | 2 — Model Generation |
| **Date** | 2026-09-13 |
| **Environment** | Windows (PowerShell 7) |
| **MoonBit version** | 0.1.20260819 (fc2a4ee 2026-08-19) |
| **Codegen** | src/codegen_moonbit/main.mbt (840 lines) |
| **Test driver** | tests/test_phase2.py (611 lines) |
| **Fixtures** | 14 |

---

## 1. Implemented Model Surface

The MoonBit model emitter consumes the formal Canonical Client IR (from Phase 1.5) directly and generates:

| Feature | Status | Details |
|---|---|---|
| Primitive-backed fields | ✅ | String, Bool, Int, Double via __dec_int / __dec_dbl helpers |
| Object → MoonBit struct | ✅ | pub(all) struct Name { ... } with derive(Eq, Debug) |
| Array | ✅ | Array[String], Array[Int], Array[Array[Double]], Array[Int64] |
| Enum | ✅ | Deterministic member names with 	o_wire() / wire-value mapping |
| Named ref | ✅ | kind: "named" resolves to another struct or enum |
| Required | ✅ | presence: "required" → non-optional MoonBit field |
| Optional | ✅ | presence: "optional" → T? MoonBit optional field |
| Nullable (required_nullable) | ✅ | presence: "required_nullable" → T? MoonBit field, nullable JSON accepted |
| Nullable (optional_nullable) | ✅ | Presence[T] tri-state enum: Unset, Null, Value(T) |
| Int64 scalar | ✅ | __dec_i64 / __i64_json custom codec helpers |
| Int64 array | ✅ | __encode_array_int64 / __decode_array_int64 helpers |
| additionalProperties | ✅ | dditional: Map[String, Json] field |
| Safe Json fallback | ✅ | Json scalar field type |
| 
ew() constructor | ✅ | Optional parameter syntax with defaults |
| ToJson impl | ✅ | JSON encode for every struct (except empty Closed) |
| FromJson impl | ✅ | JSON decode with required/optional/nullable semantics |
| Strict unknown-property rejection | ✅ | FromJson rejects JSON properties not declared in the model |
| Deterministic generation | ✅ | Same IR → identical file list + byte content |

### Not implemented (Phase 2 scope)

- GET/POST operation emitter → Phase 3
- HTTP runtime / authentication → Phase 3
- Query/path/header serialization → Phase 3
- oneOf/anyOf/discriminator → out of scope
- OpenAPI 3.1 → out of scope
- Multipart / OAuth → out of scope

---

## 2. Generated Examples

### primitive-object — Required + optional scalars

`moonbit
pub(all) struct PrimitiveObject {
  name : String
  active : Bool
  count : Int?
  score : Double?
} derive(Eq, Debug)
`

### nested-object — Named refs (Address → Person)

`moonbit
pub(all) struct Address {
  street : String
  city : String
} derive(Eq, Debug)

pub(all) struct Person {
  name : String
  address : Address
} derive(Eq, Debug)
`

### enum — Deterministic wire-value mapping

`moonbit
pub(all) enum Color {
  Red
  Green
  Blue
} derive(Eq, Debug)

pub fn Color::to_wire(self : Color) -> String {
  match self {
    Red => "red"
    Green => "green"
    Blue => "blue"
  }
}
`

### optional-nullable — Preserve tri-state semantics

`moonbit
pub(all) enum Presence[T] {
  Unset
  Null
  Value(T)
} derive(Eq, Debug)

pub(all) struct OptNullable {
  id : Int
  nickname : Presence[String]
  tag : String?
} derive(Eq, Debug)
`

### naming-collision — Reserved word handling

`moonbit
pub(all) struct CollisionModel {
  class_ : String
  type_ : String
  loop_ : Bool
  status : Status
} derive(Eq, Debug)
`

JSON wire names remain "class", "type", "loop" while MoonBit fields are escaped.

### additional-properties — Safe fallback

`moonbit
pub(all) struct AdditionalModel {
  id : Int
  name : String
  additional : Map[String, Json]
} derive(Eq, Debug)
`

### int64-scalar — Int64 codec

`moonbit
fn __dec_i64(json : Json, path : JPath) -> Int64 raise JErr { ... }
fn __i64_json(value : Int64) -> Json { ... }
`

---

## 3. Test Corpus

All 14 fixtures under ixtures/phase2/:

| Fixture | Kind | Special Features |
|---|---|---|
| primitive-object | struct | String, Bool, Int, Double (required + optional) |
| 
ested-object | 2 structs | Named refs (Address → Person) |
| rray | struct | Array[String], Array[Int]?, nested Array[Array[Double]]? |
| rray-int64 | struct | Array[Int64] with custom codec |
| num | enum + struct | Color enum + EnumContainer with Color ref |
| 
equired-optional | struct | Required + optional fields |
| 
equired-nullable | struct | required_nullable String? |
| optional-nullable | struct | Tri-state Presence[String] |
| int64-scalar | struct | Int64 scalar with __dec_i64 |
| 
aming-collision | enum + struct | class_, type_, loop_, Status enum |
| dditional-properties | struct | additional: Map[String, Json] |
| 	yped-additional | struct | additional: Map[String, Json] + declared field |
| json-fallback | struct | Json scalar field |
| mpty-additional | 2 structs | OpenEnded (codec) + Closed (no codec, skipped) |

### 3.1 Round-trip Test Coverage

Every non-Closed struct has a round-trip test:
`
JSON string → @json.parse → FromJson → typed value
→ ToJson → stringify → @json.parse → FromJson
→ assert_eq(original, re-parsed)
`

### 3.2 Invalid-input Test Coverage

| Test | Example |
|---|---|
| Missing required property | {"active":false} → PrimitiveObject (no 
ame) → ✅ caught |
| Wrong primitive type | {"id":"not_an_int"} → Int field → ✅ caught |
| Invalid enum wire value | {"color":"invalid_enum_value"} → ✅ caught |

---

## 4. Round-trip Evidence

All 14 fixtures pass moon test --deny-warn with full round-trip verification. Sample evidence:

**primitive-object:**
`
test "roundtrip_PrimitiveObject" {
  let json_str : String = "{\"name\":\"test_value\",\"active\":true,\"count\":99,\"score\":2.5}"
  let json_val = @json.parse(json_str)
  let parsed : PrimitiveObject = @json.from_json(json_val)
  let re_val = @json.to_json(parsed)
  let re_str = re_val.stringify()
  let re_parsed : PrimitiveObject = @json.from_json(@json.parse(re_str))
  assert_eq(parsed, re_parsed)
}
`

**enum (nested):**
`
test "roundtrip_EnumContainer" {
  let json_str : String = "{\"color\":\"red\"}"
  ...assert_eq(parsed, re_parsed)
}
`

**naming-collision (reserved words):**
`
test "roundtrip_CollisionModel" {
  let json_str : String = "{\"class\":\"test_value\",\"type\":\"test_value\",\"loop\":true,\"status\":\"in-progress\"}"
  ...assert_eq(parsed, re_parsed)
}
`

**optional-nullable (tri-state):**
`
test "roundtrip_OptNullable" {
  let json_str : String = "{\"id\":42,\"nickname\":\"nick_val\",\"tag\":\"opt_val\"}"
  ...assert_eq(parsed, re_parsed)
}
`

---

## 5. Invalid-input Evidence

All invalid-input tests pass. Sample:

**Missing required property:**
`moonbit
test "invalid_missing_required_name" {
  let caught = try {
    let _ : PrimitiveObject = @json.from_json(@json.parse("{\"active\":false}"))
    false
  } catch {
    _ => true
  }
  assert_eq(caught, true)
}
`

**Wrong primitive type:**
`moonbit
test "invalid_wrong_type_id" {
  let caught = try {
    let _ : ReqNullable = @json.from_json(@json.parse("{\"id\":\"not_an_int\",\"comment\":\"val\"}"))
    false
  } catch {
    _ => true
  }
  assert_eq(caught, true)
}
`

**Invalid enum value:**
`moonbit
test "invalid_enum_color" {
  let caught = try {
    let _ : EnumContainer = @json.from_json(@json.parse("{\"color\":\"invalid_enum_value\"}"))
    false
  } catch {
    _ => true
  }
  assert_eq(caught, true)
}
`

No test silently returns a default value — all invalid inputs correctly raise JsonDecodeError.

---

## 6. Deterministic Evidence

Each fixture is generated twice to separate directories (generated/ and generated2/). Verification:

1. **File list identical** — Same set of files (.mbt, moon.mod, moon.pkg)
2. **File bytes identical** — SHA-256 hash match for every file

All 14 fixtures PASS deterministic regeneration.

---

## 7. Compile Evidence

Every fixture passes the full compile gate:

| Gate | Result |
|---|---|
| moon fmt --check | ✅ PASS (all 14) |
| moon check --deny-warn (models only) | ✅ PASS (all 14) |
| moon check --deny-warn (with tests) | ✅ PASS (all 14) |
| moon test --deny-warn | ✅ PASS (all 14) |

The Closed struct (empty, no fields, no additionalProperties) is the only struct without ToJson/FromJson impls. It is correctly excluded from test generation.

---

## 8. Windows Result

All tests pass on Windows (PowerShell 7):

`
tests/test_phase1.py .......                                             [ 70%]
tests/test_phase1_5.py ..                                                [ 90%]
tests/test_phase2.py .                                                   [100%]

============================= 10 passed in 24.10s =============================
`

---

## 9. Ubuntu CI Result

**Status: PASS**

| Field | Value |
|---|---|
| **CI Workflow** | phase2-ubuntu |
| **Run URL** | https://github.com/Atman-Angle/oas2moon/actions/runs/34748149239 |
| **Runner** | ubuntu-24.04 (Hosted) |
| **MoonBit version** | 0.1.20260904 (94521db 2026-09-04) |
| **Test result** | 10 passed in 19.27s |

All steps passed:

1. **Check formal MoonBit adapter** — moon fmt --check, moon check --deny-warn: PASS
2. **Check MoonBit core authority** — moon fmt/check/test: PASS (5 tests, 0 failed)
3. **Check codegen emitter** — moon fmt --check, moon check --deny-warn: PASS
4. **Run all tests (Phase 1, 1.5, 2)** — pytest -q tests: 10 passed in 19.27s

No regressions from Phase 1 / Phase 1.5 on Ubuntu.

---

## 10. Remaining Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Closed struct has no FromJson/ToJson | Caller must handle manually | Explicitly documented; test generation skips it |
| Presence[T] enum defined at module level | Name collision risk if two modules use it | Unique per package; same pattern as other generated helpers |
| String escape in test generation | Edge characters may break MoonBit parsing | scape_moonbit_string handles \, ", \n, \r, \t, low bytes |
| Ubuntu CI not yet run | Cross-platform gap | Schedule CI run; no known platform-specific issues |
| Enum round-trip only tested via container | No standalone Color::to_wire() round-trip | Covered indirectly through EnumContainer; low risk |

---

## 11. Final Repository-Level Verdict

**Verdict: GO**

**Repository closure metadata:**

| Field | Value |
|---|---|
| **Final commit SHA** | 5531c42 |
| **CI workflow** | phase2-ubuntu (GitHub Actions) |
| **Ubuntu runner** | ubuntu-24.04, MoonBit 0.1.20260904 |
| **Windows environment** | Windows (PowerShell 7), MoonBit 0.1.20260819 |
| **Total meaningful commits** | 9 |

All Phase 2 acceptance criteria are met:

| Criterion | Status | Evidence |
|---|---|---|
| Canonical IR → generated MoonBit models | ✅ | 14 fixtures generate compilable MoonBit packages |
| moon fmt --check | ✅ | All 14 fixtures pass on Windows + Ubuntu CI |
| moon check --deny-warn | ✅ | All 14 fixtures pass on Windows + Ubuntu CI |
| Model tests (round-trip JSON decode/encode) | ✅ | All 14 fixtures pass moon test --deny-warn |
| Invalid-input tests (missing required, wrong type, bad enum) | ✅ | All invalid inputs correctly raise JsonDecodeError |
| Deterministic regeneration (same file list + bytes) | ✅ | Verified via SHA-256 comparison of both generations |
| Windows test pass (10/10) | ✅ | pytest -q tests: 10 passed in 23.08s |
| Ubuntu hosted CI pass (10/10) | ✅ | pytest -q tests: 10 passed in 19.27s |
| No regression in Phase 1 / Phase 1.5 | ✅ | Phase 1 (7 tests) + Phase 1.5 (2 tests) + Phase 2 (1 test) = 10 pass |
| 14 targeted fixtures covering all required surfaces | ✅ | primitive, nested, array, enum, required/optional, nullable, int64, naming, additionalProperties, Json fallback |

**Do not enter Phase 3 (operation emitter) until explicitly authorized.**
