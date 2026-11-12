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
    } else if keyword == "externalRef" {
      "unsupported.ref"
    } else {
      "unsupported.keyword"
    }
    out.push(
      error_diagnostic(code, key, "Unsupported OpenAPI feature: " + keyword),
    )
  }
  for op in arr(get(root, "operations")) {
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
/// Validate local component references after the parser has normalized them.
/// Missing and cyclic references cannot be allowed to reach codegen because
/// the codegen reader intentionally treats them as fatal IR errors.
fn validate_reference_support(root : Json, out : Array[Diagnostic]) -> Unit {
  let schemas = obj(get(root, "schemas"))
  let known : Map[String, Bool] = Map([])
  for name, _schema in schemas {
    known["#/components/schemas/" + name] = true
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
    graph[name] = refs
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
        "#/paths/" +
        path_seg +
        "/responses/" +
        text(get(response, "status")),
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
    if graph_has_cycle(name, graph, visiting, done) && !reported.contains(name) {
      reported[name] = true
      out.push(
        error_diagnostic(
          "unsupported.ref",
          "#/components/schemas/" + name,
          "Cyclic schema reference is unsupported",
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
              refs.push(ref_target(ref_path))
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
    let schema = schemas[name]
    let values = arr(get(schema, "enum"))
    if values.length() == 0 {
      continue
    }
    let pointer = "#/components/schemas/" +
      name.replace(old="~", new="~0").replace(old="/", new="~1") +
      "/enum"
    if text(get(schema, "kind")) != "string" {
      out.push(
        error_diagnostic(
          "unsupported.enum",
          pointer,
          "Non-string enum is unsupported; only string enums map to a MoonBit enum",
        ),
      )
      continue
    }
    let seen : Map[String, Bool] = Map([])
    for value in values {
      match value {
        String(wire) =>
          if seen.contains(wire) {
            out.push(
              error_diagnostic(
                "unsupported.enum",
                pointer,
                "Duplicate enum value: " + wire,
              ),
            )
          } else {
            seen[wire] = true
          }
        _ =>
          out.push(
            error_diagnostic(
              "unsupported.enum",
              pointer,
              "Enum value is not a string",
            ),
          )
      }
    }
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
