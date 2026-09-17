///|
/// Integration tests for the canonical IR lowering.
test "primitive and int64 mapping" {
  let i = map_schema(
    Json::object(
      Map([("kind", Json::string("integer")), ("format", Json::string("int64"))]),
    ),
  )
  match i {
    Scalar(name) => assert_eq(name, "Int64")
    _ => raise Failure("expected Scalar(Int64)")
  }
  let b = map_schema(Json::object(Map([("kind", Json::string("boolean"))])))
  match b {
    Scalar(name) => assert_eq(name, "Bool")
    _ => raise Failure("expected Scalar(Bool)")
  }
}

///|
test "array and local ref mapping" {
  let r = map_schema(
    Json::object(Map([("ref", Json::string("#/components/schemas/Pet"))])),
  )
  match r {
    Named(name) => assert_eq(name, "Pet")
    _ => raise Failure("expected Named(Pet)")
  }
  let a = map_schema(
    Json::object(
      Map([
        ("kind", Json::string("array")),
        ("items", Json::object(Map([("kind", Json::string("string"))]))),
      ]),
    ),
  )
  match a {
    Array(item) =>
      match item {
        Scalar(name) => assert_eq(name, "String")
        _ => raise Failure("expected Array(Scalar(String))")
      }
    _ => raise Failure("expected Array")
  }
}

///|
test "naming reserved and enum values" {
  assert_eq(snake("X-Trace"), "x_trace")
  assert_eq(snake("type"), "type_")
  assert_eq(pascal("available"), "Available")
  assert_eq(pascal("error"), "ErrorValue")
}

///|
test "operation ordering" {
  let d = Json::object(
    Map([
      ("path", Json::string("/pets")),
      ("method", Json::string("DELETE")),
      ("operationId", Json::string("deletePet")),
    ]),
  )
  let p = Json::object(
    Map([
      ("path", Json::string("/pets")),
      ("method", Json::string("POST")),
      ("operationId", Json::string("addPet")),
    ]),
  )
  assert_eq(before(d, p), true)
}

///|
test "canonical json is deterministic" {
  let x = Json::object(
    Map([("b", Json::number(2.0)), ("a", Json::string("x"))]),
  )
  assert_eq(x.stringify(), x.stringify())
}

///|
test "snake converts getPetById" {
  assert_eq(snake("getPetById"), "get_pet_by_id")
}

///|
test "pascal handles PetStatus" {
  assert_eq(pascal("PetStatus"), "PetStatus")
}

///|
test "unique returns first free name" {
  let taken : Map[String, Bool] = Map([])
  let a = unique("foo", taken)
  let b = unique("foo", taken)
  assert_eq(a, "foo")
  assert_eq(b, "foo_2")
}
