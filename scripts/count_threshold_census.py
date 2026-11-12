#!/usr/bin/env python3
"""#670's census — `docs/plans/count-threshold-boundary-census-scope.md` §2–§7.

The rows themselves are read in Swift, by `fixtures/count-threshold/census-run/`, because the scope counts with
the shipped `GuardDomainReader` and a reader written to its rules, not with a grep. This script freezes the
universe the harness reads and turns the harness's output, plus the hand-check, into the decision.

    python3 scripts/count_threshold_census.py controls <subjects.json>
        assert the frozen universe (§3) and write the subject list the harness reads
    python3 scripts/count_threshold_census.py report <census.json> [<handcheck.json>]
        print the tables and the decision (§7)
"""
import collections
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import measurement  # noqa: E402
from budgeted_truncation_census import FUNNEL  # noqa: E402

HOME = os.path.expanduser("~")
#: The 20 manifest corpora `measurement.corpus_roots()` resolves (§3). `swift-numerics` and `swift-algorithms` do
#: not resolve at their `localPath`, and are out, as in every 20-corpus reading.
FROZEN_MANIFEST = [
    "swift-infer-core", "swift-format", "grdb", "swift-collections", "swift-syntax", "swift-nio",
    "swift-package-manager", "swift-argument-parser", "swift-foundation", "swiftlang-swift", "harmonize",
    "swift-project-lint", "swift-property-laws", "swift-effect-inference", "maccloud-client-ios",
    "swiftlint-rule-studio", "swiftformat-rule-studio", "planted-defect-arm", "cycle27-surface", "leaderboard-sort",
]
#: §7: fewer than this many emittable rows is a decline.
MINIMUM_EMITTABLE = 5


def git(root, *arguments):
    result = subprocess.run(["git", "-C", root, *arguments], capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else None


def subject(group, name, root, scan_roots, sources_only):
    toplevel = git(root, "rev-parse", "--show-toplevel") or root
    return {
        "group": group,
        "name": name,
        "repository": os.path.basename(toplevel),
        "repositoryRoot": toplevel,
        "roots": scan_roots,
        "sourcesComponentOnly": sources_only,
        "revision": git(root, "rev-parse", "HEAD"),
        "dirty": bool(git(root, "status", "--porcelain", "--untracked-files=no")),
    }


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
    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump(subjects, handle, indent=2, sort_keys=True)
        handle.write("\n")
    dirty = [s["name"] for s in subjects if s["dirty"]]
    print(f"{len(rows)} of {asked} manifest corpora resolve, all {len(FUNNEL)} funnel repositories present")
    print(f"dirty (recorded, not refused): {', '.join(dirty) or 'none'}")
    return 0


def report(census_path, handcheck_path=None):
    census = json.load(open(census_path, encoding="utf-8"))
    verdicts = json.load(open(handcheck_path, encoding="utf-8")) if handcheck_path else {}
    rows = census["rows"]
    print(f"functions read: {census['functions']} in {census['files']} files, {len(census['subjects'])} subjects")
    if census["replicaDisagreements"]:
        print(f"REPLICA DISAGREES on {len(census['replicaDisagreements'])} functions: the A/B is void")

    today = [r for r in rows if r.get("today")]
    beyond = [r for r in today if r["today"]["beyondReach"]]
    print(f"\n(a) today's count rows: {len(today)}; beyond reach {len(beyond)}; "
          f"NOT APPLIED {sum(r['today']['notApplied'] for r in today)}; "
          f"one side only {sum(r['today']['oneSideOnly'] for r in today)}; "
          f"walk-eligible and beyond reach {sum(r['today']['beyondReach'] and r['walkEligible'] for r in today)}")

    extended = [r for r in rows if r.get("extended")]
    new = [r for r in extended if r["extended"]["isNew"]]
    print(f"(b)+(c) extended rows: {len(extended)}; new {len(new)}")
    by_need = collections.Counter("+".join(sorted(r["extended"]["needs"])) or "none" for r in new)
    print(f"  new by need: {dict(sorted(by_need.items()))}")
    by_cut = collections.Counter(r["extended"]["cutForm"] for r in new)
    print(f"  new by cut form: {dict(sorted(by_cut.items()))}")
    by_repo = collections.Counter(r["repository"] for r in new)
    print(f"  new by repository: {dict(by_repo.most_common())}")

    ab = census["gateAB"]
    print(f"\nA/B, every guard-domain row: today {ab['today']}, label-aware {ab['labelAware']}, "
          f"gained {len(ab['gained'])}, lost {len(ab['lost'])}")

    candidates = [r for r in rows if r.get("emittableCandidate")]
    passed = [r for r in candidates if verdicts.get(r["key"], {}).get("emittable") is True]
    unjudged = [r["key"] for r in candidates if r["key"] not in verdicts]
    print(f"\nemittable candidates (before hand-check): {len(candidates)}")
    for row in candidates:
        verdict = verdicts.get(row["key"], {})
        print(f"  {row['key']}: {verdict.get('emittable', 'UNJUDGED')} {verdict.get('note', '')}")
    if unjudged:
        print(f"\n{len(unjudged)} candidates unjudged: no decision")
        return 1
    repos = collections.Counter(r["repository"] for r in passed)
    top = repos.most_common(1)[0] if repos else (None, 0)
    print(f"\nE = {len(passed)} emittable rows; largest repository {top[0]} with {top[1]}")
    decline = len(passed) < MINIMUM_EMITTABLE or top[1] * 2 > len(passed)
    print("DECISION: DECLINE" if decline else "DECISION: BUILD")
    return 0


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "controls":
        return controls(sys.argv[2])
    if len(sys.argv) >= 3 and sys.argv[1] == "report":
        return report(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
    sys.exit(__doc__)


if __name__ == "__main__":
    sys.exit(main())
