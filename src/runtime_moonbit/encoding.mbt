///|
/// Parameter serialization helpers for the SDK runtime.
///
/// Implements the V1 serialization profile:
/// - path: simple style (scalar, array)
/// - query: form style (scalar, array, explode/joined)
/// - header: simple style (scalar, array)
/// - percent encoding

///|
fn is_unreserved_byte(byte : Byte) -> Bool {
  let n = byte.to_int()
  (n >= 0x41 && n <= 0x5A) || // A-Z
  (n >= 0x61 && n <= 0x7A) || // a-z
  (n >= 0x30 && n <= 0x39) || // 0-9
  n == 0x2D || // -
  n == 0x2E || // .
  n == 0x5F || // _
  n == 0x7E // ~
}

///|
/// Percent-encode a string value according to RFC 3986.
/// Reserved characters and non-ASCII bytes are encoded as %XX.
/// Unreserved characters (A-Z, a-z, 0-9, -, ., _, ~) pass through.
pub fn percent_encode(value : String) -> String {
  let out = StringBuilder(size_hint=value.length() * 3)
  for byte in @utf8.encode(value) {
    if is_unreserved_byte(byte) {
      out.write_char(byte.to_char())
    } else {
      out.write_char('%')
      let hex = byte.to_hex().to_upper()
      if hex.length() == 1 {
        out.write_char('0')
      }
      out.write_string(hex)
    }
  }
  out.to_string()
}

///|
/// Encode a single value for path insertion (simple style).
pub fn encode_path_value(value : String) -> String {
  percent_encode(value)
}

///|
/// Encode multiple values for path insertion (simple style, array).
pub fn encode_path_array(values : Array[String]) -> String {
  let out = StringBuilder()
  let mut first = true
  for v in values {
    if first {
      first = false
    } else {
      out.write_char(',')
    }
    out.write_string(percent_encode(v))
  }
  out.to_string()
}

///|
/// Encode a query parameter key-value pair (form style).
/// Both key and value are percent-encoded.
pub fn encode_query_pair(name : String, value : String) -> (String, String) {
  (percent_encode(name), percent_encode(value))
}

///|
/// Encode a query array parameter with explode=true (form style).
pub fn encode_query_array_explode(
  name : String,
  values : Array[String],
) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  let encoded_name = percent_encode(name)
  for v in values {
    out.push((encoded_name, percent_encode(v)))
  }
  out
}

///|
/// Encode a query array parameter with explode=false (form style).
pub fn encode_query_array_joined(
  name : String,
  values : Array[String],
) -> (String, String) {
  let encoded_name = percent_encode(name)
  let encoded_values = StringBuilder()
  let mut first = true
  for v in values {
    if first {
      first = false
    } else {
      encoded_values.write_char(',')
    }
    encoded_values.write_string(percent_encode(v))
  }
  (encoded_name, encoded_values.to_string())
}

///|
/// Encode a header value (simple style).
/// Simple style passes through as-is.
pub fn encode_header_value(value : String) -> String {
  value
}

///|
/// Encode header array values (simple style).
/// Values are comma-separated.
pub fn encode_header_array(values : Array[String]) -> String {
  let out = StringBuilder()
  let mut first = true
  for v in values {
    if first {
      first = false
    } else {
      out.write_char(',')
    }
    out.write_string(v)
  }
  out.to_string()
}

///|
/// Build a query string from encoded key-value pairs.
/// Returns the query string without the leading ?.
pub fn build_query_string(params : Array[(String, String)]) -> String {
  let out = StringBuilder()
  let mut first = true
  for pair in params {
    let (key, value) = pair
    if first {
      first = false
    } else {
      out.write_char('&')
    }
    out.write_string(key)
    out.write_char('=')
    out.write_string(value)
  }
  out.to_string()
}

///|
/// Interpolate path parameters into a path template.
/// Replaces {paramName} placeholders with encoded values from the map.
pub fn interpolate_path(path : String, params : Map[String, String]) -> String {
  let out = StringBuilder()
  let mut i = 0
  let bytes = @utf8.encode(path)
  while i < bytes.length() {
    if bytes[i].to_int() == 0x7B { // '{'
      let mut end = i + 1
      while end < bytes.length() && bytes[end].to_int() != 0x7D {
        end = end + 1
      }
      if end < bytes.length() {
        let name_view = bytes[i + 1:end]
        let name = name_view.to_string()
        match params.get(name) {
          Some(value) => {
            out.write_string(value)
            i = end + 1
          }
          None => {
            out.write_char('{')
            out.write_string(name)
            out.write_char('}')
            i = end + 1
          }
        }
      } else {
        out.write_char('{')
        i = i + 1
      }
    } else {
      out.write_char(bytes[i].to_char())
      i = i + 1
    }
  }
  out.to_string()
}
