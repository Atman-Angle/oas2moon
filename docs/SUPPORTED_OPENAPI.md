# Supported OpenAPI Profile — V1

This is a product contract. V1 does **not** claim full OpenAPI 3.0 support.

## Versions

| Feature | V1 |
|---|---|
| OpenAPI 3.0.0–3.0.3 | Supported |
| OpenAPI 2.0 | Not supported |
| OpenAPI 3.1.x | Not supported |

## Input

| Feature | V1 |
|---|---|
| JSON | First-class |
| Common YAML | Supported through ecosystem parser |
| Full YAML edge cases | Not guaranteed |
| local `$ref` | Supported |
| external/network `$ref` | Not supported |

## Schema

| Feature | V1 |
|---|---|
| string/integer/number/boolean | Supported |
| array | Supported |
| object/properties | Supported |
| enum | Supported |
| required | Supported |
| nullable | Supported |
| additionalProperties true/false | Supported |
| typed additionalProperties schema | Conditional / Json fallback |
| allOf | Not in initial V1 |
| oneOf / anyOf | Not supported |
| discriminator | Not supported |
| XML metadata | Not supported |

## Operations

| Feature | V1 |
|---|---|
| GET/POST/PUT/PATCH/DELETE | Supported |
| HEAD | Optional if spike is clean |
| operationId | Preferred |
| missing operationId | Deterministic generated name |

## Parameters

| Feature | V1 |
|---|---|
| path scalar | Supported |
| query scalar | Supported |
| query array | Supported for common form semantics |
| header scalar | Supported |
| header array | Supported for common simple semantics |
| cookie | Not required |
| deepObject/matrix/label | Not supported |
| arbitrary style/explode | Not supported |

## Request body

| Feature | V1 |
|---|---|
| application/json | Supported |
| application/*+json | Conditional |
| form-urlencoded | Not supported |
| multipart/form-data | Not supported |
| binary streaming | Not supported |
| XML | Not supported |

## Responses

| Feature | V1 |
|---|---|
| exact 2xx | Supported |
| 204 | Supported |
| multiple success statuses | Supported |
| JSON body | Supported |
| default response | Error path where feasible |
| non-JSON response | Raw/unsupported depending on operation |

## Authentication

| Feature | V1 |
|---|---|
| Bearer | Supported |
| Basic | Supported |
| API key header | Supported |
| API key query | Supported |
| OAuth2 flow | Not supported |
| OpenID Connect flow | Not supported |
| anonymous operation | Supported |

## Servers

| Feature | V1 |
|---|---|
| explicit base URL override | Supported |
| root servers[0] | Supported |
| complex server-variable resolution | Not required |

## Unsupported behavior

No silent approximation.

The generator must either:

- emit a stable error diagnostic; or
- use a documented `Json` fallback only when wire behavior remains correct.
