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
        # ⚠ **A trailing comment can share the line with the code.** Skipping only whole comment
        # LINES left `),// UI tests are configured in Xcode` reading as significant, so the last
        # character was `e` and a second comma went in after the `),`. SwiftProjectLint's 434
        # stubs were blocked on exactly that.
        code = line.split("//")[0] if "//" in line else line
        stripped = code.strip()
        if not stripped:
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


def rewrite_manifest(manifest_path, modules, census_target, stubs_relative_path, external=()):
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

    # 1b. **Dependency lines no remaining target uses are dropped.**
    #
    # The census records this as an adjustment: *"a swift-property-based 1.x pin used only by
    # test targets was dropped with those targets"*. Removing the test targets without removing
    # what only they referenced leaves the pin in the graph, so SwiftPM sees the subject
    # demanding 1.2.x while the stubs demand the kit's 2.x and refuses to resolve — which then
    # reads as a subject-side conflict rather than as a leftover. It blocked pbt-book (134
    # stubs), SwiftLintRuleStudio (41) and SwiftUMLStudio (43).
    #
    # Only URL dependencies are pruned, and only when no surviving target names the package.
    # 1a. **An existing SwiftPropertyLaws dependency below the pin is UPGRADED, not skipped.**
    #
    # The census records this adjustment: *"an existing SwiftPropertyLaws dependency
    # (SwiftLintRuleStudioCore pins 3.x) was replaced by HEAD — the stubs are v4 code"*. The
    # duplicate guard skipped it instead, so the subject kept 3.x while the stubs needed 4.x and
    # SwiftPM refused: `root depends on 'swift-property-based' 2.0.0..<3.0.0 and root depends on
    # 'swiftpropertylaws' 3.28.0..<4.0.0`. It blocked SwiftProjectLint's 434 stubs, and the same
    # shape blocked SwiftLintRuleStudio and SwiftUMLStudio.
    #
    # Rewritten in place, so the dependency keeps its position and the array stays well formed.
    while True:
        existing = re.search(r'\.package\s*\(\s*url:\s*"[^"]*SwiftPropertyLaws[^"]*"', text)
        if not existing:
            break
        open_paren = text.index("(", existing.start())
        close = _matching_paren(text, open_paren)
        clause = text[existing.start():close + 1]
        if '"4.7.0"' in clause:
            break
        text = text[:existing.start()] + KIT_DEPENDENCY + text[close + 1:]

    # ⚠ **Only the conflicting engine pin is dropped, not every unreferenced dependency.**
    #
    # The census's adjustment is specific: *"a swift-property-based 1.x pin used only by test
    # targets was dropped with those targets"*. A general "prune what no surviving target
    # references" rule was tried first and REGRESSED three manifests that had just parsed --
    # it is too blunt, because a dependency can be referenced in ways this text scan does not
    # model. The narrow rule cannot corrupt a manifest it does not match.
    #
    # Left standing where a LIBRARY target uses it: that is the subject-side conflict the
    # census recorded and declined to work around, and it must stay visible as such.
    for match in list(re.finditer(r'\.package\s*\(\s*url:\s*"[^"]*swift-property-based[^"]*"',
                                  text)):
        open_paren = text.index("(", match.start())
        close = _matching_paren(text, open_paren)
        clause = text[match.start():close + 1]
        if '"2.' in clause or "2.0.0" in clause:
            continue
        tail = close + 1
        while tail < len(text) and text[tail] in " \n\t":
            tail += 1
        if tail < len(text) and text[tail] == ",":
            tail += 1
        head = match.start()
        while head > 0 and text[head - 1] in " \n\t":
            head -= 1
        text = text[:head] + text[tail:]
        break

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
    # ⚠ **A dependency can already be present as a PATH, not a URL.** pbt-book declares
    # `.package(path: "../../SwiftPropertyLaws")`, so checking only URLs added the kit a second
    # time under the same identity and SwiftPM reported `swiftpropertylaws` as *unresolved* —
    # naming the package it could not resolve rather than the duplicate that caused it.
    by_path = {os.path.basename(match.rstrip("/")).lower()
               for match in re.findall(r'\.package\s*\(\s*path:\s*"([^"]+)"', text)}
    wanted = []
    for line in (KIT_DEPENDENCY, ENGINE_DEPENDENCY):
        url = re.search(r'url:\s*"([^"]+)"', line).group(1)
        if url in text:
            continue
        identity = url.rstrip("/").split("/")[-1]
        if identity.endswith(".git"):
            identity = identity[:-4]
        if identity.lower() in by_path:
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
                    + "".join(f'                {entry},\n' for entry in external)
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
    # ⚠ **Every SwiftPM call gets a timeout.** `capture_output` waits for EOF on the pipe, and
    # SwiftPM spawns helpers that inherit it — so a build whose child has already exited can
    # leave the parent blocked forever with no CPU and no children. The driver sat 25 minutes
    # that way on one repository; it is the most plausible reading of the census's 2h29m loop.
    done = subprocess.run([swift, "package", "dump-package"], cwd=package_dir,
                          capture_output=True, text=True, env=env, timeout=300)
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
    try:
        done = subprocess.run([swift, "build", "--build-tests"], cwd=package_dir,
                              capture_output=True, text=True, env=env, timeout=1800)
    except subprocess.TimeoutExpired:
        return False
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


