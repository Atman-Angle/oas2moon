# Phase 1 Report — Frontend + Canonical Client IR

> **Historical report.** Dates, commands, and paths here describe a completed
> phase and are not current release evidence; see `docs/ACCEPTANCE.md`.

Date: 2026-09-13
Status: **COMPLETE**
Phase 2: **not started**

## Outcome

Phase 1 converts the verified spike boundary into a formal, testable pipeline:

```text
OpenAPI JSON/YAML
  → src/frontend_adapter (MoonBit + mooncontract 0.1.0)
  → versioned Frontend Model (frontendModelVersion = 1)
  → src/oas2moon/support.py (support validation + diagnostics)
  → src/oas2moon/lower.py (canonical Client IR)
  → naming/type mapping
```

The formal implementation does not add V1 code emission or runtime features.

## Implementation changes

- Added `src/frontend_adapter/`, a MoonBit executable that delegates parsing to
  `Han-Wentao/mooncontract@0.1.0` and emits a project-owned normalized model.
- Kept mooncontract types inside the adapter boundary. `src/oas2moon` contains
  no mooncontract imports or parser model references.
- Added `frontendModelVersion: 1` and strict Python model parsing in
  `src/oas2moon/frontend.py` covering API metadata, servers, security,
  schemas/refs, operations, parameters, request bodies, and responses.
- Replaced the spike's whole-document keyword walk with a bounded sidecar scan.
  It inspects schema-bearing locations and operation `callbacks`/`webhooks`
  only, so `oneOf`/`anyOf` text inside examples/defaults/descriptions does not
  produce a false positive.
- Extended diagnostics with stable `code`, `severity`, `json_pointer`,
  `operation_id`, `message`, and `suggestion` fields, plus deterministic sort
  order.
- Formalized Client IR vocabulary (`Api`, `Model`, `TypeRef`, `Field`,
  `Operation`, `Parameter`, `RequestBody`, `Response`, `AuthScheme`, `Server`)
  independently of the frontend parser.
- Added deterministic model/operation/parameter/auth ordering and collision-
  safe MoonBit naming tests.
- Added Ubuntu CI workflow `.github/workflows/phase1-ubuntu.yml` for Python
  frontend/IR tests and MoonBit adapter compile checks.

## Test commands and results

Windows PowerShell 7.6.5, repository root `D:\oas2moon`:

```text
pytest -q tests
7 passed

Push-Location src/frontend_adapter
moon fmt --check                    PASS
moon check --target native --deny-warn PASS
Pop-Location

pwsh -NoProfile -File spike/run_spike.ps1 PASS
```

The spike regression still reports:

- Petstore JSON/YAML normalized equivalently;
- local `$ref`, object/enum/array/optional/nullable behavior preserved;
- generated compile/test gates pass;
- real GET/POST/DELETE integration passes with 3 requests and 11 wire checks;
- deterministic regeneration passes;
- negative `oneOf` input exits non-zero and writes no output.

Additional Phase 1 tests verify:

- Frontend Model version and strict shape;
- local ref identity preservation;
- false-positive fixture accepted;
- unsupported `oneOf` rejected with stable pointer/code;
- IR ordering and parser independence;
- naming collisions and reserved words;
- diagnostic contract keys and repeatability.

Final verification was rerun on **September 13, 2026** after the Phase 1
hardening pass. The sidecar now scans path-item inherited parameter schemas,
uses RFC 6901 escaping for diagnostic pointers, and separates unsupported
keyword findings from ignored-keyword findings. The same commands still pass:

```text
pytest -q tests                         7 passed
moon fmt --check                         PASS
moon check --target native --deny-warn   PASS
pwsh -NoProfile -File spike/run_spike.ps1 PASS
```

The negative `oneOf` case now reports only `unsupported.keyword` for the
schema location (never a contradictory `ignored.keyword` warning), and a
path-item parameter such as `/items/{id}` is reported at the escaped pointer
`#/paths/~1items~1{id}/parameters/0/schema/oneOf`.

## Environment and platform notes

- Verified toolchain: `moon 0.1.20260819`, `moonc v0.10.9+6e6c44045`,
  Python 3.13.7, Git 2.53.0.windows.2.
- The verified async pin remains `moonbitlang/async 0.20.2`; Phase 1 does not
  upgrade it to incompatible `0.21.3`.
- `moon fmt --check` requires `git` available on `PATH`; this Windows host has
  Git and the check passes.
- MoonBit native filesystem handling of non-ASCII Windows path components still
  fails in `moonbitlang/x/fs`. Tests intentionally use an ASCII workspace path
  and the limitation remains an explicit environment constraint, not a hidden
  fallback or filesystem rewrite.
- Ubuntu CI is configured for the core frontend/IR tests. It was not executed
  locally on this Windows host; CI remains the execution evidence for Ubuntu.

## Known risks / limits

This phase deliberately does not implement OpenAPI 3.1, external refs,
`oneOf`/`anyOf`/discriminator, multipart, XML, OAuth flows,
callbacks/webhooks, broad parameter serialization, or new runtime/codegen
behavior. The IR records required/optional/nullable presence explicitly, but
request-side tri-state encoding and multi-response enums remain later work.

The adapter sidecar is intentionally narrow and exists only because the pinned
mooncontract API drops some unsupported keywords. Any future supported keyword
must be added to the project model and validator deliberately, with tests.

## Phase 1 gate decision

**GO for Phase 1 completion.** The supported Petstore subset normalizes, the
unsupported feature path fails closed, diagnostics and IR ordering are stable,
and the formal MoonBit adapter compiles on the current Windows toolchain. Phase
2 is not entered automatically.
