# Feasibility Spike Report — oas2moon

> **Historical record, not current release evidence.** This report preserves
> the 2026-09-13 feasibility investigation. Its former runner scripts were
> removed because they invoked a deleted spike generator; use
> `docs/ACCEPTANCE.md`, `demo/petstore/run_demo.ps1`, and the hosted CI workflow
> for current evidence.

Date: 2026-09-13
Repository: `D:\oas2moon`

Verdict: **GO**

This round built and executed a minimal end-to-end prototype, not a repository
audit. Everything below is measured output from this machine; no claim is
carried over from the older research notes.

Reproduce the whole chain with one command:

```powershell
pwsh -NoProfile -File spike\run_spike.ps1
```

Last run: `SPIKE_EXIT=0`, nine steps PASS. Transcript:
`spike/build/spike_transcript.txt`.

## Verdict

**GO.** The complete required chain ran and passed on Windows:

```text
OpenAPI 3.0.3 Petstore fixture
  -> frontend adapter (Han-Wentao/mooncontract 0.1.0)
  -> local $ref resolution
  -> normalized Frontend Model
  -> Support Validation
  -> Client IR
  -> Naming / Type Mapping
  -> MoonBit codegen (10 files)
  -> moon fmt --check / moon check / moon test
  -> generated client -> real local HTTP server
  -> GET / POST / DELETE + typed decode
  -> byte-identical regeneration
```

The verdict is `GO` and not `CONDITIONAL_GO` because every item of
`docs/ACCEPTANCE.md` section A was demonstrated by execution, and the remaining
gaps are bounded feature work inside the planned V1 scope, not unknown
infrastructure.

| `docs/ACCEPTANCE.md` §A item | Evidence | Result |
|---|---|---|
| Petstore OpenAPI 3.0 parses | frontend step, exit 0, 6477-byte Frontend Model | PASS |
| common YAML path works | `openapi.yaml` twin normalizes to byte-identical model | PASS |
| local `$ref` resolves | `Pet.status` -> `PetStatus`; 200/201 -> `Pet`; request body -> `Pet` | PASS |
| object/enum/array/optional/nullable → valid MoonBit | `Pet` struct + `PetStatus` enum + `Array[String]?` compile | PASS |
| ≥3 operations generate | `getPetById`, `addPet`, `deletePet` | PASS |
| generated package passes `moon fmt` | `moon fmt --check` exit 0 | PASS |
| generated package passes `moon check` | `moon check --target native --deny-warn` exit 0 | PASS |
| GET/POST/DELETE against a real local server | 3 requests, 11 wire checks, 0 errors | PASS |
| method/path/query/header/body asserted | server-side capture assertions | PASS |
| typed response decode asserted | typed client report + 4 generated `moon test` cases | PASS |
| same input twice → byte-identical trees | 10 files, per-file SHA-256 + aggregate + report equality | PASS |
| no large missing infrastructure must be built first | dependency audit; only a 10-file SDK package, one fixture server, three PowerShell drivers were added | PASS |
| fresh duplicate scan, no mature direct equivalent | mooncakes (2427 modules) + GitHub search, 2026-09-13 | PASS |

## Environment

| Item | Value |
|---|---|
| OS | Microsoft Windows 11 家庭版 中文版, `Microsoft Windows NT 10.0.26200.0` |
| Shell | PowerShell (`pwsh`) 7.6.5 |
| `moon` | `0.1.20260819 (fc2a4ee 2026-08-19)` |
| `moonc` | `v0.10.9+6e6c44045 (2026-08-19)`, feature flags `rr_moon_mod,rr_moon_pkg` |
| `moonfmt` | `C:\Users\李子睿Atman\.moon\bin\moonfmt.exe` |
| Python | 3.13.7 (generator + fixture server) |
| git | 2.53.0.windows.2 |
| Workspace | `D:\oas2moon`, **not** a git repository (`git rev-parse` → fatal) |
| Verified target | `native` only (generated packages pin `supported_targets = "+native"`) |

No credentials, network services, or external state were used. The fixture
server binds `127.0.0.1:18080` on loopback only.

## Dependency audit

