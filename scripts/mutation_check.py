#!/usr/bin/env python3
"""Mutation check over the corpus funnel's passing laws — `docs/plans/funnel-mutation-check-scope.md`.

Three stages, each resumable:

    sample   <census-dirs...>   → fixtures/mutation-check/sample.json   (frozen before any mutant)
    run      <sample.json> <out.jsonl>                                    (baseline, then mutants)
    report   <out.jsonl>

Every law-mutant is scored as one of three outcomes (scope §2):

    KILLED       the law fails, traps or hangs
    DIVERGED     the law passes, but a same-seed probe shows the subject's output changed
    UNEXERCISED  the law passes and the subject's output never changed on the drawn inputs

⚠ **Works only in the census's SCRATCH worktrees, never in a real checkout** (#560). Each mutant
is written over the subject file and the original bytes restored afterwards, whatever happens.
"""
import collections
import glob
import json
import os
import random
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import corpus_funnel as cf  # noqa: E402

EXCLUDED_REPOS = {"pbt-book", "pbt-workbook", "pbt-workbook-corpus", "pbt-workbook-sampler",
                  "pbt-workbook-grader"}
# Scope §3. A stratum may name several templates; laws are drawn from their union.
STRATA = [
    ("predicate", ("predicate",), 14),
    ("idempotence", ("idempotence",), 12),
    ("input-totality", ("input-totality",), 10),
    ("guard-domain", ("guard-domain",), 5),
    ("relational", ("commutativity", "associativity"), 8),
    ("round-trip", ("round-trip",), 5),
    ("other", ("caseiterable-key-injectivity", "monotonicity", "filter-subset"), 6),
]
SEED = 20260922
PROBE_FILE = "SwiftInferMutationProbe.swift"
PROBE_HELPER = """// Written by scripts/mutation_check.py — records a subject's output per trial.
import Foundation

func __mutationProbe<T>(_ value: T, _ tag: String) -> T {
    var text = ""
    dump(value, to: &text, maxDepth: 4, maxItems: 64)
    print("MPROBE|" + tag + "|" + text.replacingOccurrences(of: "\\n", with: "\\u{23CE}"))
    return value
}
"""


# ---------------------------------------------------------------- sampling

def census_target_dir(package_dir):
    manifest = open(os.path.join(package_dir, "Package.swift"), encoding="utf-8").read()
    match = re.search(r'name: "SwiftInferCensusTests".*?path: "([^"]+)"', manifest, re.S)
    return os.path.join(package_dir, match.group(1)) if match else None


def law_of(stub_path, repo, package_dir, template):
    text = open(stub_path, encoding="utf-8").read()
    suite = re.search(r"^struct (\w+)", text, re.M)
    test = re.search(r"@Test[^\n]*\n\s*func (\w+)\(|@Test func (\w+)\(", text)
    source = re.search(r"^// Source: (.+):(\d+)\s*$", text, re.M)
    if not (suite and test and source):
        return None
    stem = os.path.basename(stub_path)[:-len(".swift")]
    # `<Type>_<fn>[_<fn2>]_<template>` — the subjects are the names between type and template.
    # ⚠ **Not `[1:]`**: a FREE function's stub has no type prefix (`isFunctionLocal_predicate`), and
    # dropping the first name dropped its only one — the first run crashed on exactly that.
    names = stem[:-(len(template) + 1)].split("_") if stem.endswith("_" + template) else []
    # The leading names are the type and any nesting; the subject is the last one — two for a
    # round trip, which pairs a function with its inverse.
    names = names[-2:] if template == "round-trip" else names[-1:]
    return {"repo": repo, "package": package_dir, "stub": stub_path, "template": template,
            "suite": suite.group(1), "test": test.group(1) or test.group(2),
            "subjects": [name for name in names if name], "source": source.group(1),
            "line": int(source.group(2)), "trials": "trials:" in text}


