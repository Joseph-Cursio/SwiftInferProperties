#!/usr/bin/env python3
r"""Measure how many reference-oracle scaffolds `swift-infer discover` prints actually COMPILE.

Usage:

  scripts/reference_oracle_scaffold_census.py --swift-infer BIN --subject REPO --target MODULE \
      --out DIR (--seeds FILE | --lint-cli BIN | --no-seeds) [--ref REF] [--label L]
      [--baseline-label L] [--sources DIR] [--swift SWIFT] [--jobs N] [--no-probes]
      [--no-compile] [--reclassify] [--bare-imports]

  BIN      a release `swift-infer` binary (`swift build -c release --product swift-infer`)
  REPO     the subject's git repository; it is only read, through `git worktree add`
  MODULE   the module `discover --target` scans, and that `@testable import` names
  DIR      the work directory: `subjects/<Name>` (a pristine worktree discover runs in),
           `build/<Name>` (a worktree whose manifest gains a census test target) and
           `runs/<label>-<Name>/` (summary.txt, results.json, the compiled files)
  --seeds  a pinned `pbt-seeds` manifest; `--lint-cli` makes one with SwiftProjectLint instead.
           With seeds, discover runs twice (seeded and unseeded); `--no-seeds` runs it once.

  The census in `docs/measurements/reference-oracle-scaffold-census.md` is, per subject, with the
  seed manifests pinned beside it in `fixtures/reference-oracle-scaffold-census/`:

    scripts/reference_oracle_scaffold_census.py --swift-infer .build/release/swift-infer \
        --subject <SwiftAssist> --ref a89e6e46d40e765e965544a0e96934ad6becd686 \
        --target SwiftAssist --seeds <fixtures>/SwiftAssist-seeds.json --out <DIR> --label after
    scripts/reference_oracle_scaffold_census.py --swift-infer .build/release/swift-infer \
        --subject <swift-format> --ref b15dd59fad --target SwiftFormat \
        --seeds <fixtures>/swift-format-seeds.json --out <DIR> --label after

  A before/after comparison needs the SAME seed manifest and the same --out: a run whose label is
  not --baseline-label (default `baseline`) checks its printed + declined count against that run's.
  The second run onwards reuses both worktrees and the census target's build.

What it does. `discover`'s docstring advisory prints, per documented function, either a runnable
reference-oracle scaffold (`DocstringAdvisoryRenderer`, built by `referenceOracleOutcome` in
`Sources/SwiftInferCLI/Discover+ReferenceOracle.swift`) or `── no runnable reference oracle:
<reason>`. This script:

  1. runs `swift-infer discover --target <T> --include-possible` in the pristine worktree, with
     and without `--seeds` (`.swiftinfer/` cleared before and after);
  2. extracts every scaffold, and every decline line with a category (`decline_category`);
  3. reads each subject function's declaration (static / instance / free, throws, async,
     global-actor isolation, access, generic parameters) from the source with a small Swift
     lexer, so a need the compiler cannot report (a `try` behind a call that does not resolve)
     is still counted;
  4. gives the build worktree a census test target, through the funnel's own
     `corpus_funnel_stage5.rewrite_manifest` + `verify_manifest` (every test target dropped,
     SwiftPropertyLaws + swift-property-based added) or, when that text surgery cannot parse the
     manifest (swift-format), by appending Swift that edits `package`, and builds it once with
     only a sentinel file;
  5. compiles EACH distinct scaffold alone with the exact `swiftc` arguments SwiftPM used for the
     census target (read off `swift build -v`), with `-emit-sil` so SIL diagnostics run too. The
     header is the accept path's stub imports (Foundation, Testing, PropertyBased,
     PropertyLawKit, `@testable import <Module>`) plus the declaring file's own imports, standing
     in for the accept path's carrier imports (`--bare-imports` drops those);
  6. builds the ones that compiled alone TOGETHER through SwiftPM (the funnel's fixpoint rule,
     batched so no two files declare the same `@Test` or `@unchecked Sendable` shim), so a
     "compiles" is a package build, not only a frontend run;
  7. attributes every compiler error to a cause and prints the histograms. Three counterfactual
     probes (mechanical call repair, generator hoisting, repair without try/await) say what a
     bare-call scaffold's first blocker hides. They are NOT what discover prints. Since the
     scaffold declares a member's reference in `extension Owner`, they are a regression check:
     such a scaffold is skipped, and a scaffold whose `call-repaired` probe compiles while the
     scaffold does not is reported as an emitter defect.

Why one file at a time: see the note above `census_compile_args`. In short, a census target
holding all scaffolds reported 4-7 files per round (the build stops at the first failed job, and
a declaration-level error anywhere stops body type-checking everywhere), so a fixpoint over 93
files measured 45 in twelve rounds.
"""
import argparse
import collections
import concurrent.futures
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time

XCODE_SWIFT = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
CENSUS_TARGET = "ScaffoldCensusTests"
CENSUS_DIR = "Tests/ScaffoldCensus"
SECTION = "Reference definitions from docstrings"
MARKER = "── runnable reference oracle (fill the stub, then run it) ──"
# Printed in place of the scaffold when none can compile (`DocstringAdvisoryRenderer`): one line,
# `── no runnable reference oracle: <reason>`.
DECLINE = "── no runnable reference oracle: "
TODO_GEN = "no generator derived"


def log(message):
    print(f"[{time.strftime('%H:%M:%S')}] {message}", file=sys.stderr, flush=True)


def env_for(swift):
    env = dict(os.environ)
    if "/" in swift:
        env["PATH"] = os.path.dirname(swift) + os.pathsep + env.get("PATH", "")
    return env


# ---------------------------------------------------------------------------------------------
# 1. worktrees + discover
# ---------------------------------------------------------------------------------------------

def resolve_ref(repo, ref):
    done = subprocess.run(["git", "-C", repo, "rev-parse", ref], capture_output=True, text=True)
    if done.returncode != 0:
        raise SystemExit(f"cannot resolve {ref} in {repo}: {done.stderr.strip()}")
    return done.stdout.strip()


def ensure_worktree(repo, destination, sha):
    """A detached worktree at `sha`. Re-created when it sits at another commit."""
    if os.path.isdir(destination):
        head = subprocess.run(["git", "-C", destination, "rev-parse", "HEAD"],
                              capture_output=True, text=True).stdout.strip()
        if head == sha:
            return destination, False
        subprocess.run(["git", "-C", repo, "worktree", "remove", "--force", destination],
                       check=True, capture_output=True)
    os.makedirs(os.path.dirname(destination), exist_ok=True)
    subprocess.run(["git", "-C", repo, "worktree", "add", "-q", "--detach", destination, sha],
                   check=True, capture_output=True)
    # A gitignored Package.resolved does not come with the worktree; copy the real one so the
    # build resolves what the subject resolves.
    real_resolved = os.path.join(repo, "Package.resolved")
    if os.path.exists(real_resolved) and not os.path.exists(os.path.join(destination, "Package.resolved")):
        shutil.copy(real_resolved, destination)
    return destination, True


def make_seeds(lint_cli, tree, out):
    done = subprocess.run([lint_cli, ".", "--format", "pbt-seeds"], cwd=tree,
                          capture_output=True, text=True, timeout=1200)
    open(out, "w", encoding="utf-8").write(done.stdout)
    rows = json.loads(done.stdout).get("seeds", [])
    return len(rows)


def run_discover(infer, tree, target, sources, seeds, out, swift):
    """`discover` in the pristine worktree. `.swiftinfer/` is cleared before and after, so a
    decision or cache from one run never shapes the next and nothing is left behind."""
    state = os.path.join(tree, ".swiftinfer")
    shutil.rmtree(state, ignore_errors=True)
    command = [infer, "discover", "--include-possible"]
    command += ["--sources", sources] if sources else ["--target", target]
    if seeds:
        command += ["--seeds", seeds]
    started = time.time()
    done = subprocess.run(command, cwd=tree, capture_output=True, text=True,
                          env=env_for(swift), timeout=3600)
    open(out, "w", encoding="utf-8").write(done.stdout)
    open(out + ".stderr", "w", encoding="utf-8").write(done.stderr)
    shutil.rmtree(state, ignore_errors=True)
    if done.returncode != 0:
        raise SystemExit(f"discover failed ({done.returncode}): {done.stderr[-1500:]}")
    return {"command": command, "seconds": round(time.time() - started, 1)}


# ---------------------------------------------------------------------------------------------
# 2. extraction
# ---------------------------------------------------------------------------------------------

_ITEM = re.compile(r"^  • (\S+\(.*?\))  (.*)$")
_LOCATION = re.compile(r"^    (/.+\.swift):(\d+)(?::(\d+))?$")
_FUNC_NAME = re.compile(r"^\s*(?:nonisolated )?(?:static )?func (\w+)_reference\(", re.M)
_EXTENSION_REFERENCE = re.compile(r"^extension (\S+) \{\n\s+(?:nonisolated )?(?:static )?func \w+_reference\(", re.M)
_TEST_NAME = re.compile(r"@Test func (\w+)\(")
_SHIM = re.compile(r"^extension (.+): @unchecked Sendable \{\}$", re.M)


