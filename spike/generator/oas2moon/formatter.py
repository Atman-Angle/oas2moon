"""Canonical emission formatting.

The emitter renders MoonBit text; this stage runs the real toolchain formatter
(``moonfmt``) over every rendered file so that a freshly generated tree is
already in the exact shape ``moon fmt`` would produce. Running the formatter
here keeps "generated code passes ``moon fmt``" a property of the generator
instead of a repair step performed by the caller.

The stage is intentionally loud: if ``moonfmt`` is missing or fails, generation
aborts. Unformatted output is never written silently.
"""

from __future__ import annotations

import shutil
import subprocess


class FormatterUnavailable(RuntimeError):
    """``moonfmt`` cannot be used, so canonical output is impossible."""


def file_type(path: str) -> str:
    """The ``moonfmt -file-type`` value for a generated path."""

    if path.endswith(".mbt"):
        return "mbt"
    if path.endswith("moon.pkg"):
        return "pkg"
    if path.endswith("moon.mod"):
        return "mod"
    raise FormatterUnavailable(f"no moonfmt file type is known for {path}")


def canonicalize(text: str, path: str) -> str:
    """Return ``text`` exactly as ``moonfmt`` would write it."""

    executable = shutil.which("moonfmt")
    if executable is None:
        raise FormatterUnavailable(
            "moonfmt was not found on PATH; install the MoonBit toolchain"
        )
    source = text if text.endswith("\n") else text + "\n"
    completed = subprocess.run(
        [executable, "-", "-file-type", file_type(path)],
        input=source.encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.decode("utf-8", "replace").strip()
        raise FormatterUnavailable(f"moonfmt failed for {path}: {detail}")
    formatted = completed.stdout.decode("utf-8").replace("\r\n", "\n")
    return formatted if formatted.endswith("\n") else formatted + "\n"
