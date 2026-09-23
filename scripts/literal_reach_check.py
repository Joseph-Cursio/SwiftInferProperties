#!/usr/bin/env python3
"""Do the funnel's passing BEHAVIOUR laws still pass when the generator draws the subject's own literals?

`docs/measurements/funnel-mutation-check.md` §7 found `HTMLEscaping.escape`'s idempotence law passing
while false, because the stub's string generator never draws `&`. This asks how common that is.

For every passing law whose stub builds strings with `Gen<Character>.letterOrNumber.string(of:)` and
whose subject body contains string literals, a clone is installed beside the stub with each such
generator mixed with those literals — alone, and embedded in random text — at 1,000 trials. A law
that passes as emitted and fails with literals is a CANDIDATE: a false law the generator hid, or a
real defect. **Every candidate is hand-checked before it is counted as either.**

    python3 scripts/literal_reach_check.py <census-root> <out.jsonl>              # behaviour laws
    python3 scripts/literal_reach_check.py <census-root> <out.jsonl> --totality   # totality laws

**`--totality`** runs the does-not-crash laws instead (`subject-literal-generation-scope.md` §3). A
totality law fails only by trapping or hanging, so a refutation there is a CRASH on the subject's own
literal — a candidate defect, hand-checked for whether the input can reach the function in real use.

⚠ Scratch census worktrees only (#560). The clones are removed afterwards.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mutation_check as mc  # noqa: E402

BASE = "Gen<Character>.letterOrNumber.string(of: 0...8)"
SHORT = "Gen<Character>.letterOrNumber.string(of: 0...4)"
MAX_LITERALS = 16


def subject_literals(law):
    """The subject's own string literals, as written in its source (escapes intact), deduplicated."""
    found = []
    for path, line, name in mc.subject_locations(law):
        source = open(path, encoding="utf-8").read()
        span = mc.subject_body(source, line, name)
        if not span:
            continue
        _, literals = mc.mask(source)
        for start, end in literals:
            if span[0] <= start and end <= span[1]:
                text = source[start:end]
                if text not in found and len(text) <= 40:
                    found.append(text)
    return found[:MAX_LITERALS]


def with_literals(text, literals):
    """`text` with every base string generator mixed with `literals`."""
    element = f"Gen<String?>.element(of: [{', '.join(literals)}] as [String]).map {{ $0! }}"
    embedded = (f"zip(zip({SHORT}, {element}).map {{ $0 + $1 }}, {SHORT}).map {{ $0 + $1 }}")
    mixed = f"Gen.frequency((2.0, {BASE}), (1.0, {element}), (1.0, {embedded}))"
    return text.replace(BASE, mixed)


def build_setting_aside(package, swift, rounds=6):
    """Build, removing any `_Lit` clone the compiler rejects, so one bad clone cannot sink a package.

    Returns `(ok, output, broken)` where `broken` maps a suite to the first error its clone raised.
    """
    broken = {}
    for _ in range(rounds):
        ok, output = mc.build(package, swift)
        if ok:
            return True, output, broken
        culprits = {}
        for match in re.finditer(r"^(/\S+_Lit\.swift):\d+:\d+: error: (.+)$", output, re.M):
            culprits.setdefault(match.group(1), match.group(2))
        if not culprits:
            return False, output, broken
        for path, error in culprits.items():
            suite = re.search(r"^struct (\w+)_Lit", open(path, encoding="utf-8").read(), re.M).group(1)
            broken[suite] = error[:200]
            os.remove(path)
    return False, output, broken


