#!/usr/bin/env python3
"""Driver for the corpus funnel walk: stages 1-6 over every subject repository.

Pipeline per `docs/measurements/corpus-funnel-census-2026-09-14.md`. **Committed, unlike the
three harnesses before it** — the 14 and 16 September drivers lived in session scratchpads, so
each census rebuilt the thing that measures it and the second rebuild found eight defects.

Resumable by design: every repository writes its own JSON result and is skipped when that file
exists. One hang costs one repository, not the run -- the 16 September census lost 2h29m to an
infinite loop and discarded a 2,914-stub pass.
"""
import json
import os
import re
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
    if os.path.isdir(destination):
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
        if target.get("type") not in SOURCE_TARGET_TYPES:
            continue
        path = target.get("path") or f"Sources/{target['name']}"
        out.append((target["name"], os.path.join(package_dir, path)))
    return out


_IMPORT = re.compile(r"^@testable import ", re.M)


def import_rate(stub_dir):
    """Share of stubs carrying a `@testable import`. **A guard, not a statistic.**

    The census's worst defect read 0 of 70 here and was only caught because the number could
    not be true. A low rate means the module never resolved -- almost always the wrong `swift`
    first on PATH -- and every downstream count is then a fact about the harness.
    """
    stubs = [os.path.join(r, f) for r, _, fs in os.walk(stub_dir)
             for f in fs if f.endswith(".swift")]
    if not stubs:
        return (0, 0)
    with_import = sum(1 for p in stubs
                      if _IMPORT.search(open(p, encoding="utf-8", errors="ignore").read()))
    return (with_import, len(stubs))


def stub_dirs(package_dir):
    """Every `Generated/SwiftInfer` directory the accept path wrote into this package."""
    found = []
    for dirpath, dirs, _files in os.walk(package_dir):
        dirs[:] = [d for d in dirs if d not in (".build", ".git", "checkouts")]
        if os.path.basename(dirpath) == "SwiftInfer" and "Generated" in dirpath:
            found.append(dirpath)
    return found


def walk_repo(repo, repo_path, scratch, infer, cli, timeout=2400):
    """Stages 1-5 for one repository. Every failure is recorded, never raised."""
    swift = toolchain(repo)
    result = {"repo": repo, "toolchain": os.path.basename(os.path.dirname(swift)),
              "started": time.strftime("%H:%M:%S")}
    tree = worktree(repo_path, os.path.join(scratch, "trees", repo))
    result["linked_siblings"] = link_path_dependencies(
        tree, os.path.join(scratch, "trees"), os.path.dirname(repo_path))

    seeded = seeds(cli, tree, os.path.join(scratch, f"{repo}-seeds.json"))
    result.update(seeds=seeded["seeds"], named=seeded["named"])
    if not seeded.get("rows"):
        result["note"] = "no seeds"
        return result

    seed_files = {os.path.normpath(os.path.join(tree, s["file"])) for s in seeded["rows"]}

    scanned, stub_total = [], 0
    for package_dir in packages(tree):
        for name, directory in regular_targets(package_dir, swift):
            if not any(f.startswith(os.path.normpath(directory) + os.sep) for f in seed_files):
                continue
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
            scanned.append({"package": os.path.relpath(package_dir, tree),
                            "target": name, "exit": done.returncode})
    result["scanned_targets"] = scanned

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
                         if f.endswith(".swift")])
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
        modules = [t for t, _ in regular_targets(package_dir, swift)]
        if not modules:
            entry["blocked"] = "no regular target"
            per_package.append(entry)
            continue
        try:
            s5.rewrite_manifest(os.path.join(package_dir, "Package.swift"), modules,
                                "SwiftInferCensusTests",
                                os.path.relpath(dirs[0], package_dir))
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
                entry["unattributed"] = built.get("unattributed", "")[-400:]
            if built["built"]:
                ran = s5.run_serially(package_dir, swift)
                entry["passed"] = len(ran["passed"])
                entry["failed"] = len(ran["failed"])
                entry["crashed"] = len(ran["crashed"])
                entry["failures"] = ran["failed"]
        except subprocess.TimeoutExpired:
            entry["blocked"] = "timeout"
        per_package.append(entry)

    result["packages"] = per_package
    result["stubs"] = stub_total
    result["compiled"] = sum(p.get("compiled", 0) for p in per_package)
    result["passed"] = sum(p.get("passed", 0) for p in per_package)
    result["failed"] = sum(p.get("failed", 0) for p in per_package)
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
        json.dump(result, open(out, "w"), indent=2)
        print(f"{repo}: seeds {result.get('seeds','?')} named {result.get('named','?')} "
              f"stubs {result.get('stubs','?')} compiled {result.get('compiled','?')} "
              f"passed {result.get('passed','?')} {result.get('error','')}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
