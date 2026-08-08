#!/usr/bin/env python3
"""Extract the Q2 answer key from swift.org's own axiom-battery call sites.

`docs/archive/swiftorg-property-test-study-scope.md` Q2: *"a tool may not grade its own homework.
Extract the answer key mechanically from the `check*` call sites and freeze it with a SHA
BEFORE running `discover`."* This is that extractor, and running it before `discover` is
the whole point — the key must not be able to have been influenced by what we found.

What a key entry is: **a law that a human asserted about a type, with a location**. The
laws are not inferred; they are read off `StdlibUnittest`'s own documented semantics, which
are quoted in `BATTERY_LAWS` below with the source line each was taken from.

Deliberately NOT extracted: the concrete instance list. Q5 already measured that domain
(median 2.5 elements) and the key is about *which law was asserted*, not how well.

Usage:
    scripts/swiftorg_answer_key.py --repo ~/GitHub_projects/swift \\
        --roots test/stdlib validation-test/stdlib --out key.json
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess

# Battery -> the laws it executes. Read from StdlibUnittest.swift's implementation, not
# guessed: `checkEquatable` asserts "bad oracle: broken reflexivity at index" (:3108),
# "broken symmetry between indices" (:3116) and "broken transitivity at indices" (:3151);
# `checkComparable` asserts "missing antisymmetry" (:3457) and "missing transitivity"
# (:3490). The collection batteries check their protocol's index/traversal contract.
BATTERY_LAWS: dict[str, list[str]] = {
    "checkEquatable": ["equatable.reflexive", "equatable.symmetric", "equatable.transitive"],
    "checkHashable": [
        "equatable.reflexive", "equatable.symmetric", "equatable.transitive",
        "hashable.consistency",
    ],
    "checkHashableGroups": ["hashable.consistency"],
    "checkComparable": [
        "comparable.antisymmetric", "comparable.transitive", "comparable.strictWeakOrdering",
    ],
    "checkSequence": ["sequence.iterationContract"],
    "checkCollection": ["collection.indexContract"],
    "checkBidirectionalCollection": ["collection.indexContract", "collection.bidirectional"],
    "checkRandomAccessCollection": ["collection.indexContract", "collection.randomAccess"],
    "checkMutableCollection": ["collection.indexContract", "collection.mutable"],
}

CALL = re.compile(r"\b(check[A-Z]\w*)\s*\(")
# The example-assertion overloads lead with a Bool — `check…(true, a, b)` or
# `check…(expectedEqual: true, …)`. Q1 measured these at 12% of the naive population and
# excluded them: they assert one fact about two named values, not a quantified law.
EXAMPLE_OVERLOAD = re.compile(r"\bcheck\w+\(\s*(?:expectedEqual:\s*)?(?:true|false)\b")
COMMENT = re.compile(r"^\s*(//|///|\*)")
IMPLEMENTATION_PATHS = (
    "stdlib/private/StdlibUnittest",
    "stdlib/private/StdlibCollectionUnittest",
    "_CollectionsTestSupport",
)


def subject_hint(line: str, battery: str) -> str:
    """Best-effort text of the first argument — a hint for attributing the carrier type,
    not a parse. Recorded as a hint precisely so nobody mistakes it for one."""
    start = line.find(battery + "(")
    if start < 0:
        return ""
    rest = line[start + len(battery) + 1:].strip()
    for stop in (",", ")"):
        index = rest.find(stop)
        if index > 0:
            rest = rest[:index]
    return rest.strip()[:60]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--roots", nargs="*", default=["test/stdlib", "validation-test/stdlib"])
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    repo = os.path.abspath(os.path.expanduser(args.repo))
    sha = subprocess.run(
        ["git", "-C", repo, "rev-parse", "HEAD"], capture_output=True, text=True
    ).stdout.strip()

    entries, skipped_example, skipped_comment, skipped_unknown = [], 0, 0, 0
    for root in args.roots:
        for base, dirs, files in os.walk(os.path.join(repo, root)):
            dirs[:] = sorted(d for d in dirs if d not in {".git", ".build"})
            for name in sorted(files):
                if not name.endswith((".swift", ".gyb")):
                    continue
                path = os.path.join(base, name)
                if any(frag in path for frag in IMPLEMENTATION_PATHS):
                    continue
                try:
                    lines = open(path, encoding="utf-8", errors="ignore").read().split("\n")
                except OSError:
                    continue
                for index, line in enumerate(lines, start=1):
                    match = CALL.search(line)
                    if not match:
                        continue
                    battery = match.group(1)
                    if COMMENT.match(line):
                        skipped_comment += 1
                        continue
                    if EXAMPLE_OVERLOAD.search(line):
                        skipped_example += 1
                        continue
                    if battery not in BATTERY_LAWS:
                        skipped_unknown += 1
                        continue
                    entries.append({
                        "file": os.path.relpath(path, repo),
                        "line": index,
                        "ext": name.rsplit(".", 1)[-1],
                        "battery": battery,
                        "laws": BATTERY_LAWS[battery],
                        "subject_hint": subject_hint(line, battery),
                    })

    laws_total: dict[str, int] = {}
    for entry in entries:
        for law in entry["laws"]:
            laws_total[law] = laws_total.get(law, 0) + 1

    key = {
        "frozen": "BEFORE any discover run — see scope Q2",
        "corpus": os.path.basename(repo),
        "corpus_sha": sha,
        "roots": args.roots,
        "site_count": len(entries),
        "distinct_laws": len(laws_total),
        "law_counts": dict(sorted(laws_total.items(), key=lambda kv: -kv[1])),
        "excluded": {
            "example_overload": skipped_example,
            "comment": skipped_comment,
            "unrecognised_check_name": skipped_unknown,
        },
        "entries": entries,
    }
    with open(args.out, "w") as handle:
        handle.write(json.dumps(key, indent=2) + "\n")
    print(f"key: {len(entries)} sites, {len(laws_total)} distinct laws @ {sha[:11]}")
    print(f"  excluded: {skipped_example} example-overload, {skipped_comment} comment, "
          f"{skipped_unknown} unrecognised")
    for law, count in sorted(laws_total.items(), key=lambda kv: -kv[1]):
        print(f"    {law:<36}{count:>5}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
