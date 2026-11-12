#!/usr/bin/env python3
"""#672's census — `docs/plans/sanitizer-alphabet-census-scope.md` §2–§7.

The rows are read in Swift, by `fixtures/sanitizer-alphabet/census-run/`, because the scope reads bodies with a
syntax reader, not a grep. This script freezes the universe the harness reads and turns the harness's output,
plus the hand-check, into the decision.

    python3 scripts/sanitizer_alphabet_census.py controls <subjects.json>
        assert the frozen universe (§3) and write the subject list the harness reads
    python3 scripts/sanitizer_alphabet_census.py report <census.json> [<handcheck.json>]
        print the per-law counts and the decision (§7)
"""
import collections
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import measurement  # noqa: E402
from budgeted_truncation_census import FUNNEL  # noqa: E402
from count_threshold_census import FROZEN_MANIFEST, HOME, subject  # noqa: E402

REPOSITORY = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
#: §7: fewer than this many rows in E2 is a decline; more than this many in E1 reopens law 1.
MINIMUM_EMITTABLE = 5
LAW1_HOLD = 10


def controls(out_path):
    rows, asked = measurement.corpus_roots()
    ids = [corpus for corpus, _, _ in rows]
    if ids != FROZEN_MANIFEST:
        sys.exit(f"the manifest universe moved: {sorted(set(ids) ^ set(FROZEN_MANIFEST))}")
    subjects = [subject("manifest", corpus, root, dirs, False) for corpus, root, dirs in rows]
    missing = [name for name in FUNNEL if not os.path.isdir(os.path.join(HOME, "xcode_projects", name))]
    if missing or len(FUNNEL) != 19:
        sys.exit(f"the funnel universe moved: missing {missing}, {len(FUNNEL)} listed")
    for name in FUNNEL:
        root = os.path.join(HOME, "xcode_projects", name)
        subjects.append(subject("funnel", name, root, [root], True))
    sources = os.path.join(REPOSITORY, "Sources")
    if not os.path.isdir(sources):
        sys.exit("this repository's Sources/ is missing")
    # Last, so the files the `swift-infer-core` corpus already read are attributed to it (§3).
    subjects.append(subject("self", "SwiftInferProperties", REPOSITORY, [sources], False))
    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump(subjects, handle, indent=2, sort_keys=True)
        handle.write("\n")
    dirty = [s["name"] for s in subjects if s["dirty"]]
    print(f"{len(rows)} of {asked} manifest corpora resolve, all {len(FUNNEL)} funnel repositories present, "
          "and this repository's Sources/")
    print(f"dirty (recorded, not refused): {', '.join(dirty) or 'none'}")
    return 0


def by_repo(rows):
    return dict(collections.Counter(r["repository"] for r in rows).most_common())


def report(census_path, handcheck_path=None):
    census = json.load(open(census_path, encoding="utf-8"))
    verdicts = json.load(open(handcheck_path, encoding="utf-8")) if handcheck_path else {}
    rows = census["rows"]
    print(f"functions read: {census['functions']} in {census['files']} files, {len(census['subjects'])} subjects")
    admitted = [r for r in rows if r["admitted"]]
    pool = [r for r in rows if r["inPool"]]
    refused = [r for r in pool if not r["admitted"]]
    print(f"\nrecall pool {len(pool)} (admitted {sum(r['admitted'] for r in pool)}, refused {len(refused)}); "
          f"admitted outside the pool {sum(not r['inPool'] for r in admitted)}")
    print(f"  refusals: {dict(collections.Counter(r.get('refusal') for r in refused).most_common())}")
    print(f"\nadmitted {len(admitted)}: law 2 {len(admitted)}, law 1 {sum(r['law1'] for r in admitted)}; "
          f"candidates {sum(r['candidate'] for r in admitted)}")
    for row in admitted:
        reading = row["reading"]
        print(f"  {row['key']}  [{reading['core']}, pre={reading['preTransform']}, prefix={reading['prefixRule']}, "
              f"fallback={reading['fallback']}, and={reading['usesAnd']}, law1={row['law1']}, "
              f"candidate={row['candidate']} {row.get('candidateRefusal') or ''}]")
    unjudged = [r["key"] for r in admitted if r["key"] not in verdicts]
    if unjudged:
        print(f"\n{len(unjudged)} admitted rows unjudged: no decision")
        return 1
    defects = [r["key"] for r in admitted if not (verdicts[r["key"]].get("law2") and verdicts[r["key"]].get("predicate"))]
    if defects:
        print(f"\nreader defects: {defects}")
    good = [r for r in admitted if r["candidate"] and r["key"] not in defects
            and verdicts[r["key"]].get("emittable") is True]
    e2 = good
    e1 = [r for r in good if r["law1"] and verdicts[r["key"]].get("law1") is True]
    selfless = lambda rs: [r for r in rs if r["repository"] != "SwiftInferProperties"]
    print(f"\nE2 = {len(e2)} {by_repo(e2)}; without this repository {len(selfless(e2))}")
    print(f"E1 = {len(e1)} {by_repo(e1)}; without this repository {len(selfless(e1))}")
    top = collections.Counter(r["repository"] for r in e2).most_common(1)
    top = top[0] if top else (None, 0)
    build = len(e2) >= MINIMUM_EMITTABLE and top[1] * 2 <= len(e2)
    print(f"largest repository in E2: {top[0]} with {top[1]}")
    print("DECISION, law 2: BUILD" if build else "DECISION, law 2: DECLINE")
    print("law 1: REOPENING CANDIDATE (E1 > 10)" if len(e1) > LAW1_HOLD else "law 1: stays HELD")
    return 0


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "controls":
        return controls(sys.argv[2])
    if len(sys.argv) >= 3 and sys.argv[1] == "report":
        return report(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
    sys.exit(__doc__)


if __name__ == "__main__":
    sys.exit(main())
