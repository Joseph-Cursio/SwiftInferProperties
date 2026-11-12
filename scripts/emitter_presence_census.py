#!/usr/bin/env python3
"""#673's census — `docs/plans/emitter-presence-census-scope.md` §2–§7.

The rows are read in Swift, by `fixtures/emitter-presence/census-run/`, because the scope reads bodies with a syntax
reader, not a grep. This script freezes the universe the harness reads and turns the harness's output, plus the
hand-check, into the decision.

    python3 scripts/emitter_presence_census.py controls <subjects.json>
        assert the frozen universe (§3) and write the subject list the harness reads
    python3 scripts/emitter_presence_census.py report <census.json> [<handcheck.json>]
        print the funnel, the per-tier counts and the decision (§7)
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
SELF = "SwiftInferProperties"
#: §7.
MINIMUM_EMITTABLE = 5
PRECISION_BAR = 0.70


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


def by_repo(rows):
    return dict(collections.Counter(r["repository"] for r in rows).most_common())


def selfless(rows):
    return [r for r in rows if r["repository"] != SELF]


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
    print(f"  refusals: {dict(collections.Counter(r['reading'].get('refusal') for r in refused).most_common())}")
    for widening in ("W1", "W2", "W3"):
        hit = [r for r in rows if widening in r["reading"]["widenings"]]
        print(f"  {widening}: {len(hit)} rows {by_repo(hit)}")
    candidates = [r for r in admitted if r["candidate"]]
    print(f"\nadmitted {len(admitted)} {by_repo(admitted)}; without this repository {len(selfless(admitted))}")
    print(f"  tiers: {dict(collections.Counter(r['reading']['tier'] for r in admitted))}")
    print(f"  candidates {len(candidates)} {by_repo(candidates)}; "
          f"not candidates {dict(collections.Counter(r['candidateRefusal'] for r in admitted if not r['candidate']))}")
    for row in admitted:
        reading = row["reading"]
        kinds = collections.Counter(o["kind"] for o in reading["obligations"])
        print(f"  {row['key']}  [{reading['tier']}, hops={reading['hops']}, {dict(kinds)}, "
              f"candidate={row['candidate']} {row.get('candidateRefusal') or ''}]")
    unjudged = [r["key"] for r in admitted if r["key"] not in verdicts]
    if unjudged:
        print(f"\n{len(unjudged)} admitted rows unjudged: no decision")
        return 1
    defects = [r["key"] for r in admitted if not (verdicts[r["key"]].get("law") and verdicts[r["key"]].get("read"))]
    precision = (len(admitted) - len(defects)) / len(admitted) if admitted else 0.0
    print(f"\nreader defects {len(defects)}: {defects}")
    print(f"precision {len(admitted) - len(defects)}/{len(admitted)} = {precision:.1%} (bar {PRECISION_BAR:.0%})")
    e = [r for r in candidates if r["key"] not in defects and verdicts[r["key"]].get("emittable") is True]
    print(f"\nE = {len(e)} {by_repo(e)}; without this repository {len(selfless(e))}")
    print(f"  tiers: {dict(collections.Counter(r['reading']['tier'] for r in e))}")
    top = collections.Counter(r["repository"] for r in e).most_common(1)
    top = top[0] if top else (None, 0)
    print(f"largest repository in E: {top[0]} with {top[1]}")
    reasons = []
    if len(e) < MINIMUM_EMITTABLE:
        reasons.append(f"E = {len(e)} < {MINIMUM_EMITTABLE}")
    if top[1] * 2 > len(e):
        reasons.append(f"{top[0]} holds {top[1]} of {len(e)}")
    if precision < PRECISION_BAR:
        reasons.append(f"precision {precision:.1%} < {PRECISION_BAR:.0%}")
    print("DECISION: BUILD" if not reasons else f"DECISION: DECLINE ({'; '.join(reasons)})")
    return 0


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "controls":
        return controls(sys.argv[2])
    if len(sys.argv) >= 3 and sys.argv[1] == "report":
        return report(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
    sys.exit(__doc__)


if __name__ == "__main__":
    sys.exit(main())
