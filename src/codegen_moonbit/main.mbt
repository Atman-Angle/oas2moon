///|
/// MoonBit model emitter for the Canonical Client IR.
///
/// This executable consumes only `ApiIr` parsed from canonical JSON. It does
/// not read OpenAPI, does not reconstruct names, and does not reinterpret model
/// semantics.

///|
fn line(out : StringBuilder, text : String) -> Unit {
  out.write_string(text)
  out.write_char('\n')
}

///|
fn quoted(text : String) -> String {
  text.escape()
}

///|
/// MoonBit reserved keywords.
let moonbit_keywords : Map[String, Bool] = {
  let m : Map[String, Bool] = Map([])
  for
    kw in [
      "as", "async", "await", "break", "catch", "const", "continue", "derive", "else",
      "enum", "false", "fn", "for", "guard", "if", "impl", "import", "in", "init",
      "is", "let", "loop", "match", "mut", "noraise", "not", "null", "op", "or",
      "override", "package", "priv", "pub", "pure", "raise", "readonly", "ref", "return",
      "self", "static", "struct", "suberror", "test", "trait", "true", "try", "type",
      "var", "while", "with",
      // generated helpers
       "all", "client", "config", "from_json", "json", "new", "open", "to_json",
      "to_wire",
    ] {
    m[kw] = true
  }
  m
}

///|
fn escape_moonbit(name : String) -> String {
  if moonbit_keywords.contains(name) {
    name + "_"
  } else {
    name
  }
}

///|
fn render_type(type_ref : TypeRef) -> String {
  match type_ref.kind {
    "scalar" =>
      match type_ref.name {
        Some(name) => name
        None => abort("validated scalar type is missing its name")
      }
    "named" =>
      match type_ref.name {
        Some(name) => name
        None => abort("validated named type is missing its name")
      }
    "array" =>
      match type_ref.item {
        Some(item) => "Array[" + render_type(item) + "]"
        None => abort("validated array type is missing its item")
      }
    _ => abort("validated type has an unsupported kind")
  }
}

///|
fn contains_int64(type_ref : TypeRef) -> Bool {
  match type_ref.kind {
    "scalar" =>
      match type_ref.name {
        Some("Int64") => true
        _ => false
      }
    "array" =>
      match type_ref.item {
        Some(item) => contains_int64(item)
        None => abort("validated array type is missing its item")
      }
    _ => false
  }
}

///|
fn is_int64_scalar(type_ref : TypeRef) -> Bool {
  type_ref.kind == "scalar" && type_ref.name == Some("Int64")
}

///|
fn field_moon_type(field : FieldIr) -> String {
  let rendered = render_type(field.type_ref)
  match field.presence {
    "required" => rendered
    "required_nullable" => rendered + "?"
    "optional" => rendered + "?"
    "optional_nullable" => "Presence[" + rendered + "]"
    _ => abort("validated field has an unsupported presence")
  }
}

///|
fn int64_codec_suffix(type_ref : TypeRef) -> String {
  match type_ref.kind {
    "scalar" =>
      match type_ref.name {
        Some("Int64") => "int64"
        _ => abort("Int64 codec requested for a non-Int64 scalar")
      }
    "array" =>
      match type_ref.item {
        Some(item) => "array_" + int64_codec_suffix(item)
        None => abort("validated array type is missing its item")
      }
    _ => abort("Int64 codec requested for a type without Int64")
  }
}

///|
fn encode_expr(type_ref : TypeRef, value : String) -> String {
  match type_ref.kind {
    "scalar" =>
      match type_ref.name {
        Some("Json") => value
        Some("Int64") => "__i64_json(" + value + ")"
        _ => "@json.to_json(" + value + ")"
      }
    "named" => "@json.to_json(" + value + ")"
    "array" =>
      if contains_int64(type_ref) {
        "__encode_" + int64_codec_suffix(type_ref) + "(" + value + ")"
      } else {
        "@json.to_json(" + value + ")"
      }
    _ => abort("validated type has an unsupported kind")
  }
}

///|
fn decode_expr(type_ref : TypeRef, value : String, path : String) -> String {
  match type_ref.kind {
    "scalar" =>
      match type_ref.name {
        Some("Json") => value
        Some("Int") => "__dec_int(" + value + ", " + path + ")"
        Some("Int64") => "__dec_i64(" + value + ", " + path + ")"
        Some("Double") => "__dec_dbl(" + value + ", " + path + ")"
        _ => "@json.from_json(" + value + ", path=" + path + ")"
      }
    "named" => "@json.from_json(" + value + ", path=" + path + ")"
    "array" =>
      if contains_int64(type_ref) {
        "__decode_" +
        int64_codec_suffix(type_ref) +
        "(" +
        value +
        ", " +
        path +
        ")"
      } else {
        "@json.from_json(" + value + ", path=" + path + ")"
      }
    _ => abort("validated type has an unsupported kind")
  }
}

///|
fn collect_int64_helpers(
  type_ref : TypeRef,
  seen : Map[String, Bool],
  helpers : Array[TypeRef],
) -> Unit {
  match type_ref.kind {
    "array" => {
      let item = match type_ref.item {
        Some(value) => value
        None => abort("validated array type is missing its item")
      }
      if contains_int64(item) {
        collect_int64_helpers(item, seen, helpers)
      }
      if contains_int64(type_ref) {
        let suffix = int64_codec_suffix(type_ref)
        if seen.get(suffix) is None {
          seen[suffix] = true
          helpers.push(type_ref)
        }
      }
    }
    _ => ()
  }
}

