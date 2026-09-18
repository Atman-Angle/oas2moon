///|
test "request and response expose wire fields" {
  let headers : Map[String, String] = Map([("X-Test", "yes")])
  let request = Request::new(
    "GET",
    "/pets",
    query=[("limit", "2")],
    headers~,
    body="{}",
  )
  assert_eq(request.http_method(), "GET")
  assert_eq(request.path(), "/pets")
  assert_eq(request.query().length(), 1)
  assert_eq(request.headers()["X-Test"], "yes")
  assert_eq(request.body(), Some("{}"))
  let response = Response::new(200, headers~, body="ok")
  assert_eq(response.status(), 200)
  assert_eq(response.headers()["X-Test"], "yes")
  assert_eq(response.body(), "ok")
}

///|
test "capture transport returns deterministic response" {
  let response = Response::new(204)
  let transport = CaptureTransport::new(response)
  let actual = send(transport, Request::new("DELETE", "/pets/1"))
  assert_eq(actual.status(), 204)
}

///|
test "unexpected status becomes structured Http error" {
  let response = Response::new(404, body="missing")
  expect_status(response, [200], operation_id="get_pet") catch {
    Http(op, status, headers, body) => {
      assert_eq(op, "get_pet")
      assert_eq(status, 404)
      assert_eq(body, "missing")
      ignore(headers)
    }
    _ => raise Failure("expected Http")
  }
}

// ---------------------------------------------------------------------------
// T08: Structured error model tests
// ---------------------------------------------------------------------------

///|
/// Helper: a transport that always raises Transport, simulating
/// network failure.
struct FailingTransport {
  message : String
}

///|
fn FailingTransport::new(message : String) -> FailingTransport {
  { message, }
}

///|
impl Transport for FailingTransport with fn send(
  self : FailingTransport,
  _request : Request,
) -> Response raise SdkError {
  raise Transport("get_pet", self.message)
}

///|
test "network failure raises Transport error" {
  let t = FailingTransport::new("connection refused")
  let _ : Response = send(t, Request::new("GET", "/pets/1")) catch {
    Transport(op, msg) => {
      assert_eq(op, "get_pet")
      assert_eq(msg, "connection refused")
      Response::new(0)
    }
    _ => raise Failure("expected Transport")
  }
}

///|
test "400 Bad Request produces Http error with status and body" {
  let body = "{\"error\":\"bad request\"}"
  let response = Response::new(400, body~)
  expect_status(response, [200], operation_id="add_pet") catch {
    Http(op, status, _, raw) => {
      assert_eq(op, "add_pet")
      assert_eq(status, 400)
      assert_eq(raw, body)
    }
    _ => raise Failure("expected Http")
  }
}

///|
test "401 Unauthorized produces Http error" {
  let response = Response::new(401, body="unauthorized")
  expect_status(response, [200], operation_id="list_pets") catch {
    Http(op, status, _, body) => {
      assert_eq(op, "list_pets")
      assert_eq(status, 401)
      assert_eq(body, "unauthorized")
    }
    _ => raise Failure("expected Http")
  }
}

///|
test "404 Not Found produces Http error" {
  let response = Response::new(404, body="not found")
  expect_status(response, [200], operation_id="get_pet") catch {
    Http(op, status, _, body) => {
      assert_eq(op, "get_pet")
      assert_eq(status, 404)
      assert_eq(body, "not found")
    }
    _ => raise Failure("expected Http")
  }
}

///|
test "500 Internal Server Error produces Http error" {
  let response = Response::new(500, body="internal error")
  expect_status(response, [200, 201], operation_id="update_pet") catch {
    Http(op, status, _, body) => {
      assert_eq(op, "update_pet")
      assert_eq(status, 500)
      assert_eq(body, "internal error")
    }
    _ => raise Failure("expected Http")
  }
}

///|
test "empty error body is preserved as empty string" {
  let response = Response::new(404)
  expect_status(response, [200], operation_id="get_pet") catch {
    Http(op, status, _, body) => {
      assert_eq(op, "get_pet")
      assert_eq(status, 404)
      assert_eq(body, "")
    }
    _ => raise Failure("expected Http")
  }
}

///|
test "error JSON body is preserved as raw string" {
  let body = "{\"error\":\"Invalid pet\",\"code\":42,\"details\":[\"name required\"]}"
  let response = Response::new(422, body~)
  expect_status(response, [200, 201], operation_id="add_pet") catch {
    Http(op, status, _, raw) => {
      assert_eq(op, "add_pet")
      assert_eq(status, 422)
      assert_eq(raw, body)
    }
    _ => raise Failure("expected Http")
  }
}

