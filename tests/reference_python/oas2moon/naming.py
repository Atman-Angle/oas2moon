"""Naming and identifier rules.

Deterministic by construction: the same input identifier always produces the
same output identifier, and collisions are resolved by appending the smallest
counter that is still free.
"""

from __future__ import annotations

import re

_CHUNK = re.compile(r"[A-Za-z0-9]+")
_PART = re.compile(r"[A-Z]+(?=[A-Z][a-z])|[A-Z]?[a-z]+|[A-Z]+|[0-9]+")

# MoonBit keywords plus a few identifiers that would shadow generated helpers.
RESERVED = frozenset(
    {
        "as", "async", "break", "catch", "const", "continue", "else", "enum",
        "false", "fn", "for", "guard", "if", "impl", "import", "in", "init",
        "is", "let", "match", "mut", "noraise", "package", "priv", "pub",
        "raise", "return", "self", "static", "struct", "suberror", "test",
        "trait", "true", "try", "type", "while", "with",
        # generated helper names
        "client", "config", "json", "new", "to_json", "from_json", "to_wire",
    }
)


def words(name: str) -> list[str]:
    """Split an arbitrary identifier or wire name into lower-case words."""

    out: list[str] = []
    for chunk in _CHUNK.findall(name):
        out.extend(part.lower() for part in _PART.findall(chunk) if part)
    return out


def snake(name: str) -> str:
    """``getPetById`` / ``X-Trace`` -> ``get_pet_by_id`` / ``x_trace``."""

    parts = words(name)
    if not parts:
        return "value"
    head, *tail = parts
    if head.isdigit():
        parts = ["v", *parts]
    candidate = "_".join(parts)
    if candidate in RESERVED:
        candidate += "_"
    return candidate


def pascal(name: str) -> str:
    """``pet_status`` / ``petStatus`` -> ``PetStatus``."""

    parts = words(name)
    if not parts:
        return "Value"
    if parts[0].isdigit():
        parts = ["v", *parts]
    candidate = "".join(part[:1].upper() + part[1:] for part in parts)
    if candidate in RESERVED:
        candidate += "Value"
    return candidate


def unique(name: str, taken: set[str]) -> str:
    """Return ``name``, or the first free ``name_2``, ``name_3``, ..."""

    if name not in taken:
        taken.add(name)
        return name
    counter = 2
    while f"{name}_{counter}" in taken:
        counter += 1
    resolved = f"{name}_{counter}"
    taken.add(resolved)
    return resolved


def upper_snake(name: str) -> str:
    """Upper-case snake case, used for header wire names."""

    return "_".join(words(name)).upper()