///|
fn emit_int64_helpers(out : StringBuilder, api : ApiIr) -> Unit {
  let uses_int64 = api_uses_int64(api)
  if uses_int64 {
    line(out, "///|")
    line(out, "fn __dec_i64(json : Json, path : JPath) -> Int64 raise JErr {")
    line(out, "  match json {")
    line(out, "    Number(n, ..) => {")
    line(out, "      if n.is_nan() || n.is_inf() || n != n.trunc() {")
    line(
      out, "        raise __error(path, \"expected an integer (JSON number)\")",
    )
    line(out, "      }")
    line(out, "      // Beyond 2^53-1 a Double rounds; parse the preserved source text.")
    line(out, "      if n > 9007199254740991.0 || n < -9007199254740991.0 {")
    line(out, "        @string.parse_int64(json.stringify()) catch {")
    line(
      out, "          _ => raise __error(path, \"integer value is out of range for Int64\")",
    )
    line(out, "        }")
    line(out, "      } else {")
    line(out, "        n.to_int64()")
    line(out, "      }")
    line(out, "    }")
    line(
      out, "    _ => raise __error(path, \"expected an integer (JSON number)\")",
    )
    line(out, "  }")
    line(out, "}")
    line(out, "")
    line(out, "///|")
    line(out, "fn __i64_json(value : Int64) -> Json {")
    line(out, "  Json::number(value.to_double(), repr=value.to_string())")
    line(out, "}")
    line(out, "")
  }
  let helpers : Array[TypeRef] = []
  let seen : Map[String, Bool] = Map([])
  for model in api.models {
    match model {
      EnumModel(_) => ()
      StructModel(value) =>
        for field in value.fields {
          collect_int64_helpers(field.type_ref, seen, helpers)
        }
    }
  }
  for type_ref in helpers {
    let suffix = int64_codec_suffix(type_ref)
    let rendered = render_type(type_ref)
    let item = match type_ref.item {
      Some(value) => value
      None => abort("validated array type is missing its item")
    }
    line(out, "///|")
    line(out, "fn __encode_" + suffix + "(value : " + rendered + ") -> Json {")
    line(out, "  let out : Array[Json] = []")
    line(out, "  for item in value {")
    line(out, "    out.push(" + encode_expr(item, "item") + ")")
    line(out, "  }")
    line(out, "  Json::array(out)")
    line(out, "}")
    line(out, "")
    line(out, "///|")
    line(
      out,
      "fn __decode_" +
      suffix +
      "(json : Json, path : JPath) -> " +
      rendered +
      " raise JErr {",
    )
    line(out, "  let items : Array[Json] = match json {")
    line(out, "    Array(values) => values")
    line(
      out, "    _ => raise @json.JsonDecodeError((path, \"expected a JSON array\"))",
    )
    line(out, "  }")
    line(out, "  let out : " + rendered + " = []")
    line(out, "  for index, value in items {")
    line(
      out,
      "    out.push(" +
      decode_expr(item, "value", "path.add_index(index)") +
      ")",
    )
    line(out, "  }")
    line(out, "  out")
    line(out, "}")
    line(out, "")
  }
}

///|
fn emit_runtime_helpers(out : StringBuilder) -> Unit {
  line(out, "///|")
  line(out, "type JPath = @json.JsonPath")
  line(out, "")
  line(out, "///|")
  line(out, "type JErr = @json.JsonDecodeError")
  line(out, "")
  line(out, "///|")
  line(out, "fn __error(path : JPath, message : String) -> JErr {")
  line(out, "  @json.JsonDecodeError((path, message))")
  line(out, "}")
  line(out, "")
  line(out, "///|")
  line(out, "pub(all) enum Presence[T] {")
  line(out, "  Unset")
  line(out, "  Null")
  line(out, "  Value(T)")
  line(out, "} derive(Eq, Debug)")
  emit_trait_extensions(out, "Presence", ["Eq", "@moonbitlang/core/debug.Debug"])
  line(out, "")
  line(out, "///|")
  line(out, "fn __dec_int(json : Json, path : JPath) -> Int raise JErr {")
  line(out, "  match json {")
  line(out, "    Number(n, ..) if !n.is_nan() && !n.is_inf() => {")
  line(out, "      if n != n.trunc() {")
  line(
    out, "        raise __error(path, \"expected an integer, found a fractional number\")",
  )
  line(out, "      }")
  line(out, "      if n > 2147483647.0 || n < -2147483648.0 {")
  line(
    out, "        raise __error(path, \"integer value is out of range for Int\")",
  )
  line(out, "      }")
  line(out, "      n.to_int()")
  line(out, "    }")
  line(
    out, "    _ => raise __error(path, \"expected an integer (JSON number)\")",
  )
  line(out, "  }")
  line(out, "}")
  line(out, "")
  line(out, "///|")
  line(out, "fn __dec_dbl(json : Json, path : JPath) -> Double raise JErr {")
  line(out, "  match json {")
  line(out, "    Number(n, ..) if !n.is_nan() && !n.is_inf() => n")
  line(out, "    _ => raise __error(path, \"expected a finite JSON number\")")
  line(out, "  }")
  line(out, "}")
  line(out, "")
  line(out, "///|")
  line(
    out, "fn __put(fields : Map[String, Json], key : String, value : Json) -> Unit {",
  )
  line(out, "  fields[key] = value")
  line(out, "}")
  line(out, "")
}

