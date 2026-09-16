///|
/// Real HTTP transport for generated SDKs.
///
/// This is the only place in the SDK runtime that touches
/// `moonbitlang/async/http`. Generated operations never import the HTTP
/// library directly: they call `Client::send_request`, which either replays a
/// `CaptureTransport` (unit tests) or delegates here through `transmit`.

///|
/// Map the canonical HTTP method string onto the async HTTP client enum.
///
/// The generator only emits methods from the V1 profile; anything outside it
/// fails loudly rather than silently degrading to GET.
fn request_method(
  name : String,
  operation_id : String,
) -> @http.RequestMethod raise SdkError {
  match name {
    "GET" => @http.Get
    "HEAD" => @http.Head
    "POST" => @http.Post
    "PUT" => @http.Put
    "DELETE" => @http.Delete
    "OPTIONS" => @http.Options
    "TRACE" => @http.Trace
    "PATCH" => @http.Patch
    _ => raise Unsupported(operation_id, "unsupported HTTP method: " + name)
  }
}

///|
/// Render query parameters into a request target suffix.
///
/// Names and values are percent-encoded with the same RFC 3986 rules the path
/// encoder uses, so repeated keys keep their declared order.
///
/// Returns `""` when there is nothing to encode and `"?k=v&k2=v2"` otherwise.
pub fn render_query(params : Array[(String, String)]) -> String {
  if params.length() == 0 {
    return ""
  }
  let encoded : Array[(String, String)] = []
  for pair in params {
    let (key, value) = pair
    encoded.push((percent_encode(key), percent_encode(value)))
  }
  "?" + build_query_string(encoded)
}

///|
/// Perform one request against the origin of `config`.
///
/// The body is already JSON-encoded by the generated operation, so this
/// function only computes `Content-Length` and writes the bytes. Responses with
/// status 204/304 never carry a body, matching the SDK response policy.
///
/// Any I/O failure becomes `Transport`; the HTTP status itself is not judged
/// here, because `expect_status` owns that decision.
pub async fn transmit(
  config : Config,
  request : Request,
  operation_id? : String = "",
) -> Response raise SdkError {
  let target = config.base_path() + request.path + render_query(request.query)
  let headers = request.headers
  match request.body {
    Some(text) =>
      headers["Content-Length"] = @utf8.encode(text).length().to_string()
    None => ()
  }
  try {
    let client = @http.Client::Client(config.origin)
    client.request(
      request_method(request.http_method, operation_id),
      target,
      extra_headers=headers,
    )
    match request.body {
      Some(text) => client.write(text)
      None => ()
    }
    let response = client.end_request()
    let body = if response.code is (204 | 304) {
      ""
    } else {
      client.read_all().text()
    }
    client.close()
    { status: response.code, headers: response.headers, body }
  } catch {
    err => raise Transport(operation_id, err.to_string())
  }
}
