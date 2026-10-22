#!/usr/bin/env python3
"""Census: where are the lexers, whatever their signature? The role probe of
`docs/measurements/lexer-corpus-prediction.md`.

`whole_to_parts_census.py` counts what a signature-keyed template could reach — free functions
shaped `(String) -> [T]`. This counts what it could NOT: every type named as a lexer
(`…Lexer`, `…Tokenizer`, `…Tokeniser`, `…Scanner`), and every method declared in the same file
that returns an array, a token, or a `Sequence` / `IteratorProtocol` — whatever its parameters.
Comparing the two is prediction P2: the real lexers are objects holding their input, so the
shape probe misses them.

Deliberately crude regex matching, like its sibling. It is a POPULATION estimate for a
build/decline decision; every row it prints is hand-classified afterwards, so a false match
costs a line of reading and a miss makes the population look smaller — the safe direction.
"""
import re
import sys
from pathlib import Path

LEXER_TYPE = re.compile(
    r"^\s*(?:public\s+|internal\s+|fileprivate\s+|private\s+|open\s+|final\s+)*"
    r"(?:class|struct|enum|actor|extension)\s+(\w*(?:Lexer|Tokenizer|Tokeniser|Scanner))\b",
    re.MULTILINE,
)
# Any `func name(...) -> Ret`, with Ret captured up to the opening brace or `where`.
FUNC = re.compile(
    r"func\s+(\w+)\s*(?:<[^>]*>)?\s*\(([^)]*)\)\s*(?:async\s+)?(?:(?:re)?throws(?:\([^)]*\))?\s+)?"
    r"->\s*([^{\n]+?)\s*(?:where\b|\{|$)",
    re.MULTILINE,
)
TOKEN_RETURN = re.compile(r"^\[|Token|Sequence|Iterator|Lexeme|Segment")
SKIP = {".build", "Tests", "checkouts", ".git", "Benchmarks", "Fuzzing", "Playground"}


def scan(repo: Path):
    types, methods = [], []
    for path in repo.rglob("*.swift"):
        if any(p in SKIP or p.endswith(".playground") for p in path.parts):
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        names = sorted(set(LEXER_TYPE.findall(text)))
        if not names:
            continue
        rel = str(path.relative_to(repo))
        types.extend((repo.name, name, rel) for name in names)
        for match in FUNC.finditer(text):
            name, params, ret = match.group(1), match.group(2), match.group(3).strip()
            if TOKEN_RETURN.search(ret):
                methods.append((repo.name, rel, name, " ".join(params.split()), ret))
    return types, methods


def main(repos):
    all_types, all_methods = [], []
    for spec in repos:
        repo = Path(spec).expanduser()
        if repo.is_dir():
            types, methods = scan(repo)
            all_types.extend(types)
            all_methods.extend(methods)

    repos_with = sorted({t[0] for t in all_types})
    print(f"lexer-named types                  : {len({(t[0], t[1]) for t in all_types})}")
    print(f"packages declaring one             : {len(repos_with)} — {', '.join(repos_with)}")
    print(f"token-returning methods beside them: {len(all_methods)}")
    print()
    print("lexer-named types:")
    for repo, name, rel in sorted(set(all_types)):
        print(f"  [{repo}] {name}    {rel}")
    print()
    print("methods, for hand classification (params empty = the input is held, not passed):")
    for repo, rel, name, params, ret in sorted(all_methods):
        print(f"  [{repo}] {name}({params}) -> {ret}")
        print(f"      {rel}")


if __name__ == "__main__":
    main(sys.argv[1:])