def decline_category(reason):
    """The decline's cause, read off the reason `discover` printed.

    access    — the subject (or a type it names) cannot be reached from a test
    generic   — `GenericSubjectGate`: a type parameter, `some P`, or a generic owner; also a
                static member of a constrained extension of a generic standard-library type
    generator — no generator derives an argument or the receiver
    equatable — `UnequatableResultGate`: a scanned result type nothing makes Equatable
    plan      — everything else: what `SubjectCallPlan` declines (tuple shapes with no `==`,
                mutating, inout, closure parameter, no value, …), an initializer, an opaque or
                existential result, and a static member of a protocol extension"""
    if "cannot be called from a test" in reason:
        return "access"
    if ("generic parameter" in reason or "an opaque type" in reason or "generic type" in reason
            or "is a generic function" in reason):
        return "generic"
    if reason.startswith("no generator derives"):
        return "generator"
    if "no scanned declaration makes" in reason:
        return "equatable"
    return "plan"


def extract_scaffolds(text):
    """Every item of the 'Reference definitions from docstrings' section, with its scaffold.

    The renderer (`DocstringAdvisoryRenderer.render`) indents every scaffold line by four spaces,
    a blank scaffold line included, and separates items with an unindented blank line — so a
    scaffold is the run of 4-space lines after the marker."""
    lines = text.split("\n")
    try:
        start = next(i for i, line in enumerate(lines) if line.startswith(SECTION))
    except StopIteration:
        return {"section": False, "functions": 0, "items": []}
    header = re.search(r"\((\d+) function", lines[start])
    items, index = [], start + 1
    current = None
    while index < len(lines):
        line = lines[index]
        if line and not line.startswith(" "):
            break  # next top-level section
        item = _ITEM.match(line)
        if item:
            current = {"display": item.group(1), "signature": item.group(2), "scaffold": None}
            items.append(current)
            location = _LOCATION.match(lines[index + 1]) if index + 1 < len(lines) else None
            if location:
                current["file"], current["line"] = location.group(1), int(location.group(2))
            index += 1
            continue
        if current is not None and line.startswith("    " + DECLINE):
            current["declined"] = line[len("    " + DECLINE):]
            index += 1
            continue
        if current is not None and line.strip() == MARKER:
            body = []
            index += 1
            while index < len(lines) and lines[index].startswith("    "):
                body.append(lines[index][4:])
                index += 1
            while body and not body[-1].strip():
                body.pop()
            current["scaffold"] = "\n".join(body) + "\n"
            continue
        index += 1
    return {"section": True, "functions": int(header.group(1)) if header else len(items),
            "items": items}


# ---------------------------------------------------------------------------------------------
# 3. declaration facts, read from the subject's source
# ---------------------------------------------------------------------------------------------

def scan_blocks(text):
    """Every `{ … }` block at code level: (open_offset, close_offset, header_code_text).

    A small Swift lexer: skips `//` and nested `/* */` comments, normal / multi-line / raw string
    literals, and recurses into `\\( … )` interpolation. The header is the CODE text since the
    previous `{`, `}` or `;`, with comments dropped and string contents blanked."""
    blocks, stack = [], []
    header = []
    i, n = 0, len(text)
    # mode frames: ("code", paren_depth, is_interp) | ("str", hashes, multiline)
    frames = [["code", 0, False]]
    while i < n:
        frame = frames[-1]
        c = text[i]
        if frame[0] == "code":
            if text.startswith("//", i):
                j = text.find("\n", i)
                i = n if j < 0 else j
                continue
            if text.startswith("/*", i):
                depth, i = 1, i + 2
                while i < n and depth:
                    if text.startswith("/*", i):
                        depth, i = depth + 1, i + 2
                    elif text.startswith("*/", i):
                        depth, i = depth - 1, i + 2
                    else:
                        i += 1
                continue
            # Regex literals carry unbalanced `{`, `(` and `"` — `/\(.*\)(\s*\{)?/` — and
            # misreading one as code nests the rest of the file one block too deep.
            extended = re.match(r"(#+)/", text[i:i + 8])
            if extended:
                closing = "/" + extended.group(1)
                j = text.find(closing, i + len(extended.group(0)))
                i = n if j < 0 else j + len(closing)
                header.append("/re/")
                continue
            if c == "/" and not text.startswith("//", i) and not text.startswith("/*", i):
                previous = "".join(header).rstrip()
                if (not previous or previous[-1] in "(,=:[{;!&|?" or previous.endswith("return")) \
                        and i + 1 < n and text[i + 1] not in " =\n":
                    j, in_class = i + 1, False
                    while j < n and text[j] != "\n":
                        if text[j] == "\\":
                            j += 2
                            continue
                        if text[j] == "[":
                            in_class = True
                        elif text[j] == "]":
                            in_class = False
                        elif text[j] == "/" and not in_class:
                            break
                        j += 1
                    if j < n and text[j] == "/":
                        header.append("/re/")
                        i = j + 1
                        continue
            m = re.match(r'(#*)("""|")', text[i:i + 12])
            if m and (m.group(1) == "" or c == "#"):
                hashes, quote = len(m.group(1)), m.group(2)
                frames.append(["str", hashes, quote == '"""'])
                header.append('""')
                i += len(m.group(0))
                continue
            if c == "(":
                frame[1] += 1
            elif c == ")":
                if frame[2] and frame[1] == 0:
                    frames.pop()
                    i += 1
                    continue
                frame[1] -= 1
            elif c == "{":
                stack.append((i, "".join(header)))
                header = []
                i += 1
                continue
            elif c == "}":
                if stack:
                    opened, head = stack.pop()
                    blocks.append((opened, i, head))
                header = []
                i += 1
                continue
            elif c == ";":
                header = []
                i += 1
                continue
            header.append(c)
            i += 1
            continue
        # string frame
        hashes, multiline = frame[1], frame[2]
        if c == "\\" and text.startswith("#" * hashes, i + 1):
            after = i + 1 + hashes
            if after < n and text[after] == "(":
                frames.append(["code", 0, True])
                i = after + 1
                continue
            i = after + 1
            continue
        closing = ('"""' if multiline else '"') + "#" * hashes
        if text.startswith(closing, i):
            frames.pop()
            i += len(closing)
            continue
        if c == "\n" and not multiline:
            frames.pop()  # unterminated single-line string: recover
        i += 1
    return blocks


_TYPE_HEAD = re.compile(r"\b(struct|class|enum|actor|extension|protocol)\s+([A-Za-z_][\w.]*)")
_GLOBAL_ACTOR = re.compile(r"@(MainActor|\w+Actor)\b")


def line_offsets(text):
    offsets, total = [0], 0
    for line in text.split("\n"):
        total += len(line) + 1
        offsets.append(total)
    return offsets


def decl_facts(path, line_number, name, cache):
    """Static facts about the function the scaffold calls: what a correct call needs."""
    if path not in cache:
        try:
            text = open(path, encoding="utf-8").read()
        except OSError:
            cache[path] = None
        else:
            cache[path] = (text, scan_blocks(text), line_offsets(text))
    if cache[path] is None:
        return {"found": False, "why": "unreadable"}
    text, blocks, offsets = cache[path]
    start = offsets[line_number - 1] if line_number - 1 < len(offsets) else 0
    # The function's own block: the first block opening after the reported line whose header
    # declares `func <name>`. A reported line can point at an attribute above `func`.
    pattern = re.compile(r"\bfunc\s+" + re.escape(name) + r"\b")
    own = None
    for opened, closed, head in sorted(blocks):
        if opened < start:
            continue
        if pattern.search(head):
            own = (opened, closed, head)
        break
    if own is None:
        # Fall back to the declaration text itself (no body found, e.g. a requirement).
        stop = text.find("\n\n", start)
        head = text[start:stop if stop > 0 else start + 400]
        if not pattern.search(head):
            return {"found": False, "why": "no `func` at the reported line"}
        own = (start, start, head)
    opened, _closed, head = own
    func_at = pattern.search(head)
    before, after = head[:func_at.start()], head[func_at.end():]
    # The header runs from the previous `{`, `}` or `;`, so it can still hold earlier
    # brace-less declarations (`public static let floor = …` above a `public func`). Keep this
    # declaration's own line plus the attribute-only lines directly above it.
    before_lines = before.split("\n")
    own_lines = [before_lines[-1]]
    for line in reversed(before_lines[:-1]):
        if re.fullmatch(r"\s*(@\w+(\([^)]*\))?\s*)*", line) or re.fullmatch(
                r"\s*((public|internal|private|fileprivate|package|open|static|class|final|"
                r"nonisolated|mutating|override|@\w+(\([^)]*\))?)\s*)+", line):
            own_lines.insert(0, line)
        else:
            break
    before = "\n".join(own_lines)
    # parameter clause: skip generics, then match the parens
    depth, k, close = 0, 0, None
    while k < len(after):
        ch = after[k]
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                close = k
                break
        k += 1
    generic_names = []
    if after.lstrip().startswith("<"):
        depth, generic_text = 0, ""
        for ch in after.lstrip():
            depth += ch == "<"
            depth -= ch == ">"
            generic_text += ch
            if depth == 0:
                break
        generic_names = re.findall(r"(?:^<|,)\s*(\w+)", generic_text)
    parameter_text = after[:close + 1] if close is not None else ""
    effects = after[close + 1:] if close is not None else after
    effects = effects.split("->")[0] if "->" in effects else effects.split("where")[0]
    enclosing = [(o, c, h) for o, c, h in blocks if o < opened < c]
    enclosing.sort()  # outermost first
    types, nested_in_func, innermost = [], False, None
    for _o, _c, h in enclosing:
        t = _TYPE_HEAD.search(h)
        if t:
            types.append({"kind": t.group(1), "name": t.group(2)})
            innermost = (t.group(1), h[:t.start()])
            nested_in_func = False
        elif re.search(r"\b(func|init|var|get|set|didSet|willSet)\b", h):
            nested_in_func = True
    is_static = bool(re.search(r"\b(static|class)\s", before))
    # Isolation comes from the INNERMOST type only: a nested type does not inherit its parent's
    # global actor, and an actor's static members are not actor-isolated. An extension's members
    # inherit the extended type's global actor, which this header cannot see (the compiler can).
    isolated_by = None
    if innermost:
        kind, attributes = innermost
        actor = _GLOBAL_ACTOR.search(attributes)
        if actor:
            isolated_by = "@" + actor.group(1)
        elif kind == "actor" and not is_static:
            isolated_by = "actor"
    own_actor = _GLOBAL_ACTOR.search(before)
    if own_actor:
        isolated_by = "@" + own_actor.group(1)
    if re.search(r"\bnonisolated\b", before):
        isolated_by = None
    access = re.findall(r"\b(private|fileprivate|internal|public|open|package)\b", before)
    # The qualifying type path: extension names restart the path (they are already qualified).
    path_names = []
    for entry in types:
        if entry["kind"] == "extension":
            path_names = [entry["name"]]
        else:
            path_names.append(entry["name"])
    if not types:
        shape = "free-function" if not nested_in_func else "local-function"
    else:
        shape = "static-member" if is_static else "instance-method"
    return {
        "found": True,
        "shape": shape,
        "qualified_type": ".".join(path_names) or None,
        "type_kinds": [t["kind"] for t in types],
        "throws": bool(re.search(r"\b(throws|rethrows)\b", effects)),
        "async": bool(re.search(r"\basync\b", effects)),
        "mutating": bool(re.search(r"\bmutating\b", before)),
        "isolated_by": isolated_by,
        "access": access[0] if access else "internal",
        "generic_parameters": generic_names,
        "opaque_parameters": bool(re.search(r"\bsome\s", parameter_text)),
    }


