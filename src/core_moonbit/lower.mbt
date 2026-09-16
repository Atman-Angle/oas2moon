///|
/// Frontend Model -> ApiIr lowering.
///
/// Consumes the versioned Frontend Model JSON produced by the adapter
/// and builds a typed Canonical Client IR.

///|
/// Stable ordering for operations: by (path, method_rank, operation_id).
fn sort_operations(ops : Array[Json]) -> Array[Json] {
  let out : Array[Json] = []
  let mut rem = ops
  while rem.length() > 0 {
    let mut best = 0
    for i = 1; i < rem.length(); i = i + 1 {
      if before(rem[i], rem[best]) {
        best = i
      }
    }
    out.push(rem[best])
    rem = remove_at_json(rem, best)
  }
  out
}

///|
fn remove_at_json(xs : Array[Json], skip : Int) -> Array[Json] {
  let out : Array[Json] = []
  for i, x in xs {
    if i != skip {
      out.push(x)
    }
  }
  out
}

///|
fn method_rank(m : String) -> Int {
  if m == "DELETE" {
    0
  } else if m == "GET" {
    1
  } else if m == "POST" {
    2
  } else if m == "PUT" {
    3
  } else if m == "PATCH" {
    4
  } else {
    9
  }
}

///|
fn before(a : Json, b : Json) -> Bool {
  let pa = text(get(a, "path"))
  let pb = text(get(b, "path"))
  if pa != pb {
    pa < pb
  } else {
    let ra = method_rank(text(get(a, "method")))
    let rb = method_rank(text(get(b, "method")))
    if ra != rb {
      ra < rb
    } else {
      text(get(a, "operationId")) < text(get(b, "operationId"))
    }
  }
}

///|
/// Map string method to HttpMethod.
fn parse_method(m : String) -> HttpMethod {
  if m == "GET" {
    Get
  } else if m == "POST" {
    Post
  } else if m == "PUT" {
    Put
  } else if m == "PATCH" {
    Patch
  } else {
    Delete
  }
}

///|
/// Map string location to ParamLocation.
fn parse_location(loc : String) -> ParamLocation {
  if loc == "path" {
    Path
  } else if loc == "query" {
    Query
  } else {
    Header
  }
}

///|
/// Parse serialization style from JSON, applying OpenAPI defaults.
fn parse_style(style_json : Json, loc : String) -> SerializationStyle {
  let style_str = text(style_json)
  if style_str == "" {
    if loc == "query" {
      Form
    } else {
      Simple
    }
  } else if style_str == "simple" {
    Simple
  } else if style_str == "form" {
    Form
  } else {
    UnsupportedStyle(style_str)
  }
}

///|
/// Parse status code from a response JSON.
fn parse_status(r : Json) -> Int {
  let status_str = text(get(r, "status"))
  let mut n = 0
  for c in status_str {
    let ch = c.to_int()
    if ch >= 48 && ch <= 57 {
      n = n * 10 + ch - 48
    }
  }
  n
}

///|
/// Parse a schema JSON node into a model IR.
fn parse_model(schema_json : Json, model_name : String) -> ModelIr {
  let kind = text(get(schema_json, "kind"))
  if kind == "string" {
    let enum_values = arr(get(schema_json, "enum"))
    if enum_values.length() > 0 {
      let taken : Map[String, Bool] = Map([])
      let members : Array[(String, String)] = []
      for ev in enum_values {
        let wire = text(ev)
        let name = unique(pascal(wire), taken)
        members.push((name, wire))
      }
      return EnumModel({ name: model_name, members })
    }
  }
  // Parse as struct
  let properties = obj(get(schema_json, "properties"))
  let required_list = arr(get(schema_json, "required"))
  let required_set : Map[String, Bool] = Map([])
  for r in required_list {
    required_set[text(r)] = true
  }
  let taken_fields : Map[String, Bool] = Map([])
  let parsed_fields : Array[FieldIr] = []
  let opt_fields : Array[FieldIr] = []
  for name, child_schema in properties {
    let is_req = required_set.contains(name)
    let nullable = truth(get(child_schema, "nullable"))
    let presence_val = compute_presence(is_req, nullable)
    let f = {
      name: unique(snake(name), taken_fields),
      wire_name: name,
      type_ref: map_schema(child_schema),
      presence: presence_val,
    }
    if is_req {
      parsed_fields.push(f)
    } else {
      opt_fields.push(f)
    }
  }
  for f in opt_fields {
    parsed_fields.push(f)
  }
  let has_additional = truth(get(schema_json, "additionalProperties"))
  let additional_field = if has_additional {
    Some(unique("additional_properties", taken_fields))
  } else {
    None
  }
  StructModel({
    name: model_name,
    fields: parsed_fields,
    additional_properties: has_additional,
    additional_properties_field: additional_field,
  })
}

