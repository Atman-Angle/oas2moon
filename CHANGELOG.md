# Changelog

## Unreleased — T15 release material

- Rewrote the README around the MoonBit-first authority boundary, runnable quick start, real HTTP demo, support limits, and hosted CI evidence.
- Classified support claims by evidence and recorded known gaps instead of future plans.
- Added release acceptance, third-party notices, five-minute demo instructions, and repository-hygiene/migration documentation.
- Removed two unreferenced broken Python editing helpers and three obsolete spike runners that invoked a deleted generator.
- Kept the remaining `spike/` sources as clearly labelled historical experiments.
- Serialized Petstore fixture capture writes and persist them before responses so repeated CI runs cannot observe stale or truncated wire evidence.
- Added a reproducible T12 corpus harness and manifest covering an official archived Petstore 3.0 sample plus curated GitHub/OpenAI/JSONPlaceholder subsets; the committed report records 5/5 real-world specs compiled and 12/12 operations supported.
- Fixed MoonBit PascalCase naming for the reserved type name `Error` (`ErrorValue`), found by the pinned official Petstore sample and covered by MoonBit/Python regressions.

## Hosted evidence referenced by this release

- `cross-platform-ci`, commit `040f488`, [run 35177945624](https://github.com/Atman-Angle/oas2moon/actions/runs/35177945624): completed successfully on Ubuntu and Windows. This is a recorded historical run, not a substitute for running CI on a release PR.

No version number, performance metric, or compatibility percentage is assigned by this file.
