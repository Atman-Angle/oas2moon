///|
test "primitive and int64 mapping" {
  let i = type_ref(
    Json::object(
      Map([("kind", Json::string("integer")), ("format", Json::string("int64"))]),
    ),
  )
  assert_eq(text(get(i, "name")), "Int64")
  let b = type_ref(Json::object(Map([("kind", Json::string("boolean"))])))
  assert_eq(text(get(b, "name")), "Bool")
}

///|
test "array and local ref mapping" {
  let r = type_ref(
    Json::object(Map([("ref", Json::string("#/components/schemas/Pet"))])),
  )
  assert_eq(text(get(r, "name")), "Pet")
  let a = type_ref(
    Json::object(
      Map([
        ("kind", Json::string("array")),
        ("items", Json::object(Map([("kind", Json::string("string"))]))),
      ]),
    ),
  )
  assert_eq(text(get(get(a, "item"), "name")), "String")
}

///|
test "naming reserved and enum values" {
  assert_eq(snake("X-Trace"), "x_trace")
  assert_eq(snake("type"), "type_")
  assert_eq(pascal("available"), "Available")
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
test "canonical json deterministic" {
  let x = Json::object(
    Map([("b", Json::number(2.0)), ("a", Json::string("x"))]),
  )
  assert_eq(x.stringify(), x.stringify())
}
