///|
/// Type mapping subsystem.
///
/// Converts Frontend Model schema nodes into IR TypeRef values.

///| Standard IR JSON access helpers.
pub fn get(v : Json, k : String) -> Json {
  match v {
    Object(o) => match o.get(k) {
      Some(x) => x
      None => Json::null()
    }
    _ => Json::null()
  }
}

pub fn text(v : Json) -> String {
  match v {
    String(s) => s
    _ => ""
  }
}

pub fn arr(v : Json) -> Array[Json] {
  match v {
    Array(a) => a
    _ => []
  }
}

pub fn obj(v : Json) -> Map[String, Json] {
  match v {
    Object(o) => o
    _ => Map([])
  }
}

pub fn truth(v : Json) -> Bool {
  match v {
    True => true
    _ => false
  }
}

///| Get the component name from a local `$ref` like `#/components/schemas/Pet`.
pub fn ref_target(ref_path : String) -> String {
  let parts = ref_path.split("/")
  let mut name = "Value"
  for p in parts {
    if p != "" { name = pascal(p.to_owned()) }
  }
  name
}

///| Map a Frontend Model schema JSON node to a TypeRef.
pub fn map_schema(schema : Json) -> TypeRef {
  let ref_path = text(get(schema, "ref"))
  if ref_path != "" {
    let name = ref_target(ref_path)
    return Named(name)
  }
  let kind = text(get(schema, "kind"))
  if kind == "array" {
    let items = get(schema, "items")
    return Array(map_schema(items))
  }
  if kind == "integer" {
    let fmt = text(get(schema, "format"))
    if fmt == "int64" { return Scalar("Int64") }
    return Scalar("Int")
  }
  if kind == "number" {
    return Scalar("Double")
  }
  if kind == "boolean" {
    return Scalar("Bool")
  }
  if kind == "any" {
    return Scalar("Json")
  }
  Scalar("String")
}

///| Determine presence from required and nullable flags.
pub fn compute_presence(required : Bool, nullable : Bool) -> Presence {
  if required && nullable { RequiredNullable }
  else if required { Required }
  else if nullable { OptionalNullable }
  else { Optional }
}

///| Convert a presence value to its canonical string representation.
pub fn presence_to_string(p : Presence) -> String {
  match p {
    Required => "required"
    RequiredNullable => "required_nullable"
    Optional => "optional"
    OptionalNullable => "optional_nullable"
  }
}

///| Convert TypeRef to its canonical JSON representation.
pub fn type_ref_to_json(t : TypeRef) -> Json {
  match t {
    Scalar(name) => Json::object(
      Map([("kind", Json::string("scalar")), ("name", Json::string(name))]),
    )
    Named(name) => Json::object(
      Map([("kind", Json::string("named")), ("name", Json::string(name))]),
    )
    Array(item) => Json::object(
      Map([("kind", Json::string("array")), ("item", type_ref_to_json(item))]),
    )
  }
}

///| Determine if a presence is required.
pub fn is_required_presence(p : Presence) -> Bool {
  match p {
    Required => true
    RequiredNullable => true
    _ => false
  }
}

///| Determine if a presence is nullable.
pub fn is_nullable_presence(p : Presence) -> Bool {
  match p {
    RequiredNullable => true
    OptionalNullable => true
    _ => false
  }
}
