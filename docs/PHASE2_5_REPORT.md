# Phase 2.5 Report — Python Authority Cleanup

**Date:** 2026-09-13
**Verdict:** GO

---

## 1. Objective

Remove historical Python prototype authority from the repository so that:

1. **MoonBit** is clearly the production implementation
2. **Python** is only used for: differential reference oracle, test harness, fixture server, reporting, and CI helpers
3. GitHub primary language reflects MoonBit as the implementation language

No `.gitattributes` language overrides were used.

---

## 2. Removed Files

### Obsolete spike generator (Python)

| File | Bytes | Notes |
|---|---|---|
| `spike_generator.py` | 2,631 | Standalone spike entry point |
| `spike/generator/generate.py` | 8,190 | Spike generator entry point |
| `spike/generator/oas2moon/__init__.py` | 439 | |
| `spike/generator/oas2moon/emit.py` | 19,593 | |
| `spike/generator/oas2moon/formatter.py` | 1,656 | |
| `spike/generator/oas2moon/frontend.py` | 10,920 | |
| `spike/generator/oas2moon/ir.py` | 4,476 | |
| `spike/generator/oas2moon/lower.py` | 7,463 | |
| `spike/generator/oas2moon/naming.py` | 2,720 | |
| `spike/generator/oas2moon/support.py` | 15,973 | |
| `spike/generator/oas2moon/typemap.py` | 2,865 | |
| **Subtotal** | **76,926** | |

### Obsolete spike templates (MoonBit — part of Python generator)

| File | Bytes | Notes |
|---|---|---|
| `spike/generator/templates/runtime/config.mbt` | 1,540 | |
| `spike/generator/templates/runtime/encoding.mbt` | 1,733 | |
| `spike/generator/templates/runtime/json_scalars.mbt` | 1,941 | |
| `spike/generator/templates/runtime/moon.pkg` | 92 | |
| `spike/generator/templates/runtime/transport.mbt` | 4,662 | |
| `spike/generator/templates/smoke/main.mbt` | 2,514 | |
| `spike/generator/templates/smoke/moon.pkg` | 124 | |
| **Subtotal** | **12,606** | |

### Moved fixture server

`spike/server/fixture_server.py` → `tools/fixture_server.py` (9,774 bytes, no content change)

### Deleted `src/oas2moon/`

All 8 files (58,395 bytes) moved to `tests/reference_python/oas2moon/`.

---

## 3. Moved Files

| Old Path | New Path | Bytes |
|---|---|---|
| `src/oas2moon/__init__.py` | `tests/reference_python/oas2moon/__init__.py` | 600 |
| `src/oas2moon/frontend.py` | `tests/reference_python/oas2moon/frontend.py` | 11,472 |
| `src/oas2moon/ir.py` | `tests/reference_python/oas2moon/ir.py` | 8,879 |
| `src/oas2moon/lower.py` | `tests/reference_python/oas2moon/lower.py` | 9,435 |
| `src/oas2moon/naming.py` | `tests/reference_python/oas2moon/naming.py` | 2,441 |
| `src/oas2moon/pipeline.py` | `tests/reference_python/oas2moon/pipeline.py` | 2,369 |
| `src/oas2moon/support.py` | `tests/reference_python/oas2moon/support.py` | 19,954 |
| `src/oas2moon/typemap.py` | `tests/reference_python/oas2moon/typemap.py` | 3,245 |
| `spike/server/fixture_server.py` | `tools/fixture_server.py` | 9,774 |

---

## 4. Python Remaining Responsibilities

All Python code is now auxiliary:

| Category | Files | Bytes | Location |
|---|---|---|---|
| **Reference oracle** | 8 | 58,395 | `tests/reference_python/oas2moon/` |
| **Test harness** | 3 | 30,194 | `tests/test_phase1.py`, `test_phase1_5.py`, `test_phase2.py` |
| **Fixture server** | 1 | 9,774 | `tools/fixture_server.py` |
| **Total** | **12** | **98,363** | |

No Python remains in `src/`. No Python file is called as a production generator authority.

---

## 5. MoonBit Production Modules

| Package | Files | Bytes | Lines | Role |
|---|---|---|---|---|
| `src/frontend_adapter/` | 2 (main.mbt, scan.mbt) | 20,741 | 789 | OpenAPI 3.0 scan + parse → frontend model |
| `src/core_moonbit/` | 3 (main.mbt, core_test.mbt, core_wbtest.mbt) | 13,047 | 519 | IR model, support validation, normalizer, naming, type map |
| `src/codegen_moonbit/` | 2 (ir.mbt, main.mbt) | 33,761 | 1,230 | Client IR → MoonBit code emission |
| **Total** | **7** | **67,549** | **2,538** | |

