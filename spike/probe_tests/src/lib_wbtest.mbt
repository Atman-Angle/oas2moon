test "closure with raise" {
  let decode = fn(text : String) -> PetStatus raise @json.JsonDecodeError {
    @json.from_json(Json::string(text))
  }
  assert_eq(decode("available"), Available)
}

test "map contains" {
  let fields : Map[String, Json] = Map([])
  fields["id"] = Json::null()
  assert_eq(fields.contains("id"), true)
  assert_eq(fields.contains("tags"), false)
}

test "match object abort arm" {
  match sample_json() {
    Object(fields) => {
      assert_eq(fields.contains("tags"), false)
      assert_eq(fields.contains("id"), true)
    }
    _ => abort("expected a JSON object")
  }
}

test "match option arm" {
  let fields : Map[String, Json] = Map([])
  match fields.get("tags") {
    None => ()
    Some(_) => abort("expected no tags")
  }
}
