#!/usr/bin/env python3
"""Does #667's layering law kill a mutant SwiftUMLBridge's own suite misses? — scope §5,
`docs/plans/layering-law-census-scope.md`.

swift-mutation-testing, the road test's tool, is not installed here, so this generates the mutants itself, with
the operators that tool's experimental tier applied in the road test (§5.3; `parity` checks them against its
recorded mutants). Each mutant is built in an export of SwiftUMLStudio and run against the hand-written law
(`fixtures/layering-law/LayeringLawTests.swift`) and against the hand-written suite, separately (§5.4). Runner
controls RC1-RC7 run first (§5.5).

  --self-test                      the operator rewrites on a fixture snippet (no compiler; joins `make measurement-selftest`)
  mutants <export>                 list the mutants, and the off-tree counts, without building
  parity <SwiftUMLStudio checkout> generate over e36da59's scoped files and diff against the road test's mutants
  run <export> <out.json>          RC1-RC7, then every mutant; resumes from <out.json> if it exists
"""
import collections
import hashlib
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from budgeted_truncation_census import FUNC, brace_pairs  # noqa: E402
from mutation_check import mask  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
FIXTURES = os.path.join(HERE, "..", "fixtures", "layering-law")
ROADTEST = os.path.join(HERE, "..", "fixtures", "mutation-check", "roadtest-swiftumlstudio-2026-10-10.jsonl")
PACKAGE = "SwiftUMLBridge"
SOURCES = os.path.join(PACKAGE, "Sources", "SwiftUMLBridgeFramework")
LAW_DESTINATION = os.path.join(PACKAGE, "Tests", "SwiftUMLBridgeFrameworkTests", "LayeringLaw",
                               "LayeringLawTests.swift")

# §5.3: the bodies on the law's call tree inside #667's scoped files. A nested function counts with its outer one.
MUTATED = {
    "Emitters/ActivitySVGRenderer.swift": ["computeLayout", "computeRows", "forwardEdges", "computeColumns",
                                           "nodeSize"],
    "Model/ComponentSVGRenderer.swift": ["computeLayout", "dependencyLevels", "chainDepth", "boxSize",
                                         "stereotypeLabel"],
}
# §5.6: which mutated functions decide layers, and which only turn layers into coordinates and sizes.
LAYERING_LOGIC = {"computeRows", "forwardEdges", "dependencyLevels", "chainDepth"}
# §5.3: the scoped files' other functions, counted and not run.
COUNTED = ["Emitters/ActivitySVGRenderer.swift", "Emitters/ActivitySVGRenderer+Shapes.swift",
           "Model/ComponentSVGRenderer.swift"]

BUILD_LIMIT, LAW_LIMIT, SUITE_LIMIT = 600, 120, 300
# §5.4: a test run whose processes hold more than this much resident memory, together, is stopped.
RSS_LIMIT_KB = 6 * 1024 * 1024
# Regexes over test IDs: `\.LayeringLawTests/` matches the law and not `ActivityRowLayeringTests`.
LAW_FILTER, SUITE_FILTER = r"\.LayeringLawTests/", r"^SwiftUMLBridgeFrameworkTests\."
# §5.4: the three tests PR #64 wrote that assert the law on its own examples, left out of the REDUCED suite.
# `whileLoopHasOneBackEdge` counts dashed edges, and an edge is dashed exactly when its target's centerY is not
# below its source's, so it asserts L2 on the while-loop graph.
DERIVED_SKIP = r"ActivityRowLayeringTests/(everyEdgeDescends|deadLoopIsIgnored|whileLoopHasOneBackEdge)"
DERIVED_NAMES = {"a join sits below every predecessor in a loop-free body",
                 "a cycle that start never reaches does not stall layering",
                 "a while loop renders exactly one dashed back-edge"}
# §5.1: the toolchain the road test used.
TOOLCHAIN = "swiftlang-6.4.0.34.1"
# §5.4: how long a killed process may take to leave the process table.
GRACE_SECONDS = 5


