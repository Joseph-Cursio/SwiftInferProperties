#!/usr/bin/env python3
"""How often does a derived generator draw only a corner of its type? — `docs/plans/generator-diversity-scope.md`.

`mutation-reach.md` measured what one degenerate generator costs: `BigUInt(word:)` drew 1,000 different
numbers that were all ONE word, so a multiplication's long path was reached by no draw, and swapping
it for word arrays took killed mutants 35 → 58. Nothing in the pipeline flags such a generator — it
derives, compiles and runs. This draws 1,000 values from every generator expression a census's
compiled stubs use and counts two things:

- **values**: distinct `dump`s;
- **shapes**: distinct `dump`s with numbers and string contents masked, collection sizes and enum
  cases kept — so a `BigUInt` of one word reads as one shape however many numbers it holds.

A probe is appended to the first stub using each expression, as an extension of that stub's suite,
so every file-private helper the expression names stays in scope.

  run    <census-dir> <out.jsonl> [repo …]    probe every compiled stub's generators
  report <out.jsonl>                          classify and summarise
"""

import collections
import glob
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import corpus_funnel as cf  # noqa: E402
import mutation_check as mc  # noqa: E402

DRAWS = 1000
MARKER = "// generator_diversity.py probe"


def expressions(stub_text):
    """Each `(EXPR).run(using:` in the stub, as the text inside the parentheses."""
    masked, _ = mc.mask(stub_text)
    found = []
    for match in re.finditer(r"\.run\(using:", masked):
        end = match.start()
        if masked[end - 1] != ")":
            continue
        depth, start = 0, None
        for index in range(end - 1, -1, -1):
            if masked[index] == ")":
                depth += 1
            elif masked[index] == "(":
                depth -= 1
                if depth == 0:
                    start = index
                    break
        if start is not None:
            found.append(stub_text[start + 1:end - 1])
    return found


def normalised(expression):
    return " ".join(expression.split())


PROBE = """
{marker}
extension {suite} {{
    @Test func __genDiversity_{key}() {{
        var rng = Xoshiro(seed: (0x9E3779B97F4A7C15, 0xBF58476D1CE4E5B9, 0x94D049BB133111EB, 0x2545F4914F6CDD1D))
        var values = Set<String>()
        var shapes = Set<String>()
        var first = ""
        for _ in 0 ..< {draws} {{
            let value = ({expression}).run(using: &rng)
            var text = ""
            dump(value, to: &text, maxDepth: 6, maxItems: 64)
            if first.isEmpty {{ first = text }}
            values.insert(text)
            // Numbers and string contents masked; a collection's size and an enum's case kept.
            var shape = text.replacingOccurrences(of: #"(\\d+) (elements|key/value pairs|element)"#,
                                                  with: "N$1 $2", options: .regularExpression)
            shape = shape.replacingOccurrences(of: #""[^"\\n]*""#, with: "\\"…\\"", options: .regularExpression)
            shape = shape.replacingOccurrences(of: #"(?<!N)\\b\\d+(\\.\\d+)?(e[-+]?\\d+)?\\b"#, with: "#",
                                               options: .regularExpression)
            shapes.insert(shape)
        }}
        let sample = first.prefix(600).replacingOccurrences(of: "\\n", with: "\\u{{23CE}}")
        print("GENDIV|{key}|\\(values.count)|\\(shapes.count)|" + sample)
    }}
}}
"""


def install(package_dir):
    """Append one probe per distinct expression to the first stub using it. {key: (expr, uses, stub)}."""
    target = mc.census_target_dir(package_dir)
    if not target:
        return {}
    stubs = sorted(glob.glob(os.path.join(target, "*", "*.swift")))
    stubs = [s for s in stubs if not re.search(r"_(N1000|Probe)\.swift$", s)]
    seen, uses = {}, collections.Counter()
    for stub in stubs:
        text = open(stub, encoding="utf-8").read()
        if MARKER in text:
            text = text[:text.index(MARKER)].rstrip() + "\n"
            open(stub, "w", encoding="utf-8").write(text)
        suite = re.search(r"^struct (\w+)", text, re.M)
        if not suite:
            continue
        for expression in expressions(text):
            key = normalised(expression)
            uses[key] += 1
            if key not in seen:
                seen[key] = (expression, stub, suite.group(1))
    probes = {}
    by_stub = collections.defaultdict(list)
    for index, (key, (expression, stub, suite)) in enumerate(sorted(seen.items())):
        tag = f"g{index}"
        probes[tag] = {"expression": key, "uses": uses[key], "stub": stub}
        by_stub[(stub, suite)].append((tag, expression))
    for (stub, suite), items in by_stub.items():
        text = open(stub, encoding="utf-8").read()
        if "import Foundation" not in text:
            text = "import Foundation\n" + text
        for tag, expression in items:
            text += PROBE.format(marker=MARKER, suite=suite, key=tag, draws=DRAWS, expression=expression)
        open(stub, "w", encoding="utf-8").write(text)
    return probes