Versions were read live from `https://mooncakes.io/api/v0/modules` and from
local checkouts under `.spike-deps/` on 2026-09-13. Nothing here is taken from
`docs/RESEARCH.md`.

| Dependency | Live evidence | Spike use | Finding |
|---|---|---|---|
| `Han-Wentao/mooncontract` | latest `0.1.0` (only version); checkout `a38d9c8a8a4790179e65be3c4aaac33c675545d3` (2026-07-24, "prepare 0.1.0 release"); deps `moonbit-community/yaml@0.0.6`, `moonbitlang/x@0.4.46`, `moonbitlang/async@0.20.2`; `preferred_target = "wasm-gc"` | **Used** as the OpenAPI frontend: `parse_json` / `parse_yaml` -> `Result[OpenApiDoc, Array[Diagnostic]]` | Real parser with operations, parameters, request bodies, responses, schemas, local `$ref` paths. Sufficient to avoid writing a parser. Silent about several keywords (see Hidden blockers). |
| `moonbit-community/yaml` | latest `0.0.6`; pulled in both directly and through mooncontract | **Used** for the YAML twin: `@yaml.Yaml::load_from_string` -> `@json.to_json` | Works. YAML path produced a byte-identical Frontend Model. |
| `moonbitlang/async` | latest `0.21.3` | **Pinned to `0.20.2`** in generated packages | **Latest is unusable with the installed compiler.** `moon check` on a package importing `moonbitlang/async@0.21.3` fails with 3 parse errors in `.mooncakes/moonbitlang/async/src/internal/coroutine/async_primitive.mbt` (`Unit noraise + nocancel`, `nocancel`, `capture_cancellation`). `0.20.6` and `0.20.3` check clean. Evidence trees: `spike/build/gen_async213` (fails), `spike/build/gen_async_0206` (passes, including integration). |
| `moonbit-community/elasticsearch` | latest `0.1.0`, repo `github.com/moonbit-community/elasticsearch.mbt`, checkout `f62e13df11df9db9e56ed0ed4c9e39b2d15494c2`; deps `moonbitlang/async@0.20.2`; `preferred_target = "native"` | **Reference only** | Generated `Client::*` async methods returning typed responses over `moonbitlang/async/http`. Proves the "generated code over a typed transport layer" architecture is the ecosystem norm, and that pinning async is normal practice. Service-specific; not a generic generator. |
| `mizchi/codegen` | latest `0.2.3`, repo `github.com/mizchi/codegen.mbt`, keywords `codegen,ir,ast`, no deps | **Not used** | A generic IR/codegen library for MoonBit programs. The spike emitter is a deterministic Python renderer; this package becomes relevant only if codegen moves into MoonBit. Not needed for feasibility. |
| `Lfan-ke/moonctl` | latest `0.7.0`, checkout `7d4ad7fd06bbf2a68dbb90b8b4da545c51e86110` (2026-08-31) | **Not used** | Parses its own `.api` (goctl-style) spec and emits `moonapi` **server** scaffolding. No OpenAPI-import → typed-client role. |
| `moonbitlang/x` | latest `0.5.5` | transitively `0.4.46` (mooncontract pin), used for `x/fs` | Works for ASCII paths; see the Windows finding on non-ASCII paths. |

Consequences applied to the prototype:

1. `mooncontract` is the only OpenAPI parser. No second parser was written.
2. `servers`, `components.securitySchemes`, root/operation `security`, and
   parameter `style`/`explode` are not exposed by mooncontract's public API, so
   the frontend reads exactly those fields from the raw document as a narrow
   sidecar. This is the sidecar the architecture doc allows, not a shadow
   parser: values are only read, never re-interpreted as operations/schemas.
3. The generated transport is pinned to `moonbitlang/async@0.20.2`.

## Competition re-check

Live re-check on 2026-09-13, not a restatement of `docs/RESEARCH.md`.

- `mooncakes.io/api/v0/modules` full listing: **2427 modules**. Filtering names
  and descriptions for `openapi|swagger|sdk generator|client generator` yields
  only: `Han-Wentao/mooncontract`, `Lfan-ke/moonapi`, `Showichiro/moon_openapi_cli`,
  `WeiR-h/moonapi_check` (plus unrelated `codegen`-keyword packages).