# ── Operators (§5.3) ──────────────────────────────────────────────────────────────────────────────
# A binary operator is one written with a space on each side, as Swift requires of a binary operator that
# has whitespace on either side; so `->`, `..<`, a prefix `-`, generic `<T>` and `String?` never match. An
# operator passed as a function, `reduce(0, +)`, is an arithmetic site too, as it was for the road test's tool.
SWAPS = {
    "arithmetic": (re.compile(r"(?<= )([+\-*/%])(?= )|(?<=[(,] )([+\-*/])(?=\))"),
                   {"+": ["-"], "-": ["+"], "*": ["/"], "/": ["*"], "%": ["*"]}),
    "relational": (re.compile(r"(?<= )(<=|>=|==|!=|<|>)(?= )"),
                   {"<": ["<=", ">"], "<=": ["<", ">="], ">": [">=", "<"], ">=": [">", "<="], "==": ["!="],
                    "!=": ["=="]}),
    "logical": (re.compile(r"(?<= )(&&|\|\|)(?= )"), {"&&": ["||"], "||": ["&&"]}),
    "boolean-literal": (re.compile(r"\b(true|false)\b"), {"true": ["false"], "false": ["true"]}),
}
TOOL_NAMES = {"arithmetic": "ArithmeticOperatorReplacement", "relational": "RelationalOperatorReplacement",
              "logical": "LogicalOperatorReplacement", "boolean-literal": "BooleanLiteralReplacement",
              "negate-conditional": "NegateConditional", "swap-ternary": "SwapTernary",
              "remove-side-effects": "RemoveSideEffects"}
CONDITION = re.compile(r"\b(if|guard|while)\b")
BINDING = re.compile(r"^\s*(let|var|case)\b|^\s*#available")
IDENTIFIER = re.compile(r"[A-Za-z_]\w*")
STATEMENT_KEYWORDS = {"return", "if", "guard", "while", "for", "switch", "case", "let", "var", "try", "await",
                      "throw", "defer", "repeat", "else", "break", "continue", "fallthrough"}
OPENERS, CLOSERS = "([{", ")]}"
STATEMENT_BLOCK = re.compile(r"^(\}\s*)?(for|while|if|else|guard|repeat|do|defer|catch|switch|case|default)\b"
                             r"|\belse$")


def _match_close(masked, index):
    """The index of the bracket closing the one at `index`."""
    depth = 0
    for position in range(index, len(masked)):
        if masked[position] in OPENERS:
            depth += 1
        elif masked[position] in CLOSERS:
            depth -= 1
            if depth == 0:
                return position
    return -1


def _top_level(masked, start, stop, test):
    """The first index in `[start, stop)` at bracket depth 0 where `test(index)` holds, or -1."""
    depth = 0
    for position in range(start, stop):
        character = masked[position]
        if depth == 0 and test(position):
            return position
        if character in OPENERS:
            depth += 1
        elif character in CLOSERS:
            depth -= 1
            if depth < 0:
                return -1
    return -1


def _ternaries(masked, start, stop):
    for match in re.finditer(r"(?<= )\?(?= )", masked[start:stop]):
        question = start + match.start()
        colon = _top_level(masked, question + 1, stop, lambda i: masked.startswith(" : ", i - 1))
        if colon < 0:
            continue
        end = colon + 1
        depth = 0
        while end < stop:
            character = masked[end]
            if character in OPENERS:
                depth += 1
            elif character in CLOSERS:
                if depth == 0:
                    break
                depth -= 1
            elif depth == 0 and character in ",\n":
                break
            end += 1
        yes = (question + 1, colon)
        no = (colon + 1, end)
        yield question, end, yes, no


def _conditions(masked, start, stop):
    """`(clause_start, clause_end)` for each condition clause of an `if`, `guard` or `while` in the span."""
    for match in CONDITION.finditer(masked, start, stop):
        keyword = match.group(1)
        begin = match.end()
        if keyword == "guard":
            end = _top_level(masked, begin, stop, lambda i: re.match(r"\belse\b", masked[i:i + 5]) is not None
                             and not (masked[i - 1].isalnum() or masked[i - 1] == "_"))
        else:
            end = _top_level(masked, begin, stop, lambda i: masked[i] == "{")
        if end < 0:
            continue
        clause_start = begin
        while True:
            comma = _top_level(masked, clause_start, end, lambda i: masked[i] == ",")
            clause_end = end if comma < 0 else comma
            text = masked[clause_start:clause_end]
            if text.strip() and not BINDING.match(text):
                left = clause_start + (len(text) - len(text.lstrip()))
                right = clause_end - (len(text) - len(text.rstrip()))
                yield left, right
            if comma < 0:
                break
            clause_start = comma + 1