# ---------------------------------------------------------------------------------------------
# 4. the census package
# ---------------------------------------------------------------------------------------------

def import_stage5():
    """The funnel's own manifest surgery, from the `scripts/` directory this file sits in."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import corpus_funnel_stage5 as stage5  # noqa: E402
    return stage5


def target_external_dependencies(package_dir, target, swift):
    """The scanned target's own dependencies on OTHER packages, as manifest entries — the funnel's
    `external_dependencies`, narrowed to one target so the census does not build the whole app."""
    done = subprocess.run([swift, "package", "dump-package"], cwd=package_dir,
                          capture_output=True, text=True, env=env_for(swift), timeout=600)
    dumped = json.loads(done.stdout)
    own = {t["name"] for t in dumped.get("targets", [])}
    entries = []
    for t in dumped.get("targets", []):
        if t["name"] != target:
            continue
        for dependency in t.get("dependencies", []):
            if "product" in dependency:
                name, package = dependency["product"][0], dependency["product"][1]
                entries.append(f'.product(name: "{name}", package: "{package}")')
            elif "byName" in dependency and dependency["byName"][0] not in own:
                entries.append(f'"{dependency["byName"][0]}"')
            elif "byName" in dependency:
                entries.append(f'"{dependency["byName"][0]}"')
    return [e for e in entries if '"PropertyLawKit"' not in e and '"PropertyBased"' not in e]


APPENDED_CENSUS = """

