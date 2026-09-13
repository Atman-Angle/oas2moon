# Phase 1.5 Report — MoonBit Core Authority

Date: 2026-09-13
Verdict: CONDITIONAL_GO

## Migrated modules

`src/core_moonbit/main.mbt` is now the production-side lowering authority for the
Phase 1 Frontend Model JSON contract. It consumes versioned normalized Frontend
Model data only and emits canonical Client IR JSON. The implementation covers
canonical model/operation ordering, local `$ref` type mapping, `int64`, arrays,
enums, required/optional/nullable presence, request-body normalization,
parameter/header naming used by the Phase 1 profile, bearer security propagation,
and deterministic serialization. It imports neither Python nor mooncontract.

A white-box MoonBit test suite is present in `src/core_moonbit/core_wbtest.mbt`.
No Phase 2 model/operation emitter or runtime work was started.

## Python remaining responsibilities

Python remains only as the differential reference oracle and for tests, fixture
HTTP server/orchestration, corpus/fixture tooling, reporting, and CI helpers.
The production MoonBit core executable does not invoke Python to obtain IR.

## Differential parity

The differential suite compares canonical JSON (not approximate semantics) for a targeted 9-case corpus:

- Petstore JSON and YAML
- auth/security propagation
- request-body normalization
- `int64`
- enum/local `$ref`
- reserved-word naming
- illegal identifier and deterministic collision naming
- multiple response statuses

Unsupported `oneOf` and diagnostic/RFC 6901 behavior remain covered by dedicated
negative/regression tests. Results:

```text
cases_total = 9
cases_equal = 9
cases_failed = 0
```

The parity comparison includes models, enum members, field ordering and
presence, primitive and `Int64` mapping, array/local-ref mapping, operation
ordering, parameters, request bodies, numeric response statuses, auth schemes,
and operation security.

## Test commands and results (Windows)

PowerShell 7.6.5 on Windows:

- `moon fmt --check` (`src/core_moonbit`): PASS
- `moon check --target native --deny-warn`: PASS
- `moon test --target native --deny-warn`: PASS — **5 tests passed**
- `pytest -q tests`: PASS — **9 tests passed**
- `pwsh -NoProfile -File spike/run_spike.ps1`: PASS

The spike regression still proves generated SDK compilation/tests, real local
HTTP GET/POST/DELETE, path/query/header/auth/body behavior, typed decoding,
negative oneOf rejection, and byte-identical regeneration. Latest aggregate
hash is `5abb2d83155053a2e8679b173e54742e66887eef6bb5d33afd3ad8cadbe3474e`.

## MoonBit core test coverage

The five real white-box tests cover primitive/`Int64` mapping, arrays and local
refs, reserved/illegal naming cases represented by the Phase 1 helpers, operation
ordering, and deterministic JSON serialization. Differential and Python tests
cover required/optional/nullable fields, request bodies, auth/security,
Petstore JSON/YAML parity, false-positive regression, and unsupported oneOf
negative behavior.

## Windows result

PASS for the supported ASCII-path workflow. The previously documented MoonBit
filesystem limitation for non-ASCII Windows paths remains; the differential
suite writes outputs under the ASCII repository path and does not hide this
constraint. No fatal blocker was observed for the current Windows environment.

## Ubuntu CI result

Not verified in this environment. `.github/workflows/phase1-ubuntu.yml` contains
MoonBit fmt/check steps and the Python test job, but no completed hosted CI run
is available as evidence. Workflow presence is therefore not counted as an
Ubuntu PASS.

## Remaining semantic differences / risks

No differences were found in the 9-case targeted canonical IR corpus.
The MoonBit core is intentionally scoped to the existing Phase 1 Frontend Model
contract; broader support validation/diagnostic construction remains at the
formal adapter/validator boundary and must stay synchronized when that contract
expands. Generalized identifier tokenization and collision corpora beyond the
current Phase 1 cases should receive additional tests before Phase 2.

## Final verdict

**CONDITIONAL_GO**. The production path no longer depends on Python semantics,
strict covered differential parity is green (`0` failures), real MoonBit core
tests pass, Windows passes, and the full spike remains green. The verdict stays
conditional solely because Ubuntu CI has not actually executed successfully in
this environment and broader-than-covered collision/diagnostic corpus evidence
is still outstanding.

Phase 2 was not started.