def _call_open(masked, begin):
    """The index of the `(` that opens a call starting at `begin` (`a.b[c, d: []].e(`), or -1. Subscripts may
    nest brackets, as `outgoing[edge.fromId, default: []]` does."""
    head = IDENTIFIER.match(masked, begin)
    if not head or head.group(0) in STATEMENT_KEYWORDS:
        return -1
    position = head.end()
    while position < len(masked):
        if masked[position] == "(":
            return position
        if masked[position] == "[":
            close = _match_close(masked, position)
            if close < 0:
                return -1
            position = close + 1
        elif masked[position] == "." and (member := IDENTIFIER.match(masked, position + 1)):
            position = member.end()
        else:
            return -1
    return -1


def _implicit_return(masked, begin, end):
    """True when the call `[begin, end)` is the only expression of a function or closure body, where it is the
    body's value, not a discarded statement. A loop's, branch's or `do`/`defer` block's only call is a statement."""
    opening = masked.rfind("{", 0, begin)
    if opening < 0 or masked[opening + 1:begin].strip() or not re.match(r"\s*\}", masked[end:]):
        return False
    line = masked[masked.rfind("\n", 0, opening) + 1:opening].strip()
    return not STATEMENT_BLOCK.match(line)


def _call_statements(masked, start, stop):
    """Statements that are only a call: they start a line (or follow `{`) and end at the call's `)`. A call
    that is a body's implicit return is not one (the road test's tool never removed those)."""
    for match in re.finditer(r"(?:(?<=\n)|(?<=\{))[ \t]*", masked[start:stop]):
        begin = start + match.end()
        opening = _call_open(masked, begin)
        if opening < 0 or opening >= stop:
            continue
        close = _match_close(masked, opening)
        if close < 0 or close >= stop:
            continue
        after = masked[close + 1:stop]
        rest = re.match(r"[ \t]*(\n|\}|;|$)", after)
        if rest and not _implicit_return(masked, begin, close + 1):
            yield begin, close + 1


def mutants_in(text, span, function, path):
    """Every §5.3 mutant inside `span` of `text` (masked first, so comments and literals are never mutated)."""
    masked, _ = mask(text)
    start, stop = span
    found = []

    def add(operator, offset, length, replacement):
        found.append({"file": path, "function": function, "operator": operator, "offset": offset,
                      "length": length, "original": text[offset:offset + length], "replacement": replacement,
                      "line": text.count("\n", 0, offset) + 1})

    for operator, (pattern, table) in SWAPS.items():
        for match in pattern.finditer(masked, start, stop):
            group = 1 if match.group(1) is not None else 2
            for replacement in table[match.group(group)]:
                add(operator, match.start(group), len(match.group(group)), replacement)
    for left, right in _conditions(masked, start, stop):
        add("negate-conditional", left, right - left, f"!({text[left:right]})")
    for _, end, yes, no in _ternaries(masked, start, stop):
        swapped = f" {text[no[0]:end].strip()} :{text[yes[0]:yes[1]]}"
        add("swap-ternary", yes[0], end - yes[0], swapped.rstrip() + (" " if text[end - 1] == " " else ""))
    for begin, end in _call_statements(masked, start, stop):
        add("remove-side-effects", begin, end - begin, "")
    found.sort(key=lambda m: (m["offset"], m["operator"], m["replacement"]))
    return found


def function_spans(text):
    """`{name: [(body_start, body_end), …]}` for every `func` in `text`, outermost and nested alike."""
    masked, _ = mask(text)
    pairs = brace_pairs(masked)
    spans = collections.defaultdict(list)
    for match in FUNC.finditer(masked):
        paren = match.end() - 1
        close = _match_close(masked, paren)
        brace = masked.find("{", close)
        if close < 0 or brace < 0 or masked[close:brace].count("\n") > 4:
            continue
        spans[match.group(1)].append((brace + 1, pairs.get(brace, len(masked) - 1)))
    return spans


def innermost(spans, offset):
    best = None
    for name, ranges in spans.items():
        for start, stop in ranges:
            if start <= offset < stop and (best is None or stop - start < best[1] - best[0]):
                best = (start, stop, name)
    return best[2] if best else None