def candidates(census_dirs):
    """Every compiled, not-failed stub in the given census runs; the LAST dir naming a repo wins."""
    runs = {}
    for directory in census_dirs:
        for path in glob.glob(os.path.join(directory, "result-*.json")):
            result = json.load(open(path))
            runs[result["repo"]] = (directory, result)
    found = []
    for repo, (directory, result) in sorted(runs.items()):
        if repo in EXCLUDED_REPOS:
            continue
        for package in result.get("packages", []):
            if not package.get("passed"):
                continue
            package_dir = os.path.join(directory, "trees", repo, package["package"])
            stubs = census_target_dir(package_dir)
            if not stubs:
                continue
            failed = {name.split(".")[0] for name in package.get("failures") or []}
            for stub in glob.glob(os.path.join(stubs, "*", "*.swift")):
                template = os.path.basename(os.path.dirname(stub))
                law = law_of(stub, repo, os.path.normpath(package_dir), template)
                if law and law["suite"] not in failed and os.path.exists(law["source"]):
                    found.append(law)
    return found


def draw(found):
    """Stratified, seeded, no repository above a third of any stratum (scope §3)."""
    rng = random.Random(SEED)
    sample, shortfalls = [], {}
    for stratum, templates, wanted in STRATA:
        pool = sorted((law for law in found if law["template"] in templates), key=lambda l: l["stub"])
        rng.shuffle(pool)
        cap = -(-wanted // 3)
        per_repo = collections.Counter()
        chosen = []
        for law in pool:
            if len(chosen) == wanted:
                break
            if per_repo[law["repo"]] >= cap:
                continue
            per_repo[law["repo"]] += 1
            chosen.append(dict(law, stratum=stratum))
        if len(chosen) < wanted:
            shortfalls[stratum] = f"{len(chosen)} of {wanted} (pool {len(pool)})"
        sample += chosen
    return sample, shortfalls


# ---------------------------------------------------------------- source masking and mutation

def mask(text):
    """`text` with comment and string-literal CONTENTS blanked, plus each simple literal's span.

    Same length as the input, so an index into the mask is an index into the source.
    """
    out, literals, index = list(text), [], 0
    while index < len(text):
        if text.startswith("//", index):
            end = text.find("\n", index)
            end = len(text) if end < 0 else end
            out[index:end] = " " * (end - index)
            index = end
        elif text.startswith("/*", index):
            end = text.find("*/", index) + 2
            out[index:end] = " " * (end - index)
            index = end
        elif text.startswith('"""', index):
            end = text.find('"""', index + 3) + 3
            out[index + 3:end - 3] = " " * (end - index - 6)
            index = end
        elif text[index] == '"':
            end = index + 1
            while text[end] != '"':
                end += 2 if text[end] == "\\" else 1
            body = text[index + 1:end]
            if body and "\\(" not in body:
                literals.append((index, end + 1))
            out[index + 1:end] = " " * (end - index - 1)
            index = end + 1
        else:
            index += 1
    return "".join(out), literals


def matching(masked, open_index, opener="{", closer="}"):
    depth = 0
    for index in range(open_index, len(masked)):
        if masked[index] == opener:
            depth += 1
        elif masked[index] == closer:
            depth -= 1
            if depth == 0:
                return index
    raise ValueError("unbalanced")


def subject_body(source, line, name):
    """(start, end, returns_bool) of the body of `name` declared at or just after `line`."""
    masked, _ = mask(source)
    offset = sum(len(row) + 1 for row in source.split("\n")[:max(line - 1, 0)])
    pattern = re.compile(r"\b(?:func\s+" + re.escape(name) + r"\b|var\s+" + re.escape(name) + r"\s*:)")
    match = pattern.search(masked, offset)
    if not match or masked.count("\n", offset, match.start()) > 12:
        return None
    brace = masked.find("{", match.end())
    header = masked[match.start():brace]
    end = matching(masked, brace)
    returns_bool = bool(re.search(r"->\s*Bool\s*$|:\s*Bool\s*$", header.strip()))
    return brace + 1, end, returns_bool


def mutants(source, span):
    """Up to three `(operator, mutated_source)` for the body in `span`, in the scope's fixed order."""
    start, end, returns_bool = span
    masked, literals = mask(source)
    body = masked[start:end]
    found = []

    def replace(at, length, text):
        return source[:at] + text + source[at + length:]

    relational = re.search(r"\s(<=|>=|<|>)\s", body)
    if relational:
        flip = {"<": "<=", "<=": "<", ">": ">=", ">=": ">"}[relational.group(1)]
        at = start + relational.start(1)
        found.append(("M1 relational boundary", replace(at, len(relational.group(1)), flip)))

    condition = re.search(r"\b(if|guard)\s+(.+?)\s*(\{|\belse\b)", body)
    if condition and not re.search(r"\b(let|var|case)\b|,", condition.group(2)):
        at = start + condition.start(2)
        found.append(("M2 negate condition",
                      replace(at, len(condition.group(2)), "!(" + source[at:at + len(condition.group(2))] + ")")))

    if returns_bool:
        # The LAST return is the function's result; an early `else { return false }` is a guard.
        # It stops at `}` so a one-line block keeps its closing brace.
        returns = list(re.finditer(r"\breturn\s+([^\n;}]*[^\n;}\s])", body))
        ret = returns[-1] if returns else None
        if ret:
            at = start + ret.start(1)
            text = source[at:at + len(ret.group(1))]
            found.append(("M3 invert Bool result", replace(at, len(text), "!(" + text + ")")))
        elif body.strip() and "\n" not in body.strip():
            inner = source[start:end]
            found.append(("M3 invert Bool result", replace(start, end - start, " !(" + inner.strip() + ") ")))

    # Not `$0`: a closure's shorthand argument is a name, and `$1` would not even compile.
    integer = re.search(r"(?<![\w.$])(\d+)(?![\w.])", body)
    if integer:
        at = start + integer.start(1)
        found.append(("M4 integer off-by-one", replace(at, len(integer.group(1)), str(int(integer.group(1)) + 1))))

    chain = re.search(r"\)\s*(\.\w+\()", body)
    if chain:
        dot = start + chain.start(1)
        close = matching(masked, dot + len(chain.group(1)) - 1, "(", ")")
        found.append(("M5 drop chained call", source[:dot] + source[close + 1:]))

    literal = next(((a, b) for a, b in literals if start <= a and b <= end), None)
    if literal:
        found.append(("M6 empty string literal", replace(literal[0], literal[1] - literal[0], '""')))

    return found[:3]


# ---------------------------------------------------------------- probe and budget clones

def matching_back(masked, close_index):
    """Index of the opener balancing the `)` or `]` at `close_index`."""
    opener = {")": "(", "]": "["}[masked[close_index]]
    depth = 0
    for index in range(close_index, -1, -1):
        if masked[index] == masked[close_index]:
            depth += 1
        elif masked[index] == opener:
            depth -= 1
            if depth == 0:
                return index
    raise ValueError("unbalanced")


def chain_start(masked, at):
    """Where the postfix chain ending in the member at `at` begins — `a.b(c).d` for `d`.

    Walked backwards over `.`-separated segments, each an identifier or a balanced `(...)` /
    `[...]` group, across newlines. A pattern could not do this: the first version allowed one
    level of parentheses and missed `Simulator(cli: Actor(cache: Manager(…))).parse(…)`, whose
    receiver spans three lines, and a leading-dot argument (`(mode: .x)`) must not start a chain.
    """
    word = lambda ch: ch.isalnum() or ch in "_$"
    cur = at
    while True:
        dot = cur - 1
        while dot >= 0 and masked[dot] in " \t\n":
            dot -= 1
        if dot < 0 or masked[dot] != ".":
            return cur
        end = dot - 1
        while end >= 0 and masked[end] in " \t\n":
            end -= 1
        if end < 0:
            return cur
        if masked[end] in ")]":
            end = matching_back(masked, end) - 1
        elif not word(masked[end]):
            return cur  # a leading-dot member, as in `(viewMode: .sourceAccurate)`
        start = end
        while start >= 0 and word(masked[start]):
            start -= 1
        cur = start + 1


def wrap_subject_calls(text, subjects, tag):
    """Wrap every call (or member access) of a subject in `text` in `__mutationProbe`."""
    masked, _ = mask(text)
    edits = []
    for name in subjects:
        for match in re.finditer(r"(?<![\w$])" + re.escape(name) + r"\b", masked):
            after = match.end()
            rest = masked[after:].lstrip(" ")
            if rest.startswith(":"):
                continue  # an argument label, not a use
            begin = chain_start(masked, match.start())
            if after < len(masked) and masked[after] == "(":
                after = matching(masked, after, "(", ")") + 1
            edits.append((begin, after))
    edits.sort(key=lambda edit: (edit[0], -edit[1]))
    kept = []
    for begin, end in edits:
        if kept and begin < kept[-1][1]:
            continue  # nested inside an earlier wrap: the outer one already records it
        kept.append((begin, end))
    for begin, end in reversed(kept):
        text = text[:begin] + "__mutationProbe(" + text[begin:end] + ', "' + tag + '")' + text[end:]
    return text, len(kept)


def clones(law):
    """The stub's text as a 1,000-trial law and as a probe, or `None` where one cannot be made."""
    text = open(law["stub"], encoding="utf-8").read()
    n1000 = None
    if law["trials"]:
        n1000 = text.replace(f"struct {law['suite']}", f"struct {law['suite']}_N1000", 1) \
                    .replace("trials: 100,", "trials: 1000,")
    # The WHOLE closure, not its first line: `guard-domain` and the relational laws spread the
    # property over several lines, and reading one line left all of them unprobed.
    masked, _ = mask(text)
    anchor = next((masked.find(key) for key in ("property:", "by: {") if masked.find(key) >= 0), -1)
    probe = None
    if anchor >= 0:
        brace = masked.index("{", anchor)
        close = matching(masked, brace)
        region, wrapped = wrap_subject_calls(text[brace:close + 1], law["subjects"], law["suite"])
        if wrapped:
            probe = (text[:brace] + region + text[close + 1:]).replace(
                f"struct {law['suite']}", f"struct {law['suite']}_Probe", 1)
    return n1000, probe


# ---------------------------------------------------------------- running

def swift_for(law):
    return cf.toolchain(law["repo"])


def build(package_dir, swift):
    done = subprocess.run([swift, "build", "--build-tests"], cwd=package_dir, capture_output=True,
                          text=True, env=cf.environment(swift), timeout=3600)
    return done.returncode == 0, done.stdout + done.stderr


def run_suite(package_dir, swift, suite, test, seconds=300):
    """'passed' | 'failed' | 'trapped' | 'hung' | 'missing', plus the probe lines it printed."""
    pattern = r"\." + re.escape(suite) + "/" + re.escape(test) + r"\("
    # ⚠ **Hash order must not vary between runs**, or every Dictionary- or Set-valued subject reads
    # as diverged. The smoke run found it at once: `buildEnvironment`'s probe differed between two
    # runs of the UNMUTATED code, because each process seeds hashing afresh.
    env = dict(cf.environment(swift), SWIFT_DETERMINISTIC_HASHING="1")
    try:
        done = subprocess.run([swift, "test", "--skip-build", "--no-parallel", "--filter", pattern],
                              cwd=package_dir, capture_output=True, text=True, env=env, timeout=seconds)
    except subprocess.TimeoutExpired:
        subprocess.run(["pkill", "-f", "swiftpm-testing-helper"], capture_output=True)
        return "hung", []
    output = done.stdout + done.stderr
    probes = [row.split("|", 2)[2] for row in output.splitlines() if row.startswith("MPROBE|")]
    if re.search(r"Test\s+\S+\(\)\s+passed", output):
        return "passed", probes
    if re.search(r"Test\s+\S+\(\)\s+(failed|recorded an issue)", output):
        return "failed", probes
    if re.search(r"Test\s+\S+\(\)\s+started", output):
        return "trapped", probes
    return "missing", probes


def evaluate(law, swift):
    package = law["package"]
    result = {"law": run_suite(package, swift, law["suite"], law["test"])[0]}
    if law.get("n1000"):
        result["law1000"] = run_suite(package, swift, law["suite"] + "_N1000", law["test"])[0]
    if law.get("probe"):
        result["probe"] = run_suite(package, swift, law["suite"] + "_Probe", law["test"])[1]
    return result


def install(laws):
    """Write the probe helper and each law's clones beside its stub, once per package."""
    for package, group in itertools_groupby(laws, "package"):
        target = census_target_dir(package)
        open(os.path.join(target, PROBE_FILE), "w").write(PROBE_HELPER)
        for law in group:
            n1000, probe = clones(law)
            base = law["stub"][:-len(".swift")]
            if n1000:
                open(base + "_N1000.swift", "w").write(n1000)
                law["n1000"] = True
            if probe:
                open(base + "_Probe.swift", "w").write(probe)
                law["probe"] = True


def itertools_groupby(items, key):
    grouped = collections.OrderedDict()
    for item in items:
        grouped.setdefault(item[key], []).append(item)
    return grouped.items()


def subject_locations(law):
    """[(file, line, name)] — the Source subject, plus a round-trip partner found by name."""
    located = [(law["source"], law["line"], law["subjects"][0])]
    if law["template"] == "round-trip" and len(law["subjects"]) > 1:
        partner = law["subjects"][1]
        hits = []
        for path in glob.glob(os.path.join(law["package"], "**", "*.swift"), recursive=True):
            if "/.build/" in path or "/Tests/" in path:
                continue
            for number, row in enumerate(open(path, encoding="utf-8", errors="ignore"), 1):
                if re.search(r"\bfunc\s+" + re.escape(partner) + r"\b", row):
                    hits.append((path, number, partner))
        if len(hits) == 1:
            located.append(hits[0])
    return located


def run(sample_path, out_path):
    laws = json.load(open(sample_path))["laws"]
    done = set()
    if os.path.exists(out_path):
        for row in open(out_path):
            record = json.loads(row)
            done.add((record["suite"], record.get("mutant", "baseline"), record.get("file", "")))
    install(laws)
    log = open(out_path, "a")
    for package, group in itertools_groupby(laws, "package"):
        swift = swift_for(group[0])
        ok, output = build(package, swift)
        if not ok:
            for law in group:
                log.write(json.dumps({"suite": law["suite"], "mutant": "baseline", "error": "baseline build failed",
                                      "detail": output[-600:]}) + "\n")
            log.flush()
            continue
        for law in group:
            if (law["suite"], "baseline", "") not in done:
                first = evaluate(law, swift)
                second = run_suite(package, swift, law["suite"] + "_Probe", law["test"])[1] if law.get("probe") else None
                record = dict(suite=law["suite"], mutant="baseline", **first,
                              deterministic=(second == first.get("probe")) if law.get("probe") else None)
                log.write(json.dumps(record) + "\n")
                log.flush()
                done.add((law["suite"], "baseline", ""))
            baseline = next(json.loads(row) for row in open(out_path)
                            if json.loads(row)["suite"] == law["suite"] and json.loads(row).get("mutant") == "baseline")
            if baseline.get("law") != "passed":
                continue
            for path, line, name in subject_locations(law):
                original = open(path, encoding="utf-8").read()
                span = subject_body(original, line, name)
                if not span:
                    log.write(json.dumps({"suite": law["suite"], "mutant": "none", "file": path,
                                          "error": f"no body found for {name}"}) + "\n")
                    continue
                for operator, mutated in mutants(original, span):
                    key = (law["suite"], operator, path)
                    if key in done:
                        continue
                    record = {"suite": law["suite"], "mutant": operator, "file": path, "subject": name}
                    try:
                        open(path, "w", encoding="utf-8").write(mutated)
                        ok, output = build(package, swift)
                        if not ok:
                            record["compiles"] = False
                        else:
                            record.update(compiles=True, **evaluate(law, swift))
                    finally:
                        open(path, "w", encoding="utf-8").write(original)
                    log.write(json.dumps(record) + "\n")
                    log.flush()
                    done.add(key)
        build(package, swift)  # leave the package built from its original sources
    return 0


# ---------------------------------------------------------------- scoring

def score(record, baseline):
    if not record.get("compiles"):
        return "DISCARDED"
    if record["law"] in ("failed", "trapped", "hung"):
        return "KILLED"
    if record["law"] != "passed":
        return "ERROR"
    if baseline.get("probe") is None:
        return "SURVIVED (unprobed)"
    if baseline.get("deterministic") is False:
        return "SURVIVED (undiffable)"
    return "DIVERGED" if record.get("probe") != baseline.get("probe") else "UNEXERCISED"


def report(sample_path, out_path):
    laws = {law["suite"]: law for law in json.load(open(sample_path))["laws"]}
    rows = [json.loads(row) for row in open(out_path)]
    baselines = {row["suite"]: row for row in rows if row.get("mutant") == "baseline"}
    table = collections.defaultdict(collections.Counter)
    killed_at_1000 = collections.Counter()
    for row in rows:
        if row.get("mutant") in ("baseline", "none") or "error" in row:
            continue
        law = laws[row["suite"]]
        outcome = score(row, baselines.get(row["suite"], {}))
        table[law["stratum"]][outcome] += 1
        if outcome != "KILLED" and row.get("law1000") in ("failed", "trapped", "hung"):
            killed_at_1000[law["stratum"]] += 1
    print(f"{'stratum':16}{'KILLED':>8}{'DIVERGED':>10}{'UNEXERC':>9}{'other':>7}{'discard':>9}{'kill% exercised':>17}{'+@1000':>8}")
    for stratum, _templates, _n in STRATA:
        counts = table[stratum]
        exercised = counts["KILLED"] + counts["DIVERGED"]
        other = sum(v for k, v in counts.items() if k.startswith("SURVIVED") or k == "ERROR")
        rate = f"{100 * counts['KILLED'] / exercised:.0f}% of {exercised}" if exercised else "—"
        print(f"{stratum:16}{counts['KILLED']:>8}{counts['DIVERGED']:>10}{counts['UNEXERCISED']:>9}"
              f"{other:>7}{counts['DISCARDED']:>9}{rate:>17}{killed_at_1000[stratum]:>8}")
    not_passing = [s for s, b in baselines.items() if b.get("law") != "passed"]
    print(f"\nbaselines not passing (excluded): {len(not_passing)} {not_passing[:8]}")


def main(argv):
    if argv[1] == "sample":
        found = candidates(argv[3:])
        sample, shortfalls = draw(found)
        os.makedirs(os.path.dirname(argv[2]), exist_ok=True)
        json.dump({"seed": SEED, "candidates": len(found),
                   "by_template": collections.Counter(l["template"] for l in found),
                   "shortfalls": shortfalls, "laws": sample}, open(argv[2], "w"), indent=1)
        print(f"{len(sample)} laws from {len(found)} candidates; shortfalls {shortfalls}")
        print(collections.Counter((l["stratum"], l["repo"]) for l in sample))
        return 0
    if argv[1] == "run":
        return run(argv[2], argv[3])
    if argv[1] == "report":
        report(argv[2], argv[3])
        return 0
    raise SystemExit("usage: mutation_check.py sample|run|report …")


if __name__ == "__main__":
    sys.exit(main(sys.argv))
