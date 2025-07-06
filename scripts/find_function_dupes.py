#!/usr/bin/env python3
"""
find_function_dupes.py – quick-n-dirty detector for copy-pasted Zig functions

How it works
------------
1. Recursively walks the `src/` tree (or an optional path argument).
2. Extracts every `pub fn` or `fn` declaration *along with* its body using a
   simple brace-depth tracker (fast but assumes balanced braces).
3. Normalises whitespace to compact the body and hashes it using `ssdeep`.
4. Compares each pair of hashes.  Pairs with a similarity > 90 % are reported
   as potential duplicates.
5. Writes a JSON report to `function_dupes.json`.

Usage
-----
    python scripts/find_function_dupes.py               # analyse ./src
    python scripts/find_function_dupes.py path/to/dir   # analyse custom dir

Requirements
------------
    pip install ssdeep

The output JSON maps the *first* occurrence of a function (file, name) tuple
onto a list of other (file, name) tuples that look almost identical.
You can import the JSON into your editor or CI to guide refactors.

This tool is intentionally lightweight – no full parsing – but good enough to
catch inadvertent copy-paste between backends, math helpers, etc.
"""

from __future__ import annotations

import json
import pathlib
import re
import sys
from typing import Dict, List, Tuple

# ---------------------------------------------------------------------------
# Optional ssdeep fuzzy hashing – falls back to stdlib difflib if unavailable
# ---------------------------------------------------------------------------

try:
    import ssdeep  # type: ignore

    def _hash(s: str) -> str:  # noqa: D401 – opaque hash token
        return ssdeep.hash(s)

    def _similar(a: str, b: str) -> int:
        return ssdeep.compare(a, b)

except ModuleNotFoundError:  # pragma: no cover – pure-python fallback
    from difflib import SequenceMatcher

    def _hash(s: str) -> str:
        """Return the input itself – hashes aren't needed for the fallback."""
        return s

    def _similar(a: str, b: str) -> int:
        """Return similarity percentage using difflib's quick_ratio."""
        return int(SequenceMatcher(None, a, b).ratio() * 100)

FUNC_RE = re.compile(r"(?:pub\\s+)?fn\\s+(\\w+)\\s*\\([^)]*\\)\\s*\\{")

# helpers
# ---------------------------------------------------------------------------


def iter_zig_files(root: pathlib.Path):
    for p in root.rglob("*.zig"):
        # ignore generated cache / build artefacts if the user runs the tool in
        # project root
        if "zig-cache" in p.parts or "zig-out" in p.parts:
            continue
        yield p


def extract_functions(source: str) -> List[Tuple[str, str]]:
    """Return list of (name, body) pairs"""
    functions: List[Tuple[str, str]] = []
    for m in FUNC_RE.finditer(source):
        name = m.group(1)
        start = m.start()
        i = m.end()  # position after opening brace
        depth = 1
        while i < len(source) and depth:
            if source[i] == '{':
                depth += 1
            elif source[i] == '}':
                depth -= 1
            i += 1
        body = source[start:i]
        # collapse whitespace to neutralise formatting differences
        body_clean = re.sub(r"\\s+", " ", body).strip()
        functions.append((name, body_clean))
    return functions


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main(argv: List[str] | None = None) -> None:  # pragma: no cover
    argv = argv or sys.argv[1:]
    root = pathlib.Path(argv[0]) if argv else pathlib.Path("src")
    if not root.exists():
        print(
            f"error: path {root} does not exist",
            file=sys.stderr,
        )
        sys.exit(1)

    tokens: Dict[Tuple[str, str], str] = {}
    for zig_file in iter_zig_files(root):
        try:
            code = zig_file.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            # skip binary or corrupted files
            continue
        for fn_name, body in extract_functions(code):
            tokens[(str(zig_file), fn_name)] = _hash(body)

    clusters: Dict[str, List[Tuple[str, str]]] = {}
    items = list(tokens.items())
    total = len(items)
    for i in range(total):
        (file1, name1), sig1 = items[i]
        for j in range(i + 1, total):
            (file2, name2), sig2 = items[j]
            score = _similar(sig1, sig2)
            if score > 90:
                clusters.setdefault(
                    f"{file1}::{name1}",
                    [],
                ).append((file2, name2))

    out_path = pathlib.Path("function_dupes.json")
    out_path.write_text(json.dumps(clusters, indent=2))
    print(f"✓ wrote {out_path} with {len(clusters)} duplicate groups")


if __name__ == "__main__":  # pragma: no cover
    main() 