# Third-party notices

This file lists direct MoonBit package dependencies declared by the production package manifests. It is an attribution and source index, not a vendored-license bundle. License identifiers below were checked against the installed package license/header material during T15.

| Dependency | Declared version | Used by | Purpose | License / source |
|---|---:|---|---|---|
| `Han-Wentao/mooncontract` | `0.1.0` | `src/frontend_adapter` | OpenAPI frontend adapter | MIT; installed `LICENSE`; [source](https://github.com/Han-Wentao/mooncontract) |
| `moonbit-community/yaml` | `0.0.6` | `src/frontend_adapter` | Common YAML input parsing | MIT; installed `LICENSE`; package source `moonbit-community/yaml` |
| `moonbitlang/x` | `0.4.46` | frontend, core, codegen | MoonBit support utilities | Apache-2.0; installed license header configuration; [source](https://github.com/moonbitlang/x) |
| `moonbitlang/async` | `0.20.2` | runtime and generated operation packages | Async HTTP transport | Apache-2.0; installed `LICENSE`; [source](https://github.com/moonbitlang/async) |

Python's standard library is used for CLI orchestration and the fixture server; no direct Python package dependency is declared in the repository. `pytest` is a development/CI test dependency installed by the workflow, not a runtime dependency of generated SDKs.

The project itself is distributed under the [MIT License](LICENSE).
