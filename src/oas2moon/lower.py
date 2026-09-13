"""Lowering: Frontend Model -> Client IR.

This is the only stage that knows about both halves of the pipeline. It resolves
local references against the component registry, assigns MoonBit identifiers,
and produces an IR that code emission can render without looking back at the
schema model.
"""

from __future__ import annotations

import re

from . import naming, typemap
from .frontend import FrontendModel, Operation, Schema
from .ir import (
    ApiIr,
    AuthScheme,
    EnumIr,
    FieldIr,
    ModelIr,
    OperationIr,
    ParamIr,
    PathPartIr,
    RequestBody,
    Response,
    Server,
    StructIr,
)
from .support import SupportReport

_PATH_PARAMETER = re.compile(r"\{([^{}]*)\}")


def path_parts(path: str) -> tuple[PathPartIr, ...]:
    """Split an operation path into literal and parameter parts."""

    parts: list[PathPartIr] = []
    position = 0
    for match in _PATH_PARAMETER.finditer(path):
        if match.start() > position:
            parts.append(PathPartIr(literal=path[position : match.start()]))
        parts.append(PathPartIr(parameter=match.group(1)))
        position = match.end()
    if position < len(path):
        parts.append(PathPartIr(literal=path[position:]))
    if not parts:
        parts.append(PathPartIr(literal=path))
    return tuple(parts)


def _enum_model(name: str, schema: Schema) -> EnumIr:
    taken: set[str] = set()
    members: list[tuple[str, str]] = []
    for wire in schema.enum:
        members.append((naming.unique(naming.pascal(str(wire)), taken), str(wire)))
    return EnumIr(
        name=name,
        description=f"Wire values accepted by `{name}`.",
        members=tuple(members),
    )


def _struct_model(name: str, schema: Schema, resolve) -> StructIr:
    taken: set[str] = set()
    declared: list[FieldIr] = []
    required = set(schema.required)
    for property_name, property_schema in schema.properties:
        declared.append(
            FieldIr(
                name=naming.unique(naming.snake(property_name), taken),
                wire_name=property_name,
                type=typemap.map_schema(
                    property_schema,
                    f"#.schemas.{name}.{property_name}",
                    resolve,
                ),
                required=property_name in required,
                nullable=property_schema.nullable,
            )
        )
    # MoonBit requires optional arguments to follow required ones and the
    # generated constructor mirrors the field order, so required properties are
    # grouped first while each group keeps its document order.
    fields = [field for field in declared if not field.optional]
    fields += [field for field in declared if field.optional]
    return StructIr(
        name=name,
        description=f"Generated model for `{name}`.",
        fields=tuple(fields),
    )


def _credential_labels(model: FrontendModel) -> dict[str, str]:
    labels: dict[str, str] = {}
    for scheme in model.security_schemes:
        if scheme.type == "http" and scheme.scheme == "bearer":
            labels[scheme.name] = "bearer"
    return labels


def _operation(
    operation: Operation,
    resolve,
    labels: dict[str, str],
    taken_functions: set[str],
) -> OperationIr:
    location = f"#.operations.{operation.operation_id}"
    fn_name = naming.unique(naming.snake(operation.operation_id), taken_functions)

    taken_arguments: set[str] = {"self", "client"}
    resolved: list[tuple[ParamIr, str]] = []
    for index, parameter in enumerate(operation.parameters):
        resolved.append(
            (
                ParamIr(
                    name=naming.unique(naming.snake(parameter.name), taken_arguments),
                    wire_name=parameter.name,
                    location=parameter.location,
                    type=typemap.map_schema(
                        parameter.schema,
                        f"{location}.parameters[{index}].schema",
                        resolve,
                    ),
                    required=parameter.required,
                    nullable=parameter.schema.nullable,
                ),
                parameter.name,
            )
        )

    # MoonBit requires optional arguments to follow required ones, so required
    # parameters keep their document order and optional ones are appended.
    ordered = [entry for entry, _ in resolved if not entry.optional]
    ordered += [entry for entry, _ in resolved if entry.optional]

    body_type = None
    body_name = None
    if operation.request_body is not None and operation.request_body.schema is not None:
        body_type = typemap.map_schema(
            operation.request_body.schema,
            f"{location}.requestBody.schema",
            resolve,
        )
        base = naming.snake(body_type.name) if body_type.kind == "named" else "body"
        body_name = naming.unique(base, taken_arguments)

    wire_to_argument = {wire: entry.name for entry, wire in resolved}
    parts = tuple(
        PathPartIr(parameter=wire_to_argument[part.parameter])
        if part.parameter is not None
        else part
        for part in path_parts(operation.path)
    )

    success = [
        response
        for response in operation.responses
        if response.status.isdigit() and 200 <= int(response.status) < 300
    ]
    response_type = None
    if success and success[0].schema is not None:
        response_type = typemap.map_schema(
            success[0].schema,
            f"{location}.responses.{success[0].status}.schema",
            resolve,
        )

    security: list[str] = []
    for alternative in operation.security:
        for scheme_name in alternative:
            label = labels.get(scheme_name, scheme_name)
            if label not in security:
                security.append(label)

    return OperationIr(
        operation_id=operation.operation_id,
        fn_name=fn_name,
        method=operation.method,
        path=operation.path,
        path_parts=parts,
        params=tuple(ordered),
        body=body_type,
        body_name=body_name,
        success_status=int(success[0].status) if success else 200,
        response=response_type,
        security=tuple(security),
        request_body_info=(
            None
            if operation.request_body is None
            else RequestBody(
                body_type,
                operation.request_body.required,
                operation.request_body.media_type,
            )
        ),
        responses_info=tuple(
            Response(
                int(response.status),
                None
                if response.schema is None
                else typemap.map_schema(
                    response.schema,
                    f"{location}.responses.{response.status}.schema",
                    resolve,
                ),
                response.media_type,
            )
            for response in operation.responses
            if response.status.isdigit()
        ),
    )


def lower(model: FrontendModel, module_name: str, report: SupportReport) -> ApiIr:
    """Build the Client IR from a validated Frontend Model."""

    taken_type_names: set[str] = set()
    type_names: dict[str, str] = {}
    for component_name, _schema in model.schemas:
        type_names[component_name] = naming.unique(
            naming.pascal(component_name), taken_type_names
        )

    def resolve(component_name: str) -> str:
        return type_names.get(component_name, naming.pascal(component_name))

    enums: list[ModelIr] = []
    structs: list[ModelIr] = []
    for component_name, schema in sorted(model.schemas, key=lambda item: type_names[item[0]]):
        name = type_names[component_name]
        if schema.ref is None and schema.kind == "string" and schema.enum:
            enums.append(_enum_model(name, schema))
        else:
            structs.append(_struct_model(name, schema, resolve))

    taken_functions: set[str] = set()
    labels = _credential_labels(model)
    operations = tuple(
        _operation(operation, resolve, labels, taken_functions)
        for operation in sorted(model.operations, key=lambda item: (item.path, item.method, item.operation_id))
    )

    auth_schemes = tuple(
        AuthScheme(
            name=scheme.name,
            kind=labels.get(scheme.name, scheme.type),
            location=scheme.location,
            key_name=scheme.key_name,
        )
        for scheme in sorted(model.security_schemes, key=lambda item: item.name)
    )

    return ApiIr(
        module_name=module_name,
        title=model.title,
        version=model.openapi,
        servers=model.servers,
        models=tuple(enums + structs),
        operations=operations,
        warnings=report.warnings,
        auth_schemes=auth_schemes,
        server_info=tuple(Server(url) for url in sorted(model.servers)),
    )
