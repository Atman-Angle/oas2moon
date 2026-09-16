#!/usr/bin/env python3
"""oas2moon — OpenAPI 3.0.x → typed MoonBit client SDK generator.

Usage:
  python -m oas2moon generate <input> --module <module> --out <directory>
  python oas2moon.py generate <input> --module <module> --out <directory>
"""

import sys
from pathlib import Path

# Add src/ to the Python path so that `from oas2moon.cli import main` works.
_src = Path(__file__).resolve().parent / "src"
sys.path.insert(0, str(_src))

from oas2moon.cli import main

if __name__ == "__main__":
    sys.exit(main())