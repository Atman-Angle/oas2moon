///|
/// Generated client for the `Spike Petstore` API.
pub struct Client {
  config : @runtime.Config
}

///|
/// Create a client. `base_url` overrides the first server declared by the spec.
pub fn Client::new(base_url : String, bearer_token? : String) -> Client {
  { config: @runtime.Config::new(base_url, bearer_token?) }
}

///|
/// `GET /pets/{id}`
pub async fn Client::get_pet_by_id(
  self : Client,
  id : Int64,
  x_trace : String,
  verbose? : Bool,
) -> Pet raise @runtime.SdkError {
  let headers = @runtime.auth_headers(self.config, ["bearer"])
  headers["X-Trace"] = x_trace
  let query : Array[(String, String)] = []
  match verbose {
    Some(value) => query.push(("verbose", value.to_string()))
    None => ()
  }
  let request = @runtime.Request::new(
    "GET",
    "/pets/" + @runtime.encode_path_segment(id.to_string()),
    query~,
    headers~,
  )
  let response = @runtime.transmit(self.config, request)
  @runtime.expect_status(response, [200])
  @runtime.decode_json(response)
}

///|
/// `POST /pets`
pub async fn Client::add_pet(
  self : Client,
  pet : Pet,
) -> Pet raise @runtime.SdkError {
  let headers = @runtime.auth_headers(self.config, ["bearer"])
  headers["Content-Type"] = "application/json"
  let request = @runtime.Request::new(
    "POST",
    "/pets",
    headers~,
    body=@json.to_json(pet),
  )
  let response = @runtime.transmit(self.config, request)
  @runtime.expect_status(response, [201])
  @runtime.decode_json(response)
}

///|
/// `DELETE /pets`
pub async fn Client::delete_pet(self : Client) -> Unit raise @runtime.SdkError {
  let headers = @runtime.auth_headers(self.config, ["bearer"])
  let request = @runtime.Request::new("DELETE", "/pets", headers~)
  let response = @runtime.transmit(self.config, request)
  @runtime.expect_status(response, [204])
}
