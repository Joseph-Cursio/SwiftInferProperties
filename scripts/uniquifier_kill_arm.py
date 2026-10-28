#!/usr/bin/env python3
"""#669's kill arm — `docs/plans/uniquifier-law-census-scope.md` §5.

Does the uniquifier law, written by hand, detect mutants of SwiftUMLStudio `c6c82e3`'s two id issuers that its
hand-written suite misses? The mutant generator, the watchdog, the patching and the flake rule are #667's
(`layering_kill_arm.py`, imported); this file binds them to #669's subject, law, suites and controls.

  --self-test            the plan and runner checks, without a compiler (joins `make measurement-selftest`)
  mutants <export>       list §5.3's mutants
  run <export> <report>  §5.5's controls, then every mutant; resumes from the report when the law and tree match
"""
import collections
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import layering_kill_arm  # noqa: E402
from layering_kill_arm import (  # noqa: E402
    BUILD_LIMIT, FAILED_TEST, LAW_LIMIT, PACKAGE, RUN_FAILED, SOURCES, SUITE_LIMIT, TOOLCHAIN, Patched,
    _replace_once, _run, _sweep, all_mutants, apply, detected, tree_hash,
)


def _ancestors():
    """This process and every process above it, up to launchd."""
    found, pid = set(), os.getpid()
    while pid > 1 and pid not in found:
        found.add(pid)
        out = subprocess.run(["ps", "-o", "ppid=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
        pid = int(out) if out.isdigit() else 0
    return found


_LISTED = layering_kill_arm._export_processes


def _export_processes(export):
    """#667's watchdog list, less this runner and its ancestors (§5.4). #667's skips its own runner by its script
    name only, so this runner, whose command line names the export too, would SIGKILL itself and the shell that
    started it at the first sweep. `_sweep`, `_kill` and `_resident_kb` look the name up at call time in #667's
    module, so rebinding it there is enough, and that file stays frozen."""
    mine = _ancestors()
    out = subprocess.run(["ps", "-axo", "pid=,command="], capture_output=True, text=True).stdout
    runners = {int(line.split(None, 1)[0]) for line in out.splitlines()
               if len(line.split(None, 1)) == 2 and "uniquifier_kill_arm" in line.split(None, 1)[1]}
    return [(pid, rss) for pid, rss in _LISTED(export) if pid not in mine and pid not in runners]


layering_kill_arm._export_processes = _export_processes

HERE = os.path.dirname(os.path.abspath(__file__))
FIXTURES = os.path.join(HERE, "..", "fixtures", "uniquifier-law")
LAW_DESTINATION = os.path.join(PACKAGE, "Tests", "SwiftUMLBridgeFrameworkTests", "UniquifierLaw",
                               "UniquifierLawTests.swift")

# §5.3: the bodies on the law's call tree inside the two scoped files. `id` is both of DiagramIdentifiers' overloads.
MUTATED = {
    "Model/DiagramContext.swift": ["uniqName", "reserveIdentifiers", "declaresIdentifier", "linkTarget",
                                   "addExtensionEdge", "drawsExtensionEdge", "nomnomlEdge", "linkType"],
    "Emitters/DiagramIdentifiers.swift": ["id"],
}
# §5.6: the functions whose result decides which id is issued; the rest only write edges and arrows.
ISSUING = {"uniqName", "reserveIdentifiers", "declaresIdentifier", "linkTarget", "id"}
COUNTED = list(MUTATED)

# Regexes over test IDs. The law is `UniquifierLawTests`; the setup-free control (§5.2's U0) is its own suite,
# kept out of the law run and of both suites.
LAW_FILTER, SETUP_FREE_FILTER = r"\.UniquifierLawTests/", r"\.UniquifierLawSetupFreeTests/"
SUITE_FILTER = r"^SwiftUMLBridgeFrameworkTests\."
FULL = ["--filter", SUITE_FILTER, "--skip", r"\.UniquifierLaw(?:SetupFree)?Tests/"]
# §5.4: the four suites the law family's own findings produced, left out of the REDUCED suite whole, as they stand
# at c6c82e3. SwiftUMLStudio's PR #65 (for #54, #669's witness) created the first three, and its PR #52 (for the
# sanitizer collision whose fix is `DiagramIdentifiers`) the fourth. 39 tests at c6c82e3.
DERIVED_SUITES = ("DiagramContextAliasTests", "ClassDiagramAliasTests", "ClassDiagramEdgeIdTests",
                  "DiagramIdentifiersTests")
DERIVED_FILES = ("ModelTests/DiagramContextAliasTests.swift", "EmitterTests/ClassDiagramAliasTests.swift",
                 "EmitterTests/ClassDiagramEdgeIdTests.swift", "EmitterTests/DiagramIdentifiersTests.swift")
DERIVED_COUNT = 39
DERIVED_SKIP = r"\.(?:" + "|".join(DERIVED_SUITES) + r")/"
# Their display titles, read from the export by `derived_titles` before the controls run; a failed test is matched
# by title, because that is what a run's `✘ Test "…"` line names.
DERIVED_NAMES = set()
TESTS_DIR = os.path.join(PACKAGE, "Tests", "SwiftUMLBridgeFrameworkTests")


def derived_titles(sources, only=DERIVED_FILES):
    """The `@Test("…")` titles in the derived suites' files (or in `only` of them), given `{relative path: text}`."""
    return [title for relative in only
            for title in re.findall(r'@Test\(\s*"((?:[^"\\]|\\.)*)"', sources[relative])]


# §8's DiagramIdentifiersTests sensitivity line: the titles of the one derived suite PR #52 created, set by `run`.
IDENTIFIER_TITLES = set()
SUMMARY = re.compile(r"^UNIQUIFIER-LAW .*$", re.M)
# RC1: U1 once per format, and M1.
LAW_LINES = 5


def _suite(swift, package, export, arguments, limit):
    """One test run, classified (§5.4): SURVIVED, or a detection by ASSERTION, CRASH, TIMEOUT or MEMORY."""
    code, output, seconds, stopped = _run([swift, "test", "--skip-build"] + arguments, package, limit, export, True)
    if stopped:
        mechanism = stopped
    elif code != 0:
        mechanism = "ASSERTION" if RUN_FAILED.search(output) else "CRASH"
    else:
        mechanism = None
    ran = re.search(r"Test run with (\d+) tests?", output)
    return {"outcome": "DETECTED" if mechanism else "SURVIVED", "mechanism": mechanism,
            "failed": sorted(set(FAILED_TEST.findall(output))), "seconds": round(seconds, 1),
            "tests": int(ran.group(1)) if ran else 0, "summary": SUMMARY.findall(output),
            "tail": output[-1500:] if mechanism else ""}


def _derived_in(name, titles):
    """A failed test's display name may carry its argument; it matches a title it equals or starts with."""
    return any(name == title or name.startswith(title + " ") for title in titles)


def _derived(name):
    return _derived_in(name, DERIVED_NAMES)


def reduced(swift, package, export, full):
    """The REDUCED suite (§5.4): the full suite less the four derived suites. Read off the full run when it
    survived, or when it failed by assertion naming another test; otherwise run."""
    if full["outcome"] == "SURVIVED":
        return dict(full, derived_from_full=True)
    others = [name for name in full["failed"] if not _derived(name)]
    if full["mechanism"] == "ASSERTION" and others:
        return dict(full, failed=others, derived_from_full=True)
    result = _suite(swift, package, export, FULL + ["--skip", DERIVED_SKIP], SUITE_LIMIT)
    return dict(result, derived_from_full=False)


def confirmed(swift, package, export, arguments, result):
    """§5.4's flake rule: a detection by ASSERTION is run once more, and stands only if the rerun detects too."""
    if result["mechanism"] != "ASSERTION":
        return result
    again = _suite(swift, package, export, arguments, SUITE_LIMIT)
    if again["outcome"] == "SURVIVED":
        return dict(again, flaked=result["failed"])
    return dict(result, rerun=again["mechanism"])


def evaluate(swift, package, export, rerun=None):
    """Build, then the law, the full suite and the reduced suite. `rerun` decides whether a suite detection by
    ASSERTION is confirmed: by default, when the law detected the mutant (§5.4)."""
    code, output, seconds, stopped = _run([swift, "build", "--build-tests"], package, BUILD_LIMIT, export, False)
    if code != 0 or stopped:
        errors = [line for line in output.splitlines() if "error:" in line][:5]
        return {"build": "UNVIABLE", "build_seconds": round(seconds, 1), "errors": errors}
    law = _suite(swift, package, export, ["--filter", LAW_FILTER], LAW_LIMIT)
    confirm = law["outcome"] == "DETECTED" if rerun is None else rerun
    suite = _suite(swift, package, export, FULL, SUITE_LIMIT)
    if confirm:
        suite = confirmed(swift, package, export, FULL, suite)
    reduced_ = reduced(swift, package, export, suite)
    if confirm and not reduced_["derived_from_full"]:
        reduced_ = dict(confirmed(swift, package, export, FULL + ["--skip", DERIVED_SKIP], reduced_),
                        derived_from_full=False)
    return {"build": "ok", "build_seconds": round(seconds, 1), "law": law, "suite": suite, "reduced": reduced_}


def plan(export):
    """`(mutants, off_tree)`: §5.3's mutants on the call tree, and the per-function count of the scoped files' rest."""
    mutants, off_tree = [], collections.Counter()
    for relative in COUNTED:
        text = open(os.path.join(export, SOURCES, relative), encoding="utf-8").read()
        rows, spans = all_mutants(text, relative)
        for mutant in rows:
            owner = mutant.pop("innermost")
            top = [name for name in MUTATED[relative]
                   if any(start <= mutant["offset"] < stop for start, stop in spans.get(name, []))]
            if top:
                mutant["function"] = top[0] if owner == top[0] else f"{top[0]}/{owner}"
                mutants.append(mutant)
            else:
                off_tree[f"{relative}:{owner}"] += 1
    for index, mutant in enumerate(mutants, 1):
        mutant["id"] = f"M{index:03d}"
    return mutants, dict(off_tree)


CONTEXT = "Model/DiagramContext.swift"
IDENTIFIERS = "Emitters/DiagramIdentifiers.swift"
# RC2: `uniqName` as it was before SwiftUMLStudio#65 — one suffix from the counter, never re-checked.
RC2_FROM = ("            repeat {\n                newName = name + \"\\(index)\"\n                index += 1\n"
            "            } while takenIdentifiers.contains(newName)")
RC2_TO = "            newName = name + \"\\(index)\"\n            index += 1"


def controls(swift, export, package):
    """§5.5's RC1–RC4, RC6 and RC7, and S0 (run after RC6, on the unmutated build). Returns `(results, passed)`; RC5 is checked after the run. S0 is a
    measurement, not a runner control: it never stops the run."""
    context, identifiers = (os.path.join(export, SOURCES, relative) for relative in (CONTEXT, IDENTIFIERS))
    results, ok = {}, {}
    baseline = evaluate(swift, package, export, rerun=True)
    results["RC1"] = baseline
    ok["RC1"] = (baseline.get("build") == "ok" and baseline["law"]["outcome"] == "SURVIVED"
                 and baseline["suite"]["outcome"] == "SURVIVED" and baseline["suite"]["tests"] >= 1800
                 and len(baseline["law"]["summary"]) == LAW_LINES
                 and all(line.endswith("failures=0") for line in baseline["law"]["summary"]))
    again = _suite(swift, package, export, ["--filter", LAW_FILTER], LAW_LIMIT) if ok["RC1"] else {"summary": None}
    results["RC6"] = again
    # The properties run in parallel and print as they finish, so the lines are compared as a set.
    ok["RC6"] = ok["RC1"] and sorted(again["summary"]) == sorted(baseline["law"]["summary"])
    # S0 (§5.2's U0): #669's law as written, with no setup call, on the unmutated build, before any patch.
    results["S0"] = _suite(swift, package, export, ["--filter", SETUP_FREE_FILTER], LAW_LIMIT)
    with Patched(context, _replace_once(RC2_FROM, RC2_TO)):
        results["RC2"] = evaluate(swift, package, export)
    rc2 = results["RC2"]
    ok["RC2"] = (detected(rc2, "law") and rc2["law"]["mechanism"] == "ASSERTION" and detected(rc2, "suite")
                 and any(name.startswith("U1") for name in rc2["law"]["failed"])
                 and not any(name.startswith("M1") for name in rc2["law"]["failed"]))
    with Patched(context, _replace_once("        if uniqElementNames.contains(name) {",
                                        "        if uniqElementNames.firstIndex(of: name) != nil {")):
        results["RC3"] = evaluate(swift, package, export, rerun=True)
    rc3 = results["RC3"]
    ok["RC3"] = rc3.get("build") == "ok" and not detected(rc3, "law") and not detected(rc3, "suite")
    marker = "        guard let name = item.fullName else { return \"\" }\n"
    with Patched(context, _replace_once(marker, marker + "        let _: Int = \"x\"\n")):
        results["RC4"] = evaluate(swift, package, export)
    ok["RC4"] = results["RC4"].get("build") == "UNVIABLE"
    with Patched(identifiers, _replace_once("            suffix += 1\n", "")):
        results["RC7"] = evaluate(swift, package, export)
    rc7 = results["RC7"]
    ok["RC7"] = (rc7.get("build") == "ok" and rc7["law"]["mechanism"] == "TIMEOUT"
                 and rc7["suite"]["mechanism"] == "TIMEOUT" and rc7["law"]["seconds"] < LAW_LIMIT + 45
                 and rc7["suite"]["seconds"] < SUITE_LIMIT + 45 and _sweep(export))
    return results, ok


def run(export, out_path):
    swift = subprocess.run(["xcrun", "--find", "swift"], capture_output=True, text=True).stdout.strip()
    version = subprocess.run([swift, "--version"], capture_output=True, text=True).stdout
    if TOOLCHAIN not in version:
        raise SystemExit(f"§5.1 runs on {TOOLCHAIN}; `xcrun --find swift` gives:\n{version}")
    export = os.path.realpath(export)
    package = os.path.join(export, PACKAGE)
    law = os.path.join(export, LAW_DESTINATION)
    os.makedirs(os.path.dirname(law), exist_ok=True)
    shutil.copyfile(os.path.join(FIXTURES, "UniquifierLawTests.swift"), law)
    titles = derived_titles({relative: open(os.path.join(export, TESTS_DIR, relative), encoding="utf-8").read()
                             for relative in DERIVED_FILES})
    if len(titles) != DERIVED_COUNT:
        raise SystemExit(f"§5.4's derived suites hold {len(titles)} tests in this export, not {DERIVED_COUNT}")
    DERIVED_NAMES.clear()
    DERIVED_NAMES.update(titles)
    IDENTIFIER_TITLES.clear()
    IDENTIFIER_TITLES.update(derived_titles({relative: open(os.path.join(export, TESTS_DIR, relative),
                                                            encoding="utf-8").read() for relative in DERIVED_FILES},
                                            only=DERIVED_FILES[-1:]))
    report = json.load(open(out_path, encoding="utf-8")) if os.path.exists(out_path) else {}
    mutants, off_tree = plan(export)
    law_sha256, tree = hashlib.sha256(open(law, "rb").read()).hexdigest(), tree_hash(export)
    if report and (report.get("law_sha256") != law_sha256 or report.get("tree_before") != tree):
        raise SystemExit(f"{out_path} was taken with another law or source tree: start a fresh report (§5.5)")
    report.update(swift=version.strip(), law_sha256=law_sha256, tree_before=tree, off_tree=off_tree,
                  planned=len(mutants))
    if "controls" not in report:
        results, ok = controls(swift, export, package)
        report["controls"], report["controls_passed"] = results, ok
        json.dump(report, open(out_path, "w", encoding="utf-8"), indent=1)
    print("controls:", report["controls_passed"], flush=True)
    print("S0:", report["controls"]["S0"]["mechanism"], report["controls"]["S0"]["summary"], flush=True)
    if not all(report["controls_passed"].values()):
        print("a runner control failed — UNMEASURED (kills); no summary is written")
        return 1
    done = {row["id"] for row in report.get("mutants", [])}
    report.setdefault("mutants", [])
    for mutant in mutants:
        if mutant["id"] in done:
            continue
        path = os.path.join(export, SOURCES, mutant["file"])
        with Patched(path, lambda text, m=mutant: apply(text, m)):
            result = evaluate(swift, package, export)
        row = dict(mutant, **result)
        report["mutants"].append(row)
        json.dump(report, open(out_path, "w", encoding="utf-8"), indent=1)
        cells = [row[side]["mechanism"] or "survived" for side in ("law", "suite", "reduced")] \
            if row.get("build") == "ok" else ["-", "-", "-"]
        print(f"{mutant['id']} {mutant['function']:<28} {mutant['operator']:<20} L{mutant['line']:<4} "
              f"{row['build']:<8} law {cells[0]:<9} suite {cells[1]:<9} reduced {cells[2]}", flush=True)
    report["tree_after"] = tree_hash(export)
    report["controls_passed"]["RC5"] = report["tree_after"] == report["tree_before"]
    complete = len(report["mutants"]) == len(mutants)
    report["summary"] = summarise(report["mutants"]) if complete and report["controls_passed"]["RC5"] else None
    if report["summary"]:
        report["summary"].update(controls_passed=True, complete=True)
    json.dump(report, open(out_path, "w", encoding="utf-8"), indent=1)
    print(json.dumps(report["summary"], indent=1) if report["summary"] else "RC5 failed or the run is incomplete — no summary")
    return 0


def law_properties(row):
    return sorted({name.split(":")[0] for name in row["law"]["failed"] if name[:2] in ("U1", "M1")})


def summarise(rows):
    """§5.6's counts. A law-only kill is listed with its mechanism, the properties that failed, and whether the
    mutated function decides which id is issued or only writes edges."""
    viable = [row for row in rows if row.get("build") == "ok"]

    def ids(side):
        return {row["id"] for row in viable if detected(row, side)}

    law, suite, reduced_ = ids("law"), ids("suite"), ids("reduced")

    def describe(chosen):
        return [{"id": row["id"], "function": row["function"], "operator": row["operator"], "line": row["line"],
                 "mechanism": row["law"]["mechanism"], "properties": law_properties(row),
                 "class": "issuing" if row["function"].split("/")[0] in ISSUING else "edges"}
                for row in viable if row["id"] in chosen]

    by_function = collections.defaultdict(collections.Counter)
    for row in viable:
        in_law, in_suite = row["id"] in law, row["id"] in suite
        by_function[row["function"]]["both" if in_law and in_suite else "law-only" if in_law
                                     else "suite-only" if in_suite else "neither"] += 1
    sole = collections.Counter()
    for row in viable:
        if row["id"] in suite and row["suite"]["mechanism"] == "ASSERTION" and len(row["suite"]["failed"]) == 1:
            sole[row["suite"]["failed"][0]] += 1
    vs_reduced = describe(law - reduced_)
    decisive = [entry for entry in vs_reduced if entry["mechanism"] == "ASSERTION"]
    # §8: a decisive kill that, in the full run, a DiagramIdentifiersTests test also detected rests on leaving
    # that suite out; the count without those is printed beside the decisive count.
    full_failed = {row["id"]: row["suite"]["failed"] for row in viable}
    resting = [entry["id"] for entry in decisive
               if any(_derived_in(name, IDENTIFIER_TITLES) for name in full_failed[entry["id"]])]
    return {"mutants": len(rows), "unviable": len(rows) - len(viable), "viable": len(viable),
            "law": len(law), "suite": len(suite), "reduced": len(reduced_), "both": len(law & suite),
            "neither": sorted(row["id"] for row in viable if row["id"] not in law | suite),
            "law_only_vs_suite": describe(law - suite), "law_only_vs_reduced": vs_reduced,
            "decisive": len(decisive), "law_only_reduced_other": len(vs_reduced) - len(decisive),
            "decisive_resting_on_identifiers": resting,
            "decisive_with_identifiers_kept": len(decisive) - len(resting),
            "law_only_full": len(law - suite), "suite_only": len(suite - law),
            "mechanisms": {side: dict(collections.Counter(row[side]["mechanism"] for row in viable
                                                          if row[side]["mechanism"]))
                           for side in ("law", "suite", "reduced")},
            "sole_killing_test": dict(sole.most_common()),
            "by_function": {name: dict(cells) for name, cells in sorted(by_function.items())}}


# ── Self-test (no compiler) ───────────────────────────────────────────────────────────────────────
CONTEXT_SNIPPET = '''class DiagramContext {
    func uniqName(item: SyntaxStructure, relationship: String) -> String {
        guard let name = item.fullName else { return "" }
        var newName = name
        if uniqElementNames.contains(name) {
            repeat {
                newName = name + "\\(index)"
                index += 1
            } while takenIdentifiers.contains(newName)
        } else {
            uniqElementNames.append(name)
        }
        if declaresIdentifier(of: item) {
            takenIdentifiers.insert(newName)
        }
        return newName
    }

    private func declaresIdentifier(of item: SyntaxStructure) -> Bool {
        item.kind != .macro || format == .plantuml
    }

    func collectNestedTypeConnections(items: [SyntaxStructure]) {
        for item in items where item.kind == .struct {
            nestingConnections.append(item.name ?? "")
        }
    }
}
'''


def _runner_checks():
    """`reduced()` and `confirmed()` against a scripted `_suite`: what is read off the full run, what is run."""
    calls, script = [], []

    def scripted(_swift, _package, _export, arguments, _limit):
        calls.append(arguments)
        return script.pop(0)

    survived = {"outcome": "SURVIVED", "mechanism": None, "failed": []}
    original = globals()["_suite"]
    globals()["_suite"] = scripted
    checks = []
    try:
        result = reduced("swift", "package", "export", survived)
        checks.append(("reduced: a survived full run is read off", result["derived_from_full"] and not calls))
        derived = sorted(DERIVED_NAMES) + ['Mermaid never declares two classes under one id "struct Foo0 {}"']
        other = {"outcome": "DETECTED", "mechanism": "ASSERTION", "failed": ["another test"] + derived}
        result = reduced("swift", "package", "export", other)
        checks.append(("reduced: an assertion naming another test is read off, less the derived tests and their"
                       " argument-carrying names", result["derived_from_full"] and result["failed"] == ["another test"]
                       and not calls))
        for label, full in (("only the derived tests", {"outcome": "DETECTED", "mechanism": "ASSERTION",
                                                        "failed": derived}),
                            ("a crash", {"outcome": "DETECTED", "mechanism": "CRASH", "failed": []}),
                            ("a timeout", {"outcome": "DETECTED", "mechanism": "TIMEOUT", "failed": []})):
            calls.clear()
            script[:] = [survived]
            result = reduced("swift", "package", "export", full)
            checks.append((f"reduced: {label} runs the reduced suite, skipping the derived tests",
                           not result["derived_from_full"] and len(calls) == 1 and DERIVED_SKIP in calls[0]))
        calls.clear()
        script[:] = [survived]
        flaky = confirmed("swift", "package", "export", FULL, {"outcome": "DETECTED", "mechanism": "ASSERTION",
                                                                "failed": ["a timing test"]})
        checks.append(("confirmed: an assertion that does not repeat is a flake, not a detection",
                       flaky["outcome"] == "SURVIVED" and flaky["flaked"] == ["a timing test"] and len(calls) == 1))
    finally:
        globals()["_suite"] = original
    return checks


def _watchdog_checks():
    """§5.4: the rebound watchdog list skips a process whose command line names this runner, and this process and
    its ancestors, and still lists any other process naming the export."""
    fake = f"/nonexistent/uniquifier-self-test-{os.getpid()}/export"
    sleep = "import time; time.sleep(30)"
    runner = subprocess.Popen([sys.executable, "-c", sleep, "uniquifier_kill_arm.py", "run", fake, "report.json"])
    helper = subprocess.Popen([sys.executable, "-c", sleep, "SwiftUMLBridgePackageTests.xctest", fake])
    # The probe names both modules by parts, so only the ancestor rule, never a name rule, can leave it out.
    # With a third argument it switches the ancestor rule off, to show the check can fail.
    probe = ("import sys, os; sys.path.insert(0, sys.argv[1]); m = __import__('uniquifier' + '_kill' + '_arm'); "
             "m._ancestors = (lambda: set()) if len(sys.argv) > 3 else m._ancestors; "
             "l = __import__('layering' + '_kill' + '_arm'); print(os.getpid(), [p for p, _ in l._export_processes(sys.argv[2])])")

    def ask(*extra):
        out = subprocess.run([sys.executable, "-c", probe, HERE, fake, *extra], capture_output=True,
                             text=True).stdout.split(" ", 1)
        return int(out[0]), out[1]

    try:
        time.sleep(0.3)
        listed = {pid for pid, _ in layering_kill_arm._export_processes(fake)}
        child, seen = ask()
        unguarded, unguarded_seen = ask("no-ancestors")
    finally:
        for process in (runner, helper):
            process.kill()
            process.wait()
    return [("the watchdog list skips this runner's command line and still lists a helper naming the export",
             listed == {helper.pid}),
            ("the watchdog list skips a process whose own command line names the export, when it asks, and lists "
             "it with the ancestor rule off", str(child) not in seen and str(helper.pid) in seen
             and str(unguarded) in unguarded_seen)]


def self_test():
    rows, spans = all_mutants(CONTEXT_SNIPPET, "Model/DiagramContext.swift")
    owners = collections.Counter(row["innermost"] for row in rows)
    checks = [
        ("the snippet's mutants fall in uniqName, declaresIdentifier and the off-tree function",
         set(owners) == {"uniqName", "declaresIdentifier", "collectNestedTypeConnections"}),
        ("the interpolated suffix is never mutated", not any("index)" in row["original"] for row in rows)),
        # #667's generator finds a condition by the `{` that ends it, so a `repeat`'s trailing `while` is never
        # negated (§5.3); RC2 removes the re-check by hand instead.
        ("the `if` and `declaresIdentifier` conditions are negated, the repeat-while's trailing one is not",
         sorted(row["original"] for row in rows if row["operator"] == "negate-conditional"
                and row["function"] == "uniqName") == ["declaresIdentifier(of: item)", "uniqElementNames.contains(name)"]),
        ("RC2's patch applies once to the snippet and leaves no re-check",
         "while takenIdentifiers" not in _replace_once(RC2_FROM, RC2_TO)(CONTEXT_SNIPPET)),
        ("the suites' skip regex keeps both law suites out",
         all(re.search(FULL[3], f"SwiftUMLBridgeFrameworkTests.{suite}/x()")
             for suite in ("UniquifierLawTests", "UniquifierLawSetupFreeTests"))
         and not re.search(FULL[3], "SwiftUMLBridgeFrameworkTests.DiagramContextAliasTests/x()")),
        ("the derived regex skips each of the four suites whole, and no other suite",
         all(re.search(DERIVED_SKIP, f"SwiftUMLBridgeFrameworkTests.{suite}/anyTest()") for suite in DERIVED_SUITES)
         and not any(re.search(DERIVED_SKIP, f"SwiftUMLBridgeFrameworkTests.{suite}/x()")
                     for suite in ("DiagramContextTests", "BoundGenericExtensionTests", "LayoutGraphBuilderNodeIdTests",
                                   "UniquifierLawTests", "XDiagramIdentifiersTests"))),
        ("titles are read from the four files, a multi-line `@Test(` and an escaped quote included",
         derived_titles({relative: text for relative, text in zip(DERIVED_FILES, (
             '@Test("one context never issues the same alias twice")\nfunc a() {}',
             '@Test("Mermaid never declares two classes under one id", arguments: x)\nfunc b() {}',
             '@Suite("x")\nstruct S {}',
             '@Test(\n    "distinct names never share an \\"identifier\\"", arguments: [\n])\nfunc c() {}'))})
         == ["one context never issues the same alias twice", "Mermaid never declares two classes under one id",
             'distinct names never share an \\"identifier\\"']),
    ]
    DERIVED_NAMES.update({"one context never issues the same alias twice",
                          "Mermaid never declares two classes under one id"})
    checks.append(("every derived title is matched with and without an argument, and no other title",
                   all(_derived(title) and _derived(title + " (x)") for title in DERIVED_NAMES)
                   and not _derived("a colliding extension with no derived title")))
    checks += _runner_checks()
    checks += _watchdog_checks()
    IDENTIFIER_TITLES.update({"an identifiers test"})
    summary = summarise([dict(row, build="ok", law={"outcome": "DETECTED", "mechanism": "ASSERTION", "failed": []},
                              reduced={"outcome": "SURVIVED", "mechanism": None, "failed": []},
                              suite={"outcome": "DETECTED", "mechanism": "ASSERTION", "failed": failed},
                              function="id", operator="x", line=1)
                         for row, failed in (({"id": "M1"}, ["an identifiers test (x)"]), ({"id": "M2"}, ["another"]))])
    checks.append(("a decisive kill the full run's DiagramIdentifiersTests detected is counted as resting on it",
                   summary["decisive"] == 2 and summary["decisive_resting_on_identifiers"] == ["M1"]
                   and summary["decisive_with_identifiers_kept"] == 1))
    failed = [label for label, passed in checks if not passed]
    for label in failed:
        print(f"  FAIL {label}")
    print(f"uniquifier kill-arm controls: {len(checks) - len(failed)}/{len(checks)} pass")
    return not failed


def main(argv):
    if argv[1:] == ["--self-test"]:
        return 0 if self_test() else 1
    if len(argv) == 3 and argv[1] == "mutants":
        mutants, off_tree = plan(argv[2])
        for mutant in mutants:
            print(f"{mutant['id']} {mutant['file']}:{mutant['line']} {mutant['function']} {mutant['operator']}: "
                  f"{mutant['original']!r} → {mutant['replacement']!r}")
        print(f"{len(mutants)} mutants on the call tree; off-tree, not run: {sum(off_tree.values())} {off_tree}")
        print(collections.Counter(m["function"] for m in mutants))
        return 0
    if len(argv) == 4 and argv[1] == "run":
        return run(argv[2], argv[3])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
