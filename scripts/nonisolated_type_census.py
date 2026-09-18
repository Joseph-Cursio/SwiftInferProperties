#!/usr/bin/env python3
"""How many refutable laws sit inside a `nonisolated` TYPE in a MainActor-default target?

#482 fills in a target's `.defaultIsolation` wherever a row carries no actor, and skips a
declaration that spells `nonisolated` itself. It reads that keyword on FUNCTIONS only, so a
`nonisolated` TYPE still has its members hopped (#522). This prices that gap.

**The question is refutable laws, not suggestions.** A hop that was not needed still compiles,
so an unnecessary one costs nothing unless it sits under a law that could have failed. The
determinism fallback's `f(x) == f(x)` is not such a law by construction.

Built on `measurement.py` for `swift_files` and its `EXCLUDED_DIRS`, because a census that
walks `.build/checkouts` counts vendored copies -- the eighth instrument error this repository
recorded.

⚠ **This is a TEXT scan for the type declarations**, which the repository's own rule says to
read as a floor: the scanner records no isolation modifier on a type, so there is nothing to
ask. It matches both modifier orders (`nonisolated public enum`, `public nonisolated struct`)
and allows the modifier on its own line. The SUGGESTION side is not a text scan -- it is
`discover`'s own output, joined on file and line.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import measurement  # noqa: E402

# Two orders, because Swift permits both and the first version of this missed one of them.
_ORDERS = (
    re.compile(r"(?:^|\n)[ \t]*(?:(?:public|internal|private|fileprivate|final|@[\w.]+)[ \t\n]+)*"
               r"nonisolated(?:\(unsafe\))?[ \t\n]+"
               r"(?:(?:public|internal|private|fileprivate|final)[ \t\n]+)*"
               r"(struct|enum|class|actor|extension)[ \t]+(\w+)"),
    re.compile(r"(?:^|\n)[ \t]*(?:(?:public|internal|private|fileprivate|final)[ \t\n]+)+"
               r"nonisolated(?:\(unsafe\))?[ \t\n]+"
               r"(struct|enum|class|actor|extension)[ \t]+(\w+)"),
)

_LOCATION = re.compile(r"^\s*(/\S+\.swift):(\d+)\s*$")
_TAUTOLOGY = "determinism tautology"


def nonisolated_type_ranges(base):
    """`(path, name, first_line, last_line)` for each `nonisolated` type declaration.

    Brace-matched rather than a fixed window, following `measurement.declaration_blocks`: a
    40-line window cannot see where a type ends, and the line range is the whole point here.
    """
    for path in measurement.swift_files(base):
        try:
            text = open(path, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        seen = set()
        for pattern in _ORDERS:
            for match in pattern.finditer(text):
                key = (match.start(), match.group(2))
                if key in seen:
                    continue
                seen.add(key)
                brace = text.find("{", match.end())
                if brace < 0:
                    continue
                depth, index = 0, brace
                while index < len(text):
                    if text[index] == "{":
                        depth += 1
                    elif text[index] == "}":
                        depth -= 1
                        if depth == 0:
                            break
                    index += 1
                yield (os.path.realpath(path), match.group(2),
                       text.count("\n", 0, brace) + 1, text.count("\n", 0, index) + 1)


def suggestions_inside(discover_output, ranges):
    """`(type, subject, is_tautology)` for each suggestion declared inside one of `ranges`."""
    lines = open(discover_output, encoding="utf-8", errors="ignore").read().splitlines()
    found = []
    for index, line in enumerate(lines):
        match = _LOCATION.match(line)
        if not match:
            continue
        path, number = os.path.realpath(match.group(1)), int(match.group(2))
        for block_path, name, first, last in ranges:
            if block_path != path or not first <= number <= last:
                continue
            subject = next((lines[back].strip() for back in range(index - 1, max(0, index - 4), -1)
                            if lines[back].strip().startswith("•")), "?")
            context = " ".join(text.strip() for text in lines[index + 1:index + 4])
            found.append((name, subject, _TAUTOLOGY in context))
    return found


def main(argv):
    if len(argv) != 3:
        print("usage: nonisolated_type_census.py <package-dir> <discover-output>")
        return 2
    ranges = list(nonisolated_type_ranges(os.path.abspath(argv[1])))
    found = suggestions_inside(argv[2], ranges)
    tautologies = sum(1 for _, _, taut in found if taut)
    print(f"nonisolated types {len(ranges)} · suggestions inside {len(found)} · "
          f"tautologies {tautologies} · REFUTABLE {len(found) - tautologies}")
    for name, subject, taut in found:
        print(f"  {'tautology' if taut else 'REFUTABLE':<10} {name:<24} {subject}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
