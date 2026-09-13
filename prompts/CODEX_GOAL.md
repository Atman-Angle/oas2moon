# Codex Goal — oas2moon

Build a deterministic, compile-verified OpenAPI 3.0.x → typed MoonBit client SDK generator.

Do **not** immediately implement the full product.

## First task: feasibility spike

Treat as authority:

1. `docs/PROJECT_SPEC.md`
2. `docs/ARCHITECTURE.md`
3. `docs/SUPPORTED_OPENAPI.md`
4. `docs/ACCEPTANCE.md`
5. `docs/FEASIBILITY_SPIKE.md`

Before implementation, inspect the current real ecosystem/toolchain and verify current APIs/status of:

- `Han-Wentao/mooncontract`
- `moonbit-community/yaml`
- `moonbitlang/async`
- `moonbit-community/elasticsearch.mbt`
- `mizchi/codegen`
- `Lfan-ke/moonctl`

Perform a fresh duplicate scan for a generic OpenAPI 3.0.x → typed MoonBit client generator.

## Intended architecture

```text
OpenAPI
→ frontend adapter
→ support validation
→ canonical Client IR
→ naming/type mapping
→ deterministic MoonBit codegen
→ generated SDK
→ small runtime transport boundary
→ real HTTP
```

Do not emit MoonBit directly from raw JSON traversal.

Do not spread dependency-specific types throughout the repository.

Do not lower acceptance criteria to make the spike pass.

## Spike must prove

- Petstore parses;
- local `$ref` works;
- typed models generate;
- GET / POST / DELETE generate;
- path/query/header/JSON body behavior is correct;
- generated package passes `moon fmt` and `moon check`;
- real HTTP integration passes;
- typed response decode passes;
- two generations are byte-identical;
- no major missing infrastructure blocks the project.

## Do not implement during spike

- OpenAPI 3.1;
- external refs;
- oneOf/anyOf/discriminator;
- multipart;
- XML;
- OAuth flows;
- callbacks/webhooks;
- arbitrary parameter styles;
- GUI.

## Required final artifact

Write `docs/SPIKE_REPORT.md`.

Verdict must be one of:

- `GO`
- `CONDITIONAL_GO`
- `NO_GO`

Support the verdict with actual commands/tests/results.

If `GO`, propose the smallest Phase 1 implementation following `docs/DEVELOPMENT_PLAN.md`.

Do not begin broad V1 implementation until the spike proves the gate.
