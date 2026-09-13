"""Support Validation.

Decides, before any code is emitted, whether the normalized document is inside
the spike's supported profile. Everything outside the profile becomes a stable
diagnostic instead of a silent approximation, exactly as the project contract
requires.

Diagnostics are produced in a fixed traversal order (document order, then a
fixed key order per node) so that repeated runs report identical results.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

from .frontend import FrontendModel, Operation, Parameter, Schema

SUPPORTED_HTTP_METHODS = ("GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS")
SUPPORTED_PARAMETER_LOCATIONS = ("path", "query", "header")
SUPPORTED_SCALAR_KINDS = ("string", "integer", "number", "boolean")
REF_PREFIX = "#/components/schemas/"
JSON_MEDIA_TYPE = "application/json"

# OpenAPI defaults per location; only these values (plus the default) are in
# scope. Anything else would change wire behavior.
ALLOWED_SERIALIZATION = {
    "path": ((None, "simple"), (None, False)),
    "query": ((None, "form"), (None, True)),
    "header": ((None, "simple"), (None, False)),
}


@dataclass(frozen=True)
class Diagnostic:
    severity: str
    code: str
    location: str
    message: str

    def render(self) -> str:
        return f"{self.severity}: {self.code}: {self.location}: {self.message}"


@dataclass(frozen=True)
class SupportReport:
    errors: tuple[Diagnostic, ...]
    warnings: tuple[Diagnostic, ...]

    @property
    def ok(self) -> bool:
        return not self.errors


def _error(code: str, location: str, message: str) -> Diagnostic:
    return Diagnostic("error", code, location, message)


def _warning(code: str, location: str, message: str) -> Diagnostic:
    return Diagnostic("warning", code, location, message)


def _is_json_media_type(media_type: str | None) -> bool:
    if media_type is None:
        return False
    return media_type.split(";", 1)[0].strip().lower() == JSON_MEDIA_TYPE


def _check_schema(
    schema: Schema,
    location: str,
    known_schemas: frozenset[str],
    errors: list[Diagnostic],
    warnings: list[Diagnostic],
    top_level: bool = False,
) -> None:
    if schema.ref is not None:
        if not schema.ref.startswith(REF_PREFIX):
            errors.append(
                _error(
                    "unsupported.ref",
                    location,
                    f"only local references into {REF_PREFIX} are supported, got {schema.ref!r}",
                )
            )
            return
        target = schema.ref[len(REF_PREFIX) :]
        if target not in known_schemas:
            errors.append(
                _error(
                    "unsupported.ref",
                    location,
                    f"reference target {schema.ref!r} is not declared in components.schemas",
                )
            )
        return

    kind = schema.kind
    if kind == "object":
        if not schema.properties:
            errors.append(
                _error(
                    "unsupported.schema",
                    location,
                    "object schemas without declared properties (free-form maps) are not supported",
                )
            )
            return
        for name, child in schema.properties:
            if child.kind == "object" and child.ref is None:
                errors.append(
                    _error(
                        "unsupported.inline_object",
                        f"{location}.{name}",
                        "inline object schemas are not supported; declare a named component schema",
                    )
                )
                continue
            if child.nullable and name in schema.required:
                warnings.append(
                    _warning(
                        "nullable.collapsed",
                        f"{location}.{name}",
                        "property is both required and nullable; the generated field is "
                        "optional, so missing and explicit null are indistinguishable",
                    )
                )
            _check_schema(child, f"{location}.{name}", known_schemas, errors, warnings)
        return
    if kind == "array":
        if schema.items is None:
            errors.append(
                _error("unsupported.schema", location, "array schemas must declare items")
            )
            return
        if schema.items.kind == "object" and schema.items.ref is None:
            errors.append(
                _error(
                    "unsupported.inline_object",
                    f"{location}.items",
                    "inline object schemas are not supported; declare a named component schema",
                )
            )
            return
        if (
            schema.items.ref is None
            and schema.items.kind == "integer"
            and schema.items.format == "int64"
        ):
            errors.append(
                _error(
                    "unsupported.schema",
                    f"{location}.items",
                    "arrays of int64 are not supported: the MoonBit Int64 JSON codec uses "
                    "a string representation, which would not match integer wire values",
                )
            )
            return
        _check_schema(schema.items, f"{location}.items", known_schemas, errors, warnings)
        return
    if kind in SUPPORTED_SCALAR_KINDS:
        if kind == "string" and schema.format in ("binary", "byte"):
            errors.append(
                _error(
                    "unsupported.schema",
                    location,
                    f"string format {schema.format!r} is not supported; encoding it as "
                    "String would not match the wire representation",
                )
            )
            return
        if schema.enum:
            if kind != "string":
                errors.append(
                    _error(
                        "unsupported.enum_kind",
                        location,
                        f"only string enums are supported, got {kind}",
                    )
                )
                return
            for member in schema.enum:
                if not isinstance(member, str):
                    errors.append(
                        _error(
                            "unsupported.enum_value",
                            location,
                            f"enum members must be strings, got {member!r}",
                        )
                    )
                    return
            if not top_level:
                errors.append(
                    _error(
                        "unsupported.inline_enum",
                        location,
                        "inline enums are not supported; declare the enum as a named "
                        "component schema and reference it with $ref",
                    )
                )
                return
        return
    if kind == "any":
        return
    errors.append(
        _error("unsupported.schema", location, f"unsupported schema kind {kind!r}")
    )


def _check_parameter(
    parameter: Parameter,
    location: str,
    known_schemas: frozenset[str],
    errors: list[Diagnostic],
    warnings: list[Diagnostic],
) -> None:
    if parameter.ref is not None:
        errors.append(
            _error(
                "unsupported.parameter_ref",
                location,
                "referenced parameters are not supported yet; inline the parameter",
            )
        )
        return
    if parameter.location not in SUPPORTED_PARAMETER_LOCATIONS:
        errors.append(
            _error(
                "unsupported.parameter_location",
                location,
                f"parameter location {parameter.location!r} is not supported",
            )
        )
        return
    allowed_style, allowed_explode = ALLOWED_SERIALIZATION[parameter.location]
    if parameter.style not in allowed_style:
        errors.append(
            _error(
                "unsupported.parameter_style",
                location,
                f"style {parameter.style!r} is not supported for {parameter.location} "
                f"parameters (allowed: simple form defaults)",
            )
        )
    if parameter.explode not in allowed_explode:
        errors.append(
            _error(
                "unsupported.parameter_style",
                location,
                f"explode={parameter.explode!r} is not supported for {parameter.location} parameters",
            )
        )
    if parameter.location == "path" and not parameter.required:
        errors.append(
            _error(
                "unsupported.parameter",
                location,
                "path parameters must be declared required",
            )
        )
    if parameter.schema.kind == "array" or (
        parameter.schema.kind == "object" and parameter.schema.ref is None
    ):
        errors.append(
            _error(
                "unsupported.parameter_schema",
                location,
                "only scalar parameters are supported in the spike",
            )
        )
        return
    _check_schema(
        parameter.schema, f"{location}.schema", known_schemas, errors, warnings
    )
    if parameter.schema.nullable:
        warnings.append(
            _warning(
                "nullable.collapsed",
                location,
                "a nullable parameter is represented as an optional argument; "
                "missing and explicit null are indistinguishable",
            )
        )


def _check_operation(
    model: FrontendModel,
    operation: Operation,
    schemes: dict[str, str],
    known_schemas: frozenset[str],
    errors: list[Diagnostic],
    warnings: list[Diagnostic],
) -> None:
    location = f"#.operations.{operation.operation_id}"
    if not operation.operation_id:
        errors.append(_error("unsupported.operation", location, "operationId is required"))
    if operation.method not in SUPPORTED_HTTP_METHODS:
        errors.append(
            _error(
                "unsupported.method",
                location,
                f"HTTP method {operation.method!r} is not supported",
            )
        )
    for index, parameter in enumerate(operation.parameters):
        _check_parameter(
            parameter,
            f"{location}.parameters[{index}]",
            known_schemas,
            errors,
            warnings,
        )

    declared_path_parameters = {
        parameter.name for parameter in operation.parameters if parameter.location == "path"
    }
    for name in re.findall(r"\{([^{}]*)\}", operation.path):
        if name not in declared_path_parameters:
            errors.append(
                _error(
                    "unsupported.path_parameter",
                    location,
                    f"path template parameter {name!r} is not declared as a path parameter",
                )
            )

    body = operation.request_body
    if body is not None:
        if not body.required:
            errors.append(
                _error(
                    "unsupported.optional_request_body",
                    f"{location}.requestBody",
                    "optional request bodies are not supported in the spike",
                )
            )
        if not _is_json_media_type(body.media_type):
            errors.append(
                _error(
                    "unsupported.media_type",
                    f"{location}.requestBody",
                    f"request body media type {body.media_type!r} is not supported; "
                    f"only {JSON_MEDIA_TYPE} is",
                )
            )
        elif body.schema is None:
            errors.append(
                _error(
                    "unsupported.request_body",
                    f"{location}.requestBody",
                    "a JSON request body must declare a schema",
                )
            )
        else:
            _check_schema(
                body.schema,
                f"{location}.requestBody.schema",
                known_schemas,
                errors,
                warnings,
            )

    success = [
        response
        for response in operation.responses
        if response.status.isdigit() and 200 <= int(response.status) < 300
    ]
    if len(success) != 1:
        errors.append(
            _error(
                "unsupported.response_set",
                location,
                f"exactly one 2xx response is supported in the spike, found {len(success)}",
            )
        )
    for index, response in enumerate(operation.responses):
        response_location = f"{location}.responses[{index}]"
        if not response.status.isdigit():
            errors.append(
                _error(
                    "unsupported.response",
                    response_location,
                    f"response key {response.status!r} is not supported (default/range keys)",
                )
            )
            continue
        status = int(response.status)
        if not 200 <= status < 300:
            warnings.append(
                _warning(
                    "response.non_success",
                    response_location,
                    f"non-2xx response {status} is not decoded; it surfaces as SdkError::HttpStatus",
                )
            )
            continue
        if response.schema is None:
            if status not in (204, 205):
                warnings.append(
                    _warning(
                        "response.bodyless",
                        response_location,
                        f"status {status} declares no schema; the operation returns Unit",
                    )
                )
            continue
        if not _is_json_media_type(response.media_type):
            errors.append(
                _error(
                    "unsupported.media_type",
                    response_location,
                    f"response media type {response.media_type!r} is not supported; "
                    f"only {JSON_MEDIA_TYPE} is",
                )
            )
            continue
        _check_schema(
            response.schema,
            f"{response_location}.schema",
            known_schemas,
            errors,
            warnings,
        )

    if len(operation.security) > 1:
        errors.append(
            _error(
                "unsupported.security_alternatives",
                location,
                "security alternatives (OR-composed requirements) are not supported",
            )
        )
    for alternative in operation.security:
        for name in alternative:
            if name not in schemes:
                errors.append(
                    _error(
                        "unsupported.security_scheme",
                        location,
                        f"security scheme {name!r} is not declared in components.securitySchemes",
                    )
                )


def validate(model: FrontendModel) -> SupportReport:
    """Validate a Frontend Model against the spike's supported profile."""

    errors: list[Diagnostic] = []
    warnings: list[Diagnostic] = []

    version = model.version
    if len(version) < 2 or version[:2] != (3, 0):
        errors.append(
            _error(
                "unsupported.version",
                "#.openapi",
                f"OpenAPI {model.openapi!r} is not supported; this project targets 3.0.x",
            )
        )

    for finding in model.issues:
        errors.append(
            _error(
                "unsupported.keyword",
                finding.pointer,
                f"keyword {finding.keyword!r} is not supported and must not be dropped silently",
            )
        )
    for finding in model.ignored:
        warnings.append(
            _warning(
                "ignored.keyword",
                finding.pointer,
                f"keyword {finding.keyword!r} is recorded but not modeled; "
                "it does not change wire encoding",
            )
        )

    known_schemas = frozenset(name for name, _schema in model.schemas)

    # Only the credential kinds the runtime template can actually apply are
    # accepted; everything else is a deterministic diagnostic.
    schemes: dict[str, str] = {}
    for scheme in model.security_schemes:
        if scheme.type == "http" and scheme.scheme == "bearer":
            schemes[scheme.name] = "bearer"
        elif scheme.type == "apiKey" and scheme.location == "header":
            errors.append(
                _error(
                    "unsupported.security_scheme",
                    f"#.securitySchemes.{scheme.name}",
                    "apiKey header credentials are not implemented in the spike runtime",
                )
            )
        elif scheme.type == "apiKey":
            errors.append(
                _error(
                    "unsupported.security_scheme",
                    f"#.securitySchemes.{scheme.name}",
                    "only apiKey in a header is representable, and it is not implemented in the spike",
                )
            )
        else:
            errors.append(
                _error(
                    "unsupported.security_scheme",
                    f"#.securitySchemes.{scheme.name}",
                    f"security scheme type {scheme.type!r} is not supported",
                )
            )

    for name, schema in model.schemas:
        location = f"#.schemas.{name}"
        if schema.ref is None and schema.kind not in ("object", "string"):
            errors.append(
                _error(
                    "unsupported.named_schema",
                    location,
                    f"named component schemas must be objects or string enums in the "
                    f"spike, got {schema.kind!r}; inline the schema at its use sites",
                )
            )
            continue
        if schema.ref is None and schema.kind == "string" and not schema.enum:
            errors.append(
                _error(
                    "unsupported.named_schema",
                    location,
                    "a named string component schema must declare enum values; plain "
                    "scalar aliases are not supported in the spike",
                )
            )
            continue
        _check_schema(
            schema, location, known_schemas, errors, warnings, top_level=True
        )

    for operation in model.operations:
        _check_operation(model, operation, schemes, known_schemas, errors, warnings)

    return SupportReport(errors=tuple(errors), warnings=tuple(warnings))
