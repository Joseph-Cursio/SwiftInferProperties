#!/usr/bin/env python3
"""#668's kill arm — `docs/plans/xml-emitter-census-scope.md` §5.

Do #668's two laws, written by hand, detect mutants of SwiftUMLStudio `9ad7631`'s four SVG renderers that its
hand-written suite misses? The mutant generator, the watchdog, the patching and the flake rule are #667's
(`layering_kill_arm.py`, imported), with #669's rebinding of the watchdog list; this file binds them to #668's
subject, laws, suites and controls.

  --self-test            the plan and runner checks, without a compiler (joins `make measurement-selftest`)
  mutants <export>       list §5.3's mutants
  derived <export>       list §5.4's derived tests, those the reduced suite leaves out
  run <export> <report>  §5.5's controls, every mutant, then H1–H6; resumes from the report when the law and tree match
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
from layering_census import declarations  # noqa: E402
from layering_kill_arm import (  # noqa: E402
    BUILD_LIMIT, LAW_LIMIT, PACKAGE, RUN_FAILED, SOURCES, SUITE_LIMIT, Patched,
    _replace_once, _run, _sweep, all_mutants, apply, detected, tree_hash,
)
from mutation_check import mask  # noqa: E402


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
    """#667's watchdog list, less this runner and its ancestors (§5.4), as #669 rebinds it: #667's skips its own
    runner by its script name only, and this runner's command line names the export too."""
    mine = _ancestors()
    out = subprocess.run(["ps", "-axo", "pid=,command="], capture_output=True, text=True).stdout
    runners = {int(line.split(None, 1)[0]) for line in out.splitlines()
               if len(line.split(None, 1)) == 2 and "xml_emitter_kill_arm" in line.split(None, 1)[1]}
    return [(pid, rss) for pid, rss in _LISTED(export) if pid not in mine and pid not in runners]


layering_kill_arm._export_processes = _export_processes

# §5.1: Xcode 27.2's Swift 6.4.2, which replaced 6.4.0 on this machine on 2026-10-30 before §10's baseline was
# taken. #667's and #669's kill arms ran on `swiftlang-6.4.0.34.1`, so these counts are not toolchain-matched to theirs.
TOOLCHAIN = "swiftlang-6.4.2.1.9"
# §5.1: the export's `Sources/` as `git archive 9ad7631` writes it, hashed by `sources_hash`. A fresh report refuses
# any other tree, so a mutant a killed run left behind can never become the base.
SOURCES_SHA256 = "6dfe38076dd677c368064a53c3f6f5e23f129bdc9eb9328c8c9cbb0accad4f13"

HERE = os.path.dirname(os.path.abspath(__file__))
FIXTURES = os.path.join(HERE, "..", "fixtures", "xml-emitter-law")
LAW_DESTINATION = os.path.join(PACKAGE, "Tests", "SwiftUMLBridgeFrameworkTests", "XMLEmitterLaw",
                               "XMLEmitterLawTests.swift")

# §5.3: the bodies on the laws' call trees in five files. A nested function counts with its outer one.
MUTATED = {
    "Model/ComponentSVGRenderer+SVG.swift": ["renderSVG", "svgHeader", "edgeSVGLine", "componentSVGLines", "boxRect",
                                             "textElement", "edgePoint", "format"],
    "Emitters/SVGRenderer.swift": ["render", "arrowMarkers", "renderNode", "renderCluster", "moduleHue",
                                   "renderEdge", "fmt"],
    "Emitters/ActivitySVGRenderer.swift": ["renderFromLayout", "fmt"],
    "Emitters/ActivitySVGRenderer+Shapes.swift": ["renderNode", "renderCircle", "renderRoundedRect", "renderDiamond",
                                                  "renderBar", "renderCenteredText", "renderEdge", "renderForwardEdge",
                                                  "renderBackEdge"],
    "Emitters/SequenceSVGRenderer.swift": ["renderFromLayout", "renderParticipantBox", "renderMessage", "renderNote",
                                           "fmt"],
}
COUNTED = list(MUTATED)
PLANNED = 125

# Regexes over test IDs.
LAW1_FILTER, LAW2_FILTER = r"\.XMLEmitterLaw1Tests/", r"\.XMLEmitterLaw2Tests/"
SUITE_FILTER = r"^SwiftUMLBridgeFrameworkTests\."
FULL = ["--filter", SUITE_FILTER, "--skip", r"\.XMLEmitterLaw[12]Tests/"]
FULL_MINIMUM = 1839

