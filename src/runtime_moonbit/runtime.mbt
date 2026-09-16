///|
/// Structured SDK error type.
///
/// Every variant carries an `operation_id` so that diagnosis context is
/// never discarded.  The `Http` variant additionally carries status, headers,
/// and raw body for programmatic inspection by callers.
///
/// Variant map (per docs/DECISIONS.md §2):
/// - Transport      — DNS, connection, timeout, TLS, or adapter failure;
/// - Http           — non-2xx response (status, headers, raw body);
/// - Decode         — response did not match the declared representation;
/// - Encode         — request serialization failed;
/// - Configuration — invalid base URL or auth configuration;
/// - Unsupported    — rejected OpenAPI semantic surfaced at runtime boundary.
pub(all) suberror SdkError {
  Transport(String, String) // operation_id, message
  Http(
    String, // operation_id
    Int, // status
    Map[String, String], // response headers
    String
  ) // raw body
  Decode(String, String) // operation_id, message
  Encode(String, String) // operation_id, message
  Configuration(String, String) // operation_id, message
  Unsupported(String, String) // operation_id, message
} derive(Debug)

///|
/// Convenience constructor for a transport error.
pub fn SdkError::transport(operation_id : String, message : String) -> SdkError {
  Transport(operation_id, message)
}

///|
/// Convenience constructor for an HTTP error.
pub fn SdkError::http(
  operation_id : String,
  status : Int,
  headers : Map[String, String],
  body : String,
) -> SdkError {
  Http(operation_id, status, headers, body)
}

///|
/// Convenience constructor for a decode error.
pub fn SdkError::decode(operation_id : String, message : String) -> SdkError {
  Decode(operation_id, message)
}

///|
/// Convenience constructor for an encode error.
pub fn SdkError::encode(operation_id : String, message : String) -> SdkError {
  Encode(operation_id, message)
}

///|
/// Convenience constructor for a configuration error.
pub fn SdkError::configuration(
  operation_id : String,
  message : String,
) -> SdkError {
  Configuration(operation_id, message)
}

///|
/// Convenience constructor for an unsupported-feature error.
pub fn SdkError::unsupported(
  operation_id : String,
  message : String,
) -> SdkError {
  Unsupported(operation_id, message)
}

///|
/// The operation id carried by this error, or `""` when unknown.
pub fn SdkError::operation_id(self : SdkError) -> String {
  match self {
    Transport(op, _) => op
    Http(op, _, _, _) => op
    Decode(op, _) => op
    Encode(op, _) => op
    Configuration(op, _) => op
    Unsupported(op, _) => op
  }
}

///|
/// HTTP status code when this is an `Http` error, otherwise `0`.
pub fn SdkError::status(self : SdkError) -> Int {
  match self {
    Http(_, status, _, _) => status
    _ => 0
  }
}

///|
/// Response headers when this is an `Http` error, otherwise an empty map.
pub fn SdkError::headers(self : SdkError) -> Map[String, String] {
  match self {
    Http(_, _, headers, _) => headers
    _ => Map([])
  }
}

///|
/// Raw response body when this is an `Http` error, otherwise `""`.
pub fn SdkError::body(self : SdkError) -> String {
  match self {
    Http(_, _, _, body) => body
    _ => ""
  }
}

///|
/// Human-readable detail message for any variant.
/// For `Http` this is a status summary; for other variants it is the
/// original message string.
pub fn SdkError::message(self : SdkError) -> String {
  match self {
    Transport(_, msg) => msg
    Http(_, status, _, body) => {
      let suffix = if body == "" { "" } else { " body: " + body }
      "HTTP " + status.to_string() + suffix
    }
    Decode(_, msg) => msg
    Encode(_, msg) => msg
    Configuration(_, msg) => msg
    Unsupported(_, msg) => msg
  }
}

///|
/// Stable, human-readable display of an SDK error.
///
/// The output is deterministic for equal inputs and never contains
/// absolute paths, timestamps, or random identifiers.
pub fn SdkError::to_string(self : SdkError) -> String {
  let op_part = match self.operation_id() {
    "" => ""
    id => " (operation: " + id + ")"
  }
  match self {
    Transport(_, _) => "transport error" + op_part + ": " + self.message()
    Http(_, _, _, _) => "http error" + op_part + ": " + self.message()
    Decode(_, _) => "decode error" + op_part + ": " + self.message()
    Encode(_, _) => "encode error" + op_part + ": " + self.message()
    Configuration(_, _) =>
      "configuration error" + op_part + ": " + self.message()
    Unsupported(_, _) => "unsupported feature" + op_part + ": " + self.message()
  }
}

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
  mut last_request : Request?
} derive(Debug)

///|
pub fn CaptureTransport::new(response : Response) -> CaptureTransport {
  { response, last_request: None }
}

///|
pub fn CaptureTransport::send(
  self : CaptureTransport,
  request : Request,
) -> Response {
  self.last_request = Some(request)
  self.response
}

///|
/// The last request that was sent through this transport, if any.
pub fn CaptureTransport::last_request(self : CaptureTransport) -> Request? {
  self.last_request
}

///|
pub fn[T : ToJson] encode_json(value : T) -> String {
  value.to_json().stringify()
}

///|
/// Decode a JSON response body into the target type.
///
/// `operation_id` is included in any raised `Decode` error so that
/// callers can programmatically identify which operation failed.
pub fn[T : FromJson] decode_json(
  response : Response,
  operation_id? : String = "",
) -> T raise SdkError {
  let json : Json = @json.parse(response.body) catch {
    err =>
      raise Decode(operation_id, "failed to parse JSON: " + err.to_string())
  }
  @json.from_json(json) catch {
    err => raise Decode(operation_id, err.to_string())
  }
}

///|
/// Assert that the response status is one of the expected values.
///
/// On failure, raises `Http` carrying the full status, headers, and raw
/// body so callers can programmatically inspect the error response.
pub fn expect_status(
  response : Response,
  expected : Array[Int],
  operation_id? : String = "",
) -> Unit raise SdkError {
  if !expected.contains(response.status) {
    raise Http(operation_id, response.status, response.headers, response.body)
  }
}

///|
pub impl Transport for CaptureTransport with fn send(
  self : CaptureTransport,
  request : Request,
) -> Response {
  self.last_request = Some(request)
  self.response
}

///|
/// Build auth headers for the given security requirements.
/// Does not perform I/O; pure map construction.
///
/// `operation_id` is included in any raised `Configuration` error.
pub fn auth_headers(
  cfg : Config,
  requirements : Array[String],
  operation_id? : String = "",
) -> Map[String, String] raise SdkError {
  let headers : Map[String, String] = Map([])
  for requirement in requirements {
    match requirement {
      "bearer" => {
        let token = match cfg.bearer_token() {
          Some(t) => t
          None =>
            raise Configuration(
              operation_id,
              "missing bearer token for " + requirement,
            )
        }
        headers["Authorization"] = "Bearer " + token
      }
      _ =>
        raise Configuration(
          operation_id,
          "unsupported auth scheme: " + requirement,
        )
    }
  }
  headers
}
