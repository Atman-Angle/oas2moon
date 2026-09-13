# Formal Phase 1 implementation

`frontend_adapter/` is the only package that imports
`Han-Wentao/mooncontract`. It parses JSON/YAML and emits the versioned,
project-owned Frontend Model (`frontendModelVersion: 1`). Its bounded raw
sidecar only inspects schema-bearing nodes and known operation feature slots.

`oas2moon/` consumes that model, validates the supported OpenAPI profile, and
lowers it to the canonical Client IR. It does not import mooncontract, read
the original OpenAPI document, or emit MoonBit source. Code emission and
runtime work remain later phases.
