#!/usr/bin/env python3
"""Driver for the corpus funnel walk: stages 1-6 over every subject repository.

Pipeline per `docs/measurements/corpus-funnel-census-2026-09-14.md`. **Committed, unlike the
three harnesses before it** — the 14 and 16 September drivers lived in session scratchpads, so
each census rebuilt the thing that measures it and the second rebuild found eight defects.

Resumable by design: every repository writes its own JSON result and is skipped when that file
exists. One hang costs one repository, not the run -- the 16 September census lost 2h29m to an
infinite loop and discarded a 2,914-stub pass.
"""
import collections
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import corpus_funnel_stage5 as s5  # noqa: E402

SWIFT_ORG = os.path.expanduser(
    "~/Library/Developer/Toolchains/swift-6.4.1-RELEASE.xctoolchain/usr/bin/swift")
XCODE = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"

# ⚠ **The toolchain is per REPOSITORY and it is not cosmetic.** SwiftMarkdownWiki needs Xcode's,
# because the swift.org one cannot see its SwiftUI cross-import overlay types; this project needed
# swift.org's, because Xcode 26's died in the plugin stage (Xcode 27's builds it; the swift.org pin
# moved 6.3.3 -> 6.4.0 on 2026-10-10, as 6.3.3 cannot use the macOS 27 SDK, then 6.4.0 -> 6.4.1 on
# 2026-10-14; see the Makefile).
# The 16 September census's worst defect was a toolchain mismatch that left 0 of 70 stubs carrying
# an import against 70 of 70 with the right one -- a whole pass discarded. Anything SwiftUI-shaped
# gets Xcode's.
XCODE_REPOS = {"SwiftMarkdownWiki", "SwiftUMLStudio", "SwiftLintRuleStudio",
               "SwiftFormatRuleStudio", "SwiftAssist", "LintStudioUI",
               "MacCloud_client_MacOS", "SwiftLintRuleStudioTeam", "SwiftCloneDetector"}

EXCLUDED = (".build", ".git", "checkouts", ".swiftinfer", "Generated")


def toolchain(repo):
    return XCODE if repo in XCODE_REPOS else SWIFT_ORG


def environment(swift):
    """The repo's toolchain, first on PATH.

    ⚠ **Choosing which `swift` RUNS the build is only half of it.** `swift-infer` resolves a
    subject's module by shelling out to bare `swift`, so with the wrong one first on PATH the
    stubs come out with no `@testable import` at all — the 16 September census's worst defect,
    which discarded a 2,914-stub pass. The first driver run reproduced it exactly: 0 of 35 on
    SwiftMarkdownWiki, caught by `import_rate` rather than by reading the stubs.

    Colored diagnostics are switched off there too — see `corpus_funnel_stage5.swift_environment`.
    """
    return s5.swift_environment(swift)


def worktree(repo_path, destination):
    """Detached worktree at a directory named EXACTLY for the repository.

    ⚠ **The directory name is not cosmetic: SwiftPM derives package identity from it.** A
    worktree called `wt-swiftpropertylaws` made the kit's own package fail with *unable to
    override package 'SwiftPropertyLaws' because its identity … doesn't match override's
    identity (directory name)*, which looked like a dependency conflict in the subject.
    """
    # ⚠ **A symlink here is the REAL repository, and the census must never run in it.**
    # `link_path_dependencies` links `trees/<repo>` to the real sibling when another subject
    # depends on it by `path:`. If that subject is walked first, this used to find the link,
    # return it, and rewrite the real checkout's manifest — the 20 September census left
    # SwiftPropertyLaws' `Package.swift` with every test target removed and a census target
    # added, uncommitted, for two days. Replacing the link with a worktree keeps the other
    # subject's path dependency resolving, now to a copy.
    if os.path.islink(destination):
        os.unlink(destination)
    elif os.path.isdir(destination):
        return destination
    os.makedirs(os.path.dirname(destination), exist_ok=True)
    subprocess.run(["git", "-C", repo_path, "worktree", "add", "-q", "--detach",
                    destination, "HEAD"], check=True, capture_output=True)
    return destination


_PATH_DEPENDENCY = re.compile(r'\.package\s*\(\s*path:\s*"([^"]+)"')


def link_path_dependencies(tree, siblings_root, real_root):
    """Satisfy `.package(path: "../X")` by linking the real sibling beside the worktree.

    ⚠ **A relocated worktree breaks every relative path dependency**, and the failure names a
    directory in the scratch tree rather than the subject — `the package at
    '…/run/SwiftPropertyLaws' cannot be accessed`, which reads as a broken subject. pbt-book and
    the workbook repos all depend on siblings this way.
    """
    linked = []
    for dirpath, dirs, files in os.walk(tree):
        dirs[:] = [d for d in dirs if d not in EXCLUDED]
        if "Package.swift" not in files:
            continue
        text = open(os.path.join(dirpath, "Package.swift"), encoding="utf-8",
                    errors="ignore").read()
        for relative in _PATH_DEPENDENCY.findall(text):
            wanted = os.path.normpath(os.path.join(dirpath, relative))
            if os.path.exists(wanted):
                continue
            name = os.path.basename(wanted)
            source = os.path.join(real_root, name)
            if not os.path.isdir(source):
                continue
            os.makedirs(os.path.dirname(wanted), exist_ok=True)
            try:
                os.symlink(source, wanted)
                linked.append(name)
            except FileExistsError:
                pass
    return linked


def seeds(cli, tree, out):
    done = subprocess.run([cli, ".", "--format", "pbt-seeds", "--include-nested-packages"],
                          cwd=tree, capture_output=True, text=True)
    open(out, "w", encoding="utf-8").write(done.stdout)
    try:
        payload = json.loads(done.stdout)
    except json.JSONDecodeError:
        return {"seeds": 0, "named": 0, "error": done.stderr[-500:]}
    rows = payload.get("seeds", [])
    # **Named = not `extractable-kernel`.** Recovered by reconciling the pilot against its
    # published row (103 - 19 = 84) and confirmed corpus-wide (3,398 - 682 = 2,716); the census
    # called them "closures inside a larger function" and never wrote the field down.
    named = [s for s in rows if s.get("kind") != "extractable-kernel"]
    return {"seeds": len(rows), "named": len(named), "rows": rows}


def packages(tree):
    """Every SwiftPM package in the tree, outermost first."""
    found = []
    for dirpath, dirs, files in os.walk(tree):
        dirs[:] = [d for d in dirs if d not in EXCLUDED]
        if "Package.swift" in files:
            found.append(dirpath)
    return sorted(found, key=len)


# Every target kind that HOLDS SOURCE a seed can name. **`regular` alone was wrong**: seeds
# land in macro and executable targets too, and filtering to `regular` silently scanned one of
# SwiftIdempotency's targets instead of both, taking its triage from six suggestions to one.
SOURCE_TARGET_TYPES = ("regular", "executable", "macro", "plugin", "system-target")

# ⚠ **A plugin is not an importable module.** Listing `PropertyLawDiscoveryPlugin` among the
# census target's dependencies made SwiftPM read it as a build-tool plugin to APPLY, and the
# package failed with *Plugin is declared with the `buildTool` capability, but doesn't conform
# to the `BuildToolPlugin` protocol* — which looks like a defect in the subject. Plugins are
# still SCANNED for seeds; they are just never depended on.
IMPORTABLE_TARGET_TYPES = ("regular", "executable", "macro")


def regular_targets(package_dir, swift):
    done = subprocess.run([swift, "package", "dump-package"], cwd=package_dir,
                          capture_output=True, text=True, env=environment(swift))
    if done.returncode != 0:
        return []
    try:
        dumped = json.loads(done.stdout)
    except json.JSONDecodeError:
        return []
    out = []
    for target in dumped.get("targets", []):
        kind = target.get("type")
        if kind not in SOURCE_TARGET_TYPES:
            continue
        path = target.get("path") or f"Sources/{target['name']}"
        out.append((target["name"], os.path.join(package_dir, path), kind))
    return out


