import json, hashlib, pathlib, shutil, subprocess, sys

ROOT = pathlib.Path(__file__).parent
FIX = ROOT / 'fixtures' / 'petstore' / 'openapi.json'

def main(out):
    out = pathlib.Path(out); out.mkdir(parents=True, exist_ok=True)
    spec = json.loads(FIX.read_text(encoding='utf-8'))
    # MoonContract is the parser/validator authority for this spike.
    mc = ROOT / '.spike-deps' / 'mooncontract2'
    subprocess.run(['moon','run','cmd/mooncontract','--target','native','--','lint','--spec',str(FIX)], cwd=mc, check=True)
    pet = spec['components']['schemas']['Pet']; status = spec['components']['schemas']['PetStatus']
    files = {
      'moon.mod.json': '{"name":"spike/generated","version":"0.1.0","deps":{"moonbitlang/async":"0.20.2"}}\n',
      'moon.pkg.json': '{"import":["moonbitlang/async/http","moonbitlang/async/io","moonbitlang/core/json"]}\n',
      'client.mbt': '''pub enum PetStatus { Available | Pending | Sold } derive(ToJson, FromJson, Eq, Show)\n\npub struct Pet { pub id : Int64; pub name : String; pub status : PetStatus; pub tags : Array[String]; pub nickname : String? } derive(ToJson, FromJson, Show)\n\npub struct Client { base_url : String; token : String }\npub fn Client::new(base_url~ : String, token~ : String) -> Client { { base_url, token } }\n\nfn headers(c : Client, trace : String) -> Map[String, String] { { "Authorization": "Bearer " + c.token, "X-Trace": trace, "Content-Type": "application/json" } }\nfn decode(s : String) -> Pet { @json.from_json(@json.parse(s).unwrap()) }\n\npub async fn Client::get_pet_by_id(self : Client, id~ : Int64, verbose~ : Bool, trace~ : String) -> Pet {\n  let query = if verbose { "?verbose=true" } else { "" }\n  let (resp, body) = @http.get(self.base_url + "/pets/" + id.to_string() + query, headers=headers(self, trace))\n  guard resp.code == 200 else { abort("GET failed") }\n  decode(body.text())\n}\n\npub async fn Client::add_pet(self : Client, pet~ : Pet) -> Pet {\n  let body = pet.to_json().stringify()\n  let (resp, data) = @http.post(self.base_url + "/pets", body, headers=headers(self, "post"))\n  guard resp.code == 201 else { abort("POST failed") }\n  decode(data.text())\n}\n\npub async fn Client::delete_pet(self : Client, id~ : Int64) -> Unit {\n  let c = @http.Client(self.base_url)\n  c.request(@http.Delete, "/pets/" + id.to_string(), extra_headers=headers(self, "delete"))\n  let resp = c.end_request()\n  guard resp.code == 204 else { abort("DELETE failed") }\n}\n'''
    }
    for p,c in files.items():
        (out/p).write_text(c, encoding='utf-8', newline='\n')
    return files

if __name__ == '__main__': main(sys.argv[1])
