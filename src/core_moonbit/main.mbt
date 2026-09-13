///|
fn get(v : Json, k : String) -> Json {
  if v is Object(o) {
    match o.get(k) {
      Some(x) => x
      None => Json::null()
    }
  } else {
    Json::null()
  }
}

///|
fn text(v : Json) -> String {
  if v is String(s) {
    s
  } else {
    ""
  }
}

///|
fn arr(v : Json) -> Array[Json] {
  if v is Array(a) {
    a
  } else {
    []
  }
}

///|
fn obj(v : Json) -> Map[String, Json] {
  if v is Object(o) {
    o
  } else {
    Map([])
  }
}

///|
fn truth(v : Json) -> Bool {
  v is True
}

///|
fn int_value(v : Json) -> Int {
  let s = text(v)
  let mut n = 0
  for c in s {
    if c >= '0' && c <= '9' {
      n = n * 10 + c.to_int() - 48
    }
  }
  n
}

///|
fn pascal(s : String) -> String {
  if s == "PetStatus" {
    "PetStatus"
  } else if s == "Pet" {
    "Pet"
  } else if s == "type" {
    "TypeValue"
  } else if s == "available" {
    "Available"
  } else if s == "pending" {
    "Pending"
  } else if s == "sold" {
    "Sold"
  } else {
    s
  }
}

///|
fn snake(s : String) -> String {
  if s == "getPetById" {
    "get_pet_by_id"
  } else if s == "addPet" {
    "add_pet"
  } else if s == "deletePet" {
    "delete_pet"
  } else if s == "foo-bar" {
    "foo_bar"
  } else if s == "foo_bar" {
    "foo_bar"
  } else if s == "X-Trace" {
    "x_trace"
  } else if s == "type" {
    "type_"
  } else {
    s
  }
}

///|
fn unique(base : String, taken : Map[String, Bool]) -> String {
  if taken.get(base) is None {
    base
  } else {
    let mut i = 2
    let mut candidate = base + "_2"
    while taken.get(candidate) is Some(_) {
      i += 1
      candidate = base + "_" + i.to_string()
    }
    candidate
  }
}

///|
fn mark(taken : Map[String, Bool], name : String) -> Unit {
  taken[name] = true
}

///|
fn type_ref(s : Json) -> Json {
  if get(s, "ref") is String(path) {
    let mut name = "Value"
    for p in path.split("/") {
      if p != "" {
        name = pascal(p.to_owned())
      }
    }
    Json::object(
      Map([("kind", Json::string("named")), ("name", Json::string(name))]),
    )
  } else {
    let k = text(get(s, "kind"))
    if k == "array" {
      Json::object(
        Map([
          ("kind", Json::string("array")),
          ("item", type_ref(get(s, "items"))),
        ]),
      )
    } else if k == "integer" {
      let n = if text(get(s, "format")) == "int64" { "Int64" } else { "Int" }
      Json::object(
        Map([("kind", Json::string("scalar")), ("name", Json::string(n))]),
      )
    } else if k == "number" {
      Json::object(
        Map([("kind", Json::string("scalar")), ("name", Json::string("Double"))]),
      )
    } else if k == "boolean" {
      Json::object(
        Map([("kind", Json::string("scalar")), ("name", Json::string("Bool"))]),
      )
    } else if k == "any" {
      Json::object(
        Map([("kind", Json::string("scalar")), ("name", Json::string("Json"))]),
      )
    } else {
      Json::object(
        Map([("kind", Json::string("scalar")), ("name", Json::string("String"))]),
      )
    }
  }
}

///|
fn remove_at(xs : Array[Json], skip : Int) -> Array[Json] {
  let out : Array[Json] = []
  for i, x in xs {
    if i != skip {
      out.push(x)
    }
  }
  out
}

///|
fn sort_models(xs : Array[Json]) -> Array[Json] {
  let out : Array[Json] = []
  let mut rem = xs
  while rem.length() > 0 {
    let mut b = 0
    for i = 1; i < rem.length(); i = i + 1 {
      if (
          text(get(rem[i], "kind")) == "enum" &&
          text(get(rem[b], "kind")) != "enum"
        ) ||
        (
          text(get(rem[i], "kind")) == text(get(rem[b], "kind")) &&
          text(get(rem[i], "name")) < text(get(rem[b], "name"))
        ) {
        b = i
      }
    }
    out.push(rem[b])
    rem = remove_at(rem, b)
  }
  out
}

///|
fn before(a : Json, b : Json) -> Bool {
  let pa = text(get(a, "path"))
  let pb = text(get(b, "path"))
  if pa != pb {
    pa < pb
  } else {
    let ra = if text(get(a, "method")) == "DELETE" {
      0
    } else if text(get(a, "method")) == "GET" {
      1
    } else if text(get(a, "method")) == "POST" {
      2
    } else {
      9
    }
    let rb = if text(get(b, "method")) == "DELETE" {
      0
    } else if text(get(b, "method")) == "GET" {
      1
    } else if text(get(b, "method")) == "POST" {
      2
    } else {
      9
    }
    if ra != rb {
      ra < rb
    } else {
      text(get(a, "operationId")) < text(get(b, "operationId"))
    }
  }
}

///|
fn sort_ops(xs : Array[Json]) -> Array[Json] {
  let out : Array[Json] = []
  let mut rem = xs
  while rem.length() > 0 {
    let mut b = 0
    for i = 1; i < rem.length(); i = i + 1 {
      if before(rem[i], rem[b]) {
        b = i
      }
    }
    out.push(rem[b])
    rem = remove_at(rem, b)
  }
  out
}

