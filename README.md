# oas2moon

> Working name.

`oas2moon` is a deterministic, compile-verified **OpenAPI 3.0.x → typed MoonBit client SDK generator**.

## Outcome

```text
openapi.yaml / openapi.json
        ↓
      oas2moon
        ↓
generated MoonBit client package
        ↓
moon fmt + moon check
        ↓
typed API calls
```

Target experience:

```moonbit
let client = @petstore.Client::new(
  base_url="https://petstore.example.com",
  auth=@petstore.Auth::bearer(token),
)

let pet = client.get_pet_by_id(id=42)
println(pet.name)
```

## Principles

1. Correct before broad.
2. Generated code must compile.
3. Same input must produce byte-identical output.
4. Generated APIs should feel MoonBit-native.
5. Reuse mature ecosystem components instead of rebuilding infrastructure.
6. Keep a small stable runtime boundary around HTTP transport.

## Documents

- `docs/PROJECT_SPEC.md`
- `docs/ARCHITECTURE.md`
- `docs/SUPPORTED_OPENAPI.md`
- `docs/ACCEPTANCE.md`
- `docs/FEASIBILITY_SPIKE.md`
- `docs/RESEARCH.md`
- `docs/DEVELOPMENT_PLAN.md`
- `AGENTS.md`
- `prompts/CODEX_GOAL.md`

## Status

```yaml
project: oas2moon
stage: phase1_complete
decision: GO
primary_language: MoonBit
openapi_target: 3.0.0-3.0.3
evidence: docs/PHASE1_REPORT.md
spike_reproduce: pwsh -NoProfile -File spike/run_spike.ps1
```

The feasibility spike built and verified the complete Petstore vertical slice.
Phase 1 now provides the formal adapter, versioned Frontend Model, support
validator, diagnostics contract, and canonical Client IR. See
`docs/SPIKE_REPORT.md` and `docs/PHASE1_REPORT.md`. Model codegen/runtime
expansion (Phase 2+) has not started.
