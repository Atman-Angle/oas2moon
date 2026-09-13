# Acceptance Criteria — oas2moon

## Project states

- `NOT_READY`
- `SPIKE_VERIFIED`
- `V1_VERIFIED`

Code existing is not a release state.

## A. Feasibility gate

All must pass before full V1 work. Every item below was verified by execution on
2026-09-13; the evidence and raw measurements are in `docs/SPIKE_REPORT.md`, and
the whole chain is reproducible with `pwsh -NoProfile -File spike/run_spike.ps1`.

- [x] Petstore OpenAPI 3.0 parses.
- [x] common YAML path works or cleanly converts through existing ecosystem support.
- [x] local `$ref` resolves.
- [x] object, enum, array, optional, nullable generate valid MoonBit.
- [x] at least 3 operations generate.
- [x] generated package passes `moon fmt`.
- [x] generated package passes `moon check`.
- [x] generated client performs GET, POST, DELETE against a real local server.
- [x] method/path/query/header/body are asserted.
- [x] typed response decode is asserted.
- [x] same input twice produces byte-identical trees.
- [x] no large missing infrastructure must be built first.
- [x] fresh duplicate scan finds no mature direct MoonBit equivalent.

Only then set `SPIKE_VERIFIED`.

State: `SPIKE_VERIFIED` (spike scope only — no V1 feature claims are implied by
this section).

## B. V1 functional acceptance

### Models

- [ ] primitive mappings
- [ ] object structs
- [ ] typed arrays
- [ ] enums
- [ ] required/optional
- [ ] nullable policy
- [ ] local refs
- [ ] naming collisions
- [ ] reserved identifiers

### Operations

- [ ] GET
- [ ] POST
- [ ] PUT
- [ ] PATCH
- [ ] DELETE
- [ ] path parameters
- [ ] query parameters
- [ ] header parameters
- [ ] JSON body
- [ ] 200 response
- [ ] 201 response
- [ ] 204 response
- [ ] multiple success statuses
- [ ] structured non-2xx error

### Authentication

- [ ] Bearer
- [ ] Basic
- [ ] API key header
- [ ] API key query
- [ ] missing required credentials fail cleanly

### Diagnostics

- [ ] unsupported schema → stable diagnostic
- [ ] unsupported parameter style → stable diagnostic
- [ ] unsupported media type → no silent approximation
- [ ] deterministic diagnostic ordering

## C. Compile verification

Every official supported fixture must:

- generate;
- `moon fmt`;
- `moon check`.

Publish real metrics only, e.g.:

```text
Specs                  80
Operations            640
Generated              80/80
moon check             80/80
Deterministic regen    80/80
```

## D. HTTP integration

At minimum assert with a real local HTTP server:

- URL path encoding;
- supported query array encoding;
- headers;
- JSON body;
- auth injection;
- 204;
- JSON decode;
- non-2xx behavior.

Capture transport alone is insufficient.

## E. Determinism

Representative corpus must verify:

- identical generated file lists;
- identical file bytes;
- no timestamps;
- no random IDs;
- no absolute local paths;
- stable sort order;
- stable diagnostics.

## F. Real-world corpus

Before V1, include at least 3 real public API specs/subsets.

Recommended:

- GitHub REST OpenAPI subset;
- OpenAI OpenAPI subset;
- one additional conventional REST API.

For each publish:

```text
operations_total
operations_supported
operations_rejected
rejection_reasons
compile_pass
```

If common-profile support is too low to be useful, reassess scope before broad claims.

## G. Cross-platform CI

Minimum:

- Ubuntu generator tests;
- Windows generator tests;
- generated-package compile verification where supported;
- transport claims match actual CI evidence.

## H. Final gate

Set `V1_VERIFIED` only if:

- all claimed V1 features have tests;
- official corpus generated packages compile;
- deterministic regen passes;
- real HTTP integration passes;
- README claims equal measured capability;
- no known unsupported behavior is silently accepted.
