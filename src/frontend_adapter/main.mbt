///|
/// Formal Frontend Adapter for oas2moon Phase 1.
///
/// Parsing is delegated to `Han-Wentao/mooncontract`. This program re-emits the
/// parsed model as deterministic JSON (the Frontend Model) so that the Client IR
/// builder can consume it. It never generates code and never walks raw OpenAPI
/// JSON to drive codegen.
///
/// The only raw-JSON access is the narrow sidecar below: mooncontract does not
/// expose `servers`, `components.securitySchemes` or `security`, so those fields
/// are read directly and merged into the same Frontend Model. No second OpenAPI
/// parser is created here.
fn string_or_null(value : String?) -> Json {
  match value {
    Some(text) => Json::string(text)
    None => Json::null()
  }
}

///|
/// Raw sidecar: read one key, `null` when absent.
#warnings("-deprecated")
fn raw_get(json : Json, key : String) -> Json {
  match json.value(key) {
    Some(value) => value
    None => Json::null()
  }
}

///|
#warnings("-deprecated")
fn raw_as_array(json : Json) -> Array[Json]? {
  json.as_array()
}

///|
#warnings("-deprecated")
fn raw_as_object(json : Json) -> Map[String, Json]? {
  json.as_object()
}

///|
#warnings("-deprecated")
fn raw_as_string(json : Json) -> String? {
  json.as_string()
}

///|
fn raw_boolean(json : Json) -> Bool? {
  match json {
    True => Some(true)
    False => Some(false)
    _ => None
  }
}

///|
fn raw_array(json : Json) -> Array[Json] {
  match raw_as_array(json) {
    Some(values) => values
    None => []
  }
}

///|
fn raw_object_entries(json : Json) -> Map[String, Json] {
  match raw_as_object(json) {
    Some(entries) => entries
    None => Map([])
  }
}

///|
/// Build an object whose keys are inserted in `keys` order.
///
/// JSON object key order carries no meaning, so the Frontend Model never
/// forwards source order: every unordered map is re-emitted through this
/// helper with sorted keys. The runtime `Map` preserves insertion order, so
/// without this the parser would leak document order into the normalized
/// model.
fn object_with_sorted_keys(
  keys : Array[String],
  lookup : (String) -> Json,
) -> Json {
  let out : Map[String, Json] = Map([])
  for key in keys {
    out[key] = lookup(key)
  }
  Json::object(out)
}

///|
/// The keys of a JSON object in a deterministic (ascending) order.
fn sorted_object_keys(json : Json) -> Array[String] {
  let keys : Array[String] = []
  for key, _value in raw_object_entries(json) {
    keys.push(key)
  }
  sort_keys(keys)
}

///|
/// Selection sort with strictly ascending comparison, so equal keys keep their
/// relative order. Mirrors `sorted_strings` in the core authority.
fn sort_keys(keys : Array[String]) -> Array[String] {
  let out : Array[String] = []
  let mut rem = keys
  while rem.length() > 0 {
    let mut best = 0
    for i = 1; i < rem.length(); i = i + 1 {
      if rem[i] < rem[best] {
        best = i
      }
    }
    out.push(rem[best])
    let rest : Array[String] = []
    for i, key in rem {
      if i != best {
        rest.push(key)
      }
    }
    rem = rest
  }
  out
}

///|
/// Declared server URLs, in document order.
fn raw_servers(root : Json) -> Json {
  let urls : Array[Json] = []
  for server in raw_array(raw_get(root, "servers")) {
    match raw_as_string(raw_get(server, "url")) {
      Some(url) => urls.push(Json::string(url))
      None => ()
    }
  }
  Json::array(urls)
}

///|
/// Declared security schemes.
fn raw_security_schemes(root : Json) -> Json {
  let schemes = raw_get(raw_get(root, "components"), "securitySchemes")
  object_with_sorted_keys(sorted_object_keys(schemes), name => {
    let scheme = raw_get(schemes, name)
    Json::object(
      Map([
        ("type", string_or_null(raw_as_string(raw_get(scheme, "type")))),
        ("scheme", string_or_null(raw_as_string(raw_get(scheme, "scheme")))),
        ("in", string_or_null(raw_as_string(raw_get(scheme, "in")))),
        ("name", string_or_null(raw_as_string(raw_get(scheme, "name")))),
      ]),
    )
  })
}

///|
/// `security` is a list of alternatives; each alternative lists scheme names.
/// Scopes are kept at the adapter boundary only as scheme names; the Phase 1
/// model deliberately does not claim OAuth-flow semantics.
fn raw_security_alternatives(owner : Json) -> Array[Json] {
  let out : Array[Json] = []
  for alternative in raw_array(raw_get(owner, "security")) {
    let names : Array[Json] = []
    for name, _scopes in raw_object_entries(alternative) {
      names.push(Json::string(name))
    }
    out.push(Json::array(names))
  }
  out
}

