///|
fn validate_support(root : Json) -> Array[Diagnostic] {
  let out : Array[Diagnostic] = []
  let issues = arr(get(root, "issues"))
  let ordered : Map[String, Json] = Map([])
  let keys : Array[String] = []
  for issue in issues {
    let key = text(get(issue, "pointer"))
    ordered[key] = issue
    keys.push(key)
  }
  for key in sorted_strings(keys) {
    let issue = ordered[key]
    let keyword = text(get(issue, "keyword"))
    let code = if keyword == "mediaType" {
      "unsupported.media_type"
    } else if keyword == "externalRef" || keyword == "componentRef" {
      "unsupported.ref"
    } else {
      "unsupported.keyword"
    }
    let message = if keyword == "componentRef" {
      "Component reference must resolve to a local, acyclic target: " +
      text(get(issue, "value"))
    } else {
      "Unsupported OpenAPI feature: " + keyword
    }
    out.push(error_diagnostic(code, key, message))
  }
  for op in arr(get(root, "operations")) {
    let http_method = text(get(op, "method"))
    let operation_pointer = "#/paths/" +
      text(get(op, "path"))
      .replace(old="~", new="~0")
      .replace(old="/", new="~1") +
      "/" +
      http_method.to_lower()
    if !["GET", "POST", "PUT", "PATCH", "DELETE"].contains(http_method) {
      out.push(
        error_diagnostic(
          "unsupported.method",
          operation_pointer,
          "Unsupported HTTP method: " + http_method,
        ),
      )
    }
    let mut has_success = false
    let mut default_pointer = ""
    for response in arr(get(op, "responses")) {
      let status = text(get(response, "status"))
      if is_three_digit_status(status) && status >= "200" && status < "300" {
        has_success = true
      }
      if status == "default" {
        default_pointer = operation_pointer + "/responses/default"
      } else if !is_three_digit_status(status) ||
        status < "100" ||
        status > "599" {
        out.push(
          error_diagnostic(
            "unsupported.response_status",
            operation_pointer + "/responses/" + status,
            "Response status ranges and default responses are unsupported",
          ),
        )
      }
    }
    if default_pointer != "" && !has_success {
      out.push(
        error_diagnostic(
          "unsupported.response_status", default_pointer, "A default response is unsupported without an explicit 2xx response",
        ),
      )
    }
    for i, p in arr(get(op, "parameters")) {
      let loc = text(get(p, "in"))
      let style = parse_style(get(p, "style"), loc)
      if (loc == "query" && style != Form) ||
        (loc != "query" && style != Simple) ||
        !["query", "path", "header"].contains(loc) {
        out.push(
          error_diagnostic(
            "unsupported.serialization",
            "#/paths/" +
            text(get(op, "path"))
            .replace(old="~", new="~0")
            .replace(old="/", new="~1") +
            "/" +
            text(get(op, "method")).to_lower() +
            "/parameters/" +
            i.to_string(),
            "Unsupported parameter location or serialization style",
          ),
        )
      }
    }
  }
  validate_security_support(root, out)
  validate_reference_support(root, out)
  validate_enum_support(root, out)
  // Only component roots become named models. Other object schemas retain JSON
  // wire semantics with an explicit warning instead of pretending to be strings.
  let schemas = obj(get(root, "schemas"))
  let schema_names : Array[String] = []
  for name, _ in schemas {
    schema_names.push(name)
  }
  for name in sorted_strings(schema_names) {
    let schema = schemas[name]
    warn_inline_objects(
      schema,
      "#/components/schemas/" +
      name.replace(old="~", new="~0").replace(old="/", new="~1"),
      true,
      out,
    )
  }
  for op in arr(get(root, "operations")) {
    let base = "#/paths/" +
      text(get(op, "path"))
      .replace(old="~", new="~0")
      .replace(old="/", new="~1") +
      "/" +
      text(get(op, "method")).to_lower()
    for r in arr(get(op, "responses")) {
      warn_inline_objects(
        get(r, "schema"),
        base +
        "/responses/" +
        text(get(r, "status")) +
        "/content/application~1json/schema",
        false,
        out,
      )
    }
    warn_inline_objects(
      get(get(op, "requestBody"), "schema"),
      base + "/requestBody/content/application~1json/schema",
      false,
      out,
    )
  }
  out
}

///|
fn is_three_digit_status(status : String) -> Bool {
  if status.length() != 3 {
    return false
  }
  for ch in status {
    let value = ch.to_int()
    if value < 48 || value > 57 {
      return false
    }
  }
  true
}