def all_mutants(text, relative):
    """Every mutant in every function body of one file, each once, with its innermost function."""
    spans = function_spans(text)
    everything = {}
    for name, ranges in spans.items():
        for span in ranges:
            for mutant in mutants_in(text, span, name, relative):
                everything[(mutant["offset"], mutant["operator"], mutant["replacement"])] = mutant
    rows = sorted(everything.values(), key=lambda m: (m["offset"], m["operator"], m["replacement"]))
    for mutant in rows:
        mutant["innermost"] = innermost(spans, mutant["offset"])
    return rows, spans


def plan(export):
    """`(mutants, off_tree)`: §5.3's mutants on the call tree, and the per-function count of the scoped files' rest."""
    mutants, off_tree = [], collections.Counter()
    for relative in COUNTED:
        text = open(os.path.join(export, SOURCES, relative), encoding="utf-8").read()
        rows, spans = all_mutants(text, relative)
        for mutant in rows:
            owner = mutant.pop("innermost")
            top = [name for name in MUTATED.get(relative, [])
                   if any(start <= mutant["offset"] < stop for start, stop in spans.get(name, []))]
            if top:
                mutant["function"] = top[0] if owner == top[0] else f"{top[0]}/{owner}"
                mutants.append(mutant)
            else:
                off_tree[f"{relative}:{owner}"] += 1
    for index, mutant in enumerate(mutants, 1):
        mutant["id"] = f"M{index:03d}"
    return mutants, dict(off_tree)


def parity(checkout):
    """§5.3's parity check: this generator over e36da59's scoped files, against the road test's recorded mutants.
    Compared as (file, line, operator, original operator token, replacement token) for the token operators and
    (file, line, operator) for the rest. Prints both differences; returns them."""
    recorded = collections.Counter()
    for line in open(ROADTEST, encoding="utf-8"):
        row = json.loads(line)
        relative = row["file"].replace("Sources/SwiftUMLBridgeFramework/", "")
        if relative in COUNTED:
            token = (row["original"], row["replacement"]) if row["operator"] in (
                "ArithmeticOperatorReplacement", "RelationalOperatorReplacement", "LogicalOperatorReplacement",
                "BooleanLiteralReplacement") else ()
            recorded[(relative, row["line"], row["operator"]) + token] += 1
    generated = collections.Counter()
    for relative in COUNTED:
        text = subprocess.run(["git", "-C", checkout, "show", f"e36da59:{SOURCES}/{relative}"], capture_output=True,
                              text=True, check=True).stdout
        for mutant in all_mutants(text, relative)[0]:
            tool = TOOL_NAMES[mutant["operator"]]
            token = (mutant["original"], mutant["replacement"]) if mutant["operator"] in (
                "arithmetic", "relational", "logical", "boolean-literal") else ()
            generated[(relative, mutant["line"], tool) + token] += 1
    only_tool, only_here = recorded - generated, generated - recorded
    print(f"recorded {sum(recorded.values())}, generated {sum(generated.values())}, shared "
          f"{sum((recorded & generated).values())}")
    for key in sorted(only_tool):
        print("  only the tool:", key)
    for key in sorted(only_here):
        print("  only here:    ", key)
    return only_tool, only_here


# ── The runner (§5.4) ─────────────────────────────────────────────────────────────────────────────
def _descendants(pid):
    found, frontier = [], [pid]
    while frontier:
        out = subprocess.run(["pgrep", "-P", str(frontier.pop())], capture_output=True, text=True).stdout.split()
        children = [int(child) for child in out]
        found += children
        frontier += children
    return found


def _export_processes(export):
    """`[(pid, rss_kb)]` for live processes whose command line names the export (the test helper's does)."""
    out = subprocess.run(["ps", "-axo", "pid=,rss=,command="], capture_output=True, text=True).stdout
    rows = []
    for line in out.splitlines():
        parts = line.split(None, 2)
        if len(parts) == 3 and export in parts[2] and "layering_kill_arm" not in parts[2]:
            rows.append((int(parts[0]), int(parts[1])))
    return rows


def _resident_kb(pid, export):
    """Resident memory of the run's own process tree and of every process naming the export, together (§5.4)."""
    pids = set(_descendants(pid) + [pid]) | {found for found, _ in _export_processes(export)}
    out = subprocess.run(["ps", "-o", "rss=", "-p", ",".join(map(str, sorted(pids)))], capture_output=True, text=True)
    return sum(int(value) for value in out.stdout.split() if value.isdigit())