def external_dependencies(package_dir, swift):
    """What the package's source targets depend on from OTHER packages, as manifest entries.

    ⚠ **A copied receiver construction names what its test file imports**, and since
    `swift-infer` began carrying those imports into the stub, the census target has to be able
    to resolve them: `SyntaxPattern` is `SwiftProjectLintVisitors`, a product of a sibling
    package that `SwiftProjectLintRules` depends on by name. A real test target depends on what
    its package's code depends on; the census target depended on the package's own targets
    alone, so it would have reported `no such module` for a module the package builds with.
    """
    done = subprocess.run([swift, "package", "dump-package"], cwd=package_dir,
                          capture_output=True, text=True, env=environment(swift))
    if done.returncode != 0:
        return []
    try:
        dumped = json.loads(done.stdout)
    except json.JSONDecodeError:
        return []
    own = {target["name"] for target in dumped.get("targets", [])}
    entries = []
    for target in dumped.get("targets", []):
        if target.get("type") not in SOURCE_TARGET_TYPES:
            continue
        for dependency in target.get("dependencies", []):
            if "product" in dependency:
                name, package = dependency["product"][0], dependency["product"][1]
                entry = f'.product(name: "{name}", package: "{package}")'
            elif "byName" in dependency and dependency["byName"][0] not in own:
                entry = f'"{dependency["byName"][0]}"'
            else:
                continue
            if entry not in entries and not any(kit in entry for kit in ('"PropertyLawKit"', '"PropertyBased"')):
                entries.append(entry)
    return entries


_IMPORT = re.compile(r"^@testable import ", re.M)


# Files the accept path writes BESIDE the stubs rather than as one. The syntax corpus holds the
# snippets SwiftSyntax-node generators draw from; counting it as a stub would add a law that
# does not exist and, having no `@testable import`, drag the import-rate guard down.
# The Sendable shim (`SendableShim`) is the same kind of file: one per test target, declaring
# drawn types `@unchecked Sendable`, with no test in it. Counted as a stub, it read as a compiled
# law that never reported — 15 phantom `unaccounted` on the first census run that wrote shims.
SUPPORT_FILES = {"SwiftInferSyntaxCorpus.swift", "SwiftInferSendableShims.swift"}


def is_stub(name):
    return name.endswith(".swift") and name not in SUPPORT_FILES


def import_rate(stub_dir):
    """Share of stubs carrying a `@testable import`. **A guard, not a statistic.**

    The census's worst defect read 0 of 70 here and was only caught because the number could
    not be true. A low rate means the module never resolved -- almost always the wrong `swift`
    first on PATH -- and every downstream count is then a fact about the harness.
    """
    stubs = [os.path.join(r, f) for r, _, fs in os.walk(stub_dir)
             for f in fs if is_stub(f)]
    if not stubs:
        return (0, 0)
    with_import = sum(1 for p in stubs
                      if _IMPORT.search(open(p, encoding="utf-8", errors="ignore").read()))
    return (with_import, len(stubs))


# `Refutability.tautologicalTemplates` is exactly one template, and its doc says adding to that
# set is "a deliberate, reviewable act". Mirrored here rather than inferred: a law class read off
# a guess is the defect #466 already records.
TAUTOLOGICAL = {"determinism"}

def laws_proposed(index_files, seed_rows, tree):
    """Named seeds that got ANY law, and that got a REFUTABLE one, from `seed-index.json`.

    ⚠ **Read from the INDEX, not from the accept transcript.** The first version parsed
    `discover --interactive` output, and that cannot answer this: interactive triage never shows
    a determinism-only seed, so *any law proposed* came back equal to *refutable law proposed* on
    every repository. It also matched paths in surrounding prose, so a transcript with four
    `Template:` blocks yielded fifteen locations — which happened to equal the published figure,
    and agreeing with a known answer for the wrong reason is worse than disagreeing.

    The index records one entry per suggestion with its `templateName` and a `path:line`
    location, which is exactly the join every other stage of this walk uses.
    """
    named = {(os.path.realpath(os.path.join(tree, row["file"])), row["line"])
             for row in seed_rows if row.get("kind") != "extractable-kernel"}
    any_law, refutable = set(), set()
    for path in index_files:
        try:
            entries = json.load(open(path, encoding="utf-8")).get("entries", [])
        except (OSError, json.JSONDecodeError):
            continue
        for entry in entries:
            location = entry.get("location", "")
            if ":" not in location:
                continue
            file_part, _, line_part = location.rpartition(":")
            if not line_part.isdigit():
                continue
            key = (os.path.realpath(file_part), int(line_part))
            if key not in named:
                continue
            any_law.add(key)
            if entry.get("templateName") not in TAUTOLOGICAL:
                refutable.add(key)
    return {"any": len(any_law), "refutable": len(refutable)}



def stub_dirs(package_dir):
    """Every `Generated/SwiftInfer` directory the accept path wrote into this package.

    ⚠ **The walk stops at a nested package's boundary.** The accept path writes a nested
    package's stubs into THAT package's test target, and descending into it here let the outer
    package claim them — the consolidation below then moved them into the outer census target,
    which cannot import the nested module. Measured on SwiftIdempotency: 4 stubs failed with
    `no such module 'AssertIdempotentSample'` in the root package while the nested package that
    owns them reported 0 stubs.
    """
    found = []
    for dirpath, dirs, _files in os.walk(package_dir):
        dirs[:] = [d for d in dirs if d not in (".build", ".git", "checkouts")
                   and not os.path.exists(os.path.join(dirpath, d, "Package.swift"))]
        if os.path.basename(dirpath) == "SwiftInfer" and "Generated" in dirpath:
            found.append(dirpath)
    return found


# Templates whose law cannot notice a WRONG ANSWER, only a crash — reported apart from `passed`.
#
# ⚠ **A totality pass means the call returned, nothing more.** The mutation check
# (`docs/measurements/funnel-mutation-check.md`) inverted predicates' answers 12 times and these
# laws caught none of them; the one totality kill was a trap. They were 75% of the funnel's
# passes, so a single `passed` figure read as "577 behaviours checked" when it was mostly "577
# functions did not crash". `determinism` joins them as `Refutability.tautologicalTemplates`'
# one member: `f(x) == f(x)` cannot fail at all. Everything else is `passed_behaviour`.
DOES_NOT_CRASH_TEMPLATES = {"predicate", "input-totality", "determinism"}


def suite_templates(stubs_dir):
    """Each generated suite's template, read from the directory its stub was written into."""
    templates = {}
    for path in glob.glob(os.path.join(stubs_dir, "*", "*.swift")):
        match = re.search(r"^struct (\w+)", open(path, encoding="utf-8").read(), re.M)
        if match:
            templates[match.group(1)] = os.path.basename(os.path.dirname(path))
    return templates


def record_passes(entry, ran, stubs_dir):
    """`passed` for the package, split into laws that check behaviour and laws that check survival."""
    templates = suite_templates(stubs_dir)
    by_template = collections.Counter(templates.get(name.split(".")[0], "unknown") for name in ran["passed"])
    entry["passed"] = len(ran["passed"])
    entry["passed_by_template"] = dict(by_template)
    entry["passed_does_not_crash"] = sum(n for t, n in by_template.items() if t in DOES_NOT_CRASH_TEMPLATES)
    entry["passed_behaviour"] = entry["passed"] - entry["passed_does_not_crash"]


def declared_tests(stubs_dir):
    """`Suite.test()` for every @Test a compiled stub file declares (set-aside files have been moved out)."""
    keys = []
    for path in glob.glob(os.path.join(stubs_dir, "*", "*.swift")):
        text = open(path, encoding="utf-8", errors="ignore").read()
        suite = re.search(r"^struct (\w+)", text, re.M)
        if suite:
            keys += [f"{suite.group(1)}.{name}()"
                     for name in re.findall(r"@Test(?:\([^)]*\))?\s+func\s+(\w+)\s*\(", text)]
    return keys


