#!/usr/bin/env python3
"""Stage 5 of the corpus funnel walk: make the emitted stubs build, then run them.

Per the pipeline in `docs/measurements/corpus-funnel-census-2026-09-14.md` §Pipeline:
existing test targets dropped, one census test target per scanned module depending on the
module + PropertyLawKit + PropertyBased, `swift build --build-tests`, every stub carrying an
error set aside with its FIRST error, repeated to a fixpoint, survivors run serially.

**Committed, unlike the three harnesses before it.** The 14 and 16 September drivers lived in
session scratchpads, so this is the third rebuild of the same thing and the first that can be
re-run or audited.

Three guards, each for a defect the 16 September census recorded:

- **The rewritten manifest is verified with `dump-package` before anything is built.** One of
  its eight defects was an unbalanced-paren manifest rewrite; a rewrite that cannot be parsed
  must fail loudly here rather than surface later as "the package does not build".
- **The set-aside loop stops when a round removes nothing.** One run burned 2h29m in an
  infinite loop.
- **Dependency lines come from the tool's own `VerifierWorkdir+KitPin`**, not from memory, so
  the census cannot drift from what the verifier itself declares.
"""
import json
import os
import re
import subprocess
import sys

# Mirrors VerifierWorkdir.swiftPropertyLawsRequirement / swiftPropertyBasedRequirement. Both
# are declared DIRECTLY, deliberately: resolution must not lean on the kit's own dep graph.
KIT_DEPENDENCY = ('.package(url: "https://github.com/Joseph-Cursio/SwiftPropertyLaws.git", '
                  'from: "4.7.0")')
ENGINE_DEPENDENCY = ('.package(url: "https://github.com/x-sheep/swift-property-based.git", '
                     'from: "2.0.0")')


def _matching_paren(text, open_index):
    """Index of the `)` closing the `(` at `open_index`, ignoring parens inside strings."""
    depth, index, in_string = 0, open_index, False
    while index < len(text):
        char = text[index]
        if char == '"' and text[index - 1] != "\\":
            in_string = not in_string
        elif not in_string:
            if char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
                if depth == 0:
                    return index
        index += 1
    raise ValueError("unbalanced parentheses in manifest")


def _last_significant(text):
    """The last character that is neither whitespace nor part of a trailing `//` comment.

    ⚠ **`rstrip()` is not enough, and the difference parses as a syntax error.** A target array
    routinely ends with explanatory comments after its final element, so the last non-space
    character is comment PROSE while the last element already ends `),`. Adding a comma on that
    evidence produced `), // …\n , .testTarget(` on four packages. Whole-line `//` comments are
    skipped; a `//` inside a string literal cannot appear at end of line here.
    """
    for line in reversed(text.splitlines()):
        stripped = line.strip()
        if not stripped or stripped.startswith("//"):
            continue
        return stripped[-1]
    return ""


def _package_level_label(text, label, want_start=False):
    """Index just past `label:` **at the Package call's own nesting depth**.

    ⚠ **Matching the first occurrence is wrong and it parses.** `.library(name: …, targets:
    ["Foo"])` puts a `targets:` before the package's own, and a target's `dependencies:` does
    the same — so a first-match splice put the census target inside a product and produced
    `type 'String' has no member 'testTarget'`. The `dump-package` guard caught it; this makes
    it not happen. Third manifest-surgery defect, all three caught by that guard.
    """
    call = re.search(r"Package\s*\(", text)
    if not call:
        raise ValueError("no Package( call")
    start = call.end()
    depth, index = 0, start
    end = _matching_paren(text, call.end() - 1)
    while index < end:
        char = text[index]
        if char in "([":
            depth += 1
        elif char in ")]":
            depth -= 1
        elif depth == 0 and text.startswith(label + ":", index):
            bracket = text.find("[", index)
            if bracket < 0:
                raise ValueError(f"{label}: is not an array")
            return bracket + 1 if not want_start else index
        index += 1
    raise ValueError(f"no package-level {label}:")