def _sweep(export):
    """Kill whatever still names the export, and wait up to GRACE_SECONDS for it to leave. True when nothing
    naming the export is left."""
    deadline = time.time() + GRACE_SECONDS
    while True:
        alive = _export_processes(export)
        if not alive:
            return True
        if time.time() > deadline:
            return False
        for pid, _ in alive:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        time.sleep(0.2)


def _kill(process, export):
    """Kill the run's whole tree. The descendants are collected first: once `swift-test` dies, the test
    helper is reparented to launchd and `pgrep -P` can no longer find it; the export path still can."""
    victims = _descendants(process.pid) + [process.pid] + [pid for pid, _ in _export_processes(export)]
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def _run(command, cwd, limit, export, watch_memory):
    """`(code, output, seconds, stopped)`: `stopped` is None, "TIMEOUT" or "MEMORY". Output goes to a file, so an
    orphan holding it cannot block the read. A run killed mid-write can end inside a character, so a bad byte
    is replaced, never fatal (scope amendment 1)."""
    with tempfile.TemporaryFile(mode="w+", encoding="utf-8", errors="replace") as log:
        started = time.time()
        process = subprocess.Popen(command, cwd=cwd, stdout=log, stderr=subprocess.STDOUT, text=True,
                                   start_new_session=True)
        stopped = None
        while process.poll() is None:
            time.sleep(0.5)
            if time.time() - started > limit:
                stopped = "TIMEOUT"
            elif watch_memory and _resident_kb(process.pid, export) > RSS_LIMIT_KB:
                stopped = "MEMORY"
            if stopped:
                _kill(process, export)
                break
        try:
            process.wait(timeout=30)
        except subprocess.TimeoutExpired:
            _kill(process, export)
        seconds = time.time() - started
        _sweep(export)
        log.seek(0)
        return process.returncode, log.read(), seconds, stopped


FAILED_TEST = re.compile(r'✘ Test "([^"]+)"')
RUN_FAILED = re.compile(r"Test run with \d+ tests?.* failed")
SUMMARY = re.compile(r"^LAYERING-LAW .*$", re.M)


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


def reduced(swift, package, export, full):
    """The REDUCED suite (§5.4): the full suite less PR #64's three law-derived tests. Read off the full run when
    its failures are assertions naming another test, or when it survived; otherwise run it."""
    if full["outcome"] == "SURVIVED":
        return dict(full, derived_from_full=True)
    if full["mechanism"] == "ASSERTION" and set(full["failed"]) - DERIVED_NAMES:
        return dict(full, failed=sorted(set(full["failed"]) - DERIVED_NAMES), derived_from_full=True)
    result = _suite(swift, package, export, FULL + ["--skip", DERIVED_SKIP], SUITE_LIMIT)
    return dict(result, derived_from_full=False)


FULL = ["--filter", SUITE_FILTER, "--skip", LAW_FILTER]


def confirmed(swift, package, export, arguments, result):
    """§5.4's flake rule: a detection by ASSERTION is run once more, and stands only if the rerun detects too.
    The suite holds wall-clock assertions, and the machine is shared."""
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


def detected(result, side):
    return result.get("build") == "ok" and result[side]["outcome"] == "DETECTED"


def tree_hash(export):
    digest = hashlib.sha256()
    for top in (os.path.join(export, PACKAGE, "Sources"), os.path.join(export, PACKAGE, "Tests")):
        for current, directories, names in sorted(os.walk(top)):
            directories.sort()
            for name in sorted(names):
                path = os.path.join(current, name)
                digest.update(os.path.relpath(path, export).encode())
                digest.update(open(path, "rb").read())
    return digest.hexdigest()


class Patched:
    """Writes a changed copy of one source file and always restores the original."""

    def __init__(self, path, transform):
        self.path, self.transform = path, transform

    def __enter__(self):
        self.original = open(self.path, encoding="utf-8").read()
        changed = self.transform(self.original)
        if changed == self.original:
            raise SystemExit(f"a patch to {self.path} changed nothing")
        open(self.path, "w", encoding="utf-8").write(changed)

    def __exit__(self, *_):
        open(self.path, "w", encoding="utf-8").write(self.original)