- GitHub repository search totals: `moonbit openapi client generator` →
  **0**, `moonbit in:name openapi` → **0**, `moonbit in:name swagger` → **0**,
  `openapi generator language:MoonBit` → **0**, `moonbit codegen in:name,description`
  → 2 unrelated, `topic:openapi language:MoonBit` → 3 (mooncontract, moonapi, an
  unrelated personal repo), `moonbit http client in:name,description api` → 1.

Closest neighbours and why none is the same goal:

| Project | What it actually does | Why it is not a substitute |
|---|---|---|
| `Showichiro/moon_openapi_cli` `0.1.5` | Agent-friendly OpenAPI **extraction/search** CLI; normalizes 3.0/3.1 and Swagger 2.0; JSON only | No MoonBit code generation; YAML explicitly out of scope |
| `WeiR-h/moonapi_check` `0.1.1` | Conservative 3.0.3 **request compatibility analysis** | Diagnostics only, no output SDK |
| `Lfan-ke/moonapi` `0.8.0` | Typed **server** framework that *emits* OpenAPI 2.0/3.0/3.1 descriptors | Opposite direction from spec → client |
| `mizchi/jsonschema` `0.8.1` | JSON Schema validator + code generator | No OpenAPI layer; no HTTP client semantics |
| `moonbit-community/tonyfettes-powermem` | Hand-written SDK for one HTTP API | One service, not a generator |
| `mizchi/github`, `mizchi/discord`, `marianoguerra/slack`, `ryota0624/moonbit_googleapis` | Hand-written or hand-maintained service clients | No generic spec input |

Limitations: GitHub search ran unauthenticated, and private/unpublished work
cannot be observed. Re-run this scan before V1 release, per `docs/RESEARCH.md`.

## Petstore results

Fixture: `fixtures/petstore/openapi.json` (`openapi: 3.0.3`,
sha256 `5584c0867eea4f3a013567723bc99886f2a2aa7cbcfdbf32f4359158f4993f40`) with a
byte-equivalent YAML twin `fixtures/petstore/openapi.yaml`
(sha256 `d49162b17499478bf3432596888c65a52214de33620a05de504891f37c175231`).

Coverage in one document: `Pet` object; `PetStatus` string enum; `Array[String]`
property; required `id`/`name`/`status`; optional `owner`/`tags`; nullable
`nickname`; local `$ref` for both a property and request/response bodies; path,
query and header parameters; JSON request body; JSON response; `bearerAuth`
applied at document level; `204` response.

Pipeline as built:

```text
fixtures/petstore/openapi.json
  -> spike/frontend (MoonBit executable)
       @openapi.parse_json  -> OpenApiDoc            (Han-Wentao/mooncontract)
       + raw sidecar: servers / securitySchemes / security / style / explode
       + raw scan:    unsupported + ignored keyword locations
  -> spike/build/normalized.json  (Frontend Model, deterministic JSON)
  -> spike/generator (Python)
       oas2moon.frontend  -> typed Frontend Model
       oas2moon.support   -> diagnostics / profile gate
       oas2moon.lower     -> Client IR (refs resolved here, once)
       oas2moon.naming + oas2moon.typemap -> names and MoonBit types
       oas2moon.emit      -> MoonBit sources (+ moonfmt canonicalization)
  -> spike/build/gen1 (generated MoonBit package)
```

Frontend Model (`spike/build/normalized.json`, 6477 bytes,
sha256 `3cd2bc562c3b5eabf765616e2aec8712d22962583020b28b4686d28d6e14f898`):
`openapi, title, servers, securitySchemes, security, operations[], schemas{},
issues[], ignored[]`.

Local `$ref` resolution, done once during lowering:

| Use site | Ref | Resolved |
|---|---|---|
| `Pet.status` | `#/components/schemas/PetStatus` | `PetStatus` enum |
| `GET /pets/{id}` 200 | `#/components/schemas/Pet` | `Pet` |
| `POST /pets` request body | `#/components/schemas/Pet` | `Pet` |
| `POST /pets` 201 | `#/components/schemas/Pet` | `Pet` |

Generated models:

| Model | Kind | Fields |
|---|---|---|
| `PetStatus` | enum | `Available` / `Pending` / `Sold`, wire values `available` / `pending` / `sold` |
| `Pet` | struct | `id : Int64` (required), `name : String` (required), `status : PetStatus` (required), `owner : String?` (optional), `tags : Array[String]?` (optional), `nickname : String?` (optional + `nullable: true`) |

Generated operations:

| operationId | Method + path | MoonBit | Success |
|---|---|---|---|
| `getPetById` | `GET /pets/{id}` | `Client::get_pet_by_id(id : Int64, x_trace : String, verbose? : Bool)` | 200 → `Pet` |
| `addPet` | `POST /pets` | `Client::add_pet(pet : Pet)` | 201 → `Pet` |
| `deletePet` | `DELETE /pets` | `Client::delete_pet()` | 204 → `Unit` |

Type mapping actually exercised: `integer/int64 → Int64`, `string → String`,
`boolean → Bool`, `array[T] → Array[T]`, `object → struct`, string `enum → enum`,
optional → `T?`. `Int64` is decoded from a JSON **number**, not a string (a
deliberate deviation from `@json`'s default `Int64` handling, implemented in
`runtime/json_scalars.mbt`).

Unsupported-feature handling (negative path): `fixtures/unsupported/oneof.json`
normalizes to `spike/build/normalized_oneof.json`, whose `issues` list is
non-empty; the generator exits **1**, writes **no** output tree, and prints:

```text
error: unsupported.keyword: #/components/schemas/Choice/oneOf: keyword 'oneOf' is not supported and must not be dropped silently
error: unsupported.named_schema: #.schemas.Choice: named component schemas must be objects or string enums in the spike, got 'any'; inline the schema at its use sites
```

Two runs produced identical reports
(sha256 `b50c6329d9dc4418bb2a49a581e511195676b780893231223CC0B35B02333D2A`).

## Compile results

Emitted tree: 10 files (LF, no timestamps, no absolute paths).

```text
moon.mod
runtime/moon.pkg  runtime/config.mbt  runtime/encoding.mbt
runtime/json_scalars.mbt  runtime/transport.mbt
sdk/moon.pkg  sdk/models.mbt  sdk/models_wbtest.mbt  sdk/client.mbt
```

```text
moon fmt --check                              exit 0
moon check --target native --deny-warn        exit 0
moon test  --target native --deny-warn        exit 0  Total tests: 4, passed: 4, failed: 0
```

`moon fmt` is genuinely active, not assumed: deliberately mangling spacing in
`sdk/models.mbt` made `moon fmt --check` print a diff and fail, and running
`moon fmt` restored the byte-identical file
(sha256 `b5fe3fe10cffe6bafe22671e986873c7c5c55890f1816c6862d8e9813c850dc2`).
The generator itself pipes every rendered file through `moonfmt` so a freshly
generated tree is canonical by construction; a missing `moonfmt` aborts
generation instead of writing unformatted output.

Generated `moon test` cases (in `sdk/models_wbtest.mbt`) pin enum wire values,
enum decode, JSON round-trip, and omission of unset optional properties.

Runtime isolation holds: `sdk/client.mbt` only builds `@runtime.Request` and
calls `@runtime.*`; the single place importing `moonbitlang/async/http` is
`runtime/transport.mbt`.

Not verified here: non-native targets (`wasm-gc`, `js`), PUT/PATCH/HEAD/OPTIONS,
multiple success statuses, structured non-2xx error types.

## HTTP integration results

`spike/server/fixture_server.py` serves the Petstore fixture on
`127.0.0.1:18080`, validates every request, answers, and writes
`capture.json`. `spike/run_integration.ps1` starts it, runs the generated
package with `moon run smoke --target native`, stops it, and fails if the
server recorded any mismatch. The smoke driver lives in
`spike/generator/templates/smoke/` and is copied next to the generated package
at run time, so the generated tree stays exactly what the generator emitted.

Result: 3 requests, 11 assertions, 0 errors.