///|
/// Parse an operation JSON node into an OperationIr.
fn parse_operation(op_json : Json) -> OperationIr {
  let operation_id = text(get(op_json, "operationId"))
  let method_str = text(get(op_json, "method"))
  let path = text(get(op_json, "path"))
  let taken_params : Map[String, Bool] = Map([])
  taken_params["self"] = true
  taken_params["client"] = true
  let parsed_params : Array[ParameterIr] = []
  let opt_params : Array[ParameterIr] = []
  for p in arr(get(op_json, "parameters")) {
    let p_name = text(get(p, "name"))
    let sc = get(p, "schema")
    let moon_name = unique(snake(p_name), taken_params)
    let required = truth(get(p, "required"))
    let nullable = truth(get(sc, "nullable"))
    let param = {
      name: moon_name,
      wire_name: p_name,
      location: parse_location(text(get(p, "in"))),
      required,
      nullable,
      style: parse_style(get(p, "style"), text(get(p, "in"))),
      explode: truth(get(p, "explode")),
      type_ref: map_schema(sc),
      source: { pointer: "" },
    }
    if required {
      parsed_params.push(param)
    } else {
      opt_params.push(param)
    }
  }
  for p in opt_params {
    parsed_params.push(p)
  }
  // Parse request body
  let rb = match get(op_json, "requestBody") {
    Object(body_fields) => {
      let body_map : Map[String, Json] = body_fields
      let body_req = match body_map.get("required") {
        Some(v) => truth(v)
        None => false
      }
      let body_media = match body_map.get("media_type") {
        Some(String(s)) => Some(s)
        _ => None
      }
      let body_type = match body_map.get("schema") {
        Some(s) => Some(map_schema(s))
        None => None
      }
      Some({ type_ref: body_type, required: body_req, media_type: body_media })
    }
    _ => None
  }
  // Parse responses
  let success : Array[ResponseIr] = []
  let errors : Array[ResponseIr] = []
  for r in arr(get(op_json, "responses")) {
    let status = parse_status(r)
    let rtype = match get(r, "schema") {
      Null => None
      x => Some(map_schema(x))
    }
    let media = match get(r, "media_type") {
      Null => None
      String(s) => Some(s)
      _ => None
    }
    let response = { status, type_ref: rtype, media_type: media }
    if status >= 200 && status < 300 {
      success.push(response)
    } else {
      errors.push(response)
    }
  }
  // Parse security
  let security : Array[String] = []
  for alt in arr(get(op_json, "security")) {
    let names_arr = arr(alt)
    for name_json in names_arr {
      let name = text(name_json)
      let label = if name == "bearerAuth" { "bearer" } else { name }
      if !security.contains(label) {
        security.push(label)
      }
    }
  }
  // Parse tags
  let tags : Array[String] = []
  for t in arr(get(op_json, "tags")) {
    tags.push(text(t))
  }
  let fn_name = operation_fn_name(operation_id)
  let strategy = determine_response_strategy(success)
  {
    operation_id,
    fn_name,
    http_method: parse_method(method_str),
    path,
    tags,
    parameters: parsed_params,
    request_body: rb,
    success_responses: success,
    error_responses: errors,
    response_strategy: strategy,
    security,
    source: { pointer: "" },
  }
}

///|
/// Check if a media type is supported for JSON body responses.
fn is_supported_media_type(media_type : String?) -> Bool {
  match media_type {
    Some(mt) => mt == "application/json"
    None => true
  }
}

