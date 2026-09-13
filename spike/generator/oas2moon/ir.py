"""Client IR.

The IR is the only thing code emission sees. It is transport-aware but
generator-language agnostic: it describes MoonBit types, argument names and
wire behavior, and contains no parser model and no raw JSON.
"""

from __future__ import annotations

from dataclasses import dataclass

from .support import Diagnostic


@dataclass(frozen=True)
class IrType:
    """A rendered MoonBit type.

    ``kind`` is one of ``scalar`` (builtin, ``name`` is the type), ``named``
    (a generated model or enum, ``name`` is the type) or ``array`` (``item``).
    """

    kind: str
    name: str | None = None
    item: "IrType | None" = None

    def render(self) -> str:
        if self.kind == "array":
            assert self.item is not None
            return f"Array[{self.item.render()}]"
        assert self.name is not None
        return self.name


SCALAR_STRING = IrType("scalar", "String")
SCALAR_BOOL = IrType("scalar", "Bool")
SCALAR_INT = IrType("scalar", "Int")
SCALAR_INT64 = IrType("scalar", "Int64")
SCALAR_DOUBLE = IrType("scalar", "Double")
IR_JSON = IrType("scalar", "Json")


def named(name: str) -> IrType:
    return IrType("named", name)


def array_of(item: IrType) -> IrType:
    return IrType("array", item=item)


@dataclass(frozen=True)
class FieldIr:
    name: str
    wire_name: str
    type: IrType
    required: bool
    nullable: bool

    @property
    def optional(self) -> bool:
        return not self.required or self.nullable

    @property
    def moon_type(self) -> str:
        rendered = self.type.render()
        return f"{rendered}?" if self.optional else rendered


@dataclass(frozen=True)
class EnumIr:
    name: str
    description: str
    members: tuple[tuple[str, str], ...]


@dataclass(frozen=True)
class StructIr:
    name: str
    description: str
    fields: tuple[FieldIr, ...]


ModelIr = EnumIr | StructIr


@dataclass(frozen=True)
class ParamIr:
    name: str
    wire_name: str
    location: str
    type: IrType
    required: bool
    nullable: bool

    @property
    def optional(self) -> bool:
        return not self.required or self.nullable

    @property
    def moon_type(self) -> str:
        rendered = self.type.render()
        return f"{rendered}?" if self.optional else rendered


@dataclass(frozen=True)
class PathPartIr:
    """One literal or parameter segment of an operation path."""

    literal: str | None = None
    parameter: str | None = None


@dataclass(frozen=True)
class OperationIr:
    operation_id: str
    fn_name: str
    method: str
    path: str
    path_parts: tuple[PathPartIr, ...]
    params: tuple[ParamIr, ...]
    body: IrType | None
    body_name: str | None
    success_status: int
    response: IrType | None
    security: tuple[str, ...]

    @property
    def description(self) -> str:
        return f"`{self.method} {self.path}`"


@dataclass(frozen=True)
class ApiIr:
    module_name: str
    title: str
    version: str
    servers: tuple[str, ...]
    models: tuple[ModelIr, ...]
    operations: tuple[OperationIr, ...]
    warnings: tuple[Diagnostic, ...]