///|
fn validate_security_support(root : Json, out : Array[Diagnostic]) -> Unit {
  let schemes = obj(get(root, "securitySchemes"))
  for op in arr(get(root, "operations")) {
    let path = text(get(op, "path"))
      .replace(old="~", new="~0")
      .replace(old="/", new="~1")
    let http_method = text(get(op, "method")).to_lower()
    for alternative in arr(get(op, "security")) {
      let authorization_schemes : Map[String, Bool] = Map([])
      let mut has_authorization_header_api_key = false
      let api_key_count = {
        let mut count = 0
        for name_json in arr(alternative) {
          let scheme = match schemes.get(text(name_json)) {
            Some(value) => value
            None => Json::null()
          }
          let kind = text(get(scheme, "type"))
          let auth_kind = text(get(scheme, "scheme")).to_lower()
          if kind == "http" && (auth_kind == "bearer" || auth_kind == "basic") {
            authorization_schemes[auth_kind] = true
          }
          if kind == "apiKey" {
            count = count + 1
            if text(get(scheme, "in")) == "header" &&
              text(get(scheme, "name")).to_lower() == "authorization" {
              has_authorization_header_api_key = true
            }
          }
        }
        count
      }
      if authorization_schemes.contains("bearer") &&
        authorization_schemes.contains("basic") {
        out.push(
          error_diagnostic(
            "unsupported.auth",
            "#/paths/" + path + "/" + http_method + "/security",
            "A single HTTP Authorization header cannot satisfy bearer and basic together",
          ),
        )
      }
      if (
          authorization_schemes.contains("bearer") ||
          authorization_schemes.contains("basic")
        ) &&
        has_authorization_header_api_key {
        out.push(
          error_diagnostic(
            "unsupported.auth",
            "#/paths/" + path + "/" + http_method + "/security",
            "An Authorization API key cannot be combined with HTTP authentication",
          ),
        )
      }
      if api_key_count > 1 {
        out.push(
          error_diagnostic(
            "unsupported.auth",
            "#/paths/" + path + "/" + http_method + "/security",
            "Multiple API key schemes in one AND requirement are unsupported",
          ),
        )
      }
      for name_json in arr(alternative) {
        let name = text(name_json)
        match schemes.get(name) {
          None =>
            out.push(
              error_diagnostic(
                "unsupported.auth",
                "#/paths/" + path + "/" + http_method + "/security/" + name,
                "Security requirement references an undeclared scheme: " + name,
              ),
            )
          Some(scheme) => {
            let kind = text(get(scheme, "type"))
            let http_scheme = text(get(scheme, "scheme")).to_lower()
            let location = text(get(scheme, "in"))
            let supported = (
                kind == "http" &&
                (http_scheme == "bearer" || http_scheme == "basic")
              ) ||
              (
                kind == "apiKey" &&
                (location == "header" || location == "query")
              )
            if !supported {
              out.push(
                error_diagnostic(
                  "unsupported.auth",
                  "#/components/securitySchemes/" + name,
                  "Unsupported security scheme: " + name,
                ),
              )
            }
          }
        }
      }
    }
  }
}

///|
/// Validate local component references after the parser has normalized them.
/// Missing and cyclic references cannot be allowed to reach codegen because
/// the codegen reader intentionally treats them as fatal IR errors.
fn validate_reference_support(root : Json, out : Array[Diagnostic]) -> Unit {
  let schemas = obj(get(root, "schemas"))
  let known : Map[String, Bool] = Map([])
  for name, _schema in schemas {
    known["#/components/schemas/" +
    name.replace(old="~", new="~0").replace(old="/", new="~1")] = true
  }
  let graph : Map[String, Array[String]] = Map([])
  for name, schema in schemas {
    let refs : Array[String] = []
    collect_schema_refs(
      schema,
      "#/components/schemas/" + name,
      known,
      refs,
      out,
    )
    graph["#/components/schemas/" +
    name.replace(old="~", new="~0").replace(old="/", new="~1")] = refs
  }
  for op in arr(get(root, "operations")) {
    let path_seg = text(get(op, "path"))
      .replace(old="~", new="~0")
      .replace(old="/", new="~1")
    for parameter in arr(get(op, "parameters")) {
      collect_schema_refs(
        get(parameter, "schema"),
        "#/paths/" + path_seg + "/parameters",
        known,
        [],
        out,
      )
    }
    let body = get(get(op, "requestBody"), "schema")
    collect_schema_refs(
      body,
      "#/paths/" + path_seg + "/requestBody",
      known,
      [],
      out,
    )
    for response in arr(get(op, "responses")) {
      collect_schema_refs(
        get(response, "schema"),
        "#/paths/" + path_seg + "/responses/" + text(get(response, "status")),
        known,
        [],
        out,
      )
    }
  }
  let visiting : Map[String, Bool] = Map([])
  let done : Map[String, Bool] = Map([])
  let reported : Map[String, Bool] = Map([])
  for name, _schema in schemas {
    let identity = "#/components/schemas/" +
      name.replace(old="~", new="~0").replace(old="/", new="~1")
    if graph_has_cycle(identity, graph, visiting, done) &&
      !reported.contains(identity) {
      reported[identity] = true
      out.push(
        error_diagnostic(
          "unsupported.ref", identity, "Cyclic schema reference is unsupported",
        ),
      )
    }
  }
}