_OUTCOMES = ("passed", "failed", "crashed", "hung")


def record_outcomes(entry, ran, stubs_dir, declared, bisect_stats=None):
    """Every outcome column for one package. Law tests feed the legacy columns, exactly as before #665;
    a predicate stub's reach test feeds only `reach`.

    ⚠ **A reach test that passes is not a law that passes.** It sits in a `predicate` suite, so
    `record_passes` would file it under `passed_does_not_crash` — one phantom law per green reach
    check, and another per warned one — and `compiled`, which counts stub FILES, would stop
    reconciling with the outcome columns, which count TESTS. Filtering by suffix keeps every legacy
    column what it was; the reach outcomes get their own bucket.
    """
    law = {k: [n for n in ran.get(k, []) if not s5.is_reach(n)] for k in _OUTCOMES}
    reach = {k: [n for n in ran.get(k, []) if s5.is_reach(n)] for k in _OUTCOMES}
    record_passes(entry, law, stubs_dir)                       # unchanged function
    entry["failed"], entry["crashed"], entry["hung"] = len(law["failed"]), len(law["crashed"]), len(law["hung"])
    entry["hung_tests"], entry["failures"] = law["hung"][:5], law["failed"]
    entry["passed_tests"], entry["crashed_tests"], entry["hung_tests_all"] = law["passed"], law["crashed"], law["hung"]
    warned, sides = set(ran.get("warned", [])), ran.get("sides", {})
    entry["warned_tests"] = sorted(n for n in warned if not s5.is_reach(n))
    entry["exhausted"], entry["resumes"] = bool(ran.get("exhausted")), ran.get("resumes", 0)
    entry["run_seconds"] = ran.get("run_seconds", [])
    if bisect_stats is not None:
        entry["bisect"] = bisect_stats
    declared_reach = {k for k in declared if s5.is_reach(k)}
    reported = list(reach["failed"]) + [n for n in reach["passed"] if n in warned]
    entry["reach"] = {
        "expected": len(declared_reach),
        "green": sorted(n for n in reach["passed"] if n not in warned),
        "not_applied": {n: sorted(sides[n]) for n in reported if sides.get(n)},
        "other": sorted(n for n in reported if not sides.get(n)),     # an emitter defect until shown otherwise
        "crashed": reach["crashed"], "hung": reach["hung"],
        "skipped_after_law": sorted(set(ran.get("reach_skipped_after_law", [])) & declared_reach),
    }
    seen = {n for k in _OUTCOMES for n in ran.get(k, [])}
    seen |= set(entry["reach"]["skipped_after_law"])
    entry["reach"]["unaccounted"] = sorted(declared_reach - seen)
    missing = sorted(set(declared) - seen)
    entry["unaccounted_tests"], entry["unaccounted_test_names"] = len(missing), missing[:10]


def _reach_tests(declared):
    return {name for name in declared if s5.is_reach(name)}


def _unaccounted(per_package):
    """Compiled stubs that reported no outcome of any kind, summed over a repository's packages.

    A package with `no_verdict` is skipped: its stubs are UNMEASURED rather than lost, which is
    the distinction `passed = None` already carries, and counting them here would report the
    run's one honest abstention as a defect.
    """
    total = 0
    for package in per_package:
        if package.get("no_verdict") or package.get("passed") is None:
            continue
        outcomes = sum(package.get(key) or 0 for key in ("passed", "failed", "crashed", "hung"))
        total += max(0, (package.get("compiled") or 0) - outcomes)
    return total


