///|
/// Whether an ASCII byte is safe to emit unescaped in a URL component.
fn is_unreserved(code : Int) -> Bool {
  (code >= 48 && code <= 57) ||
  (code >= 65 && code <= 90) ||
  (code >= 97 && code <= 122) ||
  code == 45 ||
  code == 46 ||
  code == 95 ||
  code == 126
}

///|
/// Render one hexadecimal digit as an upper-case ASCII character.
fn hex_digit(value : Int) -> Char {
  if value < 10 {
    (48 + value).unsafe_to_char()
  } else {
    (55 + value).unsafe_to_char()
  }
}

///|
/// Percent-encode one string. The result is built from `Char` values rather
/// than from a byte buffer: byte-array to string conversion is not UTF-8
/// preserving on this toolchain, see `SPIKE_REPORT.md`.
fn percent_encode(value : String, space_as_plus : Bool) -> String {
  let out = StringBuilder::new()
  for byte in @utf8.encode(value).iter() {
    let code = byte.to_int()
    if is_unreserved(code) {
      out.write_char(code.unsafe_to_char())
    } else if space_as_plus && code == 32 {
      out.write_char('+')
    } else {
      out.write_char('%')
      out.write_char(hex_digit(code / 16))
      out.write_char(hex_digit(code % 16))
    }
  }
  out.to_string()
}

///|
/// Percent-encode one path segment (RFC 3986 unreserved set only).
pub fn encode_path_segment(value : String) -> String {
  percent_encode(value, false)
}

///|
/// Percent-encode one `application/x-www-form-urlencoded` query component.
pub fn encode_query_component(value : String) -> String {
  percent_encode(value, true)
}

///|
/// Render the query string, including the leading `?` when non-empty.
pub fn render_query(pairs : Array[(String, String)]) -> String {
  if pairs.length() == 0 {
    return ""
  }
  let parts : Array[String] = []
  for pair in pairs {
    let (name, value) = pair
    parts.push(
      encode_query_component(name) + "=" + encode_query_component(value),
    )
  }
  "?" + parts.join("&")
}
