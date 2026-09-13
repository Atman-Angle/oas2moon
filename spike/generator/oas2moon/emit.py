"""Code emission.

The emitter renders the Client IR into MoonBit sources. It performs no naming
decisions and consults no schema model: everything it needs is already decided
in the IR. Output is a mapping of module-relative POSIX paths to file text, with
LF line endings and no timestamps, so two runs over one input are byte-identical.
"""

from __future__ import annotations

from pathlib import Path

from . import formatter
from .ir import ApiIr, EnumIr, IrType, ModelIr, OperationIr, StructIr
from .typemap import decode_expr, encode_expr, to_string_expr

# The async runtime the generated transport is written against.
ASYNC_VERSION = "0.20.2"
JSON_PACKAGE = "moonbitlang/core/json"
TEMPLATE_ROOT = Path(__file__).resolve().parent.parent / "templates" / "runtime"


def moon_string(text: str) -> str:
    """A MoonBit string literal for arbitrary text."""

    out = ['"']
    for character in text:
        if character == '"':
            out.append('\\"')
        elif character == "\\":
            out.append("\\\\")
        elif character == "\n":
            out.append("\\n")
        elif character == "\r":
            out.append("\\r")
        elif character == "\t":
            out.append("\\t")
        elif ord(character) < 0x20:
            out.append("\\u{%x}" % ord(character))
        else:
            out.append(character)
    out.append('"')
    return "".join(out)


def _enum_source(model: EnumIr) -> str:
    name = model.name
    constants = "\n".join(f"  {constructor}" for constructor, _wire in model.members)
    encode_arms = "\n".join(
        f"    {constructor} => {moon_string(wire)}" for constructor, wire in model.members
    )
    decode_arms = "\n".join(
        f"    {moon_string(wire)} => {constructor}" for constructor, wire in model.members
    )
    return f"""///|
/// {model.description}
pub(all) enum {name} {{
{constants}
}} derive(Eq, Debug)

///|
/// The JSON wire value of this enum member.
pub fn {name}::to_wire(self : {name}) -> String {{
  match self {{
{encode_arms}
  }}
}}

///|
pub impl ToJson for {name} with fn to_json(self : {name}) -> Json {{
  Json::string(self.to_wire())
}}

///|
pub impl FromJson for {name} with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> {name} raise @json.JsonDecodeError {{
  let text : String = @json.from_json(json) catch {{
    _ =>
      raise @json.JsonDecodeError(
        (path, {moon_string(f"expected a string for enum {name}")}),
      )
  }}
  match text {{
{decode_arms}
    _ =>
      raise @json.JsonDecodeError(
        (path, {moon_string(f"unknown wire value for enum {name}")}),
      )
  }}
}}
"""


def _encode_line(field) -> list[str]:
    key = moon_string(field.wire_name)
    attribute = f"self.{field.name}"
    if field.optional:
        return [
            f"  match self.{field.name} {{",
            f"    Some(value) => fields[{key}] = {encode_expr(field.type, 'value')}",
            "    None => ()",
            "  }",
        ]
    return [f"  fields[{key}] = {encode_expr(field.type, attribute)}"]


def _decode_lines(field) -> list[str]:
    key = moon_string(field.wire_name)
    access = f"path.add_key({key})"
    if field.optional:
        return [
            f"  let {field.name} : {field.moon_type} = match fields.get({key}) {{",
            "    Some(Null) => None",
            f"    Some(value) => Some({decode_expr(field.type, 'value', access)})",
            "    None => None",
            "  }",
        ]
    message_null = moon_string(f'required property "{field.wire_name}" is null')
    message_missing = moon_string(f'missing required property "{field.wire_name}"')
    return [
        f"  let {field.name} : {field.moon_type} = match fields.get({key}) {{",
        "    Some(Null) =>",
        "      raise @json.JsonDecodeError(",
        f"        ({access}, {message_null}),",
        "      )",
        f"    Some(value) => {decode_expr(field.type, 'value', access)}",
        "    None =>",
        "      raise @json.JsonDecodeError(",
        f"        ({access}, {message_missing}),",
        "      )",
        "  }",
    ]


