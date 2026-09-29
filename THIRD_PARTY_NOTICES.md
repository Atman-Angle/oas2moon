# Third-party notices

This file lists both direct runtime dependencies and third-party documents
committed under `fixtures/real-world/`. It is part of the source distribution
and must travel with any redistribution of those fixtures. The MIT license in
the repository root applies to oas2moon-authored code only; it does not
relicense the third-party material listed below.

| Dependency | Declared version | Used by | Purpose | License / source |
|---|---:|---|---|---|
| `Han-Wentao/mooncontract` | `0.1.0` | `src/frontend_adapter` | OpenAPI frontend adapter | MIT; installed `LICENSE`; [source](https://github.com/Han-Wentao/mooncontract) |
| `moonbit-community/yaml` | `0.0.6` | `src/frontend_adapter` | Common YAML input parsing | MIT; installed `LICENSE`; package source `moonbit-community/yaml` |
| `moonbitlang/x` | `0.4.46` | frontend, core, codegen | MoonBit support utilities | Apache-2.0; installed license header configuration; [source](https://github.com/moonbitlang/x) |
| `moonbitlang/async` | `0.20.2` | runtime and generated operation packages | Async HTTP transport | Apache-2.0; installed `LICENSE`; [source](https://github.com/moonbitlang/async) |

Python's standard library is used for CLI orchestration and the fixture server; no direct Python package dependency is declared in the repository. `pytest` is a development/CI test dependency installed by the workflow, not a runtime dependency of generated SDKs.

## Committed third-party fixture material

| Path | Upstream/source | SPDX / terms | What is redistributed |
|---|---|---|---|
| `fixtures/real-world/github-subset.json` | [github/rest-api-description](https://github.com/github/rest-api-description), commit `2c0db91ff57dc7d0670be941320e5f7d8daa17fd` | MIT | A small, curated subset of operation and schema facts; not the upstream repository |
| `fixtures/real-world/openai-subset.json` | [openai/openai-openapi](https://github.com/openai/openai-openapi), commit `ac89e26b5fa142cf9e0c4be4e19c1858607835c1` | MIT | A small, curated subset of operation and schema facts; not the upstream repository |
| `fixtures/real-world/oai-petstore-3.0.yaml` | [OAI/OpenAPI-Specification](https://github.com/OAI/OpenAPI-Specification), commit `c9f8f040e825a827bb011955bd41b7e2d899688f` | Apache-2.0 upstream; the sample itself declares MIT | The pinned archived sample, retained byte-for-byte |
| `fixtures/petstore/openapi.json` and `.yaml` | Swagger Petstore sample, reduced and maintained as a project fixture | Apache-2.0 source terms | A project-trimmed test fixture, not a copy of the full upstream repository |
| `fixtures/real-world/jsonplaceholder-subset.json` | Project-authored compatibility fixture based on the public JSONPlaceholder API shape | No upstream code or license text is redistributed | Independently written operation/schema facts used only for generator coverage |

### MIT text for fixture subsets

The MIT-licensed GitHub and OpenAI subsets are redistributed with the
permission notice below. Copyright remains with the respective upstream
copyright holders.

```text
MIT License

Copyright (c) 2020 GitHub
Copyright (c) OpenAI (https://openai.com)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### Apache-2.0 text for fixture samples

The OAI and Swagger Petstore entries are distributed under the Apache License,
Version 2.0 where that upstream license applies. The canonical license text is
available at <https://www.apache.org/licenses/LICENSE-2.0>. No NOTICE file was
present in the pinned OAI sample; if an upstream NOTICE is added later, it must
be copied here before updating the fixture.

The project itself is distributed under the [MIT License](LICENSE). That MIT
license covers only oas2moon-authored files.
