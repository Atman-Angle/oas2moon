///|
/// Raw feature scan for the support-validation stage.
///
/// `Han-Wentao/mooncontract` currently drops several OpenAPI keywords without a
/// diagnostic (`oneOf`, `anyOf`, `allOf`, `discriminator`, `xml`, `not`,
/// `callbacks`, `webhooks`). Dropping them silently would let the generator emit
/// wire behavior that the contract does not describe, so the frontend records
/// their locations in the raw document instead of re-implementing a parser.
///
/// The scan records *locations only*. Classification into
/// supported/fallback/unsupported belongs to the generator's support validator.
let unsupported_keywords : Array[String] = [
  "oneOf",
  "anyOf",
  "allOf",
  "discriminator",
  "xml",
  "not",
  "callbacks",
  "webhooks",
]

///|
/// Keywords that MoonContract parses into fields this frontend does not carry
/// into the Frontend Model. They are recorded so that support validation can
/// report them as explicit warnings instead of silently dropping them.
let ignored_keywords : Array[String] = [
  "default",
  "example",
  "examples",
  "minimum",
  "maximum",
  "exclusiveMinimum",
  "exclusiveMaximum",
  "minLength",
  "maxLength",
  "pattern",
  "minItems",
  "maxItems",
  "uniqueItems",
  "readOnly",
  "writeOnly",
  "deprecated",
]

///|
/// Scalar rendering of a keyword value, when it has one.
fn keyword_value(json : Json) -> Json {
  match json {
    String(text) => Json::string(text)
    True => Json::string("true")
    False => Json::string("false")
    _ => Json::null()
  }
}

///|
/// Walk the raw document and record every occurrence of a keyword this project
/// does not support yet.
///
/// `keys_are_names` is true while walking a `properties` map, where the child
/// keys are property names rather than OpenAPI keywords. Without that guard a
/// schema property literally named `xml` would be reported as unsupported.
fn scan_keywords(
  node : Json,
  pointer : String,
  keys_are_names : Bool,
  keywords : Array[String],
  out : Array[Json],
) -> Unit {
  match node {
    Object(entries) =>
      for key, value in entries {
        if !keys_are_names && keywords.contains(key) {
          out.push(
            Json::object(
              Map([
                ("pointer", Json::string(pointer + "/" + key)),
                ("keyword", Json::string(key)),
                ("value", keyword_value(value)),
              ]),
            ),
          )
        }
        scan_keywords(value, pointer + "/" + key, key == "properties", keywords, out)
      }
    Array(items) =>
      for index, item in items {
        scan_keywords(item, pointer + "/" + index.to_string(), false, keywords, out)
      }
    _ => ()
  }
}

///|
/// Every location of the given keywords, in document order.
fn raw_keyword_findings(root : Json, keywords : Array[String]) -> Json {
  let out : Array[Json] = []
  scan_keywords(root, "#", false, keywords, out)
  Json::array(out)
}

///|
/// The recorded unsupported-keyword locations, in document order.
fn raw_unsupported_issues(root : Json) -> Json {
  raw_keyword_findings(root, unsupported_keywords)
}

///|
/// Keywords that are dropped by the frontend, recorded for reporting only.
fn raw_ignored_issues(root : Json) -> Json {
  raw_keyword_findings(root, ignored_keywords)
}

///|
/// Raw serialization metadata for one operation parameter.
///
/// OpenAPI defaults differ per location, so the raw `style`/`explode` are
/// carried through as declared rather than applied here.
fn raw_parameter_serialization(
  root : Json,
  path : String,
  http_method : String,
  index : Int,
) -> (Json, Json) {
  let parameters = raw_array(
    raw_get(
      raw_get(raw_get(raw_get(root, "paths"), path), http_method.to_lower()),
      "parameters",
    ),
  )
  let parameter = match parameters.get(index) {
    Some(value) => value
    None => Json::null()
  }
  let style = match raw_as_string(raw_get(parameter, "style")) {
    Some(text) => Json::string(text)
    None => Json::null()
  }
  let explode = match raw_boolean(raw_get(parameter, "explode")) {
    Some(value) => Json::boolean(value)
    None => Json::null()
  }
  (style, explode)
}
