///|
/// IR serialization: ApiIr -> canonical JSON.
///
/// Produces the JSON format that the codegen backends consume.

///|
/// Convert HttpMethod to string.
fn method_to_string(m : HttpMethod) -> String {
  match m {
    Get => "GET"
    Post => "POST"
    Put => "PUT"
    Patch => "PATCH"
    Delete => "DELETE"
  }
}

///|
/// Convert ParamLocation to string.
fn location_to_string(l : ParamLocation) -> String {
  match l {
    Path => "path"
    Query => "query"
    Header => "header"
  }
}

///|
/// Convert a json array from array of strings.
fn strings_to_json(xs : Array[String]) -> Json {
  let out : Array[Json] = []
  for s in xs {
    out.push(Json::string(s))
  }
  Json::array(out)
}

///|
/// Serialize model members to JSON.
fn members_to_json(members : Array[(String, String)]) -> Json {
  let out : Array[Json] = []
  for pair in members {
    let (name, wire) = pair
    out.push(Json::array([Json::string(name), Json::string(wire)]))
  }
  Json::array(out)
}

///|
/// Serialize a FieldIr to JSON.
fn field_to_json(f : FieldIr) -> Json {
  let required = is_required_presence(f.presence)
  let nullable = is_nullable_presence(f.presence)
  Json::object(
    Map([
      ("name", Json::string(f.name)),
      ("wire_name", Json::string(f.wire_name)),
      ("type", type_ref_to_json(f.type_ref)),
      ("required", Json::boolean(required)),
      ("nullable", Json::boolean(nullable)),
      ("presence", Json::string(presence_to_string(f.presence))),
    ]),
  )
}

///|
/// Serialize fields array to JSON.
fn fields_to_json(fields : Array[FieldIr]) -> Json {
  let out : Array[Json] = []
  for f in fields {
    out.push(field_to_json(f))
  }
  Json::array(out)
}

///|
/// Serialize a model to JSON.
fn model_to_json(m : ModelIr) -> Json {
  match m {
    EnumModel(e) =>
      Json::object(
        Map([
          ("kind", Json::string("enum")),
          ("name", Json::string(e.name)),
          ("members", members_to_json(e.members)),
        ]),
      )
    StructModel(s) => {
      let additional_field = match s.additional_properties_field {
        Some(name) => Json::string(name)
        None => Json::null()
      }
      Json::object(
        Map([
          ("kind", Json::string("struct")),
          ("name", Json::string(s.name)),
          ("additional_properties", Json::boolean(s.additional_properties)),
          ("additional_properties_field", additional_field),
          ("fields", fields_to_json(s.fields)),
        ]),
      )
    }
  }
}

///|
/// Serialize models array to JSON.
fn models_to_json(models : Array[ModelIr]) -> Json {
  let out : Array[Json] = []
  for m in models {
    out.push(model_to_json(m))
  }
  Json::array(out)
}

///|
/// Serialize a ParameterIr to JSON.
fn parameter_to_json(p : ParameterIr) -> Json {
  Json::object(
    Map([
      ("name", Json::string(p.name)),
      ("wire_name", Json::string(p.wire_name)),
      ("location", Json::string(location_to_string(p.location))),
      ("type", type_ref_to_json(p.type_ref)),
      ("required", Json::boolean(p.required)),
      ("nullable", Json::boolean(p.nullable)),
      (
        "presence",
        Json::string(
          presence_to_string(compute_presence(p.required, p.nullable)),
        ),
      ),
    ]),
  )
}

///|
/// Serialize parameters array to JSON.
fn parameters_to_json(params : Array[ParameterIr]) -> Json {
  let out : Array[Json] = []
  for p in params {
    out.push(parameter_to_json(p))
  }
  Json::array(out)
}

///|
/// Serialize a RequestBodyIr to JSON.
fn request_body_to_json(rb : RequestBodyIr?) -> Json {
  match rb {
    Some(body) =>
      Json::object(
        Map([
          (
            "type",
            match body.type_ref {
              Some(t) => type_ref_to_json(t)
              None => Json::null()
            },
          ),
          ("required", Json::boolean(body.required)),
          (
            "media_type",
            match body.media_type {
              Some(s) => Json::string(s)
              None => Json::null()
            },
          ),
        ]),
      )
    None => Json::null()
  }
}

///|
/// Serialize a ResponseIr to JSON.
fn response_to_json(r : ResponseIr) -> Json {
  Json::object(
    Map([
      ("status", Json::number(r.status.to_double())),
      (
        "type",
        match r.type_ref {
          Some(t) => type_ref_to_json(t)
          None => Json::null()
        },
      ),
      (
        "media_type",
        match r.media_type {
          Some(s) => Json::string(s)
          None => Json::null()
        },
      ),
    ]),
  )
}