def _struct_source(model: StructIr) -> str:
    name = model.name
    declarations = "\n".join(
        f"  {field.name} : {field.moon_type}" for field in model.fields
    )
    arguments = "\n".join(
        f"  {field.name}? : {field.type.render()},"
        if field.optional
        else f"  {field.name} : {field.type.render()},"
        for field in model.fields
    )
    construction = ", ".join(field.name for field in model.fields)
    encode_body = "\n".join(
        line for field in model.fields for line in _encode_line(field)
    )
    decode_body = "\n".join(
        line for field in model.fields for line in _decode_lines(field)
    )
    return f"""///|
/// {model.description}
pub(all) struct {name} {{
{declarations}
}} derive(Eq, Debug)

///|
/// Build a `{name}`. Optional arguments are omitted from the request body when
/// left as `None`.
pub fn {name}::new(
{arguments}
) -> {name} {{
  {{ {construction} }}
}}

///|
/// Optional properties are omitted from the encoded object when absent, so an
/// omitted request field is not sent as an explicit `null`.
pub impl ToJson for {name} with fn to_json(self : {name}) -> Json {{
  let fields : Map[String, Json] = Map([])
{encode_body}
  Json::object(fields)
}}

///|
/// Hand-written decoder. `derive(FromJson)` cannot be used here because it
/// rejects an explicit JSON `null` instead of mapping it onto `T?`.
pub impl FromJson for {name} with fn from_json(json : Json, path : @json.JsonPath) -> {name} raise @json.JsonDecodeError {{
  let fields : Map[String, Json] = match json {{
    Object(fields) => fields
    _ =>
      raise @json.JsonDecodeError(
        (path, {moon_string(f"expected a JSON object for {name}")}),
      )
  }}
{decode_body}
  {{ {construction} }}
}}
"""


def models_source(api: ApiIr) -> str:
    """The `sdk/models.mbt` file."""

    header = f"""///|
/// Generated models for the `{api.title}` API (OpenAPI {api.version}).
///
/// This file is produced by the oas2moon generator. Do not edit by hand.
"""
    blocks = [
        _enum_source(model) if isinstance(model, EnumIr) else _struct_source(model)
        for model in api.models
    ]
    return header + "\n" + "\n".join(blocks)


def _sample_value(
    ir_type: IrType,
    models: dict[str, ModelIr],
    depth: int = 0,
) -> str | None:
    """A MoonBit expression holding any value of ``ir_type``.

    Used only by the generated model tests. ``None`` means the generator has no
    sample for the type, and the test that needed it is skipped rather than
    emitted half-finished.
    """

    if depth > 3:
        return None
    if ir_type.kind == "array":
        assert ir_type.item is not None
        item = _sample_value(ir_type.item, models, depth + 1)
        return None if item is None else f"[{item}]"
    if ir_type.kind == "named":
        model = models.get(ir_type.name or "")
        if model is None:
            return None
        if isinstance(model, EnumIr):
            return model.members[0][0] if model.members else None
        required = [field for field in model.fields if field.required]
        values = [_sample_value(field.type, models, depth + 1) for field in required]
        if any(value is None for value in values):
            return None
        return f"{model.name}::new({', '.join(values)})"
    return {
        "String": '"sample"',
        "Bool": "true",
        "Int": "1",
        "Int64": "1L",
        "Double": "1.5",
        "Json": "Json::null()",
    }.get(ir_type.name or "")


def _enum_tests(model: EnumIr) -> str:
    wires = "\n".join(
        f"  assert_eq({constructor}.to_wire(), {moon_string(wire)})"
        for constructor, wire in model.members
    )
    decodes = "\n".join(
        f"  assert_eq(decode({moon_string(wire)}), {constructor})"
        for constructor, wire in model.members
    )
    return f"""///|
/// The enum keeps its wire spelling, and decoding accepts every member.
test "{model.name} wire values" {{
{wires}
}}

///|
test "{model.name} decodes wire values" {{
  let decode = fn(text : String) -> {model.name} raise @json.JsonDecodeError {{
    @json.from_json(Json::string(text))
  }}
{decodes}
}}
"""