| Assertion | Observed |
|---|---|
| `authorization` ×3 | `Bearer spike-token` on GET, POST, DELETE |
| `get.path_parameter` | `GET /pets/42` |
| `get.header_parameter` | `x-trace: trace-get` |
| `get.query_parameter` | `verbose=true` (optional query present) |
| `post.path` | `POST /pets` |
| `post.content_type` | `application/json` |
| `post.json_body` | `{"id":99,"name":"Created","status":"available","tags":["a","b"]}` (64 bytes, `content-length: 64`) |
| `post.optional_omitted` | `nickname` (optional + nullable) absent from the body |
| `delete.path` | `DELETE /pets`, no body, `authorization` present |

Typed decode (printed by the generated client and captured server-side):

```json
{"get":{"id":"42","name":"Spike","status":"available","tags_present":true,"tags":["fluffy","friendly"],"nickname_present":false,"nickname":null},"post":{"id":"99","name":"Created","status":"available","tags_present":true,"tags":["a","b"],"nickname_present":false,"nickname":null},"delete":"204","verdict":"ok"}
```

The server answered `{"nickname": null}` for `GET`; the client decoded it into
`None` (`nickname_present=false`), which is the documented single-value collapse
described under Hidden blockers. `id` decoded into `Int64` from a JSON number,
`tags` into `Array[String]`, `status` into `PetStatus::Available`.

Cross-check on the next async release: the same generated package with
`moonbitlang/async@0.20.6` also passes `moon check` and the full integration run
(`spike/build/gen_async_0206-integration/`).

## Determinism results

`spike/verify_determinism.ps1` generates two fresh trees from the same
normalized input, runs `moon fmt` in both, and compares file lists, per-file
bytes, aggregate hash, and the generator report.

```text
file count: 10
  d21751eab92ca64b172c696d13465d9e18ad87b8a78bc8246f8782933f27791c  moon.mod
  3bb01a7a6e3623c2e1ad44d7200f1f9c8758ce65c67dfacdd166197675011a96  runtime/config.mbt
  63267deba54e8cbf7aea25e6a36f8b9d2c18f13643eb3d49676fdaf3d6183682  runtime/encoding.mbt
  941268efedb2ef0998bcd66ae5173e3d4827ecf359a8400b635aab6261d8d50e  runtime/json_scalars.mbt
  26c2b764056e221d4b03e22ad715c07f9e5109b6e57bb45fe5dced6c8e3e5594  runtime/moon.pkg
  89eded89f8a408eb965546842ab178e6a2cb53545f425650bfdc2b42194b5605  runtime/transport.mbt
  761f9af493da12bc417abe579807f156a336ad113d44531f8152e3823e8accf6  sdk/client.mbt
  4493563945a7174c2cdabd1586fbe98d6cde1e149341539b5205f6dea46b6491  sdk/models_wbtest.mbt
  b5fe3fe10cffe6bafe22671e986873c7c5c55890f1816c6862d8e9813c850dc2  sdk/models.mbt
  8151d90b79107a1c8a90a0befb2cf890bcdc2a62159bcf9f265a9c67c2c79138  sdk/moon.pkg
aggregate_sha256: 5abb2d83155053a2e8679b173e54742e66887eef6bb5d33afd3ad8cadbe3474e
reports byte-identical: True
```

Additional determinism properties observed:

- `gen1-report.json` and `gen2-report.json` are byte-identical
  (sha256 `68a0f4b86b221bdd81ca6001c3d8dfa42d754860f87a80dadae3f4dce8bdf6fd`) and
  contain no timestamps, no local paths, and no random ids.
- The JSON and YAML inputs produce byte-identical Frontend Models
  (both `3cd2bc56…`), so input format does not perturb ordering.
- Diagnostics are deterministic: repeated unsupported-input runs emit the same
  report bytes.
- Insertion order comes from `Map[String, Json]`, which preserved document
  order in the probe (MoonBit `Map` iteration here is ordered by insertion).
  Ordering discipline is therefore still required in the generator, and is
  already enforced by sorting models/operations/imports before emission.

## Windows results

Everything in this report was executed natively on Windows 11 with PowerShell
7.6.5: `moon fmt/check/test`, `moon run` of the generated client, the Python
fixture server, and the loopback HTTP round-trip. No WSL, Docker, or Linux
container was involved. There is **no fatal Windows blocker**.

Three Windows-specific facts were measured rather than assumed:

1. Non-ASCII path components break file I/O in MoonBit native programs on this
   host. `spike/build/fsprobe` isolates it:

   ```text
   argv[1]=D:\oas2moon\spike\build\路径测试\petstore.json   read_err=IOError("No such file or directory")
   argv[1]=D:\oas2moon\spike\build\测试文件.json            read_ok_bytes=5   write_ok=...
   ```

   The file exists (PowerShell lists it, 3088 bytes) and argv arrives intact;
   the failure is in the filesystem layer of `moonbitlang/x` (native), which
   hands UTF-8 bytes to an ANSI codepage (CP936 on this host). A file written by
   MoonBit with a non-ASCII name appears to Windows as mojibake
   (`测试文件.json.copy` → `娴嬭瘯鏂囦欢.json.copy`). Because a non-ASCII
   *directory* cannot be opened at all, non-ASCII input/output paths are a real
   usability limit for the CLI on Windows; ASCII paths (the whole repository,
   including `D:\oas2moon`) are unaffected. Mitigation: document ASCII-path
   support, or route file I/O through a future runtime-independent reader.
2. `moon fmt --check` requires `git` on `PATH`. With `git` removed from `PATH` it
   fails loudly (`Error: program not found` → `Error: failed when formatting
   project`, exit -1) rather than silently passing, so the gate stays sound but
   CI images must ship git.
3. The workspace is not a git repository. That is irrelevant to the toolchain:
   `moon fmt`, `moon check`, `moon test`, and `moon run` all work, and
   `moon fmt --check` still detects unformatted files (it shells out to
   `git --no-pager diff --no-index`).

## Hidden blockers

None blocks the verdict. Each is bounded, and each has a stated mitigation.

1. **`moonbitlang/async@0.21.3` does not compile with `moonc v0.10.9`.** The
   latest published async release fails to parse with the current toolchain;
   `0.20.2` (pinned) and `0.20.6` work. Mitigation: pin in generated manifests
   and keep a CI job that re-tests the newest async release; treat async as a
   version-gated dependency.
2. **mooncontract silently drops unsupported keywords.** `oneOf`, `anyOf`,
   `allOf`, `discriminator`, `xml`, `not`, `callbacks`, `webhooks` do not surface
   in its public model, so the spike frontend records their locations from the
   raw document and the generator rejects them. Without this, the generator
   would emit wire behavior the contract does not describe.
3. **That raw scan is keyword-based and therefore over-strict.** A property whose
   `example`/`default` object literally contains a key such as `oneOf` is
   reported as an unsupported-feature location and the document is rejected.
   Reproduced with `fixtures/regression/scan_false_positive_input.json`:

   ```text
   error: unsupported.keyword: #/paths//ping/get/responses/200/content/application/json/schema/properties/note/example/oneOf: keyword 'oneOf' is not supported and must not be dropped silently
   ```

   No `oneOf` schema exists in that document. The scan already guards `properties`
   keys (a property named `xml` is not flagged), but not data-valued objects. This
   fails closed, so it is a false rejection rather than a silent misgeneration;
   V1 should scope the scan to schema positions only.
4. **mooncontract reports non-object/non-enum schemas as `kind = Any`** and keeps
   `$ref` as a path string instead of resolving it. The generator must therefore
   follow ref paths and classify unknown/`Any` shapes itself; the prototype does
   this in the support validator, and named `Any` schemas are rejected rather
   than approximated.
5. **`T?` collapses "absent" and "explicit null".** The spike uses `T?` for both
   optional and nullable fields. That is safe for the verified path (the request
   body omits unset optional fields, and a decoded response null becomes `None`),
   but it cannot represent "set this field to null" in a request. `PROJECT_SPEC.md`
   §7 and `ARCHITECTURE.md` §13 require a tri-state (`Unset`/`Null`/`Value(T)`)
   before V1 claims request-side nullable semantics.
6. **Response policy is only partially implemented.** One effective 2xx schema →
   typed result, `204` → `Unit`, and status checking with a structured
   `SdkError::HttpStatus` are implemented. Multiple success statuses with
   different schemas (response enum), `default` responses, and the documented
   `Json` fallback are not.
