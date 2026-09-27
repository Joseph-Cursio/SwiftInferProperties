#!/usr/bin/env python3
"""Does generator REACH bound what a law can kill? — the same mutants, run under two generators.

`docs/plans/mutation-reach-scope.md`. The arithmetic check (`mutation-check-arithmetic.md`) found every
`BigUInt.*` mutant UNEXERCISED and blamed the generator: `BigUInt(word:)` draws one machine word, so
the body returns through its `count == 1` fast path. This runs ONE frozen mutant set twice — against a
census whose stubs draw single words, and against one whose stubs draw word arrays — and compares.

Unlike `mutation_check.py` it is mutant-major: every mutant is planted once, built once, and run
against every law, because the question is about the mutants, and two arms of dozens of mutants each
would otherwise mean hundreds of rebuilds.

  plan   <census-dir> <repo> <out-plan.json>      freeze laws and mutants (before any arm runs)
  run    <plan.json> <census-dir> <out.jsonl>     run one arm
  report <plan.json> <arm-a.jsonl> <arm-b.jsonl>  compare the arms
"""

import collections
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ["MUTATION_STRATA"] = "arithmetic"  # operator-subject handling and M7 live behind it
import mutation_check as mc  # noqa: E402

TEMPLATES = ("commutativity", "associativity")
KEYWORDS = {"if", "guard", "for", "while", "switch", "return", "min", "max", "precondition", "assert",
            "init", "print", "stride", "zip", "repeatElement", "swap", "abs"}


def sites(source, span):
    """Every M1 / M2 / M4 / M7 site in the body: `(operator, at, length, replacement)`."""
    start, end, _ = span
    masked, _ = mc.mask(source)
    body = masked[start:end]
    found = []
    for match in re.finditer(r"\s(<=|>=|<|>)\s", body):
        flip = {"<": "<=", "<=": "<", ">": ">=", ">=": ">"}[match.group(1)]
        found.append(("M1 relational boundary", start + match.start(1), len(match.group(1)), flip))
    for match in re.finditer(r"\b(if|guard|while)\s+(.+?)\s*(\{|\belse\b)", body):
        if re.search(r"\b(let|var|case)\b|,", match.group(2)):
            continue
        at = start + match.start(2)
        text = source[at:at + len(match.group(2))]
        found.append(("M2 negate condition", at, len(text), "!(" + text + ")"))
    for match in re.finditer(r"(?<![\w.$])(\d+)(?![\w.])", body):
        found.append(("M4 integer off-by-one", start + match.start(1), len(match.group(1)),
                      str(int(match.group(1)) + 1)))
    swaps = dict(mc.ARITHMETIC_SWAPS)
    for match in mc.ARITHMETIC_SITE.finditer(body):
        token = match.group(1)
        found.append((f"M7 arithmetic swap ({token} -> {swaps[token]})", start + match.start(1), len(token),
                      swaps[token]))
    return sorted(found, key=lambda site: site[1])


def declarations(package_dir):
    """{name: [(path, line, first label)]} for every `func` in the package's non-test sources.

    The first label is the external name of the first parameter (`_` when unlabelled), so a call
    `multiplied(byWord: w)` resolves when another `multiplied(by:)` exists — by bare name alone it
    was ambiguous and skipped, and it is the path single-word draws take."""
    found = collections.defaultdict(list)
    for root, dirs, files in os.walk(package_dir):
        dirs[:] = [d for d in dirs if d not in (".build", "Tests", "Generated") and not d.startswith(".")]
        for name in files:
            if not name.endswith(".swift"):
                continue
            path = os.path.join(root, name)
            for number, row in enumerate(open(path, encoding="utf-8", errors="ignore"), 1):
                match = re.search(r"\bfunc\s+([A-Za-z_]\w*|[+\-*/%<>=!&|^~?]+)\s*(?:<[^>]*>)?\(\s*(\w+)?", row)
                if match:
                    found[match.group(1)].append((path, number, match.group(2) or ""))
    return found


def callees(source, span):
    """`(name, first label)` for each call in the body, in order: `name(` or `.name(`,
    lowercase-initial, not a keyword. The label is `_` for an unlabelled first argument."""
    start, end, _ = span
    masked, _ = mc.mask(source)
    calls = []
    for match in re.finditer(r"(?:(?<=\.)|(?<![\w.]))([a-z_]\w*)\(\s*(?:(\w+)\s*:(?!:))?", masked[start:end]):
        call = (match.group(1), match.group(2) or "_")
        if call[0] not in KEYWORDS and call not in calls:
            calls.append(call)
    return calls