// ---- appended by measure-scaffolds.py (scaffold census) ----
package.dependencies += [
    {kit},
    {engine},
]
package.targets.removeAll {{ $0.type == .test }}
package.targets.append(
    .testTarget(
        name: "{census}",
        dependencies: [
{dependencies}
            .product(name: "PropertyLawKit", package: "SwiftPropertyLaws"),
            .product(name: "PropertyBased", package: "swift-property-based"),
        ],
        path: "{path}"
    )
)
"""


def append_census_target(manifest, target, external, stage5):
    """Fallback for a manifest the funnel's text surgery cannot parse (`dependencies:` held in a
    variable, targets built in a loop — swift-format): append Swift that edits `package` after it
    is built. Same dependency lines as the funnel (`stage5.KIT_DEPENDENCY` / `ENGINE_DEPENDENCY`)."""
    text = open(manifest, encoding="utf-8").read()
    dependencies = "".join(f"            {entry},\n" for entry in [f'"{target}"'] + list(external))
    text += APPENDED_CENSUS.format(kit=stage5.KIT_DEPENDENCY, engine=stage5.ENGINE_DEPENDENCY,
                                   census=CENSUS_TARGET, dependencies=dependencies, path=CENSUS_DIR)
    open(manifest, "w", encoding="utf-8").write(text)


def ensure_build_tree(repo, build_root, sha, target, swift, stage5):
    """A second worktree whose manifest carries the census test target.

    The funnel's `rewrite_manifest` first (drop every test target, add the kit + engine, add the
    census target), verified by its `verify_manifest`; when that cannot parse the manifest, the
    append fallback, verified the same way."""
    tree, fresh = ensure_worktree(repo, os.path.join(build_root, os.path.basename(repo)), sha)
    stamp = os.path.join(tree, ".scaffold-census-manifest")
    census = os.path.join(tree, CENSUS_DIR)
    if fresh or not os.path.exists(stamp):
        manifest = os.path.join(tree, "Package.swift")
        subprocess.run(["git", "-C", tree, "checkout", "--", "Package.swift"], check=True)
        external = target_external_dependencies(tree, target, swift)
        os.makedirs(census, exist_ok=True)
        open(os.path.join(census, "_Sentinel.swift"), "w").write("import Testing\n")
        how = "stage5.rewrite_manifest"
        try:
            stage5.rewrite_manifest(manifest, [target], CENSUS_TARGET, CENSUS_DIR, external)
            stage5.verify_manifest(tree, swift)
        except (SystemExit, ValueError) as error:
            log(f"stage5 manifest rewrite failed ({str(error)[:200]}); appending instead")
            subprocess.run(["git", "-C", tree, "checkout", "--", "Package.swift"], check=True)
            append_census_target(manifest, target, external, stage5)
            stage5.verify_manifest(tree, swift)
            how = "appended census target"
        open(stamp, "w").write(f"{sha} {target} {how}\n")
    return tree


FIXED_IMPORTS = ["import Foundation", "import Testing", "import PropertyBased", "import PropertyLawKit"]
_IMPORT_LINE = re.compile(
    r"^(?:@[\w]+(?:\([^)]*\))?\s+)*(?:(?:public|internal|package|private|fileprivate)\s+)?"
    r"import\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?([\w]+)")


def stub_header(module, subject_file, file_imports=True):
    """The accept path's fixed imports (`InteractiveTriage+StubFile.swift`) plus `@testable import
    <module>` — and, standing in for the accept path's carrier imports
    (`InteractiveTriage+ConstructionImports.swift`), the plain imports of the file that declares
    the subject, so a signature type from another module (`TokenSyntax`) is in scope the way the
    declaring file had it. Column-0 imports only; the subject module itself is skipped."""
    lines = list(FIXED_IMPORTS)
    if file_imports and subject_file and os.path.exists(subject_file):
        seen = {"Foundation", "Testing", "PropertyBased", "PropertyLawKit", module}
        for line in open(subject_file, encoding="utf-8", errors="ignore"):
            match = _IMPORT_LINE.match(line)
            if match and match.group(1) not in seen:
                seen.add(match.group(1))
                lines.append(f"import {match.group(1)}")
    lines.append(f"@testable import {module}")
    return "\n".join(lines) + "\n\n"


_ERROR = re.compile(r"^(/[^:]+\.swift):(\d+):(\d+): error: (.+)$")
_ANSI = re.compile(r"\x1b\[[0-9;]*m")


def build_once(tree, swift):
    started = time.time()
    try:
        # `--target` builds the census target and what it depends on, not the whole package (an
        # app, five executables). SwiftPM rejects `--target` together with `--build-tests`, and
        # does not need it: naming a test target builds it, with testability in debug.
        done = subprocess.run([swift, "build", "--target", CENSUS_TARGET],
                              cwd=tree, capture_output=True, text=True, env=env_for(swift),
                              timeout=3600)
    except subprocess.TimeoutExpired:
        return None, "timeout", time.time() - started
    # The new build system colours diagnostics even into a pipe; `path:line:col: error:` only
    # matches once the escapes are gone.
    output = _ANSI.sub("", done.stdout + done.stderr)
    return done.returncode, output, time.time() - started


def build_batch_to_fixpoint(tree, swift, files, max_rounds=40):
    """Write the batch, build, set aside every file with an error, repeat.

    Returns {file_id: [errors]} for files that failed, plus the ids that compiled."""
    census = os.path.join(tree, CENSUS_DIR)
    for entry in os.listdir(census):
        if entry.endswith(".swift") and entry != "_Sentinel.swift":
            os.remove(os.path.join(census, entry))
    present, header_lines = {}, {}
    for file_id, (header, scaffold) in files.items():
        path = os.path.join(census, f"{file_id}.swift")
        open(path, "w", encoding="utf-8").write(header + scaffold)
        present[os.path.realpath(path)] = file_id
        header_lines[file_id] = header.count("\n")
    failed, rounds = {}, []
    for round_number in range(max_rounds):
        code, output, seconds = build_once(tree, swift)
        rounds.append({"round": round_number, "exit": code, "seconds": round(seconds, 1),
                       "files": len(present)})
        log(f"    round {round_number}: exit {code} in {seconds:.0f}s with {len(present)} files")
        if code == 0:
            return {"failed": failed, "compiled": sorted(present.values()), "rounds": rounds}
        errors = collections.defaultdict(list)
        for line in output.splitlines():
            match = _ERROR.match(line.strip())
            if not match:
                continue
            path = os.path.realpath(match.group(1))
            if path not in present:
                continue
            record = {"line": int(match.group(2)) - header_lines[present[path]],
                      "col": int(match.group(3)),
                      "message": match.group(4)}
            if record not in errors[path]:
                errors[path].append(record)
        if not errors:
            unattributed = [l for l in output.splitlines() if "error:" in l][:8]
            return {"failed": failed, "compiled": [], "rounds": rounds,
                    "unattributed": unattributed or output[-3000:].splitlines()}
        for path, records in errors.items():
            file_id = present.pop(path)
            failed[file_id] = records
            os.remove(path)
    return {"failed": failed, "compiled": [], "rounds": rounds, "exhausted": True}


# ⚠ **Why each scaffold is compiled ALONE, with SwiftPM's own flags, and not as one target.**
#
# Measured on SwiftAssist 2026-10-04: one census target holding all 93 scaffolds, built to a
# fixpoint, set aside only 4-7 files a round — the build system stops at the first failed
# compile job (`-continue-building-after-errors` does not change it), and a declaration-level
# error in ANY file (`cannot find type 'Citation'` in a reference signature) stops the frontend
# before it type-checks a single body, even under `-wmo`. Twelve rounds measured 45 of 93. So the
# census target is built ONCE with only a sentinel, the exact `swiftc` invocation SwiftPM used
# for it is read off `swift build -v`, and each scaffold is compiled on its own with those flags
# (`-emit-sil`, so the SIL-stage diagnostics — region isolation — run too). Files cannot mask or
# collide with one another, and they run in parallel. The scaffolds that compile alone are then
# built TOGETHER through SwiftPM (`confirm_in_package`) so the headline is a package build.

_DROP_FLAGS = {"-g", "-c", "-enable-batch-mode", "-incremental", "-save-temps", "-color-diagnostics",
               "-explicit-module-build", "-emit-dependencies", "-emit-module", "-serialize-diagnostics",
               "-validate-clang-modules-once", "-emit-const-values",
               "-experimental-emit-module-separately", "-disable-cmo", "-serialize-debugging-options",
               "-enable-incremental-file-hashing", "-emit-objc-header", "-whole-module-optimization",
               "-wmo", "-parseable-output", "-use-frontend-parseable-output"}
_DROP_WITH_VALUE = {"-index-store-path", "-ivfsstatcache", "-output-file-map",
                    "-clang-scanner-module-cache-path", "-sdk-module-cache-path", "-emit-module-path",
                    "-dependency-scan-serialize-diagnostics-path", "-clang-build-session-file",
                    "-const-gather-protocols-list", "-emit-objc-header-path", "-o",
                    "-emit-module-interface-path", "-emit-private-module-interface-path",
                    "-num-threads", "-index-unit-output-path"}


def census_compile_args(tree, swift):
    """The `swiftc` arguments SwiftPM compiles the census target with, minus inputs and outputs."""
    census = os.path.join(tree, CENSUS_DIR)
    for entry in os.listdir(census):
        if entry != "_Sentinel.swift":
            os.remove(os.path.join(census, entry))
    # A changed sentinel forces the census module to recompile, so `-v` prints its command.
    open(os.path.join(census, "_Sentinel.swift"), "w").write(
        f"import Testing\n// {time.time()}\n")
    done = subprocess.run([swift, "build", "--target", CENSUS_TARGET, "-v"], cwd=tree,
                          capture_output=True, text=True, env=env_for(swift), timeout=3600)
    output = _ANSI.sub("", done.stdout + done.stderr)
    if done.returncode != 0:
        raise SystemExit("the census target does not build with only its sentinel — the subject or "
                         "the manifest rewrite is broken, not a scaffold:\n"
                         + "\n".join(l for l in output.splitlines() if "error:" in l)[:3000])
    command = None
    for line in output.splitlines():
        if f"-module-name {CENSUS_TARGET}" not in line:
            continue
        found = re.search(r"(\S*/swiftc|\S*/swift-frontend|\S*/swift-driver)\s", line)
        if found and " -emit-module " in line or found and " -c " in line:
            command = line[found.start():]
            break
    if command is None:
        raise SystemExit("no swiftc command for the census module in `swift build -v` output")
    args = shlex.split(command)
    units, index = [], 0
    while index < len(args):
        if args[index] in ("-Xcc", "-Xfrontend", "-Xllvm") and index + 1 < len(args):
            units.append((args[index], args[index + 1]))
            index += 2
        else:
            units.append((None, args[index]))
            index += 1
    kept, index, seen_cache = [], 0, False
    while index < len(units):
        prefix, arg = units[index]
        if (arg.startswith("@") or arg.endswith(".swift") or arg in _DROP_FLAGS
                or re.match(r"-j\d*$", arg) or arg.startswith("-fmodules-prune")):
            index += 1 + (1 if arg == "-j" else 0)
            continue
        if arg in _DROP_WITH_VALUE:
            index += 2
            continue
        if arg == "-module-cache-path":
            if seen_cache:  # the explicit-module-build cache; implicit modules use the first
                index += 2
                continue
            seen_cache = True
        if prefix:
            kept.append(prefix)
        kept.append(arg)
        index += 1
    return kept


def compile_alone(args, path, timeout=1200):
    """Compile one scaffold file with the census target's flags. Returns (exit, errors, seconds)."""
    started = time.time()
    try:
        done = subprocess.run(args + [path, "-emit-sil", "-o", "/dev/null"], capture_output=True,
                              text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None, [{"line": 0, "col": 0, "message": f"compile timed out after {timeout}s"}], \
            time.time() - started
    output = _ANSI.sub("", done.stdout + done.stderr)
    errors, real = [], os.path.realpath(path)
    for line in output.splitlines():
        match = _ERROR.match(line.strip())
        if match and os.path.realpath(match.group(1)) == real:
            record = {"line": int(match.group(2)), "col": int(match.group(3)),
                      "message": match.group(4)}
            if record not in errors:
                errors.append(record)
        elif ": error:" in line and not line.startswith("/"):
            record = {"line": 0, "col": 0, "message": line.strip()[:400]}
            if record not in errors:
                errors.append(record)
    if done.returncode != 0 and not errors:
        errors.append({"line": 0, "col": 0,
                       "message": f"compiler exited {done.returncode} with no error line"})
    return done.returncode, errors, time.time() - started


def compile_texts(texts, args, files_dir, workers):
    """{key: (header, body)} -> {key: (exit, errors with body-relative lines, seconds)}."""
    os.makedirs(files_dir, exist_ok=True)
    jobs = {}
    for key, (header, body) in texts.items():
        path = os.path.join(files_dir, f"{key}.swift")
        open(path, "w", encoding="utf-8").write(header + body)
        jobs[key] = (path, header.count("\n"))
    finished, out = 0, {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(compile_alone, args, path): key for key, (path, _h) in jobs.items()}
        for future in concurrent.futures.as_completed(futures):
            key = futures[future]
            code, errors, seconds = future.result()
            for error in errors:
                if error["line"]:
                    error["line"] -= jobs[key][1]
            out[key] = (code, errors, round(seconds, 1))
            finished += 1
            if finished % 25 == 0 or finished == len(jobs):
                log(f"    compiled {finished}/{len(jobs)}")
    return out


def compile_each(scaffolds, args, files_dir, workers):
    texts = {k: (v["header"], v["scaffold"]) for k, v in scaffolds.items()}
    for key, (code, errors, seconds) in compile_texts(texts, args, files_dir, workers).items():
        entry = scaffolds[key]
        entry["compiled_alone"] = code == 0
        entry["compiled"] = code == 0
        entry["errors"] = errors
        entry["compile_seconds"] = seconds


# ---------------------------------------------------------------------------------------------
# counterfactual probes — NOT what discover prints; what the next blocker would be
# ---------------------------------------------------------------------------------------------
#
# A bare call that does not resolve hides everything behind it: the compiler never gets far
# enough to say the call also needs `try`, or that the return type is not Equatable. The probes
# apply, mechanically and from the declaration alone, the repairs a fixed emitter would make, and
# compile again, so the baseline's histogram can be read together with what each repair EXPOSES.
#
#   call-repaired  — a static member called through its type (`BeadCorrelation.correlation(for:)`),
#                    `try` / `await` where the declaration throws / is async or actor-isolated,
#                    `Self` and nested types in the reference signature qualified. An instance
#                    method is NOT repaired: it needs a receiver, which is a design decision (a
#                    generator for the receiver type), not a spelling.
#   +hoisted       — call-repaired, plus every draw's generator bound to a typed local
#                    (`let gen0: Gen<String> = …`) before `backend.check`, which is what decides
#                    whether a `type-check-timeout` is the generator expression's own weight.

def _parameter_types(reference_line):
    open_at = reference_line.find("(")
    depth, close_at = 0, None
    for index in range(open_at, len(reference_line)):
        ch = reference_line[index]
        if ch in "([<":
            depth += 1
        elif ch in ")]>":
            depth -= 1
            if depth == 0 and ch == ")":
                close_at = index
                break
    if open_at < 0 or close_at is None:
        return None
    inner, parts, depth, current = reference_line[open_at + 1:close_at], [], 0, ""
    for ch in inner:
        if ch in "([<":
            depth += 1
        elif ch in ")]>":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(current)
            current = ""
        else:
            current += ch
    if current.strip():
        parts.append(current)
    types = []
    for part in parts:
        if ":" not in part:
            return None
        types.append(part.split(":", 1)[1].strip())
    return types


def repair_call(entry, types, effects_too=True):
    facts, func = entry["facts"], entry["func"]
    lines, applied = entry["scaffold"].split("\n"), []
    qualified = facts.get("qualified_type")
    for index, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("property:"):
            qualifier = ""
            if facts.get("shape") == "static-member" and qualified:
                qualifier = qualified + "."
                applied.append("type-qualifier")
            effects = ""
            if effects_too and facts.get("throws"):
                effects += "try "
                applied.append("try")
            if effects_too and (facts.get("async") or facts.get("isolated_by")):
                effects += "await "
                applied.append("await")
            lines[index] = line.replace(f"in {func}(", f"in {effects}{qualifier}{func}(", 1)
        elif stripped.startswith(f"func {func}_reference(") and qualified:
            head, paren, rest = line.partition("(")
            rest = re.sub(r"\bSelf\b", qualified, rest)

            def qualify(match):
                # Swift's own lookup, outward from the subject's type: `Diagnostic` written in
                # `BuildRunner` is `BuildRunner.Diagnostic` when that exists, else the next scope
                # out, else a top-level type (left as written).
                name = match.group(0)
                paths = types.get(name, set())
                scope = qualified.split(".")
                while scope:
                    candidate = ".".join(scope + [name])
                    if candidate in paths:
                        return candidate
                    scope.pop()
                if name in paths or len(paths) != 1:
                    return name
                return next(iter(paths))
            rest = re.sub(r"(?<![.\w])[A-Z]\w*", qualify, rest)
            if head + paren + rest != line:
                applied.append("signature-types")
            lines[index] = head + paren + rest
    return "\n".join(lines), applied


def hoist_generators(text, func):
    lines = text.split("\n")
    try:
        reference = next(l for l in lines if l.strip().startswith(f"func {func}_reference("))
        sample_at = next(i for i, l in enumerate(lines) if l.strip().startswith("sample:"))
        check_at = next(i for i, l in enumerate(lines) if "backend.check(" in l)
    except StopIteration:
        return text, False
    parameter_types = _parameter_types(reference)
    groups = generator_groups(lines[sample_at])
    if not parameter_types or len(groups) != len(parameter_types) or any(
            re.search(r"\b(some|inout|any)\b|@|\.\.\.", t) for t in parameter_types):
        return text, False
    indent = re.match(r"\s*", lines[check_at]).group(0)
    # Unannotated: the kit's generators are `Generator<Value, some Sequence>`, whose shrink type
    # cannot be spelled, and `Generator<T, _>` fails ("could not infer type for placeholder",
    # 42 of 88 on SwiftAssist). A statement of its own is still a separate constraint system.
    bindings = [f"{indent}let gen{k} = {g[1:-1]}"
                for k, (t, (_o, _c, g)) in enumerate(zip(parameter_types, groups))]
    draws = [f"gen{k}.run(using: &rng)" for k in range(len(groups))]
    closure = "{ rng in " + (draws[0] if len(draws) == 1 else "(" + ", ".join(draws) + ")") + " }"
    sample_indent = re.match(r"\s*", lines[sample_at]).group(0)
    lines[sample_at] = f"{sample_indent}sample: {closure},"
    lines[check_at:check_at] = bindings
    return "\n".join(lines), True


def run_probes(scaffolds, args, files_dir, workers, tree):
    types = type_index(tree)
    texts, meta = {}, {}
    for key, entry in scaffolds.items():
        # A regression check, not a measurement: the repairs rewrite a bare call and a file-scope
        # reference, so a reference declared in `extension Owner` has nothing for them to repair,
        # and is skipped.
        if entry.get("reference_in_extension"):
            entry["probes_skipped"] = "reference declared in an extension"
            continue
        repaired, applied = repair_call(entry, types)
        hoisted, did_hoist = hoist_generators(repaired, entry["func"])
        texts[f"{key}__call"] = (entry["header"], repaired)
        meta[f"{key}__call"] = (key, "call-repaired", repaired, applied)
        texts[f"{key}__hoist"] = (entry["header"], hoisted)
        meta[f"{key}__hoist"] = (key, "call-repaired+hoisted", hoisted,
                                 applied + (["hoisted"] if did_hoist else []))
        # The same, WITHOUT `try` / `await`: the compiler's own count of the effects a bare call
        # was hiding (static members and free functions only — an instance method still has no
        # receiver, so its call never resolves far enough to be asked).
        qualified, q_applied = repair_call(entry, types, effects_too=False)
        q_hoisted, q_did = hoist_generators(qualified, entry["func"])
        texts[f"{key}__noeff"] = (entry["header"], q_hoisted)
        meta[f"{key}__noeff"] = (key, "qualified-no-effects+hoisted", q_hoisted,
                                 q_applied + (["hoisted"] if q_did else []))
    for key, (code, errors, seconds) in compile_texts(texts, args, files_dir, workers).items():
        owner, probe, text, applied = meta[key]
        scaffolds[owner].setdefault("probes", {})[probe] = {
            "compiled": code == 0, "errors": errors, "applied": applied, "text": text,
            "compile_seconds": seconds}


def confirm_in_package(tree, swift, scaffolds):
    """The scaffolds that compiled alone, built together in the census target through SwiftPM
    (the funnel's fixpoint rule), in batches with no repeated function name."""
    clean = {k: v for k, v in scaffolds.items() if v.get("compiled_alone")}
    if not clean:
        return {"files": 0, "batches": []}
    log_rows = []
    for number, batch in enumerate(partition(clean)):
        outcome = build_batch_to_fixpoint(tree, swift, batch)
        log_rows.append({"batch": number, "files": len(batch), "rounds": outcome["rounds"],
                         "unattributed": outcome.get("unattributed")})
        for file_id, errors in outcome["failed"].items():
            scaffolds[file_id]["compiled"] = False
            scaffolds[file_id]["errors"] = errors
            scaffolds[file_id]["failed_only_in_package"] = True
        if outcome.get("unattributed"):
            for file_id in batch:
                if file_id not in outcome["failed"]:
                    scaffolds[file_id]["compiled"] = None
    census = os.path.join(tree, CENSUS_DIR)
    for entry in os.listdir(census):
        if entry != "_Sentinel.swift":
            os.remove(os.path.join(census, entry))
    return {"files": len(clean), "batches": log_rows}


def partition(scaffolds):
    """Batches in which no two files declare the same thing: the `@Test func` (owner-prefixed for a
    member, bare for a free function, so it also stands for the `_reference` it calls)
    and each `extension T: @unchecked Sendable {}` shim, which two files in one module may not both
    declare — the scaffold's comment tells its reader the same."""
    batches = []
    for file_id, entry in scaffolds.items():
        names = {"test:" + (entry.get("test_name") or entry["func"]), "ref:" + entry["func"]
                 if not entry.get("reference_in_extension") else "ref:" + entry["reference_in_extension"]
                 + "." + entry["func"]} | {"shim:" + t for t in entry.get("shims", [])}
        for batch in batches:
            if batch["names"].isdisjoint(names):
                batch["names"] |= names
                batch["files"][file_id] = (entry["header"], entry["scaffold"])
                break
        else:
            batches.append({"names": set(names),
                            "files": {file_id: (entry["header"], entry["scaffold"])}})
    return [b["files"] for b in batches]


# ---------------------------------------------------------------------------------------------
# 5. attribution
# ---------------------------------------------------------------------------------------------

def line_role(line_text, func):
    stripped = line_text.strip()
    if re.match(r"(?:nonisolated )?(?:static )?func " + re.escape(func) + r"_reference\(", stripped):
        return "reference-decl"
    if stripped.startswith("sample:") or re.match(r"let gen\d+ = ", stripped):
        return "sample"
    if stripped.startswith("property:"):
        return "property"
    if stripped.startswith("@Test"):
        return "test-decl"
    if "backend.check(" in stripped:
        return "check"
    return "other"


def generator_groups(sample_line):
    """[(open_col, close_col)] (1-based) of each `( … ).run(using: &rng)` draw on the sample line."""
    spans, stack, i, in_string = [], [], 0, False
    while i < len(sample_line):
        ch = sample_line[i]
        if in_string:
            if ch == "\\":
                i += 2
                continue
            if ch == '"':
                in_string = False
        elif ch == '"':
            in_string = True
        elif ch == "(":
            stack.append(i)
        elif ch == ")" and stack:
            opened = stack.pop()
            if sample_line.startswith(".run(using: &rng)", i + 1):
                spans.append((opened + 1, i + 1, sample_line[opened:i + 1]))
        i += 1
    return spans


_TYPE_DECL = re.compile(r"\b(struct|class|enum|actor|protocol|typealias|extension)\s+([A-Za-z_][\w.]*)")


def type_index(tree):
    """Every type the subject declares: name -> set of qualified paths (`X`, `Outer.X`).

    Read with the same lexer as the declaration facts, so a type inside `#if` is still top level
    and a `{` in a regex literal does not nest the rest of the file."""
    index = collections.defaultdict(dict)
    for root, dirs, files in os.walk(tree):
        dirs[:] = [d for d in dirs if d not in (".build", ".git", ".swiftinfer", "checkouts")]
        for name in files:
            if not name.endswith(".swift"):
                continue
            try:
                text = open(os.path.join(root, name), encoding="utf-8", errors="ignore").read()
            except OSError:
                continue
            blocks = scan_blocks(text)
            scopes = []  # (open, close, kind, name, modifiers) of every type or extension body
            for opened, closed, head in blocks:
                match = None
                for match in _TYPE_DECL.finditer(head):
                    pass
                if match and match.group(1) != "typealias":
                    scopes.append((opened, closed, match.group(1), match.group(2),
                                   head[:match.start()].split("\n")[-3:]))

            def path_at(offset):
                names = []
                for opened, closed, kind, type_name, _m in sorted(scopes):
                    if opened < offset < closed:
                        names = [type_name] if kind == "extension" else names + [type_name]
                return names

            def modifiers(lines):
                text_before = " ".join(lines)
                access = re.findall(r"\b(private|fileprivate|internal|public|open|package)\b",
                                    text_before)
                return {"access": access[-1] if access else "internal",
                        "spi": "@_spi" in text_before}
            for opened, closed, kind, type_name, mods in scopes:
                if kind == "extension":
                    continue
                path = ".".join(path_at(opened) + [type_name])
                index[type_name.split(".")[-1]][path] = modifiers(mods[-1:] if mods else [])
                index[type_name.split(".")[-1]][path]["spi"] = "@_spi" in " ".join(mods)
            for match in re.finditer(r"\btypealias\s+(\w+)", text):
                line_start = text.rfind("\n", 0, match.start()) + 1
                if "//" in text[line_start:match.start()]:
                    continue
                path = ".".join(path_at(match.start()) + [match.group(1)])
                index[match.group(1)][path] = modifiers([text[line_start:match.start()]])
    return index


def classify(error, scaffold_lines, func, facts, types):
    """One compiler error -> one cause."""
    message = error["message"]
    if error["line"] <= 0:
        if "timed out" in message or "no error line" in message:
            return "other:compiler"
        return "harness:header-import"  # an import the harness added, not the scaffold
    index = error["line"] - 1
    text = scaffold_lines[index] if 0 <= index < len(scaffold_lines) else ""
    role = line_role(text, func)
    # A type the scaffold names but cannot see — in the reference signature or a generator. The
    # emitter prints parameter types as SPELLED in the declaration, so a nested type written
    # unqualified inside its parent (`Citation`, not `SwiftEvolutionCitationChecker.Citation`)
    # is out of scope at file level in a test.
    missing_type = re.match(r"cannot find (?:type )?'(\w+)' in scope", message)
    if missing_type and missing_type.group(1) != func:
        name = missing_type.group(1)
        if name == "some" or name in facts.get("generic_parameters", []):
            # `func f<Node: P>(_ n: Node)` copied into a non-generic `f_reference(_ n: Node)`, or
            # an opaque `some P` parameter whose generator reads `some P.gen()`.
            return "generic-signature"
        paths = types.get(name, {})
        if not paths:
            return "type-not-in-scope:foreign-module"
        top = {p: m for p, m in paths.items() if "." not in p}
        if not top:
            return "type-not-in-scope:unqualified-nested"
        if all(m["access"] in ("private", "fileprivate") for m in top.values()):
            return "type-not-in-scope:private-type"
        if all(m["spi"] for m in top.values()):
            return "type-not-in-scope:spi-type"  # `@_spi(X) public` needs `@_spi(X) import`
        return "type-not-in-scope:other"
    if "is ambiguous for type lookup" in message:
        return "type-ambiguous"  # needs module qualification (`SwiftSyntax.SourceLocation`)
    if ("'frequency' is unavailable in Swift" in message or "'oneOf' is unavailable in Swift" in message
            or "(weight: FloatLiteralType, gen:" in message):
        # `Gen.frequency` and `Gen.oneOf` are `@available(swift 6.2)`; a Swift 5 language-mode
        # package cannot call them
        return "gen-frequency-needs-swift6.2-mode"
    if "'Self'" in message and role == "reference-decl":
        return "self-in-reference-signature"  # `-> Self?` copied out of the type it meant
    if role == "sample":
        for opened, closed, group in generator_groups(text):
            if opened <= error["col"] <= closed:
                return "todo-generator" if TODO_GEN in group else "generator-other"
        return "todo-generator" if TODO_GEN in text else "generator-other"
    if "unable to type-check this expression in reasonable time" in message:
        return "type-check-timeout"
    if "tuple type '()'" in message or "could not be inferred" in message:
        return "other:consequential"  # the sample closure failed, so `Input` never resolved
    if re.search(r"'Sendable' protocol|non-[Ss]endable|risks causing data races|^sending '", message):
        return "non-sendable-input"
    if re.search(r"(can throw|throwing).*not (marked|handled)|not marked with 'try'", message):
        return "missing-try"
    if "'async'" in message and "await" in message:
        return "missing-await:async-func" if facts.get("async") else "missing-await:isolation"
    if "actor-isolated" in message or "isolated" in message and "context" in message:
        return "actor-isolation"
    if "inaccessible due to" in message:
        return "inaccessible"
    unqualified = {
        "static-member": "bare-call:static-member",
        "instance-method": "missing-receiver:instance-method",
    }
    if re.search(r"cannot find '" + re.escape(func) + r"' in scope", message):
        if facts.get("shape") in ("free-function", "local-function") and \
                facts.get("access") in ("private", "fileprivate"):
            return "inaccessible"  # a private free function: no test can name it at all
        return unqualified.get(facts.get("shape"), "bare-call:unresolved-free-function")
    if role == "property":
        # An error AT the callee name of a member function means the bare name resolved to
        # something else (a global, a stdlib overload) rather than to nothing.
        callee = text.find(f"in {func}(")
        if callee >= 0 and error["col"] == callee + 4 and facts.get("shape") in unqualified:
            return unqualified[facts["shape"]]
        if "'=='" in message or "Equatable" in message or "==" in message:
            return "return-not-equatable"
    if "Equatable" in message or "operator '=='" in message:
        return "return-not-equatable"
    return f"other:{role}"


PRIMARY_ORDER = [
    "missing-receiver:instance-method", "bare-call:static-member", "inaccessible",
    "bare-call:unresolved-free-function", "type-check-timeout", "todo-generator", "missing-try",
    "missing-await:async-func", "missing-await:isolation", "actor-isolation",
    "non-sendable-input", "return-not-equatable",
    "type-not-in-scope:unqualified-nested", "type-not-in-scope:foreign-module",
    "type-not-in-scope:private-type", "type-not-in-scope:spi-type", "type-not-in-scope:other",
    "generic-signature", "type-ambiguous", "self-in-reference-signature",
    "gen-frequency-needs-swift6.2-mode", "generator-other",
]


def primary(causes):
    """The one cause a failing scaffold is counted under. `other:*` errors are taken as
    consequential when a known cause is present (an unresolved call leaves `backend.check`'s
    generic `Input` uninferable, for one), so they decide only when nothing else does."""
    for cause in PRIMARY_ORDER:
        if cause in causes:
            return cause
    return sorted(causes)[0] if causes else "none"


def latent_needs(entry):
    """What a CORRECT call would need, from the declaration — independent of what the compiler got
    far enough to say. A bare call that does not resolve hides its missing `try` and `await`."""
    facts, needs = entry["facts"], []
    if not facts.get("found"):
        return ["declaration-not-found"]
    if facts["shape"] == "instance-method":
        needs.append("receiver")
    elif facts["shape"] == "static-member":
        needs.append("type-qualifier")
    if facts["throws"]:
        needs.append("try")
    if facts["async"]:
        needs.append("await:async")
    elif facts["isolated_by"]:
        needs.append("await:isolation")
    if facts["mutating"]:
        needs.append("var-receiver")
    if facts["access"] in ("private", "fileprivate"):
        needs.append("access:" + facts["access"])  # no test can name it, @testable or not
    if TODO_GEN in entry["scaffold"]:
        needs.append("generator")
    return needs


# ---------------------------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------------------------

def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--swift-infer", required=True, help="the swift-infer binary to measure")
    parser.add_argument("--subject", required=True, help="the subject's git repository (read only)")
    parser.add_argument("--target", required=True, help="the module discover scans (--target)")
    parser.add_argument("--out", required=True,
                        help="work directory: subjects/, build/ and runs/<label>-<Name>/ land here")
    parser.add_argument("--sources", help="pass --sources <subject-relative dir> instead of --target")
    parser.add_argument("--ref", default="HEAD", help="the subject revision to measure")
    parser.add_argument("--label", default="baseline", help="names this run's directory")
    seeds = parser.add_mutually_exclusive_group(required=True)
    seeds.add_argument("--seeds", help="a pinned pbt-seeds manifest (compare runs on the same one)")
    seeds.add_argument("--lint-cli", help="a SwiftProjectLint CLI binary that writes the manifest")
    seeds.add_argument("--no-seeds", action="store_true", help="run discover unseeded only")
    parser.add_argument("--swift", default=XCODE_SWIFT if os.path.exists(XCODE_SWIFT) else "swift",
                        help="the toolchain that builds the subject and compiles the scaffolds")
    parser.add_argument("--no-compile", action="store_true",
                        help="run discover and extract only; compile nothing")
    parser.add_argument("--no-probes", action="store_true",
                        help="skip the counterfactual call-repair probes")
    parser.add_argument("--jobs", type=int, default=max(2, (os.cpu_count() or 4) // 2),
                        help="scaffolds compiled at once (default: half the cores)")
    parser.add_argument("--reclassify", action="store_true",
                        help="re-attribute the saved results.json of this label; no discover, no build")
    parser.add_argument("--baseline-label", default="baseline",
                        help="the run whose printed-scaffold count printed + declined must equal")
    parser.add_argument("--bare-imports", action="store_true",
                        help="header = the accept path's fixed imports + @testable only, without "
                             "the declaring file's imports")
    args = parser.parse_args(argv[1:])

    subject = os.path.realpath(os.path.expanduser(args.subject))
    name = os.path.basename(subject)
    sha = resolve_ref(subject, args.ref)
    infer = os.path.realpath(os.path.abspath(os.path.expanduser(args.swift_infer)))
    out_dir = os.path.realpath(os.path.expanduser(args.out))
    run_dir = os.path.join(out_dir, "runs", f"{args.label}-{name}")
    os.makedirs(run_dir, exist_ok=True)
    version = subprocess.run([infer, "--version"], capture_output=True, text=True).stdout.strip()
    # The type-check timeout is the solver's scope limit: deterministic, but per compiler version.
    compiler = subprocess.run([args.swift, "--version"], capture_output=True, text=True,
                              env=env_for(args.swift)).stdout.strip().split("\n")[0]
    log(f"swift-infer {version} ({infer}); subject {name} @ {sha[:10]}; run dir {run_dir}")
    log(f"compiler: {compiler}")

    tree, _ = ensure_worktree(subject, os.path.join(out_dir, "subjects", name), sha)
    sources = os.path.join(tree, args.sources) if args.sources else None

    # Types are looked up in the scanned module only: a same-named type elsewhere in the tree
    # (a sibling package) is not visible to the scaffold and must not read as in scope.
    target_sources = sources or os.path.join(tree, "Sources", args.target)

    if args.reclassify:
        results = json.load(open(os.path.join(run_dir, "results.json")))
        cache = {}
        for entry in results["scaffolds"]:  # facts too: the reader may have changed since
            if entry.get("file"):
                entry["facts"] = decl_facts(entry["file"], entry["line"], entry["func"], cache)
        attribute(results["scaffolds"], target_sources)
        json.dump(results, open(os.path.join(run_dir, "results.json"), "w"), indent=2)
        report(results, run_dir)
        return 0

    manifest = None
    if args.seeds:
        manifest = os.path.realpath(os.path.expanduser(args.seeds))
    elif args.lint_cli:
        manifest = os.path.join(run_dir, f"{name}-seeds.json")
        count = make_seeds(args.lint_cli, tree, manifest)
        log(f"seeds: {count} rows from {args.lint_cli}")

    modes = [("seeded", manifest)] if manifest else []
    modes.append(("unseeded", None))
    runs, scaffolds, cache = {}, {}, {}
    for mode, seed_path in modes:
        out = os.path.join(run_dir, f"discover-{mode}.txt")
        meta = run_discover(infer, tree, args.target, sources, seed_path, out, args.swift)
        extracted = extract_scaffolds(open(out, encoding="utf-8").read())
        items = extracted["items"]
        with_scaffold = [i for i in items if i["scaffold"]]
        declined = [{"display": i["display"], "file": i.get("file"), "line": i.get("line"),
                     "reason": i["declined"], "category": decline_category(i["declined"])}
                    for i in items if i.get("declined")]
        runs[mode] = {"discover": meta, "section_functions": extracted["functions"],
                      "items_parsed": len(items), "scaffolds": len(with_scaffold), "ids": [],
                      "declined": declined,
                      "declined_by_category": dict(collections.Counter(d["category"] for d in declined))}
        log(f"{mode}: {extracted['functions']} documented functions, {len(with_scaffold)} scaffolds, "
            f"{len(declined)} declined ({meta['seconds']}s)")
        for item in with_scaffold:
            func_match = _FUNC_NAME.search(item["scaffold"])
            func = func_match.group(1) if func_match else item["display"].split("(")[0]
            digest = hashlib.sha1(item["scaffold"].encode()).hexdigest()[:10]
            file_id = f"S_{func}_{digest}"
            runs[mode]["ids"].append(file_id)
            if file_id in scaffolds:
                scaffolds[file_id]["modes"].append(mode)
                continue
            owner = _EXTENSION_REFERENCE.search(item["scaffold"])
            scaffolds[file_id] = {
                "id": file_id, "func": func, "display": item["display"],
                "reference_in_extension": owner.group(1) if owner else None,
                "test_name": (_TEST_NAME.search(item["scaffold"]) or [None, func])[1],
                "shims": _SHIM.findall(item["scaffold"]),
                "signature": item["signature"], "file": item.get("file"),
                "line": item.get("line"), "scaffold": item["scaffold"], "modes": [mode],
                "facts": decl_facts(item["file"], item["line"], func, cache)
                if item.get("file") else {"found": False, "why": "no location"},
            }
    for entry in scaffolds.values():
        entry["latent_needs"] = latent_needs(entry)
        entry["header"] = stub_header(args.target, entry.get("file"), not args.bare_imports)

    baseline = {}
    baseline_path = os.path.join(out_dir, "runs", f"{args.baseline_label}-{name}", "results.json")
    if args.label != args.baseline_label and os.path.exists(baseline_path):
        baseline_runs = json.load(open(baseline_path))["runs"]
        baseline = {"label": args.baseline_label,
                    "scaffolds": {m: r["scaffolds"] for m, r in baseline_runs.items()},
                    "items": {m: r["items_parsed"] for m, r in baseline_runs.items()}}
    results = {"swift_infer": version, "swift_infer_path": infer, "compiler": compiler,
               "subject": name,
               "subject_sha": sha, "target": args.target, "seeds": manifest, "runs": runs,
               "baseline": baseline,
               "distinct_scaffolds": len(scaffolds),
               "imports": "fixed" if args.bare_imports else "fixed + declaring file's"}
    if not args.no_compile and scaffolds:
        stage5 = import_stage5()
        build_tree = ensure_build_tree(subject, os.path.join(out_dir, "build"), sha,
                                       args.target, args.swift, stage5)
        log(f"building the census target (sentinel only) in {build_tree}")
        compile_args = census_compile_args(build_tree, args.swift)
        json.dump(compile_args, open(os.path.join(run_dir, "census-swiftc-args.json"), "w"), indent=1)
        log(f"compiling {len(scaffolds)} distinct scaffolds one file each ({args.jobs} at a time)")
        compile_each(scaffolds, compile_args, os.path.join(run_dir, "files"), args.jobs)
        alone = sum(1 for v in scaffolds.values() if v.get("compiled_alone"))
        log(f"{alone} compiled alone; confirming them together in the package")
        results["package_confirm"] = confirm_in_package(build_tree, args.swift, scaffolds)
        if not args.no_probes:
            log("counterfactual probes: call-repaired, +hoisted, qualified-no-effects+hoisted")
            run_probes(scaffolds, compile_args, os.path.join(run_dir, "probe-files"), args.jobs,
                       target_sources)
        attribute(scaffolds.values(), target_sources)

    results["scaffolds"] = list(scaffolds.values())
    json.dump(results, open(os.path.join(run_dir, "results.json"), "w"), indent=2)
    report(results, run_dir)
    return 0


_TODO_DRAW = re.compile(r"\(([^()]*?(?:\([^()]*\))?[^()]*?)\.gen\(\) /\* TODO")


def todo_types(scaffold, types):
    """Each `<T>.gen() /* TODO */` draw, with whether T is the subject's own type (`project`: the
    project-type resolver the template path uses could derive it), another module's (`foreign`:
    a SwiftSyntax node, `Range<Int>` — no resolver over the subject's sources can), or both."""
    rows = []
    for type_text in _TODO_DRAW.findall(scaffold):
        names = [n for n in re.findall(r"[A-Za-z_]\w*", type_text)
                 if n not in ("some", "any", "Type", "Index", "Element")]
        own = [n for n in names if n in types]
        origin = "project" if own and len(own) == len(names) else ("mixed" if own else "foreign")
        rows.append({"type": type_text, "origin": origin})
    return rows


