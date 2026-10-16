"""Regression coverage for the nine generator correctness reports."""
import json
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'tests/_build/generator-regressions'


def run(args, cwd=ROOT):
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True,
                          encoding='utf-8', errors='replace', timeout=180)


def schema_response(schema):
    return {'description': 'ok', 'content': {'application/json': {'schema': schema}}}


def document():
    obj = {'type': 'object', 'required': ['id'], 'properties': {'id': {'type': 'integer'}}}
    return {'openapi': '3.0.3', 'info': {'title': 'Regression', 'version': '1'},
            'components': {'schemas': {
                'mode': {'type': 'string', 'enum': ['fast-mode', 'slow-mode']},
                'foo-bar': {'type': 'object', 'required': ['first'], 'properties': {'first': {'type': 'string'}}},
                'foo_bar': {'type': 'object', 'required': ['second'], 'properties': {'second': {'type': 'integer'}, 'nested': obj}}},
                'securitySchemes': {'Bearer': {'type': 'http', 'scheme': 'bearer'}, 'Basic': {'type': 'http', 'scheme': 'basic'}}},
            'paths': {
                '/inline': {'post': {'operationId': 'inlineObject', 'requestBody': {'required': True, 'content': {'application/json': {'schema': obj}}}, 'responses': {'200': schema_response(obj)}}},
                '/ref': {'get': {'operationId': 'getRef', 'responses': {'200': schema_response({'$ref': '#/components/schemas/foo_bar'})}}},
                '/mixed': {'get': {'operationId': 'mixed', 'responses': {'200': schema_response({'type': 'string'}), '204': {'description': 'empty'}}}},
                '/a': {'get': {'operationId': 'getItems', 'security': [{'Bearer': []}, {'Basic': []}], 'parameters': [
                    {'name': 'tags', 'in': 'query', 'required': True, 'schema': {'type': 'array', 'items': {'type': 'string'}}},
                    {'name': 'joined', 'in': 'query', 'explode': False, 'schema': {'type': 'array', 'items': {'type': 'integer'}}},
                    {'name': 'X-Mode', 'in': 'header', 'schema': {'$ref': '#/components/schemas/mode'}},
                    {'name': 'X-Count', 'in': 'header', 'schema': {'type': 'integer'}},
                    {'name': 'X-Flags', 'in': 'header', 'schema': {'type': 'array', 'items': {'type': 'boolean'}}}
                ], 'responses': {'200': schema_response({'type': 'string'})}}},
                '/b': {'get': {'operationId': 'get-items', 'responses': {'200': schema_response({'type': 'string'}), '204': {'description': 'empty'}}}}
            }}


def generate(spec, label):
    work = BUILD / label
    work.mkdir(parents=True, exist_ok=True)
    source, out, ir = work / 'spec.json', work / 'sdk', work / 'ir.json'
    source.write_text(json.dumps(spec), encoding='utf-8')
    result = run([sys.executable, str(ROOT / 'oas2moon.py'), 'generate', str(source), '--module', 'regression/sdk', '--out', str(out), '--ir-out', str(ir)])
    return result, out, ir


def test_unsupported_rejected_before_output():
    spec = document()
    spec['components']['schemas']['Choice'] = {'oneOf': [{'type': 'string'}, {'type': 'integer'}]}
    spec['paths']['/ref']['get']['responses']['200'] = schema_response({'$ref': '#/components/schemas/Choice'})
    result, out, ir = generate(spec, 'unsupported')
    assert result.returncode == 4, result.stderr
    assert '#/components/schemas/Choice/oneOf' in result.stderr
    assert not out.exists() and not ir.exists()


