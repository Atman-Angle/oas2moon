///|
/// Petstore end-to-end driver.
///
/// This executable imports the *generated* SDK package and nothing else from
/// the project: no runtime module, no HTTP library. Every assertion below is
/// therefore a statement about what the generated client actually did on the
/// wire.
///
/// Run with:
///   moon run integration --target native -- <base_url> <token> <user> <pass> <api_key>

///|
/// Collects assertion failures so one failing step does not hide the rest.
struct Report {
  mut passed : Int
  failures : Array[String]
} derive(Debug)

///|
fn Report::new() -> Report {
  { passed: 0, failures: [] }
}

///|
fn Report::check(self : Report, label : String, ok : Bool) -> Unit {
  if ok {
    self.passed = self.passed + 1
  } else {
    self.failures.push(label)
  }
}

///|
fn Report::check_eq(
  self : Report,
  label : String,
  actual : String,
  expected : String,
) -> Unit {
  self.check(
    label + " (expected " + expected + ", got " + actual + ")",
    actual == expected,
  )
}

///|
fn Report::failed(self : Report, label : String, err : @sdk.SdkError) -> Unit {
  self.failures.push(label + " raised " + @debug.to_string(err))
}

///|
fn arg_or(args : Array[String], index : Int, fallback : String) -> String {
  if args.length() > index {
    args[index]
  } else {
    fallback
  }
}