# §5.4: what this law family's findings produced, by provenance: every test SwiftUMLStudio's PR #79 (for #56) and
# PR #86 (for #80) added, by suite and function, read from their merge commits' diffs; and any other test that calls
# `WellFormedXML`, the helper PR #79 created. Not a whole suite: `ActivityGraphBuilderCompactTextTests`, which PR #86
# created with two tests, has since gained eight for #63, and `SVGRendererTests.noClustersNoClusterBox` is an older
# test PR #79 renamed. The count is §10's.
DERIVED_FUNCTIONS = {
    ("DepsSVGTests", "doubleHyphenModuleNameIsWellFormed"),
    ("SVGRendererWellFormednessTests", "nodeLabelKeepsDocumentWellFormed"),
    ("SVGRendererWellFormednessTests", "clusterLabelKeepsDocumentWellFormed"),
    ("SVGRendererWellFormednessTests", "fullGraphIsWellFormed"),
    ("SVGRendererWellFormednessTests", "forbiddenCharacterInEveryTextSlotIsReplaced"),
    ("ActivitySVGRendererWellFormednessTests", "forbiddenCharacterInEveryTextSlotIsReplaced"),
    ("ActivitySVGRendererWellFormednessTests", "formFeedLineInFunctionBodyIsWellFormed"),
    ("ActivitySVGRendererWellFormednessTests", "controlCharacterInConditionCommentIsWellFormed"),
    ("SequenceSVGRendererWellFormednessTests", "forbiddenCharacterInEveryTextSlotIsReplaced"),
    ("ComponentSVGRendererWellFormednessTests", "forbiddenCharacterInEveryTextSlotIsReplaced"),
    ("ClassDiagramGeneratorTests", "svgWithDoubleHyphenRawIdentifierIsWellFormed"),
    ("ClassDiagramGeneratorTests", "svgWithControlCharacterInTypeAnnotationCommentIsWellFormed"),
    ("DependencyGraphGeneratorTests", "modulesSVGWithDoubleHyphenDirectoryIsWellFormed"),
    ("DependencyGraphGeneratorTests", "modulesSVGWithControlCharacterDirectoryIsWellFormed"),
    ("StringExtensionsTests", "xmlEscapedEscapesMarkup"), ("StringExtensionsTests", "xmlEscapedReplacesForbiddenControl"),
    ("StringExtensionsTests", "xmlEscapedKeepsLegalWhitespace"),
    ("StringExtensionsTests", "xmlEscapedReplacesForbiddenNoncharacters"),
    ("StringExtensionsTests", "xmlEscapedKeepsLegalCharacters"),
    ("StringExtensionsTests", "xmlEscapedEscapesMarkupBeforeCombiningMark"),
    ("StringExtensionsTests", "xmlEscapedTextOfEveryScalarIsWellFormed"),
    ("ActivityGraphBuilderCompactTextTests", "collapsesWhitespace"),
    ("ActivityGraphBuilderCompactTextTests", "keepsOtherControlCharacters"),
}
HELPER = "WellFormedXML"
DERIVED_COUNT = 23
TESTS_DIR = os.path.join(PACKAGE, "Tests", "SwiftUMLBridgeFrameworkTests")
# Set by `prepare` from the export: the derived tests' display titles, and the regex that skips them.
DERIVED_NAMES = set()
DERIVED_SKIP = [""]
SUMMARY = re.compile(r"^XML-EMITTER-LAW .*$", re.M)
LAW_LINES = 4


def test_functions(text):
    """`[(owner, function, title, body)]` for every `@Test` function in one test file. The title is the attribute's
    first string literal, or the function's name and `()` when it has none, as swift-testing displays it."""
    masked, _ = mask(text)
    _, functions = declarations(text)
    lines = text.split("\n")
    starts = [0]
    for line in lines[:-1]:
        starts.append(starts[-1] + len(line) + 1)
    found = []
    for function in functions:
        offset = starts[function["line"] - 1]
        keyword = offset + masked[offset:].find("func")
        at = masked.rfind("@Test", 0, keyword)
        if at < 0:
            continue
        cursor = at + len("@Test")
        if masked[cursor:cursor + 1] == "(":
            depth = 0
            while cursor < len(masked):
                if masked[cursor] == "(":
                    depth += 1
                elif masked[cursor] == ")":
                    depth -= 1
                    if depth == 0:
                        cursor += 1
                        break
                cursor += 1
        between = masked[cursor:keyword]
        if re.sub(r"@\w+(\([^)]*\))?|\b(?:static|private|fileprivate|internal|public|mutating|nonisolated)\b", "",
                  between).strip():
            continue
        literal = re.search(r'"((?:[^"\\]|\\.)*)"', text[at:cursor])
        title = literal.group(1) if literal else f"{function['name']}()"
        found.append((function["owner"], function["name"], title, function["text"]))
    return found


def derived_tests(sources):
    """§5.4's derived tests, given `{relative path: text}` of the test target: `[(owner, function, title, reason)]`."""
    found = []
    for relative in sorted(sources):
        for owner, name, title, body in test_functions(sources[relative]):
            if (owner, name) in DERIVED_FUNCTIONS:
                reason = "added"
            elif HELPER in body:
                reason = "helper"
            else:
                continue
            found.append((owner, name, title, reason))
    return found


def derived_skip(tests):
    """The `--skip` regex for the derived tests, one alternative per function."""
    return "|".join(rf"\.{re.escape(owner)}/{re.escape(name)}\(" for owner, name in
                    sorted({(owner, name) for owner, name, _, _ in tests}))


def sources_hash(export):
    """sha256 over the export's `Sources/` files, relative path and bytes, in path order."""
    root = os.path.join(export, PACKAGE, "Sources")
    digest = hashlib.sha256()
    for current, _, names in sorted(os.walk(root)):
        for name in sorted(names):
            path = os.path.join(current, name)
            digest.update(os.path.relpath(path, root).encode() + b"\0" + open(path, "rb").read() + b"\0")
    return digest.hexdigest()


def _sources(export):
    root = os.path.join(export, TESTS_DIR)
    found = {}
    for current, _, names in os.walk(root):
        for name in names:
            if name.endswith(".swift"):
                path = os.path.join(current, name)
                found[os.path.relpath(path, root)] = open(path, encoding="utf-8").read()
    return found


def prepare(export):
    """Read the derived tests from the export and set DERIVED_NAMES and DERIVED_SKIP."""
    tests = derived_tests(_sources(export))
    DERIVED_NAMES.clear()
    DERIVED_NAMES.update(title for _, _, title, _ in tests)
    DERIVED_SKIP[:] = [derived_skip(tests)]
    return tests


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
            "failed": failed_tests(output), "seconds": round(seconds, 1),
            "tests": int(ran.group(1)) if ran else 0, "summary": SUMMARY.findall(output),
            "tail": _counterexample(output) if mechanism else ""}


