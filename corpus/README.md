# Corpus (T12)

The corpus is the set of documents the project measures itself against. Its
purpose is to prove generality **without exaggerating support**: every number in
`docs/CORPUS_REPORT.md` must come from a document this repository can produce
again.

## Layout

```text
corpus/
├── README.md        this file
├── sources.json     the manifest: what is in the corpus and where it came from
└── _downloads/      fetched remote documents (git-ignored, never committed)
```

Nothing under `corpus/_downloads/` is committed. Big third-party API
descriptions would balloon the repository and change under us; the manifest
pins them instead.

## Manifest rules

`sources.json` has a `sources` array. Each entry is either:

- `"kind": "local"` — a document already in the repository, addressed by a
  repo-relative `path`;
- `"kind": "remote"` — addressed by `url` + `document`, and **only measurable
  once it carries a pinned `commit` and `sha256`**;
- `"kind": "planned"` — a source whose document is not even chosen yet. It must
  say what the next step is and is reported as pending until it becomes
  `local` or `remote`.

A remote entry without those pins stays `"status": "pending"` and the metrics
script reports it as `not_fetched`. That is deliberate: an unpinned download is
not evidence, and a report must never contain a number nobody can reproduce.

Every entry also carries:

- `role` — `real-world` for the API documents/subsets the published headline
  numbers come from, `control` for local fixtures that only guard the machinery.
  Controls are reported in their own block and never pad the real-world totals;
- `origin` / `license` — where the document came from and under what terms.
  Only redistribute documents whose license allows it; otherwise pin and fetch.

## Adding a source

1. Decide the document or subset. "GitHub REST" is far outside V1, so a
   subset (a tag, a path prefix, or a curated operation list) is what actually
   gets measured — state which one it is in `subset`. A full upstream sample is
   also valid when it remains inside the V1 profile.
2. For a remote source, pin the exact `commit` (not `main`) and record the
   document's `sha256`.
3. Run the metrics and commit the updated report:

   ```pwsh
   python tools/corpus_metrics.py `
       --json-out tests/_build/corpus-metrics/summary.json `
       --report-out docs/CORPUS_REPORT.md
   ```

4. If the new document exercises the determinism gate, add it to the corpus
   lists in `tests/test_t13_determinism.py` as well (`SPEC_CORPUS` for specs
   that generate, `REFUSED_SPECS` for specs that must be refused).

## What the numbers mean

See the T12 section of `docs/DEVELOPMENT_TASKS.md` for the exact definitions of
`operations_total`, `operations_supported`, `operations_rejected`,
`rejection_reasons` and `compile_pass`, including the spec-level granularity
caveat: V1 refuses a spec, not an operation.

`compile_pass` is only meaningful with the MoonBit toolchain available. Pass
`--skip-compile` for a quick structural run; a published report must not skip it.