///|
async fn main {
  let args = @env.args()
  let base_url = arg_or(args, 1, "http://127.0.0.1:18080")
  let token = arg_or(args, 2, "demo-token")
  let basic_user = arg_or(args, 3, "demo-user")
  let basic_password = arg_or(args, 4, "demo-pass")
  let api_key = arg_or(args, 5, "demo-api-key")

  let report = Report::new()

  // ---- bearer CRUD -------------------------------------------------------
  let client = @sdk.Client::new(base_url=base_url, bearer_token=token)

  let get_outcome : Result[@sdk.Pet, @sdk.SdkError] = Ok(
    client.get_pet_by_id(42L, "trace-get", verbose=true),
  ) catch {
    err => Err(err)
  }
  match get_outcome {
    Ok(pet) => {
      report.check_eq("GET pet.id", pet.id.to_string(), "42")
      report.check_eq("GET pet.name", pet.name, "Spike")
      report.check_eq("GET pet.status", pet.status.to_wire(), "available")
      report.check(
        "GET pet.tags has two entries",
        match pet.tags {
          Some(tags) => tags.length() == 2
          None => false
        },
      )
      report.check(
        "GET explicit null decodes to Presence::Null",
        match pet.nickname {
          @sdk.Null => true
          _ => false
        },
      )
    }
    Err(err) => report.failed("GET", err)
  }

  // ---- multiple success schemas become a typed response enum -------------
  let existing_result : Result[
    @sdk.GetPetResultResponse,
    @sdk.SdkError,
  ] = Ok(client.get_pet_result(42L, created=false)) catch {
    err => Err(err)
  }
  match existing_result {
    Ok(@sdk.S200(pet)) =>
      report.check_eq("response enum S200 carries Pet", pet.name, "Spike")
    Ok(@sdk.S201(_)) => report.failures.push("expected response enum S200")
    Err(err) => report.failed("response enum S200", err)
  }

  let created_result : Result[
    @sdk.GetPetResultResponse,
    @sdk.SdkError,
  ] = Ok(client.get_pet_result(42L, created=true)) catch {
    err => Err(err)
  }
  match created_result {
    Ok(@sdk.S201(created)) =>
      report.check_eq(
        "response enum S201 carries CreatedPetResponse",
        created.created_at,
        "2026-09-18T00:00:00Z",
      )
    Ok(@sdk.S200(_)) => report.failures.push("expected response enum S201")
    Err(err) => report.failed("response enum S201", err)
  }

  // ---- unexpected response media type fails explicitly ------------------
  let media_mismatch : Result[@sdk.Pet, @sdk.SdkError] = Ok(
    client.get_media_mismatch(),
  ) catch {
    err => Err(err)
  }
  match media_mismatch {
    Ok(_) => report.failures.push("media mismatch unexpectedly decoded")
    Err(err) =>
      report.check(
        "non-JSON response media type becomes Unsupported",
        match err {
          @sdk.Unsupported(op, msg) =>
            op == "getMediaMismatch" && msg.contains("text/plain")
          _ => false
        },
      )
  }

  let new_pet = @sdk.Pet::new(99L, "Created", @sdk.Available, tags=["a", "b"])
  let post_outcome : Result[@sdk.Pet, @sdk.SdkError] = Ok(client.add_pet(new_pet)) catch {
    err => Err(err)
  }
  match post_outcome {
    Ok(created) => {
      report.check_eq("POST pet.id", created.id.to_string(), "99")
      report.check_eq("POST pet.name", created.name, "Created")
      report.check_eq("POST pet.status", created.status.to_wire(), "available")
    }
    Err(err) => report.failed("POST", err)
  }

  let delete_outcome : Result[Unit, @sdk.SdkError] = Ok(client.delete_pet()) catch {
    err => Err(err)
  }
  match delete_outcome {
    Ok(_) => report.check("DELETE accepted 204", true)
    Err(err) => report.failed("DELETE", err)
  }

  // ---- every V1 authentication scheme ------------------------------------
  let bearer_outcome : Result[@sdk.AuthEcho, @sdk.SdkError] = Ok(
    client.check_bearer_auth(),
  ) catch {
    err => Err(err)
  }
  match bearer_outcome {
    Ok(echo) => report.check_eq("bearer auth accepted", echo.scheme, "bearer")
    Err(err) => report.failed("bearer auth", err)
  }

  let basic_client = @sdk.Client::new(
    base_url=base_url,
    basic_username=basic_user,
    basic_password=basic_password,
  )
  let basic_outcome : Result[@sdk.AuthEcho, @sdk.SdkError] = Ok(
    basic_client.check_basic_auth(),
  ) catch {
    err => Err(err)
  }
  match basic_outcome {
    Ok(echo) => report.check_eq("basic auth accepted", echo.scheme, "basic")
    Err(err) => report.failed("basic auth", err)
  }

  let header_key_client = @sdk.Client::new(
    base_url=base_url,
    api_key_name="X-Api-Key",
    api_key_value=api_key,
    api_key_location="header",
  )
  let header_outcome : Result[@sdk.AuthEcho, @sdk.SdkError] = Ok(
    header_key_client.check_api_key_header(),
  ) catch {
    err => Err(err)
  }
  match header_outcome {
    Ok(echo) =>
      report.check_eq("api key (header) accepted", echo.scheme, "apiKey(header)")
    Err(err) => report.failed("api key header", err)
  }

  let query_key_client = @sdk.Client::new(
    base_url=base_url,
    api_key_name="api_key",
    api_key_value=api_key,
    api_key_location="query",
  )
  let query_outcome : Result[@sdk.AuthEcho, @sdk.SdkError] = Ok(
    query_key_client.check_api_key_query(),
  ) catch {
    err => Err(err)
  }
  match query_outcome {
    Ok(echo) =>
      report.check_eq("api key (query) accepted", echo.scheme, "apiKey(query)")
    Err(err) => report.failed("api key query", err)
  }

  // ---- non-2xx surfaces as a structured error ---------------------------
  // A wrong base path makes the generated client issue a request the server
  // does not serve, so the 404 travels back through the SDK error channel.
  let missing_client = @sdk.Client::new(
    base_url=base_url + "/missing",
    bearer_token=token,
  )
  let missing_outcome : Result[@sdk.Pet, @sdk.SdkError] = Ok(
    missing_client.get_pet_by_id(42L, "trace-get", verbose=true),
  ) catch {
    err => Err(err)
  }
  match missing_outcome {
    Ok(_) => report.failures.push("404 probe unexpectedly succeeded")
    Err(err) =>
      report.check(
        "non-2xx becomes Http(404) with the operation id",
        match err {
          @sdk.Http(op, status, _, _) => status == 404 && op == "getPetById"
          _ => false
        },
      )
  }

  // ---- missing credential is a configuration fault ----------------------
  let anonymous_client = @sdk.Client::new(base_url=base_url)
  let config_outcome : Result[@sdk.AuthEcho, @sdk.SdkError] = Ok(
    anonymous_client.check_bearer_auth(),
  ) catch {
    err => Err(err)
  }
  match config_outcome {
    Ok(_) => report.failures.push("missing credential unexpectedly succeeded")
    Err(err) =>
      report.check(
        "missing credential becomes Configuration",
        match err {
          @sdk.Configuration(_, _) => true
          _ => false
        },
      )
  }

  // ---- rejected credential is an HTTP error, not a crash ----------------
  let bad_client = @sdk.Client::new(base_url=base_url, bearer_token="wrong-token")
  let rejected_outcome : Result[@sdk.Pet, @sdk.SdkError] = Ok(
    bad_client.get_pet_by_id(1L, "trace-get", verbose=true),
  ) catch {
    err => Err(err)
  }
  match rejected_outcome {
    Ok(_) => report.failures.push("rejected credential unexpectedly succeeded")
    Err(err) =>
      report.check(
        "rejected credential becomes Http(401)",
        match err {
          @sdk.Http(_, status, _, _) => status == 401
          _ => false
        },
      )
  }

  println("e2e checks passed: " + report.passed.to_string())
  for failure in report.failures {
    println("e2e FAILURE: " + failure)
  }
  if report.failures.length() > 0 {
    abort("petstore end-to-end driver failed")
  }
  println("e2e verdict: PASS")
}