def _counterexample(output):
    """What §5.5 hand-checks: the output from the first failing test's issue on, which names the trial, the parser's
    reason and the drawn input before the document, capped at 20,000 characters; the last 1,500 when none is named."""
    first = output.find("✘ Test ")
    if first < 0:
        return output[-1500:]
    head = output[first:first + 20000]
    # A cut head would drop the end, where a crash's cause and SwiftPM's exit line are printed: keep both.
    return head if first + 20000 >= len(output) else head + "\n…\n" + output[-1500:]


# #667's failed-test pattern names a titled test (`✘ Test "title"`); swift-testing prints an untitled one bare
# (`✘ Test name() recorded …`), which `test_functions` titles `name()`. Both are read (§5.4).
FAILED_TEST = re.compile(r'✘ Test (?:"([^"]+)"|([A-Za-z_]\w*\([^)\s]*\)))')


def failed_tests(output):
    return sorted({titled or bare for titled, bare in FAILED_TEST.findall(output)})


def _derived(name):
    """A failed test's display name may carry its argument; it matches a title it equals or starts with."""
    return any(name == title or name.startswith(title + " ") for title in DERIVED_NAMES)


def reduced(swift, package, export, full):
    """The REDUCED suite (§5.4): the full suite less the derived tests. Read off the full run when it survived, or
    when it failed by assertion naming another test; otherwise run."""
    if full["outcome"] == "SURVIVED":
        return dict(full, derived_from_full=True)
    others = [name for name in full["failed"] if not _derived(name)]
    if full["mechanism"] == "ASSERTION" and others:
        return dict(full, failed=others, derived_from_full=True)
    result = _suite(swift, package, export, FULL + ["--skip", DERIVED_SKIP[0]], SUITE_LIMIT)
    return dict(result, derived_from_full=False)


def confirmed(swift, package, export, arguments, result):
    """§5.4's flake rule: a detection by ASSERTION is run once more, and stands only if the rerun detects too; then
    only the failures both runs name are kept, so a coincident flake cannot decide the reduced suite's read-off."""
    if result["mechanism"] != "ASSERTION":
        return result
    again = _suite(swift, package, export, arguments, SUITE_LIMIT)
    if again["outcome"] == "SURVIVED":
        return dict(again, flaked=result["failed"])
    shared = sorted(set(result["failed"]) & set(again["failed"]))
    if again["mechanism"] == "ASSERTION" and not shared:
        # Two assertion runs that name no failure in common reproduce nothing: a flake each time (§5.4).
        return dict(again, outcome="SURVIVED", mechanism=None, failed=[], disjoint=True,
                    flaked=sorted(set(result["failed"]) | set(again["failed"])))
    return dict(result, rerun=again["mechanism"], failed=shared,
                flaked=sorted(set(result["failed"]) - set(again["failed"])))


def _build(swift, package, export):
    code, output, seconds, stopped = _run([swift, "build", "--build-tests"], package, BUILD_LIMIT, export, False)
    if code != 0 or stopped:
        return {"build": "UNVIABLE", "build_seconds": round(seconds, 1),
                "errors": [line for line in output.splitlines() if "error:" in line][:5]}
    return {"build": "ok", "build_seconds": round(seconds, 1)}


def evaluate(swift, package, export, rerun=None):
    """Build, then Law 1, Law 2, the full suite and the reduced suite. `rerun` decides whether a suite detection by
    ASSERTION is confirmed: by default, when either law detected the mutant (§5.4)."""
    result = _build(swift, package, export)
    if result["build"] != "ok":
        return result
    law1 = _suite(swift, package, export, ["--filter", LAW1_FILTER], LAW_LIMIT)
    law2 = _suite(swift, package, export, ["--filter", LAW2_FILTER], LAW_LIMIT)
    confirm = (law1["outcome"] == "DETECTED" or law2["outcome"] == "DETECTED") if rerun is None else rerun
    suite = _suite(swift, package, export, FULL, SUITE_LIMIT)
    if confirm:
        suite = confirmed(swift, package, export, FULL, suite)
    reduced_ = reduced(swift, package, export, suite)
    if confirm and not reduced_["derived_from_full"]:
        reduced_ = dict(confirmed(swift, package, export, FULL + ["--skip", DERIVED_SKIP[0]], reduced_),
                        derived_from_full=False)
    return dict(result, law1=law1, law2=law2, suite=suite, reduced=reduced_)


def plan(export):
    """`(mutants, off_tree)`: §5.3's mutants on the call trees, and the per-function count of the scoped files' rest."""
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


COMPONENT = "Model/ComponentSVGRenderer+SVG.swift"
GRAPH = "Emitters/SVGRenderer.swift"
ESCAPER = "Emitters/String+Extensions.swift"
GUARD = "        guard !layout.components.isEmpty else { return \"\" }\n"
# RC7: `renderNode`'s `<g>` opener given back the label comment it had at `e36da59` (#56's defect).
RC7_FROM = ("        // because a comment cannot contain `--` and no escaping makes it legal there (#56).\n"
            "        var svg = \"\\n<g>\\n\"\n")
RC7_TO = ("        // because a comment cannot contain `--` and no escaping makes it legal there (#56).\n"
          "        var svg = \"\\n<!-- \\(node.label.xmlEscaped) -->\\n\"\n        svg += \"<g>\\n\"\n")
# §5.3's hand mutants, `(id, file, old, new)`: H1–H5 remove one arm of `xmlEscaped`'s switch each; H6 is RC7's patch,
# #56's label comment given back, counted with them so the decisive count with hand mutants sees the defect Law 1 found.
HAND = [
    ("H1", ESCAPER, "            case \"&\": escaped += \"&amp;\"\n", ""),
    ("H2", ESCAPER, "            case \"<\": escaped += \"&lt;\"\n", ""),
    ("H3", ESCAPER, "            case \">\": escaped += \"&gt;\"\n", ""),
    ("H4", ESCAPER, "            case \"\\\"\": escaped += \"&quot;\"\n", ""),
    ("H5", ESCAPER, "            case \"\\u{00}\"...\"\\u{1F}\": escaped.unicodeScalars.append(Unicode.Scalar(0x2400 + "
                    "scalar.value) ?? \"\\u{FFFD}\")\n", ""),
    ("H6", GRAPH, RC7_FROM, RC7_TO),
]