///|
/// Operation-level security, falling back to the document root when the
/// operation does not declare its own `security` list.
fn raw_operation_security(
  root : Json,
  http_method : String,
  path : String,
) -> Array[Json] {
  let operation = raw_get(
    raw_get(raw_get(root, "paths"), path),
    http_method.to_lower(),
  )
  match raw_as_array(raw_get(operation, "security")) {
    Some(_) => raw_security_alternatives(operation)
    None => raw_security_alternatives(root)
  }
}

///|
fn schema_to_json(schema : @openapi.Schema) -> Json {
  let property_names : Array[String] = []
  for name, _child in schema.properties {
    property_names.push(name)
  }
  // Keys come from the same map, so the indexed read cannot miss.
  let properties = object_with_sorted_keys(sort_keys(property_names), name => {
    schema_to_json(schema.properties[name])
  })
  let required : Array[Json] = []
  for name in schema.required {
    required.push(Json::string(name))
  }
  let items = match schema.items {
    Some(child) => schema_to_json(child)
    None => Json::null()
  }
  Json::object(
    Map([
      ("kind", Json::string(schema.kind.label())),
      ("ref", string_or_null(schema.ref_path)),
      ("format", string_or_null(schema.format)),
      ("nullable", Json::boolean(schema.nullable)),
      ("required", Json::array(required)),
      ("properties", properties),
      ("items", items),
      ("enum", Json::array(schema.enum_values.copy())),
      ("additionalProperties", Json::boolean(schema.additional_properties)),
    ]),
  )
}

///|
/// Resolve one local component object from the raw sidecar. MoonContract keeps
/// component refs on Parameter/BodySpec/ResponseSpec as ref_path metadata, so
/// this small lookup restores the referenced object's wire fields without
/// duplicating OpenAPI parsing.
fn raw_component(root : Json, section : String, name : String) -> Json {
  raw_get(raw_get(raw_get(root, "components"), section), name)
}

///|
fn raw_resolve_component(root : Json, section : String, value : Json) -> Json {
  let prefix = "#/components/" + section + "/"
  let seen : Map[String, Bool] = Map([])
  let mut resolved = value
  while raw_as_string(raw_get(resolved, "$ref")) is Some(reference) {
    if seen.contains(reference) {
      return Json::null()
    }
    seen[reference] = true
    match reference.strip_prefix(prefix) {
      Some(name) =>
        resolved = raw_component(
          root,
          section,
          name
          .to_owned()
          .replace_all(old="~1", new="/")
          .replace_all(old="~0", new="~"),
        )
      None => return Json::null()
    }
  }
  resolved
}

///|
fn raw_schema_to_json(schema : Json) -> Json {
  let properties = match raw_as_object(raw_get(schema, "properties")) {
    Some(entries) => {
      let names : Array[String] = []
      for name, _ in entries {
        names.push(name)
      }
      object_with_sorted_keys(sort_keys(names), name => {
        raw_schema_to_json(entries[name])
      })
    }
    None => Json::object(Map([]))
  }
  let items = match raw_get(schema, "items") {
    Null => Json::null()
    value => raw_schema_to_json(value)
  }
  let kind = raw_as_string(raw_get(schema, "type")).unwrap_or("any")
  Json::object(
    Map([
      ("kind", Json::string(kind)),
      ("ref", raw_get(schema, "$ref")),
      ("format", raw_get(schema, "format")),
      (
        "nullable",
        Json::boolean(raw_boolean(raw_get(schema, "nullable")).unwrap_or(false)),
      ),
      (
        "required",
        match raw_get(schema, "required") {
          Array(values) => Json::array(values)
          _ => Json::array([])
        },
      ),
      ("properties", properties),
      ("items", items),
      (
        "enum",
        match raw_get(schema, "enum") {
          Array(values) => Json::array(values)
          _ => Json::array([])
        },
      ),
      (
        "additionalProperties",
        match raw_get(schema, "additionalProperties") {
          True => Json::boolean(true)
          _ => Json::boolean(false)
        },
      ),
    ]),
  )
}

///|
fn raw_parameter_at(
  root : Json,
  path : String,
  http_method : String,
  index : Int32,
) -> Json {
  let path_parameters = raw_array(
    raw_get(raw_get(raw_get(root, "paths"), path), "parameters"),
  )
  let operation_parameters = raw_array(
    raw_get(
      raw_get(raw_get(raw_get(root, "paths"), path), http_method.to_lower()),
      "parameters",
    ),
  )
  if index < path_parameters.length() {
    path_parameters[index]
  } else {
    operation_parameters
    .get(index - path_parameters.length())
    .unwrap_or(Json::null())
  }
}

