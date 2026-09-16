///|
/// Errors returned by the runtime boundary.
pub(all) suberror SdkError {
  Transport(String)
  Encode(String)
  Decode(String)
  HttpStatus(Int, String)
  InvalidRequest(String)
} derive(Debug)

///|
/// A transport-neutral request.
pub struct Request {
  http_method : String
  path : String
  query : Array[(String, String)]
  headers : Map[String, String]
  body : String?
} derive(Debug)

///|
pub fn Request::new(
  http_method : String,
  path : String,
  query? : Array[(String, String)] = [],
  headers? : Map[String, String] = Map([]),
  body? : String,
) -> Request {
  { http_method, path, query, headers, body }
}

///|
pub fn Request::http_method(self : Request) -> String {
  self.http_method
}

///|
pub fn Request::path(self : Request) -> String {
  self.path
}

///|
pub fn Request::query(self : Request) -> Array[(String, String)] {
  self.query
}

///|
pub fn Request::headers(self : Request) -> Map[String, String] {
  self.headers
}

///|
pub fn Request::body(self : Request) -> String? {
  self.body
}

///|
/// A transport-neutral response.
pub struct Response {
  status : Int
  headers : Map[String, String]
  body : String
} derive(Debug)

///|
pub fn Response::new(
  status : Int,
  headers? : Map[String, String] = Map([]),
  body? : String = "",
) -> Response {
  { status, headers, body }
}

///|
pub fn Response::status(self : Response) -> Int {
  self.status
}

///|
pub fn Response::headers(self : Response) -> Map[String, String] {
  self.headers
}

///|
pub fn Response::body(self : Response) -> String {
  self.body
}

///|
/// The only boundary generated operations use to perform I/O.
pub trait Transport {
  fn send(Self, Request) -> Response raise SdkError
}

///|
pub fn[T : Transport] send(
  transport : T,
  request : Request,
) -> Response raise SdkError {
  transport.send(request)
}

///|
/// In-memory transport useful for deterministic unit tests.
pub struct CaptureTransport {
  response : Response
} derive(Debug)

///|
pub fn CaptureTransport::new(response : Response) -> CaptureTransport {
  { response, }
}

///|
pub fn CaptureTransport::send(
  self : CaptureTransport,
  request : Request,
) -> Response {
  ignore(request)
  self.response
}

///|
pub fn[T : ToJson] encode_json(value : T) -> String {
  value.to_json().stringify()
}

///|
pub fn[T : FromJson] decode_json(response : Response) -> T raise SdkError {
  let json : Json = @json.parse(response.body) catch {
    err => raise Decode(err.to_string())
  }
  @json.from_json(json) catch {
    err => raise Decode(err.to_string())
  }
}

///|
pub fn expect_status(
  response : Response,
  expected : Array[Int],
) -> Unit raise SdkError {
  if !expected.contains(response.status) {
    raise HttpStatus(response.status, response.body)
  }
}

///|
pub impl Transport for CaptureTransport with fn send(
  self : CaptureTransport,
  request : Request,
) -> Response {
  ignore(request)
  self.response
}

///|
/// Build auth headers for the given security requirements.
/// Does not perform I/O; pure map construction.
pub fn auth_headers(
  cfg : Config,
  requirements : Array[String],
) -> Map[String, String] raise SdkError {
  let headers : Map[String, String] = Map([])
  for requirement in requirements {
    match requirement {
      "bearer" => {
        let token = match cfg.bearer_token() {
          Some(t) => t
          None => raise InvalidRequest("missing bearer token for " + requirement)
        }
        headers["Authorization"] = "Bearer " + token
      }
      _ => raise InvalidRequest("unsupported auth scheme: " + requirement)
    }
  }
  headers
}