///|
/// Emit explicit method promotion declarations required by MoonBit 0.10.14.
/// Without these, `--deny-warn` rejects derived/implemented traits.
fn emit_trait_extensions(
  out : StringBuilder,
  type_name : String,
  traits : Array[String],
) -> Unit {
  for trait_name in traits {
    let methods = if trait_name == "Eq" {
      "{not_equal, equal}"
    } else if trait_name == "ToJson" {
      "{to_json}"
    } else if trait_name == "@moonbitlang/core/json.FromJson" {
      "{from_json}"
    } else {
      "{to_repr}"
    }
    line(
      out,
      "pub extend " + type_name + " with " + trait_name + "::" + methods,
    )
  }
  line(out, "")
}

///|
fn emit_enum(out : StringBuilder, model : EnumModelIr) -> Unit {
  line(out, "///|")
  line(out, "pub(all) enum " + model.name + " {")
  for enum_member in model.members {
    line(out, "  " + enum_member.name)
  }
  line(out, "} derive(Eq, Debug)")
  emit_trait_extensions(out, model.name, ["Eq", "@moonbitlang/core/debug.Debug"])
  line(out, "")
  line(out, "///|")
  line(
    out,
    "pub fn " + model.name + "::to_wire(self : " + model.name + ") -> String {",
  )
  line(out, "  match self {")
  for enum_member in model.members {
    line(out, "    " + enum_member.name + " => " + quoted(enum_member.wire))
  }
  line(out, "  }")
  line(out, "}")
  line(out, "")
  line(out, "///|")
  line(
    out,
    "pub impl ToJson for " +
    model.name +
    " with fn to_json(self : " +
    model.name +
    ") -> Json {",
  )
  line(out, "  Json::string(self.to_wire())")
  line(out, "}")
  emit_trait_extensions(out, model.name, ["ToJson"])
  line(out, "")
  line(out, "///|")
  line(
    out,
    "pub impl FromJson for " + model.name + " with fn from_json(json, path) {",
  )
  line(out, "  let text : String = @json.from_json(json) catch {")
  line(
    out,
    "    _ => raise __error(path, \"expected a string for enum " +
    model.name +
    "\")",
  )
  line(out, "  }")
  line(out, "  match text {")
  for enum_member in model.members {
    line(out, "    " + quoted(enum_member.wire) + " => " + enum_member.name)
  }
  line(
    out,
    "    _ => raise __error(path, \"unknown wire value for enum " +
    model.name +
    "\")",
  )
  line(out, "  }")
  line(out, "}")
  emit_trait_extensions(out, model.name, ["@moonbitlang/core/json.FromJson"])
  line(out, "")
}

///|
fn emit_struct_declaration(out : StringBuilder, model : StructModelIr) -> Unit {
  line(out, "///|")
  line(out, "pub(all) struct " + model.name + " {")
  for field in model.fields {
    let mn = escape_moonbit(field.name)
    line(out, "  " + mn + " : " + field_moon_type(field))
  }
  match model.additional_properties_field {
    Some(name) => {
      let en = escape_moonbit(name)
      line(out, "  " + en + " : Map[String, Json]")
    }
    None => ()
  }
  line(out, "} derive(Eq, Debug)")
  emit_trait_extensions(out, model.name, ["Eq", "@moonbitlang/core/debug.Debug"])
  line(out, "")
}

///|
fn emit_struct_constructor(out : StringBuilder, model : StructModelIr) -> Unit {
  line(out, "///|")
  line(out, "pub fn " + model.name + "::new(")
  for field in model.fields {
    match field.presence {
      "required" =>
        line(
          out,
          "  " +
          escape_moonbit(field.name) +
          " : " +
          render_type(field.type_ref) +
          ",",
        )
      "required_nullable" =>
        line(
          out,
          "  " +
          escape_moonbit(field.name) +
          " : " +
          render_type(field.type_ref) +
          "?,",
        )
      "optional" =>
        line(
          out,
          "  " +
          escape_moonbit(field.name) +
          "? : " +
          render_type(field.type_ref) +
          ",",
        )
      "optional_nullable" =>
        line(
          out,
          "  " +
          field.name +
          "? : Presence[" +
          render_type(field.type_ref) +
          "] = Unset,",
        )
      _ => abort("validated field has an unsupported presence")
    }
  }
  match model.additional_properties_field {
    Some(name) => line(out, "  " + name + "? : Map[String, Json] = Map([]),")
    None => ()
  }
  line(out, ") -> " + model.name + " {")
  let names : Array[String] = []
  for field in model.fields {
    names.push(escape_moonbit(field.name))
  }
  match model.additional_properties_field {
    Some(name) => names.push(escape_moonbit(name))
    None => ()
  }
  if names.length() == 0 {
    line(out, "  { }")
  } else {
    let mut inline = "{ "
    for index, name in names {
      if index > 0 {
        inline += ", "
      }
      inline += name
    }
    if names.length() == 1 {
      inline += ","
    }
    inline += " }"
    if inline.length() + 2 <= 80 {
      line(out, "  " + inline)
    } else {
      line(out, "  {")
      for name in names {
        line(out, "    " + name + ",")
      }
      line(out, "  }")
    }
  }
  line(out, "}")
  line(out, "")
}