///|
fn parameter_to_json(
  parameter : @openapi.Parameter,
  index : Int32,
  root : Json,
  path : String,
  http_method : String,
) -> Json {
  let source = raw_parameter_at(root, path, http_method, index)
  let raw_parameter = raw_resolve_component(root, "parameters", source)
  let raw_name = raw_as_string(raw_get(raw_parameter, "name")).unwrap_or(
    parameter.name,
  )
  let raw_location = raw_as_string(raw_get(raw_parameter, "in")).unwrap_or(
    parameter.location.label(),
  )
  let raw_required = match raw_get(raw_parameter, "required") {
    True => true
    _ => parameter.required
  }
  let raw_schema = if parameter.ref_path is Some(_) {
    raw_schema_to_json(raw_get(raw_parameter, "schema"))
  } else {
    schema_to_json(parameter.schema)
  }
  Json::object(
    Map([
      ("name", Json::string(raw_name)),
      ("in", Json::string(raw_location)),
      ("required", Json::boolean(raw_required)),
      ("schema", raw_schema),
      ("ref", string_or_null(parameter.ref_path)),
      ("style", string_or_null(raw_as_string(raw_get(raw_parameter, "style")))),
      ("explode", raw_get(raw_parameter, "explode")),
    ]),
  )
}

///|
fn body_to_json(body : @openapi.BodySpec) -> Json {
  Json::object(
    Map([
      ("required", Json::boolean(body.required)),
      ("media_type", Json::string(body.media_type)),
      ("schema", schema_to_json(body.schema)),
    ]),
  )
}

///|
fn raw_body_to_json(body : Json, fallback : @openapi.BodySpec) -> Json {
  let resolved = body
  let required = match raw_get(resolved, "required") {
    True => true
    _ => fallback.required
  }
  let content = raw_get(resolved, "content")
  let media = match raw_as_object(content) {
    Some(entries) =>
      match entries.get("application/json") {
        Some(_) => "application/json"
        None => "application/*+json"
      }
    None => fallback.media_type
  }
  let media_node = raw_get(raw_get(content, media), "schema")
  Json::object(
    Map([
      ("required", Json::boolean(required)),
      ("media_type", Json::string(media)),
      (
        "schema",
        if media_node is Null {
          schema_to_json(fallback.schema)
        } else {
          raw_schema_to_json(media_node)
        },
      ),
    ]),
  )
}

///|
fn response_to_json(response : @openapi.ResponseSpec) -> Json {
  let schema = match response.schema {
    Some(value) => schema_to_json(value)
    None => Json::null()
  }
  Json::object(
    Map([
      ("status", Json::string(response.status)),
      ("description", Json::string(response.description)),
      ("media_type", string_or_null(response.media_type)),
      ("schema", schema),
    ]),
  )
}

///|
fn raw_response_to_json(
  response : Json,
  fallback : @openapi.ResponseSpec,
) -> Json {
  let content = raw_get(response, "content")
  let media_node = raw_get(raw_get(content, "application/json"), "schema")
  let schema = if media_node is Null {
    Json::null()
  } else {
    raw_schema_to_json(media_node)
  }
  Json::object(
    Map([
      ("status", Json::string(fallback.status)),
      (
        "description",
        Json::string(
          raw_as_string(raw_get(response, "description")).unwrap_or(
            fallback.description,
          ),
        ),
      ),
      (
        "media_type",
        if media_node is Null {
          Json::null()
        } else {
          Json::string("application/json")
        },
      ),
      ("schema", schema),
    ]),
  )
}

