#!/usr/bin/env python3
"""#674's census — `docs/plans/encoder-collision-census-scope.md`.

The rows are read in Swift, by `fixtures/encoder-collision/census-run/`, because (b) reads bodies with a syntax
reader and (a) is `ReplacementChainClassifier`'s own code. This script freezes the universe the harness reads and
turns the harness's output, plus the hand-check, into the decision.

    python3 scripts/encoder_collision_census.py controls <subjects.json>
        assert the frozen universe (§3) and write the subject list, with each subject's files, for the harness
    python3 scripts/encoder_collision_census.py report <census.json> [<handcheck.json>]
        print the funnel, the rows by repository and the decision (§7)
"""
import collections
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from layering_census import HOME, git, subject_files, toplevel  # noqa: E402
from uniquifier_census import without_fixtures  # noqa: E402
from budgeted_truncation_census import revision  # noqa: E402
import xml_emitter_census  # noqa: E402

#: §3.2, cloned 2026-11-12 before any was read.
CORPUS = os.path.join(HOME, "github_projects", "encoder-collision-corpus")
CLONES = [
    ("diagram", "SwiftDocOrg/GraphViz", "74b6cbd8c5ecea9f64d84c4e1c88d65604dd033f"),
    ("diagram", "gabrielepalma/poddotify", "d3ead2f11df8b4ff04e95972b56746f5844566f2"),
    ("diagram", "palaniraja/swiftuml", "07d96b6744e205216f46e7ffb54c5f81411732b8"),
    ("diagram", "Ryu0118/swift-dependencies-graph", "e9c8abd4ff5d84e24421c50e66a6781213857365"),
    ("diagram", "Christmas-Blues/tca-diagram", "e1bdc0d52d045868d48689be7736df6101e322a4"),
    ("diagram", "pauljohanneskraft/Acai", "30f4223a55c11d8c8ffeadc0692a65fcf4930a17"),
    ("codegen", "SwiftGen/SwiftGen", "ddb03a73cab2a9feaf870b00ecab0fdda3d451e1"),
    ("codegen", "JiriTrecak/Laurine", "230fa63f3862bd88e487f1caf673a2acc4d8c4e3"),
    ("codegen", "krzyzanowskim/Natalie", "0cab43da7e6d59c85ce379b186b04f0c6d51b4bd"),
    ("codegen", "Bouke/SwiftInitializerGenerator", "8b0c4610d2d40e3a4ec5a6ad17656dd3798561e5"),
    ("codegen", "yonaskolb/SwagGen", "61877cb860d59cdf4c2cc747354ec9d8b397d588"),
    ("codegen", "CreateAPI/CreateAPI", "7d0a70a8e1e18387738d19d7167b15e996e1d33f"),
]
WITNESS = "SwiftUMLStudio"
#: §7.
MINIMUM_SITES = 3
MINIMUM_REPOSITORIES = 2


def clone_groups():
    result = []
    for kind, slug, sha in CLONES:
        root = os.path.join(CORPUS, slug.replace("/", "__"))
        if not os.path.isdir(root) or git(root, "rev-parse", "HEAD") != sha or git(root, "status", "--porcelain"):
            sys.exit(f"§3.2's clone {slug} is missing, not at {sha}, or dirty")
        result.append((f"clone-{kind}", slug.replace("/", "__"), root, [root]))
    return result


def controls(out_path):
    by_root = collections.OrderedDict()
    for group, name, root, roots in xml_emitter_census.groups() + clone_groups():
        key = os.path.realpath(root)
        entry = by_root.setdefault(key, {"group": group, "name": name, "root": root, "roots": []})
        entry["roots"].extend(roots)
    subjects = []
    for key, entry in by_root.items():
        files, _ = subject_files(entry["root"], sorted(set(entry["roots"])))
        files, _ = without_fixtures(files, entry["root"])
        subjects.append({
            "group": entry["group"], "name": entry["name"], "repository": toplevel(entry["root"]), "root": key,
            "revision": revision(entry["root"]), "dirty": bool(git(entry["root"], "status", "--porcelain")),
            "files": sorted(files)})
    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump(subjects, handle, indent=1, sort_keys=True)
        handle.write("\n")
    counts = collections.Counter(subject["group"] for subject in subjects)
    print(f"{len(subjects)} subjects ({dict(counts)}), {sum(len(s['files']) for s in subjects)} files")
    print(f"dirty (recorded, not refused): {', '.join(s['name'] for s in subjects if s['dirty']) or 'none'}")
    return 0


