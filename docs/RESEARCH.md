# Ecosystem / Competition Notes

> Re-check before development and again before submission.

## Target gap

```text
standard OpenAPI 3.0.x
        ↓
generic typed MoonBit client SDK
```

At project establishment, no mature public MoonBit project was found covering this full outcome.

## Adjacent projects

### `Han-Wentao/mooncontract`

Role:

```text
OpenAPI → validation / deterministic mock / replay
```

Potentially reusable as the initial OpenAPI frontend.

Boundary: not typed client SDK generation.

### `Lfan-ke/moonapi`

Role:

```text
MoonBit routes/server → OpenAPI
```

Opposite direction.

### `Lfan-ke/moonctl`

Role:

```text
.api / proto / sql → MoonBit scaffolding + OpenAPI
```

Potential future collision risk because it already has substantial codegen infrastructure.

Monitor specifically for:

```text
OpenAPI import → typed MoonBit HTTP client
```

### `WeiR-h/moonapi-check`

Role:

```text
old OpenAPI + new OpenAPI → compatibility diagnostics
```

Not client generation.

### `Showichiro/moon_openapi_cli`

OpenAPI extraction/search/agent-oriented tooling.

Not typed SDK generation.

### `moonbit-community/elasticsearch.mbt`

Important technical reference proving MoonBit can support:

- generated request/response types;
- generated endpoint wrappers;
- auth;
- path/query encoding;
- typed decode;
- hundreds of endpoints;
- Json escape hatches.

It is service-specific, not generic OpenAPI codegen.

## External reference

Use OpenAPI Generator as a design/fixture reference for:

- generator architecture;
- naming;
- type mapping;
- feature declarations;
- test corpus;
- language backend behavior.

Do not make the competition implementation primarily a Java/OpenAPI-Generator plugin.

## Re-check triggers

Reassess immediately if:

1. `moonctl` adds generic OpenAPI client generation;
2. Mooncakes gains such a generator;
3. a September hackathon repo appears with the same outcome;
4. OpenAPI Generator gains a substantial MoonBit target;
5. another MoonBit project demonstrates broader compiling client generation.

If a direct competitor appears, compare actual:

- supported profile;
- API quality;
- deterministic behavior;
- compile verification;
- real-world corpus;
- integration tests;
- MoonBit implementation depth.