///|
fn operation_to_json(
  operation : @openapi.Operation,
  security : Array[Json],
  root : Json,
) -> Json {
  let parameters : Array[Json] = []
  for index, parameter in operation.parameters {
    let normalized = parameter_to_json(
      parameter,
      index,
      root,
      operation.path,
      operation.http_method.label(),
    )
    let inherited_index = for position, existing in parameters {
      if raw_get(existing, "name") == raw_get(normalized, "name") &&
        raw_get(existing, "in") == raw_get(normalized, "in") {
        break Some(position)
      }
    } nobreak {
      None
    }
    match inherited_index {
      Some(position) => parameters[position] = normalized
      None => parameters.push(normalized)
    }
  }
  let responses : Array[Json] = []
  for response in operation.responses {
    let raw_responses = raw_get(
      raw_get(
        raw_get(raw_get(root, "paths"), operation.path),
        operation.http_method.label().to_lower(),
      ),
      "responses",
    )
    let raw_value = raw_get(raw_responses, response.status)
    let resolved = raw_resolve_component(root, "responses", raw_value)
    responses.push(
      if raw_get(raw_value, "$ref") is String(_) && resolved is Object(_) {
        raw_response_to_json(resolved, response)
      } else {
        response_to_json(response)
      },
    )
  }
  let body = match operation.request_body {
    Some(value) => {
      let raw_body = raw_get(
        raw_get(
          raw_get(raw_get(root, "paths"), operation.path),
          operation.http_method.label().to_lower(),
        ),
        "requestBody",
      )
      let resolved = raw_resolve_component(root, "requestBodies", raw_body)
      if raw_get(raw_body, "$ref") is String(_) && resolved is Object(_) {
        raw_body_to_json(resolved, value)
      } else {
        body_to_json(value)
      }
    }
    None => Json::null()
  }
  Json::object(
    Map([
      ("operationId", Json::string(operation.operation_id)),
      ("method", Json::string(operation.http_method.label())),
      ("path", Json::string(operation.path)),
      ("security", Json::array(security)),
      ("parameters", Json::array(parameters)),
      ("requestBody", body),
      ("responses", Json::array(responses)),
    ]),
  )
}

///|
/// Whether a path names a YAML document. YAML is a convenience input; JSON stays
/// the authoritative format.
fn is_yaml_path(path : String) -> Bool {
  let lower = path.to_lower()
  lower.has_suffix(".yaml") || lower.has_suffix(".yml")
}

///|
fn supported_openapi_version(version : String) -> Bool {
  version == "3.0.0" ||
  version == "3.0.1" ||
  version == "3.0.2" ||
  version == "3.0.3"
}

///|
/// Convert a YAML document into JSON using the ecosystem YAML parser so that the
/// raw sidecar sees the same shape as the JSON input path.
fn raw_from_yaml(source : String) -> Json raise {
  let documents = @yaml.Yaml::load_from_string(source)
  match documents.get(0) {
    Some(document) => @json.to_json(document)
    None => Json::null()
  }
}

///|
fn main raise {
  let args = @env.args()
  guard args.length() >= 3 else {
    println("usage: oas2moon-frontend <spec.json|spec.yaml> <normalized.json>")
    @sys.exit(2)
    return
  }
  let source = @fs.read_file_to_string(args[1])
  let yaml_input = is_yaml_path(args[1])
  let raw = if yaml_input { raw_from_yaml(source) } else { @json.parse(source) }
  let version = raw_as_string(raw_get(raw, "openapi")).unwrap_or("")
  if !supported_openapi_version(version) {
    println(
      "error[unsupported.version] /openapi: expected OpenAPI 3.0.0 through 3.0.3, got " +
      version,
    )
    @sys.exit(3)
    return
  }
  let parsed = if yaml_input {
    @openapi.parse_yaml(source)
  } else {
    @openapi.parse_json(source)
  }
  match parsed {
    Err(diagnostics) => {
      for diagnostic in diagnostics {
        println(diagnostic.to_text())
      }
      @sys.exit(3)
    }
    Ok(document) => {
      let operations : Array[Json] = []
      for operation in document.operations {
        operations.push(
          operation_to_json(
            operation,
            raw_operation_security(
              raw,
              operation.http_method.label(),
              operation.path,
            ),
            raw,
          ),
        )
      }
      let schema_names : Array[String] = []
      for name, _schema in document.components.schemas {
        schema_names.push(name)
      }
      // Keys come from the same map, so the indexed read cannot miss.
      let schemas = object_with_sorted_keys(sort_keys(schema_names), name => {
        schema_to_json(document.components.schemas[name])
      })
      let normalized = Json::object(
        Map([
          ("frontendModelVersion", Json::number(1.0)),
          ("openapi", Json::string(document.version)),
          ("title", Json::string(document.title)),
          ("servers", raw_servers(raw)),
          ("securitySchemes", raw_security_schemes(raw)),
          ("security", Json::array(raw_security_alternatives(raw))),
          ("operations", Json::array(operations)),
          ("schemas", schemas),
          (
            "issues",
            merge_issue_arrays(
              raw_unsupported_issues(raw),
              raw_media_findings(raw),
            ),
          ),
          ("ignored", raw_ignored_issues(raw)),
        ]),
      )
      @fs.write_string_to_file(args[2], normalized.stringify(indent=2) + "\n")
    }
  }
}

///|
fn merge_issue_arrays(left : Json, right : Json) -> Json {
  let out : Array[Json] = []
  for value in raw_array(left) {
    out.push(value)
  }
  for value in raw_array(right) {
    out.push(value)
  }
  Json::array(out)
}
