///| Shared assumption probe for the feasibility spike.
///
/// This package exists to answer concrete questions about the current MoonBit
/// toolchain before the generator relies on them:
///
/// 1. does `derive(FromJson)` on a struct map a missing optional field to `None`?
/// 2. does it map an explicit JSON `null` to `None`?
/// 3. does `derive(FromJson)` on an enum use constructor names instead of wire values?
/// 4. does `Json::object` preserve insertion order when stringified?
/// 5. does `@json.from_json` raise on unknown extra keys?

///|
pub(all) struct ProbeModel {
  required_name : String
  optional_tags : Array[String]?
  nullable_note : String?
} derive(FromJson, Eq, Debug)

///|
pub(all) enum ProbeEnum {
  Available
  Pending
} derive(FromJson, ToJson, Eq, Debug)

///|
fn report(label : String, value : Json) -> Unit {
  println(
    Json::object(Map([("label", Json::string(label)), ("value", value)])).stringify(),
  )
}

///|
fn main raise {
  // 1. missing optional field
  let decoded : ProbeModel = @json.from_json(
    @json.parse("{\"required_name\":\"a\"}"),
  )
  report("missing_optional", Json::string(decoded.required_name))
  report("missing_optional_tags", Json::boolean(decoded.optional_tags is None))
  report("missing_nullable_note", Json::boolean(decoded.nullable_note is None))
  // 2. explicit null
  let null_result : Result[ProbeModel, Json] = try {
    let v : ProbeModel = @json.from_json(
      @json.parse(
        "{\"required_name\":\"a\",\"optional_tags\":null,\"nullable_note\":null}",
      ),
    )
    Ok(v)
  } catch {
    _ => Err(Json::string("decode error"))
  }
  report(
    "explicit_null",
    match null_result {
      Ok(v) => Json::string("decoded: tags_none=" + (v.optional_tags is None).to_string())
      Err(err) => err
    },
  )
  // 2b. present value
  let decoded_some : ProbeModel = @json.from_json(
    @json.parse(
      "{\"required_name\":\"a\",\"optional_tags\":[\"x\",\"y\"],\"nullable_note\":\"n\"}",
    ),
  )
  report(
    "present_tags",
    Json::string(decoded_some.optional_tags.unwrap_or([]).length().to_string()),
  )
  // 3. enum decode from constructor name vs wire value
  let enum_ok : Result[ProbeEnum, Json] = try {
    let v : ProbeEnum = @json.from_json(@json.parse("\"Available\""))
    Ok(v)
  } catch {
    _ => Err(Json::string("decode error"))
  }
  report(
    "enum_constructor_name",
    match enum_ok {
      Ok(_) => Json::string("decoded")
      Err(err) => err
    },
  )
  let enum_wire : Result[ProbeEnum, Json] = try {
    let v : ProbeEnum = @json.from_json(@json.parse("\"available\""))
    Ok(v)
  } catch {
    _ => Err(Json::string("decode error"))
  }
  report(
    "enum_wire_value",
    match enum_wire {
      Ok(_) => Json::string("decoded")
      Err(err) => err
    },
  )
  // 4. insertion order
  let ordered : Map[String, Json] = Map([])
  ordered["z"] = Json::string("1")
  ordered["a"] = Json::string("2")
  ordered["m"] = Json::string("3")
  report("object_order", Json::string(Json::object(ordered).stringify()))
  // 5. number round trip: does parsing keep the original numeric text?
  let parsed_number : Result[Json, Json] = try {
    Ok(@json.parse("{\"id\":9007199254740993}"))
  } catch {
    _ => Err(Json::string("parse error"))
  }
  report(
    "number_parse_stringify",
    match parsed_number {
      Ok(value) => Json::string(value.stringify())
      Err(err) => err
    },
  )
  report(
    "number_with_repr",
    Json::string(Json::number(42.0, repr="42").stringify()),
  )
  report("number_without_repr", Json::string(Json::number(42.0).stringify()))
  let repr_probe : Result[String, Json] = try {
    let parsed = @json.parse("{\"id\":42,\"big\":9007199254740993}")
    match parsed {
      Object(fields) =>
        match fields.get("id") {
          Some(Number(_, repr~)) =>
            Ok(
              match repr {
                Some(text) => "id repr=" + text
                None => "id repr=<none>"
              },
            )
          _ => Ok("id is not a Number")
        }
      _ => Ok("not an object")
    }
  } catch {
    _ => Err(Json::string("parse error"))
  }
  report(
    "number_repr",
    match repr_probe {
      Ok(text) => Json::string(text)
      Err(err) => err
    },
  )
  report(
    "number_debug",
    Json::string(@debug.to_string(@json.parse("{\"id\":42}"))),
  )
  let repr_probe2 : Result[String, Json] = try {
    let parsed = @json.parse("{\"id\":42}")
    match parsed {
      Object(fields) =>
        match fields.get("id") {
          Some(Number(_, repr=repr)) =>
            Ok(
              match repr {
                Some(text) => "id repr=" + text
                None => "id repr=<none>"
              },
            )
          _ => Ok("id is not a Number")
        }
      _ => Ok("not an object")
    }
  } catch {
    _ => Err(Json::string("parse error"))
  }
  report(
    "number_repr2",
    match repr_probe2 {
      Ok(text) => Json::string(text)
      Err(err) => err
    },
  )
  report("int64_to_json", Json::string(@json.to_json(42L).stringify()))
  let int64_from_number : Result[Int64, Json] = try {
    Ok(@json.from_json(@json.parse("42")))
  } catch {
    _ => Err(Json::string("decode error"))
  }
  report(
    "int64_from_number",
    match int64_from_number {
      Ok(value) => Json::string(value.to_string())
      Err(err) => err
    },
  )
  let int64_from_string : Result[Int64, Json] = try {
    Ok(@json.from_json(@json.parse("\"42\"")))
  } catch {
    _ => Err(Json::string("decode error"))
  }
  report(
    "int64_from_string",
    match int64_from_string {
      Ok(value) => Json::string(value.to_string())
      Err(err) => err
    },
  )
  // 5. extra keys
  let extra : Result[ProbeModel, Json] = try {
    let v : ProbeModel = @json.from_json(
      @json.parse("{\"required_name\":\"a\",\"unknown\":1}"),
    )
    Ok(v)
  } catch {
    _ => Err(Json::string("decode error"))
  }
  report(
    "extra_key",
    match extra {
      Ok(_) => Json::string("ignored")
      Err(err) => err
    },
  )
}
