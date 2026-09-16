///|
/// Naming subsystem.
///
/// Converts OpenAPI identifiers into stable MoonBit identifiers.

///|
/// MoonBit reserved keywords plus generated helper names.
let reserved : Map[String, Bool] = {
  let m : Map[String, Bool] = Map([])
  let words = [
    "as", "async", "await", "break", "catch", "const", "continue", "derive", "else",
    "enum", "false", "fn", "for", "guard", "if", "impl", "import", "in", "init",
    "is", "let", "loop", "match", "mut", "noraise", "not", "null", "op", "or", "override",
    "package", "priv", "pub", "pure", "raise", "readonly", "ref", "return", "self",
    "static", "struct", "suberror", "test", "trait", "true", "try", "type", "var",
    "while", "with", "all", "client", "config", "from_json", "json", "new", "open",
    "to_json", "to_wire",
  ]
  for kw in words {
    m[kw] = true
  }
  m
}

///|
/// Get first char of a string.
fn first_char(s : String) -> Char {
  for ch in s {
    return ch
  }
  ' '
}

///|
/// Build a string from an array of words joined by separator.
fn join_words(parts : Array[String], sep : String) -> String {
  let mut result = ""
  for i, part in parts {
    if i > 0 {
      result = result + sep
    }
    result = result + part
  }
  result
}

///|
/// Check if a character is alphanumeric.
fn is_alnum(ch : Char) -> Bool {
  (ch >= '0' && ch <= '9') ||
  (ch >= 'A' && ch <= 'Z') ||
  (ch >= 'a' && ch <= 'z')
}

///|
/// Check if a character is uppercase.
fn is_upper(ch : Char) -> Bool {
  ch >= 'A' && ch <= 'Z'
}

///|
/// Check if a character is a digit.
fn is_digit(ch : Char) -> Bool {
  ch >= '0' && ch <= '9'
}

///|
/// Convert a Char to uppercase.
fn to_upper_char(ch : Char) -> Char {
  if ch >= 'a' && ch <= 'z' {
    Int::unsafe_to_char(ch.to_int() - 32)
  } else {
    ch
  }
}

///|
/// Convert a string to its uppercase first char version.
fn first_upper(s : String) -> String {
  if s.length() == 0 {
    return s
  }
  let first = first_char(s)
  let upper = to_upper_char(first)
  let buf = StringBuilder()
  buf.write_char(upper)
  let mut passed_first = false
  for ch in s {
    if !passed_first {
      passed_first = true
    } else {
      buf.write_char(ch)
    }
  }
  buf.to_string()
}

///|
/// Convert a string to lowercase using StringBuilder.
fn to_lower_str(s : String) -> String {
  let buf = StringBuilder()
  for ch in s {
    if ch >= 'A' && ch <= 'Z' {
      buf.write_char(Int::unsafe_to_char(ch.to_int() + 32))
    } else {
      buf.write_char(ch)
    }
  }
  buf.to_string()
}

///|
/// Split a camelCase/PascalCase/kebab-case name into lowercase words.
pub fn words(name : String) -> Array[String] {
  let out : Array[String] = []
  let mut buf = StringBuilder()
  let mut prev_lower = false
  for ch in name {
    if is_alnum(ch) {
      if prev_lower && is_upper(ch) {
        let word = buf.to_string()
        if word.length() > 0 {
          out.push(to_lower_str(word))
        }
        buf = StringBuilder()
      }
      buf.write_char(ch)
      prev_lower = !is_upper(ch) && !is_digit(ch)
    } else {
      let word = buf.to_string()
      if word.length() > 0 {
        out.push(to_lower_str(word))
      }
      buf = StringBuilder()
      prev_lower = false
    }
  }
  let word = buf.to_string()
  if word.length() > 0 {
    out.push(to_lower_str(word))
  }
  if out.length() == 0 {
    out.push("value")
  }
  out
}

///|
/// Convert to snake_case.
pub fn snake(name : String) -> String {
  let parts = words(name)
  let candidate = join_words(parts, "_")
  if reserved.contains(candidate) {
    candidate + "_"
  } else {
    candidate
  }
}

///|
/// Convert to PascalCase.
pub fn pascal(name : String) -> String {
  let parts = words(name)
  let mut candidate = ""
  for part in parts {
    if part.length() > 0 {
      candidate = candidate + first_upper(part)
    }
  }
  if reserved.contains(candidate) {
    candidate + "Value"
  } else {
    candidate
  }
}

///|
/// Return `base`, or the first free `base_N`.
pub fn unique(base : String, taken : Map[String, Bool]) -> String {
  if !taken.contains(base) {
    taken[base] = true
    return base
  }
  let mut i = 2
  let mut candidate = base + "_" + i.to_string()
  while taken.contains(candidate) {
    i = i + 1
    candidate = base + "_" + i.to_string()
  }
  taken[candidate] = true
  candidate
}

///|
/// OperationID to snake_case function name.
pub fn operation_fn_name(operation_id : String) -> String {
  snake(operation_id)
}
