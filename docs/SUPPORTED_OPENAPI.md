# Supported OpenAPI profile

This is a bounded OpenAPI 3.0.x profile, not a claim of full OpenAPI support. “Tested” means evidence exists in the named test, fixture, demo, or hosted CI; it does not make unlisted combinations supported.

## Supported and evidenced

| Capability | Evidence |
|---|---|
| OpenAPI 3.0.0–3.0.3 JSON; common YAML | `tests/test_t10_cli.py`, `tests/test_phase1_5.py` |
| Local component `$ref` | Petstore fixture and demo generation |
| Primitive, object, array, string enum, required/optional/nullable, `additionalProperties` cases | phase tests and phase-2 fixtures |
| GET, POST, PUT, PATCH, DELETE | `tests/test_t07.py`, generated fixtures |
| Path/query/header common scalar and array forms | runtime tests plus Petstore local-HTTP assertions |
| `application/json` request bodies and JSON responses | T07 tests and Petstore demo |
| 200, 201, 204, equal-schema multiple success statuses, structured non-2xx | `tests/test_response_strategy.py`, T07 tests; 204/non-2xx demo |
| Bearer, Basic, API-key header and API-key query | Petstore real-HTTP demo |
| Base URL override | CLI and Petstore demo |
| Stable naming, diagnostics and regeneration | `tests/test_t13_determinism.py` and demo hash comparison |

## Supported with limited verification

| Capability | Limit |
|---|---|
| YAML | Common YAML fixtures are covered; full YAML edge-case compatibility is not promised. |
| `additionalProperties` with a schema | Fixture/codegen coverage exists; no real-HTTP Petstore case. |
| Multiple distinct success schemas / operation response enum | Represented and unit-tested by response-strategy fixtures; no real-HTTP demo case. |
| `application/*+json` | Only accept it where the current normalizer classifies it as safe JSON; no broad media-type claim. |
| HEAD transport mapping | Runtime maps HEAD, but the public supported operation profile and local-HTTP demo do not claim HEAD. |

## Explicitly unsupported

- OpenAPI 3.1.x and OpenAPI 2.0;
- external or network `$ref`;
- `oneOf`, `anyOf`, `discriminator`, and `allOf`;
- multipart/form-data, form-urlencoded, binary streaming, XML;
- callbacks and webhooks;
- OAuth authorization flows and OpenID Connect flows;
- cookie parameters and arbitrary parameter serialization styles (including matrix, label and deepObject);
- unclassified request/response media types.

For unsupported semantics, generation must stop with a deterministic diagnostic; it must not silently emit wire behaviour known to be wrong. `Json` is a safe fallback only when the normalizer documents that actual wire behaviour is preserved. The `oneOf` negative fixture covers the no-silent-fallback rule.

## Not verified or not promised

- Real-world API corpus acceptance rates, operation counts, and compatibility metrics (T12 has not been delivered).
- Complex server-variable resolution.
- Every legal OpenAPI 3.0 serialization/default combination.
- Non-JSON response decoding, response enums, and `UnsupportedMediaType` over a real HTTP fixture.

See [acceptance evidence](ACCEPTANCE.md) and the [Petstore demo](DEMO_SCRIPT.md) for the exact release evidence.
