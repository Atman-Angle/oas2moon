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
    line(out, "  if json is String(s) {")
    line(out, "    @string.parse_int64(s) catch {")
    line(
      out, "      _ => raise __error(path, \"integer value is out of range for Int64\")",
    )
    line(out, "    }")
    line(out, "  } else {")
    line(out, "    match json {")
    line(
      out, "      Number(n, ..) if !n.is_nan() && !n.is_inf() && n == n.trunc() => {",
    )
    line(out, "        let max_bound = 9223372036854775807L.to_double()")
    line(out, "        let min_bound = (-9223372036854775808L).to_double()")
    line(out, "        if n > max_bound || n < min_bound {")
    line(
      out, "          raise __error(path, \"integer value is out of range for Int64\")",
    )
    line(out, "        }")
    line(out, "        n.to_int64()")
    line(out, "      }")
    line(
      out, "      _ => raise __error(path, \"expected an integer (JSON number)\")",
    )
    line(out, "    }")
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
fn emit_enum(out : StringBuilder, model : EnumModelIr) -> Unit {
  line(out, "///|")
  line(out, "pub(all) enum " + model.name + " {")
  for enum_member in model.members {
    line(out, "  " + enum_member.name)
  }
  line(out, "} derive(Eq, Debug)")
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
fn module_file(module_name : String) -> String {
  "name = " +
  quoted(module_name) +
  "\n" +
  "\n" +
  "version = \"0.1.0\"\n" +
  "\n" +
  "preferred_target = \"native\"\n"
}

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
  false
}

///|
fn package_file(needs_string : Bool) -> String {
  if needs_string {
    "import {\n" +
    "  \"moonbitlang/core/json\",\n" +
    "  \"moonbitlang/core/string\",\n" +
    "}\n" +
    "\n" +
    "supported_targets = \"+native\"\n"
  } else {
    "import {\n" +
    "  \"moonbitlang/core/json\",\n" +
    "}\n" +
    "\n" +
    "supported_targets = \"+native\"\n"
  }
}

///|
fn path_join(directory : String, file : String) -> String {
  if directory.has_suffix("/") || directory.has_suffix("\\") {
    directory + file
  } else {
    directory + "/" + file
  }
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
    module_file(api.module_name),
  )
  @fs.write_string_to_file(
    path_join(args[2], "moon.pkg"),
    package_file(api_uses_int64(api)),
  )
  @fs.write_string_to_file(path_join(args[2], "models.mbt"), emit_models(api))
}