def rewrite_manifest(manifest_path, modules, census_target, stubs_relative_path):
    """Drop every test target, add the two dependencies, add the census target."""
    text = open(manifest_path, encoding="utf-8").read()

    # 1. every `.testTarget(...)` block, paren-matched, with its trailing comma
    while True:
        match = re.search(r"\.testTarget\s*\(", text)
        if not match:
            break
        close = _matching_paren(text, match.end() - 1)
        tail = close + 1
        while tail < len(text) and text[tail] in " \n\t":
            tail += 1
        if tail < len(text) and text[tail] == ",":
            tail += 1
        head = match.start()
        while head > 0 and text[head - 1] in " \n\t":
            head -= 1
        text = text[:head] + text[tail:]

    # 2. the two dependencies, at the head of the package's `dependencies:` array
    # ⚠ **A dependency the manifest already declares must NOT be added again.** SwiftPM rejects
    # the package outright — `Conflicting identity for swift-property-based: dependency … and
    # dependency … both point to the same package identity` — and the failure is not
    # attributable to any stub, so it reads as "this package does not build" rather than as a
    # harness bug. The 16 September census recorded a duplicate dependency declaration among its
    # eight defects; this is the same one, found again by rebuilding.
    # ⚠ **A subject may BE one of the dependencies.** SwiftPropertyLaws is the kit, and adding a
    # URL dependency on SwiftPropertyLaws to its own manifest produced a graph that crashed the
    # compiler outright — exit 138, SIGBUS, with no error line, while the pristine repo builds in
    # 69s. The self-dependency is dropped and the census target uses the local product instead.
    own = re.search(r'Package\s*\(\s*\n?\s*name:\s*"([^"]+)"', text)
    own_name = own.group(1) if own else ""
    SELF = {"SwiftPropertyLaws": "PropertyLawKit", "swift-property-based": "PropertyBased"}
    local_products = [product for package, product in SELF.items() if package == own_name]
    wanted = []
    for line in (KIT_DEPENDENCY, ENGINE_DEPENDENCY):
        url = re.search(r'url:\s*"([^"]+)"', line).group(1)
        if url in text:
            continue
        if any(package in url for package in SELF if package == own_name):
            continue
        wanted.append(line)
    try:
        insert = _package_level_label(text, "dependencies")
    except ValueError:
        # **A package may declare no dependencies at all**, and three subjects do. Raising left
        # them recorded as unbuildable, which is a fact about this harness, not about them.
        #
        # ⚠ **Inserted straight after `Package(`, never before `targets:`.** Searching backwards
        # for `targets` landed inside a PRODUCT's `targets: ["LintStudioCore"]`, which is the
        # same first-match-is-the-wrong-one defect as the census-target splice. The head of the
        # argument list is unambiguous.
        # ⚠ **Inserted before the package-level `targets:`, not after `Package(`.** `Package`'s
        # initializer takes `name` first, so putting the array at the head of the argument list
        # produced `argument 'name' must precede argument 'dependencies'`. The signature order
        # is name, platforms, products, dependencies, targets — immediately before `targets:` is
        # the one slot that is always legal.
        head = _package_level_label(text, "targets", want_start=True)
        text = text[:head] + "dependencies: [],\n    " + text[head:]
        insert = _package_level_label(text, "dependencies")
    added = "".join(f"\n        {line}," for line in wanted)
    text = text[:insert] + added + text[insert:]

    # 3. the census target, before the closing `]` of `targets:`
    depth, index = 1, _package_level_label(text, "targets")
    while index < len(text) and depth:
        if text[index] == "[":
            depth += 1
        elif text[index] == "]":
            depth -= 1
        index += 1
    close = index - 1
    # **Whether a comma is needed is a question about the text, not a constant.** Removing the
    # test targets can leave a trailing comma behind, and assuming one either way produces
    # `), ,.testTarget(` or two targets with none between them. The first version of this
    # assumed, and `verify_manifest` caught it — which is what that guard is for.
    separator = "" if _last_significant(text[:close]) == "," else ","
    # ⚠ **Every source target, not the first one.** A package's stubs name subjects from all of
    # its modules -- SwiftIdempotency's macro target among them -- and depending on the first
    # alone set both of its stubs aside with `no such module 'SwiftIdempotencyMacros'`, which
    # reads as an emitter failure rather than a harness one.
    kit = ("" if "PropertyLawKit" in local_products else
           '                .product(name: "PropertyLawKit", package: "SwiftPropertyLaws"),\n')
    engine = ("" if "PropertyBased" in local_products else
              '                .product(name: "PropertyBased", package: "swift-property-based")\n')
    dependencies = ("".join(f'                "{name}",\n' for name in modules)
                    + "".join(f'                "{name}",\n' for name in local_products)
                    + kit + engine).rstrip(",\n") + "\n"
    block = (
        # ⚠ **The leading newline is load-bearing.** Without it the block continues whatever
        # line precedes the closing `]`, and after a test target is removed that line is often a
        # trailing `//` comment — so the whole census target was swallowed by the comment and
        # the manifest failed to parse on four packages. It worked on the pilot only because the
        # character before `]` happened to be `)`.
        f"\n       {separator} .testTarget(\n"
        f'            name: "{census_target}",\n'
        "            dependencies: [\n"
        f"{dependencies}"
        "            ],\n"
        f'            path: "{stubs_relative_path}"\n'
        "        )\n"
    )
    text = text[:close] + block + text[close:]
    open(manifest_path, "w", encoding="utf-8").write(text)


