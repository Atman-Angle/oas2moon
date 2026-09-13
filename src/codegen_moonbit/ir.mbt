///|
/// Strict in-memory view of the Canonical Client IR consumed by the model
/// emitter. JSON names, MoonBit names, presence and wire strings all arrive
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
pub struct ApiIr {
  module_name : String
  models : Array[ModelIr]
} derive(Eq, Debug)

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
      { kind, name: Some(name), item: None, }
    }
    "named" => {
      let name = require_string_field(fields, "name", location)
      if name.length() == 0 {
        raise Failure(location + ": named type name must not be empty")
      }
      { kind, name: Some(name), item: None, }
    }
    "array" => {
      let item_value = require_field(fields, "item", location)
      let item = parse_type_ref(item_value, location + ".item")
      { kind, name: None, item: Some(item), }
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
      ": presence " +
      presence.escape() +
      " does not match required/nullable",
    )
  }
  if name.length() == 0 {
    raise Failure(location + ": field name must not be empty")
  }
  if wire_name.length() == 0 {
    raise Failure(location + ": wire_name must not be empty")
  }
  {
    name,
    wire_name,
    type_ref: parse_type_ref(
      require_field(fields, "type", location),
      location + ".type",
    ),
    presence,
  }
}

///|
fn parse_enum_member(value : Json, location : String) -> EnumMemberIr raise {
  let pair = require_array(value, location)
  if pair.length() != 2 {
    raise Failure(location + ": enum enum_member must be a two-element array")
  }
  let name = require_string(pair[0], location + "[0]")
  let wire = require_string(pair[1], location + "[1]")
  if name.length() == 0 {
    raise Failure(location + ": enum enum_member name must not be empty")
  }
  { name, wire, }
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
    let enum_member = parse_enum_member(value, member_where)
    if taken_names.get(enum_member.name) is Some(_) {
      raise Failure(member_where + ": duplicate enum enum_member name")
    }
    if taken_wires.get(enum_member.wire) is Some(_) {
      raise Failure(member_where + ": duplicate enum wire value")
    }
    taken_names[enum_member.name] = true
    taken_wires[enum_member.wire] = true
    members.push(enum_member)
  }
  { name, members, }
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

///|
pub fn parse_api(value : Json) -> ApiIr raise {
  let root = require_object(value, "canonical")
  let module_name = require_string_field(root, "module", "canonical")
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
  { module_name, models, }
}
