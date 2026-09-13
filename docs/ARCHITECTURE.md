# Architecture — oas2moon

## 1. Core rule

> Parser models are input facts; **Client IR is the generator authority**.

Do not generate MoonBit directly while recursively walking raw OpenAPI JSON.

## 2. High-level architecture

```text
              OpenAPI JSON/YAML
                     │
        ┌────────────┴────────────┐
        │                         │
        ▼                         ▼
 Primary OpenAPI Adapter      Raw OAS Sidecar
 (MoonContract-first)         (security/servers/etc.)
        │                         │
        └────────────┬────────────┘
                     ▼
               Frontend Model
                     │
                     ▼
              Support Validator
                     │
                     ▼
                 Normalizer
                     │
                     ▼
              Canonical Client IR
                     │
        ┌────────────┼─────────────┐
        ▼            ▼             ▼
     Naming       Type Map     Operation Plan
        │            │             │
        └────────────┴─────────────┘
                     ▼
                  Codegen
        ┌────────────┼──────────────┐
        ▼            ▼              ▼
      Models      Operations      Package
        │            │              │
        └────────────┴──────────────┘
                     ▼
              Generated SDK
                     │
                     ▼
               oas2moon/runtime
                     │
                     ▼
           Async HTTP Transport
```

## 3. Recommended repository layout

```text
oas2moon/
├── AGENTS.md
├── README.md
├── src/
│   ├── frontend/
│   │   ├── adapter/
│   │   ├── raw/
│   │   └── diagnostics/
│   ├── normalize/
│   ├── ir/
│   ├── naming/
│   ├── codegen/
│   │   ├── model/
│   │   ├── operation/
│   │   ├── auth/
│   │   └── package/
│   └── cli/
├── runtime/
│   ├── request/
│   ├── response/
│   ├── auth/
│   ├── encoding/
│   └── transport/
├── tests/
│   ├── frontend/
│   ├── normalize/
│   ├── codegen/
│   ├── compile/
│   └── integration/
├── fixtures/
│   ├── petstore/
│   └── real-world/
├── docs/
└── prompts/
```

Exact MoonBit packages should follow the current toolchain rather than copying this tree mechanically.

## 4. Frontend layer

### Preferred path

Use a **MoonContract adapter first** if its current public API remains suitable.

Reasons:

- OpenAPI 3.0.x parsing already exists;
- common YAML support already exists;
- local refs are already handled;
- operations/parameters/body/responses/components are already modeled.

### Dependency boundary

MoonContract-specific types stay under:

```text
src/frontend/adapter/
```

The rest of the project consumes project-owned types.

### Raw sidecar

Keep access to normalized raw JSON only to extract fields the adapter does not expose, such as:

- `servers`;
- `components.securitySchemes`;
- root/operation `security`;
- serialization metadata.

Do **not** create a second full OpenAPI parser.

## 5. Support validator

Before codegen, classify every used feature:

```text
Supported
SafeJsonFallback
Unsupported
```

- `Supported`: V1 can represent correct semantics.
- `SafeJsonFallback`: wire behavior remains correct but static precision is lost.
- `Unsupported`: generation must stop for that affected scope.

Examples of `Unsupported`:

- unsupported parameter serialization;
- `oneOf` requiring ambiguous variant decode;
- unsupported request media type.

## 6. Canonical Client IR

Conceptual shape:

```text
ApiIr
├── metadata
├── servers
├── auth_schemes
├── models
└── operations

ModelIr
├── name
├── kind
├── fields
├── enum_values
└── additional_properties

TypeRef
├── Primitive
├── Named
├── Array
├── Optional
├── Map
└── Json

OperationIr
├── id
├── method
├── path
├── parameters
├── request_body
├── success_responses
├── security
└── docs

ParameterIr
├── source_name
├── moon_name
├── location
├── type
├── required
└── serialization
```

Why IR is mandatory:

- references are resolved once;
- naming is decided once;
- nullable/required semantics are decided once;
- response strategy is decided once;
- unsupported semantics are diagnosed before emission.

Emitters should not contain OpenAPI business logic.

## 7. Naming subsystem

Centralize:

- operationId → function name;
- schema → type name;
- property/parameter → field/argument name;
- keyword handling;
- illegal-character normalization;
- collisions;
- stable suffixes.

Collision resolution must not depend on discovery order.

## 8. Type mapping

One subsystem owns:

- primitive mapping;
- nullable mapping;
- arrays/maps;
- named refs;
- request tri-state fields;
- Json fallback.

The emitter only renders already-decided types.

## 9. Codegen

### Model emitter

Generates:

- structs;
- enums;
- request/body types;
- JSON encode/decode support.

### Operation emitter

Generates:

- typed signatures;
- path/query/header serialization;
- request body calls;
- runtime invocation;
- response dispatch;
- typed decode.

### Auth emitter

Generates public auth/config surface and security wiring.

### Package emitter

Generates:

- package metadata;
- deterministic imports;
- entry points;
- no timestamps.

## 10. Runtime boundary

Generated code depends on a small stable runtime owned by this project.

Conceptual surface:

```text
Request
Response
Transport
SdkError
Auth
encode_path
encode_query
decode_json
```

The default transport adapter can use `moonbitlang/async/http`.

Generated source should not directly scatter transport-specific APIs.

### Why this matters

- isolates async/http API churn;
- enables an in-memory capture transport;
- stabilizes generated code;
- keeps request semantics testable without sockets.

## 11. Authentication

Client config owns credentials.

At operation call time:

1. inspect normalized security alternatives;
2. choose first satisfiable requirement;
3. apply all schemes required by that requirement;
4. fail before network I/O if required credentials are missing.

## 12. Response strategy

Normalization decides the return shape:

1. `204` only → `Unit`.
2. one effective 2xx schema → direct typed result.
3. multiple 2xx statuses with same schema → direct typed result.
4. multiple 2xx schemas → operation-specific response enum.
5. non-2xx → structured HTTP error.
6. safe dynamic response → `Json` + warning.

## 13. Request field presence

When OpenAPI distinguishes:

- absent;
- explicit null;
- concrete value;

use a runtime concept equivalent to:

```text
Unset
Null
Value(T)
```

Do not collapse omission and explicit null where it changes the request body.

## 14. Determinism

Before emission, sort canonical IR by stable keys.

Examples:

- models by canonical source identity;
- operations by `(path, method, operationId)`;
- imports lexicographically;
- diagnostics by `(location, code)`.

Generated output must not contain current timestamps.

## 15. Verification pipeline

Every corpus case:

```text
spec
 ↓
parse
 ↓
normalize
 ↓
generate
 ↓
moon fmt
 ↓
moon check
 ↓
hash source tree
```

Selected cases continue:

```text
generated SDK
 ↓
real local HTTP server
 ↓
request assertions
 ↓
typed decode assertions
```

CI minimum:

- Ubuntu;
- Windows.

Only claim targets actually verified.

## 16. Future extensions

Possible later:

- `allOf`;
- `oneOf` / `anyOf`;
- discriminator;
- multipart;
- external refs;
- OpenAPI 3.1;
- additional parameter styles;
- OAuth helpers.

None are required for V1.
