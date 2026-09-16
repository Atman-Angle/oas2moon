///|
/// Strict in-memory view of the Canonical Client IR consumed by the codegen
/// emitters. JSON names, MoonBit names, presence and wire strings all arrive
/// precomputed from the Phase 1.5 authority; this module only validates and
/// copies them.

///|
pub struct TypeRef {
  kind : String
  name : String?
  item : TypeRef?
} derive(Eq, Debug)

///|
pub struct FieldIr {
  name : String
  wire_name : String
  type_ref : TypeRef
  presence : String
} derive(Eq, Debug)

///|
pub struct EnumMemberIr {
  name : String
  wire : String
} derive(Eq, Debug)

///|
pub struct EnumModelIr {
  name : String
  members : Array[EnumMemberIr]
} derive(Eq, Debug)

///|
pub struct StructModelIr {
  name : String
  fields : Array[FieldIr]
  additional_properties : Bool
  additional_properties_field : String?
} derive(Eq, Debug)

///|
pub enum ModelIr {
  EnumModel(EnumModelIr)
  StructModel(StructModelIr)
} derive(Eq, Debug)

///|
pub enum ParamLocation {
  PathLoc
  QueryLoc
  HeaderLoc
} derive(Eq, Debug)

///|
pub struct ParameterIr {
  name : String
  wire_name : String
  location : ParamLocation
  type_ref : TypeRef
  required : Bool
  nullable : Bool
  presence : String
} derive(Eq, Debug)

///|
pub struct RequestBodyIr {
  type_ref : TypeRef?
  required : Bool
  media_type : String?
} derive(Eq, Debug)

///|
pub struct ResponseIr {
  status : Int
  type_ref : TypeRef?
  media_type : String?
} derive(Eq, Debug)

///|
pub struct ResponseVariant {
  status : Int
  type_ref : TypeRef
} derive(Eq, Debug)

///|
pub enum ResponseStrategy {
  SingleResult(TypeRef)
  UnitResult
  ResponseEnum(Array[ResponseVariant])
  NoContent
  UnsupportedMediaType(String)
} derive(Eq, Debug)

///|
pub struct AuthSchemeIr {
  name : String
  kind : String
  location : String?
  key_name : String?
} derive(Eq, Debug)

///|
pub struct OperationIr {
  operation_id : String
  fn_name : String
  http_method : String
  path : String
  tags : Array[String]
  parameters : Array[ParameterIr]
  request_body : RequestBodyIr?
  body_name : String?
  success_responses : Array[ResponseIr]
  error_responses : Array[ResponseIr]
  response_strategy : ResponseStrategy
  security : Array[String]
  source_pointer : String
} derive(Eq, Debug)

///|
pub struct ApiIr {
  module_name : String
  title : String
  version : String
  servers : Array[String]
  auth_schemes : Array[AuthSchemeIr]
  models : Array[ModelIr]
  operations : Array[OperationIr]
} derive(Eq, Debug)

// ---------------------------------------------------------------------------
// JSON helpers
// ---------------------------------------------------------------------------

///|
fn require_object(value : Json, location : String) -> Map[String, Json] raise {
  match value {
    Object(fields) => fields
    _ => raise Failure(location + ": expected object")
  }
}

///|
fn require_array(value : Json, location : String) -> Array[Json] raise {
  match value {
    Array(items) => items
    _ => raise Failure(location + ": expected array")
  }
}

///|
fn require_string(value : Json, location : String) -> String raise {
  match value {
    String(text) => text
    _ => raise Failure(location + ": expected string")
  }
}

///|
fn require_bool(value : Json, location : String) -> Bool raise {
  match value {
    True => true
    False => false
    _ => raise Failure(location + ": expected boolean")
  }
}

///|
fn require_field(
  fields : Map[String, Json],
  key : String,
  location : String,
) -> Json raise {
  match fields.get(key) {
    Some(value) => value
    None => raise Failure(location + ": missing field " + key.escape())
  }
}

///|
fn require_string_field(
  fields : Map[String, Json],
  key : String,
  location : String,
) -> String raise {
  require_string(require_field(fields, key, location), location + "." + key)
}

///|
fn require_bool_field(
  fields : Map[String, Json],
  key : String,
  location : String,
) -> Bool raise {
  require_bool(require_field(fields, key, location), location + "." + key)
}

