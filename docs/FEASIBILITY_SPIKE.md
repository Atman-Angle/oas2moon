# Feasibility Spike

## Purpose

Prove one complete end-to-end path before broad development.

## Fixture

Use an OpenAPI 3.0.x Petstore-style fixture containing:

- object;
- enum;
- array;
- required/optional;
- nullable;
- local `$ref`;
- path/query parameters;
- JSON body;
- JSON response;
- API key or Bearer auth.

## Required operations

At least:

```text
getPetById
addPet
deletePet
```

## Questions

1. Can current MoonBit ecosystem code parse the fixture without a new full parser?
2. Can local refs normalize into stable Client IR?
3. Can generated models compile?
4. Can path/query/header/body serialize correctly?
5. Can generated code call a real local server?
6. Can typed response decode work?
7. Can auth be applied cleanly?
8. Can output be byte-deterministic?
9. Does Windows introduce a blocker?
10. Has a direct competitor appeared?

## Evidence

Record toolchain/dependency versions.

Run generated package through:

```text
moon fmt
moon check
moon test
```

Generate twice and hash all generated files.

Run a real fixture server and assert:

```text
method
path
query
headers
body
response
```

## Stop conditions

Return `CONDITIONAL_GO` or `NO_GO` if:

- a mature direct competitor exists;
- common OpenAPI requires building a large unrelated parser/runtime first;
- useful generated MoonBit types cannot compile;
- HTTP minimum path does not work;
- deterministic generation is unreliable;
- real-world supported coverage is too low.

## Output

Create `docs/SPIKE_REPORT.md`:

```text
Verdict
Environment
Dependency audit
Competition re-check
Petstore results
Compile results
HTTP integration results
Determinism results
Windows results
Hidden blockers
Recommended V1 boundary
```

Only a verified spike authorizes broad V1 development.