///|
fn emit_struct_encoder(out : StringBuilder, model : StructModelIr) -> Unit {
  line(out, "///|")
  line(
    out,
    "pub impl ToJson for " +
    model.name +
    " with fn to_json(self : " +
    model.name +
    ") -> Json {",
  )
  line(out, "  let __m : Map[String, Json] = Map([])")
  for field in model.fields {
    let wire = quoted(field.wire_name)
    let mn = escape_moonbit(field.name)
    let value = "self." + mn
    match field.presence {
      "required" =>
        line(
          out,
          "  __put(__m, " +
          wire +
          ", " +
          encode_expr(field.type_ref, value) +
          ")",
        )
      "required_nullable" => {
        line(out, "  match " + value + " {")
        line(
          out,
          "    Some(value) => __put(__m, " +
          wire +
          ", " +
          encode_expr(field.type_ref, "value") +
          ")",
        )
        line(out, "    None => __put(__m, " + wire + ", Json::null())")
        line(out, "  }")
      }
      "optional" => {
        line(out, "  match " + value + " {")
        line(
          out,
          "    Some(value) => __put(__m, " +
          wire +
          ", " +
          encode_expr(field.type_ref, "value") +
          ")",
        )
        line(out, "    None => ()")
        line(out, "  }")
      }
      "optional_nullable" => {
        line(out, "  match " + value + " {")
        line(out, "    Unset => ()")
        line(out, "    Null => __put(__m, " + wire + ", Json::null())")
        line(
          out,
          "    Value(value) => __put(__m, " +
          wire +
          ", " +
          encode_expr(field.type_ref, "value") +
          ")",
        )
        line(out, "  }")
      }
      _ => abort("validated field has an unsupported presence")
    }
  }
  match model.additional_properties_field {
    Some(name) => {
      let en = escape_moonbit(name)
      line(out, "  for key, value in self." + en + " {")
      line(out, "    if !__m.contains(key) {")
      line(out, "      __put(__m, key, value)")
      line(out, "    }")
      line(out, "  }")
    }
    None => ()
  }
  line(out, "  Json::object(__m)")
  line(out, "}")
  emit_trait_extensions(out, model.name, ["ToJson"])
  line(out, "")
}

///|
fn emit_declared_map(out : StringBuilder, model : StructModelIr) -> Unit {
  if model.fields.length() == 0 {
    line(out, "  let __d : Map[String, Bool] = Map([])")
  } else {
    line(out, "  let __d : Map[String, Bool] = Map([")
    for field in model.fields {
      line(out, "    (" + quoted(field.wire_name) + ", true),")
    }
    line(out, "  ])")
  }
}

///|
fn emit_field_decoder(
  out : StringBuilder,
  field : FieldIr,
  index : Int,
) -> Unit {
  let field_name = "__f" + index.to_string()
  let path_name = "__p" + index.to_string()
  let value_name = "__v" + index.to_string()
  let wire = quoted(field.wire_name)
  line(out, "  let " + path_name + " = path.add_key(" + wire + ")")
  line(out, "  let " + value_name + " = __m.get(" + wire + ")")
  line(out, "  let " + field_name + " = match " + value_name + " {")
  match field.presence {
    "required" => {
      line(
        out,
        "    Some(Null) => raise __error(" +
        path_name +
        ", \"required property must not be null\")",
      )
      line(
        out,
        "    Some(value) => " + decode_expr(field.type_ref, "value", path_name),
      )
      line(
        out,
        "    None => raise __error(" +
        path_name +
        ", \"missing required property\")",
      )
    }
    "required_nullable" => {
      line(out, "    Some(Null) => None")
      line(
        out,
        "    Some(value) => Some(" +
        decode_expr(field.type_ref, "value", path_name) +
        ")",
      )
      line(
        out,
        "    None => raise __error(" +
        path_name +
        ", \"missing required property\")",
      )
    }
    "optional" => {
      line(
        out,
        "    Some(Null) => raise __error(" +
        path_name +
        ", \"optional property must not be null\")",
      )
      line(
        out,
        "    Some(value) => Some(" +
        decode_expr(field.type_ref, "value", path_name) +
        ")",
      )
      line(out, "    None => None")
    }
    "optional_nullable" => {
      line(out, "    Some(Null) => Null")
      line(
        out,
        "    Some(value) => Value(" +
        decode_expr(field.type_ref, "value", path_name) +
        ")",
      )
      line(out, "    None => Unset")
    }
    _ => abort("validated field has an unsupported presence")
  }
  line(out, "  }")
}

///|
fn emit_record_value(
  out : StringBuilder,
  model : StructModelIr,
  additional_name : String?,
) -> Unit {
  let names : Array[String] = []
  for index, field in model.fields {
    let mn = escape_moonbit(field.name)
    names.push(mn + ": __f" + index.to_string())
  }
  match additional_name {
    Some(name) => {
      let en = escape_moonbit(name)
      names.push(en + ": __x")
    }
    None => ()
  }
  if names.length() == 0 {
    line(out, "  " + "{ }")
  } else {
    let mut inline = "{ "
    for index, name in names {
      if index > 0 {
        inline += ", "
      }
      inline += name
    }
    inline += " }"
    if inline.length() + 2 <= 80 {
      line(out, "  " + inline)
    } else {
      line(out, "  {")
      for name in names {
        line(out, "    " + name + ",")
      }
      line(out, "  }")
    }
  }
}