def verify_manifest(package_dir, swift):
    """`dump-package` must parse the rewrite. An unparseable manifest fails HERE, loudly."""
    env = dict(os.environ)
    env["PATH"] = os.path.dirname(swift) + os.pathsep + env.get("PATH", "")
    done = subprocess.run([swift, "package", "dump-package"], cwd=package_dir,
                          capture_output=True, text=True, env=env)
    if done.returncode != 0:
        raise SystemExit("REWRITTEN MANIFEST DOES NOT PARSE — refusing to build:\n"
                         + done.stderr[-2000:])
    return json.loads(done.stdout)


def _swift_files(directory):
    return sorted(os.path.join(r, f) for r, _s, fs in os.walk(directory)
                  for f in fs if f.endswith(".swift"))


def _builds(package_dir, swift):
    env = dict(os.environ)
    env["PATH"] = os.path.dirname(swift) + os.pathsep + env.get("PATH", "")
    done = subprocess.run([swift, "build", "--build-tests"], cwd=package_dir,
                          capture_output=True, text=True, env=env)
    return done.returncode == 0


def _bisect_crash(package_dir, stubs_dir, swift, aside_dir, code, limit=12):
    """Isolate the stub(s) whose presence crashes the compiler, by halving.

    Returns the basenames moved to `aside_dir`. Bounded by `limit` halvings so a crash that is
    not attributable to any single file cannot spin -- the 2h29m lesson, one level down.
    """
    os.makedirs(aside_dir, exist_ok=True)
    moved = []
    for _ in range(limit):
        present = _swift_files(stubs_dir)
        if not present:
            return moved
        half = present[: max(1, len(present) // 2)]
        parked = []
        for path in half:
            destination = os.path.join(aside_dir, os.path.basename(path))
            os.replace(path, destination)
            parked.append((path, destination))
        if _builds(package_dir, swift):
            # The crash is in the half just removed. Put back all but one and narrow.
            if len(parked) == 1:
                moved.append(os.path.basename(parked[0][0]))
                return moved
            for path, destination in parked[len(parked) // 2:]:
                os.replace(destination, path)
            continue
        # Still crashing without that half: the culprit is in what remains.
        for path, destination in parked:
            os.replace(destination, path)
        remaining = _swift_files(stubs_dir)
        if len(remaining) <= 1:
            return moved
    return moved


_ERROR = re.compile(r"^(/[^:]+\.swift):(\d+):(\d+): error: (.+)$")


def build_to_fixpoint(package_dir, stubs_dir, swift, aside_dir, max_rounds=40):
    """Build, set aside every stub with an error, repeat until it builds or nothing moves."""
    os.makedirs(aside_dir, exist_ok=True)
    set_aside = {}
    for round_number in range(max_rounds):
        env = dict(os.environ)
        env["PATH"] = os.path.dirname(swift) + os.pathsep + env.get("PATH", "")
        done = subprocess.run([swift, "build", "--build-tests"], cwd=package_dir,
                              capture_output=True, text=True, env=env)
        if done.returncode == 0:
            return {"built": True, "rounds": round_number, "set_aside": set_aside}
        first_error = {}
        for line in (done.stdout + done.stderr).splitlines():
            match = _ERROR.match(line.strip())
            if not match:
                continue
            path = os.path.realpath(match.group(1))
            if path.startswith(os.path.realpath(stubs_dir)) and path not in first_error:
                first_error[path] = match.group(4)
        if not first_error:
            # The failure is not attributable to a stub — a manifest or dependency problem.
            # ⚠ **Keep the ERROR lines, not the tail.** SwiftPM prints pages of
            # `Creating working copy for …` after the failure, so a trailing slice captured
            # resolution chatter and the real cause never reached the result file.
            errors = [line for line in (done.stdout + done.stderr).splitlines()
                      if "error:" in line]
            if errors:
                return {"built": False, "rounds": round_number, "set_aside": set_aside,
                        "unattributed": "\n".join(errors[:6])}
            # ⚠ **A build can fail with NO error line: the compiler crashed.** SwiftPropertyLaws
            # exits 138 — signal 10, SIGBUS — on a generated stub, which this repository already
            # records as a stack-depth trap. There is nothing to read, so the culprit is found by
            # bisection instead; without this the whole package reports unbuilt and its 45 stubs
            # read as a tool limitation rather than one file crashing a compiler.
            culprits = _bisect_crash(package_dir, stubs_dir, swift, aside_dir, done.returncode)
            if culprits:
                for name in culprits:
                    set_aside[name] = f"compiler crashed (exit {done.returncode})"
                continue
            return {"built": False, "rounds": round_number, "set_aside": set_aside,
                    "unattributed": f"build exited {done.returncode} with no error line"}
        for path, message in first_error.items():
            set_aside[os.path.basename(path)] = message
            os.replace(path, os.path.join(aside_dir, os.path.basename(path)))
    return {"built": False, "rounds": max_rounds, "set_aside": set_aside,
            "exhausted": True}


# ⚠ **Swift Testing prints these names UNQUOTED** — `Test foo() passed`, not `Test "foo" passed`.
# The first version of these matched the quoted form, found nothing, and reported 0 passed and
# 0 failed for a run that had just executed 15 tests. A zero that means *matched nothing* reads
# exactly like a zero that means *nothing ran*, which is this repository's most-repeated defect.
# ⚠ **The `\(\)` is load-bearing, not decoration.** Swift Testing's own banner reads
# `Test run started.` / `Test run with 15 tests … failed`, so a pattern matching any token
# captured a test called `run` that starts and never finishes — and the resume loop then
# attributed a crash to it on every round, thirty times, while reporting one real result short.
# A real test name always prints with its parentheses; the banner never does.
_STARTED = re.compile(r"Test\s+(\S+\(\))\s+started")
_PASSED = re.compile(r"Test\s+(\S+\(\))\s+passed")
_FAILED = re.compile(r"Test\s+(\S+\(\))\s+(?:failed|recorded an issue)")


def run_serially(package_dir, swift, census_target=None, max_resumes=30):
    """Run the surviving stubs one at a time, resuming past a crash.

    **A crash is attributed to the last test STARTED, and the run resumes past it.** A trapping
    law takes the whole process down, so without this one overflow ends the repository's run and
    every law behind it is reported as though it never ran — which reads as a tool limitation
    rather than one subject's arithmetic.

    ⚠ **Results are keyed on `Suite.test`, never the bare test name.** Two generated suites
    routinely declare the same test — `WikilinkParser_parse_input_totalityTests.parse_isTotal()`
    and `SearchService_parse_input_totalityTests.parse_isTotal()` both exist on the pilot — and
    keying on the bare name silently collapsed them, reporting 12 results for 13 lines. That is
    this repository's most-repeated defect, arriving in the instrument that measures it.
    """
    skipped, results, crashed = [], {}, []
    for _ in range(max_resumes):
        # **No `--filter`.** Stage 5 drops every other test target, so the census target is the
        # only one left — and `--filter` matches a test ID, not a target name, so passing the
        # target here matched nothing and reported an empty run as a clean one.
        command = [swift, "test", "--no-parallel"]
        for name in skipped:
            command += ["--skip", re.escape(name.split(".")[-1])]
        env = dict(os.environ)
        env["PATH"] = os.path.dirname(swift) + os.pathsep + env.get("PATH", "")
        done = subprocess.run(command, cwd=package_dir, capture_output=True, text=True, env=env)
        output = done.stdout + done.stderr

        suite, started = None, []
        for line in output.splitlines():
            suite_match = re.search(r"Suite\s+(\S+)\s+started", line)
            if suite_match:
                suite = suite_match.group(1)
                continue
            start_match = _STARTED.search(line)
            if start_match:
                started.append(f"{suite}.{start_match.group(1)}")
                continue
            pass_match = _PASSED.search(line)
            if pass_match:
                results[f"{suite}.{pass_match.group(1)}"] = "passed"
                continue
            fail_match = _FAILED.search(line)
            if fail_match:
                results[f"{suite}.{fail_match.group(1)}"] = "failed"

        unfinished = [name for name in started if name not in results]
        if not unfinished:
            passed = sorted(k for k, v in results.items() if v == "passed")
            failed = sorted(k for k, v in results.items() if v == "failed")
            return {"passed": passed, "failed": failed, "crashed": crashed,
                    "returncode": done.returncode}
        victim = unfinished[-1]
        crashed.append(victim)
        skipped.append(victim)
    passed = sorted(k for k, v in results.items() if v == "passed")
    failed = sorted(k for k, v in results.items() if v == "failed")
    return {"passed": passed, "failed": failed, "crashed": crashed, "exhausted": True}