def _failed(result, prefix):
    return any(name.startswith(prefix) for name in result["failed"])


def controls(swift, export, package):
    """§5.5's RC1–RC4 and RC6–RC8. Returns `(results, passed)`; RC5 is checked after the run."""
    component, graph = (os.path.join(export, SOURCES, relative) for relative in (COMPONENT, GRAPH))
    results, ok = {}, {}
    baseline = evaluate(swift, package, export, rerun=True)
    results["RC1"] = baseline
    lines = (baseline.get("law1", {}).get("summary") or []) + (baseline.get("law2", {}).get("summary") or [])
    reach = [int(re.search(r"reach=(\d+)", line).group(1)) for line in lines if " R-" in line]
    ok["RC1"] = (baseline.get("build") == "ok" and baseline["law1"]["outcome"] == "SURVIVED"
                 and baseline["law2"]["outcome"] == "SURVIVED" and baseline["suite"]["outcome"] == "SURVIVED"
                 and baseline["suite"]["tests"] >= FULL_MINIMUM and not baseline["suite"].get("disjoint")
                 and len(baseline["law1"]["summary"]) == LAW_LINES and len(baseline["law2"]["summary"]) == LAW_LINES
                 and all(line.endswith("failures=0") for line in lines) and len(reach) == LAW_LINES
                 and all(count > 0 for count in reach))
    if ok["RC1"]:
        # The reduced suite, run once on the unmutated export, skips exactly the derived tests (§5.5).
        alone = _suite(swift, package, export, FULL + ["--skip", DERIVED_SKIP[0]], SUITE_LIMIT)
        alone = confirmed(swift, package, export, FULL + ["--skip", DERIVED_SKIP[0]], alone)
        results["RC1_reduced"] = alone
        ok["RC1"] = alone["outcome"] == "SURVIVED" and alone["tests"] == baseline["suite"]["tests"] - DERIVED_COUNT
    if ok["RC1"]:
        again = [_suite(swift, package, export, ["--filter", law], LAW_LIMIT) for law in (LAW1_FILTER, LAW2_FILTER)]
        results["RC6"] = again
        # The properties run in parallel and print as they finish, so the lines are compared as a set.
        ok["RC6"] = sorted(again[0]["summary"] + again[1]["summary"]) == sorted(lines)
    else:
        results["RC6"], ok["RC6"] = None, False
    with Patched(component, _replace_once("        lines.append(arrowMarkerDefs)\n", "")):
        results["RC2"] = evaluate(swift, package, export)
    rc2 = results["RC2"]
    ok["RC2"] = (detected(rc2, "law2") and rc2["law2"]["mechanism"] == "ASSERTION" and _failed(rc2["law2"], "R-C")
                 and not detected(rc2, "law1"))
    with Patched(graph, _replace_once("        svg += \"\\n</svg>\"\n", "")):
        results["RC3"] = evaluate(swift, package, export)
    rc3 = results["RC3"]
    ok["RC3"] = detected(rc3, "law1") and rc3["law1"]["mechanism"] == "ASSERTION" and _failed(rc3["law1"], "P-S")
    with Patched(component, _replace_once(GUARD, GUARD + "        let _: Int = \"x\"\n")):
        results["RC4"] = evaluate(swift, package, export)
    ok["RC4"] = results["RC4"].get("build") == "UNVIABLE"
    with Patched(graph, _replace_once(RC7_FROM, RC7_TO)):
        results["RC7"] = evaluate(swift, package, export)
    rc7 = results["RC7"]
    ok["RC7"] = detected(rc7, "law1") and rc7["law1"]["mechanism"] == "ASSERTION" and _failed(rc7["law1"], "P-S")
    with Patched(component, _replace_once(GUARD, GUARD + "        while !layout.components.isEmpty {}\n")):
        built = _build(swift, package, export)
        law1 = _suite(swift, package, export, ["--filter", LAW1_FILTER], LAW_LIMIT) if built["build"] == "ok" else None
        results["RC8"] = dict(built, law1=law1)
    ok["RC8"] = (results["RC8"]["build"] == "ok" and law1["mechanism"] == "TIMEOUT"
                 and law1["seconds"] < LAW_LIMIT + 45 and _sweep(export))
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
    shutil.copyfile(os.path.join(FIXTURES, "XMLEmitterLawTests.swift"), law)
    tests = prepare(export)
    if DERIVED_COUNT is None or len(tests) != DERIVED_COUNT:
        raise SystemExit(f"§5.4's derived tests number {len(tests)} in this export, not {DERIVED_COUNT}")
    report = json.load(open(out_path, encoding="utf-8")) if os.path.exists(out_path) else {}
    if not report and sources_hash(export) != SOURCES_SHA256:
        raise SystemExit("the export's Sources/ is not 9ad7631's: re-export it with `git archive 9ad7631`")
    mutants, off_tree = plan(export)
    if len(mutants) != PLANNED:
        raise SystemExit(f"§5.3 plans {PLANNED} mutants; this export gives {len(mutants)}")
    law_sha256, tree = hashlib.sha256(open(law, "rb").read()).hexdigest(), tree_hash(export)
    if report and (report.get("law_sha256") != law_sha256 or report.get("tree_before") != tree):
        raise SystemExit(f"{out_path} was taken with another law or source tree: start a fresh report (§5.5)")
    report.update(swift=version.strip(), law_sha256=law_sha256, tree_before=tree, off_tree=off_tree,
                  planned=len(mutants), derived=[list(test) for test in tests], derived_skip=DERIVED_SKIP[0])
    if "controls" not in report:
        results, ok = controls(swift, export, package)
        report["controls"], report["controls_passed"] = results, ok
        json.dump(report, open(out_path, "w", encoding="utf-8"), indent=1)
    print("controls:", report["controls_passed"], flush=True)
    if not all(report["controls_passed"].values()):
        print("a runner control failed — UNMEASURED (kills); no summary is written")
        return 1
    done = {row["id"] for row in report.get("mutants", []) + report.get("hand", [])}
    report.setdefault("mutants", [])
    report.setdefault("hand", [])
    for mutant in mutants:
        if mutant["id"] in done:
            continue
        path = os.path.join(export, SOURCES, mutant["file"])
        with Patched(path, lambda text, m=mutant: apply(text, m)):
            result = evaluate(swift, package, export)
        row = dict(mutant, **result)
        report["mutants"].append(row)
        json.dump(report, open(out_path, "w", encoding="utf-8"), indent=1)
        _print(row)
    for identifier, relative, old, new in HAND:
        if identifier in done:
            continue
        with Patched(os.path.join(export, SOURCES, relative), _replace_once(old, new)):
            result = evaluate(swift, package, export)
        row = dict({"id": identifier, "file": relative, "function": "renderNode" if relative == GRAPH else "xmlEscaped",
                    "operator": "hand", "original": old.strip(), "replacement": new.strip(), "line": 0}, **result)
        report["hand"].append(row)
        json.dump(report, open(out_path, "w", encoding="utf-8"), indent=1)
        _print(row)
    report["tree_after"] = tree_hash(export)
    report["controls_passed"]["RC5"] = report["tree_after"] == report["tree_before"]
    complete = len(report["mutants"]) == len(mutants) and len(report["hand"]) == len(HAND)
    report["summary"] = summarise(report["mutants"], report["hand"]) \
        if complete and report["controls_passed"]["RC5"] else None
    if report["summary"]:
        report["summary"].update(controls_passed=True, complete=True)
    json.dump(report, open(out_path, "w", encoding="utf-8"), indent=1)
    print(json.dumps(report["summary"], indent=1) if report["summary"] else "RC5 failed or the run is incomplete — no summary")
    return 0


