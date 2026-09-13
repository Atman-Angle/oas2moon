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
  "oneOf", "anyOf", "allOf", "discriminator", "xml", "not", "callbacks", "webhooks",
]

///|
/// Keywords that MoonContract parses into fields this frontend does not carry
/// into the Frontend Model. They are recorded so that support validation can
/// report them as explicit warnings instead of silently dropping them.
let ignored_keywords : Array[String] = [
  "default", "example", "examples", "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum",
  "minLength", "maxLength", "pattern", "minItems", "maxItems", "uniqueItems", "readOnly",
  "writeOnly", "deprecated", "additionalProperties",
]

///|
/// Scalar rendering of a keyword value, when it has one.
fn keyword_value(keyword : String, json : Json) -> Json {
  if keyword == "additionalProperties" {
    match json {
      Object(_) => Json::string("schema")
      _ => Json::null()
    }
  } else {
    match json {
      String(text) => Json::string(text)
      True => Json::string("true")
      False => Json::string("false")
      _ => Json::null()
    }
  }
}

///|
/// RFC 6901 JSON Pointer token escaping.
fn pointer_escape(value : String) -> String {
  value.replace_all(old="~", new="~0").replace_all(old="/", new="~1")
}

///|
/// Scan only schema-bearing nodes and known operation-level feature slots.
///
/// This is intentionally a bounded sidecar, not a second OpenAPI parser. In
/// particular it never descends into `example`, `default`, `description`, or
/// arbitrary extension values. A user may therefore legitimately use a key
/// such as `oneOf` inside example data without producing an unsupported-schema
/// diagnostic.
fn scan_schema(
  node : Json,
  pointer : String,
  out : Array[Json],
  keywords : Array[String],
) -> Unit {
  match node {
    Object(entries) => {
      for keyword in keywords {
        match entries.get(keyword) {
          Some(value) => {
            let record = if keyword == "additionalProperties" {
              match value {
                Object(_) => true
                _ => false
              }
            } else {
              true
            }
            if record {
              out.push(
                Json::object(
                  Map([
                    ("pointer", Json::string(pointer + "/" + keyword)),
                    ("keyword", Json::string(keyword)),
                    ("value", keyword_value(keyword, value)),
                  ]),
                ),
              )
            }
          }
          None => ()
        }
      }
      match entries.get("properties") {
        Some(properties) =>
          match properties {
            Object(children) =>
              for name, child in children {
                scan_schema(
                  child,
                  pointer + "/properties/" + pointer_escape(name),
                  out,
                  keywords,
                )
              }
            _ => ()
          }
        None => ()
      }
      match entries.get("items") {
        Some(items) => scan_schema(items, pointer + "/items", out, keywords)
        None => ()
      }
      match entries.get("additionalProperties") {
        Some(value) =>
          match value {
            Object(_) =>
              scan_schema(
                value,
                pointer + "/additionalProperties",
                out,
                keywords,
              )
            _ => ()
          }
        None => ()
      }
    }
    _ => ()
  }
}

///|
fn scan_content(
  node : Json,
  pointer : String,
  out : Array[Json],
  keywords : Array[String],
) -> Unit {
  match node {
    Object(entries) =>
      match entries.get("schema") {
        Some(schema) => scan_schema(schema, pointer + "/schema", out, keywords)
        None => ()
      }
    _ => ()
  }
}

///|
/// Scan schemas attached to a parameter array. This is shared by operation
/// parameters and path-item inherited parameters; the latter are easy to miss
/// because mooncontract merges them into each operation.
fn scan_parameters(
  node : Json,
  pointer : String,
  out : Array[Json],
  keywords : Array[String],
) -> Unit {
  match node {
    Array(values) =>
      for index, parameter in values {
        match parameter {
          Object(parameter_entries) =>
            match parameter_entries.get("schema") {
              Some(schema) =>
                scan_schema(
                  schema,
                  pointer + "/" + index.to_string() + "/schema",
                  out,
                  keywords,
                )
              None => ()
            }
          _ => ()
        }
      }
    _ => ()
  }
}