def _swap_function(name, replacement):
    def transform(text):
        start = text.index(f"    static func {name}(")
        masked, _ = mask(text)
        brace = masked.index("{", start)
        end = _match_close(masked, brace)
        return text[:start] + replacement.rstrip("\n") + text[end + 1:]
    return transform


def _replace_once(old, new):
    def transform(text):
        if text.count(old) != 1:
            raise SystemExit(f"a control's patch target occurs {text.count(old)} times: {old!r}")
        return text.replace(old, new)
    return transform


def controls(swift, export, package):
    """§5.5's RC1-RC4, RC6 and RC7. Returns `(results, passed)`; RC5 is checked after the run."""
    activity = os.path.join(export, SOURCES, "Emitters/ActivitySVGRenderer.swift")
    results, ok = {}, {}
    baseline = evaluate(swift, package, export, rerun=True)
    results["RC1"] = baseline
    ok["RC1"] = (baseline.get("build") == "ok" and baseline["law"]["outcome"] == "SURVIVED"
                 and baseline["suite"]["outcome"] == "SURVIVED" and baseline["suite"]["tests"] >= 1800
                 and len(baseline["law"]["summary"]) == 3
                 and all(line.endswith("failures=0") for line in baseline["law"]["summary"]))
    again = _suite(swift, package, export, ["--filter", LAW_FILTER], LAW_LIMIT) if ok["RC1"] else {"summary": None}
    results["RC6"] = again
    # The three properties run in parallel and print as they finish, so the lines are compared as a set.
    ok["RC6"] = ok["RC1"] and sorted(again["summary"]) == sorted(baseline["law"]["summary"])
    prefix = open(os.path.join(FIXTURES, "computeRows-e36da59.swift"), encoding="utf-8").read()
    prefix = "\n".join(line for line in prefix.splitlines() if not line.startswith("//")) + "\n"
    with Patched(activity, _swap_function("computeRows", prefix)):
        results["RC2"] = evaluate(swift, package, export)
    rc2 = results["RC2"]
    ok["RC2"] = (detected(rc2, "law") and rc2["law"]["mechanism"] == "ASSERTION" and detected(rc2, "suite")
                 and any(name.startswith("L1") for name in rc2["law"]["failed"])
                 and any(name.startswith("L2") for name in rc2["law"]["failed"]))
    with Patched(activity, _replace_once("max(rows[target] ?? 0, nextRow)", "max(nextRow, rows[target] ?? 0)")):
        results["RC3"] = evaluate(swift, package, export, rerun=True)
    rc3 = results["RC3"]
    ok["RC3"] = rc3.get("build") == "ok" and not detected(rc3, "law") and not detected(rc3, "suite")
    marker = "        var rows: [Int: Int] = [:]\n        guard let start = graph.startNode else {"
    with Patched(activity, _replace_once(marker, marker.replace("[:]\n", "[:]\n        let _: Int = \"x\"\n"))):
        results["RC4"] = evaluate(swift, package, export)
    ok["RC4"] = results["RC4"].get("build") == "UNVIABLE"
    with Patched(activity, _replace_once("while let nodeId = ready.popLast() {", "while let nodeId = ready.last {")):
        results["RC7"] = evaluate(swift, package, export)
    rc7 = results["RC7"]
    ok["RC7"] = (rc7.get("build") == "ok" and rc7["law"]["mechanism"] == "TIMEOUT"
                 and rc7["suite"]["mechanism"] == "TIMEOUT" and rc7["law"]["seconds"] < LAW_LIMIT + 45
                 and rc7["suite"]["seconds"] < SUITE_LIMIT + 45 and _sweep(export))
    return results, ok


def apply(text, mutant):
    end = mutant["offset"] + mutant["length"]
    if text[mutant["offset"]:end] != mutant["original"]:
        raise SystemExit(f"{mutant['id']} no longer matches its source")
    return text[:mutant["offset"]] + mutant["replacement"] + text[end:]


def run(export, out_path):
    swift = subprocess.run(["xcrun", "--find", "swift"], capture_output=True, text=True).stdout.strip()
    version = subprocess.run([swift, "--version"], capture_output=True, text=True).stdout
    if TOOLCHAIN not in version:
        raise SystemExit(f"§5.1 runs on {TOOLCHAIN}; `xcrun --find swift` gives:\n{version}")
    export = os.path.realpath(export)
    package = os.path.join(export, PACKAGE)
    law = os.path.join(export, LAW_DESTINATION)
    os.makedirs(os.path.dirname(law), exist_ok=True)
    shutil.copyfile(os.path.join(FIXTURES, "LayeringLawTests.swift"), law)
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
    json.dump(report, open(out_path, "w", encoding="utf-8"), indent=1)
    print(json.dumps(report["summary"], indent=1) if report["summary"] else "RC5 failed or the run is incomplete — no summary")
    return 0


