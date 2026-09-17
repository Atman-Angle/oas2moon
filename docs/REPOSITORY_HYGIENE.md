# MoonBit-first repository hygiene

## Production boundary

MoonBit owns parsing adaptation, support validation, Canonical Client IR, type mapping, naming, SDK emission, and runtime transport semantics. Python is deliberately limited to CLI process orchestration, test harnesses, the strict local fixture server, and demonstration support. Parser AST is never a codegen authority.

## T15 audit decisions

| Material | Decision | Evidence / reason |
|---|---|---|
| `tools/do_test.py`, `tools/fix_test.py` | Removed | `rg` found no callers; both contained broken ad-hoc text replacement code. |
| `spike/run_spike.ps1`, `spike/run_integration.ps1`, `spike/verify_determinism.ps1` | Removed | Not in CI/test/demo; each referenced deleted `spike/generator/generate.py`. |
| Remaining `spike/` MoonBit sources | Kept, marked historical | They document feasibility experiments but must not be used as production or current verification evidence. |
| `tests/reference_python/` | Kept as test-only reference oracle | Imported by `test_phase1.py`, `test_phase1_5.py`, and `test_phase2.py`; it is not under `src/` and does not drive the production CLI. |
| `demo/petstore/gen_tests.py` | Kept | Called twice by `run_demo.ps1` to add test-only generated-package tests. It is not a generator implementation. |
| `tests/test_t03.py`, `tests/test_t06.py`, `tests/test_t09.py` | Removed | Legacy manual runners were not invoked by pytest, CI, Demo, imports, or scripts. Their still-valid behavior is covered by `test_t10_cli.py` compilation, `test_t13_determinism.py`, runtime MoonBit tests, and the real HTTP Petstore Demo. |

Historical reports may preserve old dates, paths, and observations, but are not current evidence. `docs/SPIKE_REPORT.md` is explicitly labelled historical; current evidence is limited to the commands and hosted run linked from `ACCEPTANCE.md`.

## Migration direction

- Move `tests/reference_python/` gradually into MoonBit/golden fixture coverage, retaining it only while it has a named test consumer.
- Evaluate replacing `demo/petstore/gen_tests.py` with generated MoonBit fixture tests or a MoonBit test package, without weakening the real HTTP driver.
- Replace the Python CLI wrapper with a MoonBit CLI only when it can preserve the same input handling, diagnostics, exit codes, Canonical Client IR contract, and byte-identical outputs.

## Release audit checklist

Before release, scan tracked content for credentials, ignored local configuration, temporary outputs, absolute paths, stale links, and false Python-authority language. Use `git ls-files` for tracked files and do not delete fixture, CI, demo, or test helpers merely because they are Python.