///|
fn require_array_field(
  fields : Map[String, Json],
  key : String,
  location : String,
) -> Array[Json] raise {
  require_array(require_field(fields, key, location), location + "." + key)
}

///|
fn optional_string_field(
  fields : Map[String, Json],
  key : String,
  location : String,
) -> String? raise {
  match fields.get(key) {
    Some(Null) => None
    Some(value) => Some(require_string(value, location + "." + key))
    None => raise Failure(location + ": missing field " + key.escape())
  }
}

///|
fn optional_type_ref_field(
  fields : Map[String, Json],
  key : String,
  location : String,
) -> TypeRef? raise {
  match fields.get(key) {
    Some(Null) => None
    Some(value) => Some(parse_type_ref(value, location + "." + key))
    None => raise Failure(location + ": missing field " + key.escape())
  }
}

// ---------------------------------------------------------------------------
// Type parsing
// ---------------------------------------------------------------------------

///|
fn is_known_scalar(name : String) -> Bool {
  name == "String" ||
  name == "Bool" ||
  name == "Int" ||
  name == "Int64" ||
  name == "Double" ||
  name == "Json"
}

///|
fn parse_type_ref(value : Json, location : String) -> TypeRef raise {
  let fields = require_object(value, location)
  let kind = require_string_field(fields, "kind", location)
  match kind {
    "scalar" => {
      let name = require_string_field(fields, "name", location)
      if !is_known_scalar(name) {
        raise Failure(location + ": unsupported scalar " + name.escape())
      }
      { kind, name: Some(name), item: None }
    }
    "named" => {
      let name = require_string_field(fields, "name", location)
      if name.length() == 0 {
        raise Failure(location + ": named type name must not be empty")
      }
      { kind, name: Some(name), item: None }
    }
    "array" => {
      let item_value = require_field(fields, "item", location)
      let item = parse_type_ref(item_value, location + ".item")
      { kind, name: None, item: Some(item) }
    }
    _ => raise Failure(location + ": unsupported type kind " + kind.escape())
  }
}

///|
fn expected_presence(required : Bool, nullable : Bool) -> String {
  if required && nullable {
    "required_nullable"
  } else if required {
    "required"
  } else if nullable {
    "optional_nullable"
  } else {
    "optional"
  }
}

// ---------------------------------------------------------------------------
// Model parsing
// ---------------------------------------------------------------------------

///|
fn parse_field(value : Json, location : String) -> FieldIr raise {
  let fields = require_object(value, location)
  let name = require_string_field(fields, "name", location)
  let wire_name = require_string_field(fields, "wire_name", location)
  let required = require_bool_field(fields, "required", location)
  let nullable = require_bool_field(fields, "nullable", location)
  let presence = require_string_field(fields, "presence", location)
  let expected = expected_presence(required, nullable)
  if presence != expected {
    raise Failure(
      location +
      ": presence mismatch: got " +
      presence.escape() +
      ", expected " +
      expected,
    )
  }
  let type_value = require_field(fields, "type", location)
  let type_ref = parse_type_ref(type_value, location + ".type")
  { name, wire_name, type_ref, presence }
}

///|
fn parse_enum_member(value : Json, location : String) -> (String, String) raise {
  let pair = require_array(value, location)
  guard pair.length() == 2 else {
    raise Failure(location + ": enum member must be a 2-element array")
  }
  let name = require_string(pair[0], location + "[0]")
  let wire = require_string(pair[1], location + "[1]")
  (name, wire)
}

///|
fn parse_enum(
  fields : Map[String, Json],
  location : String,
) -> EnumModelIr raise {
  let name = require_string_field(fields, "name", location)
  let member_values = require_array_field(fields, "members", location)
  let members : Array[EnumMemberIr] = []
  let taken_names : Map[String, Bool] = Map([])
  let taken_wires : Map[String, Bool] = Map([])
  for index, value in member_values {
    let member_where = location + ".members[" + index.to_string() + "]"
    let (n, w) = parse_enum_member(value, member_where)
    if taken_names.get(n) is Some(_) {
      raise Failure(member_where + ": duplicate enum member name")
    }
    if taken_wires.get(w) is Some(_) {
      raise Failure(member_where + ": duplicate enum wire value")
    }
    taken_names[n] = true
    taken_wires[w] = true
    members.push({ name: n, wire: w })
  }
  { name, members }
}