def _print(row):
    cells = [row[side]["mechanism"] or "survived" for side in ("law1", "law2", "suite", "reduced")] \
        if row.get("build") == "ok" else ["-"] * 4
    print(f"{row['id']} {row['function']:<28} {row['operator']:<20} L{row['line']:<4} {row['build']:<8} "
          f"law1 {cells[0]:<9} law2 {cells[1]:<9} suite {cells[2]:<9} reduced {cells[3]}", flush=True)


def summarise(rows, hand=()):
    """§5.6's counts, for each law. A law-only kill is listed with its mechanism and the properties that failed."""
    viable = [row for row in rows if row.get("build") == "ok"]

    def ids(side, chosen=viable):
        return {row["id"] for row in chosen if detected(row, side)}

    suite, reduced_ = ids("suite"), ids("reduced")
    sole = collections.Counter()
    for row in viable:
        if row["id"] in suite and row["suite"]["mechanism"] == "ASSERTION" and len(row["suite"]["failed"]) == 1:
            sole[row["suite"]["failed"][0]] += 1
    summary = {"mutants": len(rows), "unviable": len(rows) - len(viable), "viable": len(viable),
               "suite": len(suite), "reduced": len(reduced_),
               "neither": sorted(row["id"] for row in viable if row["id"] not in ids("law1") | ids("law2") | suite),
               "sole_killing_test": dict(sole.most_common())}
    hand_viable = [row for row in hand if row.get("build") == "ok"]
    summary["hand"] = [{"id": row["id"], "law1": row["law1"]["mechanism"], "law2": row["law2"]["mechanism"],
                        "suite": row["suite"]["mechanism"], "reduced": row["reduced"]["mechanism"],
                        "suite_failed": row["suite"]["failed"][:6]} for row in hand_viable]
    for side in ("law1", "law2"):
        law = ids(side)

        def describe(chosen, side=side):
            return [{"id": row["id"], "file": row.get("file", ""), "function": row["function"],
                     "operator": row["operator"], "line": row["line"],
                     "mechanism": row[side]["mechanism"],
                     # A reduced suite that failed twice on different tests is SURVIVED; the hand-check sees it.
                     "reduced_flaked": (row.get("reduced") or {}).get("flaked", []),
                     "properties": sorted({name.split(":")[0] for name in row[side]["failed"]})}
                    for row in viable if row["id"] in chosen]

        by_function = collections.defaultdict(collections.Counter)
        for row in viable:
            in_law, in_suite = row["id"] in law, row["id"] in suite
            # Keyed by file too: `renderNode`, `renderEdge` and `renderFromLayout` each live in two files.
            cell = f"{row.get('file', '')}:{row['function']}"
            by_function[cell]["both" if in_law and in_suite else "law-only" if in_law
                              else "suite-only" if in_suite else "neither"] += 1
        vs_reduced = describe(law - reduced_)
        decisive = [entry for entry in vs_reduced if entry["mechanism"] == "ASSERTION"]
        hand_decisive = [row["id"] for row in hand_viable if detected(row, side)
                         and row[side]["mechanism"] == "ASSERTION" and not detected(row, "reduced")]
        summary[side] = {
            "law": len(law), "suite": len(suite), "reduced": len(reduced_), "both": len(law & suite),
            "viable": len(viable), "law_only_vs_suite": describe(law - suite), "law_only_vs_reduced": vs_reduced,
            "decisive": len(decisive), "law_only_reduced_other": len(vs_reduced) - len(decisive),
            "law_only_full": len(law - suite), "suite_only": len(suite - law),
            "hand_decisive": hand_decisive, "decisive_with_hand": len(decisive) + len(hand_decisive),
            "mechanisms": dict(collections.Counter(row[side]["mechanism"] for row in viable if row[side]["mechanism"])),
            "by_function": {name: dict(cells) for name, cells in sorted(by_function.items())}}
    summary["mechanisms"] = {side: dict(collections.Counter(row[side]["mechanism"] for row in viable
                                                            if row[side]["mechanism"]))
                             for side in ("suite", "reduced")}
    return summary