///|
fn emit_struct_decoder(out : StringBuilder, model : StructModelIr) -> Unit {
  line(out, "///|")
  line(
    out,
    "pub impl FromJson for " + model.name + " with fn from_json(json, path) {",
  )
  line(out, "  let __m : Map[String, Json] = match json {")
  line(out, "    Object(fields) => fields")
  line(out, "    _ => raise __error(path, \"expected a JSON object\")")
  line(out, "  }")
  emit_declared_map(out, model)
  for index, field in model.fields {
    emit_field_decoder(out, field, index)
  }
  match model.additional_properties_field {
    Some(name) => {
      line(out, "  let __x : Map[String, Json] = Map([])")
      line(out, "  for key, value in __m {")
      line(out, "    if !__d.contains(key) {")
      line(out, "      __x[key] = value")
      line(out, "    }")
      line(out, "  }")
      emit_record_value(out, model, Some(name))
    }
    None => {
      line(out, "  for key, _ in __m {")
      line(out, "    if !__d.contains(key) {")
      line(out, "      raise __error(path.add_key(key), \"unknown property\")")
      line(out, "    }")
      line(out, "  }")
      emit_record_value(out, model, None)
    }
  }
  line(out, "}")
  emit_trait_extensions(out, model.name, ["@moonbitlang/core/json.FromJson"])
  line(out, "")
}

///|
fn emit_struct(out : StringBuilder, model : StructModelIr) -> Unit {
  emit_struct_declaration(out, model)
  if model.fields.length() == 0 && model.additional_properties_field is None {
    return
  }
  emit_struct_constructor(out, model)
  emit_struct_encoder(out, model)
  emit_struct_decoder(out, model)
}

///|
fn emit_models(api : ApiIr) -> String {
  let out = StringBuilder()
  line(out, "///|")
  line(out, "/// Generated model types and JSON codecs. Do not edit by hand.")
  line(out, "")
  emit_runtime_helpers(out)
  emit_int64_helpers(out, api)
  for model in api.models {
    match model {
      EnumModel(value) => emit_enum(out, value)
      StructModel(value) => emit_struct(out, value)
    }
  }
  out.to_string().trim_end(chars="\n").to_owned() + "\n"
}

///|
fn module_file(module_name : String, has_operations : Bool) -> String {
  let mut result = "name = " +
    quoted(module_name) +
    "\n" +
    "\n" +
    "version = \"0.1.0\"\n"
  if has_operations {
    // Generated operations reach the network through the runtime transport,
    // which is built on moonbitlang/async/http.
    result += "\nimport {\n  \"moonbitlang/async@0.20.2\",\n}\n"
  }
  result + "\npreferred_target = \"native\"\n"
}

///|
fn path_join(directory : String, file : String) -> String {
  if directory.has_suffix("/") || directory.has_suffix("\\") {
    directory + file
  } else {
    directory + "/" + file
  }
}

// ---------------------------------------------------------------------------
// String helpers
// ---------------------------------------------------------------------------

///|
fn join_strings(parts : Array[String], sep : String) -> String {
  let out = StringBuilder()
  for i, part in parts {
    if i > 0 {
      out.write_string(sep)
    }
    out.write_string(part)
  }
  out.to_string()
}
// ---------------------------------------------------------------------------
// Operation codegen helpers
// ---------------------------------------------------------------------------

///|
fn pascal_from_snake(snake : String) -> String {
  let out = StringBuilder()
  let mut upper_next = true
  for ch in snake {
    if ch == '_' {
      upper_next = true
    } else if upper_next && ch >= 'a' && ch <= 'z' {
      out.write_char(Int::unsafe_to_char(ch.to_int() - 32))
      upper_next = false
    } else {
      out.write_char(ch)
      upper_next = false
    }
  }
  out.to_string()
}

///|
fn response_enum_name(op : OperationIr) -> String {
  op.response_name
}

///|
fn success_status_list(op : OperationIr) -> Array[Int] {
  let out : Array[Int] = []
  for r in op.success_responses {
    out.push(r.status)
  }
  if out.length() == 0 {
    out.push(200)
  }
  out
}

///|
fn int_list_to_moon(ints : Array[Int]) -> String {
  let parts : Array[String] = []
  for n in ints {
    parts.push(n.to_string())
  }
  "[" + join_strings(parts, ", ") + "]"
}

// ---------------------------------------------------------------------------
// Path expression builder
// ---------------------------------------------------------------------------

///|
fn build_path_expr(op : OperationIr) -> String {
  let path = op.path
  let parts : Array[String] = []
  let mut buf = StringBuilder()
  let mut in_brace = false
  let mut brace_buf = StringBuilder()
  for ch in path {
    if ch == '{' {
      let lit = buf.to_string()
      if lit.length() > 0 {
        parts.push(quoted(lit))
        buf = StringBuilder()
      }
      in_brace = true
      brace_buf = StringBuilder()
    } else if ch == '}' {
      in_brace = false
      let wire_name = brace_buf.to_string()
      let mut found = ""
      for p in op.parameters {
        if p.wire_name == wire_name {
          found = escape_moonbit(p.name)
        }
      }
      if found.length() > 0 {
        let mut array = false
        for p in op.parameters {
          if p.wire_name == wire_name && p.type_ref.kind == "array" {
            array = true
          }
        }
        if array {
          parts.push("encode_path_array(" + found + ".map(v => v.to_string()))")
        } else {
          parts.push("encode_path_value(" + found + ".to_string())")
        }
      } else {
        parts.push(quoted("{" + wire_name + "}"))
      }
    } else if in_brace {
      brace_buf.write_char(ch)
    } else {
      buf.write_char(ch)
    }
  }
  let lit = buf.to_string()
  if lit.length() > 0 {
    parts.push(quoted(lit))
  }
  if parts.length() == 0 {
    quoted("")
  } else if parts.length() == 1 {
    parts[0]
  } else {
    join_strings(parts, " + ")
  }
}