# The header the accept path writes on a stub whose subject no test can name
# (`InteractiveTriage+AccessCaveat.swift`).
ACCESS_HEADER = "// Access: no test can name the subject"
PRIVATE_PREFIX = "private subject; compiler said: "


def attributed_reason(path, message):
    """The set-aside reason, naming `private` when the stub's own header already does.

    ⚠ **The compiler's first error is not the cause for a private subject.** It reports a name it
    cannot see, or gives up type-checking after trying every overload, instead of saying
    *inaccessible*. Census 14 recorded 16 stubs as access failures while 164 carried this
    header — 18 of 19 type-check timeouts and 53 of 84 *cannot find in scope* among them
    (`docs/measurements/cannot-find-in-scope-decomposition.md`). The compiler's text is kept
    after the prefix, so nothing it said is lost.
    """
    try:
        with open(path, encoding="utf-8") as stub:
            head = stub.read(4096)
    except OSError:
        return message
    return PRIVATE_PREFIX + message if ACCESS_HEADER in head else message


_ERROR = re.compile(r"^(/[^:]+\.swift):(\d+):(\d+): error: (.+)$")


def build_to_fixpoint(package_dir, stubs_dir, swift, aside_dir, max_rounds=40):
    """Build, set aside every stub with an error, repeat until it builds or nothing moves."""
    os.makedirs(aside_dir, exist_ok=True)
    set_aside = {}
    for round_number in range(max_rounds):
        env = dict(os.environ)
        env["PATH"] = os.path.dirname(swift) + os.pathsep + env.get("PATH", "")
        try:
            done = subprocess.run([swift, "build", "--build-tests"], cwd=package_dir,
                                  capture_output=True, text=True, env=env, timeout=1800)
        except subprocess.TimeoutExpired:
            return {"built": False, "rounds": round_number, "set_aside": set_aside,
                    "unattributed": "build timed out after 1800s"}
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
            set_aside[os.path.basename(path)] = attributed_reason(path, message)
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


