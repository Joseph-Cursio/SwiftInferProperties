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
    "~/Library/Developer/Toolchains/swift-6.3.3-RELEASE.xctoolchain/usr/bin/swift")
XCODE = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"

# ⚠ **The toolchain is per REPOSITORY and it is not cosmetic.** SwiftMarkdownWiki needs Xcode's,
# because the swift.org one cannot see its SwiftUI cross-import overlay types; this project needs
# swift.org's, because Xcode's dies in the plugin stage. The 16 September census's worst defect
# was a toolchain mismatch that left 0 of 70 stubs carrying an import against 70 of 70 with the
# right one -- a whole pass discarded. Anything SwiftUI-shaped gets Xcode's.
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
    """
    env = dict(os.environ)
    env["PATH"] = os.path.dirname(swift) + os.pathsep + env.get("PATH", "")
    return env


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
SUPPORT_FILES = {"SwiftInferSyntaxCorpus.swift"}


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
                ran = s5.run_serially(package_dir, swift)
                record_passes(entry, ran, dirs[0])
                entry["failed"] = len(ran["failed"])
                entry["crashed"] = len(ran["crashed"])
                entry["hung"] = len(ran.get("hung", []))
                if ran.get("no_verdict"):
                    # **Name the law that hangs, then measure the rest.** A repo-level "no
                    # verdict" says nothing about 18 innocent stubs; bisecting turns it into a
                    # finding about one law and lets the others report.
                    culprits = s5.bisect_hang(package_dir, dirs[0], swift,
                                              os.path.join(scratch, f"hang-{repo}"))
                    if culprits:
                        entry["hangs"] = culprits
                        for name in culprits:
                            built["set_aside"][name] = "test process hangs before reporting"
                        entry["compiled"] = max(0, entry["compiled"] - len(culprits))
                        ran = s5.run_serially(package_dir, swift)
                        # ⚠ **Read the counts back off the RE-RUN.** They were taken above from
                        # the hung run, and setting the culprit aside is pointless if the entry
                        # still reports what the hang produced — measured on
                        # SwiftFormatRuleStudio, that is the difference between 0 passes and 13.
                        record_passes(entry, ran, dirs[0])
                        entry["failed"] = len(ran["failed"])
                        entry["crashed"] = len(ran["crashed"])
                        entry["hung"] = len(ran.get("hung", []))
                if ran.get("no_verdict"):
                    # Not "0 passed": the run produced no verdict at all, so these stubs are
                    # unmeasured rather than failing. Kept out of the pass column deliberately.
                    entry["no_verdict"] = ran["no_verdict"]
                    entry["passed"] = None
                    entry["passed_behaviour"] = None
                    entry["passed_does_not_crash"] = None
                    entry["failed"] = None
                entry["hung_tests"] = ran.get("hung", [])[:5]
                entry["failures"] = ran["failed"]
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
    result["finished"] = time.strftime("%H:%M:%S")
    return result


def main(argv):
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
        subprocess.run(["pkill", "-f", "swiftpm-testing-helper"], check=False,
                       capture_output=True)
        json.dump(result, open(out, "w"), indent=2)
        print(f"{repo}: seeds {result.get('seeds','?')} named {result.get('named','?')} "
              f"stubs {result.get('stubs','?')} compiled {result.get('compiled','?')} "
              f"passed {result.get('passed','?')} (behaviour {result.get('passed_behaviour','?')}, "
              f"does not crash {result.get('passed_does_not_crash','?')}) crashed {result.get('crashed','?')} "
              f"unaccounted {result.get('unaccounted','?')} {result.get('error','')}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