///|
fn collect_schema_refs(
  schema : Json,
  pointer : String,
  known : Map[String, Bool],
  refs : Array[String],
  out : Array[Diagnostic],
) -> Unit {
  match schema {
    Object(fields) => {
      match fields.get("ref") {
        Some(String(ref_path)) =>
          if ref_path.has_prefix("#/components/schemas/") {
            if !known.contains(ref_path) {
              out.push(
                error_diagnostic(
                  "unsupported.ref",
                  pointer + "/ref",
                  "Missing local schema reference: " + ref_path,
                ),
              )
            } else {
              refs.push(ref_path)
            }
          }
        _ => ()
      }
      match fields.get("properties") {
        Some(Object(properties)) =>
          for name, child in properties {
            collect_schema_refs(
              child,
              pointer + "/properties/" + name,
              known,
              refs,
              out,
            )
          }
        _ => ()
      }
      match fields.get("items") {
        Some(child) =>
          collect_schema_refs(child, pointer + "/items", known, refs, out)
        None => ()
      }
    }
    _ => ()
  }
}

///|
fn graph_has_cycle(
  name : String,
  graph : Map[String, Array[String]],
  visiting : Map[String, Bool],
  done : Map[String, Bool],
) -> Bool {
  match done.get(name) {
    Some(true) => return false
    _ => ()
  }
  match visiting.get(name) {
    Some(true) => return true
    _ => ()
  }
  visiting[name] = true
  let neighbors = graph.get(name).unwrap_or([])
  for next in neighbors {
    if graph_has_cycle(next, graph, visiting, done) {
      visiting[name] = false
      return true
    }
  }
  visiting[name] = false
  done[name] = true
  false
}

///|
/// Only string enums with unique wire values map to a MoonBit enum. A non-string
/// enum would lower to an empty struct and duplicate wires would emit duplicate
/// match arms, so both must stop generation with a deterministic diagnostic
/// instead of silently producing a wrong or uncompilable model.
fn validate_enum_support(root : Json, out : Array[Diagnostic]) -> Unit {
  let schemas = obj(get(root, "schemas"))
  let names : Array[String] = []
  for name, _ in schemas {
    names.push(name)
  }
  for name in sorted_strings(names) {
    validate_schema_enum(
      schemas[name],
      "#/components/schemas/" +
      name.replace(old="~", new="~0").replace(old="/", new="~1"),
      out,
    )
  }
  for op in arr(get(root, "operations")) {
    let base = "#/paths/" +
      text(get(op, "path"))
      .replace(old="~", new="~0")
      .replace(old="/", new="~1") +
      "/" +
      text(get(op, "method")).to_lower()
    for index, param in arr(get(op, "parameters")) {
      validate_schema_enum(
        get(param, "schema"),
        base + "/parameters/" + index.to_string() + "/schema",
        out,
      )
    }
    validate_schema_enum(
      get(get(op, "requestBody"), "schema"),
      base + "/requestBody/content/application~1json/schema",
      out,
    )
    for response in arr(get(op, "responses")) {
      validate_schema_enum(
        get(response, "schema"),
        base +
        "/responses/" +
        text(get(response, "status")) +
        "/content/application~1json/schema",
        out,
      )
    }
  }
}

///|
fn validate_schema_enum(
  schema : Json,
  pointer : String,
  out : Array[Diagnostic],
) -> Unit {
  let values = arr(get(schema, "enum"))
  if !values.is_empty() {
    let enum_pointer = pointer + "/enum"
    if text(get(schema, "kind")) != "string" {
      out.push(
        error_diagnostic(
          "unsupported.enum", enum_pointer, "Non-string enum is unsupported; only string enums map to a MoonBit enum",
        ),
      )
    } else {
      let seen : Map[String, Bool] = Map([])
      for value in values {
        match value {
          String(wire) =>
            if seen.contains(wire) {
              out.push(
                error_diagnostic(
                  "unsupported.enum",
                  enum_pointer,
                  "Duplicate enum value: " + wire,
                ),
              )
            } else {
              seen[wire] = true
            }
          _ =>
            out.push(
              error_diagnostic(
                "unsupported.enum", enum_pointer, "Enum value is not a string",
              ),
            )
        }
      }
    }
  }
  for name, child in obj(get(schema, "properties")) {
    validate_schema_enum(
      child,
      pointer +
      "/properties/" +
      name.replace(old="~", new="~0").replace(old="/", new="~1"),
      out,
    )
  }
  match get(schema, "items") {
    Object(_) as item => validate_schema_enum(item, pointer + "/items", out)
    _ => ()
  }
}

///|
fn warn_inline_objects(
  schema : Json,
  pointer : String,
  named : Bool,
  out : Array[Diagnostic],
) -> Unit {
  if text(get(schema, "kind")) == "object" &&
    !named &&
    text(get(schema, "ref")) == "" {
    out.push(
      warning_diagnostic(
        "schema.json_fallback", pointer, "Inline object uses Json; JSON wire values are preserved",
      ),
    )
  }
  let properties = obj(get(schema, "properties"))
  let names : Array[String] = []
  for name, _ in properties {
    names.push(name)
  }
  for name in sorted_strings(names) {
    warn_inline_objects(
      properties[name],
      pointer +
      "/properties/" +
      name.replace(old="~", new="~0").replace(old="/", new="~1"),
      false,
      out,
    )
  }
  if text(get(schema, "kind")) == "array" {
    warn_inline_objects(get(schema, "items"), pointer + "/items", false, out)
  }
}
