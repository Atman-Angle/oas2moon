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