7. **Authentication coverage is Bearer only.** API key (header/query), Basic, and
   "missing required credentials fail before network I/O" are unverified; the
   runtime has the `MissingCredential` error path but only one scheme wired.
8. **Parameter serialization coverage.** Only path scalar, query scalar, and
   header scalar are exercised. Query/header arrays, and explicit
   `style`/`explode` handling (captured by the sidecar but unused) are open.
9. **Generated API shape differs slightly from the doc example.** The doc shows
   `client.get_pet_by_id(id=42)`; the generated method is
   `Client::get_pet_by_id(id, x_trace, verbose?)`. Named-argument style for
   required parameters is a V1 API decision, not a spike result.
10. **Generator implementation language is an open decision.** The frontend is
    MoonBit; the spike generator is Python for speed. `PROJECT_SPEC.md` names
    MoonBit as the primary language, so Phase 1 must decide whether the
    production generator stays Python or moves to MoonBit (where
    `mizchi/codegen` becomes relevant).
11. **Non-ASCII filesystem paths on Windows** (see Windows results) and
    **`moon fmt --check` requiring git** are environment-level limitations to
    document and CI-encode.
12. **Native-only.** Generated packages pin `supported_targets = "+native"`;
    `wasm-gc`/`js` are untested. `docs/ACCEPTANCE.md` §G requires Ubuntu CI as
    well, which has not been run at all.
13. **Repository hygiene.** `spike_generator.py`, `out1/`, `out2/`,
    `.spike-scratch/`, and `prompts/` are pre-spike leftovers kept in the tree;
    they are not part of the spike and should be removed or moved before V1.
    Evidence tooling to keep: `spike/frontend/`, `spike/generator/`,
    `spike/server/`, `spike/probe/`, `spike/probe_tests/`,
    `spike/run_spike.ps1`, `spike/run_integration.ps1`,
    `spike/verify_determinism.ps1`, `spike/build/`.

## Recommended V1 boundary

Unchanged from `docs/SUPPORTED_OPENAPI.md` and `docs/DEVELOPMENT_PLAN.md`; the
spike does not justify broadening it. Keep out: OpenAPI 3.1, Swagger 2.0,
external/network `$ref`, `oneOf`/`anyOf`/`discriminator`, `allOf` (initially),
multipart/form-upload, XML, OAuth/OpenID flows, callbacks/webhooks, GUI, and
arbitrary parameter serialization beyond the documented common profile.

Because the verdict is `GO`, the next stage is Phase 1 as defined in
`docs/DEVELOPMENT_PLAN.md` — and only Phase 1. The smallest useful slice is to
turn the verified prototype into a real frontend/IR foundation, not to add
features:

1. Fix the repository layout the docs describe: a `src/` (or documented
   equivalent) home, a CLI entry point named `oas2moon`, and the runtime package
   as a first-class artifact instead of a spike template.
2. Promote the Frontend Model JSON from "whatever the spike printed" to a
   versioned, validated schema, with a failing test for every field the
   generator consumes.
3. Move the raw keyword scan from raw-document keys to schema positions so the
   `oneOf` false positive in Hidden blocker 3 disappears, and shorten the
   ignored-keyword list to what the profile actually promises.
4. Give diagnostics the stable shape from `PROJECT_SPEC.md` §11 (`code`,
   `severity`, `json_pointer`, `operation_id`, `message`, `suggestion`) with a
   fixed code taxonomy and deterministic ordering.
5. Grow the support classifier only along already-documented V1 rows, starting
   with PUT/PATCH and Basic/API-key auth, then query/header arrays — each with
   parse, codegen, compile, and wire tests.
6. Stand up the corpus runner (`docs/ACCEPTANCE.md` §C) so `spec → generate →
   moon fmt → moon check → hash` reports real metrics per fixture.
7. Decide the generator implementation language (Hidden blocker 10) before the
   IR schema is frozen.
8. Add Ubuntu CI for the frontend/generator and keep Windows as the integration
   environment (`docs/ACCEPTANCE.md` §G).

Phase 1 gate: the Petstore subset still normalizes; unsupported input still
fails with stable diagnostics and no output; the Frontend Model schema and IR
ordering are frozen and covered by tests; the corpus runner reproduces the
determinism numbers in this report. No V1 feature work started in this round.