def run(census_dir, out_path, repos):
    log = open(out_path, "a")
    for path in sorted(glob.glob(os.path.join(census_dir, "result-*.json"))):
        result = json.load(open(path))
        repo = result["repo"]
        if repos and repo not in repos:
            continue
        swift = cf.toolchain(repo)
        for package in result.get("packages", []):
            if not package.get("compiled"):
                continue
            package_dir = os.path.normpath(os.path.join(census_dir, "trees", repo, package["package"]))
            probes = install(package_dir)
            if not probes:
                continue
            # A probe whose expression names something local to its test function — a held
            # receiver, a subject-literal array — cannot compile outside it. Strip the probes from
            # each file the compiler names and rebuild, recording those as unmeasured, rather than
            # losing every probe in the package to one of them.
            stripped = set()
            for _ in range(8):
                ok, output = mc.build(package_dir, swift)
                if ok:
                    break
                named = {os.path.realpath(f) for f in re.findall(r"^(/\S+\.swift):\d+:\d+: error:", output, re.M)}
                culprits = {tag for tag, probe in probes.items() if os.path.realpath(probe["stub"]) in named}
                if not culprits - stripped:
                    break
                for stub in {probes[tag]["stub"] for tag in culprits}:
                    text = open(stub, encoding="utf-8").read()
                    if MARKER in text:
                        open(stub, "w", encoding="utf-8").write(text[:text.index(MARKER)].rstrip() + "\n")
                stripped |= culprits
            for tag in stripped:
                probes[tag]["unmeasured"] = "probe did not compile outside its test"
            if not ok:
                log.write(json.dumps({"repo": repo, "package": package["package"], "error": "build failed",
                                      "detail": output[-1500:]}) + "\n")
                log.flush()
                continue
            env = dict(cf.environment(swift), SWIFT_DETERMINISTIC_HASHING="1")
            # A generator that traps on a draw kills the process and every probe queued behind it.
            # The probe that STARTED and never reported is the one that trapped; mark it and resume
            # on the rest.
            lines, trapped = {}, set()
            pending = {tag for tag, probe in probes.items() if not probe.get("unmeasured")}
            for _ in range(20):
                if not pending:
                    break
                pattern = r"__genDiversity_(" + "|".join(sorted(pending)) + r")\("
                try:
                    done = subprocess.run([swift, "test", "--skip-build", "--no-parallel", "--filter", pattern],
                                          cwd=package_dir, capture_output=True, text=True, env=env, timeout=1800)
                    output = done.stdout + done.stderr
                except subprocess.TimeoutExpired as error:
                    output = error.stdout.decode() if isinstance(error.stdout, bytes) else (error.stdout or "")
                for row in output.splitlines():
                    if row.startswith("GENDIV|"):
                        _, tag, values, shapes, sample = row.split("|", 4)
                        lines[tag] = (int(values), int(shapes), sample)
                started = re.findall(r"__genDiversity_(g\d+)\(\)[^\n]*started", output)
                silent = [tag for tag in started if tag not in lines]
                pending -= set(lines)
                if not silent:
                    break
                trapped.add(silent[-1])
                pending.discard(silent[-1])
            for tag, probe in probes.items():
                entry = {"repo": repo, "package": package["package"], "tag": tag, **probe}
                entry["stub"] = os.path.relpath(probe["stub"], os.path.join(census_dir, "trees", repo))
                if probe.get("unmeasured"):
                    entry["error"] = probe["unmeasured"]
                elif tag in lines:
                    entry.update(values=lines[tag][0], shapes=lines[tag][1], sample=lines[tag][2])
                elif tag in trapped:
                    entry["error"] = "generator trapped while drawing"
                else:
                    entry["error"] = "no probe output (trapped, hung, or not run)"
                log.write(json.dumps(entry) + "\n")
            log.flush()
    return 0


def kind(entry):
    """Scope §3's classes, decided on the draws alone."""
    if "error" in entry:
        return "NO READING"
    if entry["values"] == 1:
        return "CONSTANT"
    if entry["values"] <= 10:
        return "NARROW"
    room = re.search(r"elements|key/value pairs|Optional|\bnil\b|▿ [\w.]+\.[a-z]\w*(\(|$|⏎)", entry["sample"])
    if entry["shapes"] == 1 and room:
        return "SHAPE-FIXED"
    return "VARIED"


def report(out_path):
    rows = [json.loads(row) for row in open(out_path)]
    rows = [row for row in rows if "tag" in row or "error" in row]
    probes = [row for row in rows if "tag" in row]
    builds = [row for row in rows if "tag" not in row]
    tally = collections.Counter(kind(row) for row in probes)
    uses = collections.Counter()
    for row in probes:
        uses[kind(row)] += row["uses"]
    print(f"{len(probes)} generator expressions over {sum(r['uses'] for r in probes)} uses; build failures {len(builds)}")
    for name in ("CONSTANT", "NARROW", "SHAPE-FIXED", "VARIED", "NO READING"):
        print(f"  {name:12} {tally[name]:>4} expressions  {uses[name]:>5} uses")
    for name in ("CONSTANT", "NARROW", "SHAPE-FIXED"):
        print(f"\n{name}:")
        for row in sorted((r for r in probes if kind(r) == name), key=lambda r: -r["uses"]):
            print(f"  {row['repo']:22} uses {row['uses']:>3}  values {row['values']:>4} shapes {row['shapes']:>3}  "
                  f"{row['expression'][:110]}")
    return 0


def main(argv):
    if argv[1] == "run":
        return run(argv[2], argv[3], set(argv[4:]))
    if argv[1] == "report":
        return report(argv[2])
    raise SystemExit(__doc__)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
