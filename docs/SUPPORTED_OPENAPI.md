# Supported OpenAPI profile

This is a bounded OpenAPI 3.0.x profile, not a claim of full OpenAPI support. “Tested” means evidence exists in the named test, fixture, demo, or hosted CI; it does not make unlisted combinations supported.

## Supported and evidenced

| Capability | Evidence |
|---|---|
| OpenAPI 3.0.0–3.0.3 JSON; common YAML | `tests/test_t10_cli.py` and generated-package compile checks |
| Local component `$ref` | Petstore fixture and demo generation |
| Primitive, object, array, string enum, required/optional/nullable, `additionalProperties` cases | `tests/test_t07.py`, `tests/test_response_strategy.py`, and corpus compile checks |
| GET, POST, PUT, PATCH, DELETE | `tests/test_t07.py`, generated fixtures |
| Path/query/header common scalar and array forms | runtime tests plus Petstore local-HTTP assertions |
| `application/json` request bodies and JSON responses | T07 tests and Petstore demo |
| 200, 201, 204, equal-schema multiple success statuses, structured non-2xx | `tests/test_response_strategy.py`, T07 tests; 204/non-2xx demo |
| Multiple distinct success schemas / operation response enum | `tests/test_response_strategy.py`; Petstore real-HTTP 200/201 enum assertions |
| Declared JSON response with mismatched wire Content-Type | runtime media-type tests; Petstore real-HTTP `SdkError.Unsupported` probe |
| Bearer, Basic, API-key header and API-key query | Petstore real-HTTP demo |
| Base URL override | CLI and Petstore demo |
| Stable naming, diagnostics and regeneration | `tests/test_t13_determinism.py` and demo hash comparison |

## Supported with limited verification

| Capability | Limit |
|---|---|
| YAML | Common YAML fixtures are covered; full YAML edge-case compatibility is not promised. |
| `additionalProperties` with a schema | Fixture/codegen coverage exists; no real-HTTP Petstore case. |
| `application/*+json` | Only accept it where the current normalizer classifies it as safe JSON; no broad media-type claim. |
| HEAD transport mapping | Runtime maps HEAD, but the public supported operation profile and local-HTTP demo do not claim HEAD. |
| Bounded real-world corpus | Five local real-world specs compiled: official OAI Petstore 3.0 plus project Petstore and curated GitHub/OpenAI/JSONPlaceholder subsets. The measured 12/12 operation total is not a full-document support rate. |

## Explicitly unsupported

- OpenAPI 3.1.x and OpenAPI 2.0;
- external, network, cyclic, or missing local `$ref`;
- `oneOf`, `anyOf`, `discriminator`, and `allOf`;
- non-string enums (integer/boolean) and duplicate enum wire values;
- multipart/form-data, form-urlencoded, binary streaming, XML;
- callbacks and webhooks;
- OAuth authorization flows and OpenID Connect flows;
- cookie parameters and arbitrary parameter serialization styles (including matrix, label and deepObject);
- unclassified request/response media types.

For unsupported semantics, generation must stop with a deterministic diagnostic; it must not silently emit wire behaviour known to be wrong. `Json` is a safe fallback only when the normalizer documents that actual wire behaviour is preserved. The `oneOf` negative fixture covers the no-silent-fallback rule.

## Not verified or not promised

- Full-document or network-fetched API acceptance rates; the committed corpus uses small curated subsets and one full 3-operation OAI sample.
- Complex server-variable resolution.
- Every legal OpenAPI 3.0 serialization/default combination.
- Arbitrary non-JSON response decoding. Declared JSON responses with a non-JSON wire media type are rejected explicitly rather than decoded.

See [acceptance evidence](ACCEPTANCE.md) and the [Petstore demo](DEMO_SCRIPT.md) for the exact release evidence.

## Generator correctness regression coverage

`tests/test_generator_regressions.py` exercises the real CLI and generated SDK
against a local HTTP server: inline objects, colliding component and operation
names, security alternatives, query arrays, typed headers, mixed body/204
responses, and declared server defaults. Inline objects (including nested fields,
array items, request bodies and responses) currently use `Json` with an explicit
`schema.json_fallback` warning; named component objects retain generated structs.
Unsupported keyword diagnostics stop lowering and the CLI returns exit code 4.

Canonical IR preserves `style` and `explode`, security alternatives as arrays of
scheme names, and the allocated `response_name`. No-body response enum variants
carry `Unit`. The codegen reader accepts legacy flat security arrays as a single
AND group. Joined query arrays encode each item before inserting comma separators.

`tests/test_acceptance_regressions.py` locks the fixes from the 2026-11-11
independent acceptance review: unclassified request/response media types,
external/cyclic/missing refs, root webhooks and callbacks, and non-string or
duplicate enums all stop the CLI with exit code 4, a stable diagnostic
(`unsupported.media_type`, `unsupported.ref`, `unsupported.keyword`,
`unsupported.enum`), and no generated SDK.

Int64 wire decoding is number-based and exact. A declared `integer/int64`
response or field decodes from a JSON number, never a JSON string; integers
within 2^53-1 are taken losslessly from the parsed value, and larger integers
are parsed from the preserved source text so values such as `9007199254740993`
and the Int64 bounds `±9223372036854775807/8` are not rounded. Out-of-range
values, booleans, strings, and non-integral numbers fail with a structured
decode error. Integral decimal/exponent forms (`1.0`, `1e3`) decode to their
exact integer value, matching the `Int` decoder.
