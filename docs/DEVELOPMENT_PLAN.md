# Development Plan

## Phase 0 — Feasibility

Outcome:

```text
Petstore → generated MoonBit client → moon check → real HTTP → typed response
```

No broad feature work before this passes.

## Phase 1 — Frontend + IR

Status: **COMPLETE (2026-09-13)**. The formal frontend adapter, versioned
Frontend Model, support validator, canonical Client IR, deterministic naming,
and Ubuntu CI workflow are implemented. See `docs/PHASE1_REPORT.md`.

Deliver:

- OpenAPI adapter;
- raw sidecar extraction;
- diagnostics;
- Client IR;
- deterministic naming;
- support classifier.

Gate:

- supported Petstore subset normalizes;
- unsupported features diagnose cleanly;
- IR order is deterministic.

## Phase 2 — Model generation

Deliver:

- primitives;
- objects;
- arrays;
- enums;
- optional/nullable;
- refs;
- JSON encode/decode.

Gate:

- generated model package compiles;
- round-trip tests pass;
- naming collision tests pass.

## Phase 3 — Operations

Deliver:

- GET/POST/PUT/PATCH/DELETE;
- path/query/header;
- JSON body;
- response strategy;
- base URL.

Gate:

- capture transport tests;
- generated package compile tests.

## Phase 4 — Runtime + auth

Deliver:

- stable request/response model;
- transport adapter;
- HTTP errors;
- Bearer;
- Basic;
- API key header/query.

Gate:

- real HTTP integration;
- auth assertions;
- non-2xx behavior.

## Phase 5 — Corpus + hardening

Deliver:

- Petstore;
- GitHub subset;
- OpenAI subset;
- third real API subset;
- coverage reporting;
- deterministic regen;
- Windows + Ubuntu CI.

Gate:

- measured support table;
- all claimed supported cases compile;
- no silent unsupported semantics.

## Phase 6 — Release quality

Deliver:

- Mooncakes package if appropriate;
- clean CLI;
- concise README;
- examples;
- architecture/support docs;
- reproducible release process.

Do not expand into OpenAPI 3.1 or advanced unions before V1 quality gates are complete.
