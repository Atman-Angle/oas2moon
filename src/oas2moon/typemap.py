"""Naming / Type Mapping.

Schema kinds become MoonBit types here. Anything this module cannot map was
already rejected by Support Validation, so an unmappable schema is a bug in the
generator rather than an input the user can produce.
"""

from __future__ import annotations

from . import naming
from .frontend import Schema
from .ir import (
    IR_JSON,
    SCALAR_BOOL,
    SCALAR_DOUBLE,
    SCALAR_INT,
    SCALAR_INT64,
    SCALAR_STRING,
    IrType,
    array_of,
    named,
)


class TypeMappingError(RuntimeError):
    """A schema reached the mapper that Support Validation should have rejected."""


def ref_target(ref: str) -> str:
    """The component name of a local schema reference."""

    return ref.rsplit("/", 1)[-1]


def named_type(ref: str, resolve=None) -> IrType:
    """The generated type for a local reference.

    ``resolve`` maps a component name onto the generated type name; the default
    is the plain PascalCase of the component name.
    """

    target = ref_target(ref)
    return named(resolve(target) if resolve is not None else naming.pascal(target))


def map_schema(schema: Schema, where: str, resolve=None) -> IrType:
    """Map a schema node onto a MoonBit type."""

    if schema.ref is not None:
        return named_type(schema.ref, resolve)
    if schema.kind == "array":
        if schema.items is None:
            raise TypeMappingError(f"{where}: array without items")
        return array_of(map_schema(schema.items, f"{where}.items", resolve))
    if schema.kind == "string":
        if schema.enum:
            raise TypeMappingError(
                f"{where}: an inline enum cannot be mapped; it must be a named schema"
            )
        return SCALAR_STRING
    if schema.kind == "integer":
        return SCALAR_INT64 if schema.format == "int64" else SCALAR_INT
    if schema.kind == "number":
        return SCALAR_DOUBLE
    if schema.kind == "boolean":
        return SCALAR_BOOL
    if schema.kind == "any":
        return IR_JSON
    raise TypeMappingError(f"{where}: unsupported schema kind {schema.kind!r}")


def encode_expr(schema_type: IrType, expr: str) -> str:
    """MoonBit expression that encodes ``expr`` of ``schema_type`` as JSON."""

    if schema_type.kind == "scalar" and schema_type.name == "Int64":
        return f"@runtime.int64_to_json({expr})"
    if schema_type.kind == "scalar" and schema_type.name == "Json":
        return expr
    return f"@json.to_json({expr})"


def decode_expr(
    schema_type: IrType,
    expr: str,
    path_expr: str,
) -> str:
    """MoonBit expression that decodes JSON ``expr`` into ``schema_type``."""

    if schema_type.kind == "scalar" and schema_type.name == "Int64":
        return f"@runtime.json_to_int64({expr}, {path_expr})"
    if schema_type.kind == "scalar" and schema_type.name == "Json":
        return expr
    return f"@json.from_json({expr}, path={path_expr})"


def to_string_expr(schema_type: IrType, expr: str) -> str:
    """MoonBit expression rendering a parameter value for the wire."""

    if schema_type.kind == "named":
        return f"{expr}.to_wire()"
    if schema_type.kind == "scalar" and schema_type.name == "Json":
        return f"{expr}.stringify()"
    return f"{expr}.to_string()"