def attribute(scaffolds, tree):
    """Classify every recorded compiler error. Separate from the build so `--reclassify` can
    re-run it over a saved results.json without compiling anything."""
    types = type_index(tree)
    for entry in scaffolds:
        entry["latent_needs"] = latent_needs(entry)
        entry["todo_types"] = todo_types(entry["scaffold"], types)
        if entry.get("compiled") is None:
            entry["compiled"] = None  # unmeasured: an unattributed failure stopped the batch
            continue
        lines = entry["scaffold"].split("\n")
        for error in entry["errors"]:
            error["cause"] = classify(error, lines, entry["func"], entry["facts"], types)
            index = error["line"] - 1
            error["source"] = lines[index].strip()[:240] if 0 <= index < len(lines) else ""
        entry["causes"] = sorted({e["cause"] for e in entry["errors"]})
        entry["primary"] = primary(entry["causes"]) if not entry["compiled"] else None
        for probe in entry.get("probes", {}).values():
            probe_lines = probe["text"].split("\n")
            for error in probe["errors"]:
                error["cause"] = classify(error, probe_lines, entry["func"], entry["facts"], types)
                index = error["line"] - 1
                error["source"] = (probe_lines[index].strip()[:240]
                                   if 0 <= index < len(probe_lines) else "")
            probe["causes"] = sorted({e["cause"] for e in probe["errors"]})


