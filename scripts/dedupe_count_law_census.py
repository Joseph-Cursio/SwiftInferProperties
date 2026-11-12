#!/usr/bin/env python3
"""#671's census — `docs/plans/dedupe-count-law-census-scope.md` §2–§7.

The rows are read in Swift, by `fixtures/dedupe-count-law/census-run/`, because the scope gates on syntax, not a
grep. This script freezes the universe the harness reads and turns the harness's output, plus the hand-check,
into the decision.

    python3 scripts/dedupe_count_law_census.py controls <subjects.json>
        assert the frozen universe (§3) and write the subject list the harness reads
    python3 scripts/dedupe_count_law_census.py report <census.json> [<handcheck.json>]
        print the funnel and the decision (§7)
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
#: §7: fewer than this many rows in E is not a build.
MINIMUM_EMITTABLE = 5


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


def first_refusal(row):
    return row.get("nameRefusal") or row.get("shapeRefusal") or row.get("bodyRefusal")


def report(census_path, handcheck_path=None):
    census = json.load(open(census_path, encoding="utf-8"))
    verdicts = json.load(open(handcheck_path, encoding="utf-8")) if handcheck_path else {}
    rows = census["rows"]
    family = [r for r in rows if r["inNameFamily"]]
    print(f"functions read: {census['functions']} in {census['files']} files, {len(census['subjects'])} subjects")

    named = [r for r in family if not r.get("nameRefusal")]
    shaped = [r for r in named if not r.get("shapeRefusal")]
    admitted = [r for r in shaped if not r.get("bodyRefusal")]
    candidates = [r for r in admitted if r["candidate"]]
    print(f"\nfunnel: name family {len(family)} -> name gate {len(named)} -> shape {len(shaped)} "
          f"-> body (admitted) {len(admitted)} -> candidates {len(candidates)}")
    print(f"  family by repository: {dict(collections.Counter(r['repository'] for r in family).most_common())}")
    print(f"  first refusal: {dict(collections.Counter(first_refusal(r) for r in family if first_refusal(r)).most_common())}")
    print(f"  shape passes, name refused: {[r['key'] for r in family if r.get('nameRefusal') and not r.get('shapeRefusal')]}")
    recognised = [r for r in family if r["recognisedToday"]]
    print(f"  recognised today: {len(recognised)}; of them admitted {sum(r['admitted'] for r in recognised)}; "
          f"idempotence fires today on {sum(r['idempotenceToday'] for r in recognised)}")

    print("\nadmitted rows:")
    for row in admitted:
        print(f"  {row['key']}  [{row.get('route')}, keepFirst={row.get('keepFirst')}, recognised={row['recognisedToday']}, "
              f"idempotenceToday={row['idempotenceToday']}, candidate={row['candidate']} {row.get('candidateRefusal') or ''}]")

    outside = [r for r in rows if not r["inNameFamily"]]
    print(f"\nunscored: {len(outside)} functions outside the name family pass shape and body")
    for row in outside:
        print(f"  {row['key']}  [{row.get('route')}, candidate={row['candidate']}]")

    unjudged = [r["key"] for r in admitted if r["key"] not in verdicts]
    if unjudged:
        print(f"\n{len(unjudged)} admitted rows unjudged: no decision")
        return 1
    defects = [r["key"] for r in admitted if not (verdicts[r["key"]].get("c1") and verdicts[r["key"]].get("c2"))]
    if defects:
        print(f"\ngate defects (a count law false of today's code): {defects}")
    e_rows = [r for r in candidates if verdicts[r["key"]].get("emittable") is True and r["key"] not in defects]
    for row in admitted:
        verdict = verdicts[row["key"]]
        print(f"  {row['key']}: emittable={verdict.get('emittable')} {verdict.get('note', '')}")
    repos = collections.Counter(r["repository"] for r in e_rows)
    top = repos.most_common(1)[0] if repos else (None, 0)
    a_rows = [r for r in e_rows if r["recognisedToday"]]
    print(f"\nE = {len(e_rows)} {[r['key'] for r in e_rows]}; largest repository {top[0]} with {top[1]}")
    print(f"A = {len(a_rows)} {[r['key'] for r in a_rows]}")
    if len(e_rows) >= MINIMUM_EMITTABLE and top[1] * 2 <= len(e_rows):
        print("DECISION: BUILD")
    elif a_rows:
        print("DECISION: ATTACH")
    else:
        print("DECISION: DECLINE")
    return 0


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "controls":
        return controls(sys.argv[2])
    if len(sys.argv) >= 3 and sys.argv[1] == "report":
        return report(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
    sys.exit(__doc__)


if __name__ == "__main__":
    sys.exit(main())
