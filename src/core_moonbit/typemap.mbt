///|
/// Type mapping subsystem.
///
/// Converts Frontend Model schema nodes into IR TypeRef values.

///|
/// Standard IR JSON access helpers.
pub fn get(v : Json, k : String) -> Json {
  match v {
    Object(o) =>
      match o.get(k) {
        Some(x) => x
        None => Json::null()
      }
    _ => Json::null()
  }
}

///|
pub fn text(v : Json) -> String {
  match v {
    String(s) => s
    _ => ""
  }
}

///|
pub fn arr(v : Json) -> Array[Json] {
  match v {
    Array(a) => a
    _ => []
  }
}

///|
pub fn obj(v : Json) -> Map[String, Json] {
  match v {
    Object(o) => o
    _ => Map([])
  }
}

///|
pub fn truth(v : Json) -> Bool {
  match v {
    True => true
    _ => false
  }
}

///|
/// Get the component name from a local `$ref` like `#/components/schemas/Pet`.
pub fn ref_target(ref_path : String) -> String {
  let parts = ref_path.split("/")
  let mut name = "Value"
  for p in parts {
    if p != "" {
      name = pascal(p.to_owned())
    }
  }
  name
}

///|
/// Map a Frontend Model schema JSON node to a TypeRef.
pub fn map_schema(
  schema : Json,
  names~ : Map[String, String] = Map([]),
  nullable_refs~ : Map[String, Bool] = Map([]),
) -> TypeRef {
  let ref_path = text(get(schema, "ref"))
  let kind = text(get(schema, "kind"))
  let base = if ref_path != "" {
    let named = Named(names.get(ref_path).unwrap_or(ref_target(ref_path)))
    if nullable_refs.get(ref_path).unwrap_or(false) {
      Nullable(named)
    } else {
      named
    }
  } else if kind == "array" {
    let items = get(schema, "items")
    let item_type = map_schema(items, names~, nullable_refs~)
    Array(item_type)
  } else if kind == "integer" {
    let fmt = text(get(schema, "format"))
    if fmt == "int64" {
      Scalar("Int64")
    } else {
      Scalar("Int")
    }
  } else if kind == "number" {
    Scalar("Double")
  } else if kind == "boolean" {
    Scalar("Bool")
  } else if kind == "any" || kind == "object" {
    Scalar("Json")
  } else {
    Scalar("String")
  }
  if truth(get(schema, "nullable")) {
    // A normalized `$ref` may carry the target component's nullable flag as
    // well as the reference-site flag. Keep the wrapper idempotent so the IR
    // records one wire-level nullability layer, not `Nullable(Nullable(T))`.
    match base {
      Nullable(_) => base
      _ => Nullable(base)
    }
  } else {
    base
  }
}

///|
/// Determine presence from required and nullable flags.
pub fn compute_presence(required : Bool, nullable : Bool) -> Presence {
  if required && nullable {
    RequiredNullable
  } else if required {
    Required
  } else if nullable {
    OptionalNullable
  } else {
    Optional
  }
}

///|
/// Convert a presence value to its canonical string representation.
pub fn presence_to_string(p : Presence) -> String {
  match p {
    Required => "required"
    RequiredNullable => "required_nullable"
    Optional => "optional"
    OptionalNullable => "optional_nullable"
  }
}

///|
/// Convert TypeRef to its canonical JSON representation.
pub fn type_ref_to_json(t : TypeRef) -> Json {
  match t {
    Scalar(name) =>
      Json::object(
        Map([("kind", Json::string("scalar")), ("name", Json::string(name))]),
      )
    Named(name) =>
      Json::object(
        Map([("kind", Json::string("named")), ("name", Json::string(name))]),
      )
    Array(item) =>
      Json::object(
        Map([("kind", Json::string("array")), ("item", type_ref_to_json(item))]),
      )
    Nullable(item) =>
      Json::object(
        Map([
          ("kind", Json::string("nullable")),
          ("item", type_ref_to_json(item)),
        ]),
      )
  }
}

///|
/// Determine if a presence is required.
pub fn is_required_presence(p : Presence) -> Bool {
  match p {
    Required => true
    RequiredNullable => true
    _ => false
  }
}

///|
/// Determine if a presence is nullable.
pub fn is_nullable_presence(p : Presence) -> Bool {
  match p {
    RequiredNullable => true
    OptionalNullable => true
    _ => false
  }
}