def _struct_tests(model: StructIr, models: dict[str, ModelIr]) -> str:
    sample = _sample_value(IrType("named", model.name), models)
    if sample is None:
        return ""
    optional = [field for field in model.fields if field.optional]
    omitted = ""
    if optional:
        assertions = "\n".join(
            f"      assert_eq(fields.contains({moon_string(field.wire_name)}), false)"
            for field in optional
        )
        omitted = f"""
///|
/// Unset optional properties stay out of the encoded object.
test "{model.name} omits unset optional properties" {{
  match @json.to_json({sample}) {{
    Object(fields) => {{
{assertions}
    }}
    _ => abort("expected a JSON object")
  }}
}}
"""
    return f"""///|
/// A generated value survives an encode/decode round-trip.
test "{model.name} JSON round-trip" {{
  let value = {sample}
  let decoded : {model.name} = @json.from_json(@json.to_json(value))
  assert_eq(decoded, value)
}}
{omitted}"""


def tests_source(api: ApiIr) -> str:
    """The `sdk/models_wbtest.mbt` file: generated model coverage."""

    models = {model.name: model for model in api.models}
    header = f"""///|
/// Generated model tests for the `{api.title}` API (OpenAPI {api.version}).
///
/// These tests pin the wire contract of the generated codecs, so a generated
/// package is never accepted without exercising its own JSON behaviour.
"""
    blocks = [
        _enum_tests(model) if isinstance(model, EnumIr) else _struct_tests(model, models)
        for model in api.models
    ]
    return header + "\n" + "\n".join(block for block in blocks if block)


def _path_expression(operation: OperationIr) -> str:
    parts: list[str] = []
    for part in operation.path_parts:
        if part.literal is not None:
            parts.append(moon_string(part.literal))
        else:
            assert part.parameter is not None
            parameter = next(
                entry for entry in operation.params if entry.name == part.parameter
            )
            parts.append(
                "@runtime.encode_path_segment("
                + to_string_expr(parameter.type, part.parameter)
                + ")"
            )
    return " + ".join(parts)


def _operation_source(operation: OperationIr) -> str:
    lines: list[str] = ["///|", f"/// {operation.description}"]
    arguments = ["  self : Client,"]
    for parameter in operation.params:
        if parameter.optional:
            arguments.append(f"  {parameter.name}? : {parameter.type.render()},")
        else:
            arguments.append(f"  {parameter.name} : {parameter.type.render()},")
    if operation.body is not None:
        assert operation.body_name is not None
        arguments.append(f"  {operation.body_name} : {operation.body.render()},")
    return_type = "Unit" if operation.response is None else operation.response.render()
    lines.append(f"pub async fn Client::{operation.fn_name}(")
    lines.extend(arguments)
    lines.append(f") -> {return_type} raise @runtime.SdkError {{")

    if operation.security:
        rendered = ", ".join(moon_string(label) for label in operation.security)
        lines.append(f"  let headers = @runtime.auth_headers(self.config, [{rendered}])")
    else:
        lines.append("  let headers : Map[String, String] = Map([])")

    for parameter in operation.params:
        if parameter.location != "header":
            continue
        key = moon_string(parameter.wire_name)
        if parameter.optional:
            lines.extend(
                [
                    f"  match {parameter.name} {{",
                    f"    Some(value) => headers[{key}] = value",
                    "    None => ()",
                    "  }",
                ]
            )
        else:
            lines.append(f"  headers[{key}] = {parameter.name}")

    query_parameters = [p for p in operation.params if p.location == "query"]
    if query_parameters:
        lines.append("  let query : Array[(String, String)] = []")
        for parameter in query_parameters:
            key = moon_string(parameter.wire_name)
            rendered = to_string_expr(parameter.type, "value")
            if parameter.optional:
                lines.extend(
                    [
                        f"  match {parameter.name} {{",
                        f"    Some(value) => query.push(({key}, {rendered}))",
                        "    None => ()",
                        "  }",
                    ]
                )
            else:
                lines.append(
                    f"  query.push(({key}, {to_string_expr(parameter.type, parameter.name)}))"
                )

    if operation.body is not None:
        lines.append('  headers["Content-Type"] = "application/json"')

    if any(part.parameter is not None for part in operation.path_parts):
        lines.append(f"  let path = {_path_expression(operation)}")
        path_argument = "path"
    else:
        path_argument = _path_expression(operation)

    request_arguments = [moon_string(operation.method), path_argument]
    if query_parameters:
        request_arguments.append("query~")
    request_arguments.append("headers~")
    if operation.body is not None:
        assert operation.body_name is not None
        request_arguments.append(f"body={encode_expr(operation.body, operation.body_name)}")

    if len(request_arguments) <= 3:
        lines.append(f"  let request = @runtime.Request::new({', '.join(request_arguments)})")
    else:
        lines.append("  let request = @runtime.Request::new(")
        lines.extend(f"    {argument}," for argument in request_arguments)
        lines.append("  )")

    lines.append("  let response = @runtime.transmit(self.config, request)")
    lines.append(f"  @runtime.expect_status(response, [{operation.success_status}])")
    if operation.response is not None:
        lines.append("  @runtime.decode_json(response)")
    lines.append("}")
    return "\n".join(lines)