# ── Self-test (no compiler) ───────────────────────────────────────────────────────────────────────
COMPONENT_SNIPPET = '''extension ComponentSVGRenderer {
    public static func renderSVG(_ layout: ComponentLayout) -> String {
        guard !layout.components.isEmpty else { return "" }

        var lines: [String] = []
        lines.append(svgHeader(width: layout.totalWidth, height: layout.totalHeight))
        lines.append(arrowMarkerDefs)

        // Edges first so boxes paint over them at their borders.
        for dependency in layout.dependencies {
            if let edgeLine = edgeSVGLine(for: dependency, in: layout) {
                lines.append(edgeLine)
            }
        }

        for component in layout.components {
            lines.append(contentsOf: componentSVGLines(for: component))
        }

        lines.append("</svg>")
        return lines.joined(separator: "\\n")
    }
}
'''

GRAPH_SNIPPET = '''public struct SVGRenderer: Sendable {
    public static func render(_ graph: LayoutGraph) -> String {
        var svg = ""
        for node in graph.nodes {
            svg += renderNode(node)
        }

        svg += "\\n</svg>"
        return svg
    }

    private static func renderNode(_ node: LayoutNode) -> String {
        // The label appears only in the <text> elements. It is not copied into an XML comment,
        // because a comment cannot contain `--` and no escaping makes it legal there (#56).
        var svg = "\\n<g>\\n"
        svg += "</g>\\n"
        return svg
    }

    private static func renderCluster(_ cluster: LayoutCluster) -> String {
        // No label comment, for the reason given in `renderNode` (#56).
        var svg = "\\n<g>\\n"
        return svg
    }
}
'''

ESCAPER_SNIPPET = '''internal extension String {
    var xmlEscaped: String {
        var escaped = ""
        escaped.reserveCapacity(utf8.count)
        for scalar in unicodeScalars {
            switch scalar {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\\"": escaped += "&quot;"
            case "\\t", "\\n", "\\r": escaped.unicodeScalars.append(scalar)
            case "\\u{00}"..."\\u{1F}": escaped.unicodeScalars.append(Unicode.Scalar(0x2400 + scalar.value) ?? "\\u{FFFD}")
            case "\\u{FFFE}", "\\u{FFFF}": escaped.unicodeScalars.append("\\u{FFFD}")
            default: escaped.unicodeScalars.append(scalar)
            }
        }
        return escaped
    }
}
'''

TESTS_SNIPPET = {
    "EmitterTests/SVGRendererWellFormednessTests.swift": '''struct SVGRendererWellFormednessTests {
    @Test("a node label containing hyphens leaves the document well-formed", arguments: hyphenatedLabels)
    func nodeLabelKeepsDocumentWellFormed(label: String) {}
}
''',
    "ParsingTests/ActivityGraphBuilderCompactTextTests.swift": '''struct ActivityGraphBuilderCompactTextTests {
    @Test("compactText keeps a control character that is not whitespace")
    func keepsOtherControlCharacters() {}

    @Test("a label of 81 Characters becomes its first 77 plus an ellipsis")
    func overTheLimitIsTruncated() {}
}
''',
    "EmitterTests/DepsSVGTests.swift": '''struct DepsSVGTests {
    @Test("renders module boxes")
    func rendersModuleBoxes() {}

    @Test("a module name containing a double hyphen leaves the SVG well-formed")
    func doubleHyphenModuleNameIsWellFormed() {}
}
''',
    "EmitterTests/StringExtensionsTests.swift": '''struct StringExtensionsTests {
    @Test(
        "xmlEscaped replaces a C0 control",
        arguments: [UInt32(1)]
    )
    func xmlEscapedReplacesForbiddenControl(value: UInt32) throws {}

    @Test func nomnomlEscapes() {}
}
''',
    "ModelTests/LaterTests.swift": '''struct LaterTests {
    @Test("a later test that parses the output")
    func laterParses() {
        #expect(WellFormedXML.error(in: "") == nil)
    }

    @Test("an unrelated test")
    func unrelated() {}
}
''',
}


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
        derived = sorted(DERIVED_NAMES) + ["a node label containing hyphens leaves the document well-formed (x)"]
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
                           not result["derived_from_full"] and len(calls) == 1 and DERIVED_SKIP[0] in calls[0]))
        calls.clear()
        script[:] = [survived]
        flaky = confirmed("swift", "package", "export", FULL, {"outcome": "DETECTED", "mechanism": "ASSERTION",
                                                                "failed": ["a timing test"]})
        checks.append(("confirmed: an assertion that does not repeat is a flake, not a detection",
                       flaky["outcome"] == "SURVIVED" and flaky["flaked"] == ["a timing test"] and len(calls) == 1))
        assertion = {"outcome": "DETECTED", "mechanism": "ASSERTION"}
        script[:] = [dict(assertion, failed=["kept", "flake two"])]
        shared = confirmed("swift", "package", "export", FULL, dict(assertion, failed=["kept", "flake one"]))
        script[:] = [dict(assertion, failed=["flake four"])]
        disjoint = confirmed("swift", "package", "export", FULL, dict(assertion, failed=["flake three"]))
        checks.append(("confirmed: only the failures both runs name are kept; two runs naming none in common are a"
                       " flake each time, not a detection",
                       shared["outcome"] == "DETECTED" and shared["failed"] == ["kept"]
                       and disjoint["outcome"] == "SURVIVED" and disjoint["failed"] == []
                       and disjoint["flaked"] == ["flake four", "flake three"]))
        calls.clear()
        script[:] = [survived, dict(assertion, failed=["P-S: x"]), dict(assertion, failed=["other", "flake one"]),
                     dict(assertion, failed=["other", "flake two"])]
        built = globals()["_build"]
        globals()["_build"] = lambda *_: {"build": "ok"}
        try:
            result = evaluate("swift", "package", "export")
        finally:
            globals()["_build"] = built
        checks.append(("evaluate: Law 2 detecting alone confirms the suite's assertion, and the reduced suite is"
                       " read off the confirmed failures",
                       len(calls) == 4 and result["suite"]["failed"] == ["other"]
                       and result["reduced"]["failed"] == ["other"] and result["reduced"]["derived_from_full"]))
        script[:] = [{"outcome": "DETECTED", "mechanism": "CRASH", "failed": []}]
        crashed = confirmed("swift", "package", "export", FULL, dict(assertion, failed=["x"]))
        checks.append(("confirmed: an assertion whose rerun crashes stands, though the runs name no failure in common;"
                       " two disjoint assertion runs are marked disjoint",
                       crashed["outcome"] == "DETECTED" and crashed["rerun"] == "CRASH" and disjoint.get("disjoint")))
    finally:
        globals()["_suite"] = original
    return checks


