# Development Decisions (T00)

Status: **Frozen for T00**  
Date: 2026-09-16  
Scope: OpenAPI 3.0.x typed client generation only.

This document is the normative development contract. If implementation or an older report conflicts with it, update the implementation or record a new dated decision before proceeding. Unsupported semantics must produce deterministic diagnostics; no silent wire-level fallback is allowed.

## 1. Runtime Request/Response

Generated operation code depends only on the small runtime adapter, never directly on `moonbitlang/async/http`.

Logical request fields:

- method: uppercase HTTP method;
- URL: base URL plus encoded path and query;
- headers: deterministic multi-map/list preserving duplicate values where needed;
- body: absent or JSON bytes/value;
- timeout/config: supplied by client configuration, not operation code.

Logical response fields:

- status: integer HTTP status;
- headers: response headers;
- body: bytes/text/JSON as required by the decoder.

The adapter returns a response for HTTP-level statuses, including non-2xx. Network, timeout, transport, and decoding failures are represented by `SdkError`. Exact MoonBit type names and async signatures remain **SPIKE-T02** until verified against the installed toolchain and real dependency APIs.

## 2. `SdkError`

The public error is a closed, structured error type with at least:

- `Transport` — DNS, connection, timeout, TLS, or adapter failure;
- `Http` — non-2xx response, containing status, headers, and bounded/raw body representation;
- `Decode` — response did not match the declared supported representation;
- `Encode` — request serialization failed;
- `Configuration` — invalid base URL or auth configuration;
- `Unsupported` — rejected OpenAPI semantic, when surfaced at generation/runtime boundary.

No error variant may discard the operation context needed for diagnosis. Whether MoonBit uses `enum`, `struct`, or a package-qualified alias is **SPIKE-T02**.

## 3. Response status policy

- Success is a declared 2xx response only; undeclared 2xx is not guessed.
- One effective success schema, or multiple success statuses sharing one schema: return that typed value.
- A sole 204 response: return `Unit` and do not decode a body.
- Multiple successful statuses with different schemas: generate an operation-specific response enum carrying status and typed payload.
- A declared success without a schema is accepted only when body absence is unambiguous; otherwise emit a stable diagnostic.
- Any non-2xx response becomes `SdkError::Http`; it is never decoded as a success type.
- A declared JSON response whose wire `Content-Type` is not JSON fails as `SdkError::Unsupported`; it is never decoded as if the declared representation were valid.
- Redirect handling belongs to the transport adapter and is not generated operation behavior.

## 4. Optional and nullable

These are distinct:

- required + non-nullable: value type;
- optional + non-nullable: absence-capable field/input representation;
- required + nullable: value that may contain `null`;
- optional + nullable: absence and explicit `null` must remain distinguishable.

Request serialization must omit absent optional values and emit explicit JSON `null` for present nullable values. Response decoding must preserve the distinction where the target type permits it; if it cannot, generation is rejected with a diagnostic rather than silently collapsing states. Exact MoonBit option/result encoding is **SPIKE-T01/T02**.

## 5. Parameter encoding

Only the default, explicitly supported OpenAPI 3.0 serialization profile is frozen:

- path: URI percent-encode parameter values; substitute into the templated path; no raw slash injection;
- query: percent-encode names and values using repeated key form for supported arrays; stable parameter order;
- header: encode scalar values as strings; header names are case-insensitive but generated names are canonical and stable;
- unsupported `style`, `explode`, deepObject, matrix, label, or arbitrary content serialization: deterministic diagnostic.

The exact percent-encoding byte set and array rules require wire tests and are **SPIKE-T04**; implementation must not rely on host-language defaults without tests.

## 6. Authentication

Client configuration owns auth. Supported V1 schemes are API key, Bearer, and Basic. Auth is applied by the runtime/request builder so generated operations remain transport-isolated. Per-operation security overrides global security; explicit `security: []` means unauthenticated. Missing required credentials is a configuration error. OAuth authorization flows are out of scope. Header/query placement and precedence are **SPIKE-T09** where not already proven by tests.

## 7. CLI exit codes

These are the codes `src/oas2moon/cli.py` actually returns; they are covered by
`tests/test_t10_cli.py`.

- `0`: success;
- `1`: input file missing, or its extension is not `.json`/`.yaml`/`.yml`;
- `2`: invalid MoonBit module name;
- `3`: frontend adapter failure (invalid or unparseable OpenAPI document);
- `5`: pipeline failure after the frontend stage — IR building, codegen, or the
  trailing `moon fmt`;
- `6`: `--out` exists and is a file rather than a directory.

`4` is currently unused; it was reserved in an earlier draft for a distinct
"unsupported OpenAPI contract" outcome, but unsupported documents are reported
by the frontend adapter and therefore return `3`. If a separate code is ever
introduced, this section and the CLI must change together.