///|
/// Serialize responses array to JSON.
fn responses_to_json(responses : Array[ResponseIr]) -> Json {
  let out : Array[Json] = []
  for r in responses {
    out.push(response_to_json(r))
  }
  Json::array(out)
}

///| Serialize an OperationIr to JSON.

///|
/// Serialize a ResponseVariant to JSON.
fn variant_to_json(v : ResponseVariant) -> Json {
  Json::object(
    Map([
      ("status", Json::number(v.status.to_double())),
      ("type", type_ref_to_json(v.type_ref)),
    ]),
  )
}

///|
/// Serialize ResponseStrategy to JSON.
fn strategy_to_json(s : ResponseStrategy) -> Json {
  match s {
    SingleResult(tr) =>
      Json::object(
        Map([
          ("kind", Json::string("single_result")),
          ("type", type_ref_to_json(tr)),
        ]),
      )
    UnitResult => Json::object(Map([("kind", Json::string("unit_result"))]))
    ResponseEnum(variants) => {
      let out : Array[Json] = []
      for v in variants {
        out.push(variant_to_json(v))
      }
      Json::object(
        Map([
          ("kind", Json::string("response_enum")),
          ("variants", Json::array(out)),
        ]),
      )
    }
    NoContent => Json::object(Map([("kind", Json::string("no_content"))]))
    UnsupportedMediaType(mt) =>
      Json::object(
        Map([
          ("kind", Json::string("unsupported_media_type")),
          ("media_type", Json::string(mt)),
        ]),
      )
  }
}

///|
fn body_name_to_json(name : String?) -> Json {
  match name {
    Some(n) => Json::string(n)
    None => Json::null()
  }
}

///|
/// Serialize an OperationIr to JSON.
fn operation_to_json(op : OperationIr) -> Json {
  Json::object(
    Map([
      ("operation_id", Json::string(op.operation_id)),
      ("http_method", Json::string(method_to_string(op.http_method))),
      ("path", Json::string(op.path)),
      ("fn_name", Json::string(op.fn_name)),
      ("tags", strings_to_json(op.tags)),
      ("parameters", parameters_to_json(op.parameters)),
      ("request_body", request_body_to_json(op.request_body)),
      ("body_name", body_name_to_json(op.body_name)),
      ("success_responses", responses_to_json(op.success_responses)),
      ("error_responses", responses_to_json(op.error_responses)),
      ("response_strategy", strategy_to_json(op.response_strategy)),
      ("security", strings_to_json(op.security)),
      ("source_pointer", Json::string(op.source.pointer)),
    ]),
  )
}

///|
/// Serialize AuthSchemeIr to JSON.
fn auth_scheme_to_json(s : AuthSchemeIr) -> Json {
  Json::object(
    Map([
      ("name", Json::string(s.name)),
      ("kind", Json::string(s.kind)),
      (
        "location",
        match s.location {
          Some(l) => Json::string(l)
          None => Json::null()
        },
      ),
      (
        "key_name",
        match s.key_name {
          Some(k) => Json::string(k)
          None => Json::null()
        },
      ),
    ]),
  )
}

///|
/// Serialize auth schemes array to JSON.
fn auth_schemes_to_json(schemes : Array[AuthSchemeIr]) -> Json {
  let out : Array[Json] = []
  for s in schemes {
    out.push(auth_scheme_to_json(s))
  }
  Json::array(out)
}

///|
/// Serialize operations array to JSON.
fn operations_to_json(ops : Array[OperationIr]) -> Json {
  let out : Array[Json] = []
  for op in ops {
    out.push(operation_to_json(op))
  }
  Json::array(out)
}

///|
/// Serialize the full ApiIr to canonical JSON.
pub fn api_to_json(api : ApiIr) -> Json {
  Json::object(
    Map([
      ("module", Json::string(api.module_name)),
      ("title", Json::string(api.title)),
      ("version", Json::string(api.version)),
      ("servers", strings_to_json(api.servers)),
      ("auth_schemes", auth_schemes_to_json(api.auth_schemes)),
      ("models", models_to_json(api.models)),
      ("operations", operations_to_json(api.operations)),
    ]),
  )
}

///|
/// Serialize ApiIr to a canonical JSON string.
pub fn api_to_json_string(api : ApiIr) -> String {
  api_to_json(api).stringify() + "\n"
}