def report(results, run_dir):
    scaffolds = results["scaffolds"]
    by_id = {s["id"]: s for s in scaffolds}
    out = []
    out.append(f"subject {results['subject']} @ {results['subject_sha'][:10]}, target "
               f"{results['target']}; swift-infer {results['swift_infer']}")
    out.append(f"results: {os.path.join(run_dir, 'results.json')}; stub imports: {results['imports']}")
    if results.get("compiler"):
        out.append(f"compiler: {results['compiler']}")
    for mode, run in results["runs"].items():
        ids = run["ids"]
        measured = [by_id[i] for i in ids if by_id[i].get("compiled") is not None]
        compiled = sum(1 for s in measured if s["compiled"])
        out.append("")
        out.append(f"== {mode}: {run['section_functions']} documented functions, {run['scaffolds']} "
                   f"scaffolds printed; COMPILE {compiled} / {len(measured)} measured"
                   + ("" if len(measured) == len(ids) else f" ({len(ids) - len(measured)} unmeasured)"))
        declined = run.get("declined", [])
        categories = collections.Counter(d["category"] for d in declined)
        neither = run["items_parsed"] - run["scaffolds"] - len(declined)
        out.append(f"   printed {run['scaffolds']}, compiled {compiled}, declined {len(declined)} ("
                   + ", ".join(f"{k} {v}" for k, v in sorted(categories.items())) + f"), neither {neither}")
        base = results.get("baseline") or {}
        if base.get("scaffolds", {}).get(mode) is not None:
            was = base["scaffolds"][mode]
            now = run["scaffolds"] + len(declined)
            out.append(f"   printed + declined = {now}; {base['label']} printed {was} scaffolds: "
                       + ("MATCH" if now == was else f"MISMATCH ({now - was:+d})")
                       + f"; items {run['items_parsed']} (was {base['items'][mode]})")
        shapes = collections.Counter(by_id[i]["facts"].get("shape", "not-found") for i in ids)
        out.append("   subject shape: " + ", ".join(f"{k} {v}" for k, v in shapes.most_common()))
        failing = [s for s in measured if not s["compiled"]]
        prim = collections.Counter(s["primary"] for s in failing)
        out.append(f"   primary cause (one per failing scaffold, priority order): "
                   + ", ".join(f"{k} {v}" for k, v in prim.most_common()))
        multi = collections.Counter(c for s in failing for c in s["causes"])
        out.append(f"   any cause (a scaffold counts under every cause the compiler reported): "
                   + ", ".join(f"{k} {v}" for k, v in multi.most_common()))
        known = {s["id"]: [c for c in s["causes"] if not c.startswith(("other:", "harness:"))]
                 for s in failing}
        sole = collections.Counter(known[s["id"]][0] for s in failing if len(known[s["id"]]) == 1)
        out.append(f"   sole known cause (other:* errors beside it ignored): "
                   + ", ".join(f"{k} {v}" for k, v in sole.most_common()))
        combos = collections.Counter(" + ".join(known[s["id"]]) or "(other only)" for s in failing)
        out.append(f"   cause combinations: " + "; ".join(f"{k}: {v}" for k, v in combos.most_common()))
        origins = collections.Counter(t["origin"] for i in ids for t in by_id[i].get("todo_types", []))
        per_scaffold = collections.Counter(
            "+".join(sorted({t["origin"] for t in by_id[i].get("todo_types", [])}))
            for i in ids if by_id[i].get("todo_types"))
        out.append(f"   TODO-generator draws by type origin: "
                   + ", ".join(f"{k} {v}" for k, v in origins.most_common())
                   + "; scaffolds: " + ", ".join(f"{k} {v}" for k, v in per_scaffold.most_common()))
        latent = collections.Counter(n for i in ids for n in by_id[i]["latent_needs"])
        out.append(f"   declaration says the call needs (all scaffolds, compiler-independent): "
                   + ", ".join(f"{k} {v}" for k, v in latent.most_common()))
        for entry in failing:
            first = entry["errors"][0] if entry["errors"] else {"message": "?", "line": 0, "source": ""}
            out.append(f"   PRINTED BUT FAILS: {entry['display']}  {entry.get('file', '?')}:{entry.get('line')}"
                       f"  [{entry.get('primary')}] {first['message'][:200]}")
        for row in declined:
            out.append(f"   declined [{row['category']}] {row['display']}: {row['reason'][:220]}")
    if any(s.get("probes") or s.get("probes_skipped") for s in scaffolds):
        out.append("")
        out.append("== counterfactual probes (NOT what discover prints — what the next blocker is)")
        for mode, run in results["runs"].items():
            ids = run["ids"]
            for probe in ("call-repaired", "call-repaired+hoisted", "qualified-no-effects+hoisted"):
                rows = [by_id[i]["probes"][probe] for i in ids if probe in by_id[i].get("probes", {})]
                if not rows:
                    continue
                ok = sum(1 for r in rows if r["compiled"])
                multi = collections.Counter(c for r in rows if not r["compiled"] for c in r["causes"])
                out.append(f"   {mode} / {probe}: COMPILE {ok} / {len(rows)}; any cause: "
                           + ", ".join(f"{k} {v}" for k, v in multi.most_common()))
                combos = collections.Counter(
                    " + ".join(c for c in r["causes"] if not c.startswith(("other:", "harness:")))
                    or "(other only)" for r in rows if not r["compiled"])
                out.append(f"      still failing, by cause combination: "
                           + "; ".join(f"{k}: {v}" for k, v in combos.most_common()))
        # The regression check: a mechanical repair of the printed call compiling where the printed
        # scaffold does not means the emitter still spells something the repair fixes.
        regressions = [s for s in scaffolds if s.get("compiled") is False and s.get("probes")
                       and s["probes"]["call-repaired"]["compiled"]]
        skipped = sum(1 for s in scaffolds if s.get("probes_skipped"))
        out.append(f"   regression check: {len(regressions)} scaffolds whose call-repaired probe compiles "
                   f"while the scaffold does not (emitter defects); {skipped} skipped (reference in "
                   f"an extension, nothing to repair)")
        for s in regressions:
            out.append(f"      EMITTER DEFECT: {s['display']}  {s.get('file')}:{s.get('line')}")
        probe_failing = [(s, s["probes"]["call-repaired"]) for s in scaffolds
                         if s.get("probes") and not s["probes"]["call-repaired"]["compiled"]]
        seen = collections.defaultdict(list)
        for s, probe in probe_failing:
            for e in probe["errors"]:
                if e["cause"] in ("missing-receiver:instance-method",):
                    continue
                if len(seen[e["cause"]]) < 3 and all(x[0]["id"] != s["id"] for x in seen[e["cause"]]):
                    seen[e["cause"]].append((s, e))
        out.append("   examples exposed by call-repaired (receiver failures omitted):")
        for cause, rows in sorted(seen.items(), key=lambda kv: -len(kv[1])):
            out.append(f"   -- {cause}")
            for s, e in rows:
                out.append(f"      {s['display']}  [{s['facts'].get('shape')}]: {e['message'][:200]}")
                out.append(f"         line {e['line']}: {e['source'][:180]}")
    failing = [s for s in scaffolds if s.get("compiled") is False]
    out.append("")
    out.append("== examples (3 per cause, all distinct scaffolds)")
    seen = collections.defaultdict(list)
    for s in failing:
        for e in s["errors"]:
            if len(seen[e["cause"]]) < 3 and all(x[0] != s["id"] for x in seen[e["cause"]]):
                seen[e["cause"]].append((s["id"], s, e))
    for cause in sorted(seen, key=lambda c: -sum(1 for s in failing if c in s["causes"])):
        out.append(f"-- {cause}")
        for _id, s, e in seen[cause]:
            loc = f"{os.path.relpath(s['file'], os.path.dirname(os.path.dirname(s['file'])))}:{s['line']}" if s.get("file") else "?"
            facts = s["facts"]
            out.append(f"   {s['display']}  [{facts.get('shape')}"
                       f"{' ' + facts['qualified_type'] if facts.get('qualified_type') else ''}"
                       f"{', throws' if facts.get('throws') else ''}{', async' if facts.get('async') else ''}"
                       f"{', ' + facts['isolated_by'] if facts.get('isolated_by') else ''}]  {loc}")
            out.append(f"      error: {e['message'][:220]}")
            out.append(f"      line {e['line']}: {e['source'][:200]}")
    text = "\n".join(out) + "\n"
    open(os.path.join(run_dir, "summary.txt"), "w").write(text)
    print(text)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