def _output_checks():
    """§5.2, §5.4: the counterexample kept from a detecting run, and the failed tests read off it."""
    issue = '✘ Test "P-S: SVGRenderer.render parses" recorded an issue: trial 3: unexpected character; input: x\n'
    long = "preamble\n" * 200 + issue + "<svg>" + "x" * 30000 + "\nFatal error: crashed here\n"
    kept = _counterexample(long)
    short = _counterexample("preamble\n" + issue + "done\n")
    named = failed_tests('✘ Test "a titled test" failed\n✘ Test bareName() recorded an issue\n'
                         '✘ Test withArgs(x:) failed\n')
    return [("the counterexample starts at the first failing test's issue, keeps 20,000 characters and, when cut, the"
             " output's last 1,500", kept.startswith(issue) and "trial 3" in kept and "Fatal error: crashed here" in kept
             and len(kept) == 20000 + len("\n…\n") + 1500 and short == issue + "done\n"),
            ("failed tests: a titled one by its title, an untitled one by its name with its parentheses",
             named == ["a titled test", "bareName()", "withArgs(x:)"])]


def _watchdog_checks():
    """§5.4: the rebound watchdog list skips a process whose command line names this runner, and this process and
    its ancestors, and still lists any other process naming the export."""
    fake = f"/nonexistent/xml-emitter-self-test-{os.getpid()}/export"
    sleep = "import time; time.sleep(30)"
    runner = subprocess.Popen([sys.executable, "-c", sleep, "xml_emitter_kill_arm.py", "run", fake, "report.json"])
    helper = subprocess.Popen([sys.executable, "-c", sleep, "SwiftUMLBridgePackageTests.xctest", fake])
    # The probe names both modules by parts, so only the ancestor rule, never a name rule, can leave it out.
    # With a third argument it switches the ancestor rule off, to show the check can fail.
    probe = ("import sys, os; sys.path.insert(0, sys.argv[1]); m = __import__('xml_emitter' + '_kill' + '_arm'); "
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
    rows, _ = all_mutants(COMPONENT_SNIPPET, COMPONENT)
    removals = sorted(row["original"] for row in rows if row["operator"] == "remove-side-effects")
    tests = derived_tests(TESTS_SNIPPET)
    names = {(owner, name, reason) for owner, name, _, reason in tests}
    skip = derived_skip(tests)
    checks = [
        ("renderSVG's five `lines.append` sites are remove-side-effects mutants (F5's sites)",
         len(removals) == 5 and "lines.append(arrowMarkerDefs)" in removals and 'lines.append("</svg>")' in removals),
        ("the `</svg>` literal is never mutated in place", not any(row["operator"] != "remove-side-effects"
                                                                     and "</svg>" in row["original"] for row in rows)),
        ("an `svg += …` statement carries no removal mutant",
         not any(row["operator"] == "remove-side-effects" for row in all_mutants(GRAPH_SNIPPET, GRAPH)[0])),
        ("RC2's, RC3's, RC4's, RC7's and RC8's patches apply once to the snippets",
         "arrowMarkerDefs" not in _replace_once("        lines.append(arrowMarkerDefs)\n", "")(COMPONENT_SNIPPET)
         and "</svg>" not in _replace_once("        svg += \"\\n</svg>\"\n", "")(GRAPH_SNIPPET)
         and "let _: Int" in _replace_once(GUARD, GUARD + "        let _: Int = \"x\"\n")(COMPONENT_SNIPPET)
         and "<!--" in _replace_once(RC7_FROM, RC7_TO)(GRAPH_SNIPPET)),
        ("each of H1–H5 removes one arm of xmlEscaped, once; H6 is RC7's patch",
         all(_replace_once(old, new)(ESCAPER_SNIPPET).count("case ") == ESCAPER_SNIPPET.count("case ") - 1
             for _, relative, old, new in HAND if relative == ESCAPER)
         and HAND[-1] == ("H6", GRAPH, RC7_FROM, RC7_TO)),
        ("the suites' skip regex keeps both law suites out",
         all(re.search(FULL[3], f"SwiftUMLBridgeFrameworkTests.{suite}/x()")
             for suite in ("XMLEmitterLaw1Tests", "XMLEmitterLaw2Tests"))
         and not re.search(FULL[3], "SwiftUMLBridgeFrameworkTests.SVGRendererTests/x()")),
        ("the derived tests: the tests the PRs added, a later helper call; not a later test in a suite a PR created,"
         " and not their neighbours",
         names == {("SVGRendererWellFormednessTests", "nodeLabelKeepsDocumentWellFormed", "added"),
                   ("DepsSVGTests", "doubleHyphenModuleNameIsWellFormed", "added"),
                   ("StringExtensionsTests", "xmlEscapedReplacesForbiddenControl", "added"),
                   ("ActivityGraphBuilderCompactTextTests", "keepsOtherControlCharacters", "added"),
                   ("LaterTests", "laterParses", "helper")}),
        ("titles: one-line, multi-line, and a function's name when the attribute has none",
         sorted(title for _, _, title, _ in test_functions(TESTS_SNIPPET["EmitterTests/StringExtensionsTests.swift"]))
         == ["nomnomlEscapes()", "xmlEscaped replaces a C0 control"]),
        ("the derived skip regex skips each derived test and no neighbour",
         all(re.search(skip, f"SwiftUMLBridgeFrameworkTests.{owner}/{name}(x:)") for owner, name, _, _ in tests)
         and not any(re.search(skip, f"SwiftUMLBridgeFrameworkTests.{owner}/{name}()") for owner, name in
                     (("DepsSVGTests", "rendersModuleBoxes"), ("LaterTests", "unrelated"),
                      ("StringExtensionsTests", "nomnomlEscapes"), ("XMLEmitterLaw1Tests", "graphParses"),
                      ("DepsSVGTests", "doubleHyphenModuleNameIsWellFormedToo"),
                      ("ActivityGraphBuilderCompactTextTests", "overTheLimitIsTruncated")))),
    ]
    DERIVED_NAMES.clear()
    DERIVED_NAMES.update(title for _, _, title, _ in tests)
    DERIVED_SKIP[:] = [skip]
    checks.append(("every derived title is matched with and without an argument, and no other title",
                   all(_derived(title) and _derived(title + " (x)") for title in DERIVED_NAMES)
                   and not _derived("renders module boxes")))
    checks += _runner_checks()
    checks += _output_checks()
    checks += _watchdog_checks()

    def fake(identifier, law1, law2, suite, reduced_, mechanism="ASSERTION"):
        def side(hit):
            return {"outcome": "DETECTED" if hit else "SURVIVED", "mechanism": mechanism if hit else None,
                    "failed": ["P-C: x"] if hit else []}
        return {"id": identifier, "build": "ok", "function": "renderSVG", "operator": "x", "line": 1,
                "law1": side(law1), "law2": side(law2), "suite": side(suite), "reduced": side(reduced_)}

    summary = summarise([fake("M1", True, False, True, False), fake("M2", False, True, True, True),
                         fake("M3", False, True, False, False), fake("M4", True, True, False, False, "CRASH")],
                        [fake("H1", True, False, False, False), fake("H2", True, False, True, True),
                         fake("H3", True, False, False, False, "CRASH"), fake("H4", True, False, True, False)])
    checks.append(("summarise: law-only by assertion against the reduced suite, per law, and the H-mutants apart:"
                   " a hand mutant counts by assertion only, and against the reduced suite, not the full one",
                   summary["law1"]["decisive"] == 1 and summary["law1"]["law_only_reduced_other"] == 1
                   and summary["law2"]["decisive"] == 1 and summary["law1"]["law_only_full"] == 1
                   and summary["law1"]["decisive_with_hand"] == 3 and summary["law1"]["hand_decisive"] == ["H1", "H4"]
                   and summary["law2"]["decisive_with_hand"] == 1 and summary["neither"] == []))
    split = summarise([dict(fake("M1", True, False, False, False), file="A.swift", function="renderNode"),
                       dict(fake("M2", True, False, False, False), file="B.swift", function="renderNode")])
    checks.append(("summarise: one function name in two files is two cells, and each law-only kill names its file",
                   sorted(split["law1"]["by_function"]) == ["A.swift:renderNode", "B.swift:renderNode"]
                   and [entry["file"] for entry in split["law1"]["law_only_vs_reduced"]] == ["A.swift", "B.swift"]))
    flaky = fake("M1", True, False, False, False)
    flaky["reduced"]["flaked"] = ["one", "two"]
    checks.append(("summarise: a decisive kill whose reduced suite failed twice on different tests says so",
                   summarise([flaky])["law1"]["law_only_vs_reduced"][0]["reduced_flaked"] == ["one", "two"]))
    failed = [label for label, passed in checks if not passed]
    for label in failed:
        print(f"  FAIL {label}")
    print(f"xml emitter kill-arm controls: {len(checks) - len(failed)}/{len(checks)} pass")
    return not failed


def main(argv):
    if argv[1:] == ["--self-test"]:
        return 0 if self_test() else 1
    if len(argv) == 3 and argv[1] == "mutants":
        mutants, off_tree = plan(argv[2])
        for mutant in mutants:
            print(f"{mutant['id']} {mutant['file']}:{mutant['line']} {mutant['function']} {mutant['operator']}: "
                  f"{mutant['original']!r} → {mutant['replacement']!r}")
        print(f"{len(mutants)} mutants on the call trees; off-tree, not run: {sum(off_tree.values())} {off_tree}")
        print(collections.Counter(m["function"] for m in mutants))
        return 0
    if len(argv) == 3 and argv[1] == "derived":
        tests = prepare(argv[2])
        for owner, name, title, reason in tests:
            print(f"{reason:<7} {owner}.{name}  “{title}”")
        print(f"{len(tests)} derived tests; skip regex: {DERIVED_SKIP[0]}")
        return 0
    if len(argv) == 4 and argv[1] == "run":
        return run(argv[2], argv[3])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