def _runs_within(package_dir, swift, seconds, skip=None):
    """Does the test target RUN to completion inside `seconds`?

    ⚠ **Build first, then time only the run.** Removing a stub forces a recompile, and on a
    package with a heavy dependency graph that rebuild alone outlasts the probe's budget — so
    every bisection attempt timed out during the BUILD and the search concluded that no single
    stub was responsible. The build gets its own generous bound; the hang is measured against
    the run.
    """
    env = dict(os.environ)
    env["PATH"] = os.path.dirname(swift) + os.pathsep + env.get("PATH", "")
    try:
        built = subprocess.run([swift, "build", "--build-tests"], cwd=package_dir,
                               capture_output=True, text=True, env=env, timeout=1800)
    except subprocess.TimeoutExpired:
        return False
    if built.returncode != 0:
        return True  # not a hang: a build failure is the set-aside loop's business, not ours
    try:
        command = [swift, "test", "--no-parallel"]
        for name in (skip or []):
            command += ["--skip", re.escape(name)]
        subprocess.run(command, cwd=package_dir, capture_output=True, text=True,
                       env=env, timeout=seconds)
    except subprocess.TimeoutExpired:
        return False
    return True


def _suite_names(stubs_dir):
    """The generated suite names, read from the stub files themselves."""
    names = []
    for path in _swift_files(stubs_dir):
        try:
            text = open(path, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        names.extend(re.findall(r"^(?:final )?(?:public )?struct (\w+)\s*\{", text, re.M))
    return sorted(set(names))


def bisect_hang(package_dir, stubs_dir, swift, aside_dir, seconds=150, limit=40):
    """Name the suites whose presence stops the test process reporting at all.

    ⚠ **Skip suites, do not remove files.** The first version moved stub files aside, which
    forces a recompile and can break the build when a surviving stub references a removed one —
    and `_runs_within` treats a build failure as "not a hang", so the search concluded the hang
    was gone and named no culprit. Skipping needs no rebuild and cannot break the build, so
    every probe measures the thing it is supposed to measure.

    ⚠ **And it MINIMIZES, it does not bisect.** A plain bisection asks which half holds *a*
    culprit and throws the other half away; with two hanging suites that discards one of them
    and reports a single name while the run still hangs. Exercised against a fake oracle over
    every 0/1/2/3-culprit combination of six suites, the bisecting version mis-attributed all
    35 of the multi-culprit cases. This narrows by halves only while a half is *sufficient on
    its own*, then removes one candidate at a time and keeps it only when its removal brings
    the hang back — so what is returned is minimal, not merely sufficient.

    Returns the suite names that had to be skipped for the run to finish, and moves their files
    to `aside_dir` so the caller's counts stay consistent.
    """
    os.makedirs(aside_dir, exist_ok=True)
    suites = _suite_names(stubs_dir)
    if not suites:
        return []
    probes = [0]

    def runs(skip):
        probes[0] += 1
        return _runs_within(package_dir, swift, seconds, skip=skip)

    if runs([]):
        return []
    if not runs(suites):
        return []  # hangs even with every generated suite skipped: not ours to attribute

    # Narrow by halves, but only while one half is sufficient BY ITSELF.
    while len(suites) > 1 and probes[0] < limit:
        first, second = suites[: len(suites) // 2], suites[len(suites) // 2:]
        if runs(first):
            suites = first
        elif runs(second):
            suites = second
        else:
            break  # culprits straddle the split; halving would drop one

    # Minimize: drop a candidate and keep it only if the hang comes back.
    for name in list(suites):
        if probes[0] >= limit:
            break
        trial = [n for n in suites if n != name]
        if trial and runs(trial):
            suites = trial

    for name in suites:
        # Match the DECLARATION, not a mention: a stub that merely names another suite in a
        # comment would otherwise be set aside in place of the one that hangs.
        pattern = re.compile(r"^(?:final )?(?:public )?struct " + re.escape(name) + r"\s*\{", re.M)
        for path in _swift_files(stubs_dir):
            if pattern.search(open(path, encoding="utf-8", errors="ignore").read()):
                os.replace(path, os.path.join(aside_dir, os.path.basename(path)))
                break
    return suites


def _skip_pattern(name):
    """A `--skip` regex matching exactly the test `Suite.test()`, never its namesakes.

    ⚠ **Skipping by the bare test name skipped every suite's test of that name.** A resume after
    a crash passed `--skip combine_isCommutative`, and Swift Testing matched it against every ID —
    `…Mod8_combine_commutativityTests/combine_isCommutative()` and the four other suites declaring
    the same test — so those four never ran and were counted nowhere. That was 5 of the 22
    September census's 6 *unaccounted* stubs, all in pbt-book, which has 21 crashes to resume past.
    A test ID reads `Module.Suite/test()`, so the pattern anchors on the dot before the suite:
    `Sum_…` must not match `CheckSum_…`.
    """
    suite, _, test = name.rpartition(".")
    if not suite or suite == "None":
        return re.escape(test)
    return r"\." + re.escape(suite) + "/" + re.escape(test)


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
    skipped, results, crashed, hung = [], {}, [], []
    for _ in range(max_resumes):
        # **No `--filter`.** Stage 5 drops every other test target, so the census target is the
        # only one left — and `--filter` matches a test ID, not a target name, so passing the
        # target here matched nothing and reported an empty run as a clean one.
        command = [swift, "test", "--no-parallel"]
        for name in skipped:
            command += ["--skip", _skip_pattern(name)]
        env = dict(os.environ)
        env["PATH"] = os.path.dirname(swift) + os.pathsep + env.get("PATH", "")
        timed_out = False
        try:
            # ⚠ **600s, not 1800s.** A generated law is cheap — the pilot ran 15 of them in
            # 0.03s — so minutes of test time means one law is looping, not working. The census
            # recorded a chapter hanging for 677s.
            done = subprocess.run(command, cwd=package_dir, capture_output=True, text=True,
                                  env=env, timeout=600)
            output = done.stdout + done.stderr
            code = done.returncode
        except subprocess.TimeoutExpired as expired:
            # ⚠ **A HANG is recovered exactly like a crash, and it was not.** Returning here
            # discarded every result the run had already produced: SwiftFormatRuleStudio read
            # 15 compiled and 0 passed because one looping law ended the process, not because
            # its laws failed. The partial output names which test never finished, so it is set
            # aside and the rest are re-run — the same rule the census states for a crash.
            # ⚠ **`TimeoutExpired.stdout` is BYTES even under `text=True`** — a documented
            # quirk, and concatenating it to a str raised `TypeError` inside the recovery path,
            # so the repository reported no counts at all rather than partial ones.
            def _text(stream):
                if stream is None:
                    return ""
                return stream.decode("utf-8", "replace") if isinstance(stream, bytes) else stream

            output = _text(expired.stdout) + _text(expired.stderr)
            code, timed_out = None, True
        

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
        if timed_out and unfinished:
            victim = unfinished[-1]
            hung.append(victim)
            skipped.append(victim)
            continue
        if timed_out and not started:
            # ⚠ **The process hung before ANY test reported**, so there is no name to attribute
            # it to and nothing to skip. SwiftFormatRuleStudio does this: 15 stubs compile and
            # the run never gets as far as printing a first test. Returning zeros here would
            # read as "15 laws, none pass", which is a claim about the laws; this says the run
            # never produced a verdict, which is a claim about the run.
            return {"passed": [], "failed": [], "crashed": crashed, "hung": hung,
                    "no_verdict": "test run timed out before any test reported"}
        if not unfinished:
            passed = sorted(k for k, v in results.items() if v == "passed")
            failed = sorted(k for k, v in results.items() if v == "failed")
            return {"passed": passed, "failed": failed, "crashed": crashed,
                    "hung": hung, "returncode": code}
        victim = unfinished[-1]
        crashed.append(victim)
        skipped.append(victim)
    passed = sorted(k for k, v in results.items() if v == "passed")
    failed = sorted(k for k, v in results.items() if v == "failed")
    return {"passed": passed, "failed": failed, "crashed": crashed, "hung": hung,
            "exhausted": True}