// ---------------------------------------------------------------------------
// Operation emission
// ---------------------------------------------------------------------------

///|
fn variant_name(v : ResponseVariant) -> String {
  "S" + v.status.to_string()
}

///|
fn emit_operation(out : StringBuilder, op : OperationIr, api : ApiIr) -> Unit {
  line(out, "///|")
  line(out, "/// `" + op.http_method + " " + op.path + "`")
  line(out, "pub async fn Client::" + op.fn_name + "(")
  line(out, "  self : Client,")
  let has_body = match op.request_body {
    Some(body) =>
      match body.type_ref {
        Some(_) => true
        None => false
      }
    None => false
  }
  let body_name = match op.body_name {
    Some(name) => name
    None => "body"
  }
  let param_lines : Array[String] = []
  for p in op.parameters {
    let mn = escape_moonbit(p.name)
    match p.presence {
      "required" =>
        param_lines.push("  " + mn + " : " + render_type(p.type_ref))
      "required_nullable" =>
        param_lines.push("  " + mn + " : " + render_type(p.type_ref) + "?")
      "optional" =>
        param_lines.push("  " + mn + "? : " + render_type(p.type_ref))
      "optional_nullable" =>
        param_lines.push(
          "  " + mn + "? : Presence[" + render_type(p.type_ref) + "] = Unset",
        )
      _ => abort("validated parameter has an unsupported presence")
    }
  }
  if has_body {
    match op.request_body {
      Some(body) =>
        match body.type_ref {
          Some(tr) => {
            let btype = render_type(tr)
            if body.required {
              param_lines.push("  " + body_name + " : " + btype)
            } else {
              param_lines.push("  " + body_name + "? : " + btype)
            }
          }
          None => ()
        }
      None => ()
    }
  }
  for pline in param_lines {
    line(out, pline + ",")
  }
  let ret_type = match op.response_strategy {
    SingleResult(tr) => render_type(tr)
    UnitResult => "Unit"
    NoContent => "Unit"
    ResponseEnum(_) => response_enum_name(op)
    UnsupportedMediaType(mt) =>
      abort("unsupported media type in codegen: " + mt)
  }
  line(out, ") -> " + ret_type + " raise SdkError {")
  if op.security.length() > 0 {
    let groups : Array[String] = []
    for group in op.security {
      let schemes : Array[String] = []
      for name in group {
        let mut kind = name
        let mut key = ""
        let mut loc = ""
        for scheme in api.auth_schemes {
          if scheme.name == name {
            kind = scheme.kind
            key = scheme.key_name.unwrap_or("")
            loc = scheme.location.unwrap_or("")
          }
        }
        schemes.push(
          "(" +
          quoted(name) +
          ", " +
          quoted(kind) +
          ", " +
          quoted(key) +
          ", " +
          quoted(loc) +
          ")",
        )
      }
      groups.push("[" + join_strings(schemes, ", ") + "]")
    }
    line(
      out,
      "  let requirements = select_security(self.config, [" +
      join_strings(groups, ", ") +
      "], operation_id=" +
      quoted(op.operation_id) +
      ")",
    )
    line(
      out,
      "  let headers = auth_headers(self.config, " +
      "requirements" +
      ", operation_id=" +
      quoted(op.operation_id) +
      ")",
    )
  } else {
    line(out, "  let headers : Map[String, String] = Map([])")
  }
  for p in op.parameters {
    if p.location is HeaderLoc {
      emit_wire_parameter(out, p, false)
    }
  }
  if has_body {
    match op.request_body {
      Some(body) =>
        match body.media_type {
          Some(mt) =>
            line(
              out,
              "  headers[" + quoted("Content-Type") + "] = " + quoted(mt),
            )
          None => ()
        }
      None => ()
    }
  }
  let has_joined_query = op.parameters.any(p => {
    p.location == QueryLoc && p.type_ref.kind == "array" && !p.explode
  })
  if has_joined_query {
    line(out, "  let joined_query : Array[(String, Array[String])] = []")
  }
  let has_query = op.parameters.any(p => p.location == QueryLoc)
  if has_query {
    line(out, "  let query : Array[(String, String)] = []")
    for p in op.parameters {
      if p.location is QueryLoc {
        emit_wire_parameter(out, p, true)
      }
    }
  }
  if op.security.length() > 0 {
    if !has_query {
      line(out, "  let query : Array[(String, String)] = []")
    }
    line(
      out,
      "  for pair in auth_query(self.config, " +
      "requirements" +
      ", operation_id=" +
      quoted(op.operation_id) +
      ") {",
    )
    line(out, "    query.push(pair)")
    line(out, "  }")
  }
  let path_expr = build_path_expr(op)
  let http_method_str = quoted(op.http_method)
  // Determine if body is optional
  let sends_query = has_query || op.security.length() > 0
  let body_optional : Bool = if has_body {
    match op.request_body {
      Some(body) => !body.required
      None => false
    }
  } else {
    false
  }
  if body_optional {
    line(out, "  let request = match " + body_name + " {")
    let mut with_args = http_method_str + ", " + path_expr
    if sends_query {
      with_args += ", query~"
    }
    if has_joined_query {
      with_args += ", joined_query~"
    }
    with_args += ", headers~"
    line(
      out,
      "    Some(v) => Request::new(" + with_args + ", body=encode_json(v))",
    )
    line(out, "    None => Request::new(" + with_args + ")")
    line(out, "  }")
  } else {
    let mut req_str = "  let request = Request::new(" +
      http_method_str +
      ", " +
      path_expr
    if sends_query {
      req_str += ", query~"
    }
    if has_joined_query {
      req_str += ", joined_query~"
    }
    req_str += ", headers~"
    if has_body {
      match op.request_body {
        Some(body) =>
          match body.type_ref {
            Some(_) =>
              if body.required {
                req_str += ", body=encode_json(" + body_name + ")"
              }
            None => ()
          }
        None => ()
      }
    }
    req_str += ")"
    line(out, req_str)
  }
  line(
    out,
    "  let response = self.send_request(request, " +
    quoted(op.operation_id) +
    ")",
  )
  let statuses = success_status_list(op)
  line(
    out,
    "  expect_status(response, " +
    int_list_to_moon(statuses) +
    ", operation_id=" +
    quoted(op.operation_id) +
    ")",
  )
  match op.response_strategy {
    SingleResult(tr) =>
      if is_int64_scalar(tr) {
        line(
          out,
          "  decode_int64(response, operation_id=" +
          quoted(op.operation_id) +
          ")",
        )
      } else {
        line(
          out,
          "  (decode_json(response, operation_id=" +
          quoted(op.operation_id) +
          ") : " +
          render_type(tr) +
          ")",
        )
      }
    UnitResult => line(out, "  ()")
    NoContent => line(out, "  ()")
    ResponseEnum(variants) => {
      line(out, "  match response.status {")
      for v in variants {
        line(out, "    " + v.status.to_string() + " => {")
        let tname = render_type(v.type_ref)
        if tname == "Unit" {
          line(
            out,
            "      " + response_enum_name(op) + "::" + variant_name(v) + "(())",
          )
          line(out, "    }")
          continue
        }
        line(
          out,
          "      " + response_enum_name(op) + "::" + variant_name(v) + "(",
        )
        if is_int64_scalar(v.type_ref) {
          line(
            out,
            "        decode_int64(response, operation_id=" +
            quoted(op.operation_id) +
            "),",
          )
        } else {
          line(
            out,
            "        (decode_json(response, operation_id=" +
            quoted(op.operation_id) +
            ") : " +
            tname +
            "),",
          )
        }
        line(out, "      )")
        line(out, "    }")
      }
      line(
        out,
        "    _ => raise Http(" +
        quoted(op.operation_id) +
        ", response.status, response.headers, response.body)",
      )
      line(out, "  }")
    }
    UnsupportedMediaType(mt) =>
      abort("unsupported media type in codegen: " + mt)
  }
  line(out, "}")
  line(out, "")
}

