///|
/// Wire values accepted by `PetStatus`.
pub(all) enum PetStatus {
  Available
  Pending
  Sold
} derive(Eq, Debug)

///|
/// The JSON wire value of this enum member.
pub fn PetStatus::to_wire(self : PetStatus) -> String {
  match self {
    Available => "available"
    Pending => "pending"
    Sold => "sold"
  }
}

///|
pub impl ToJson for PetStatus with fn to_json(self : PetStatus) -> Json {
  Json::string(self.to_wire())
}

///|
pub impl FromJson for PetStatus with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> PetStatus raise @json.JsonDecodeError {
  let text : String = @json.from_json(json) catch {
    _ =>
      raise @json.JsonDecodeError(
        (path, "expected a string for enum PetStatus"),
      )
  }
  match text {
    "available" => Available
    "pending" => Pending
    "sold" => Sold
    _ =>
      raise @json.JsonDecodeError(
        (path, "unknown wire value for enum PetStatus"),
      )
  }
}

///|
/// Generated model for `Pet`.
pub(all) struct Pet {
  id : Int64
  name : String
  status : PetStatus
  tags : Array[String]?
  nickname : String?
} derive(Eq, Debug)

///|
/// Build a `Pet`. Optional arguments are omitted from the request body when
/// left as `None`.
pub fn Pet::new(
  id : Int64,
  name : String,
  status : PetStatus,
  tags? : Array[String],
  nickname? : String,
) -> Pet {
  { id, name, status, tags, nickname }
}

///|
/// Optional properties are omitted from the encoded object when absent, so an
/// omitted request field is not sent as an explicit `null`.
pub impl ToJson for Pet with fn to_json(self : Pet) -> Json {
  let fields : Map[String, Json] = Map([])
  fields["id"] = @runtime.int64_to_json(self.id)
  fields["name"] = @json.to_json(self.name)
  fields["status"] = @json.to_json(self.status)
  match self.tags {
    Some(value) => fields["tags"] = @json.to_json(value)
    None => ()
  }
  match self.nickname {
    Some(value) => fields["nickname"] = @json.to_json(value)
    None => ()
  }
  Json::object(fields)
}

///|
/// Hand-written decoder. `derive(FromJson)` cannot be used here because it
/// rejects an explicit JSON `null` instead of mapping it onto `T?`.
pub impl FromJson for Pet with fn from_json(json : Json, path : @json.JsonPath) -> Pet raise @json.JsonDecodeError {
  let fields : Map[String, Json] = match json {
    Object(fields) => fields
    _ => raise @json.JsonDecodeError((path, "expected a JSON object for Pet"))
  }
  let id : Int64 = match fields.get("id") {
    Some(Null) =>
      raise @json.JsonDecodeError(
        (path.add_key("id"), "required property \"id\" is null"),
      )
    Some(value) => @runtime.json_to_int64(value, path.add_key("id"))
    None =>
      raise @json.JsonDecodeError(
        (path.add_key("id"), "missing required property \"id\""),
      )
  }
  let name : String = match fields.get("name") {
    Some(Null) =>
      raise @json.JsonDecodeError(
        (path.add_key("name"), "required property \"name\" is null"),
      )
    Some(value) => @json.from_json(value, path=path.add_key("name"))
    None =>
      raise @json.JsonDecodeError(
        (path.add_key("name"), "missing required property \"name\""),
      )
  }
  let status : PetStatus = match fields.get("status") {
    Some(Null) =>
      raise @json.JsonDecodeError(
        (path.add_key("status"), "required property \"status\" is null"),
      )
    Some(value) => @json.from_json(value, path=path.add_key("status"))
    None =>
      raise @json.JsonDecodeError(
        (path.add_key("status"), "missing required property \"status\""),
      )
  }
  let tags : Array[String]? = match fields.get("tags") {
    Some(Null) => None
    Some(value) => Some(@json.from_json(value, path=path.add_key("tags")))
    None => None
  }
  let nickname : String? = match fields.get("nickname") {
    Some(Null) => None
    Some(value) => Some(@json.from_json(value, path=path.add_key("nickname")))
    None => None
  }
  { id, name, status, tags, nickname }
}