def behaviour_stubs(root, totality=False):
    """Every compiled, not-failed stub whose law checks behaviour, from each repo's LATEST census tree.

    `census-widened` supersedes `census-imports2` for the six repositories it re-ran; a totality
    template (`corpus_funnel.DOES_NOT_CRASH_TEMPLATES`) is excluded, because literals cannot make a
    law that only checks for a crash notice anything.
    """
    import glob
    import corpus_funnel as cf
    latest = {}
    for directory in ("census-imports2", "census-widened"):
        for path in glob.glob(os.path.join(root, directory, "result-*.json")):
            result = json.load(open(path))
            latest[result["repo"]] = (directory, result)
    stubs = []
    for repo, (directory, result) in sorted(latest.items()):
        for package in result.get("packages", []):
            if not package.get("passed"):
                continue
            target = mc.census_target_dir(os.path.join(root, directory, "trees", repo, package["package"]))
            failed = {name.split(".")[0] for name in package.get("failures") or []}
            for path in sorted(glob.glob(os.path.join(target, "*", "*.swift"))):
                template = os.path.basename(os.path.dirname(path))
                suite = re.search(r"^struct (\w+)", open(path, encoding="utf-8").read(), re.M)
                if (template in cf.DOES_NOT_CRASH_TEMPLATES) != totality or not suite or suite.group(1) in failed:
                    continue
                stubs.append((repo, template, path))
    return stubs


def main(root, out_path, *flags):
    stubs = behaviour_stubs(root, totality="--totality" in flags)
    done = set()
    if os.path.exists(out_path):
        done = {json.loads(row)["suite"] for row in open(out_path)}
    laws, clones = [], []
    for repo, template, stub in stubs:
        text = open(stub, encoding="utf-8").read()
        if BASE not in text:
            continue
        package = os.path.dirname(stub)
        while not os.path.exists(os.path.join(package, "Package.swift")):
            package = os.path.dirname(package)
        law = mc.law_of(stub, repo, package, template)
        if not law or not law["subjects"]:
            continue
        law["stratum"] = template
        try:
            law["literals"] = subject_literals(law)
        except (ValueError, StopIteration, IndexError) as error:
            law["literals"], law["error"] = [], f"subject not readable: {error}"
        laws.append(law)
    log = open(out_path, "a")
    # ⚠ **Clones are written INSIDE the cleanup block.** The first run wrote them before it and
    # crashed, stranding 8 clone files in the census trees as extra suites.
    try:
        for law in laws:
            if not law["literals"] or law["suite"] in done:
                continue
            text = open(law["stub"], encoding="utf-8").read()
            clone = with_literals(text, law["literals"]).replace(
                f"struct {law['suite']}", f"struct {law['suite']}_Lit", 1)
            clone = re.sub(r"trials: 100,", "trials: 1000,", clone)
            path = law["stub"][:-len(".swift")] + "_Lit.swift"
            open(path, "w", encoding="utf-8").write(clone)
            clones.append(path)
        for package, group in mc.itertools_groupby(laws, "package"):
            swift = mc.swift_for(group[0])
            ok, output, broken = build_setting_aside(package, swift)
            for law in group:
                if law["suite"] in done:
                    continue
                record = {"repo": law["repo"], "suite": law["suite"], "test": law["test"],
                          "template": law["template"], "stub": law["stub"], "literals": law["literals"]}
                if law.get("error"):
                    record["outcome"] = "subject not readable"
                    record["detail"] = law["error"]
                elif not law["literals"]:
                    record["outcome"] = "no literals"
                elif law["suite"] in broken:
                    record["outcome"] = "clone does not compile"
                    record["detail"] = broken[law["suite"]]
                elif not ok:
                    record["outcome"] = "clone build failed"
                    record["detail"] = output[-400:]
                else:
                    record["baseline"] = mc.run_suite(package, swift, law["suite"], law["test"])[0]
                    record["literal"] = mc.run_suite(package, swift, law["suite"] + "_Lit", law["test"])[0]
                    record["outcome"] = ("baseline not passing" if record["baseline"] != "passed" else
                                         "CANDIDATE" if record["literal"] in ("failed", "trapped", "hung") else
                                         "held")
                log.write(json.dumps(record) + "\n")
                log.flush()
    finally:
        for path in clones:
            if os.path.exists(path):
                os.remove(path)
    return 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:]))