def walk_repo(repo, repo_path, scratch, infer, cli, timeout=2400):
    """Stages 1-5 for one repository. Every failure is recorded, never raised."""
    swift = toolchain(repo)
    result = {"repo": repo, "toolchain": os.path.basename(os.path.dirname(swift)),
              "started": time.strftime("%H:%M:%S")}
    tree = worktree(repo_path, os.path.join(scratch, "trees", repo))
    result["linked_siblings"] = link_path_dependencies(
        tree, os.path.join(scratch, "trees"), os.path.dirname(repo_path))

    seeds_path = os.path.join(scratch, f"{repo}-seeds.json")
    seeded = seeds(cli, tree, seeds_path)
    result.update(seeds=seeded["seeds"], named=seeded["named"])
    if not seeded.get("rows"):
        result["note"] = "no seeds"
        return result

    seed_files = {os.path.normpath(os.path.join(tree, s["file"])) for s in seeded["rows"]}

    scanned, stub_total, transcripts, index_files = [], 0, [], []
    for package_dir in packages(tree):
        for name, directory, _kind in regular_targets(package_dir, swift):
            if not any(f.startswith(os.path.normpath(directory) + os.sep) for f in seed_files):
                continue
            # **The index runs FIRST, and its output is copied out**: `discover` clears
            # `.swiftinfer/` below, which would take `seed-index.json` with it.
            index_out = os.path.join(scratch, f"index-{repo}-{name}.json")
            # ⚠ **`index --target` resolves `Sources/<target>` and nothing else.** A manifest may
            # put a target anywhere via `path:` — SwiftMarkdownWiki uses `path:
            # "SwiftMarkdownWiki"` — and the command then fails with *no `Sources/` directory*,
            # so that repository contributed 0 to both middle stages while writing 35 stubs,
            # which cannot both be true. `discover` has `--sources` for this; `index` does not,
            # so the expected directory is linked for the duration. This is the harness working
            # around a product gap, and it is recorded as such rather than hidden.
            expected = os.path.join(package_dir, "Sources", name)
            linked = False
            if not os.path.exists(expected) and os.path.isdir(directory):
                os.makedirs(os.path.dirname(expected), exist_ok=True)
                try:
                    os.symlink(directory, expected)
                    linked = True
                except OSError:
                    pass
            subprocess.run([infer, "index", "--target", name, "--seeds", seeds_path,
                            "--include-possible"], cwd=package_dir, capture_output=True,
                           text=True, timeout=timeout, env=environment(swift))
            written = os.path.join(package_dir, ".swiftinfer", "seed-index.json")
            if os.path.exists(written):
                shutil.copy(written, index_out)
                index_files.append(index_out)
            if linked:
                os.unlink(expected)

            # ⚠ **Recorded decisions are cleared between scan groups.** A decision suppresses
            # its suggestion, so `.swiftinfer/decisions.json` surviving from the previous
            # target offers this one nothing — the 16 September census's defect #1, and the
            # reason its first pass had to be discarded. Each target is its own scan group.
            decisions = os.path.join(tree, ".swiftinfer")
            if os.path.isdir(decisions):
                subprocess.run(["rm", "-rf", decisions], check=False)
            done = subprocess.run([infer, "discover", "--sources", directory,
                                   "--include-possible", "--interactive"],
                                  cwd=tree, input="A\n" * 4000, capture_output=True,
                                  text=True, timeout=timeout, env=environment(swift))
            # **Keep the accept path's own output.** The two middle funnel stages — *any law
            # proposed* and *refutable law proposed* — are in here already, one `Template:` line
            # per suggestion beside the subject's location. The first version of this harness
            # discarded it and reported those two stages as "not captured", which left the
            # funnel with a hole that a second tool invocation was going to be needed to fill.
            transcript = os.path.join(scratch, f"discover-{repo}-{name}.txt")
            open(transcript, "w", encoding="utf-8").write(done.stdout + done.stderr)
            transcripts.append(transcript)
            scanned.append({"package": os.path.relpath(package_dir, tree),
                            "target": name, "exit": done.returncode})
    result["scanned_targets"] = scanned
    proposed = laws_proposed(index_files, seeded["rows"], tree)
    result.update(any_law=proposed["any"], refutable_law=proposed["refutable"])

    per_package = []
    for package_dir in packages(tree):
        dirs = stub_dirs(package_dir)
        if not dirs:
            continue
        # ⚠ **A package can hold several `Generated/SwiftInfer` trees** — one per test target the
        # accept path chose across scan groups. Wiring only the first into the census target left
        # SwiftPropertyLaws reporting 1 stub of its 45 and building none of the rest. They are
        # consolidated into the first so one census target covers the package.
        for extra in dirs[1:]:
            for root, _sub, files in os.walk(extra):
                for name in files:
                    if not name.endswith(".swift"):
                        continue
                    relative = os.path.relpath(os.path.join(root, name), extra)
                    target = os.path.join(dirs[0], relative)
                    os.makedirs(os.path.dirname(target), exist_ok=True)
                    if not os.path.exists(target):
                        os.replace(os.path.join(root, name), target)
        dirs = [dirs[0]]
        stubs = sum(len([f for f in os.listdir(os.path.join(r))
                         if is_stub(f)])
                    for d in dirs for r, _, _ in os.walk(d))
        stub_total += stubs
        with_import, total = import_rate(dirs[0])
        entry = {"package": os.path.relpath(package_dir, tree), "stubs": total,
                 "with_import": with_import}
        # ⚠ The guard. Below half means the module never resolved; the counts below it would be
        # facts about the harness, so the package is recorded unbuilt rather than measured.
        if total and with_import * 2 < total:
            entry["blocked"] = f"import rate {with_import}/{total} — module did not resolve"
            per_package.append(entry)
            continue
        modules = [name for name, _dir, kind in regular_targets(package_dir, swift)
                   if kind in IMPORTABLE_TARGET_TYPES]
        if not modules:
            entry["blocked"] = "no regular target"
            per_package.append(entry)
            continue
        try:
            s5.rewrite_manifest(os.path.join(package_dir, "Package.swift"), modules,
                                "SwiftInferCensusTests",
                                os.path.relpath(dirs[0], package_dir),
                                external_dependencies(package_dir, swift))
            s5.verify_manifest(package_dir, swift)
        except (SystemExit, ValueError) as error:
            entry["blocked"] = f"manifest: {str(error)[:300]}"
            per_package.append(entry)
            continue
        try:
            built = s5.build_to_fixpoint(package_dir, dirs[0], swift,
                                         os.path.join(scratch, f"aside-{repo}"))
            entry["built"] = built["built"]
            entry["set_aside"] = built["set_aside"]
            # ⚠ **`compiled` is zero unless the target BUILT.** Counting `total - set_aside`
            # regardless reported 2 compiled for a package whose build failed on a manifest
            # error and which therefore ran nothing — a headline inflated by a number that
            # described no artifact.
            entry["compiled"] = (total - len(built["set_aside"])) if built["built"] else 0
            if not built["built"]:
                detail = built.get("unattributed", "")
                entry["unattributed"] = detail[-600:]
                # **A resolution conflict is a fact about the SUBJECT, not a harness failure.**
                # pbt-workbook, -sampler and -corpus pin swift-property-based 1.2 in library
                # code while the stubs need the kit's 2.x; the 16 September census recorded that
                # as a standing limit and left it standing. Classified so the funnel can report
                # "emitted, not compilable here" rather than counting it as the tool's ceiling.
                if "could not be resolved" in detail or "Dependencies could not" in detail:
                    entry["limit"] = "dependency conflict in the subject (kit 2.x vs pinned 1.x)"
            if built["built"]:
                # #665: the declared tests are read off the stub files that BUILT, so a predicate
                # stub's reach test can be told apart from its law and every test that reported
                # nothing can be named. Read again after a hang's culprits are set aside.
                declared = declared_tests(dirs[0])
                ran = s5.run_serially(package_dir, swift, reach_tests=_reach_tests(declared))
                record_outcomes(entry, ran, dirs[0], declared)
                if ran.get("no_verdict"):
                    # **Name the law that hangs, then measure the rest.** A repo-level "no
                    # verdict" says nothing about 18 innocent stubs; bisecting turns it into a
                    # finding about one law and lets the others report.
                    bisect_stats = {}
                    culprits = s5.bisect_hang(package_dir, dirs[0], swift,
                                              os.path.join(scratch, f"hang-{repo}"),
                                              stats=bisect_stats)
                    if culprits:
                        entry["hangs"] = culprits
                        for name in culprits:
                            built["set_aside"][name] = "test process hangs before reporting"
                        entry["compiled"] = max(0, entry["compiled"] - len(culprits))
                        declared = declared_tests(dirs[0])
                        hung_seconds = ran["run_seconds"]
                        ran = s5.run_serially(package_dir, swift,
                                              reach_tests=_reach_tests(declared))
                        # Two runs, two clocks: the timed-out one is most of the package's wall
                        # time, so it is kept. Every other column is the re-run's.
                        ran["run_seconds"] = hung_seconds + ran["run_seconds"]
                    # ⚠ **Read the counts back off the RE-RUN.** They were taken above from
                    # the hung run, and setting the culprit aside is pointless if the entry
                    # still reports what the hang produced — measured on
                    # SwiftFormatRuleStudio, that is the difference between 0 passes and 13.
                    record_outcomes(entry, ran, dirs[0], declared, bisect_stats)
                if ran.get("no_verdict"):
                    # Not "0 passed": the run produced no verdict at all, so these stubs are
                    # unmeasured rather than failing. Kept out of the pass column deliberately.
                    entry["no_verdict"] = ran["no_verdict"]
                    entry["passed"] = None
                    entry["passed_behaviour"] = None
                    entry["passed_does_not_crash"] = None
                    entry["failed"] = None
                # fef2971d assigned these two last, so they move back to the end: a result file
                # keeps every legacy key in fef2971d's order, with #665's keys between them.
                for key in ("hung_tests", "failures"):
                    entry[key] = entry.pop(key)
        except subprocess.TimeoutExpired:
            entry["blocked"] = "timeout"
        per_package.append(entry)

    result["packages"] = per_package
    result["stubs"] = stub_total
    # `or 0` rather than a default: a no-verdict package carries `None`, which means UNMEASURED
    # and must not be summed as a zero — that is the distinction the whole classification exists
    # for, and defaulting would put it straight back.
    result["compiled"] = sum(p.get("compiled") or 0 for p in per_package)
    result["passed"] = sum(p.get("passed") or 0 for p in per_package)
    result["passed_behaviour"] = sum(p.get("passed_behaviour") or 0 for p in per_package)
    result["passed_does_not_crash"] = sum(p.get("passed_does_not_crash") or 0 for p in per_package)
    result["failed"] = sum(p.get("failed") or 0 for p in per_package)
    result["crashed"] = sum(p.get("crashed") or 0 for p in per_package)
    result["hung"] = sum(p.get("hung") or 0 for p in per_package)
    result["no_verdict_stubs"] = sum(p["stubs"] for p in per_package if p.get("no_verdict"))
    # **A compiled stub must land in exactly one outcome, and for two runs it did not.**
    # `compiled - (passed + failed + crashed + hung)` read 29 corpus-wide on both, and nothing
    # printed it: a reader subtracting passed and failed from compiled found 29 stubs missing and
    # no column to put them in. 23 were CRASHES, which are a third outcome and were simply never
    # summed here; the remaining 6 were a `consumer-producer` stub that is documentation only
    # and declares no test at all, and 5 pbt-book tests the resume loop's bare-name `--skip`
    # never ran (fixed in `_skip_pattern`; first misread as a shared `Suite.test` key).
    #
    # Recorded per repository rather than asserted, because a legitimate third outcome must not
    # end a 50-minute run. It is the seventh number in this harness put there so that a figure
    # that cannot be true cannot also be invisible.
    result["unaccounted"] = _unaccounted(per_package)
    result.update(_reach_totals(per_package))
    result["finished"] = time.strftime("%H:%M:%S")
    return result