def short(repository):
    return os.path.basename(repository)


def merged(sites):
    """§2.5: one row per (owner type, owner, literal), kept under the first repository in universe order."""
    first, copies = collections.OrderedDict(), collections.defaultdict(list)
    for site in sites:
        key = (site.get("ownerType"), site["owner"], site["literal"])
        if key in first:
            copies[key].append(site["key"])
        else:
            first[key] = site
    return list(first.values()), copies


def report(census_path, handcheck_path=None):
    with open(census_path, encoding="utf-8") as handle:
        census = json.load(handle)
    chains = [row for row in census["candidates"] if row["candidate"].get("steps") is not None]
    colliding = [row for row in chains if row["candidate"].get("witness")]
    print(f"universe: {len(census['subjects'])} subjects, {census['files']} files, {census['loops']} loops")
    print(f"(a) candidates {len(census['candidates'])}, chains {len(chains)}, colliding {len(colliding)}; "
          f"{census['foundationChecked']} witnesses checked against Foundation")
    for row in colliding:
        c = row["candidate"]
        print(f"    {short(row['repository'])}: {c.get('typeName') or '-'}.{c['name']} ({c['file']}:{c['line']}) "
              f"{c['witness']['first']!r} ~ {c['witness']['second']!r}")
    sites, copies = merged(census["sites"])
    print(f"(b) site rows {len(census['sites'])}, {len(sites)} after merging copies")
    for filing, count in sorted(collections.Counter(s["filing"] for s in sites).items()):
        print(f"    {filing}: {count}")
    for reason, count in sorted(census["tally"].items()):
        print(f"    ({reason}: {count})")
    print("rows by repository:")
    for site in sites:
        if site["filing"] == "refused: no returned buffer":
            continue
        print(f"    [{site['filing']}] {short(site['repository'])} {site['file']}:{site['line']} "
              f"{site.get('ownerType') or '-'}.{site['owner']} {site['idExpression']}")
    admitted = [s for s in sites if s["filing"] == "admitted"]
    outside = [s for s in admitted if short(s["repository"]) != WITNESS]
    print(f"admitted {len(admitted)}, outside {WITNESS} {len(outside)} over "
          f"{len({s['repository'] for s in outside})} repositories")
    if not handcheck_path:
        print("no hand-check given: no decision")
        return 0
    with open(handcheck_path, encoding="utf-8") as handle:
        verdicts = {row["key"]: row for row in json.load(handle)["rows"]}
    missing = [s["key"] for s in admitted if s["key"] not in verdicts]
    if missing:
        sys.exit(f"admitted rows without a verdict: {missing}")
    read_true = [s for s in admitted if verdicts[s["key"]]["read"]]
    counted = [s for s in outside if all(verdicts[s["key"]][k] for k in ("read", "merge", "reachable"))
               and not verdicts[s["key"]]["handled"]]
    repositories = {s["repository"] for s in counted}
    precision = f"{len(read_true) / len(admitted):.1%}" if admitted else "n/a, nothing admitted"
    print(f"precision (read over admitted): {len(read_true)}/{len(admitted)} = {precision}")
    print(f"counted outside {WITNESS}: {len(counted)} over {len(repositories)} repositories "
          f"({', '.join(sorted(short(r) for r in repositories)) or 'none'})")
    build = len(counted) >= MINIMUM_SITES and len(repositories) >= MINIMUM_REPOSITORIES
    print("decision:", "BUILD" if build else "DECLINE (population)")
    return 0


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "controls":
        return controls(sys.argv[2])
    if len(sys.argv) in (3, 4) and sys.argv[1] == "report":
        return report(*sys.argv[2:])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