///|
fn emit_response_enums(out : StringBuilder, api : ApiIr) -> Unit {
  for op in api.operations {
    match op.response_strategy {
      ResponseEnum(variants) => {
        let ename = response_enum_name(op)
        line(out, "///|")
        line(out, "pub enum " + ename + " {")
        for v in variants {
          line(
            out,
            "  " + variant_name(v) + "(" + render_type(v.type_ref) + ")",
          )
        }
        line(out, "} derive(Debug)")
        emit_trait_extensions(out, ename, ["@moonbitlang/core/debug.Debug"])
        line(out, "")
      }
      _ => ()
    }
  }
}

///|
fn emit_client(api : ApiIr) -> String {
  let out = StringBuilder()
  line(out, "///|")
  line(out, "/// Generated typed API client. Do not edit by hand.")
  line(out, "")
  emit_response_enums(out, api)
  line(out, "///|")
  line(out, "pub struct Client {")
  line(out, "  config : Config")
  line(out, "  capture : CaptureTransport?")
  line(out, "} derive(Debug)")
  emit_trait_extensions(out, "Client", ["@moonbitlang/core/debug.Debug"])
  line(out, "")
  line(out, "///|")
  line(out, "/// Create a client.")
  line(out, "///")
  line(
    out, "/// Without `capture` every operation performs real HTTP through the",
  )
  line(
    out, "/// runtime transport. Supplying a `capture` transport keeps the same",
  )
  line(out, "/// generated methods but replays an in-memory response instead.")
  line(out, "pub fn Client::new(")
  let mut default_url = ""
  for server in api.servers {
    if default_url == "" &&
      (server.has_prefix("http://") || server.has_prefix("https://")) &&
      !server.contains("{") {
      default_url = server
    }
  }
  line(out, "  base_url? : String = " + quoted(default_url) + ",")
  line(out, "  bearer_token? : String,")
  line(out, "  basic_username? : String,")
  line(out, "  basic_password? : String,")
  line(out, "  api_key_name? : String,")
  line(out, "  api_key_value? : String,")
  line(out, "  api_key_location? : String,")
  line(out, "  capture? : CaptureTransport,")
  line(out, ") -> Client {")
  line(
    out, "  let config = Config::new(base_url, bearer_token?, basic_username?, basic_password?, api_key_name?, api_key_value?, api_key_location?)",
  )
  line(out, "  { config, capture }")
  line(out, "}")
  line(out, "")
  line(out, "///|")
  line(out, "/// The single place generated operations obtain a response.")
  line(out, "async fn Client::send_request(")
  line(out, "  self : Client,")
  line(out, "  request : Request,")
  line(out, "  operation_id : String,")
  line(out, ") -> Response raise SdkError {")
  line(out, "  match self.capture {")
  line(out, "    Some(transport) => transport.send(request)")
  line(out, "    None => transmit(self.config, request, operation_id~)")
  line(out, "  }")
  line(out, "}")
  line(out, "")
  for op in api.operations {
    emit_operation(out, op, api)
  }
  out.to_string().trim_end(chars="\n").to_owned() + "\n"
}

