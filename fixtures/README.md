# Fixtures

## `petstore/`

Owned minimal OpenAPI 3.0.x fixture for feasibility/regression tests.

It should contain only features needed by the V1 spike.

## `phase1_5/`

Pinned normalized Frontend Model fixtures used by the Phase 1.5 differential
tests. They are source-controlled test inputs, not generated build output.

## `regression/`

Focused regression inputs for previously observed parser/validator behavior.

## `real-world/`

Store pinned public OpenAPI fixtures or reduced reproducible subsets with:

- source URL/repository;
- source license;
- pinned version/commit;
- reduction method if subset;
- expected operation count.

License handling is part of the fixture contract. Every third-party-derived
file must have a pinned source and an SPDX/terms entry in
`THIRD_PARTY_NOTICES.md`. Do not describe a source as merely "public". If an
upstream license cannot be established, keep the fixture project-authored or
fetch it during tests instead of committing copied source material.

Do not silently modify a real-world fixture merely to make generation pass.
