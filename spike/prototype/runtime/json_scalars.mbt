///|
/// Decode a JSON value into `Int64` following OpenAPI `integer/int64` wire
/// semantics.
///
/// `moonbitlang/core/json` maps `Int64` onto a JSON *string* in both
/// directions, which does not match how OpenAPI `integer/int64` values appear
/// on the wire. This helper accepts the regular JSON number form (preferring
/// the exact source text recorded by the parser) and, for interoperability,
/// the string form as well.
pub fn json_to_int64(
  json : Json,
  path : @json.JsonPath,
) -> Int64 raise @json.JsonDecodeError {
  match json {
    Number(n, repr~) =>
      match repr {
        Some(text) => parse_int64_text(text, path)
        None => decode_integral_double(n, path)
      }
    String(text) => parse_int64_text(text, path)
    _ =>
      raise @json.JsonDecodeError((path, "expected an integer (JSON number)"))
  }
}

///|
fn parse_int64_text(
  text : String,
  path : @json.JsonPath,
) -> Int64 raise @json.JsonDecodeError {
  @string.parse_int64(text) catch {
    _ =>
      raise @json.JsonDecodeError((path, "expected a decimal integer literal"))
  }
}

///|
fn decode_integral_double(
  n : Double,
  path : @json.JsonPath,
) -> Int64 raise @json.JsonDecodeError {
  if n.is_nan() || n.is_inf() {
    raise @json.JsonDecodeError(
      (path, "expected an integer, found a non-finite number"),
    )
  }
  if n != n.trunc() {
    raise @json.JsonDecodeError(
      (path, "expected an integer, found a fractional number"),
    )
  }
  let max_bound = 9223372036854775807L.to_double()
  let min_bound = (-9223372036854775808L).to_double()
  if n > max_bound || n < min_bound {
    raise @json.JsonDecodeError(
      (path, "integer value is out of range for Int64"),
    )
  }
  n.to_int64()
}

///|
/// Encode an `Int64` as a JSON number, keeping the exact decimal text so that
/// values outside the exactly representable `Double` range stay intact.
pub fn int64_to_json(value : Int64) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}
