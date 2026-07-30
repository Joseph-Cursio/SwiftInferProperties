#!/usr/bin/env python3
"""Stratified, seeded sampler for the swift.org property-style-test study.

`docs/swiftorg-property-test-study-scope.md` requires samples that are "stratified,
sampled not cherry-picked". That is only a checkable claim if the sampling is
**reproducible**, so this emits a manifest carrying the seed, the corpus SHA, the
population definition, and every selected site. Same seed + same SHA -> same sample,
and a reader can regenerate it rather than take the number on trust.

It deliberately does NOT classify. Q1's own guardrail is that a structural classifier
written for the earlier survey "read `result == Decimal(12340)` as a round-trip", and
that hazard recurred while building this study's corpus table (`associatedtype` counted
as associativity; protobuf's `idempotencyLevel` counted as idempotence). So this tool
locates candidate sites and stops. Adjudication is by hand, into the findings doc.

Usage:
    scripts/swiftorg_sample.py --repo ~/GitHub_projects/swift --population check-battery
    scripts/swiftorg_sample.py --repo ... --population loops --size 30 --seed 20260730
"""
from __future__ import annotations

import argparse
import json
import os
import random
import re
import subprocess
import sys

# Population definitions. Each is (regex, description). A "site" is one match with its
# file and 1-indexed line, which is the unit a human adjudicates.
#
# `.gyb` is included deliberately and is a Q1 decision, not an accident: 24 of the 57
# files carrying `check*` sites in `swift` are gyb TEMPLATES, which expand to N
# instantiations at build time. Counting the template once undercounts what executes;
# counting expansions needs a gyb run. The manifest records the extension so the
# adjudication can split them, and the scope doc's Q1 has to settle it.
POPULATIONS: dict[str, tuple[re.Pattern[str], str]] = {
    "check-battery": (
        re.compile(
            r"\bcheck(?:Equatable|Hashable|Comparable|Collection|Sequence"
            r"|BidirectionalCollection|RandomAccessCollection|MutableCollection)\("
        ),
        "StdlibUnittest / _CollectionsTestSupport axiom batteries",
    ),
    "loops": (
        re.compile(r"for\s+_\s+in\s+0\s*\.\.<\s*\d+"),
        "hand-rolled repetition quantifier",
    ),
    "roundtrip": (
        re.compile(r"round[-_ ]?trip", re.IGNORECASE),
        "round-trip named tests and helpers",
    ),
    "lit-checknot": (
        re.compile(r"^\s*//\s*CHECK-NOT:"),
        "lit + FileCheck negative-assertion verifiers",
    ),
}

SKIP_DIRS = {".git", ".build", "node_modules"}
SOURCE_SUFFIXES = (".swift", ".gyb")

# Path fragments whose matches are the battery's own IMPLEMENTATION, not a call site.
# `StdlibUnittest` defines `checkEquatable` and calls it internally from
# `checkHashable`; `_CollectionsTestSupport` does the same for its own helpers. A
# definition is not a test, and counting 25 of them on `swift` inflated the population
# by ~9% before this was excluded.
IMPLEMENTATION_PATHS = (
    "stdlib/private/StdlibUnittest",
    "stdlib/private/StdlibCollectionUnittest",
    "_CollectionsTestSupport",
)


def corpus_sha(repo: str) -> str:
    result = subprocess.run(
        ["git", "-C", repo, "rev-parse", "HEAD"], capture_output=True, text=True
    )
    return result.stdout.strip() or "UNKNOWN"


def collect(repo: str, pattern: re.Pattern[str], roots: list[str]) -> list[dict]:
    """Every match, in a deterministic order — sorted, so the sample depends only on
    the seed and the corpus, never on filesystem walk order."""
    sites: list[dict] = []
    search_roots = [os.path.join(repo, r) for r in roots] if roots else [repo]
    for root in search_roots:
        if not os.path.isdir(root):
            continue
        for base, dirs, files in os.walk(root):
            dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
            for name in sorted(files):
                if not name.endswith(SOURCE_SUFFIXES):
                    continue
                path = os.path.join(base, name)
                if any(frag in path for frag in IMPLEMENTATION_PATHS):
                    continue
                try:
                    lines = open(path, encoding="utf-8", errors="ignore").read().split("\n")
                except OSError:
                    continue
                for index, line in enumerate(lines, start=1):
                    if pattern.search(line):
                        sites.append({
                            "file": os.path.relpath(path, repo),
                            "line": index,
                            "ext": name.rsplit(".", 1)[-1],
                            "text": line.strip()[:160],
                        })
    return sorted(sites, key=lambda s: (s["file"], s["line"]))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--population", required=True, choices=sorted(POPULATIONS))
    parser.add_argument("--size", type=int, default=30)
    parser.add_argument("--seed", type=int, default=20260730)
    parser.add_argument(
        "--roots", nargs="*", default=[],
        help="subdirectories to restrict to (default: whole repo). For `swift`, Q1 "
             "established that this MUST be the stdlib test dirs: an unscoped count is "
             "91%% compiler-test noise (loops 95%%, lit-checknot 100%%). See "
             "docs/swiftorg-property-test-study-findings.md 1.1.",
    )
    parser.add_argument("--out", default="-")
    args = parser.parse_args()

    repo = os.path.abspath(os.path.expanduser(args.repo))
    pattern, description = POPULATIONS[args.population]
    sites = collect(repo, pattern, args.roots)

    # Sample WITHOUT replacement from the sorted population, seeded. `random.Random`
    # rather than the module-global, so an import elsewhere cannot perturb it.
    rng = random.Random(args.seed)
    chosen = sorted(
        rng.sample(sites, min(args.size, len(sites))),
        key=lambda s: (s["file"], s["line"]),
    )

    manifest = {
        "corpus": os.path.basename(repo),
        "corpus_sha": corpus_sha(repo),
        "roots": args.roots or ["<whole repo>"],
        "population": args.population,
        "population_description": description,
        "population_total": len(sites),
        "by_extension": {
            ext: sum(1 for s in sites if s["ext"] == ext)
            for ext in sorted({s["ext"] for s in sites})
        },
        "seed": args.seed,
        "sample_size": len(chosen),
        "sites": chosen,
    }
    text = json.dumps(manifest, indent=2)
    if args.out == "-":
        print(text)
    else:
        with open(args.out, "w") as handle:
            handle.write(text + "\n")
        print(
            f"{args.population}: {len(sites)} sites "
            f"({', '.join(f'{k}={v}' for k, v in manifest['by_extension'].items())}) "
            f"-> sampled {len(chosen)} @ seed {args.seed} -> {args.out}",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