///|
fn parse_struct(
  fields : Map[String, Json],
  location : String,
) -> StructModelIr raise {
  let name = require_string_field(fields, "name", location)
  let additional_properties = require_bool_field(
    fields, "additional_properties", location,
  )
  let additional_properties_field = optional_string_field(
    fields, "additional_properties_field", location,
  )
  if additional_properties && additional_properties_field is None {
    raise Failure(
      location + ": additionalProperties=true requires a field name",
    )
  }
  if !additional_properties && additional_properties_field is Some(_) {
    raise Failure(
      location + ": additionalProperties=false must use a null field name",
    )
  }
  let field_values = require_array_field(fields, "fields", location)
  let parsed_fields : Array[FieldIr] = []
  let taken_names : Map[String, Bool] = Map([])
  let taken_wires : Map[String, Bool] = Map([])
  for index, value in field_values {
    let field_where = location + ".fields[" + index.to_string() + "]"
    let field = parse_field(value, field_where)
    if taken_names.get(field.name) is Some(_) {
      raise Failure(field_where + ": duplicate field name")
    }
    if taken_wires.get(field.wire_name) is Some(_) {
      raise Failure(field_where + ": duplicate wire_name")
    }
    taken_names[field.name] = true
    taken_wires[field.wire_name] = true
    parsed_fields.push(field)
  }
  match additional_properties_field {
    Some(extra_name) =>
      if taken_names.get(extra_name) is Some(_) {
        raise Failure(
          location +
          ": additional properties field collides with a declared field",
        )
      }
    None => ()
  }
  {
    name,
    fields: parsed_fields,
    additional_properties,
    additional_properties_field,
  }
}

///|
fn validate_named_type(
  type_ref : TypeRef,
  location : String,
  model_names : Map[String, Bool],
) -> Unit raise {
  match type_ref.kind {
    "named" =>
      match type_ref.name {
        Some(name) =>
          if model_names.get(name) is None {
            raise Failure(location + ": unresolved named type " + name.escape())
          }
        None => abort("validated named type is missing its name")
      }
    "array" =>
      match type_ref.item {
        Some(item) => validate_named_type(item, location + ".item", model_names)
        None => abort("validated array type is missing its item")
      }
    _ => ()
  }
}

///|
fn validate_model_references(
  model : ModelIr,
  model_names : Map[String, Bool],
) -> Unit raise {
  match model {
    EnumModel(_) => ()
    StructModel(value) =>
      for index, field in value.fields {
        validate_named_type(
          field.type_ref,
          "canonical.models." +
          value.name +
          ".fields[" +
          index.to_string() +
          "].type",
          model_names,
        )
      }
  }
}

///|
fn parse_model(value : Json, location : String) -> ModelIr raise {
  let fields = require_object(value, location)
  let kind = require_string_field(fields, "kind", location)
  match kind {
    "enum" => EnumModel(parse_enum(fields, location))
    "struct" => StructModel(parse_struct(fields, location))
    _ => raise Failure(location + ": unsupported model kind " + kind.escape())
  }
}

// ---------------------------------------------------------------------------
// Operation parsing
// ---------------------------------------------------------------------------

///|
fn parse_param_location(loc : String, location : String) -> ParamLocation raise {
  match loc {
    "path" => PathLoc
    "query" => QueryLoc
    "header" => HeaderLoc
    _ =>
      raise Failure(
        location + ": unsupported parameter location " + loc.escape(),
      )
  }
}

///|
fn parse_parameter(value : Json, location : String) -> ParameterIr raise {
  let fields = require_object(value, location)
  let name = require_string_field(fields, "name", location)
  let wire_name = require_string_field(fields, "wire_name", location)
  let loc_str = require_string_field(fields, "location", location)
  let loc = parse_param_location(loc_str, location + ".location")
  let required = require_bool_field(fields, "required", location)
  let nullable = require_bool_field(fields, "nullable", location)
  let presence = require_string_field(fields, "presence", location)
  let expected = expected_presence(required, nullable)
  if presence != expected {
    raise Failure(
      location +
      ": presence mismatch: got " +
      presence.escape() +
      ", expected " +
      expected,
    )
  }
  let type_value = require_field(fields, "type", location)
  let type_ref = parse_type_ref(type_value, location + ".type")
  { name, wire_name, location: loc, type_ref, required, nullable, presence }
}

