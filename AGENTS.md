# AGENTS.md

## Authority

Before changing code, read:

1. `docs/PROJECT_SPEC.md`
2. `docs/ARCHITECTURE.md`
3. `docs/SUPPORTED_OPENAPI.md`
4. `docs/ACCEPTANCE.md`

These documents define the project boundary.

## Core goal

Build a deterministic, compile-verified OpenAPI 3.0.x → typed MoonBit client SDK generator.

The project is successful only when generated SDKs:

- compile with the real MoonBit toolchain;
- perform correct HTTP requests;
- decode supported responses into useful MoonBit types;
- fail explicitly on unsupported semantics;
- regenerate deterministically.

Code quantity is not evidence of completion.

## Inspect before implementing

Before adding infrastructure, inspect the current ecosystem and real APIs of:

- `Han-Wentao/mooncontract`
- `moonbit-community/yaml`
- `moonbitlang/async`
- `moonbit-community/elasticsearch.mbt`
- `mizchi/codegen`
- `Lfan-ke/moonctl`

Do not assume their APIs from old notes.

## Keep boundaries

Do not mix:

- OpenAPI parsing;
- normalization;
- client IR;
- naming/type mapping;
- code emission;
- runtime transport.

Parser models are not the codegen authority.

## No silent fallback

Unsupported behavior must become either:

- a deterministic diagnostic; or
- an explicitly documented safe fallback to `Json`.

Never silently generate wire behavior known to be wrong.

## Generated code

Generated code must:

- pass `moon fmt`;
- pass `moon check`;
- have stable imports and ordering;
- contain no timestamps/random IDs;
- expose useful typed APIs.

## Runtime isolation

Generated operation/model code must not scatter direct `moonbitlang/async/http` calls.

Transport-specific behavior belongs behind the runtime adapter.

## Tests

Every supported feature should have:

1. parse/normalize coverage;
2. codegen coverage;
3. generated-package compile coverage;
4. HTTP behavior coverage where wire semantics matter.

## V1 scope restraint

Do not add these unless the support matrix is deliberately revised:

- OpenAPI 3.1;
- external/network `$ref`;
- `oneOf` / `anyOf` / discriminator;
- multipart;
- XML;
- callbacks/webhooks;
- OAuth authorization flows;
- arbitrary parameter serialization styles.

If a new mature direct competitor appears, stop broad implementation and reassess before continuing.
