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

- `0`: generation completed and all requested verification steps passed;
- `2`: usage/argument/input-file error;
- `3`: invalid or unsupported OpenAPI contract;
- `4`: generation or output I/O failure;
- `5`: generated package verification failure (`moon fmt`, `moon check`, or configured tests);
- `6`: deterministic-output verification failure.

Diagnostics go to stderr; successful summary goes to stdout. Exact CLI parser API is **SPIKE-T10**.

## 8. Generated directory structure

`--out <dir>` is the complete generated package root. Generation writes only deterministic, owned files below it:

```text
<out>/
  moon.mod.json
  README.md
  runtime/        # only if packaging runtime locally is selected
  model/          # generated models
  operation/      # generated operation/request/response types
  client.mbt      # public client and operation methods
```

The exact module layout may be simplified by the emitter, but file ownership and stable naming must be documented before implementation. Existing unrelated files must not be deleted. **SPIKE-T06** confirms the final MoonBit package layout.

## 9. Diagnostics

Machine-stable diagnostic record:

```text
DIAG <code> <severity> <location>: <message>
```

`code` is stable and machine-matchable; severity is `error` or `warning`; location is a deterministic JSON Pointer/OpenAPI path (or `input`); message is human-readable and must not contain absolute paths, timestamps, or nondeterministic values. Diagnostics sort by location, then code, then severity, then message. Unsupported behavior is an error unless the support matrix explicitly documents a safe `Json` fallback; such fallback must emit a warning.

## 10. Determinism

Sort all unordered source maps by UTF-8 bytewise key order. Preserve array order where OpenAPI gives semantic order; otherwise sort normalized operations, schemas, parameters, responses, imports, files, and diagnostics by their canonical keys. Use stable naming collision rules and stable newline/encoding. Never emit timestamps, random IDs, machine paths, environment-dependent ordering, or hash seeds.

## 11. Evidence and change control

Every contract item below has evidence status in `EVIDENCE_MATRIX.md`. A `SPIKE` item is not an implementation license: first create the smallest executable verification, record the observed API/output, then promote the decision with a dated amendment.