Diagnostics go to stderr; the successful summary goes to stdout. The exact CLI
parser API was **SPIKE-T10**.

## 8. Generated directory structure

`--out <dir>` is the complete generated package root. Generation writes only deterministic, owned files directly below it — a **flat** layout, with no `model/`, `operation/`, or `runtime/` subdirectories:

```text
<out>/
  moon.mod          # module name + moonbitlang/async dependency when needed
  moon.pkg          # imports; owned by the codegen, never rewritten downstream
  models.mbt        # generated structs, enums, presence helpers, JSON codecs
  client.mbt        # public client and every generated operation method
  runtime.mbt       # SdkError, Request/Response, Transport, CaptureTransport
  config.mbt        # base URL, credentials
  encoding.mbt      # path/query/header serialization
  http_transport.mbt # the only file that touches moonbitlang/async/http
```

`client.mbt` is emitted only when the API has operations; `moonbitlang/core/string`
is imported only when the API uses `Int64`.

**Why flat, and why the runtime is inlined rather than referenced as a package.**
Inlining makes a generated SDK self-contained: one directory compiles on its own,
and there is no version skew between a published `oas2moon/runtime` package and
the code that a given generator revision emitted. The cost is explicit and
accepted: **a runtime fix does not reach an existing SDK until that SDK is
regenerated**, because there is no shared dependency to update in place. If the
runtime is ever published and consumed as a dependency instead, this section and
the emitter must change together.

File ownership and stable naming are fixed by this section. Existing unrelated
files must not be deleted. **SPIKE-T06** and the T11 demo (`demo/petstore/run_demo.ps1`,
which hashes two independent generations) confirm the layout.

## 9. Diagnostics

Machine-stable diagnostic record:

```text
DIAG <code> <severity> <location>: <message>
```

`code` is stable and machine-matchable; severity is `error` or `warning`; location is a deterministic JSON Pointer/OpenAPI path (or `input`); message is human-readable and must not contain absolute paths, timestamps, or nondeterministic values. Diagnostics sort by location, then code, then severity, then message. Unsupported behavior is an error unless the support matrix explicitly documents a safe `Json` fallback; such fallback must emit a warning.

## 10. Determinism

Sort all unordered source maps by one deterministic key order. Preserve array order where OpenAPI gives semantic order; otherwise sort normalized operations, schemas, parameters, responses, imports, files, and diagnostics by their canonical keys. Use stable naming collision rules and stable newline/encoding. Never emit timestamps, random IDs, machine paths, environment-dependent ordering, or hash seeds.

**Amendment 2026-09-16 (T13).** The implemented comparator is MoonBit's `String` `Compare`, which is *shortlex* (shorter strings first, then UTF-16 code-unit order), not UTF-8 bytewise order. Earlier wording said "UTF-8 bytewise"; that was never what the code did. T13 verified the shortlex order is a strict total order and that output is byte-identical across repeated runs, reversed spec key order, and reversed normalized-model key order, so shortlex is the rule this project commits to. Switching to bytewise order would reorder generated struct fields for some inputs and is therefore a deliberate decision, not a bug fix.

## 11. Evidence and change control

Every contract item below has evidence status in `EVIDENCE_MATRIX.md`. A `SPIKE` item is not an implementation license: first create the smallest executable verification, record the observed API/output, then promote the decision with a dated amendment.

## 12. Generated operation call shape

Generated operation methods follow the convention the MoonBit ecosystem uses for
generated clients:

- **required parameters are positional**;
- **optional parameters are labelled** (`name? : T`);
- **operations are `async fn`** and report failure by raising `SdkError`
  rather than returning `Result`;
- `Client::new` takes labelled options only, including credentials
  (`bearer_token`, `basic_username`/`basic_password`,
  `api_key_name`/`api_key_value`/`api_key_location`) and an optional
  `capture : CaptureTransport` used by hermetic tests.

So the generated call shape is

```moonbit
let pet = client.get_pet_by_id(42L, "trace-id", verbose=true)
```

and not `client.get_pet_by_id(id=42)`, which MoonBit rejects for a parameter
declared as positional.

**Evidence.** `moonbit-community/elasticsearch.mbt` — the reference
implementation identified in the dependency audit — generates
`pub fn AsyncSearchDeleteRequest::new(id : String, query? : ... = ...)` and
`pub async fn Client::async_search_delete(self : Client, request : ...)`, i.e.
positional required arguments, labelled optional arguments, and async methods.
The same shape is reproduced and executed by the T11 Petstore demo, which
compiles the generated package with `moon fmt` + `moon check --deny-warn`,
runs its generated tests with `moon test`, and drives the client against a real
local HTTP server.

**Consequences.** The `PROJECT_SPEC.md` samples were updated to this shape; the earlier `Result`-returning sketches were never
implemented and are not part of the contract.