// ---------------------------------------------------------------------------
// Updated package/main functions
// ---------------------------------------------------------------------------

///|
fn api_uses_int64(api : ApiIr) -> Bool {
  for model in api.models {
    match model {
      EnumModel(_) => ()
      StructModel(value) =>
        for field in value.fields {
          if contains_int64(field.type_ref) {
            return true
          }
        }
    }
  }
  for op in api.operations {
    for p in op.parameters {
      if contains_int64(p.type_ref) {
        return true
      }
    }
    match op.request_body {
      Some(body) =>
        match body.type_ref {
          Some(tr) => if contains_int64(tr) { return true }
          None => ()
        }
      None => ()
    }
    match op.response_strategy {
      SingleResult(tr) => if contains_int64(tr) { return true }
      ResponseEnum(variants) =>
        for v in variants {
          if contains_int64(v.type_ref) {
            return true
          }
        }
      _ => ()
    }
  }
  false
}

///|
fn api_has_operations(api : ApiIr) -> Bool {
  api.operations.length() > 0
}

///|
fn package_file(needs_string : Bool, has_operations : Bool) -> String {
  let imports : Array[String] = []
  imports.push("\"moonbitlang/core/debug\"")
  imports.push("\"moonbitlang/core/json\"")
  if has_operations {
    imports.push("\"moonbitlang/core/encoding/utf8\"")
    imports.push("\"moonbitlang/async/http\"")
  }
  if needs_string {
    imports.push("\"moonbitlang/core/string\"")
  }
  let mut result = "import {\n"
  for imp in imports {
    result += "  " + imp + ",\n"
  }
  result += "}\n"
  // A test-only `moonbitlang/async` import is deliberately *not* emitted here:
  // `async test` needs it, but a package without tests would then carry an
  // unused import. Whoever adds tests adds the import.
  result += "\nsupported_targets = \"+native\"\n"
  result
}

///|
fn main raise {
  let args = @env.args()
  guard args.length() >= 3 else {
    println("usage: oas2moon-codegen <canonical-ir.json> <output-dir>")
    @sys.exit(2)
    return
  }
  let source = @fs.read_file_to_string(args[1])
  let api = parse_api(@json.parse(source))
  @fs.write_string_to_file(
    path_join(args[2], "moon.mod"),
    module_file(api.module_name, api_has_operations(api)),
  )
  @fs.write_string_to_file(
    path_join(args[2], "moon.pkg"),
    package_file(api_uses_int64(api), api_has_operations(api)),
  )
  @fs.write_string_to_file(path_join(args[2], "models.mbt"), emit_models(api))
  if api_has_operations(api) {
    @fs.write_string_to_file(path_join(args[2], "client.mbt"), emit_client(api))
  }
}

///|
fn emit_wire_parameter(
  out : StringBuilder,
  p : ParameterIr,
  query : Bool,
) -> Unit {
  let mn = escape_moonbit(p.name)
  let optional = p.presence != "required"
  let value = if optional { "v" } else { mn }
  if optional {
    line(out, "  match " + mn + " {")
    if p.presence == "optional_nullable" {
      line(out, "    Unset | Null => ()")
      line(out, "    Value(v) => {")
    } else {
      line(out, "    None => ()")
      line(out, "    Some(v) => {")
    }
  }
  let wire = quoted(p.wire_name)
  if query && p.type_ref.kind == "array" && p.explode {
    line(
      out,
      "    for item in " +
      value +
      " { query.push((" +
      wire +
      ", " +
      parameter_scalar_wire(p.type_ref.item.unwrap(), "item") +
      ")) }",
    )
  } else if query && p.type_ref.kind == "array" {
    line(
      out,
      "    joined_query.push((" +
      wire +
      ", " +
      value +
      ".map(item => " +
      parameter_scalar_wire(p.type_ref.item.unwrap(), "item") +
      ")))",
    )
  } else {
    let expr = if p.type_ref.kind == "array" {
      "encode_header_array(" +
      value +
      ".map(item => " +
      parameter_scalar_wire(p.type_ref.item.unwrap(), "item") +
      "))"
    } else {
      parameter_scalar_wire(p.type_ref, value)
    }
    if query {
      line(out, "    query.push((" + wire + ", " + expr + "))")
    } else {
      line(out, "    headers[" + wire + "] = " + expr)
    }
  }
  if optional {
    line(out, "    }")
    line(out, "  }")
  }
}

///|
fn parameter_scalar_wire(type_ref : TypeRef, value : String) -> String {
  if type_ref.kind == "named" {
    value + ".to_wire()"
  } else {
    value + ".to_string()"
  }
}
