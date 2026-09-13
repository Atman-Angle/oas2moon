"""Frontend Model: the contract between the frontend adapter and codegen.

The model is produced by ``spike/frontend``. Every value here is already
normalized: ``$ref`` targets are recorded as-is, document order is preserved,
and nothing in this module knows how OpenAPI text is parsed.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence


class FrontendModelError(ValueError):
    """The normalized document does not have the shape the generator expects."""


def _as_object(value: Any, where: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise FrontendModelError(f"{where}: expected an object, got {type(value).__name__}")
    return value


def _as_array(value: Any, where: str) -> list[Any]:
    if not isinstance(value, list):
        raise FrontendModelError(f"{where}: expected an array, got {type(value).__name__}")
    return value


def _as_string(value: Any, where: str) -> str:
    if not isinstance(value, str):
        raise FrontendModelError(f"{where}: expected a string, got {type(value).__name__}")
    return value


def _as_optional_string(value: Any, where: str) -> str | None:
    if value is None:
        return None
    return _as_string(value, where)


def _as_bool(value: Any, where: str) -> bool:
    if not isinstance(value, bool):
        raise FrontendModelError(f"{where}: expected a boolean, got {type(value).__name__}")
    return value


def _as_optional_bool(value: Any, where: str) -> bool | None:
    if value is None:
        return None
    return _as_bool(value, where)


@dataclass(frozen=True)
class Schema:
    """One normalized schema node."""

    kind: str
    ref: str | None
    format: str | None
    nullable: bool
    required: tuple[str, ...]
    properties: tuple[tuple[str, "Schema"], ...]
    items: "Schema | None"
    enum: tuple[Any, ...]
    additional_properties: bool

    @staticmethod
    def from_json(value: Any, where: str) -> "Schema":
        node = _as_object(value, where)
        items = node.get("items")
        return Schema(
            kind=_as_string(node.get("kind"), f"{where}.kind"),
            ref=_as_optional_string(node.get("ref"), f"{where}.ref"),
            format=_as_optional_string(node.get("format"), f"{where}.format"),
            nullable=_as_bool(node.get("nullable"), f"{where}.nullable"),
            required=tuple(
                _as_string(entry, f"{where}.required[]")
                for entry in _as_array(node.get("required"), f"{where}.required")
            ),
            properties=tuple(
                (name, Schema.from_json(child, f"{where}.properties.{name}"))
                for name, child in _as_object(
                    node.get("properties"), f"{where}.properties"
                ).items()
            ),
            items=None
            if items is None
            else Schema.from_json(items, f"{where}.items"),
            enum=tuple(_as_array(node.get("enum"), f"{where}.enum")),
            additional_properties=_as_bool(
                node.get("additionalProperties"), f"{where}.additionalProperties"
            ),
        )


@dataclass(frozen=True)
class Parameter:
    name: str
    location: str
    required: bool
    schema: Schema
    ref: str | None
    style: str | None
    explode: bool | None

    @staticmethod
    def from_json(value: Any, where: str) -> "Parameter":
        node = _as_object(value, where)
        return Parameter(
            name=_as_string(node.get("name"), f"{where}.name"),
            location=_as_string(node.get("in"), f"{where}.in"),
            required=_as_bool(node.get("required"), f"{where}.required"),
            schema=Schema.from_json(node.get("schema"), f"{where}.schema"),
            ref=_as_optional_string(node.get("ref"), f"{where}.ref"),
            style=_as_optional_string(node.get("style"), f"{where}.style"),
            explode=_as_optional_bool(node.get("explode"), f"{where}.explode"),
        )


@dataclass(frozen=True)
class RequestBody:
    required: bool
    media_type: str | None
    schema: Schema | None

    @staticmethod
    def from_json(value: Any, where: str) -> "RequestBody | None":
        if value is None:
            return None
        node = _as_object(value, where)
        schema = node.get("schema")
        return RequestBody(
            required=_as_bool(node.get("required"), f"{where}.required"),
            media_type=_as_optional_string(node.get("media_type"), f"{where}.media_type"),
            schema=None if schema is None else Schema.from_json(schema, f"{where}.schema"),
        )


@dataclass(frozen=True)
class Response:
    status: str
    description: str
    media_type: str | None
    schema: Schema | None

    @staticmethod
    def from_json(value: Any, where: str) -> "Response":
        node = _as_object(value, where)
        schema = node.get("schema")
        return Response(
            status=_as_string(node.get("status"), f"{where}.status"),
            description=_as_string(node.get("description"), f"{where}.description"),
            media_type=_as_optional_string(node.get("media_type"), f"{where}.media_type"),
            schema=None if schema is None else Schema.from_json(schema, f"{where}.schema"),
        )


@dataclass(frozen=True)
class Operation:
    operation_id: str
    method: str
    path: str
    security: tuple[tuple[str, ...], ...]
    parameters: tuple[Parameter, ...]
    request_body: RequestBody | None
    responses: tuple[Response, ...]

    @staticmethod
    def from_json(value: Any, where: str) -> "Operation":
        node = _as_object(value, where)
        return Operation(
            operation_id=_as_string(node.get("operationId"), f"{where}.operationId"),
            method=_as_string(node.get("method"), f"{where}.method"),
            path=_as_string(node.get("path"), f"{where}.path"),
            security=tuple(
                tuple(
                    _as_string(name, f"{where}.security[{i}][]")
                    for name in _as_array(alternative, f"{where}.security[{i}]")
                )
                for i, alternative in enumerate(
                    _as_array(node.get("security"), f"{where}.security")
                )
            ),
            parameters=tuple(
                Parameter.from_json(entry, f"{where}.parameters[{i}]")
                for i, entry in enumerate(
                    _as_array(node.get("parameters"), f"{where}.parameters")
                )
            ),
            request_body=RequestBody.from_json(
                node.get("requestBody"), f"{where}.requestBody"
            ),
            responses=tuple(
                Response.from_json(entry, f"{where}.responses[{i}]")
                for i, entry in enumerate(
                    _as_array(node.get("responses"), f"{where}.responses")
                )
            ),
        )


@dataclass(frozen=True)
class SecurityScheme:
    name: str
    type: str
    scheme: str | None
    location: str | None
    key_name: str | None

    @staticmethod
    def from_json(name: str, value: Any, where: str) -> "SecurityScheme":
        node = _as_object(value, where)
        return SecurityScheme(
            name=name,
            type=_as_string(node.get("type"), f"{where}.type"),
            scheme=_as_optional_string(node.get("scheme"), f"{where}.scheme"),
            location=_as_optional_string(node.get("in"), f"{where}.in"),
            key_name=_as_optional_string(node.get("name"), f"{where}.name"),
        )


@dataclass(frozen=True)
class Finding:
    """One raw-document keyword occurrence recorded by the frontend scan."""

    pointer: str
    keyword: str
    value: Any

    @staticmethod
    def from_json(value: Any, where: str) -> "Finding":
        node = _as_object(value, where)
        return Finding(
            pointer=_as_string(node.get("pointer"), f"{where}.pointer"),
            keyword=_as_string(node.get("keyword"), f"{where}.keyword"),
            value=node.get("value"),
        )


@dataclass(frozen=True)
class FrontendModel:
    openapi: str
    title: str
    servers: tuple[str, ...]
    security_schemes: tuple[SecurityScheme, ...]
    security: tuple[tuple[str, ...], ...]
    operations: tuple[Operation, ...]
    schemas: tuple[tuple[str, Schema], ...]
    issues: tuple[Finding, ...]
    ignored: tuple[Finding, ...]

    @property
    def version(self) -> tuple[int, ...]:
        head = self.openapi.split("-", 1)[0]
        parts: list[int] = []
        for chunk in head.split("."):
            if not chunk.isdigit():
                break
            parts.append(int(chunk))
        return tuple(parts)


def parse(document: Any) -> FrontendModel:
    """Build a :class:`FrontendModel` from a parsed normalized document."""

    root = _as_object(document, "#")
    schemas = _as_object(root.get("schemas"), "#.schemas")
    schemes = _as_object(root.get("securitySchemes"), "#.securitySchemes")
    return FrontendModel(
        openapi=_as_string(root.get("openapi"), "#.openapi"),
        title=_as_string(root.get("title"), "#.title"),
        servers=tuple(
            _as_string(entry, "#.servers[]")
            for entry in _as_array(root.get("servers"), "#.servers")
        ),
        security_schemes=tuple(
            SecurityScheme.from_json(name, value, f"#.securitySchemes.{name}")
            for name, value in schemes.items()
        ),
        security=tuple(
            tuple(
                _as_string(name, f"#.security[{i}][]")
                for name in _as_array(alternative, f"#.security[{i}]")
            )
            for i, alternative in enumerate(
                _as_array(root.get("security", []), "#.security")
            )
        ),
        operations=tuple(
            Operation.from_json(entry, f"#.operations[{i}]")
            for i, entry in enumerate(
                _as_array(root.get("operations"), "#.operations")
            )
        ),
        schemas=tuple(
            (name, Schema.from_json(value, f"#.schemas.{name}"))
            for name, value in schemas.items()
        ),
        issues=tuple(
            Finding.from_json(entry, f"#.issues[{i}]")
            for i, entry in enumerate(_as_array(root.get("issues"), "#.issues"))
        ),
        ignored=tuple(
            Finding.from_json(entry, f"#.ignored[{i}]")
            for i, entry in enumerate(
                _as_array(root.get("ignored", []), "#.ignored")
            )
        ),
    )


def load(path: str | Path) -> FrontendModel:
    """Read and parse a normalized Frontend Model document."""

    text = Path(path).read_text(encoding="utf-8")
    return parse(json.loads(text))