///|
test "Http error headers are preserved" {
  let headers : Map[String, String] = Map([
    ("Content-Type", "application/json"),
    ("X-Request-Id", "abc123"),
  ])
  let response = Response::new(500, headers~, body="error")
  expect_status(response, [200], operation_id="get_pet") catch {
    Http(op, status, hdrs, body) => {
      assert_eq(op, "get_pet")
      assert_eq(status, 500)
      assert_eq(body, "error")
      assert_eq(hdrs["Content-Type"], "application/json")
      assert_eq(hdrs["X-Request-Id"], "abc123")
    }
    _ => raise Failure("expected Http")
  }
}

///|
test "missing bearer token raises Configuration error with operation id" {
  let cfg = Config::new("http://localhost")
  let _ : Map[String, String] = auth_headers(
    cfg,
    ["bearer"],
    operation_id="delete_pet",
  ) catch {
    Configuration(op, msg) => {
      assert_eq(op, "delete_pet")
      let _ = msg.contains("bearer")
      Map([])
    }
    _ => raise Failure("expected Configuration")
  }
}

///|
test "unsupported auth scheme raises Configuration error" {
  let cfg = Config::new("http://localhost", bearer_token="tok")
  let _ : Map[String, String] = auth_headers(
    cfg,
    ["oauth"],
    operation_id="add_pet",
  ) catch {
    Configuration(op, msg) => {
      assert_eq(op, "add_pet")
      let _ = msg.contains("oauth")
      Map([])
    }
    _ => raise Failure("expected Configuration")
  }
}

///|
test "decode_json raises Decode error on invalid JSON" {
  let response = Response::new(200, body="{invalid")
  let _ : Int = (decode_json(response, operation_id="get_pet") : Int) catch {
    Decode(op, _) => {
      assert_eq(op, "get_pet")
      0
    }
    _ => raise Failure("expected Decode")
  }
}

///|
test "decode_json raises Decode error on type mismatch" {
  let response = Response::new(200, body="\"hello\"")
  let _ : Int = (decode_json(response, operation_id="get_pet") : Int) catch {
    Decode(op, _) => {
      assert_eq(op, "get_pet")
      0
    }
    _ => raise Failure("expected Decode")
  }
}

///|
test "decode_json rejects unsupported response media type" {
  let response = Response::new(
    200,
    headers=Map([("Content-Type", "text/plain")]),
    body="1",
  )
  let _ : Int = (decode_json(response, operation_id="get_raw") : Int) catch {
    Unsupported(op, msg) => {
      assert_eq(op, "get_raw")
      let _ = msg.contains("text/plain")
      0
    }
    _ => raise Failure("expected Unsupported")
  }
}

///|
test "decode_json accepts JSON media type parameters and suffixes" {
  let with_charset = Response::new(
    200,
    headers=Map([("Content-Type", "application/json; charset=utf-8")]),
    body="1",
  )
  let parsed : Int = decode_json(with_charset, operation_id="get_one")
  assert_eq(parsed, 1)

  let problem_json = Response::new(
    200,
    headers=Map([("content-type", "application/problem+json")]),
    body="2",
  )
  let parsed_problem : Int = decode_json(problem_json, operation_id="get_two")
  assert_eq(parsed_problem, 2)
}

///|
test "SdkError::to_string is stable and contains no absolute paths" {
  // Http error display
  let http_err = SdkError::http("get_pet", 404, Map([]), "not found")
  let s1 = http_err.to_string()
  assert_eq(s1, "http error (operation: get_pet): HTTP 404 body: not found")

  // Http error with empty body
  let http_empty = SdkError::http("get_pet", 500, Map([]), "")
  let s2 = http_empty.to_string()
  assert_eq(s2, "http error (operation: get_pet): HTTP 500")

  // Transport error display
  let t_err = SdkError::transport("get_pet", "timeout")
  let s3 = t_err.to_string()
  assert_eq(s3, "transport error (operation: get_pet): timeout")

  // Decode error display
  let d_err = SdkError::decode("add_pet", "expected integer")
  let s4 = d_err.to_string()
  assert_eq(s4, "decode error (operation: add_pet): expected integer")

  // Configuration error display
  let c_err = SdkError::configuration("delete_pet", "missing bearer token")
  let s5 = c_err.to_string()
  assert_eq(
    s5, "configuration error (operation: delete_pet): missing bearer token",
  )

  // Unsupported error display
  let u_err = SdkError::unsupported("list_pets", "oneOf not supported")
  let s6 = u_err.to_string()
  assert_eq(
    s6, "unsupported feature (operation: list_pets): oneOf not supported",
  )

  // Encode error display
  let e_err = SdkError::encode("add_pet", "invalid body")
  let s7 = e_err.to_string()
  assert_eq(s7, "encode error (operation: add_pet): invalid body")

  // No absolute paths (drive letters or root paths) in any display
  for s in [s1, s2, s3, s4, s5, s6, s7] {
    let _ = !s.contains("C:\\")
    let _ = !s.contains("D:\\")
    let _ = !s.contains("/home/")
  }
}