def client_source(api: ApiIr) -> str:
    """The `sdk/client.mbt` file."""

    header = f"""///|
/// Generated client for the `{api.title}` API (OpenAPI {api.version}).
///
/// Every operation only builds a `@runtime.Request`; the transport library is
/// reached exclusively through the runtime package.
pub struct Client {{
  config : @runtime.Config
}}

///|
/// Create a client. `base_url` overrides the first server declared by the spec.
pub fn Client::new(base_url : String, bearer_token? : String) -> Client {{
  {{ config: @runtime.Config::new(base_url, bearer_token?) }}
}}
"""
    blocks = [_operation_source(operation) for operation in api.operations]
    return header + "\n" + "\n".join(blocks)


def module_source(api: ApiIr) -> str:
    """The generated `moon.mod`."""

    return f"""name = "{api.module_name}"

version = "0.1.0"

import {{
  "moonbitlang/async@{ASYNC_VERSION}",
}}

preferred_target = "native"
"""


def runtime_package_source(api: ApiIr) -> str:
    """The generated `runtime/moon.pkg`."""

    template = TEMPLATE_ROOT / "moon.pkg"
    return template.read_text(encoding="utf-8")


def sdk_package_source(api: ApiIr) -> str:
    """The generated `sdk/moon.pkg`."""

    return f"""import {{
  "{api.module_name}/runtime",
  "{JSON_PACKAGE}",
}}

supported_targets = "+native"
"""


def emit(api: ApiIr) -> dict[str, str]:
    """Render every generated file, keyed by module-relative path.

    The rendered text is canonicalised by ``moonfmt`` before it is returned, so
    callers receive exactly the bytes ``moon fmt`` would leave on disk.
    """

    files: dict[str, str] = {
        "moon.mod": module_source(api),
        "runtime/moon.pkg": runtime_package_source(api),
        "sdk/client.mbt": client_source(api),
        "sdk/models.mbt": models_source(api),
        "sdk/moon.pkg": sdk_package_source(api),
    }
    if api.models:
        files["sdk/models_wbtest.mbt"] = tests_source(api)
    for template in sorted(TEMPLATE_ROOT.glob("*.mbt")):
        files[f"runtime/{template.name}"] = template.read_text(encoding="utf-8")
    rendered = {
        path: text.replace("\r\n", "\n") for path, text in sorted(files.items())
    }
    return {
        path: formatter.canonicalize(text, path)
        for path, text in sorted(rendered.items())
    }
