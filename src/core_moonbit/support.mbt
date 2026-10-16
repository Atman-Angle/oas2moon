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
    out.push(
      error_diagnostic(
        "unsupported.keyword",
        key,
        "Unsupported schema feature: " + text(get(issue, "keyword")),
      ),
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