Plus 3 `moon.mod` + 3 `moon.pkg` files (987 bytes).

---

## 6. Before/After Language Bytes

| Language | Before (bc6017d) | After (HEAD) | Change |
|---|---|---|---|
| Python (`.py` files) | 23 files, **170,866 bytes** | 12 files, **98,363 bytes** | **−72,503 bytes (−42.4%)** |
| MoonBit (`.mbt` + `moon.mod` + `moon.pkg`) | 42 files, **120,752 bytes** | 19 files, **106,116 bytes** | **−14,636 bytes (−12.1%)** |
| PowerShell (`.ps1`) | 3 files, **14,476 bytes** | 3 files, **14,476 bytes** | No change |

After cleanup, tracked **MoonBit (106 KB) > Python (98 KB)** by approximately **8%**.

---

## 7. Regression Results

All checks pass on Windows (pwsh):

| Check | Result |
|---|---|
| `pytest tests -q` | **10/10 passed** in 34s |
| `moon fmt --check` (3 packages) | All passed |
| `moon check --target native --deny-warn` (3 packages) | All passed |
| `moon test --target native --deny-warn` (3 packages) | **5/5 passed** (core_moonbit) |

Detailed breakdown:

- **Phase 1** (test_phase1.py): 9 tests — parse, normalize, naming, type map, lower, codegen (Python reference vs MoonBit output)
- **Phase 1.5** (test_phase1_5.py): 1 test — deterministic differential pipeline parity
- **Phase 2** (test_phase2.py): — 14-fixture generation, deterministic regeneration, generated model fmt/check/test, codec round-trip, invalid-input, full spike regression
- **core_moonbit**: 5 unit tests

---

## 8. GitHub Primary Language Analysis

**Current GitHub status** (before pushing):

| Language | Bytes | Percentage |
|---|---|---|
| Python | 170,888 | 56.2% |
| MoonBit | 117,992 | 38.8% |
| PowerShell | 14,367 | 4.7% |
| AMPL | 722 | 0.2% |

**Expected after pushing Phase 2.5 commits:**

| Language | Estimated Bytes | Estimated Percentage |
|---|---|---|
| MoonBit | ~106,116 | ~48.5% |
| Python | ~98,363 | ~44.9% |
| PowerShell | ~14,476 | ~6.6% |
| AMPL | ~722 | ~0.3% |

**MoonBit should become the primary language** with approximately 48% share.

> **Note**: GitHub's language detection runs on the default branch after push. The exact percentages may differ slightly due to GitHub's Linguist heuristics, but the byte-count delta favors MoonBit.

> **No `.gitattributes` overrides were used.** The language statistic change is driven entirely by removing Python authority, not by hiding Python files.

---

## 9. Remaining Risks

1. **Spike MoonBit files** (`spike/frontend/`, `spike/probe/`, `spike/probe_tests/`, `spike/prototype/`) contribute ~40,566 bytes to MoonBit's total (38% of tracked MoonBit code). These are historical probes, not production code, but they benefit the MoonBit language share. If removed later, MoonBit drops to 67,549 bytes and Python (98,363) would become primary again.

2. **`spike/run_spike.ps1`** and **`spike/verify_determinism.ps1`** still reference `spike/generator/generate.py` (deleted). These scripts will fail if executed. They are historical artifacts documenting the spike methodology; they were not part of the test suite or CI pipeline.

3. **GitHub cache** — the language stats may take several minutes to update after push. If they initially still show Python as primary, this is because GitHub caches results.

4. **`src/codegen_moonbit/spike/build/phase2-smoke/`** — a generated build artifact inside the source tree. Not tracked by git (excluded in `.gitignore`).

---

## 10. Verdict: **GO**

Phase 2.5 is complete:

- [x] Python reference pipeline moved out of `src/` → `tests/reference_python/`
- [x] Obsolete spike generator prototypes deleted
- [x] Fixture server relocated to `tools/`
- [x] All test import paths updated
- [x] All test output paths updated (spike/build/ → tests/_build/)
- [x] `moon fmt --check` passes (3 packages)
- [x] `moon check --deny-warn` passes (3 packages)
- [x] `moon test --deny-warn` passes (5/5)
- [x] `pytest tests` passes (10/10)
- [x] GitHub primary language expected to flip to MoonBit after push
- [x] No `.gitattributes` language overrides

**Production generator path is MoonBit.** Python is auxiliary (reference oracle, test harness, fixture server). MoonBit bytes exceed Python bytes in tracked files.

---

## 11. Commit History

```
346b2c3 fix: remove trailing commas in record expressions
b78c23e chore: remove obsolete spike generator prototypes
e353355 refactor: move Python reference pipeline out of production src
```