def _reach_totals(per_package):
    """#665's repository-level columns, each summed over the packages that produced a verdict.

    Every legacy column above is untouched, `unaccounted` (stub FILES) included; `unaccounted_tests`
    is its per-TEST sibling, which a stub declaring no test at all (`consumer-producer`) cannot move.
    """
    measured = [p for p in per_package if not p.get("no_verdict")]

    def reach(package, key, default):
        return (package.get("reach") or {}).get(key, default)

    def side(package, which):
        return sum(1 for sides in reach(package, "not_applied", {}).values() if which in sides)

    return {
        "unaccounted_tests": sum(p.get("unaccounted_tests") or 0 for p in measured),
        "reach_expected": sum(reach(p, "expected", 0) for p in measured),
        "reach_green": sum(len(reach(p, "green", [])) for p in measured),
        "reach_not_applied_true": sum(side(p, "true") for p in measured),
        "reach_not_applied_false": sum(side(p, "false") for p in measured),
        "reach_other": sum(len(reach(p, "other", [])) for p in measured),
        "reach_crashed": sum(len(reach(p, "crashed", [])) for p in measured),
        "reach_hung": sum(len(reach(p, "hung", [])) for p in measured),
        "reach_skipped_after_law": sum(len(reach(p, "skipped_after_law", [])) for p in measured),
        "reach_unaccounted": sum(len(reach(p, "unaccounted", [])) for p in measured),
        "run_seconds_total": round(sum(sum(p.get("run_seconds") or []) for p in measured), 1),
    }


def summary_line(repo, result):
    """The one line `main` prints per repository. The reach part appears only when a stub declared a
    reach test, so a run without them (every census before #665, and its arm A) prints what it did."""
    reach = ""
    if result.get("reach_expected"):
        reach = (f" reach {result.get('reach_green', 0)}/{result['reach_expected']} (not applied "
                 f"{result.get('reach_not_applied_true', 0) + result.get('reach_not_applied_false', 0)})")
    return (f"{repo}: seeds {result.get('seeds','?')} named {result.get('named','?')} "
            f"stubs {result.get('stubs','?')} compiled {result.get('compiled','?')} "
            f"passed {result.get('passed','?')} (behaviour {result.get('passed_behaviour','?')}, "
            f"does not crash {result.get('passed_does_not_crash','?')}) crashed {result.get('crashed','?')} "
            f"unaccounted {result.get('unaccounted','?')}{reach} {result.get('error','')}")


def census_helpers(listing, scratch):
    """The pids, in a `ps -axo pid=,command=` listing, of the `swiftpm-testing-helper`s running a test
    bundle inside this census's trees.

    ⚠ **This sweep was `pkill -f swiftpm-testing-helper`, which killed every helper on the machine** —
    a `swift test` in another checkout or another session died mid-run with no failure printed, and a
    measurement run beside the funnel read a kill as a trap (#665). A helper's command line names its
    bundle, `--test-bundle-path <package>/.build/…`, so the ones this census started are the ones
    under its `trees/`. Both spellings of the scratch path are matched, as given and resolved
    (`/tmp` is `/private/tmp`), because SwiftPM may print either.
    """
    roots = {os.path.join(path, "trees") + os.sep
             for path in (os.path.abspath(scratch), os.path.realpath(scratch))}
    pids = []
    for line in listing.splitlines():
        pid, _, command = line.strip().partition(" ")
        if "swiftpm-testing-helper" in command and any(root in command for root in roots):
            pids.append(pid)
    return pids


def main(argv):
    if "--self-test" in argv[1:]:
        return self_test()
    scratch, infer, cli = argv[1], argv[2], argv[3]
    repos = argv[4:]
    os.makedirs(scratch, exist_ok=True)
    for repo in repos:
        out = os.path.join(scratch, f"result-{repo}.json")
        if os.path.exists(out):
            print(f"{repo}: already done, skipping", flush=True)
            continue
        repo_path = os.path.abspath(os.path.join("..", repo))
        print(f"{repo}: starting ({time.strftime('%H:%M:%S')})", flush=True)
        try:
            result = walk_repo(repo, repo_path, scratch, infer, cli)
        except Exception as error:  # noqa: BLE001 - one repo must not end the run
            result = {"repo": repo, "error": f"{type(error).__name__}: {str(error)[:400]}"}
        # **Sweep SwiftPM's orphaned helpers between repositories.** `swiftpm-testing-helper`
        # outlives its parent and keeps the inherited pipe open, which is what blocks the next
        # `capture_output` call forever — observed alive at 25 minutes after its run was killed.
        # Only this census's own helpers: see `census_helpers`.
        listing = subprocess.run(["ps", "-axo", "pid=,command="], capture_output=True,
                                 text=True).stdout
        for pid in census_helpers(listing, scratch):
            subprocess.run(["kill", pid], check=False, capture_output=True)
        json.dump(result, open(out, "w"), indent=2)
        print(summary_line(repo, result), flush=True)
    return 0


# ---------------------------------------------------------------------------------------------
# self-test — `record_outcomes` against the assignments it replaced, with no compiler.
# `make measurement-selftest` runs it.
# ---------------------------------------------------------------------------------------------

_SELFTEST_STUBS = {
    "predicate/XPredicateTests.swift": (
        "// Template: predicate\nimport Testing\n\nstruct XPredicateTests {\n"
        + "".join(f"    @Test func {s}_isTotal() {{}}\n\n    @Test func {s}_reachesBothOutcomes() {{}}\n"
                  for s in "abcd") + "}\n"),
    "round-trip/YRoundTripTests.swift": (
        "import Testing\n\nstruct YRoundTripTests {\n    @Test(\"y round trip\") func y_roundTrip() {}\n}\n"),
    # documentation only, like a `consumer-producer` stub: a file, but no test
    "consumer-producer/WConsumerProducerTests.swift": "struct WConsumerProducerTests {\n}\n",
}


def _pre_patch(entry, ran, stubs_dir):
    """The five assignments `walk_repo` made before #665, copied verbatim (`record_passes`, the three
    `len()`s, `hung_tests` and `failures`)."""
    record_passes(entry, ran, stubs_dir)
    entry["failed"] = len(ran["failed"])
    entry["crashed"] = len(ran["crashed"])
    entry["hung"] = len(ran.get("hung", []))
    entry["hung_tests"] = ran.get("hung", [])[:5]
    entry["failures"] = ran["failed"]


