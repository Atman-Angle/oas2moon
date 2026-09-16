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
pub fn SdkError::to_string(self : SdkError) -> String {
  match self {
    Transport(msg) => "Transport: " + msg
    Encode(msg) => "Encode: " + msg
    Decode(msg) => "Decode: " + msg
    HttpStatus(status, body) => "HttpStatus(" + status.to_string() + "): " + body
    InvalidRequest(msg) => "InvalidRequest: " + msg
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
  mut captured : Request?
} derive(Debug)

///|
pub fn CaptureTransport::new(response : Response) -> CaptureTransport {
  { response, captured: None }
}

///|
/// Return the last captured request, or None if no request was sent.
pub fn CaptureTransport::last_request(self : CaptureTransport) -> Request? {
  self.captured
}

///|
pub fn CaptureTransport::send(
  self : CaptureTransport,
  request : Request,
) -> Response {
  self.captured = Some(request)
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
  self.captured = Some(request)
  self.response
}

///|
/// Build auth headers for the given security requirements.
/// Does not perform I/O; pure map construction.
// ---------------------------------------------------------------------------
// Base64 encoding for Basic auth
// ---------------------------------------------------------------------------

///|
/// The standard Base64 alphabet as a Char array (RFC 4648).
let base64_chars : Array[Char] = [
  'A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P',
  'Q','R','S','T','U','V','W','X','Y','Z',
  'a','b','c','d','e','f','g','h','i','j','k','l','m','n','o','p',
  'q','r','s','t','u','v','w','x','y','z',
  '0','1','2','3','4','5','6','7','8','9','+','/',
]

///|
/// Encode a UTF-8 string to Base64 (RFC 4648).
fn base64_encode(input : String) -> String {
  let bytes = @utf8.encode(input)
  let out = StringBuilder::new()
  let mut i = 0
  while i < bytes.length() {
    let b0 = bytes[i].to_int() & 0xFF
    let b1 = if i + 1 < bytes.length() { bytes[i + 1].to_int() & 0xFF } else { 0 }
    let b2 = if i + 2 < bytes.length() { bytes[i + 2].to_int() & 0xFF } else { 0 }
    let triple = (b0 << 16) | (b1 << 8) | b2
    let c0 = (triple >> 18) & 0x3F
    let c1 = (triple >> 12) & 0x3F
    let c2 = (triple >> 6) & 0x3F
    let c3 = triple & 0x3F
    out.write_char(base64_chars[c0])
    out.write_char(base64_chars[c1])
    if i + 1 < bytes.length() {
      out.write_char(base64_chars[c2])
    } else {
      out.write_char('=')
    }
    if i + 2 < bytes.length() {
      out.write_char(base64_chars[c3])
    } else {
      out.write_char('=')
    }
    i = i + 3
  }
  out.to_string()
}

// ---------------------------------------------------------------------------
// Authentication helpers
// ---------------------------------------------------------------------------

///|
/// Build auth headers for the given security requirements.
///
/// For each requirement (scheme kind), lookup the credential from Config and
/// add the appropriate HTTP headers. API key with location "query" returns
/// empty headers because the key is sent as a query parameter instead.
///
/// Raises InvalidRequest if a required credential is missing.
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
          None =>
            raise InvalidRequest(
              "missing bearer token for " + requirement,
            )
        }
        headers["Authorization"] = "Bearer " + token
      }
      "basic" => {
        let username = match cfg.basic_username() {
          Some(u) => u
          None =>
            raise InvalidRequest(
              "missing basic auth username for " + requirement,
            )
        }
        let password = match cfg.basic_password() {
          Some(p) => p
          None =>
            raise InvalidRequest(
              "missing basic auth password for " + requirement,
            )
        }
        let encoded = base64_encode(username + ":" + password)
        headers["Authorization"] = "Basic " + encoded
      }
      "apiKey" => {
        let location = match cfg.api_key_location() {
          Some(l) => l
          None =>
            raise InvalidRequest(
              "missing apiKey location for " + requirement,
            )
        }
        if location == "header" {
          let key_name = match cfg.api_key_name() {
            Some(n) => n
            None =>
              raise InvalidRequest(
                "missing apiKey name for " + requirement,
              )
          }
          let key_value = match cfg.api_key_value() {
            Some(v) => v
            None =>
              raise InvalidRequest(
                "missing apiKey value for " + requirement,
              )
          }
          headers[key_name] = key_value
        }
      }
      _ =>
        raise InvalidRequest(
          "unsupported auth scheme: " + requirement,
        )
    }
  }
  headers
}

///|
/// Build auth query parameters for the given security requirements.
///
/// Currently only apiKey with location "query" produces query parameters.
/// Returns an empty array for all other scheme kinds.
pub fn auth_query(
  cfg : Config,
  requirements : Array[String],
) -> Array[(String, String)] raise SdkError {
  let params : Array[(String, String)] = []
  for requirement in requirements {
    match requirement {
      "apiKey" => {
        let location = match cfg.api_key_location() {
          Some(l) => l
          None =>
            raise InvalidRequest(
              "missing apiKey location for " + requirement,
            )
        }
        if location == "query" {
          let key_name = match cfg.api_key_name() {
            Some(n) => n
            None =>
              raise InvalidRequest(
                "missing apiKey name for " + requirement,
              )
          }
          let key_value = match cfg.api_key_value() {
            Some(v) => v
            None =>
              raise InvalidRequest(
                "missing apiKey value for " + requirement,
              )
          }
          params.push((key_name, key_value))
        }
      }
      _ => ()
    }
  }
  params
}