def resolve(call, decls):
    """The one declaration a call names: unique by name, else unique by name and first label."""
    name, label = call
    hits = decls.get(name, [])
    if len(hits) == 1:
        return hits[0]
    labelled = [hit for hit in hits if hit[2] == label]
    return labelled[0] if len(labelled) == 1 else None


def functions_for(subject_path, subject_line, subject_name, decls):
    """The subject, each uniquely-named package function it calls, and — through a callee with no
    site of its own — that callee's callees. `[(path, line, name)]`, the subject first."""
    chosen, queue = [], [(subject_path, subject_line, subject_name, 0)]
    seen = set()
    while queue:
        path, line, name, depth = queue.pop(0)
        if (path, line) in seen:
            continue
        seen.add((path, line))
        source = open(path, encoding="utf-8").read()
        span = mc.subject_body(source, line, name)
        if not span:
            continue
        chosen.append((path, line, name))
        if depth == 2:
            continue
        has_sites = bool(sites(source, span))
        if depth == 1 and has_sites:
            continue  # scope §2: follow further only through a pure delegation
        for call in callees(source, span):
            hit = resolve(call, decls)
            if hit:
                queue.append((hit[0], hit[1], call[0], depth + 1))
    return chosen


def plan(census_dir, repo, out_path):
    # A tree an earlier check ran in still holds that check's `_N1000` / `_Probe` clones, which read
    # as laws with no subject; they are the check's instruments, not the census's stubs.
    laws = [law for law in mc.candidates([census_dir])
            if law["repo"] == repo and law["template"] in TEMPLATES
            and not re.search(r"_(N1000|Probe)\.swift$", law["stub"])]
    if not laws:
        raise SystemExit("no relational laws")
    package = laws[0]["package"]
    tree = os.path.join(census_dir, "trees", repo)
    decls = declarations(package)
    functions = {}
    for law in laws:
        for path, line, name in functions_for(law["source"], law["line"], law["subjects"][0], decls):
            # Keyed by LINE, not name: `BigUInt.+` and `BigInt.+` share a file and a name.
            functions.setdefault((os.path.relpath(path, tree), line), name)
    mutants = []
    for (relative, line), name in sorted(functions.items()):
        source = open(os.path.join(tree, relative), encoding="utf-8").read()
        for operator, at, length, replacement in sites(source, mc.subject_body(source, line, name)):
            mutants.append({"id": len(mutants), "file": relative, "function": name, "line": line,
                            "operator": operator, "at": at, "original": source[at:at + length],
                            "replacement": replacement,
                            "source_line": source.count("\n", 0, at) + 1})
    frozen = {"repo": repo,
              "laws": [{"suite": l["suite"], "test": l["test"], "template": l["template"],
                        "subjects": l["subjects"], "stub": os.path.relpath(l["stub"], tree),
                        "trials": l["trials"]} for l in laws],
              "functions": [{"file": f, "function": n, "line": ln} for (f, ln), n in sorted(functions.items())],
              "mutants": mutants}
    json.dump(frozen, open(out_path, "w"), indent=1)
    print(f"{len(frozen['laws'])} laws, {len(frozen['functions'])} functions, {len(mutants)} mutants")
    print(collections.Counter((m["function"], m["operator"][:2]) for m in mutants))
    return 0


def arm_laws(frozen, census_dir):
    tree = os.path.join(census_dir, "trees", frozen["repo"])
    laws = []
    for law in frozen["laws"]:
        stub = os.path.join(tree, law["stub"])
        package = os.path.dirname(stub)
        while not os.path.exists(os.path.join(package, "Package.swift")):
            package = os.path.dirname(package)
        laws.append(dict(law, stub=stub, package=package, repo=frozen["repo"]))
    return tree, laws


