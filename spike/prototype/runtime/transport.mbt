///|
/// Error surface shared by every generated operation.
pub(all) suberror SdkError {
  MissingCredential(String)
  UnsupportedScheme(String)
  Transport(String)
  Decode(String)
  HttpStatus(Int, String)
} derive(Debug)

///|
/// A transport-neutral request description produced by generated operations.
pub struct Request {
  http_method : String
  path : String
  query : Array[(String, String)]
  headers : Map[String, String]
  body : Json?
}

///|
/// Build a request description.
pub fn Request::new(
  http_method : String,
  path : String,
  query? : Array[(String, String)] = [],
  headers? : Map[String, String] = Map([]),
  body? : Json,
) -> Request {
  { http_method, path, query, headers, body }
}

///|
/// A transport-neutral response description.
pub struct Response {
  status : Int
  body : String
}

///|
/// The HTTP status code of this response.
pub fn Response::status(self : Response) -> Int {
  self.status
}

///|
/// The raw response body of this response.
pub fn Response::body(self : Response) -> String {
  self.body
}

///|
fn request_method(name : String) -> @http.RequestMethod {
  match name {
    "GET" => @http.Get
    "HEAD" => @http.Head
    "POST" => @http.Post
    "PUT" => @http.Put
    "DELETE" => @http.Delete
    "OPTIONS" => @http.Options
    "TRACE" => @http.Trace
    "PATCH" => @http.Patch
    _ => @http.Get
  }
}

///|
/// Perform one HTTP request through `moonbitlang/async/http`.
///
/// This is the single place in the generated SDK that is allowed to touch the
/// transport library. Generated operation code only calls this function.
pub async fn transmit(
  config : Config,
  request : Request,
) -> Response raise SdkError {
  let target = config.base_path() + request.path + render_query(request.query)
  let payload : String? = match request.body {
    Some(body) => {
      let text = body.stringify()
      request.headers["Content-Length"] = @utf8.encode(text)
        .length()
        .to_string()
      Some(text)
    }
    None => None
  }
  try {
    let client = @http.Client::Client(config.origin())
    client.request(
      request_method(request.http_method),
      target,
      extra_headers=request.headers,
    )
    match payload {
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
    { status: response.code, body }
  } catch {
    err => raise Transport(err.to_string())
  }
}

///|
/// Build the authentication headers required by an operation.
pub fn auth_headers(
  config : Config,
  requirements : Array[String],
) -> Map[String, String] raise SdkError {
  let headers : Map[String, String] = Map([])
  for requirement in requirements {
    match requirement {
      "bearer" => {
        let token = match config.bearer_token() {
          Some(token) => token
          None => raise MissingCredential(requirement)
        }
        headers["Authorization"] = "Bearer " + token
      }
      _ => raise UnsupportedScheme(requirement)
    }
  }
  headers
}

///|
/// Raise a structured error unless the status is one of the expected codes.
pub fn expect_status(
  response : Response,
  expected : Array[Int],
) -> Unit raise SdkError {
  if !expected.contains(response.status()) {
    raise HttpStatus(response.status(), response.body())
  }
}

///|
/// Decode a JSON response body into `T`.
pub fn[T : FromJson] decode_json(response : Response) -> T raise SdkError {
  let json : Json = @json.parse(response.body()) catch {
    err => raise Decode("response body is not valid JSON: " + err.to_string())
  }
  let decoded : T = @json.from_json(json) catch {
    err =>
      raise Decode(
        "response body does not match the generated schema: " + err.to_string(),
      )
  }
  decoded
}