///|
fn scan_operation(
  node : Json,
  pointer : String,
  out : Array[Json],
  keywords : Array[String],
) -> Unit {
  match node {
    Object(entries) => {
      for keyword in ["callbacks", "webhooks"] {
        match entries.get(keyword) {
          Some(value) => {
            let record = if keyword == "additionalProperties" {
              match value {
                Object(_) => true
                _ => false
              }
            } else {
              true
            }
            if record {
              out.push(
                Json::object(
                  Map([
                    ("pointer", Json::string(pointer + "/" + keyword)),
                    ("keyword", Json::string(keyword)),
                    ("value", keyword_value(keyword, value)),
                  ]),
                ),
              )
            }
          }
          None => ()
        }
      }
      match entries.get("parameters") {
        Some(parameters) =>
          scan_parameters(parameters, pointer + "/parameters", out, keywords)
        None => ()
      }
      match entries.get("requestBody") {
        Some(body) =>
          match body {
            Object(body_entries) =>
              match body_entries.get("content") {
                Some(content) =>
                  match content {
                    Object(media_types) =>
                      for media_type, value in media_types {
                        scan_content(
                          value,
                          pointer +
                          "/requestBody/content/" +
                          pointer_escape(media_type),
                          out,
                          keywords,
                        )
                      }
                    _ => ()
                  }
                None => ()
              }
            _ => ()
          }
        None => ()
      }
      match entries.get("responses") {
        Some(responses) =>
          match responses {
            Object(response_map) =>
              for status, response in response_map {
                match response {
                  Object(response_entries) =>
                    match response_entries.get("content") {
                      Some(content) =>
                        match content {
                          Object(media_types) =>
                            for media_type, value in media_types {
                              scan_content(
                                value,
                                pointer +
                                "/responses/" +
                                pointer_escape(status) +
                                "/content/" +
                                pointer_escape(media_type),
                                out,
                                keywords,
                              )
                            }
                          _ => ()
                        }
                      None => ()
                    }
                  _ => ()
                }
              }
            _ => ()
          }
        None => ()
      }
    }
    _ => ()
  }
}

///|
fn raw_keyword_findings(root : Json, keywords : Array[String]) -> Json {
  let out : Array[Json] = []
  match raw_get(root, "components") {
    Object(components) =>
      match components.get("schemas") {
        Some(schemas) =>
          match schemas {
            Object(entries) =>
              for name, schema in entries {
                scan_schema(
                  schema,
                  "#/components/schemas/" + pointer_escape(name),
                  out,
                  keywords,
                )
              }
            _ => ()
          }
        None => ()
      }
    _ => ()
  }
  match raw_get(root, "paths") {
    Object(paths) =>
      for path, path_item in paths {
        match path_item {
          Object(methods) => {
            match methods.get("parameters") {
              Some(parameters) =>
                scan_parameters(
                  parameters,
                  "#/paths/" + pointer_escape(path) + "/parameters",
                  out,
                  keywords,
                )
              None => ()
            }
            for verb, operation in methods {
              if [
                  "get", "post", "put", "patch", "delete", "head", "options", "trace",
                ].contains(verb) {
                scan_operation(
                  operation,
                  "#/paths/" + pointer_escape(path) + "/" + pointer_escape(verb),
                  out,
                  keywords,
                )
              }
            }
          }
          _ => ()
        }
      }
    _ => ()
  }
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
  let path_parameters = raw_array(
    raw_get(raw_get(raw_get(root, "paths"), path), "parameters"),
  )
  let operation_parameters = raw_array(
    raw_get(
      raw_get(raw_get(raw_get(root, "paths"), path), http_method.to_lower()),
      "parameters",
    ),
  )
  let parameter = if index < path_parameters.length() {
    match path_parameters.get(index) {
      Some(value) => value
      None => Json::null()
    }
  } else {
    match operation_parameters.get(index - path_parameters.length()) {
      Some(value) => value
      None => Json::null()
    }
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