def _selftest_shapes():
    """One synthetic `ran` per shape, with what its reach bucket must read and, for E and W, the
    `passed_does_not_crash` the pre-patch reading would have inflated by."""
    def x(name):
        return f"XPredicateTests.{name}()"

    def law(s):
        return x(f"{s}_isTotal")

    def reach(s):
        return x(f"{s}_reachesBothOutcomes")

    y = "YRoundTripTests.y_roundTrip()"
    tail = {"warned": [], "sides": {}, "resumes": 0, "exhausted": False,
            "reach_skipped_after_law": [], "run_seconds": [1.5]}
    empty = {"expected": 4, "green": [], "not_applied": {}, "other": [], "crashed": [], "hung": [],
             "skipped_after_law": [], "unaccounted": []}
    return {
        # Arm A: no reach test was emitted, so nothing may differ from the pre-patch reading.
        "arm A": (dict(tail, passed=[law("a"), law("b"), law("c"), y], failed=[],
                       crashed=[law("d")], hung=[], resumes=1, run_seconds=[2.0, 3.5]),
                  dict(empty, expected=0), None, 0),
        # E: a not-applied reach test FAILS. a is green; b names true; d names false; c fails
        # without naming a side (an emitter defect until shown otherwise). Inflation g = 1.
        "E": (dict(tail, passed=[law(s) for s in "abcd"] + [reach("a"), y],
                   failed=[reach("b"), reach("c"), reach("d")], crashed=[], hung=[],
                   sides={reach("b"): ["true"], reach("d"): ["false"]}),
              dict(empty, green=[reach("a")], not_applied={reach("b"): ["true"], reach("d"): ["false"]},
                   other=[reach("c")]), 1, 0),
        # W: a not-applied reach test PASSES with a warning. a and d green; b true; c false; and
        # a LAW that warned, which `warned_tests` keeps. Inflation g + t + f = 2 + 1 + 1.
        "W": (dict(tail, passed=[law(s) for s in "abcd"] + [reach(s) for s in "abcd"] + [y],
                   failed=[], crashed=[], hung=[],
                   warned=[reach("b"), reach("c"), law("a")],
                   sides={reach("b"): ["true"], reach("c"): ["false"]}),
              dict(empty, green=[reach("a"), reach("d")],
                   not_applied={reach("b"): ["true"], reach("c"): ["false"]}), 4, 0),
        # A law that crashed takes its twin with it (C27): the twin is accounted for, not lost.
        "law crash, twin skipped": (
            dict(tail, passed=[law(s) for s in "acd"] + [reach(s) for s in "acd"] + [y], failed=[],
                 crashed=[law("b")], hung=[], resumes=1, reach_skipped_after_law=[reach("b")]),
            dict(empty, green=[reach(s) for s in "acd"], skipped_after_law=[reach("b")]), None, 0),
        # A reach test that crashes or hangs beside a passing law moves no law column.
        "reach crash beside a passing law": (
            dict(tail, passed=[law(s) for s in "abcd"] + [reach("b"), reach("d"), y], failed=[],
                 crashed=[reach("a")], hung=[reach("c")], resumes=2),
            dict(empty, green=[reach("b"), reach("d")], crashed=[reach("a")], hung=[reach("c")]),
            None, 0),
        # No verdict: nothing reported, so every declared test is unaccounted for in this package.
        "no_verdict": (dict(tail, passed=[], failed=[], crashed=[], hung=[], run_seconds=[600.0],
                            no_verdict="test run timed out before any test reported"),
                       dict(empty, unaccounted=[reach(s) for s in "abcd"]), None, 9),
    }


def _walk_stubs(reach):
    """One package's stub files: two predicate suites (each with its reach twin when `reach`), a
    round trip, a law whose `@Test` sits on its own line, and a `consumer-producer` file with no test."""
    def suite(name, *tests):
        return (f"import Testing\n@testable import M\n\nstruct {name} {{\n"
                + "".join(f"    @Test func {test}() {{}}\n" for test in tests) + "}\n")

    def predicate(stem):
        return [f"{stem}_isTotal"] + ([f"{stem}_reachesBothOutcomes"] if reach else [])

    return {
        "predicate/APredicateTests.swift": suite("APredicateTests", *predicate("a")),
        "predicate/EPredicateTests.swift": suite("EPredicateTests", *predicate("e")),
        "round-trip/BRoundTripTests.swift": suite("BRoundTripTests", "b_roundTrip"),
        "idempotence/DIdempotenceTests.swift": ("import Testing\n@testable import M\n\n"
                                                "struct DIdempotenceTests {\n    @Test\n"
                                                "    func d_idempotent() {}\n}\n"),
        "consumer-producer/CConsumerProducerTests.swift": "@testable import M\n\nstruct CConsumerProducerTests {\n}\n",
    }


def _walk_scenarios():
    """name → (reach twins emitted, scripted `swift test` runs, the suite bisection must name).

    A run is `(output, exit code)`, the code `None` for a hang. Each arm-A shape has its fef2971d
    reading in `_WALK_FEF2971D`; the arm-B one is checked by hand in `_selftest_walk_repo`."""
    def ran(suite, test, side=None):
        lines = [f"◇ Suite {suite} started.", f"◇ Test {test}() started."]
        if side:
            lines += [f"⚠︎ Test {test}() recorded a warning at X.swift:1:1: Issue recorded",
                      f"↳ NOT APPLIED — the {side} side: no draw made f(_:) return {side} in 100 trials"]
        return lines + [f"✔ Test {test}() passed after 0.001 seconds{' with 1 warning' if side else ''}."]

    def failed(suite, test):
        return [f"◇ Suite {suite} started.", f"◇ Test {test}() started.",
                f"✘ Test {test}() recorded an issue at X.swift:1:1: Expectation failed",
                f"✘ Test {test}() failed after 0.001 seconds with 1 issue."]

    def traps(suite, test):
        return [f"◇ Suite {suite} started.", f"◇ Test {test}() started.", "Fatal error: Index out of range"]

    def out(*groups):
        return "".join(line + "\n" for group in groups for line in group)

    a, b, d, e = (("APredicateTests", "a_isTotal"), ("BRoundTripTests", "b_roundTrip"),
                  ("DIdempotenceTests", "d_idempotent"), ("EPredicateTests", "e_isTotal"))
    twin = ("APredicateTests", "a_reachesBothOutcomes")
    hang = ("Building for debugging...\n", None)
    return {
        "crash, then resume": (False, [(out(ran(*a), traps(*b)), 1),
                                       (out(ran(*a), ran(*d), failed(*e)), 1)], None),
        "no verdict, culprit set aside": (False, [hang, (out(ran(*a), failed(*b), traps(*e)), 1),
                                                  (out(ran(*a), failed(*b)), 1)], "DIdempotenceTests"),
        "no verdict, no culprit": (False, [hang], None),
        "no verdict, the re-run hangs too": (False, [hang, hang], "DIdempotenceTests"),
        "arm B: no verdict, culprit, a law traps in the re-run": (
            True, [hang, (out(ran(*a), ran(*twin, "false"), ran(*b), traps(*e)), 1),
                   (out(ran(*a), ran(*twin, "false"), ran(*b)), 0)], "DIdempotenceTests"),
    }


def _drive_walk(funnel, reach, runs, culprit):
    """`funnel.walk_repo` over one package: every stage before 5 stubbed, `swift test` scripted,
    and bisection's probe answering whether `culprit` is skipped.

    It takes the module so it can drive fef2971d's `walk_repo` too, which is how `_WALK_FEF2971D`
    was taken. Returns `(result, commands, runs left)`; each command ends in its `timeout=`.
    """
    import tempfile
    stage5, runs, commands = funnel.s5, list(runs), []

    def scripted(command, **kwargs):
        if list(command[1:3]) != ["test", "--no-parallel"]:
            raise AssertionError(f"unscripted command {command}")
        commands.append(list(command) + [f"timeout={kwargs.get('timeout')}"])
        output, code = runs.pop(0)
        if code is None:
            raise subprocess.TimeoutExpired(command, kwargs.get("timeout"),
                                            output=output.encode("utf-8"), stderr=b"")
        return subprocess.CompletedProcess(command, code, stdout=output, stderr="")

    with tempfile.TemporaryDirectory() as scratch:
        tree = os.path.join(scratch, "trees", "Repo")
        package = os.path.join(tree, "pkg")
        stubs = os.path.join(package, "Tests", "Generated", "SwiftInfer")
        for relative, text in _walk_stubs(reach).items():
            os.makedirs(os.path.join(stubs, os.path.dirname(relative)), exist_ok=True)
            open(os.path.join(stubs, relative), "w", encoding="utf-8").write(text)
        doubles = [
            (funnel, "toolchain", lambda _repo: "swift"),
            (funnel, "worktree", lambda _path, _destination: tree),
            (funnel, "link_path_dependencies", lambda *_args: []),
            # a seed outside every target, so no `index` or `discover` runs
            (funnel, "seeds", lambda *_args: {"seeds": 3, "named": 2, "rows": [{"file": "elsewhere.swift"}]}),
            (funnel, "packages", lambda _tree: [package]),
            (funnel, "regular_targets", lambda *_args: [("M", os.path.join(package, "Sources", "M"), "regular")]),
            (funnel, "external_dependencies", lambda *_args: []),
            (funnel, "laws_proposed", lambda *_args: {"any": 1, "refutable": 1}),
            (stage5, "rewrite_manifest", lambda *_args, **_kwargs: None),
            (stage5, "verify_manifest", lambda *_args, **_kwargs: None),
            # a fresh dict per call, because `walk_repo` adds a hang's culprits to it
            (stage5, "build_to_fixpoint",
             lambda *_args, **_kwargs: {"built": True, "set_aside": {"ZGoneTests": "error: x"}}),
            (stage5, "_runs_within", lambda _p, _s, _t, skip=None: bool(culprit) and culprit in (skip or [])),
            (subprocess, "run", scripted),
        ]
        saved = [(owner, name, getattr(owner, name)) for owner, name, _double in doubles]
        try:
            for owner, name, double in doubles:
                setattr(owner, name, double)
            result = funnel.walk_repo("Repo", os.path.join(scratch, "Repo"), scratch, "infer", "cli")
        finally:
            for owner, name, original in saved:
                setattr(owner, name, original)
    for key in ("started", "finished"):
        result.pop(key, None)
    return result, commands, len(runs)