def test_generated_sdk_wire_and_decode():
    requests = []

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_POST(self):
            body = self.rfile.read(int(self.headers['Content-Length']))
            requests.append((self.path, dict(self.headers), body))
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            requests.append((self.path, dict(self.headers), b''))
            status, body = (204, b'') if self.path.endswith(('/mixed', '/b')) else (200, b'{"second":42,"nested":{"id":1}}' if self.path.endswith('/ref') else b'"ok"')
            self.send_response(status)
            if body:
                self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(body)

    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        spec = document()
        spec['servers'] = [{'url': 'http://127.0.0.1:%d/api' % server.server_port}]
        result, out, ir_file = generate(spec, 'supported')
        assert result.returncode == 0, result.stderr
        assert 'schema.json_fallback' in result.stderr
        ir = json.loads(ir_file.read_text(encoding='utf-8'))
        ops = {o['operation_id']: o for o in ir['operations']}
        assert ops['getItems']['security'] == [['Bearer'], ['Basic']]
        assert ops['getItems']['parameters'][0]['explode'] is True
        assert ops['getRef']['response_strategy']['type']['name'] == 'FooBar_2'
        assert ops['inlineObject']['response_strategy']['type']['name'] == 'Json'
        assert ops['getItems']['fn_name'] != ops['get-items']['fn_name']
        assert ops['mixed']['response_strategy']['kind'] == 'response_enum'
        pkg = out / 'moon.pkg'
        pkg.write_text(pkg.read_text(encoding='utf-8') + '\nimport { "moonbitlang/async", } for "wbtest"\n', encoding='utf-8')
        (out / 'regression_wbtest.mbt').write_text(r'''
///|
async test "real HTTP regression matrix" {
  let c = Client::new(bearer_token="token")
  assert_eq(c.config.base_path(), "/api")
  assert_eq(Client::new(base_url="http://override/other").config.origin(), "http://override")
  assert_eq(c.get_items(["a", "b"], joined=[1, 2], x_count=42, x_mode=Mode::FastMode, x_flags=[true, false]), "ok")
  let ref_value = c.get_ref()
  assert_eq(ref_value.second, 42)
  assert_eq(ref_value.nested.unwrap(), { "id": 1 })
  assert_eq(c.inline_object({ "id": 1 }), { "id": 1 })
  match c.mixed() { S204(_) => (); _ => fail("expected empty variant") }
  match c.get_items_2() { S204(_) => (); _ => fail("expected empty variant") }
  let basic = Client::new(basic_username="user", basic_password="pass")
  assert_eq(basic.get_items(["a,b", "空 格"]), "ok")
}
///|
test "security preserves AND, anonymous and API key identity" {
  let cfg = Config::new("", bearer_token="tok", api_key_name="X-Right", api_key_value="key", api_key_location="header")
  let selected = select_security(cfg, [
    [("Wrong", "apiKey", "X-Wrong", "header")],
    [("Right", "apiKey", "X-Right", "header"), ("Bearer", "bearer", "", "")],
  ])
  assert_eq(selected, ["apiKey", "bearer"])
  assert_eq(select_security(Config::new(""), [[("Bearer", "bearer", "", "")], []]), [])
  try {
    ignore(select_security(cfg, [[("Bearer", "bearer", "", ""), ("Basic", "basic", "", "")]]))
    fail("partial AND group accepted")
  } catch { Configuration(_, _) => (); _ => fail("wrong error") }
}
///|
async test "all alternatives missing fails before transport" {
  let t = CaptureTransport::new(Response::new(200, body="\"ok\""))
  let c = Client::new(capture=t)
  try { ignore(c.get_items([])); fail("missing credentials accepted") }
  catch { Configuration(_, _) => (); _ => fail("wrong error") }
  assert_true(t.last_request() is None)
}
''', encoding='utf-8')
        for cmd in (['moon', 'fmt'], ['moon', 'check', '--target', 'native', '--deny-warn'], ['moon', 'test', '--target', 'native', '--deny-warn']):
            checked = run(cmd, out)
            assert checked.returncode == 0, checked.stdout + checked.stderr
        first = requests[0]
        assert first[0] == '/api/a?tags=a&tags=b&joined=1,2'
        assert first[1]['X-Count'] == '42' and first[1]['X-Flags'] == 'true,false'
        assert first[1]['X-Mode'] == 'fast-mode'
        assert first[1]['Authorization'] == 'Bearer token'
        assert requests[-1][0] == "/api/a?tags=a%2Cb&tags=%E7%A9%BA%20%E6%A0%BC"
        assert requests[-1][1]['Authorization'] == 'Basic dXNlcjpwYXNz'
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