def run(plan_path, census_dir, out_path):
    frozen = json.load(open(plan_path))
    tree, laws = arm_laws(frozen, census_dir)
    mc.install(laws)
    package = laws[0]["package"]
    swift = mc.swift_for(laws[0])
    done = set()
    if os.path.exists(out_path):
        done = {json.loads(row)["id"] for row in open(out_path)}
    log = open(out_path, "a")
    if "baseline" not in done:
        ok, output = mc.build(package, swift)
        if not ok:
            raise SystemExit("baseline build failed\n" + output[-800:])
        results = {}
        for law in laws:
            first = mc.evaluate(law, swift)
            # Same guard as mutation_check: a probe that differs between two runs of UNMUTATED code
            # cannot tell a mutant's divergence from noise.
            again = mc.run_suite(law["package"], swift, law["suite"] + "_Probe", law["test"])[1] \
                if law.get("probe") else None
            results[law["suite"]] = dict(first, deterministic=(again == first.get("probe")) if law.get("probe") else None)
        log.write(json.dumps({"id": "baseline", "results": results}) + "\n")
        log.flush()
    for mutant in frozen["mutants"]:
        if mutant["id"] in done:
            continue
        path = os.path.join(tree, mutant["file"])
        original = open(path, encoding="utf-8").read()
        at, text = mutant["at"], mutant["original"]
        if original[at:at + len(text)] != text:
            raise SystemExit(f"mutant {mutant['id']} does not match the source — plan and tree disagree")
        record = {"id": mutant["id"]}
        try:
            open(path, "w", encoding="utf-8").write(original[:at] + mutant["replacement"] + original[at + len(text):])
            ok, _ = mc.build(package, swift)
            record["compiles"] = ok
            if ok:
                record["results"] = {law["suite"]: mc.evaluate(law, swift) for law in laws}
        finally:
            open(path, "w", encoding="utf-8").write(original)
        log.write(json.dumps(record) + "\n")
        log.flush()
    mc.build(package, swift)
    return 0


def outcomes(frozen, rows):
    """{mutant id: {suite: outcome}} with mutation_check's scoring against each law's baseline."""
    baseline = next(row for row in rows if row["id"] == "baseline")["results"]
    graded = {}
    for row in rows:
        if row["id"] == "baseline":
            continue
        if not row.get("compiles"):
            graded[row["id"]] = "DISCARDED"
            continue
        per_law = {}
        for suite, result in row["results"].items():
            base = baseline[suite]
            per_law[suite] = mc.score(dict(result, compiles=True), base) \
                if baseline[suite].get("law") == "passed" else "BASELINE-NOT-PASSING"
        graded[row["id"]] = per_law
    return graded


def best(per_law):
    """A mutant's outcome over all laws: KILLED if any law kills it, else DIVERGED if any law's
    subject output changed, else UNEXERCISED."""
    if per_law == "DISCARDED":
        return "DISCARDED"
    values = set(per_law.values())
    for outcome in ("KILLED", "DIVERGED", "UNEXERCISED"):
        if outcome in values:
            return outcome
    return sorted(values)[0] if values else "NONE"


def report(plan_path, path_a, path_b):
    frozen = json.load(open(plan_path))
    arms = [outcomes(frozen, [json.loads(row) for row in open(path)]) for path in (path_a, path_b)]
    moves = collections.Counter()
    for arm_name, arm in zip(("A", "B"), arms):
        tally = collections.Counter(best(arm[m["id"]]) for m in frozen["mutants"] if m["id"] in arm)
        exercised = tally["KILLED"] + tally["DIVERGED"]
        rate = f"{tally['KILLED']} of {exercised}" if exercised else "—"
        print(f"arm {arm_name}: {dict(tally)}  kill rate over exercised {rate}")
    for mutant in frozen["mutants"]:
        a, b = (best(arm.get(mutant["id"], "DISCARDED")) for arm in arms)
        moves[(a, b)] += 1
    print("\nA -> B")
    for (a, b), count in sorted(moves.items(), key=lambda item: -item[1]):
        print(f"  {a:12} -> {b:12} {count}")
    print("\nby function, arm A / arm B (killed/exercised/all):")
    for function, line in sorted({(m["function"], m["line"]) for m in frozen["mutants"]}, key=lambda k: (k[0], k[1])):
        ids = [m["id"] for m in frozen["mutants"] if (m["function"], m["line"]) == (function, line)]
        parts = []
        for arm in arms:
            grades = [best(arm.get(i, "DISCARDED")) for i in ids]
            parts.append(f"{grades.count('KILLED')}/{grades.count('KILLED') + grades.count('DIVERGED')}/{len(ids)}")
        print(f"  {function + '@' + str(line):28} {parts[0]:>10}  {parts[1]:>10}")
    return 0


def main(argv):
    if argv[1] == "plan":
        return plan(argv[2], argv[3], argv[4])
    if argv[1] == "run":
        return run(argv[2], argv[3], argv[4])
    if argv[1] == "report":
        return report(argv[2], argv[3], argv[4])
    raise SystemExit(__doc__)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
