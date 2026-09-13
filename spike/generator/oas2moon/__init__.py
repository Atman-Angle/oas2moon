"""Minimal OpenAPI 3.0.x -> typed MoonBit client SDK generator.

This package is the feasibility-spike generator. It is deliberately small, but
the stage boundaries are the ones the project is built on::

    Frontend Model  ->  Support Validation  ->  Client IR
                    ->  Naming / Type Mapping  ->  Code emission

The original OpenAPI document is never read here. ``spike/frontend`` owns all
OpenAPI knowledge (it delegates parsing to ``Han-Wentao/mooncontract``) and
hands over a normalized document. Generated code is therefore produced by
walking the Client IR, never by walking raw OpenAPI JSON.
"""

__all__ = ["frontend", "support", "ir", "naming", "typemap", "lower", "emit"]