# ⚠ **What fef2971d's `walk_repo` wrote for each arm-A shape — taken from fef2971d, not from this
# walk.** `git show fef2971d:scripts/corpus_funnel.py` and its stage 5 were imported, and
# `_walk_stubs`, `_walk_scenarios` and `_drive_walk` were lifted out of this file by name and
# exec'd beside them, so the walk under replay was fef2971d's and only the scaffolding is new.
# `started` and `finished` are dropped. The patched walk must reproduce every key here, value AND
# order; the keys #665 added may sit between them. Regenerate the same way, never from this walk.
_WALK_FEF2971D = {
    "crash, then resume": {
        "commands": [
            ["swift", "test", "--no-parallel", "timeout=600"],
            ["swift", "test", "--no-parallel", "--skip", "\\.BRoundTripTests/b_roundTrip\\(\\)", "timeout=600"]],
        "result": {
            "repo": "Repo", "toolchain": "", "linked_siblings": [], "seeds": 3, "named": 2,
            "scanned_targets": [], "any_law": 1, "refutable_law": 1,
            "packages": [{
                "package": "pkg", "stubs": 5, "with_import": 5, "built": True,
                "set_aside": {"ZGoneTests": "error: x"}, "compiled": 4, "passed": 2,
                "passed_by_template": {"predicate": 1, "idempotence": 1}, "passed_does_not_crash": 1,
                "passed_behaviour": 1, "failed": 1, "crashed": 1, "hung": 0, "hung_tests": [],
                "failures": ["EPredicateTests.e_isTotal()"]}],
            "stubs": 5, "compiled": 4, "passed": 2, "passed_behaviour": 1, "passed_does_not_crash": 1,
            "failed": 1, "crashed": 1, "hung": 0, "no_verdict_stubs": 0, "unaccounted": 0}},
    "no verdict, culprit set aside": {
        "commands": [
            ["swift", "test", "--no-parallel", "timeout=600"],
            ["swift", "test", "--no-parallel", "timeout=600"],
            ["swift", "test", "--no-parallel", "--skip", "\\.EPredicateTests/e_isTotal\\(\\)", "timeout=600"]],
        "result": {
            "repo": "Repo", "toolchain": "", "linked_siblings": [], "seeds": 3, "named": 2,
            "scanned_targets": [], "any_law": 1, "refutable_law": 1,
            "packages": [{
                "package": "pkg", "stubs": 5, "with_import": 5, "built": True,
                "set_aside": {"ZGoneTests": "error: x", "DIdempotenceTests": "test process hangs before reporting"},
                "compiled": 3, "passed": 1, "passed_by_template": {"predicate": 1},
                "passed_does_not_crash": 1, "passed_behaviour": 0, "failed": 1, "crashed": 1, "hung": 0,
                "hangs": ["DIdempotenceTests"], "hung_tests": [],
                "failures": ["BRoundTripTests.b_roundTrip()"]}],
            "stubs": 5, "compiled": 3, "passed": 1, "passed_behaviour": 0, "passed_does_not_crash": 1,
            "failed": 1, "crashed": 1, "hung": 0, "no_verdict_stubs": 0, "unaccounted": 0}},
    "no verdict, no culprit": {
        "commands": [
            ["swift", "test", "--no-parallel", "timeout=600"]],
        "result": {
            "repo": "Repo", "toolchain": "", "linked_siblings": [], "seeds": 3, "named": 2,
            "scanned_targets": [], "any_law": 1, "refutable_law": 1,
            "packages": [{
                "package": "pkg", "stubs": 5, "with_import": 5, "built": True,
                "set_aside": {"ZGoneTests": "error: x"}, "compiled": 4, "passed": None,
                "passed_by_template": {}, "passed_does_not_crash": None, "passed_behaviour": None,
                "failed": None, "crashed": 0, "hung": 0,
                "no_verdict": "test run timed out before any test reported", "hung_tests": [],
                "failures": []}],
            "stubs": 5, "compiled": 4, "passed": 0, "passed_behaviour": 0, "passed_does_not_crash": 0,
            "failed": 0, "crashed": 0, "hung": 0, "no_verdict_stubs": 5, "unaccounted": 0}},
    "no verdict, the re-run hangs too": {
        "commands": [
            ["swift", "test", "--no-parallel", "timeout=600"],
            ["swift", "test", "--no-parallel", "timeout=600"]],
        "result": {
            "repo": "Repo", "toolchain": "", "linked_siblings": [], "seeds": 3, "named": 2,
            "scanned_targets": [], "any_law": 1, "refutable_law": 1,
            "packages": [{
                "package": "pkg", "stubs": 5, "with_import": 5, "built": True,
                "set_aside": {"ZGoneTests": "error: x", "DIdempotenceTests": "test process hangs before reporting"},
                "compiled": 3, "passed": None, "passed_by_template": {}, "passed_does_not_crash": None,
                "passed_behaviour": None, "failed": None, "crashed": 0, "hung": 0,
                "hangs": ["DIdempotenceTests"], "no_verdict": "test run timed out before any test reported",
                "hung_tests": [], "failures": []}],
            "stubs": 5, "compiled": 3, "passed": 0, "passed_behaviour": 0, "passed_does_not_crash": 0,
            "failed": 0, "crashed": 0, "hung": 0, "no_verdict_stubs": 5, "unaccounted": 0}},
}


def _legacy_view(new, old):
    """`new`'s items for `old`'s keys, in `new`'s order: equal to `old.items()` only when every
    legacy key kept its value and its place."""
    return [(key, value) for key, value in new.items() if key in old]