///|
fn parse_request_body(value : Json, location : String) -> RequestBodyIr? raise {
  match value {
    Null => None
    _ => {
      let fields = require_object(value, location)
      let type_ref = optional_type_ref_field(fields, "type", location)
      let required = require_bool_field(fields, "required", location)
      let media_type = optional_string_field(fields, "media_type", location)
      Some({ type_ref, required, media_type })
    }
  }
}

///|
fn parse_response(value : Json, location : String) -> ResponseIr raise {
  let fields = require_object(value, location)
  let status = match require_field(fields, "status", location) {
    Number(n, ..) if n == n.trunc() => n.to_int()
    _ => raise Failure(location + ".status: expected number")
  }
  let type_ref = optional_type_ref_field(fields, "type", location)
  let media_type = optional_string_field(fields, "media_type", location)
  { status, type_ref, media_type }
}

///|
fn parse_responses_array(
  value : Json,
  location : String,
) -> Array[ResponseIr] raise {
  let items = require_array(value, location)
  let out : Array[ResponseIr] = []
  for index, item in items {
    out.push(parse_response(item, location + "[" + index.to_string() + "]"))
  }
  out
}

///|
fn parse_response_strategy(
  value : Json,
  location : String,
) -> ResponseStrategy raise {
  let fields = require_object(value, location)
  let kind = require_string_field(fields, "kind", location)
  match kind {
    "single_result" => {
      let type_value = require_field(fields, "type", location)
      SingleResult(parse_type_ref(type_value, location + ".type"))
    }
    "unit_result" => UnitResult
    "no_content" => NoContent
    "response_enum" => {
      let variants_value = require_field(fields, "variants", location)
      let variant_items = require_array(variants_value, location + ".variants")
      let variants : Array[ResponseVariant] = []
      for index, vv in variant_items {
        let vloc = location + ".variants[" + index.to_string() + "]"
        let vf = require_object(vv, vloc)
        let status = match require_field(vf, "status", vloc) {
          Number(n, ..) if n == n.trunc() => n.to_int()
          _ => raise Failure(vloc + ".status: expected number")
        }
        let tv = require_field(vf, "type", vloc)
        let type_ref = parse_type_ref(tv, vloc + ".type")
        variants.push({ status, type_ref })
      }
      ResponseEnum(variants)
    }
    "unsupported_media_type" => {
      let mt = require_string_field(fields, "media_type", location)
      UnsupportedMediaType(mt)
    }
    _ =>
      raise Failure(
        location + ": unsupported response strategy kind " + kind.escape(),
      )
  }
}

///|
fn parse_strings_array(value : Json, location : String) -> Array[String] raise {
  let items = require_array(value, location)
  let out : Array[String] = []
  for index, item in items {
    out.push(require_string(item, location + "[" + index.to_string() + "]"))
  }
  out
}

///|
fn parse_auth_scheme(value : Json, location : String) -> AuthSchemeIr raise {
  let fields = require_object(value, location)
  let name = require_string_field(fields, "name", location)
  let kind = require_string_field(fields, "kind", location)
  let loc = optional_string_field(fields, "location", location)
  let key_name = optional_string_field(fields, "key_name", location)
  { name, kind, location: loc, key_name }
}

///|
fn parse_auth_schemes(
  value : Json,
  location : String,
) -> Array[AuthSchemeIr] raise {
  let items = require_array(value, location)
  let out : Array[AuthSchemeIr] = []
  for index, item in items {
    out.push(parse_auth_scheme(item, location + "[" + index.to_string() + "]"))
  }
  out
}

