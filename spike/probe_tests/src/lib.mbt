pub(all) enum PetStatus {
  Available
  Pending
  Sold
} derive(Eq, Debug)

pub impl ToJson for PetStatus with fn to_json(self : PetStatus) -> Json {
  match self {
    Available => Json::string("available")
    Pending => Json::string("pending")
    Sold => Json::string("sold")
  }
}

pub impl FromJson for PetStatus with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> PetStatus raise @json.JsonDecodeError {
  let text : String = @json.from_json(json) catch {
    _ => raise @json.JsonDecodeError((path, "expected a string"))
  }
  match text {
    "available" => Available
    "pending" => Pending
    "sold" => Sold
    _ => raise @json.JsonDecodeError((path, "unknown wire value"))
  }
}

pub fn sample_json() -> Json {
  let fields : Map[String, Json] = Map([])
  fields["id"] = @json.to_json(1L)
  Json::object(fields)
}