def _selftest_walk_repo(check):
    """`walk_repo`'s wiring: the re-run after a hang is read, the override comes after it, the
    budgets reach `swift test`, and an arm-B re-run still skips a trapping law's twin."""
    walked = {}
    for name, (reach, runs, culprit) in _walk_scenarios().items():
        try:
            result, commands, left = _drive_walk(sys.modules[__name__], reach, runs, culprit)
        except Exception as error:  # a walk that raises is a failed check, not a traceback
            check(f"walk_repo, {name}", False, repr(error))
            continue
        walked[name] = result, commands
        check(f"walk_repo, {name}: every scripted run was used", left == 0, f"{left} left")
        entry = result["packages"][0]
        want = _WALK_FEF2971D.get(name)
        if want is not None:
            old_entry = want["result"]["packages"][0]
            old_repository = {k: v for k, v in want["result"].items() if k != "packages"}
            check(f"walk_repo, {name}: fef2971d's commands and timeouts", commands == want["commands"],
                  f"{commands} != {want['commands']}")
            check(f"walk_repo, {name}: fef2971d's package entry, value and order",
                  _legacy_view(entry, old_entry) == list(old_entry.items()),
                  f"{_legacy_view(entry, old_entry)} != {list(old_entry.items())}")
            check(f"walk_repo, {name}: fef2971d's repository columns, value and order",
                  _legacy_view({k: v for k, v in result.items() if k != "packages"}, old_repository)
                  == list(old_repository.items()), str(result))
            check(f"walk_repo, {name}: no reach column moves", result["reach_expected"] == 0
                  and entry.get("reach", {}).get("expected", 0) == 0, str(entry.get("reach")))
        if culprit:
            # Both runs' clocks are kept: the timed-out one, then the re-run's own.
            check(f"walk_repo, {name}: bisection recorded, every run timed",
                  entry.get("bisect", {}).get("probes", 0) > 0 and len(entry["run_seconds"]) == len(runs),
                  str(entry))
    # Arm B, by hand: the re-run's law trap takes its twin out with it; the twin that warned is
    # NOT APPLIED; the culprit's tests are gone from what was declared.
    name = "arm B: no verdict, culprit, a law traps in the re-run"
    if name not in walked:
        return len(walked)
    result, commands = walked[name]
    entry = result["packages"][0]
    law, twin = "EPredicateTests.e_isTotal()", "EPredicateTests.e_reachesBothOutcomes()"
    check(f"walk_repo, {name}: the twin is skipped with its law",
          commands[2] == ["swift", "test", "--no-parallel", "--skip", s5._skip_pattern(law),
                          "--skip", s5._skip_pattern(twin), "timeout=600"], str(commands))
    check(f"walk_repo, {name}: law columns",
          (entry["compiled"], entry["passed"], entry["passed_does_not_crash"], entry["passed_behaviour"],
           entry["crashed"], entry["failures"], entry["hangs"])
          == (3, 2, 1, 1, 1, [], ["DIdempotenceTests"]), str(entry))
    check(f"walk_repo, {name}: reach bucket", entry["reach"] == {
        "expected": 2, "green": [], "not_applied": {"APredicateTests.a_reachesBothOutcomes()": ["false"]},
        "other": [], "crashed": [], "hung": [], "skipped_after_law": [twin], "unaccounted": []},
          str(entry["reach"]))
    check(f"walk_repo, {name}: repository reach columns",
          (result["reach_expected"], result["reach_not_applied_false"], result["reach_skipped_after_law"],
           result["unaccounted_tests"]) == (2, 1, 1, 0), str(result))
    return len(walked)


def self_test():
    import tempfile
    failures = []

    def check(name, condition, detail):
        if not condition:
            failures.append(f"{name}: {detail}")

    with tempfile.TemporaryDirectory() as stubs:
        for relative, text in _SELFTEST_STUBS.items():
            os.makedirs(os.path.join(stubs, os.path.dirname(relative)), exist_ok=True)
            open(os.path.join(stubs, relative), "w", encoding="utf-8").write(text)
        declared = declared_tests(stubs)
        check("declared_tests reads every @Test, the attributed one included",
              sorted(declared) == sorted([f"XPredicateTests.{s}_{t}()" for s in "abcd"
                                          for t in ("isTotal", "reachesBothOutcomes")]
                                         + ["YRoundTripTests.y_roundTrip()"]), str(sorted(declared)))
        entries = {}
        for shape, (ran, want_reach, inflation, unaccounted) in _selftest_shapes().items():
            shape_declared = [n for n in declared if not s5.is_reach(n)] if shape == "arm A" else declared
            entry = {}
            record_outcomes(entry, ran, stubs, shape_declared)
            entries[shape] = entry
            # Legacy fields: exactly the pre-patch assignments over `ran` with every reach name removed.
            law_only = {k: ([n for n in v if not s5.is_reach(n)] if k in _OUTCOMES else v)
                        for k, v in ran.items()}
            before = {}
            _pre_patch(before, law_only, stubs)
            check(f"{shape}: legacy fields", {k: entry[k] for k in before} == before,
                  f"{ {k: entry[k] for k in before} } != {before}")
            check(f"{shape}: reach bucket", entry["reach"] == want_reach,
                  f"{entry['reach']} != {want_reach}")
            check(f"{shape}: unaccounted tests", entry["unaccounted_tests"] == unaccounted,
                  str(entry["unaccounted_test_names"]))
            check(f"{shape}: law-only lists", not any(s5.is_reach(n) for key in
                  ("passed_tests", "crashed_tests", "hung_tests_all", "failures", "warned_tests")
                                                     for n in entry[key]), str(entry))
            unfiltered = {}
            _pre_patch(unfiltered, ran, stubs)
            if inflation is None:
                check(f"{shape}: the unfiltered reading inflates nothing it reads as a pass",
                      unfiltered["passed"] - entry["passed"] == len([n for n in ran["passed"]
                                                                    if s5.is_reach(n)]), "")
            else:
                # The regression the bucket exists for: a reach pass filed as a does-not-crash law.
                check(f"{shape}: unfiltered pre-patch passed_does_not_crash is +{inflation}",
                      unfiltered["passed_does_not_crash"] - entry["passed_does_not_crash"] == inflation,
                      f"{unfiltered['passed_does_not_crash']} - {entry['passed_does_not_crash']}")
        check("arm A: identical to the pre-patch reading of the unfiltered ran",
              entries["arm A"]["passed_by_template"] == {"predicate": 3, "round-trip": 1}
              and entries["arm A"]["crashed"] == 1, str(entries["arm A"]))
        check("W: a warned law stays in warned_tests", entries["W"]["warned_tests"]
              == ["XPredicateTests.a_isTotal()"], str(entries["W"]["warned_tests"]))
        entries["no_verdict"]["no_verdict"] = "test run timed out before any test reported"
        totals = _reach_totals(list(entries.values()))
        check("repository sums skip the no-verdict package", totals == {
            "unaccounted_tests": 0, "reach_expected": 16, "reach_green": 8,
            "reach_not_applied_true": 2, "reach_not_applied_false": 2, "reach_other": 1,
            "reach_crashed": 1, "reach_hung": 1, "reach_skipped_after_law": 1, "reach_unaccounted": 0,
            "run_seconds_total": 11.5}, str(totals))
        legacy = {"seeds": 3, "named": 2, "stubs": 9, "compiled": 9, "passed": 5,
                  "passed_behaviour": 1, "passed_does_not_crash": 4, "crashed": 0, "unaccounted": 0}
        check("summary line: unchanged without reach tests",
              summary_line("R", dict(legacy, reach_expected=0)) ==
              "R: seeds 3 named 2 stubs 9 compiled 9 passed 5 (behaviour 1, does not crash 4) "
              "crashed 0 unaccounted 0 ", summary_line("R", legacy))
        check("summary line: reach appended when expected",
              summary_line("R", dict(legacy, **totals)).endswith(
                  "unaccounted 0 reach 8/16 (not applied 4) "), summary_line("R", dict(legacy, **totals)))
    helper = "/tc/usr/libexec/swift/pm/swiftpm-testing-helper --test-bundle-path"
    listing = "\n".join([
        f"  101 {helper} /private/tmp/census/trees/Repo/.build/out/Products/Debug/RepoTests.xctest",
        f"  102 {helper} /Users/me/OtherCheckout/.build/out/Products/Debug/OtherTests.xctest",
        "  103 /tc/usr/bin/swift-build --package-path /private/tmp/census/trees/Repo",
        f"  104 {helper} /private/tmp/census/trees-old/Repo/.build/out/Products/Debug/RepoTests.xctest",
    ])
    check("census_helpers kills only a helper inside this census's trees",
          census_helpers(listing, "/private/tmp/census") == ["101"],
          str(census_helpers(listing, "/private/tmp/census")))
    walks = _selftest_walk_repo(check)
    for failure in failures:
        print("FAIL", failure)
    if failures:
        print(f"{len(failures)} self-test failure(s)")
        return 1
    print(f"corpus_funnel.py self-test OK  ({len(_selftest_shapes())} outcome shapes against the "
          f"pre-patch assignments, reach sums, summary line; {walks} walk_repo runs, "
          f"{len(_WALK_FEF2971D)} against fef2971d's)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
