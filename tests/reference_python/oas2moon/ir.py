"""Client IR.

The IR is the only thing code emission sees. It is transport-aware but
generator-language agnostic: it describes MoonBit types, argument names and
wire behavior, and contains no parser model and no raw JSON.
"""

from __future__ import annotations

import json
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
        if self.presence == "optional_nullable":
            return f"Presence[{rendered}]"
        return f"{rendered}?" if self.optional else rendered

    @property
    def presence(self) -> str:
        """Normalized presence semantics, before a runtime chooses encoding."""

        if self.required and self.nullable:
            return "required_nullable"
        if self.required:
            return "required"
        if self.nullable:
            return "optional_nullable"
        return "optional"


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
    additional_properties: bool = False
    additional_properties_field: str | None = None


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
        if self.presence == "optional_nullable":
            return f"Presence[{rendered}]"
        return f"{rendered}?" if self.optional else rendered

    @property
    def presence(self) -> str:
        if self.required and self.nullable:
            return "required_nullable"
        if self.required:
            return "required"
        if self.nullable:
            return "optional_nullable"
        return "optional"


@dataclass(frozen=True)
class RequestBody:
    """Canonical request body facts; no OpenAPI parser types leak here."""

    type: IrType | None
    required: bool
    media_type: str | None


@dataclass(frozen=True)
class Response:
    """One normalized response status/media/type tuple."""

    status: int
    type: IrType | None
    media_type: str | None


@dataclass(frozen=True)
class AuthScheme:
    name: str
    kind: str
    location: str | None = None
    key_name: str | None = None


@dataclass(frozen=True)
class Server:
    url: str


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
    request_body_info: RequestBody | None = None
    responses_info: tuple[Response, ...] = ()

    @property
    def description(self) -> str:
        return f"`{self.method} {self.path}`"

    @property
    def request_body(self) -> RequestBody | None:
        return self.request_body_info

    @property
    def responses(self) -> tuple[Response, ...]:
        if self.responses_info:
            return self.responses_info
        if self.response is None:
            return (Response(self.success_status, None, None),)
        return (Response(self.success_status, self.response, "application/json"),)


@dataclass(frozen=True)
class ApiIr:
    module_name: str
    title: str
    version: str
    servers: tuple[str, ...]
    models: tuple[ModelIr, ...]
    operations: tuple[OperationIr, ...]
    warnings: tuple[Diagnostic, ...]
    auth_schemes: tuple[AuthScheme, ...] = ()
    server_info: tuple[Server, ...] = ()

    def canonical_dict(self) -> dict:
        """Stable, JSON-compatible debug representation for tests and reports."""

        def typeref(value: IrType | None):
            if value is None:
                return None
            if value.kind == "array":
                return {"kind": "array", "item": typeref(value.item)}
            return {"kind": value.kind, "name": value.name}

        models = []
        for model in self.models:
            if isinstance(model, EnumIr):
                models.append({"kind": "enum", "name": model.name, "members": list(model.members)})
            else:
                models.append({
                    "kind": "struct",
                    "name": model.name,
                    "additional_properties": model.additional_properties,
                    "additional_properties_field": model.additional_properties_field,
                    "fields": [
                        {"name": field.name, "wire_name": field.wire_name,
                         "type": typeref(field.type), "required": field.required,
                         "nullable": field.nullable, "presence": field.presence}
                        for field in model.fields
                    ],
                })
        return {
            "module": self.module_name,
            "title": self.title,
            "version": self.version,
            "servers": [server.url for server in self.server_info] or list(self.servers),
            "auth_schemes": [
                {"name": scheme.name, "kind": scheme.kind,
                 "location": scheme.location, "key_name": scheme.key_name}
                for scheme in self.auth_schemes
            ],
            "models": models,
            "operations": [
                {"operation_id": operation.operation_id, "method": operation.method,
                 "path": operation.path, "fn_name": operation.fn_name,
                 "parameters": [
                     {"name": parameter.name, "wire_name": parameter.wire_name,
                      "location": parameter.location, "type": typeref(parameter.type),
                      "required": parameter.required, "nullable": parameter.nullable,
                      "presence": parameter.presence}
                     for parameter in operation.params
                 ],
                 "request_body": None if operation.request_body is None else {
                     "type": typeref(operation.request_body.type),
                     "required": operation.request_body.required,
                     "media_type": operation.request_body.media_type,
                 },
                 "responses": [
                     {"status": response.status, "type": typeref(response.type),
                      "media_type": response.media_type}
                     for response in operation.responses
                 ],
                 "security": list(operation.security)}
                for operation in self.operations
            ],
        }

    def canonical_json(self) -> str:
        return json.dumps(self.canonical_dict(), ensure_ascii=False, sort_keys=True, separators=(",", ":"))


# Public Phase 1 vocabulary.  The compatibility ``*Ir`` names remain for the
# spike emitter, while the canonical aliases keep downstream code independent
# of the parser/frontend implementation.
TypeRef = IrType
Field = FieldIr
Model = ModelIr
Parameter = ParamIr
Operation = OperationIr
Api = ApiIr