///|
fn parse_operation(
  value : Json,
  location : String,
  model_names : Map[String, Bool],
) -> OperationIr raise {
  let fields = require_object(value, location)
  let operation_id = require_string_field(fields, "operation_id", location)
  let fn_name = require_string_field(fields, "fn_name", location)
  let http_method = require_string_field(fields, "http_method", location)
  let path = require_string_field(fields, "path", location)
  let tags = match fields.get("tags") {
    Some(tv) => parse_strings_array(tv, location + ".tags")
    None => []
  }
  let parameters : Array[ParameterIr] = []
  match fields.get("parameters") {
    Some(pv) => {
      let pitems = require_array(pv, location + ".parameters")
      for index, p in pitems {
        parameters.push(
          parse_parameter(
            p,
            location + ".parameters[" + index.to_string() + "]",
          ),
        )
      }
    }
    None => ()
  }
  for index, p in parameters {
    validate_named_type(
      p.type_ref,
      location + ".parameters[" + index.to_string() + "].type",
      model_names,
    )
  }
  let request_body = match fields.get("request_body") {
    Some(rv) => parse_request_body(rv, location + ".request_body")
    None => None
  }
  let body_name = match fields.get("body_name") {
    Some(Null) => None
    Some(value) => Some(require_string(value, location + ".body_name"))
    None => None
  }
  match request_body {
    Some(body) =>
      match body.type_ref {
        Some(tr) =>
          validate_named_type(tr, location + ".request_body.type", model_names)
        None => ()
      }
    None => ()
  }
  let success_responses = match fields.get("success_responses") {
    Some(sv) => parse_responses_array(sv, location + ".success_responses")
    None => []
  }
  let error_responses = match fields.get("error_responses") {
    Some(ev) => parse_responses_array(ev, location + ".error_responses")
    None => []
  }
  for index, r in success_responses {
    match r.type_ref {
      Some(tr) =>
        validate_named_type(
          tr,
          location + ".success_responses[" + index.to_string() + "].type",
          model_names,
        )
      None => ()
    }
  }
  let response_strategy = match fields.get("response_strategy") {
    Some(rsv) => parse_response_strategy(rsv, location + ".response_strategy")
    None => raise Failure(location + ": missing field response_strategy")
  }
  match response_strategy {
    SingleResult(tr) =>
      validate_named_type(tr, location + ".response_strategy.type", model_names)
    ResponseEnum(variants) =>
      for index, v in variants {
        validate_named_type(
          v.type_ref,
          location +
          ".response_strategy.variants[" +
          index.to_string() +
          "].type",
          model_names,
        )
      }
    _ => ()
  }
  let security = match fields.get("security") {
    Some(sv) => parse_strings_array(sv, location + ".security")
    None => []
  }
  let source_pointer = match fields.get("source_pointer") {
    Some(sp) => require_string(sp, location + ".source_pointer")
    None => ""
  }
  {
    operation_id,
    fn_name,
    http_method,
    path,
    tags,
    parameters,
    request_body,
    body_name,
    success_responses,
    error_responses,
    response_strategy,
    security,
    source_pointer,
  }
}

// ---------------------------------------------------------------------------
// Top-level API parsing
// ---------------------------------------------------------------------------

///|
pub fn parse_api(value : Json) -> ApiIr raise {
  let root = require_object(value, "canonical")
  let module_name = require_string_field(root, "module", "canonical")
  let title = match root.get("title") {
    Some(t) => require_string(t, "canonical.title")
    None => ""
  }
  let version = match root.get("version") {
    Some(v) => require_string(v, "canonical.version")
    None => ""
  }
  let servers = match root.get("servers") {
    Some(sv) => parse_strings_array(sv, "canonical.servers")
    None => []
  }
  let auth_schemes = match root.get("auth_schemes") {
    Some(av) => parse_auth_schemes(av, "canonical.auth_schemes")
    None => []
  }
  let model_values = require_array_field(root, "models", "canonical")
  let models : Array[ModelIr] = []
  let model_names : Map[String, Bool] = Map([])
  for index, model_value in model_values {
    let location = "canonical.models[" + index.to_string() + "]"
    let model = parse_model(model_value, location)
    let name = match model {
      EnumModel(value) => value.name
      StructModel(value) => value.name
    }
    if model_names.get(name) is Some(_) {
      raise Failure(location + ": duplicate model name " + name.escape())
    }
    model_names[name] = true
    models.push(model)
  }
  for model in models {
    validate_model_references(model, model_names)
  }
  let operations : Array[OperationIr] = []
  match root.get("operations") {
    Some(ov) => {
      let op_items = require_array(ov, "canonical.operations")
      for index, op_value in op_items {
        let op_loc = "canonical.operations[" + index.to_string() + "]"
        operations.push(parse_operation(op_value, op_loc, model_names))
      }
    }
    None => ()
  }
  { module_name, title, version, servers, auth_schemes, models, operations }
}
