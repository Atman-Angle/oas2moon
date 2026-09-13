///|
/// Spike-only integration driver: exercises the generated SDK against a real
/// local HTTP server. Not part of the SDK surface.
fn pet_json(pet : @sdk.Pet) -> Json {
  let tags : Array[Json] = []
  match pet.tags {
    Some(values) =>
      for value in values {
        tags.push(Json::string(value))
      }
    None => ()
  }
  let nickname = match pet.nickname {
    Some(value) => Json::string(value)
    None => Json::null()
  }
  Json::object(
    Map([
      ("id", Json::string(pet.id.to_string())),
      ("name", Json::string(pet.name)),
      ("status", Json::string(pet.status.to_wire())),
      ("tags_present", Json::boolean(pet.tags is Some(_))),
      ("tags", Json::array(tags)),
      ("nickname_present", Json::boolean(pet.nickname is Some(_))),
      ("nickname", nickname),
    ]),
  )
}

///|
async fn run_spike() -> Unit raise @runtime.SdkError {
  let args = @env.args()
  let base_url = if args.length() >= 2 {
    args[1]
  } else {
    "http://127.0.0.1:18080"
  }
  let token = if args.length() >= 3 { args[2] } else { "spike-token" }
  let client = @sdk.Client::new(base_url, bearer_token=token)
  let report : Map[String, Json] = Map([])
  let pet = client.get_pet_by_id(42L, "trace-get", verbose=true)
  guard pet.id == 42L else { abort("get: unexpected id") }
  guard pet.name == "Spike" else { abort("get: unexpected name") }
  guard pet.status.to_wire() == "available" else {
    abort("get: unexpected status")
  }
  guard pet.tags.unwrap_or([]).length() == 2 else {
    abort("get: unexpected tags")
  }
  guard pet.nickname is None else {
    abort("get: explicit null should decode to None")
  }
  report["get"] = pet_json(pet)
  let created = client.add_pet(
    @sdk.Pet::new(99L, "Created", @sdk.Available, tags=["a", "b"]),
  )
  guard created.id == 99L else { abort("post: unexpected id") }
  guard created.name == "Created" else { abort("post: unexpected name") }
  guard created.status.to_wire() == "available" else {
    abort("post: unexpected status")
  }
  guard created.tags.unwrap_or([]).length() == 2 else {
    abort("post: unexpected tags")
  }
  report["post"] = pet_json(created)
  client.delete_pet()
  report["delete"] = Json::string("204")
  report["verdict"] = Json::string("ok")
  println(Json::object(report).stringify())
}

///|
async fn main {
  let outcome : Result[Unit, @runtime.SdkError] = Ok(run_spike()) catch {
    err => Err(err)
  }
  match outcome {
    Ok(_) => ()
    Err(err) => {
      println("SPIKE FAILED: " + @debug.to_string(err))
      abort("spike driver failed")
    }
  }
}
