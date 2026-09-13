"""Formal Phase 1 OpenAPI 3.0.x frontend and canonical Client IR.

This package is deliberately limited to the frontend/IR phase. The stage
boundaries are::

    Frontend Model  ->  Support Validation  ->  Client IR
                    ->  Naming / Type Mapping  ->  Code emission

The original OpenAPI document is never read here. ``src/frontend_adapter`` owns
OpenAPI parsing and hands over a versioned project-owned model. This package
does not import mooncontract and is not a codegen/runtime implementation.
"""

__all__ = ["frontend", "support", "ir", "naming", "typemap", "lower", "pipeline"]