def law_properties(row):
    return sorted({name.split(":")[0] for name in row["law"]["failed"] if name[:2] in ("L1", "L2", "L3")})


def summarise(rows):
    """§5.6's counts. A law-only kill is listed with its mechanism, the properties that failed, and whether the
    mutated function decides layers or only places them."""
    viable = [row for row in rows if row.get("build") == "ok"]

    def ids(side):
        return {row["id"] for row in viable if detected(row, side)}

    law, suite, reduced_ = ids("law"), ids("suite"), ids("reduced")

    def describe(chosen):
        return [{"id": row["id"], "function": row["function"], "operator": row["operator"], "line": row["line"],
                 "mechanism": row["law"]["mechanism"], "properties": law_properties(row),
                 "class": "layering" if row["function"].split("/")[0] in LAYERING_LOGIC else "placement"}
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
    decisive = [entry for entry in describe(law - reduced_) if entry["mechanism"] == "ASSERTION"]
    return {"mutants": len(rows), "unviable": len(rows) - len(viable), "viable": len(viable),
            "law": len(law), "suite": len(suite), "reduced": len(reduced_), "both": len(law & suite),
            "neither": sorted(row["id"] for row in viable if row["id"] not in law | suite),
            "law_only_vs_suite": describe(law - suite), "law_only_vs_reduced": describe(law - reduced_),
            "decisive_law_only_assertion_kills": len(decisive),
            "suite_only": len(suite - law),
            "mechanisms": {side: dict(collections.Counter(row[side]["mechanism"] for row in viable
                                                          if row[side]["mechanism"]))
                           for side in ("law", "suite", "reduced")},
            "sole_killing_test": dict(sole.most_common()),
            "by_function": {name: dict(cells) for name, cells in sorted(by_function.items())}}


# ── Self-test (operators, no compiler) ────────────────────────────────────────────────────────────
SNIPPET = '''struct S {
    static func probe(_ values: [Int], flag: Bool) -> Int {
        // a + b < c && d
        let label = "x + y == z || w"
        var total = values.reduce(0, +)
        var ready: [Int] = []
        let range = 0..<values.count
        guard let first = values.first, first > 0 else { return -1 }
        if values.isEmpty || flag { return total % 7 }
        while let next = ready.popLast() {
            total += next * 2
        }
        let pick = flag ? first : total - 1
        ready.append(first)
        for value in values { ready.append(value) }
        var outgoing: [Int: [Int]] = [:]
        outgoing[first, default: []].append(total)
        print(label, range, pick)
        return first == total ? 1 : 0
    }

    static func probe2(_ a: Int, _ b: Int) -> Bool {
        let half = a / 2
        let open = true
        let shut = false
        return (a < b && half <= b) || (a >= b && half != b) || open == shut
    }

    static func wrapper(_ values: [Int]) -> Int {
        probe(values, flag: true)
    }

    static func mapped(_ values: [Int]) -> [Int] {
        values.map { probe([$0], flag: false) }
    }
}
'''
EXPECTED = [
    ("arithmetic", "+", "-"),
    ("negate-conditional", "first > 0", "!(first > 0)"),
    ("relational", ">", ">="),
    ("relational", ">", "<"),
    ("negate-conditional", "values.isEmpty || flag", "!(values.isEmpty || flag)"),
    ("logical", "||", "&&"),
    ("arithmetic", "%", "*"),
    ("arithmetic", "*", "/"),
    ("swap-ternary", " first : total - 1", " total - 1 : first"),
    ("arithmetic", "-", "+"),
    ("remove-side-effects", "ready.append(first)", ""),
    ("remove-side-effects", "ready.append(value)", ""),
    ("remove-side-effects", "outgoing[first, default: []].append(total)", ""),
    ("remove-side-effects", "print(label, range, pick)", ""),
    ("relational", "==", "!="),
    ("swap-ternary", " 1 : 0", " 0 : 1"),
]


EXPECTED2 = [
    ("arithmetic", "/", "*"), ("boolean-literal", "true", "false"), ("boolean-literal", "false", "true"),
    ("relational", "<", "<="), ("relational", "<", ">"), ("logical", "&&", "||"), ("relational", "<=", "<"),
    ("relational", "<=", ">="), ("logical", "||", "&&"), ("relational", ">=", ">"), ("relational", ">=", "<="),
    ("logical", "&&", "||"), ("relational", "!=", "=="), ("logical", "||", "&&"), ("relational", "==", "!="),
]


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
        other = {"outcome": "DETECTED", "mechanism": "ASSERTION", "failed": ["another test"] + sorted(DERIVED_NAMES)}
        result = reduced("swift", "package", "export", other)
        checks.append(("reduced: an assertion naming another test is read off, less the derived tests",
                       result["derived_from_full"] and result["failed"] == ["another test"] and not calls))
        for label, full in (("only the derived tests", {"outcome": "DETECTED", "mechanism": "ASSERTION",
                                                        "failed": sorted(DERIVED_NAMES)}),
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
        script[:] = [{"outcome": "DETECTED", "mechanism": "ASSERTION", "failed": ["x"]}]
        steady = confirmed("swift", "package", "export", FULL, {"outcome": "DETECTED", "mechanism": "ASSERTION",
                                                                 "failed": ["x"]})
        checks.append(("confirmed: an assertion that repeats stands", steady["outcome"] == "DETECTED"))
        calls.clear()
        crash = confirmed("swift", "package", "export", FULL, {"outcome": "DETECTED", "mechanism": "CRASH"})
        checks.append(("confirmed: a crash is not rerun", crash["mechanism"] == "CRASH" and not calls))
    finally:
        globals()["_suite"] = original
    return checks


def self_test():
    spans = function_spans(SNIPPET)
    found = mutants_in(SNIPPET, spans["probe"][0], "probe", "S.swift")
    second = [(m["operator"], m["original"], m["replacement"])
              for m in mutants_in(SNIPPET, spans["probe2"][0], "probe2", "S.swift")]
    returns = mutants_in(SNIPPET, spans["wrapper"][0], "wrapper", "S.swift") + \
        mutants_in(SNIPPET, spans["mapped"][0], "mapped", "S.swift")
    got = [(m["operator"], m["original"], m["replacement"]) for m in found]
    checks = [("the snippet's mutants are exactly the expected set", sorted(got) == sorted(EXPECTED)),
              ("every table rewrite, on the second function", sorted(second) == sorted(EXPECTED2))]
    if sorted(got) != sorted(EXPECTED):
        print("  missing:", sorted(set(EXPECTED) - set(got)))
        print("  extra:  ", sorted(set(got) - set(EXPECTED)))
    rewritten = [apply(SNIPPET, dict(m, id="x")) for m in found]
    checks.append(("every mutant changes the snippet", all(text != SNIPPET for text in rewritten)))
    checks.append(("no mutant touches a comment or a string literal",
                   all("// a + b < c && d" in text and '"x + y == z || w"' in text for text in rewritten)))
    checks.append(("`total += next * 2` gives `*` only: no compound-assignment mutant",
                   not any(m["original"] in ("+=", "-=") for m in found)))
    checks.append(("a body's only call, its implicit return, is never removed (a function's or a closure's)",
                   not any(m["operator"] == "remove-side-effects" for m in returns)))
    checks.append(("an ordering site gives both of the tool's rewrites",
                   sorted(r for o, x, r in got if o == "relational" and x == ">") == ["<", ">="]))
    checks += _runner_checks()
    cut = _run([sys.executable, "-c", "import sys; sys.stdout.buffer.write(b'ok \\xe2')"], os.getcwd(), 30,
               f"/nonexistent/layering-self-test-{os.getpid()}", False)
    checks.append(("a log that ends inside a character is read, not fatal", cut[1].startswith("ok ")))
    failed = [label for label, passed in checks if not passed]
    for label in failed:
        print(f"  FAIL {label}")
    print(f"layering kill-arm operator controls: {len(checks) - len(failed)}/{len(checks)} pass")
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
    if len(argv) == 3 and argv[1] == "parity":
        parity(argv[2])
        return 0
    if len(argv) == 4 and argv[1] == "run":
        return run(argv[2], argv[3])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