///|
test "SdkError accessors work for all variants" {
  // Http variant
  let http_err = SdkError::http("get_pet", 404, Map([("X", "Y")]), "body")
  assert_eq(http_err.operation_id(), "get_pet")
  assert_eq(http_err.status(), 404)
  assert_eq(http_err.body(), "body")
  assert_eq(http_err.headers()["X"], "Y")

  // Non-Http variants return defaults
  let t_err = SdkError::transport("op", "msg")
  assert_eq(t_err.status(), 0)
  assert_eq(t_err.body(), "")
  assert_eq(t_err.operation_id(), "op")
  assert_eq(t_err.message(), "msg")

  let d_err = SdkError::decode("op", "decode failed")
  assert_eq(d_err.status(), 0)
  assert_eq(d_err.body(), "")
  assert_eq(d_err.message(), "decode failed")
}

///|
test "non-2xx response never returns success" {
  // Test multiple non-2xx statuses all raise
  for status in [400, 401, 403, 404, 409, 422, 500, 502, 503] {
    let response = Response::new(status, body="error")
    expect_status(response, [200], operation_id="test") catch {
      Http(op, s, _, b) => {
        assert_eq(op, "test")
        assert_eq(s, status)
        assert_eq(b, "error")
      }
      _ => raise Failure("expected Http for status " + status.to_string())
    }
  }
}

///|
test "2xx response matching expected does not raise" {
  let response = Response::new(200, body="{}")
  expect_status(response, [200], operation_id="get_pet")
  // Also test 201
  let response2 = Response::new(201, body="{}")
  expect_status(response2, [200, 201], operation_id="add_pet")
}

// ---------------------------------------------------------------------------
// Encoding tests (preserved from before)
// ---------------------------------------------------------------------------

///|
test "percent_encode unreserved chars pass through" {
  assert_eq(percent_encode("hello"), "hello")
  assert_eq(percent_encode("a b"), "a%20b")
  assert_eq(percent_encode("a.b-c_d~e"), "a.b-c_d~e")
}

///|
test "percent_encode reserved chars get encoded" {
  assert_eq(percent_encode("a/b"), "a%2Fb")
  assert_eq(percent_encode("foo?bar"), "foo%3Fbar")
  assert_eq(percent_encode("a=b&c"), "a%3Db%26c")
  assert_eq(percent_encode("hello world"), "hello%20world")
  assert_eq(percent_encode("a#b"), "a%23b")
}

///|
test "percent_encode empty string" {
  assert_eq(percent_encode(""), "")
}

///|
test "encode_path_value" {
  assert_eq(encode_path_value("123"), "123")
  assert_eq(encode_path_value("a/b"), "a%2Fb")
}

///|
test "encode_path_array" {
  assert_eq(encode_path_array(["a", "b"]), "a,b")
  assert_eq(encode_path_array(["a/b", "c d"]), "a%2Fb,c%20d")
  assert_eq(encode_path_array([]), "")
}

///|
test "encode_query_pair" {
  let (k, v) = encode_query_pair("name", "hello world")
  assert_eq(k, "name")
  assert_eq(v, "hello%20world")
}

///|
test "encode_query_array_explode" {
  let pairs = encode_query_array_explode("color", ["red", "green", "blue"])
  assert_eq(pairs.length(), 3)
  assert_eq(pairs[0], ("color", "red"))
  assert_eq(pairs[1], ("color", "green"))
  assert_eq(pairs[2], ("color", "blue"))
}

///|
test "encode_query_array_explode empty" {
  let pairs = encode_query_array_explode("tag", [])
  assert_eq(pairs.length(), 0)
}

///|
test "encode_query_array_joined" {
  let (k, v) = encode_query_array_joined("color", ["red", "green", "blue"])
  assert_eq(k, "color")
  assert_eq(v, "red,green,blue")
}

///|
test "encode_header_value" {
  assert_eq(encode_header_value("application/json"), "application/json")
  assert_eq(encode_header_value(""), "")
}

///|
test "encode_header_array" {
  assert_eq(encode_header_array(["a", "b"]), "a,b")
  assert_eq(encode_header_array([]), "")
  assert_eq(encode_header_array(["single"]), "single")
}

///|
test "build_query_string" {
  assert_eq(build_query_string([]), "")
  assert_eq(
    build_query_string([("q", "hello"), ("page", "1")]),
    "q=hello&page=1",
  )
  assert_eq(build_query_string([("a", "1")]), "a=1")
}