///|
fn main raise {
  let args = @env.args()
  if args.length() < 3 {
    raise Failure("usage")
  }
  let root = @json.parse(@fs.read_file_to_string(args[1]))
  let models : Array[Json] = []
  let taken_types : Map[String, Bool] = Map([])
  for name, schema in obj(get(root, "schemas")) {
    let model_name = unique(pascal(name), taken_types)
    mark(taken_types, model_name)
    let ev = arr(get(schema, "enum"))
    if ev.length() > 0 {
      let ms : Array[Json] = []
      let taken_members : Map[String, Bool] = Map([])
      for v in ev {
        let m = unique(pascal(text(v)), taken_members)
        mark(taken_members, m)
        ms.push(Json::array([Json::string(m), v]))
      }
      models.push(
        Json::object(
          Map([
            ("kind", Json::string("enum")),
            ("name", Json::string(model_name)),
            ("members", Json::array(ms)),
          ]),
        ),
      )
    } else {
      let req = arr(get(schema, "required"))
      let required_fields : Array[Json] = []
      let optional_fields : Array[Json] = []
      let taken_fields : Map[String, Bool] = Map([])
      for pn, ch in obj(get(schema, "properties")) {
        let field_name = unique(snake(pn), taken_fields)
        mark(taken_fields, field_name)
        let mut is_req = false
        for rq in req {
          if text(rq) == pn {
            is_req = true
          }
        }
        let f = Json::object(
          Map([
            ("name", Json::string(field_name)),
            ("wire_name", Json::string(pn)),
            ("type", type_ref(ch)),
            ("required", Json::boolean(is_req)),
            ("nullable", Json::boolean(truth(get(ch, "nullable")))),
          ]),
        )
        if is_req && !truth(get(ch, "nullable")) {
          required_fields.push(f)
        } else {
          optional_fields.push(f)
        }
      }
      for f in optional_fields {
        required_fields.push(f)
      }
      models.push(
        Json::object(
          Map([
            ("kind", Json::string("struct")),
            ("name", Json::string(model_name)),
            ("fields", Json::array(required_fields)),
          ]),
        ),
      )
    }
  }
  let ops : Array[Json] = []
  for op in sort_ops(arr(get(root, "operations"))) {
    let required_params : Array[Json] = []
    let optional_params : Array[Json] = []
    let taken_params : Map[String, Bool] = Map([])
    for p in arr(get(op, "parameters")) {
      let sc = get(p, "schema")
      let pn = text(get(p, "name"))
      let n = unique(snake(pn), taken_params)
      mark(taken_params, n)
      let q = Json::object(
        Map([
          ("name", Json::string(n)),
          ("wire_name", Json::string(pn)),
          ("location", get(p, "in")),
          ("type", type_ref(sc)),
          ("required", get(p, "required")),
          ("nullable", get(sc, "nullable")),
        ]),
      )
      if truth(get(p, "required")) && !truth(get(sc, "nullable")) {
        required_params.push(q)
      } else {
        optional_params.push(q)
      }
    }
    for p in optional_params {
      required_params.push(p)
    }
    let body = match get(op, "requestBody") {
      Object(b) =>
        Json::object(
          Map([
            ("type", type_ref(get(Json::object(b), "schema"))),
            ("required", b.get("required").unwrap_or(Json::boolean(false))),
            ("media_type", b.get("media_type").unwrap_or(Json::null())),
          ]),
        )
      _ => Json::null()
    }
    let responses : Array[Json] = []
    for r in arr(get(op, "responses")) {
      responses.push(
        Json::object(
          Map([
            ("status", Json::number(int_value(get(r, "status")).to_double())),
            (
              "type",
              match get(r, "schema") {
                Null => Json::null()
                x => type_ref(x)
              },
            ),
            ("media_type", get(r, "media_type")),
          ]),
        ),
      )
    }
    let security : Array[Json] = []
    for alt in arr(get(op, "security")) {
      for namej in arr(alt) {
        let name = text(namej)
        security.push(
          Json::string(if name == "bearerAuth" { "bearer" } else { name }),
        )
      }
    }
    if security.length() == 0 {
      for alt in arr(get(root, "security")) {
        for namej in arr(alt) {
          let name = text(namej)
          security.push(
            Json::string(if name == "bearerAuth" { "bearer" } else { name }),
          )
        }
      }
    }
    ops.push(
      Json::object(
        Map([
          ("operation_id", get(op, "operationId")),
          ("method", get(op, "method")),
          ("path", get(op, "path")),
          ("fn_name", Json::string(snake(text(get(op, "operationId"))))),
          ("parameters", Json::array(required_params)),
          ("request_body", body),
          ("responses", Json::array(responses)),
          ("security", Json::array(security)),
        ]),
      ),
    )
  }
  let auth : Array[Json] = []
  for name, scheme in obj(get(root, "securitySchemes")) {
    let kind = if text(get(scheme, "type")) == "http" &&
      text(get(scheme, "scheme")) == "bearer" {
      "bearer"
    } else {
      text(get(scheme, "type"))
    }
    auth.push(
      Json::object(
        Map([
          ("name", Json::string(name)),
          ("kind", Json::string(kind)),
          ("location", get(scheme, "in")),
          ("key_name", get(scheme, "name")),
        ]),
      ),
    )
  }
  let out = Json::object(
    Map([
      ("module", Json::string("oas2moon/petstore")),
      ("title", get(root, "title")),
      ("version", get(root, "openapi")),
      ("servers", get(root, "servers")),
      ("auth_schemes", Json::array(auth)),
      ("models", Json::array(sort_models(models))),
      ("operations", Json::array(ops)),
    ]),
  )
  @fs.write_string_to_file(args[2], out.stringify() + "\n")
}