///|
/// Determine the response strategy from success responses.
fn determine_response_strategy(
  responses : Array[ResponseIr],
) -> ResponseStrategy {
  if responses.length() == 0 {
    return NoContent
  }
  let all_204 = {
    let mut ok = true
    for r in responses {
      if r.status != 204 {
        ok = false
      }
    }
    ok
  }
  if all_204 {
    return UnitResult
  }
  let with_body : Array[ResponseIr] = []
  for r in responses {
    match r.type_ref {
      Some(_) => with_body.push(r)
      None => ()
    }
  }
  if with_body.length() == 0 {
    return NoContent
  }
  for r in with_body {
    if !is_supported_media_type(r.media_type) {
      let mt_msg = match r.media_type {
        Some(mt) => mt
        None => "unknown"
      }
      return UnsupportedMediaType(mt_msg)
    }
  }
  let first_type = with_body[0].type_ref
  let all_same = {
    let mut ok = true
    for i = 1; i < with_body.length(); i = i + 1 {
      if with_body[i].type_ref != first_type {
        ok = false
      }
    }
    ok
  }
  if all_same {
    match first_type {
      Some(t) => return SingleResult(t)
      None => return NoContent
    }
  }
  let variants : Array[ResponseVariant] = []
  for r in with_body {
    match r.type_ref {
      Some(t) => variants.push({ status: r.status, type_ref: t })
      None => ()
    }
  }
  ResponseEnum(variants)
}

///|
/// Sort schema names deterministically.
fn sorted_names(names : Array[String]) -> Array[String] {
  let out : Array[String] = []
  let mut rem = names
  while rem.length() > 0 {
    let mut best = 0
    for i = 1; i < rem.length(); i = i + 1 {
      if rem[i] < rem[best] {
        best = i
      }
    }
    out.push(rem[best])
    rem = remove_at_string(rem, best)
  }
  out
}

///|
fn remove_at_string(xs : Array[String], skip : Int) -> Array[String] {
  let out : Array[String] = []
  for i, x in xs {
    if i != skip {
      out.push(x)
    }
  }
  out
}

///|
/// Sort models: enums before structs, then by name.
fn sort_models(xs : Array[ModelIr]) -> Array[ModelIr] {
  let out : Array[ModelIr] = []
  let mut rem = xs
  while rem.length() > 0 {
    let mut best = 0
    for i = 1; i < rem.length(); i = i + 1 {
      let n_i = model_name(rem[i])
      let n_b = model_name(rem[best])
      let e_i = model_is_enum(rem[i])
      let e_b = model_is_enum(rem[best])
      if (e_i && !e_b) || (e_i == e_b && n_i < n_b) {
        best = i
      }
    }
    out.push(rem[best])
    rem = remove_at_model(rem, best)
  }
  out
}

///|
fn remove_at_model(xs : Array[ModelIr], skip : Int) -> Array[ModelIr] {
  let out : Array[ModelIr] = []
  for i, x in xs {
    if i != skip {
      out.push(x)
    }
  }
  out
}

///|
fn model_name(m : ModelIr) -> String {
  match m {
    EnumModel(e) => e.name
    StructModel(s) => s.name
  }
}

///|
fn model_is_enum(m : ModelIr) -> Bool {
  match m {
    EnumModel(_) => true
    _ => false
  }
}

///|
/// Parse the Frontend Model JSON root and produce an ApiIr.
pub fn lower(root : Json, module_name : String) -> ApiIr {
  let title = text(get(root, "title"))
  let version = text(get(root, "openapi"))
  // Servers
  let servers : Array[String] = []
  for s in arr(get(root, "servers")) {
    servers.push(text(s))
  }
  // Auth schemes
  let auth_schemes : Array[AuthSchemeIr] = []
  for name, scheme in obj(get(root, "securitySchemes")) {
    let kind = if text(get(scheme, "type")) == "http" &&
      text(get(scheme, "scheme")) == "bearer" {
      "bearer"
    } else {
      text(get(scheme, "type"))
    }
    let location = match get(scheme, "in") {
      Null => None
      String(s) => Some(s)
      _ => None
    }
    let key_name = match get(scheme, "name") {
      Null => None
      String(s) => Some(s)
      _ => None
    }
    auth_schemes.push({ name, kind, location, key_name })
  }
  // Models
  let models : Array[ModelIr] = []
  let taken_model_names : Map[String, Bool] = Map([])
  let schema_names : Array[String] = []
  for name, _ in obj(get(root, "schemas")) {
    schema_names.push(name)
  }
  for schema_name in sorted_names(schema_names) {
    let model_name = unique(pascal(schema_name), taken_model_names)
    let schema = get(get(root, "schemas"), schema_name)
    models.push(parse_model(schema, model_name))
  }
  let sorted_models = sort_models(models)
  // Operations
  let ops = arr(get(root, "operations"))
  let sorted_ops = sort_operations(ops)
  let operations : Array[OperationIr] = []
  for op in sorted_ops {
    operations.push(parse_operation(op))
  }
  {
    module_name,
    title,
    version,
    servers,
    auth_schemes,
    models: sorted_models,
    operations,
  }
}
