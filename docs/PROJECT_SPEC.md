# Project Spec — oas2moon

## 1. Product definition

`oas2moon` converts supported OpenAPI 3.0.x documents into usable typed MoonBit HTTP client SDKs.

### Input

- OpenAPI `3.0.0`–`3.0.3`
- JSON as authoritative input
- common YAML via existing MoonBit ecosystem capability

### Output

A MoonBit client package containing:

- generated model types;
- generated request/input types where needed;
- typed operation methods;
- operation-specific response types where needed;
- authentication wiring;
- deterministic package metadata/imports;
- dependency on a small stable SDK runtime.

### Non-goals

V1 is not:

- an OpenAPI authoring tool;
- a server framework;
- a mock server;
- a compatibility checker;
- a general HTTP framework;
- full OpenAPI 3.0;
- OpenAPI 3.1 / JSON Schema 2020-12.

## 2. User problem

A MoonBit developer has a REST API described by OpenAPI.

Without this tool they must manually implement:

- models;
- path/query/header serialization;
- JSON request bodies;
- auth;
- HTTP calls;
- JSON decoding;
- error handling.

`oas2moon` should remove most of this repeated work.

## 3. Main flow

```text
OpenAPI spec
    ↓
oas2moon generate
    ↓
validate supported profile
    ↓
normalize to Client IR
    ↓
generate MoonBit package
    ↓
moon fmt
    ↓
moon check
    ↓
use typed client
```

Target CLI:

```bash
oas2moon generate petstore.yaml   --module petstore   --out generated/petstore
```

## 4. Generated API target

For:

```text
GET /pets/{id}
path id: integer
200: Pet
```

target:

```moonbit
let client = @petstore.Client::new(
  base_url="https://api.example.com",
)

let pet = client.get_pet_by_id(id=42)
println(pet.name)
```

Avoid forcing users to manually construct raw URL strings, `Map[String, String]`, or `Json` when the contract has enough type information.

## 5. V1 scope

Minimum:

- OpenAPI 3.0.0–3.0.3;
- JSON;
- common YAML;
- local component refs;
- primitive/object/array/enum;
- required/optional/nullable;
- GET/POST/PUT/PATCH/DELETE;
- path/query/header parameters;
- JSON request bodies;
- JSON responses;
- multiple declared success statuses;
- API key, Bearer, Basic auth;
- base URL override;
- deterministic naming and codegen;
- compile verification;
- real HTTP integration.

## 6. Response policy

- one effective successful schema → direct typed result;
- 204 only → `Unit`;
- multiple success statuses with same schema → direct typed result;
- multiple success statuses with different schemas → generated operation response enum;
- non-2xx → structured SDK HTTP error;
- safely dynamic JSON → `Json` with warning.

## 7. Model mapping intent

```text
string          -> String
integer/int32   -> Int
integer/int64   -> Int64
number/float    -> Float
number/double   -> Double
boolean         -> Bool
array[T]        -> Array[T]
object          -> generated struct
enum            -> generated enum when representable
free-form       -> Json
```

Exact mappings must be checked against the current MoonBit toolchain.

### Optional vs nullable

Do not assume they are the same.

For requests, optional + nullable may require a tri-state runtime field concept:

```text
Unset
Null
Value(T)
```

so omission is distinct from explicit JSON `null`.

## 8. Parameter serialization

V1 supports a deliberately small common profile:

- path: common `simple`;
- query: common `form`, scalar/array;
- header: common `simple`, scalar/array;
- correct percent encoding.

Unsupported styles must produce a stable diagnostic.

## 9. Authentication

V1:

- HTTP Bearer;
- HTTP Basic;
- API key header;
- API key query.

Client configuration owns credentials. Operation code applies its declared security requirements.

OAuth authorization flows are out of scope.

## 10. Servers

- use declared server URL when usable;
- allow explicit `base_url` override;
- remain usable when the document omits servers;
- unresolved complex server variables must not produce malformed URLs.

## 11. Diagnostics

Recommended stable shape:

```text
code
severity
json_pointer
operation_id
message
suggestion
```

Example:

```text
OAS203 ERROR
Unsupported schema feature: oneOf
location: #/components/schemas/Payment
```

## 12. Determinism

For identical:

```text
spec bytes + normalized config + generator version
```

generated source must be byte-identical.

No timestamps, random IDs, unstable map iteration, filesystem-order dependence, or local absolute paths.

## 13. Success definition

The project is complete only when:

1. supported real OpenAPI inputs normalize correctly;
2. generated packages compile;
3. generated clients send correct HTTP requests;
4. typed decoding works;
5. unsupported semantics fail explicitly;
6. deterministic regeneration passes;
7. real-world coverage is measured and published.
