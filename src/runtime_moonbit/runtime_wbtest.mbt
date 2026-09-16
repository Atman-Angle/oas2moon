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
test "unexpected status becomes structured error" {
  let response = Response::new(404, body="missing")
  expect_status(response, [200]) catch {
    HttpStatus(status, body) => {
      assert_eq(status, 404)
      assert_eq(body, "missing")
    }
    _ => raise Failure("expected HttpStatus")
  }
}

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
