#!/usr/bin/env python3
"""Census: functions sharing a name AND a signature across DIFFERENT enclosing types.

The candidate pairing rule behind `docs/measurements/same-name-differential-pairing.md`.
`DifferentialTemplate` currently pairs only on a name MARKER (`fooSlow`,
`appendUnchecked`), so duplication spelled as the same name in a different type is
invisible to it — nine copies of one generic-parameter strip in this repo alone.

Study tooling, not product code: nothing in the shipped targets imports `scripts/`,
and `make test` does not run it (CLAUDE.md).

Deliberately crude — a regex walk, not SwiftSyntax. This measures whether the SHAPE is
worth templating; if it is, the real implementation reads `FunctionSummary` where the
enclosing type, parameter types and protocol conformances are already resolved. A
scorer that needed the production parser to exist first would invert the order this
study depends on.

Usage:  same_name_pairs.py <repo> [<repo> ...]
"""
import re
import sys
import json
from pathlib import Path
from collections import defaultdict

# `func name(params) -> Return`, capturing enough to compare signatures. Generic
# parameter lists are tolerated but not compared.
FUNC = re.compile(
    r'^(?P<indent>[ \t]*)'
    r'(?P<mods>(?:@\w+(?:\([^)]*\))?\s+|public\s+|private\s+|internal\s+|fileprivate\s+|'
    r'static\s+|class\s+|final\s+|override\s+|mutating\s+|nonmutating\s+)*)'
    r'func\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*'
    r'(?:<[^>]*>)?\s*'
    r'\((?P<params>[^)]*)\)'
    r'(?P<effects>(?:\s+(?:async|throws|rethrows))*)'
    r'(?:\s*->\s*(?P<ret>[^{\n]+?))?\s*\{',
    re.MULTILINE,
)

# Enclosing type declarations, tracked by indentation depth.
TYPE = re.compile(
    r'^(?P<indent>[ \t]*)(?:public\s+|private\s+|internal\s+|fileprivate\s+|final\s+|'
    r'@\w+(?:\([^)]*\))?\s+)*'
    r'(?P<kind>struct|class|enum|actor|extension|protocol)\s+(?P<name>[A-Za-z_][A-Za-z0-9_.]*)',
    re.MULTILINE,
)

# Names that are protocol requirements or language/lifecycle hooks. Two types
# implementing these share a name BECAUSE A PROTOCOL MADE THEM — the opposite of
# someone writing the same function twice (prediction P2).
PROTOCOL_REQUIREMENTS = {
    "==", "!=", "<", "<=", ">", ">=", "hash", "encode", "init", "callAsFunction",
    "next", "makeIterator", "index", "formIndex", "distance", "subscript",
    "run", "main", "validate", "description", "debugDescription",
    "visit", "visitPost", "visitAny", "walk",
    "encodeIfPresent", "decode", "decodeIfPresent",
}


def enclosing_types(text):
    """[(start_offset, end_hint, type_name)] — crude scope stack by indentation."""
    stack = []
    spans = []
    for match in TYPE.finditer(text):
        indent = len(match.group("indent").expandtabs(4))
        while stack and stack[-1][0] >= indent:
            stack.pop()
        stack.append((indent, match.group("name"), match.start()))
        spans.append((match.start(), match.group("name"), indent))
    return spans


def type_at(spans, offset, indent):
    """Innermost type declared before `offset` at a strictly smaller indent."""
    best = None
    for start, name, type_indent in spans:
        if start < offset and type_indent < indent:
            best = name
    return best


def normalise_params(params):
    """Parameter TYPES only — labels and names are not part of the contract."""
    out = []
    depth = 0
    current = ""
    for ch in params:
        if ch in "<([":
            depth += 1
        elif ch in ">)]":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(current)
            current = ""
        else:
            current += ch
    if current.strip():
        out.append(current)
    types = []
    for part in out:
        part = part.strip()
        if ":" in part:
            part = part.split(":", 1)[1]
        types.append(re.sub(r"\s+", " ", part.strip().rstrip("=").strip()))
    return tuple(types)


def scan(repo):
    rows = []
    for path in sorted(Path(repo).rglob("*.swift")):
        parts = set(path.parts)
        if ".build" in parts or "Tests" in parts or "checkouts" in parts:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        spans = enclosing_types(text)
        for match in FUNC.finditer(text):
            indent = len(match.group("indent").expandtabs(4))
            owner = type_at(spans, match.start(), indent)
            if owner is None:
                continue  # free function; no enclosing type to differ in
            ret = (match.group("ret") or "Void").strip()
            rows.append({
                "repo": Path(repo).name,
                "file": str(path.relative_to(repo)),
                "owner": owner,
                "name": match.group("name"),
                "params": normalise_params(match.group("params")),
                "ret": re.sub(r"\s+", " ", ret),
                "mods": match.group("mods").strip(),
            })
    return rows


def main():
    repos = sys.argv[1:]
    if not repos:
        print(__doc__)
        return 1

    by_signature = defaultdict(list)
    total = 0
    for repo in repos:
        for row in scan(repo):
            total += 1
            key = (row["repo"], row["name"], row["params"], row["ret"])
            by_signature[key].append(row)

    raw, filtered = [], []
    for key, rows in by_signature.items():
        owners = {r["owner"] for r in rows}
        if len(owners) < 2:
            continue  # same name in ONE type = overload, not a second implementation
        group = {
            "repo": key[0], "name": key[1],
            "params": list(key[2]), "ret": key[3],
            "owners": sorted(owners),
            "files": sorted({r["file"] for r in rows}),
        }
        raw.append(group)
        if key[1] not in PROTOCOL_REQUIREMENTS:
            filtered.append(group)

    print(f"functions scanned:            {total}")
    print(f"RAW same-name/same-sig groups: {len(raw)}")
    print(f"after protocol-name exclusion: {len(filtered)}")
    print()
    by_repo = defaultdict(int)
    for g in filtered:
        by_repo[g["repo"]] += 1
    for repo, count in sorted(by_repo.items(), key=lambda kv: -kv[1]):
        print(f"  {repo:28s} {count}")

    Path("same-name-pairs.json").write_text(
        json.dumps({"raw": raw, "filtered": filtered}, indent=1)
    )
    print("\nwrote same-name-pairs.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
