#!/usr/bin/env python3
"""Do a predicate stub's draws reach both answers? — `docs/plans/predicate-outcome-reach-scope.md` (#665).

A `predicate` stub is a totality law: `_ = f(x); return true`, 100 trials at the stub's own seed. It
passes whatever `f` answers, so a pass says nothing about the inputs where `f` returns the answer
the generator never reached. The road test on SwiftUMLStudio found 7 of 10 predicate stubs that
only ever saw `false`. Before the emitter grows a check that says so, this measures how common
that is, at each stub's OWN seed and with each stub's OWN call:

- **a whole-file clone per stub**, `<Suite>_Reach`, holding three copies of the law in source
  order: `<s>_isTotal` (100 trials, the law's replica), `<s>_isTotalAgain` (100 more on the same
  seed, so it sees the subject after exactly the law's 100 calls — what a reach test emitted after
  the law would see) and `<s>_isTotalAt1000` (1,000 trials). The subject's one call in each is
  wrapped in `__reachProbe`, which appends its `Bool` answer to a FILE the test process writes
  itself, so a trap or a hang loses nothing already written (a hung `swift test` can lose all of
  its relayed output);
- **one process per clone and hashing mode**: deterministic hashing (all three tests), then two
  random-hashing runs of the first two, each killed by a substring match on the package's real
  `.build` path, never by a machine-wide `pkill`;
- **a class per reading**: BOTH, ONLY-FALSE, ONLY-TRUE, TRAPPED, HUNG, or NO READING with a reason,
  plus the flags that make a row unstable (state across the law and its replay, hash order).

The census decides, by the rule frozen in the scope, whether the reach check ships as a failure
(E), a warning (W) or not at all (NONE). Nothing here changes a census tree for longer than one
package's probe: clones, helper and logs are removed in a `finally`.

    --self-test                                                       V0, pure Python
    validate <scratch> <swift-infer> [--rand-runs 8]                  V1, the toy control
    run <census-dir> <out.jsonl> --arm <arm> [repo …]                 V2 and the census
    run --package <dir> [--package <dir> …] <out.jsonl> --arm <arm>   list mode: law_a = unknown
    oracle <out.jsonl> <stub> …                                       V2a: hand oracles vs clone bits
    sample <out.jsonl> [--arm census]                                 the stratified hand sample
    report <out.jsonl> [--judgements <json>] [--v1 pass|fail] [--v2a pass|fail] [--v2b k/10] [--json]
           [--record-decision <log>] [--arm census]                   tables and the DECISION line
    record <out.jsonl> <fixture.jsonl>                                portable paths
    crosscheck <census.jsonl> <census-A-dir> <census-B-dir> <out.jsonl> [--rerun 10]

Run it from the repository root, as `corpus_funnel.py` is. Every path is passed through
`os.path.realpath` first: a root package's `entry["package"]` is `"."`, and that `./` defeats any
path match.

**Oracles** (V1's toy and V2a): a hand-written test that re-draws a stub's inputs with
`Xoshiro(seed:)` from the stub's four seed words and generator text, calls the subject directly, and
logs through the helper's `__reachOracle(_:)`: `OPROBE|<subject>|<0|1>` per answer, optionally
grouped by `OBEGIN|<subject>|<law|again|scale>` and ended early by `OSTOP|<subject>|<pass>|<k>`.
For `oracle`, each stub's oracle lives beside it as `<stub stem>_Oracle.swift`, declaring the
suite `<Suite>_Oracle`; OPROBE lines before any OBEGIN count as the `law` pass.

⚠ Census SCRATCH trees and the toy only — never a real checkout (#560).
"""
import argparse
import collections
import contextlib
import datetime
import fractions
import glob
import hashlib
import io
import json
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import corpus_funnel as cf  # noqa: E402
import corpus_funnel_stage5 as s5  # noqa: E402
import literal_reach_check as lrc  # noqa: E402
import mutation_check as mc  # noqa: E402

SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)
TOY_DIR = os.path.join(REPO_ROOT, "fixtures", "predicate-outcome-reach", "toy")

TAGS = ("law", "again", "scale")
TRIALS = {"law": 100, "again": 100, "scale": 1000}
TEST_SUFFIX = {"law": "_isTotal", "again": "_isTotalAgain", "scale": "_isTotalAt1000"}
CLASSES = ("BOTH", "ONLY-FALSE", "ONLY-TRUE")
NO_READING = "NO READING"
CLONE_SUFFIX = "_Reach"
ORACLE_SUFFIX = "_Oracle"
HELPER_FILE = "SwiftInferReachProbe.swift"
LOG_ENV = "SWIFTINFER_REACH_LOG"
PLACEHOLDER = "@@REACH_TAG@@"
SAMPLE_SEED = 20261027
SAMPLE_SIZE = 30
JUDGEMENT_CLASSES = ("generator-miss", "relational", "constant-by-design", "undecidable-by-reading")
CENSUS_ARM = "census"
DEFAULT_DECISIONS = os.path.join(REPO_ROOT, "fixtures", "predicate-outcome-reach", "decisions.log")

# ⚠ **A trap is read from SwiftPM's own line, never from the exit status alone.** `swift test` exits 1
# however its test helper died, and a helper killed from OUTSIDE — the funnel's sweep sends SIGTERM, a
# timeout elsewhere SIGKILL — read as TRAPPED until this was measured: on both toolchains (swift.org
# 6.4.1 and Xcode's 6.4.0) SwiftPM prints `exited with unexpected signal code N` for a trap (5, with
# `Fatal error`) and for SIGILL, SIGABRT, SIGBUS, SIGSEGV, SIGHUP and SIGQUIT, and prints NOTHING for
# SIGKILL, SIGTERM, SIGINT or a subject calling `exit()`. Those, and the signals another process sends
# to stop one, are NO READING `killed-or-exited`, so a kill can neither turn a row red nor drop it from R.
_SIGNAL_LINE = re.compile(r"exited with unexpected signal code (\d+)")
OUTSIDE_SIGNALS = frozenset({1, 2, 3, 9, 15})

# Q1.6. A row whose law hung in arm A gets one short det run; a validate run gets 20 s everywhere.
DET_SECONDS, RAND_SECONDS, HUNG_LAW_SECONDS, VALIDATE_SECONDS = 180, 60, 60, 20
DEFAULT_RAND_RUNS = 2

# Files another instrument leaves in a census target. A package holding any of them is not probed:
# its build would carry suites this run did not write.
FOREIGN_FILE = re.compile(r"(_N1000|_Probe|_Lit)\.swift$|^SwiftInferMutationProbe\.swift$")
FOREIGN_MARKER = "// generator_diversity.py probe"

# The V1 subjects a toy hand stub stands in for, when `discover` does not offer them (Q1.11 step 5).
# Each is the emitted `Rules.isEven` stub with its subject replaced and its seed words kept.
HAND_SUBJECTS = ("Faults.trapsLate", "Faults.spinsLate", "Sightings.isFirstSighting", "HashOrder.firstOfTwoIsA")

HELPER = """// Written by scripts/predicate_outcome_reach.py — one line per predicate answer, and one when each
// cloned test begins, appended by the test process itself to the file SWIFTINFER_REACH_LOG names.
// A trap or a hang leaves every line written before it; output relayed through `swift test` can
// lose its unflushed tail, or all of it, when a hung run is killed.
import Foundation

private let reachProbeDescriptor: Int32 = {
    guard let path = ProcessInfo.processInfo.environment["SWIFTINFER_REACH_LOG"] else { return 2 }
    return open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
}()

private func reachProbeWrite(_ text: String) {
    let line = Array(text.utf8)
    _ = line.withUnsafeBytes { write(reachProbeDescriptor, $0.baseAddress, $0.count) }
}

func __reachBegin(_ tag: String) {
    reachProbeWrite("RBEGIN|\\(tag)\\n")
}

func __reachProbe(_ value: Bool, _ tag: String) -> Bool {
    reachProbeWrite("RPROBE|\\(tag)|\\(value ? 1 : 0)\\n")
    return value
}

/// One line of a hand-written oracle (`OPROBE|…`, `OBEGIN|…`, `OSTOP|…`), through the same descriptor.
func __reachOracle(_ line: String) {
    reachProbeWrite(line + "\\n")
}
"""


class Abort(Exception):
    """An orphaned test process or an incomplete kill: the run stops rather than measure on."""


def real(path):
    return os.path.realpath(os.path.abspath(os.path.expanduser(path)))


# ---------------------------------------------------------------- parsing a stub (Q1.3)

def law_bounds(masked, subject):
    """`(fn_start, body_open, fn_end)` of `@Test func <subject>_isTotal(` in the masked text."""
    match = re.search(r"@Test func " + re.escape(subject) + r"_isTotal\(", masked)
    if not match:
        return None
    body_open = masked.index("{", match.end())
    return match.start(), body_open, mc.matching(masked, body_open)


def expression_before(masked, end):
    """Start of the postfix expression ending just before `end`: balanced groups, names, dots."""
    index, depth = end - 1, 0
    closers, openers = ")]>", "([<"
    while index >= 0:
        char = masked[index]
        if char in closers:
            depth += 1
        elif char in openers:
            if depth == 0:
                break
            depth -= 1
        elif depth == 0 and not (char.isalnum() or char in "_.?!$"):
            break
        index -= 1
    return index + 1


def hoisted_generator(text, masked, name):
    """The text of `static let <name> = …`, up to the first blank line after it (the hoist's layout)."""
    match = re.search(r"static let " + re.escape(name) + r"\s*=\s*", masked)
    if not match:
        return None
    blank = text.find("\n\n", match.end())
    return text[match.end():blank if blank >= 0 else len(text)].strip()


def stub_generators(text, masked, start, end):
    """Each generator `.run(using: &rng)` draws from between `sample:` and `property:`, in draw order."""
    sample = masked.find("sample:", start, end)
    prop = masked.find("property:", sample if sample >= 0 else start, end)
    if sample < 0 or prop < 0:
        return []
    found = []
    for match in re.finditer(r"\.run\(\s*using:\s*&\w+\s*\)", masked[sample:prop]):
        dot = sample + match.start()
        if masked[dot - 1] == ")":
            opener = mc.matching_back(masked, dot - 1)
            before = masked[opener - 1] if opener > 0 else " "
            if not (before.isalnum() or before in "_>)]?!"):
                found.append(text[opener + 1:dot - 1].strip())  # a grouping `( … )`
                continue
        named = re.search(r"Self\.(\w+)$", masked[:dot])
        if named:
            found.append(hoisted_generator(text, masked, named.group(1)) or named.group(0))
            continue
        found.append(text[expression_before(masked, dot):dot].strip())
    return found


def string_lists(generator):
    """The `[…]` of every `Gen<String?>.element(of: [...])` in a generator, as written."""
    masked, _ = mc.mask(generator)
    lists = []
    for match in re.finditer(r"Gen<String\?>\s*\.element\(\s*of:\s*\[", masked):
        opener = match.end() - 1
        lists.append(generator[opener:mc.matching(masked, opener, "[", "]") + 1])
    return lists


def skeleton(generator):
    """The generator's outermost layer: every bracketed group emptied, whitespace collapsed.

    `zip(Gen<Int>.int(), Gen.always(x)).map { … }` → `zip().map {}`, so a rule can ask what the
    generator IS rather than what it contains somewhere inside.
    """
    masked, _ = mc.mask(generator)
    out, depth = [], 0
    for char in masked:
        if char in ")]}":
            depth -= 1
        if depth == 0:
            out.append(char)
        if char in "([{":
            depth += 1
    return re.sub(r"\s+", " ", "".join(out)).strip()


def generator_kind(generator):
    """Q1.3's kinds, first matching rule wins. Returns `(kind, literals)`.

    ⚠ **A kind names the generator's OUTERMOST shape, not a piece nested inside it.** As substrings,
    the rules read a derived `Configuration` whose enum fields draw `Gen.oneOf(Gen.always(…))` as
    `held-constant`, `zip(…, ….array(of:)).map { … }` as `array`, and `Gen<Int>.int().map { Level(…) }`
    as `stdlib-scalar` — all three are `derived`. So `held-constant` needs the whole generator to be one
    `Gen.always(…)`, `array` needs `.array(of:)` to be the outermost call (a trailing `.optional`
    allowed), `hostile-string` needs a generator that is not itself a `zip`/`.map`, and
    `stdlib-scalar` excludes any `.string(`, `.map {` or `zip(`.
    """
    lists = string_lists(generator)
    hostile = any('"[[a|b]]"' in items for items in lists)
    outer = skeleton(generator)
    composite = "zip(" in outer or re.search(r"\.map\s*\{", outer)
    if "TODO: no generator derived" in generator:
        return "unresolved", False
    if "SwiftInferSyntaxCorpus.gen(" in generator:
        return "syntax-corpus", False
    if outer == "Gen.always()":
        return "held-constant", False
    if hostile and not composite:
        return "hostile-string", any('"[[a|b]]"' not in items for items in lists)
    if re.search(r"\.array\(\)$", re.sub(r"\.optional$", "", outer)):
        return "array", False
    scalar = re.match(r"Gen<(U?Int\d*|Double|Float|Bool|Character)>", generator) or "Gen.int(" in generator
    if scalar and not re.search(r"\.string\(|\.map\s*\{|zip\(", generator):
        return "stdlib-scalar", False
    if "zip(" in generator or re.search(r"\.map\s*\{", generator) or ".gen()" in generator:
        return "derived", False
    return "other", False


def wrapped_call(region, subject):
    """`(count, call text)`: the subject's calls in a property region, and the first one's text."""
    wrapped, count = mc.wrap_subject_calls(region, [subject], PLACEHOLDER)
    match = re.search(r"__mutationProbe\((.*?), \"" + re.escape(PLACEHOLDER) + r"\"\)", wrapped, re.S)
    return count, match.group(1) if match else ""


def parse_stub_text(text):
    """Every field Q1.3 reads off one predicate stub. `no_reading` is set when it cannot be read."""
    row = {"suite": None, "test": None, "subject": None, "label": None, "source": None, "line": None,
           "seed": None, "generators": [], "kinds": [], "arity": 0, "receiver": "none",
           "isolation": "none", "inout": False, "throwing": False, "async": False,
           "literals": False, "primary_kind": None, "row_kind": "unary", "no_reading": None}
    suite = re.search(r"^struct (\w+)", text, re.M)
    row["suite"] = suite.group(1) if suite else None
    test = re.search(r"@Test func (\w+)_isTotal\(", text)
    label = re.search(r'"([^"\n]+?) failed totality at input', text)
    source = re.search(r"^// Source: (.+):(\d+)\s*$", text, re.M)
    row["label"] = label.group(1) if label else None
    if source:
        row["source"], row["line"] = source.group(1), int(source.group(2))
    if not (suite and test):
        row["no_reading"] = "no _isTotal"
        return row
    subject = test.group(1)
    row.update(test=subject + "_isTotal", subject=subject)
    masked, _ = mc.mask(text)
    bounds = law_bounds(masked, subject)
    if not bounds:
        row["no_reading"] = "no _isTotal"
        return row
    start, _body, end = bounds
    words = dict(re.findall(r"state([ABCD]): 0x([0-9A-F]{16})", text[start:end]))
    row["seed"] = "".join(words[k] for k in "ABCD") if len(words) == 4 else None
    row["generators"] = stub_generators(text, masked, start, end)
    row["arity"] = len(row["generators"])
    kinds = [generator_kind(g) for g in row["generators"]]
    row["kinds"] = [kind for kind, _ in kinds]
    row["literals"] = any(literal for _, literal in kinds)
    prop = masked.find("property:", start, end)
    region_masked = masked[prop:mc.matching(masked, masked.index("{", prop)) + 1] if prop >= 0 else ""
    region = text[prop:prop + len(region_masked)] if prop >= 0 else ""
    count, call = wrapped_call(region, subject) if region else (0, "")
    if re.match(r"(value|args\.0)\." + re.escape(subject) + r"\(", call):
        row["receiver"] = "drawn"
    elif re.search(r"\)\s*\.\s*" + re.escape(subject) + r"\(", call):
        row["receiver"] = "constructed"
    hop = re.search(r"\bawait\s+([\w.]+)\.run\s*\{", region_masked)
    if hop:
        row["isolation"] = hop.group(1)
    elif re.search(r"\bawait\b", region_masked):
        # An `await` with no hop reaches an actor's instance — drawn, constructed, or held, as in
        # `Registry.shared.holds(value)`. Only a bare `f(` or `Type.f(` has no instance to hop to, so it
        # is an `async` subject — which `PredicateTemplate` never offers.
        if row["receiver"] == "none" and re.match(r"(\w+\.)?" + re.escape(subject) + r"\(", call):
            row["async"] = True
        else:
            row["isolation"] = "actor"
    row["inout"] = bool(re.search(r"\bvar inout\d", masked[start:end]))
    row["throwing"] = "try?" in region_masked
    receiver_drawn = row["receiver"] == "drawn"
    primary = row["kinds"][1:] if receiver_drawn and len(row["kinds"]) > 1 else row["kinds"]
    row["primary_kind"] = primary[0] if primary else None
    row["row_kind"] = "relational" if row["arity"] >= 2 else "unary"
    row["wrap_count"] = count
    return row


def parse_stub(path):
    return parse_stub_text(open(path, encoding="utf-8").read())


# ---------------------------------------------------------------- the clone (Q1.4)

def clone_text(text, subject, suite):
    """`(clone, None)`, or `(None, reason)` for a stub whose law cannot be cloned faithfully."""
    masked, _ = mc.mask(text)
    bounds = law_bounds(masked, subject)
    if not bounds:
        return None, "no _isTotal"
    fn_start, body_open, fn_end = bounds
    prop = masked.find("property:", fn_start, fn_end)
    if prop < 0:
        return None, "no property closure"
    close = mc.matching(masked, masked.index("{", prop))
    wrapped, count = mc.wrap_subject_calls(text[prop:close + 1], [subject], PLACEHOLDER)
    if count != 1:
        return None, f"wrap n={count}"
    wrapped = wrapped.replace("__mutationProbe(", "__reachProbe(")
    trials = [m.start() for m in re.finditer(r"trials: 100,", masked[fn_start:fn_end])]
    if len(trials) != 1:
        return None, f"trials n={len(trials)}"
    trials_at = fn_start + trials[0]
    name_at = masked.index("func " + subject + "_isTotal(", fn_start) + len("func ")
    next_line = text[body_open + 1:].split("\n", 2)
    indent = re.match(r"\s*", next_line[1] if len(next_line) > 1 else "").group(0) or "        "
    line_start = text.rfind("\n", 0, fn_start) + 1
    lead = text[line_start:fn_start] if not text[line_start:fn_start].strip() else ""
    functions = []
    for tag in TAGS:
        label = f"{suite}{CLONE_SUFFIX}|{tag}"
        # Edits from the end of the function backwards, so every earlier index stays valid.
        body = text[:prop] + wrapped.replace(PLACEHOLDER, label) + text[close + 1:fn_end + 1]
        if tag == "scale":
            body = body[:trials_at] + "trials: 1000," + body[trials_at + len("trials: 100,"):]
        body = body[:body_open + 1] + f'\n{indent}__reachBegin("{label}")' + body[body_open + 1:]
        name = subject + TEST_SUFFIX[tag] + "("
        body = body[:name_at] + name + body[name_at + len(subject + "_isTotal("):]
        functions.append(body[fn_start:])
    clone = text[:fn_start] + ("\n\n" + lead).join(functions) + text[fn_end + 1:]
    clone, renamed = re.subn(r"^struct " + re.escape(suite) + r"\b", f"struct {suite}{CLONE_SUFFIX}",
                             clone, count=1, flags=re.M)
    if not renamed:
        return None, "no struct"
    return clone, None


def hand_stub_text(even_text, qualified, line, source="Sources/PredicateReachToy/Subjects.swift"):
    """The emitted `Rules.isEven` stub with its subject replaced by `qualified` (`Type.name`).

    Same seed words and generator; for the toy's subjects `discover` does not offer (Q1.11 step 5).
    """
    owner, name = qualified.split(".")
    suite = f"{owner}{name[0].upper()}{name[1:]}PredicateTests"
    text = re.sub(r"^// Auto-generated by .*$", "// Hand stub written by scripts/predicate_outcome_reach.py "
                  "validate: the emitted `Rules.isEven` stub, seed words kept, subject replaced.",
                  even_text, count=1, flags=re.M)
    text = re.sub(r"^// Source: .*$", f"// Source: {source}:{line}", text, count=1, flags=re.M)
    text = text.replace("struct RulesIsEvenPredicateTests", f"struct {suite}", 1)
    text = text.replace("isEven_isTotal(", f"{name}_isTotal(")
    text = text.replace("Rules.isEven(", f"{qualified}(")
    return suite, text


# ---------------------------------------------------------------- bits and classes (Q1.7, Q1.8)

def pack_bits(bits):
    """Hex, bit i = call i + 1, zero-padded to ceil(n / 4) digits. The count travels beside it."""
    value = sum(bit << index for index, bit in enumerate(bits))
    return format(value, "0{}x".format(max(1, -(-len(bits) // 4)))) if bits else ""


def unpack_bits(text, count):
    value = int(text, 16) if text else 0
    return [(value >> index) & 1 for index in range(count)]


def classify(bits):
    ones = sum(bits)
    return "BOTH" if 0 < ones < len(bits) else ("ONLY-TRUE" if bits and ones == len(bits) else "ONLY-FALSE")


def read_log(lines, clone_suite=None):
    """`(order, bits)`: the tags whose `RBEGIN` appeared, in order, and each tag's answers."""
    order, bits = [], {tag: [] for tag in TAGS}
    for line in lines:
        parts = line.strip().split("|")
        if clone_suite and len(parts) > 1 and parts[1] != clone_suite:
            continue
        if parts[0] == "RBEGIN" and len(parts) == 3 and parts[2] in TAGS:
            order.append(parts[2])
        elif parts[0] == "RPROBE" and len(parts) == 4 and parts[2] in TAGS and parts[3] in ("0", "1"):
            bits[parts[2]].append(int(parts[3]))
    return order, bits


def read_output(output, subject):
    """`(passed, failed)`: the clone tests Swift Testing reported, by tag."""
    names = {subject + TEST_SUFFIX[tag] + "()": tag for tag in TAGS}
    passed, failed = set(), set()
    for line in output.splitlines():
        hit = s5._PASSED.search(line)
        if hit and hit.group(1) in names:
            passed.add(names[hit.group(1)])
            continue
        hit = s5._FAILED.search(line)
        if hit and hit.group(1) in names:
            failed.add(names[hit.group(1)])
    return passed, failed


def exit_signal(output):
    """The signal SwiftPM says the test helper died of, or None when it printed no such line."""
    codes = [int(match.group(1)) for match in _SIGNAL_LINE.finditer(output or "")]
    return codes[-1] if codes else None


def process_status(order, bits, passed, failed, timed_out, returncode, expected, signal=None):
    """Q1.6's status table for one process. `expected` is the tags it was meant to run; `signal` is
    `exit_signal(output)`.

    Two readings the table leaves open are NO READING here, never a class:
    - **`killed-or-exited`**: the process died, not timed out, with no crash signal in SwiftPM's
      output — an outside kill or an `exit()` (see `OUTSIDE_SIGNALS`), never a trap;
    - **`stopped-after-complete`**: a timeout or a trap in a test whose count is already full. The
      subject answered every call, so the stop is not the subject's — under load it is the 180 s
      timeout landing between two tests, or after the last call.
    """
    def before_complete(tag):
        return all(len(bits[t]) == TRIALS[t] for t in TAGS[:TAGS.index(tag)])

    def stop(status, tag):
        if not before_complete(tag) or len(bits[tag]) > TRIALS[tag]:
            return {"status": NO_READING, "no_reading": "miscounted"}
        if len(bits[tag]) == TRIALS[tag]:
            return {"status": NO_READING, "no_reading": "stopped-after-complete"}
        return {"status": status, status: {"test": tag, "at": len(bits[tag]) + 1}}

    if failed:
        return {"status": NO_READING, "no_reading": "unexpected-failure"}
    if timed_out:
        if not order:
            return {"status": NO_READING, "no_reading": "no-test-began"}
        return stop("hung", order[-1])
    if all(tag in passed for tag in expected):
        if any(len(bits[tag]) != TRIALS[tag] for tag in expected):
            return {"status": NO_READING, "no_reading": "miscounted"}
        return {"status": "ran"}
    if returncode not in (0, None) and order and order[-1] not in passed:
        if signal is None or signal in OUTSIDE_SIGNALS:
            return {"status": NO_READING, "no_reading": "killed-or-exited"}
        return stop("trapped", order[-1])
    return {"status": NO_READING, "no_reading": "missing"}


def tag_class(run, tag):
    """The class one process gives one of its tests, or None when that test never ran."""
    if not run or run["status"] == NO_READING:
        return None
    if run["status"] == "ran":
        return classify(run["bits"][tag]) if run["bits"][tag] else None
    stop = run.get("trapped") or run.get("hung")
    stopped = TAGS.index(stop["test"])
    if TAGS.index(tag) < stopped:
        return classify(run["bits"][tag])
    if TAGS.index(tag) == stopped:
        return run["status"].upper()
    return None


def completed(run, tag):
    return bool(run) and run["status"] != NO_READING and len(run["bits"][tag]) == TRIALS[tag] and \
        tag_class(run, tag) in CLASSES


def readings(det, rands):
    """Classes, flags and counts for one row from its det run and the random runs that happened."""
    out = {"class100": NO_READING, "class_again": None, "class1000": NO_READING, "class1000_note": None,
           "class100_rand": [], "class_again_rand": [], "true100": None, "true1000": None,
           "first_true_at": None, "first_false_at": None, "minority100": None, "stateful": False,
           "hash_sensitive_class": False, "hash_sensitive_bits": False, "again_bits_differ": False,
           "scale_prefix_differs": False, "unstable": False}
    if not det or det["status"] == NO_READING:
        return out
    out["class100"] = tag_class(det, "law")
    law_done = completed(det, "law")
    if law_done:
        out["class_again"] = tag_class(det, "again")
    stop = det.get("trapped") or det.get("hung")
    if det["status"] == "ran":
        out["class1000"] = classify(det["bits"]["scale"])
    elif stop["test"] == "scale":
        out["class1000"] = det["status"].upper()
    elif stop["test"] == "law":
        out["class1000"] = out["class100"]
    else:
        out["class1000"], out["class1000_note"] = NO_READING, "blocked-by-again"
    for run in rands:
        out["class100_rand"].append(tag_class(run, "law") or NO_READING)
        out["class_again_rand"].append(tag_class(run, "again") if completed(run, "law") else None)
    law = det["bits"]["law"]
    if law_done:
        out["true100"] = sum(law)
        out["minority100"] = min(out["true100"], TRIALS["law"] - out["true100"])
    scale = det["bits"]["scale"]
    if det["status"] == "ran":
        out["true1000"] = sum(scale)
    if scale:
        out["first_true_at"] = scale.index(1) + 1 if 1 in scale else None
        out["first_false_at"] = scale.index(0) + 1 if 0 in scale else None
    pairs = [(out["class100"], out["class_again"])] + list(zip(out["class100_rand"], out["class_again_rand"]))
    out["stateful"] = any(again is not None and first in CLASSES and again != first for first, again in pairs)
    seen = {c for c in [out["class100"]] + out["class100_rand"] if c in CLASSES or c in ("TRAPPED", "HUNG")}
    out["hash_sensitive_class"] = len(seen) > 1
    if law_done and completed(det, "again"):
        out["again_bits_differ"] = det["bits"]["again"] != law
    if law_done and scale:
        span = min(len(scale), TRIALS["law"])
        out["scale_prefix_differs"] = scale[:span] != law[:span]
    laws = [tuple(law)] if law_done else []
    laws += [tuple(run["bits"]["law"]) for run in rands if completed(run, "law")]
    out["hash_sensitive_bits"] = len(set(laws)) > 1
    out["unstable"] = out["stateful"] or out["hash_sensitive_class"]
    return out


def run_record(run):
    """A process as the JSONL stores it: hex bits with their counts, no raw lists."""
    record = {"status": run["status"], "seconds": run.get("seconds"),
              "trapped": run.get("trapped"), "hung": run.get("hung"), "no_reading": run.get("no_reading"),
              "n": {tag: len(run["bits"][tag]) for tag in TAGS if run["bits"][tag]}}
    for tag in TAGS:
        if run["bits"][tag]:
            record[tag] = pack_bits(run["bits"][tag])
    return record


def run_bits(record, tag):
    return unpack_bits(record.get(tag, ""), (record.get("n") or {}).get(tag, 0))


# ---------------------------------------------------------------- running (Q1.6)

def build_process_pids(listing, package):
    """PIDs whose command line contains `realpath(package)/.build` — a substring, never a regex."""
    marker = os.path.join(real(package), ".build")
    pids = []
    for line in listing.splitlines():
        pid, _, command = line.strip().partition(" ")
        if marker in command and pid.isdigit():
            pids.append(pid)
    return pids


def process_listing():
    return subprocess.run(["ps", "-axo", "pid=,command="], capture_output=True, text=True).stdout


def kill_build_processes(package):
    for pid in build_process_pids(process_listing(), package):
        subprocess.run(["kill", "-9", pid], capture_output=True)


def orphans(package):
    marker = os.path.join(real(package), ".build")
    return [line.strip() for line in process_listing().splitlines() if marker in line]


def run_logged(command, package, env, log, seconds):
    """`(log_lines, status)` for one `swift test` process that writes its answers to the file `log`.

    The log is removed first (`O_APPEND` would otherwise extend an old run's log). On a timeout every
    process under the package's real `.build` is killed — a substring over `ps`, never a pgrep regex
    (N10) — then the process group; if the output still does not arrive in 30 s, the pipes are closed
    and the status says `kill_incomplete`, which every caller turns into `Abort`.
    """
    if os.path.exists(log):
        os.remove(log)
    env = dict(env)
    env[LOG_ENV] = log
    began = time.monotonic()
    proc = subprocess.Popen(command, cwd=package, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, errors="replace", env=env, start_new_session=True)
    timed_out, kill_incomplete = False, False
    try:
        output, _ = proc.communicate(timeout=seconds)
    except subprocess.TimeoutExpired:
        timed_out = True
        kill_build_processes(package)
        try:
            os.killpg(proc.pid, 9)
        except (ProcessLookupError, PermissionError):
            pass
        try:
            output, _ = proc.communicate(timeout=30)
        except subprocess.TimeoutExpired:
            kill_incomplete = True
            for stream in (proc.stdout, proc.stderr):
                if stream:
                    stream.close()
            output = ""
    lines = open(log, encoding="utf-8", errors="replace").read().splitlines() if os.path.exists(log) else []
    return lines, {"timed_out": timed_out, "returncode": proc.returncode, "output": output or "",
                   "kill_incomplete": kill_incomplete, "seconds": round(time.monotonic() - began, 2)}


def run_one(package, swift, clone_suite, subject, mode, log_dir, seconds):
    """`(log_lines, status)` for one clone suite in its own process; `mode` is det | rand<k>."""
    env = dict(s5.swift_environment(swift))
    if mode == "det":
        env["SWIFT_DETERMINISTIC_HASHING"] = "1"
    else:
        env.pop("SWIFT_DETERMINISTIC_HASHING", None)
    command = [swift, "test", "--skip-build", "--no-parallel", "--filter", r"\." + re.escape(clone_suite) + "/"]
    if mode != "det":
        command += ["--skip", r"\." + re.escape(clone_suite) + "/" + re.escape(subject) + r"_isTotalAt1000\("]
    return run_logged(command, package, env, os.path.join(log_dir, f"{clone_suite}-{mode}.log"), seconds)


def probe(package, swift, suite, subject, mode, log_dir, seconds):
    """One process, read and classified: the run dict `readings` consumes."""
    clone_suite = suite + CLONE_SUFFIX
    lines, raw = run_one(package, swift, clone_suite, subject, mode, log_dir, seconds)
    if raw["kill_incomplete"]:
        raise Abort(f"kill incomplete for {clone_suite} ({mode}) in {package}")
    order, bits = read_log(lines, clone_suite)
    passed, failed = read_output(raw["output"], subject)
    expected = TAGS if mode == "det" else ("law", "again")
    status = process_status(order, bits, passed, failed, raw["timed_out"], raw["returncode"], expected,
                            exit_signal(raw["output"]))
    return dict(status, bits=bits, seconds=raw["seconds"], order=order)


# ---------------------------------------------------------------- one package

def predicate_stubs(target):
    """The emitted predicate stubs: never this probe's clones, a V2a oracle, or another instrument's
    copy (`*_Lit`, `*_N1000`, `*_Probe`), which would otherwise each count as one more row."""
    return sorted(path for path in glob.glob(os.path.join(target, "predicate", "*.swift"))
                  if not path.endswith(CLONE_SUFFIX + ".swift") and not path.endswith(ORACLE_SUFFIX + ".swift")
                  and not FOREIGN_FILE.search(os.path.basename(path)))


def foreign_clones(target):
    found = []
    for root, _dirs, files in os.walk(target):
        for name in files:
            path = os.path.join(root, name)
            if FOREIGN_FILE.search(name):
                found.append(path)
            elif name.endswith(".swift") and FOREIGN_MARKER in open(path, encoding="utf-8", errors="ignore").read():
                found.append(path)
    return found


def remove_own_leftovers(target):
    for root, _dirs, files in os.walk(target):
        for name in files:
            if name.endswith(CLONE_SUFFIX + ".swift") or name == HELPER_FILE:
                os.remove(os.path.join(root, name))


_VERSIONS = {}


def swift_version(swift):
    if swift not in _VERSIONS:
        try:
            done = subprocess.run([swift, "--version"], capture_output=True, text=True, timeout=60,
                                  env=s5.swift_environment(swift))
            _VERSIONS[swift] = (done.stdout or done.stderr).strip().split("\n")[0]
        except (OSError, subprocess.TimeoutExpired):
            _VERSIONS[swift] = os.path.basename(swift)
    return _VERSIONS[swift]


def resolved_versions(package):
    """`{identity: version}` from the package's `Package.resolved`, or {}."""
    path = os.path.join(package, "Package.resolved")
    try:
        pins = json.load(open(path)).get("pins", [])
    except (OSError, ValueError):
        return {}
    return {pin.get("identity", ""): (pin.get("state") or {}).get("version") for pin in pins}


def git_short(path):
    done = subprocess.run(["git", "-C", path, "rev-parse", "--short", "HEAD"], capture_output=True, text=True)
    return done.stdout.strip() or None


def law_of(entry, suite, subject):
    """`law_a` for one stub, from the package's commit-2 result fields (Q1.2)."""
    if entry is None:
        return "unknown"
    if entry.get("no_verdict") or entry.get("passed") is None:
        return "no-verdict"
    key = f"{suite}.{subject}_isTotal()"
    for field, value in (("passed_tests", "passed"), ("failures", "failed"),
                         ("crashed_tests", "crashed"), ("hung_tests_all", "hung")):
        if key in (entry.get(field) or []):
            return value
    return "unknown"


def probe_package(package, swift, ctx):
    """Every predicate stub of one package as a JSONL row. `ctx` carries the run's settings."""
    package = real(package)
    target = mc.census_target_dir(package)
    if not target:
        return []
    target = real(target)
    stubs = predicate_stubs(target)
    resolved = resolved_versions(package)
    rows = []
    for stub in stubs:
        parsed = parse_stub(stub)
        parsed.pop("wrap_count", None)
        row = {"arm": ctx["arm"], "repo": ctx["repo"], "repo_sha": ctx["repo_sha"], "teaching": ctx["teaching"],
               "package": ctx["package"], "stub": os.path.relpath(stub, ctx["root"]),
               "package_dir": package, "stub_path": stub}
        row.update(parsed)
        row["law_a"] = law_of(ctx.get("entry"), row["suite"], row["subject"])
        row.update(clone=None, runs={}, swift_infer=ctx.get("swift_infer"), cli=ctx.get("cli"),
                   toolchain=swift_version(swift), kit=resolved.get("swiftpropertylaws"),
                   engine=resolved.get("swift-property-based"), package_build_seconds=None)
        row.update(readings(None, []))
        rows.append(row)
    if not rows:
        return rows

    def unread(row, clone, reason):
        row["clone"], row["no_reading"] = clone, row.get("no_reading") or reason

    if ctx.get("no_verdict"):
        for row in rows:
            unread(row, "package-no-verdict", "package-no-verdict")
        return rows
    if foreign_clones(target):
        for row in rows:
            unread(row, "foreign-clones", "foreign-clones")
        return rows
    remove_own_leftovers(target)
    written, cloned = [], []
    log_dir = tempfile.mkdtemp(prefix="reach-logs-")
    try:
        helper = os.path.join(target, HELPER_FILE)
        open(helper, "w", encoding="utf-8").write(HELPER)
        written.append(helper)
        for row in rows:
            if row["no_reading"]:
                unread(row, f"not-cloned: {row['no_reading']}", row["no_reading"])
                continue
            text, reason = clone_text(open(row["stub_path"], encoding="utf-8").read(), row["subject"], row["suite"])
            if reason:
                unread(row, f"not-cloned: {reason}", reason)
                continue
            path = row["stub_path"][:-len(".swift")] + CLONE_SUFFIX + ".swift"
            open(path, "w", encoding="utf-8").write(text)
            written.append(path)
            cloned.append(row)
        if cloned:
            began = time.monotonic()
            ok, output, broken = lrc.build_setting_aside(package, swift, suffix=CLONE_SUFFIX)
            seconds = round(time.monotonic() - began, 1)
            for row in cloned:
                row["package_build_seconds"] = seconds
                if row["suite"] in broken:
                    unread(row, f"clone-not-compiled: {broken[row['suite']]}", "clone-not-compiled")
                elif not ok:
                    unread(row, "package-build-failed", "package-build-failed")
                else:
                    measure_row(row, package, swift, log_dir, ctx)
    finally:
        for path in written:
            if os.path.exists(path):
                os.remove(path)
        shutil.rmtree(log_dir, ignore_errors=True)
    return rows


def measure_row(row, package, swift, log_dir, ctx):
    """The det run, then the random runs Q1.6 allows, into `row`."""
    row["clone"] = "built"
    hung_law = row["law_a"] == "hung"
    det_seconds = ctx.get("seconds") or (HUNG_LAW_SECONDS if hung_law else DET_SECONDS)
    det = probe(package, swift, row["suite"], row["subject"], "det", log_dir, det_seconds)
    rands = []
    det_class = tag_class(det, "law") if det["status"] != NO_READING else NO_READING
    if not hung_law and det_class in CLASSES:
        for index in range(1, ctx["rand_runs"] + 1):
            rands.append(probe(package, swift, row["suite"], row["subject"], f"rand{index}", log_dir,
                               ctx.get("seconds") or RAND_SECONDS))
    row["runs"] = {"det": run_record(det)}
    for index, run in enumerate(rands, 1):
        row["runs"][f"rand{index}"] = run_record(run)
    row.update(readings(det, rands))
    row["no_reading"] = det.get("no_reading") if det["status"] == NO_READING else None


# ---------------------------------------------------------------- run (census and list mode)

def helpers_running():
    return sum(1 for line in process_listing().splitlines() if "swiftpm-testing-helper" in line)


def write_rows(out, rows):
    with open(out, "a", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, sort_keys=True) + "\n")


def done_packages(out):
    done = set()
    if os.path.exists(out):
        for line in open(out, encoding="utf-8"):
            if line.strip():
                row = json.loads(line)
                done.add((row["repo"], row["package"]))
    return done


def package_summary(rows):
    tally = collections.Counter(row["class100"] for row in rows)
    return " ".join(f"{name} {tally[name]}" for name in ("BOTH", "ONLY-FALSE", "ONLY-TRUE", "TRAPPED", "HUNG",
                                                          NO_READING) if tally[name])


def finish_package(out, package, rows):
    write_rows(out, rows)
    left = orphans(package)
    if left:
        raise Abort(f"orphaned processes under {package}/.build:\n  " + "\n  ".join(left))


def run_census(census, out, arm, repos, rand_runs, seconds, swift_infer, cli):
    census = real(census)
    done = done_packages(out)
    for path in sorted(glob.glob(os.path.join(census, "result-*.json"))):
        result = json.load(open(path))
        repo = result.get("repo")
        if repos and repo not in repos:
            continue
        tree = real(os.path.join(census, "trees", repo))
        for entry in result.get("packages", []):
            if not entry.get("built") or (repo, entry["package"]) in done:
                continue
            package = real(os.path.join(tree, entry["package"]))
            ctx = {"arm": arm, "repo": repo, "repo_sha": git_short(tree), "teaching": repo in mc.EXCLUDED_REPOS,
                   "package": entry["package"], "root": tree, "entry": entry, "rand_runs": rand_runs,
                   "seconds": seconds, "swift_infer": swift_infer, "cli": cli,
                   "no_verdict": bool(entry.get("no_verdict")) or entry.get("passed") is None}
            began = time.monotonic()
            rows = probe_package(package, cf.toolchain(repo), ctx)
            finish_package(out, package, rows)
            print(f"{repo}/{entry['package']}: {len(rows)} predicate stubs  {package_summary(rows)}  "
                  f"({time.monotonic() - began:.0f}s)", flush=True)
    return 0


def run_packages(packages, out, arm, rand_runs, seconds, swift_infer, cli):
    done = done_packages(out)
    for directory in packages:
        package = real(directory)
        repo = os.path.basename(package)
        if (repo, ".") in done:
            continue
        ctx = {"arm": arm, "repo": repo, "repo_sha": git_short(package), "teaching": False, "package": ".",
               "root": package, "entry": None, "rand_runs": rand_runs, "seconds": seconds,
               "swift_infer": swift_infer, "cli": cli, "no_verdict": False}
        began = time.monotonic()
        rows = probe_package(package, cf.toolchain(repo), ctx)
        finish_package(out, package, rows)
        print(f"{repo}: {len(rows)} predicate stubs  {package_summary(rows)}  ({time.monotonic() - began:.0f}s)",
              flush=True)
    return 0


def command_run(args):
    others = helpers_running()
    if others:
        print(f"note: {others} swiftpm-testing-helper process(es) already running on this machine; the kill "
              f"here is scoped to each package's .build, so they are left alone", flush=True)
    try:
        if args.package:
            if len(args.rest) != 1:
                raise SystemExit("run --package <dir> … <out.jsonl> --arm <arm>")
            return run_packages(args.package, real(args.rest[0]), args.arm, args.rand_runs, args.timeout,
                                args.swift_infer, args.cli)
        if len(args.rest) < 2:
            raise SystemExit("run <census-dir> <out.jsonl> --arm <arm> [repo …]")
        census, out = args.rest[0], real(args.rest[1])
        return run_census(census, out, args.arm, set(args.rest[2:]), args.rand_runs, args.timeout,
                          args.swift_infer, args.cli)
    except Abort as error:
        print(f"ABORT: {error}", flush=True)
        return 2


# ---------------------------------------------------------------- oracles (V1's toy, V2a)

def read_oracle_log(lines):
    """`{subject: {"bits": {pass: [...]}, "stop": {pass: k}}}` from an oracle process's file log."""
    found, current = {}, {}
    for line in lines:
        parts = line.strip().split("|")
        if len(parts) < 3 or parts[0] not in ("OBEGIN", "OPROBE", "OSTOP"):
            continue
        subject = parts[1]
        entry = found.setdefault(subject, {"bits": {}, "stop": {}})
        if parts[0] == "OBEGIN":
            current[subject] = parts[2]
            entry["bits"].setdefault(parts[2], [])
        elif parts[0] == "OPROBE" and parts[2] in ("0", "1"):
            entry["bits"].setdefault(current.get(subject, "law"), []).append(int(parts[2]))
        elif parts[0] == "OSTOP" and len(parts) == 4 and parts[3].isdigit():
            entry["stop"][parts[2]] = int(parts[3])
    return found


def run_oracle_suite(package, swift, suite, log_dir, seconds=120):
    """One oracle suite in its own det-hashing process. `(found, raw)`; `Abort` on an incomplete kill."""
    env = dict(s5.swift_environment(swift), SWIFT_DETERMINISTIC_HASHING="1")
    command = [swift, "test", "--skip-build", "--no-parallel", "--filter", r"\." + re.escape(suite) + "/"]
    lines, raw = run_logged(command, package, env, os.path.join(log_dir, f"{suite}.log"), seconds)
    if raw["kill_incomplete"]:
        raise Abort(f"kill incomplete for oracle suite {suite} in {package}")
    return read_oracle_log(lines), raw


def oracle_process_ok(raw):
    """An oracle never hands a trapping or spinning draw to its subject, so its process must exit 0."""
    return bool(raw) and not raw.get("timed_out") and raw.get("returncode") == 0


def oracle_agreement(row, oracle, required=TAGS):
    """`(ok, detail)`: the clone's det bits against an oracle's, tag by tag, stops included.

    Every tag in `required` up to the clone's stop is compared, logged by the oracle or not: V1's
    oracles replay all three tests, so a tag one of them never logged is a disagreement. V2a's
    oracles replay the law only, and pass `required=("law",)`. Where the clone stopped, the oracle
    must have stopped at the same call; past it, the oracle must not have run.
    """
    det = (row.get("runs") or {}).get("det")
    if not det or det["status"] == NO_READING:
        return None, "no det reading"
    stop = det.get("trapped") or det.get("hung")
    problems = []
    for tag in TAGS:
        if tag not in required and tag not in oracle["bits"] and tag not in oracle["stop"]:
            continue
        clone = run_bits(det, tag)
        mine = oracle["bits"].get(tag, [])
        clone_stop = stop["at"] if stop and stop["test"] == tag else None
        if stop and TAGS.index(tag) > TAGS.index(stop["test"]):
            if mine or tag in oracle["stop"]:
                problems.append(f"{tag}: the oracle ran past the clone's stop")
            continue
        if clone_stop != oracle["stop"].get(tag):
            problems.append(f"{tag}: clone stops at {clone_stop}, oracle at {oracle['stop'].get(tag)}")
        if clone != mine[:len(clone)] or len(mine) != len(clone):
            first = next((i + 1 for i, (a, b) in enumerate(zip(clone, mine)) if a != b), min(len(clone), len(mine)) + 1)
            problems.append(f"{tag}: {len(clone)} clone bits vs {len(mine)} oracle bits, first difference at call {first}")
    return not problems, "; ".join(problems) or "equal"


def command_oracle(args):
    """V2a: every given stub's `<stem>_Oracle.swift` against the clone's det law bits in `out.jsonl`."""
    rows = {real(row["stub_path"]): row for row in load_rows(args.out) if row.get("stub_path")}
    by_package = collections.OrderedDict()
    for stub in args.stubs:
        stub = real(stub)
        row = rows.get(stub)
        if not row:
            print(f"{stub}: no row in {args.out}")
            return 1
        by_package.setdefault(row["package_dir"], []).append((stub, row))
    print(f"script {script_sha()}", flush=True)
    agree, total = 0, 0
    try:
        for package, items in by_package.items():
            agreed, checked = oracle_package(package, items)
            agree, total = agree + agreed, total + checked
            left = orphans(package)
            if left:
                raise Abort(f"orphaned processes under {package}/.build:\n  " + "\n  ".join(left))
    except Abort as error:
        print(f"ABORT: {error}\nV2a=fail  (the oracle run did not finish)", flush=True)
        return 2
    verdict = "pass" if total and agree == total and total >= 5 else "fail"
    print(f"V2a={verdict}  ({agree} of {total} oracles agree bit for bit; at least 5 are needed)")
    return 0 if verdict == "pass" else 1


def oracle_package(package, items):
    """`(agreed, checked)` for one package's `(stub, row)` pairs: build once, one process per oracle."""
    swift = cf.toolchain(items[0][1]["repo"])
    target = real(mc.census_target_dir(package))
    helper = os.path.join(target, HELPER_FILE)
    wrote = not os.path.exists(helper)
    log_dir = tempfile.mkdtemp(prefix="reach-oracle-")
    agreed = 0
    try:
        if wrote:
            open(helper, "w", encoding="utf-8").write(HELPER)
        ok, output = mc.build(package, swift)
        if not ok:
            errors = [line for line in output.splitlines() if "error:" in line][:6]
            print(f"{package}: build failed\n  " + "\n  ".join(errors))
            return 0, len(items)
        for _stub, row in items:
            suite = row["suite"] + ORACLE_SUFFIX
            found, raw = run_oracle_suite(package, swift, suite, log_dir)
            oracle = found.get(row["subject"])
            if not oracle or not oracle_process_ok(raw):
                print(f"  {row['stub']}: NO ORACLE READING ({suite}, exit {raw['returncode']}, "
                      f"timed out {raw['timed_out']}, {'logged' if oracle else 'nothing logged'})")
                continue
            law_only = {"bits": {"law": oracle["bits"].get("law", [])[:TRIALS["law"]]},
                        "stop": {k: v for k, v in oracle["stop"].items() if k == "law"}}
            same, detail = oracle_agreement(row, law_only, required=("law",))
            agreed += bool(same)
            print(f"  {row['stub']}: {'agree' if same else 'DISAGREE'} — {detail} "
                  f"(class100 {row['class100']}, {raw['seconds']}s)")
    finally:
        if wrote and os.path.exists(helper):
            os.remove(helper)
        shutil.rmtree(log_dir, ignore_errors=True)
    return agreed, len(items)


# ---------------------------------------------------------------- validate (V1)

def discover_accept_all(infer, tree, sources, swift, timeout=2400):
    """`discover --include-possible --interactive`, accepting every suggestion — exactly as
    `corpus_funnel.walk_repo` drives it (`:413-419`): recorded decisions cleared first, `"A\\n"`
    × 4000 on stdin, the repository's toolchain first on PATH."""
    decisions = os.path.join(tree, ".swiftinfer")
    if os.path.isdir(decisions):
        shutil.rmtree(decisions)
    done = subprocess.run([infer, "discover", "--sources", sources, "--include-possible", "--interactive"],
                          cwd=tree, input="A\n" * 4000, capture_output=True, text=True, timeout=timeout,
                          env=cf.environment(swift))
    return done.returncode, done.stdout + done.stderr


def offered_suites(transcript):
    return {os.path.basename(path)[:-len(".swift")]
            for path in re.findall(r"^Wrote (\S+/predicate/\w+\.swift)$", transcript, re.M)}


def source_line(source_text, name):
    for number, line in enumerate(source_text.split("\n"), 1):
        if re.search(r"\bfunc " + re.escape(name) + r"\(", line):
            return number
    return 0


def expectation_misses(row, expect):
    """Every expected key whose value the row does not have, as readable strings."""
    misses = []
    det = row.get("runs", {}).get("det") or {}
    for key, wanted in expect.items():
        if key == "det_trapped":
            got = det.get("trapped")
        elif key == "det_hung":
            got = det.get("hung")
        elif key == "rand_skipped":
            got = not any(name.startswith("rand") for name in row.get("runs", {}))
        elif key == "clone":
            got = row.get("clone")
        else:
            got = row.get(key)
        if got != wanted:
            misses.append(f"{key}: expected {json.dumps(wanted)}, got {json.dumps(got)}")
    return misses


def command_validate(args):
    scratch = real(args.scratch)
    infer = real(args.swift_infer)
    expected = json.load(open(os.path.join(TOY_DIR, "expected.json")))
    os.makedirs(scratch, exist_ok=True)
    toy = os.path.join(scratch, "toy")
    if os.path.exists(toy):
        shutil.rmtree(toy)
    # Only the package itself: the pins and the oracles go in at the steps that use them.
    shutil.copytree(TOY_DIR, toy, ignore=shutil.ignore_patterns(".build", ".swiftinfer", "expected.json", "README.md",
                                                                 ".gitignore", "Package.resolved", "Oracles.swift"))
    swift = cf.toolchain("toy")
    version = subprocess.run([infer, "--version"], capture_output=True, text=True).stdout.strip()
    sha = (re.search(r"\(([0-9a-f]{7,})\)", version) or re.search(r"(.*)", version)).group(1)
    clock = time.monotonic()
    timings = {}
    print(f"V1 toy at {toy}\nswift-infer {version}; {swift_version(swift)}", flush=True)

    # 1. discover, as the funnel drives it.
    began = time.monotonic()
    code, transcript = discover_accept_all(infer, toy, os.path.join(toy, "Sources", "PredicateReachToy"), swift)
    timings["discover"] = round(time.monotonic() - began, 1)
    open(os.path.join(scratch, "discover.txt"), "w", encoding="utf-8").write(transcript)
    offered = offered_suites(transcript)
    print(f"discover exit {code}: {len(offered)} predicate stubs written", flush=True)
    # 2-3. the funnel's own manifest rewrite and build, resolution pinned to the committed file.
    dirs = cf.stub_dirs(toy)
    if not dirs:
        print("V1 FAIL: discover wrote no stubs")
        return 1
    modules = [name for name, _d, kind in cf.regular_targets(toy, swift) if kind in cf.IMPORTABLE_TARGET_TYPES]
    s5.rewrite_manifest(os.path.join(toy, "Package.swift"), modules, "SwiftInferCensusTests",
                        os.path.relpath(dirs[0], toy), cf.external_dependencies(toy, swift))
    s5.verify_manifest(toy, swift)
    shutil.copy(os.path.join(TOY_DIR, "Package.resolved"), os.path.join(toy, "Package.resolved"))
    target = real(dirs[0])
    # 5. hand stubs, before the build, for any subject discover did not offer.
    predicate_dir = os.path.join(target, "predicate")
    even = os.path.join(predicate_dir, "RulesIsEvenPredicateTests.swift")
    subjects_text = open(os.path.join(toy, "Sources", "PredicateReachToy", "Subjects.swift")).read()
    hand = []
    for qualified in HAND_SUBJECTS:
        suite, text = hand_stub_text(open(even).read(), qualified,
                                     source_line(subjects_text, qualified.split(".")[1]))
        if suite not in offered:
            open(os.path.join(predicate_dir, suite + ".swift"), "w", encoding="utf-8").write(text)
            hand.append(suite)
    print(f"hand stubs written: {hand or 'none (discover offered every subject)'}", flush=True)
    began = time.monotonic()
    built = s5.build_to_fixpoint(toy, target, swift, os.path.join(scratch, "aside-toy"))
    timings["build_to_fixpoint"] = round(time.monotonic() - began, 1)
    print(f"build_to_fixpoint: built {built['built']}, set aside {built['set_aside'] or 'nothing'} "
          f"({timings['build_to_fixpoint']}s)", flush=True)
    # 4. the resolved versions are part of the toy.
    versions = resolved_versions(toy)
    got = {"SwiftPropertyLaws": versions.get("swiftpropertylaws"),
           "swift-property-based": versions.get("swift-property-based")}
    versions_ok = got == expected["resolved"]
    print(f"resolved {got}; expected {expected['resolved']}: {'ok' if versions_ok else 'MISMATCH'}", flush=True)
    # 6. the oracles, into the census target.
    shutil.copy(os.path.join(TOY_DIR, "Oracles.swift"), os.path.join(target, "Oracles.swift"))
    # 7. the probe itself, in list mode.
    out = os.path.join(scratch, "v1.jsonl")
    if os.path.exists(out):
        os.remove(out)
    gate_c, abort = True, None
    began = time.monotonic()
    try:
        run_packages([toy], out, "toy", args.rand_runs, VALIDATE_SECONDS, sha, None)
    except Abort as error:
        gate_c, abort = False, str(error)
    timings["run"] = round(time.monotonic() - began, 1)
    rows = {row["suite"]: row for row in load_rows(out)} if os.path.exists(out) else {}
    # 8. the oracles, in their own det process, with the helper back for the build.
    helper = os.path.join(target, HELPER_FILE)
    log_dir = tempfile.mkdtemp(prefix="reach-oracle-")
    began = time.monotonic()
    found, raw, ok, output = {}, {}, False, ""
    try:
        open(helper, "w", encoding="utf-8").write(HELPER)
        ok, output = mc.build(toy, swift)
        if ok:
            found, raw = run_oracle_suite(toy, swift, "PredicateReachOracles", log_dir, seconds=300)
    except Abort as error:
        gate_c, abort = False, "; ".join(filter(None, [abort, str(error)]))
    finally:
        if os.path.exists(helper):
            os.remove(helper)
        shutil.rmtree(log_dir, ignore_errors=True)
    timings["oracles"] = round(time.monotonic() - began, 1)
    if not ok:
        print("oracle build failed:\n  " + "\n  ".join([line for line in output.splitlines() if "error:" in line][:6]))
    # The oracle process itself must finish cleanly: it never hands a trap or a spin to a subject.
    oracle_ok = oracle_process_ok(raw)
    if ok and not oracle_ok:
        print(f"oracle process: exit {raw.get('returncode')}, timed out {raw.get('timed_out')}")
    left = orphans(toy)
    gate_c = gate_c and not left

    # The gate.
    gate_a, gate_b, lines = oracle_ok, True, []
    readings_notes = []
    m_counts = expected.get("readings", {}).get("counts", {})
    for suite, spec in expected["subjects"].items():
        row = rows.get(suite)
        if not row:
            gate_b = False
            lines.append(f"  {suite:42} MISSING from the run")
            continue
        oracle = found.get(row["subject"])
        det = row.get("runs", {}).get("det")
        if det and det["status"] != NO_READING:
            if oracle is None:
                same, detail = False, "no oracle reading"
            else:
                same, detail = oracle_agreement(row, oracle)
            gate_a = gate_a and bool(same)
        else:
            same, detail = None, "det gave no reading"
        misses = expectation_misses(row, spec["expect"])
        if spec.get("offered", True) != (suite in offered):
            misses.append(f"offered: expected {spec.get('offered', True)}, got {suite in offered}")
        gate_b = gate_b and not misses
        rand = [k for k in row.get("runs", {}) if k.startswith("rand")]
        position = det.get("trapped") or det.get("hung") if det else None
        lines.append(f"  {suite:42} {row['class100']:10} again {str(row['class_again']):10} "
                     f"1000 {row['class1000']:10} rand {len(rand)}"
                     f"{'  stop ' + position['test'] + '@' + str(position['at']) if position else ''}  "
                     f"oracle {'=' if same else ('—' if same is None else 'DIFFERS')}"
                     f"{'' if same in (True, None) else ' (' + detail + ')'}"
                     f"{'  EXPECTATION: ' + '; '.join(misses) if misses else ''}")
        if suite in m_counts and m_counts[suite] != [row.get("true100"), row.get("true1000")]:
            readings_notes.append(f"  {suite}: M read {m_counts[suite]}, this run "
                                  f"[{row.get('true100')}, {row.get('true1000')}]")
    for suite in sorted(set(rows) - set(expected["subjects"])):
        lines.append(f"  {suite:42} not in expected.json")
        gate_b = False
    print("\n".join(lines))
    process_seconds = [run["seconds"] for row in rows.values() for run in row.get("runs", {}).values()
                       if run.get("seconds") is not None]
    det_seconds = sorted(row["runs"]["det"]["seconds"] for row in rows.values() if "det" in row.get("runs", {}))
    rand_seconds = sorted(run["seconds"] for row in rows.values() for name, run in row.get("runs", {}).items()
                          if name.startswith("rand"))
    print(f"\nprocesses: {len(process_seconds)}, {sum(process_seconds):.0f}s in all; det median "
          f"{median(det_seconds)}s (max {max(det_seconds or [0])}s); rand median {median(rand_seconds)}s "
          f"(max {max(rand_seconds or [0])}s); oracle process {raw.get('seconds') if found else '—'}s")
    print(f"stages: {timings}; wall {time.monotonic() - clock:.0f}s")
    if readings_notes:
        print("readings that differ from M's (provenance notes, not failures):\n" + "\n".join(readings_notes))
    else:
        print("readings: every true100/true1000 equals M's")
    print(f"\ngate (a) oracle agreement, bit for bit, every test up to the clone's stop: "
          f"{'pass' if gate_a else 'FAIL'}{'' if oracle_ok else '  (the oracle process did not exit 0)'}")
    print(f"gate (b) every class and flag in expected.json: {'pass' if gate_b else 'FAIL'}")
    print(f"gate (c) no orphan, no kill_incomplete: {'pass' if gate_c else 'FAIL'}"
          f"{'  (' + abort + ')' if abort else ''}{'  orphans: ' + '; '.join(left) if left else ''}")
    print(f"resolved versions: {'pass' if versions_ok else 'FAIL'}")
    verdict = "pass" if gate_a and gate_b and gate_c and versions_ok and built["built"] else "fail"
    script = script_sha()
    json.dump({"V1": verdict, "gate_a": gate_a, "gate_b": gate_b, "gate_c": gate_c, "versions": got,
               "swift_infer": version, "script": script, "rows": len(rows), "offered": sorted(offered),
               "hand_stubs": hand, "timings": timings, "oracle_process": {k: raw.get(k) for k in
                                                                          ("returncode", "timed_out", "seconds")}},
              open(os.path.join(scratch, "v1-verdict.json"), "w"), indent=1)
    print(f"script {script}")
    print(f"V1={verdict}")
    return 0 if verdict == "pass" else 1


def median(values):
    values = sorted(values)
    if not values:
        return None
    middle = len(values) // 2
    return values[middle] if len(values) % 2 else round((values[middle - 1] + values[middle]) / 2, 2)


# ---------------------------------------------------------------- sample (Q1.10)

def load_rows(path):
    return [json.loads(line) for line in open(path, encoding="utf-8") if line.strip()]


def in_r(row):
    return not row.get("teaching") and row.get("law_a") == "passed" and row.get("class100") in CLASSES


def reds(rows):
    return [row for row in rows if in_r(row) and row["class100"] in ("ONLY-FALSE", "ONLY-TRUE")]


def allocate(counts, size):
    """Largest-remainder allocation of `size` over `{repo: reds}`; remainder ties to the earlier name.

    In integers: as floats, three remainders of exactly 1/3 came out .33333333333333326,
    .3333333333333333 and .33333333333333215, so rounding error, not the name, broke the tie.
    """
    total = sum(counts.values())
    if not total:
        return {}
    allocation = {repo: size * count // total for repo, count in counts.items()}
    remainder = {repo: size * count % total for repo, count in counts.items()}
    left = size - sum(allocation.values())
    for repo in sorted(counts, key=lambda repo: (-remainder[repo], repo))[:left]:
        allocation[repo] += 1
    return allocation


def draw_sample(rows):
    """`(sample, allocation, red counts)`: Q1.10's frozen draw."""
    red = reds(rows)
    counts = collections.Counter(row["repo"] for row in red)
    allocation = allocate(counts, min(SAMPLE_SIZE, len(red)))
    rng = random.Random(SAMPLE_SEED)
    sample = []
    for repo in sorted(counts):
        pool = sorted((row for row in red if row["repo"] == repo), key=lambda row: row["stub"])
        sample += rng.sample(pool, allocation.get(repo, 0))
    # `judgements.json` is keyed by `stub`, a path relative to its repository's tree: two sampled rows with
    # one path would silently share a verdict.
    shared = sorted(stub for stub, count in collections.Counter(row["stub"] for row in sample).items() if count > 1)
    if shared:
        raise SystemExit(f"hand sample: {len(shared)} stub path(s) sampled from more than one repository, which "
                         f"judgements.json cannot tell apart: {', '.join(shared[:3])}")
    return sample, allocation, dict(counts)


def cbd_share(sample, judgements, red_counts):
    """`(weighted share, k, n)` of constant-by-design, or `(None, k, n)` when a sampled row is unjudged.

    The share is an exact `Fraction`: §7 drops E to W only when it is strictly above 1/2, and as a
    float an exact 1/2 (reds 48 and 192, allocation 6 and 24, 1 and 14 constant-by-design) summed to
    0.5000000000000001. With no reds there is nothing to judge: n = 0 and the share is 0 (§5).
    A class other than §5's four is refused, so a misspelling cannot count as judged.
    """
    if not sample:
        return fractions.Fraction(0), 0, 0
    per_repo = collections.defaultdict(lambda: [0, 0])
    judged = 0
    for row in sample:
        verdict = (judgements.get(row["stub"]) or {}).get("class")
        if not verdict:
            continue
        if verdict not in JUDGEMENT_CLASSES:
            raise SystemExit(f"judgement for {row['stub']}: class {verdict!r} is not one of {', '.join(JUDGEMENT_CLASSES)}")
        judged += 1
        per_repo[row["repo"]][1] += 1
        per_repo[row["repo"]][0] += verdict == "constant-by-design"
    k = sum(c for c, _ in per_repo.values())
    if judged < len(sample):
        return None, k, judged
    weight = sum(red_counts[repo] for repo, (_, n) in per_repo.items() if n)
    share = sum((fractions.Fraction(red_counts[repo], weight) * fractions.Fraction(c, n)
                 for repo, (c, n) in per_repo.items() if n), fractions.Fraction(0))
    return share, k, judged


def source_span(row, limit=40):
    path = row.get("source") or ""
    if not os.path.isabs(path):
        path = os.path.join(row.get("package_dir") or "", path)
    try:
        source = open(path, encoding="utf-8").read()
    except OSError:
        return f"(source not readable: {path})"
    lines = source.split("\n")
    first = max(0, (row.get("line") or 1) - 1)
    span = mc.subject_body(source, row["line"], row["subject"]) if row.get("line") else None
    last = source.count("\n", 0, span[1]) + 1 if span else first + 12
    return "\n".join(f"{number + 1:>6}  {lines[number]}" for number in range(first, min(last, first + limit, len(lines))))


def arm_rows(rows, arm):
    """The rows of one arm. R is defined over census-arm rows (§7), so `report` and `sample` default
    to `census`: a control or toy row enters the rule, or the hand sample, only when named."""
    kept = [row for row in rows if row.get("arm") == arm]
    others = collections.Counter(row.get("arm") for row in rows if row.get("arm") != arm)
    if others:
        print(f"note: --arm {arm}: ignoring {sum(others.values())} row(s) of {dict(others)}", file=sys.stderr)
    return kept


def command_sample(args):
    rows = arm_rows(load_rows(args.out), args.arm)
    sample, allocation, counts = draw_sample(rows)
    print(f"{len(sample)} of {sum(counts.values())} reds in R; allocation {dict(sorted(allocation.items()))}")
    for row in sample:
        print(f"\n## {row['repo']} — {row['stub']}  [{row['class100']} at 100, {row['class1000']} at 1,000; "
              f"{row['row_kind']}, {row['primary_kind']}]")
        print(f"   {row['label']}  ({row['source']}:{row['line']})")
        for index, generator in enumerate(row.get("generators") or []):
            print(f"   generator {index}: " + " ".join(generator.split())[:400])
        print(source_span(row))
    if args.write_template:
        if os.path.exists(args.write_template):
            print(f"\n{args.write_template} exists; not overwritten")
        else:
            json.dump({row["stub"]: {"class": "", "note": ""} for row in sample},
                      open(args.write_template, "w"), indent=1, sort_keys=True)
            print(f"\ntemplate written to {args.write_template}")
    return 0


# ---------------------------------------------------------------- report and the DECISION (Q1.9, Q2.3)

def band(value):
    """`E` ≥ 0.80, `W` ≥ 0.50, else `NONE` — NONE < W < E."""
    return "E" if value >= 0.80 else "W" if value >= 0.50 else "NONE"


BAND_ORDER = {"NONE": 0, "W": 1, "E": 2}


def decide(g, g_loo, r_size, no_reading, compiled_nt, instrument_ok, cbd, prior=()):
    """Q2.3's frozen rule. `prior` maps each NOT-DECISIVE cause to the number of fix rounds already
    recorded for it (`fix_rounds`); a list of DECISION tokens, one per round, is accepted too.

    ⚠ **An input §7 cannot compute is a failed gate, never a band** (scope §0): when R holds one
    repository, G_loo is G over nothing, and the rule's answer is NOT-DECISIVE(instrument), counted
    toward the two fix rounds — not NONE, which would be an amendment to §7.
    """
    rounds = prior if isinstance(prior, dict) else collections.Counter(prior)

    def instrument():
        return "NONE(instrument)" if rounds.get("NOT-DECISIVE(instrument)", 0) >= 2 else "NOT-DECISIVE(instrument)"

    if not instrument_ok:
        return instrument()
    if r_size < 100:
        return "NONE(population)"
    if no_reading > 0.10 * compiled_nt:
        return "NONE(no-reading)" if rounds.get("NOT-DECISIVE(no-reading)", 0) >= 1 else "NOT-DECISIVE(no-reading)"
    if g is None or g_loo is None:
        return instrument()
    chosen = min(band(g), band(g_loo), key=BAND_ORDER.get)
    if chosen == "E" and cbd is not None and cbd > fractions.Fraction(1, 2):
        chosen = "W"  # a red that is not the user's to fix must not fail CI
    return chosen


def largest_repo(rows):
    counts = collections.Counter(row["repo"] for row in rows)
    return min(counts, key=lambda repo: (-counts[repo], repo)) if counts else None


def is_green(row):
    return row["class100"] == "BOTH" and not row.get("unstable")


def share(rows):
    return sum(is_green(row) for row in rows) / len(rows) if rows else None


def population(rows):
    """The numbers the rule reads, and the lists every table needs."""
    nt = [row for row in rows if not row.get("teaching")]
    r_rows = [row for row in nt if in_r(row)]
    largest = largest_repo(r_rows)
    loo = [row for row in r_rows if row["repo"] != largest]
    readable = [row for row in nt if row.get("class100") in CLASSES]
    unread = [row for row in nt if row.get("class100") == NO_READING]
    return {"nt": nt, "R": r_rows, "largest": largest, "loo": loo, "readable": readable, "unread": unread,
            "G": share(r_rows), "G_loo": share(loo), "G_all": share(readable),
            "green": sum(is_green(row) for row in r_rows)}


def pct(value):
    return "n/a" if value is None else f"{100 * float(value):.1f}%"


def decision_line(pop, verdict, cbd, k, n, v1, v2a, v2b, digest):
    hand = "n/a" if cbd is None else f"{pct(cbd)} weighted ({k}/{n})"
    no_reading = len(pop["unread"]) / len(pop["nt"]) if pop["nt"] else 0
    return (f"DECISION: {verdict}  G={pct(pop['G'])} ({pop['green']}/{len(pop['R'])})  "
            f"G_loo={pct(pop['G_loo'])} without {pop['largest']}  G_all={pct(pop['G_all'])}  |R|={len(pop['R'])}  "
            f"unstable={sum(bool(row.get('unstable')) for row in pop['R'])}  no_reading={pct(no_reading)} of compiled  "
            f"hand: constant-by-design {hand}  V1={v1}  V2a={v2a}  V2b={v2b}  input={digest}")


BUCKETS = ("BOTH", "ONLY-FALSE", "ONLY-TRUE", "TRAPPED", "HUNG")


def bucket_table(title, groups, field):
    print(f"\n{title}")
    print(f"  {'population':28}{'rows':>6}" + "".join(f"{name:>12}" for name in BUCKETS) + f"{'NO READING':>12}")
    for name, rows in groups:
        tally = collections.Counter(row.get(field) for row in rows)
        print(f"  {name:28}{len(rows):>6}" + "".join(f"{tally[b]:>12}" for b in BUCKETS) + f"{tally[NO_READING]:>12}")
        reasons = collections.Counter((row.get("no_reading") or row.get("class1000_note") or "?")
                                      for row in rows if row.get(field) == NO_READING)
        if reasons:
            print("      NO READING: " + ", ".join(f"{reason} {count}" for reason, count in reasons.most_common()))


def breakdown(title, rows, key):
    print(f"\n{title}")
    groups = collections.defaultdict(list)
    for row in rows:
        groups[str(row.get(key))].append(row)
    for name, members in sorted(groups.items(), key=lambda item: (-len(item[1]), item[0])):
        print(f"  {name:28}{len(members):>6} rows  green {sum(is_green(r) for r in members):>5}  "
              f"G {pct(share(members)):>7}  share of R {pct(len(members) / len(rows) if rows else None):>7}")


_RECORDED = re.compile(r"^\S+  script (\S+)  (DECISION: (\S+) .* input=(\w+))\s*$")


def recorded_decisions(path):
    """`[(script, decision token, input digest, line without its timestamp)]` from a decisions log."""
    if not path or not os.path.exists(path):
        return []
    found = []
    for line in open(path, encoding="utf-8"):
        match = _RECORDED.match(line.rstrip("\n"))
        if match:
            found.append((match.group(1), match.group(3), match.group(4),
                          f"script {match.group(1)}  {match.group(2)}"))
    return found


def fix_rounds(recorded, script, digest):
    """`{NOT-DECISIVE cause: rounds}`: the distinct `(script, input)` pairs that recorded it.

    ⚠ **A round is a re-run after a fix, not a recorded line.** Recording the same report twice (say
    once as text and once with `--json`) wrote two lines with one script and one input, and the second
    turned NOT-DECISIVE(no-reading) into the terminal NONE(no-reading) with no fix made. So a pair is
    counted once, and the current run's own pair is not a round at all.
    """
    pairs = collections.defaultdict(set)
    for line_script, token, line_digest, _line in recorded:
        if token.startswith("NOT-DECISIVE(") and (line_script, line_digest) != (script, digest):
            pairs[token].add((line_script, line_digest))
    return {token: len(seen) for token, seen in pairs.items()}


def script_sha():
    """The script's git SHA, with `-dirty-<content hash>` for an uncommitted edit, so two different
    working-tree states never record the same SHA."""
    sha = git_short(SCRIPT_DIR) or "unknown"
    dirty = subprocess.run(["git", "-C", SCRIPT_DIR, "status", "--porcelain", "--", os.path.basename(__file__)],
                           capture_output=True, text=True).stdout.strip()
    if not dirty:
        return sha
    return f"{sha}-dirty-{hashlib.sha256(open(os.path.realpath(__file__), 'rb').read()).hexdigest()[:8]}"


def arm_invariants(census):
    """Q5.4's arm-A invariants over a census directory's result files. Returns the violations."""
    problems = []
    for path in sorted(glob.glob(os.path.join(real(census), "result-*.json"))):
        result = json.load(open(path))
        repo = result.get("repo")
        for key, value in result.items():
            if key.startswith("reach_") and value:
                problems.append(f"{repo}: {key} = {value}")
        for entry in result.get("packages", []):
            where = f"{repo}/{entry.get('package')}"
            names = [n for field in ("passed_tests", "failures", "crashed_tests", "hung_tests_all")
                     for n in entry.get(field) or []]
            if any(n.endswith("_reachesBothOutcomes()") for n in names):
                problems.append(f"{where}: a reach name in a law list")
            if entry.get("exhausted"):
                problems.append(f"{where}: exhausted")
            if (entry.get("resumes") or 0) > 30:
                problems.append(f"{where}: resumes {entry['resumes']}")
            if entry.get("built") and "run_seconds" not in entry:
                problems.append(f"{where}: no run_seconds")
            if entry.get("built") and entry.get("passed_tests") is not None and entry.get("passed") is not None:
                stubs = mc.census_target_dir(os.path.join(real(census), "trees", repo, entry["package"]))
                if stubs:
                    check = {}
                    cf.record_passes(check, {"passed": entry["passed_tests"]}, stubs)
                    for field in ("passed", "passed_behaviour", "passed_does_not_crash"):
                        if check[field] != entry.get(field):
                            problems.append(f"{where}: record_passes gives {field} {check[field]}, "
                                            f"stored {entry.get(field)}")
    return problems


def command_report(args):
    rows = arm_rows(load_rows(args.out), args.arm)
    arms = sorted({row.get("arm") for row in rows})
    digest = hashlib.sha256(open(args.out, "rb").read()).hexdigest()[:12]
    pop = population(rows)
    teaching = [row for row in rows if row.get("teaching")]
    judgements = json.load(open(args.judgements)) if args.judgements else {}
    sample, _allocation, red_counts = draw_sample(rows)
    # With no reds there is nothing to judge: cbd_share is 0 without a judgements file (§5).
    cbd, k, n = cbd_share(sample, judgements, red_counts) if args.judgements or not sample else (None, 0, 0)
    v0 = self_test(quiet=True) == 0
    instrument_ok = v0 and args.v1 == "pass" and args.v2a == "pass"
    # The earlier lines decide the terminal outcomes, so they are read whether or not this run records:
    # a report that ignored them printed NOT-DECISIVE after the log already held the terminal NONE.
    log = args.record_decision or DEFAULT_DECISIONS
    recorded = recorded_decisions(log)
    script = script_sha()
    no_reading = len(pop["unread"])
    verdict = decide(pop["G"], pop["G_loo"], len(pop["R"]), no_reading, len(pop["nt"]), instrument_ok, cbd,
                     fix_rounds(recorded, script, digest))
    line = decision_line(pop, verdict, cbd, k, n, args.v1 or "unknown", args.v2a or "unknown",
                         args.v2b or "unknown", digest)
    seconds = sum(run.get("seconds") or 0 for row in rows for run in (row.get("runs") or {}).values())
    builds = {}
    for row in rows:
        if row.get("package_build_seconds") is not None:
            builds[(row["repo"], row["package"])] = row["package_build_seconds"]
    if args.json:
        summary = {"arms": arms, "rows": len(rows), "R": len(pop["R"]), "green": pop["green"], "G": pop["G"],
                   "G_loo": pop["G_loo"], "largest": pop["largest"], "G_all": pop["G_all"],
                   "compiled_nt": len(pop["nt"]), "no_reading": no_reading,
                   "cbd_share": None if cbd is None else float(cbd),
                   "cbd_share_exact": None if cbd is None else str(cbd), "hand": [k, n],
                   "V0": "pass" if v0 else "fail", "decision": verdict, "decision_line": line,
                   "decisions_log": log, "script": script,
                   "class100": collections.Counter(row.get("class100") for row in pop["nt"]),
                   "class1000": collections.Counter(row.get("class1000") for row in pop["nt"]),
                   "process_seconds": round(seconds, 1), "build_seconds": round(sum(builds.values()), 1),
                   "input": digest}
        print(json.dumps(summary, indent=1, sort_keys=True))
    else:
        print_report(rows, pop, teaching, arms, seconds, builds, args)
        print(f"\n{len(recorded)} earlier decision line(s) read from {log}; script {script}")
        print("\n" + line)
    if args.record_decision:
        return record_decision(args, recorded, script, verdict, cbd, line)
    return 0


def record_decision(args, recorded, script, verdict, cbd, line):
    """Append the DECISION line, or say why not. Only a census-arm decision is recorded, and never the
    same line twice in a row: a repeat is the same run, not a fix round."""
    refusal = None
    if args.arm != CENSUS_ARM:
        refusal = f"only a --arm {CENSUS_ARM} decision is recorded (this is --arm {args.arm})"
    elif not (args.v1 and args.v2a):
        refusal = "--v1 and --v2a are required to record a decision"
    elif verdict == "E" and cbd is None:
        refusal = "an E decision needs the hand check (--judgements), complete"
    if refusal:
        print(f"not recorded: {refusal}", file=sys.stderr)
        return 1
    entry = f"script {script}  {line}"
    if recorded and recorded[-1][3] == entry:
        print(f"not recorded: identical, but for its timestamp, to the last line of {args.record_decision}")
        return 0
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    with open(args.record_decision, "a", encoding="utf-8") as handle:
        handle.write(f"{stamp}  {entry}\n")
    print(f"recorded in {args.record_decision}")
    return 0


def print_report(rows, pop, teaching, arms, seconds, builds, args):
    print(f"{len(rows)} rows, arms {arms}; non-teaching {len(pop['nt'])}, teaching {len(teaching)}")
    groups = [("non-teaching R (decides)", pop["R"]), ("non-teaching, all (G_all)", pop["nt"]),
              ("teaching", teaching), ("all", rows), (f"R without {pop['largest']}", pop["loo"])]
    bucket_table("At 100 trials (det `law`):", groups, "class100")
    bucket_table("At 1,000 trials (det `scale`):", groups, "class1000")
    breakdown("Per repository (R):", pop["R"], "repo")
    for key in ("primary_kind", "row_kind", "receiver", "isolation"):
        breakdown(f"Per {key} (R):", pop["R"], key)
    print("\n100 → 1,000 (R):")
    matrix = collections.Counter((row["class100"], row.get("class1000")) for row in pop["R"])
    for (first, second), count in sorted(matrix.items()):
        print(f"  {first:12} → {str(second):12} {count}")
    red = [row for row in pop["R"] if row["class100"] in ("ONLY-FALSE", "ONLY-TRUE")]
    reached = [row for row in red if row.get("class1000") == "BOTH"]
    firsts = sorted((row.get("first_true_at") if row["class100"] == "ONLY-FALSE" else row.get("first_false_at"))
                    for row in reached)
    print(f"  red at 100: {len(red)}; BOTH at 1,000 (the rare region): {len(reached)}; first other answer at "
          f"calls {firsts[:20]}{' …' if len(firsts) > 20 else ''}")
    for field in ("unstable", "stateful", "hash_sensitive_class"):
        listed = [row for row in pop["nt"] if row.get(field)]
        print(f"\n{field}: {len(listed)}")
        for row in listed[:25]:
            print(f"  {row['repo']}  {row['stub']}  {row['class100']} / again {row.get('class_again')} / "
                  f"rand {row.get('class100_rand')}")
    print("\nbit flags (non-teaching): " + ", ".join(
        f"{field} {sum(bool(row.get(field)) for row in pop['nt'])}"
        for field in ("again_bits_differ", "scale_prefix_differs", "hash_sensitive_bits")))
    minority = collections.Counter(min(row.get("minority100") or 0, 50) for row in pop["R"] if row["class100"] == "BOTH")
    print("minority100 over BOTH rows in R: " + ", ".join(f"{key}:{value}" for key, value in sorted(minority.items())))
    print("\nconsistency:")
    readable_not_passed = collections.Counter(row.get("law_a") for row in pop["readable"] if row.get("law_a") != "passed")
    print(f"  readable rows whose law did not pass in arm A: {dict(readable_not_passed)}")
    trapped = collections.Counter(row.get("law_a") for row in rows if row.get("class100") == "TRAPPED")
    crashed = collections.Counter(row.get("class100") for row in rows if row.get("law_a") == "crashed")
    print(f"  TRAPPED at 100 by law_a: {dict(trapped)}")
    print(f"  law_a crashed by class100: {dict(crashed)}")
    print(f"  throwing {sum(bool(r.get('throwing')) for r in rows)}, async {sum(bool(r.get('async')) for r in rows)} "
          f"(both expected 0)")
    print(f"  process time {seconds:.0f}s over {sum(len(r.get('runs') or {}) for r in rows)} processes; "
          f"clone builds {sum(builds.values()):.0f}s over {len(builds)} packages")
    if args.expected_rows and rows:
        projected = seconds * args.expected_rows / len(rows) + (
            sum(builds.values()) / max(1, len(builds)) * (args.expected_packages or len(builds)))
        print(f"  projected census time = {seconds:.0f}s × ({args.expected_rows} / {len(rows)}) + builds "
              f"= {projected / 3600:.2f} h")
    if args.census:
        problems = arm_invariants(args.census)
        print(f"\narm-A invariants over {args.census}: {'all hold' if not problems else str(len(problems)) + ' violated'}")
        for problem in problems[:40]:
            print(f"  {problem}")


# ---------------------------------------------------------------- record

def command_record(args):
    """The run as a portable fixture: no absolute path, sorted keys, one row per stub."""
    out = []
    for row in load_rows(args.out):
        row = dict(row)
        row.pop("package_dir", None)
        row.pop("stub_path", None)
        source = row.get("source")
        if source and os.path.isabs(source) and "trees" in source.split(os.sep):
            _repo, row["source"], _root = mc.portable(source)
        absolute = [key for key, value in row.items() if isinstance(value, str) and value.startswith("/")]
        if absolute:
            raise SystemExit(f"{row.get('stub')}: absolute path left in {absolute}")
        out.append(row)
    with open(args.fixture, "w", encoding="utf-8") as handle:
        for row in out:
            handle.write(json.dumps(row, sort_keys=True) + "\n")
    print(f"{len(out)} rows written to {args.fixture}")
    return 0


# ---------------------------------------------------------------- crosscheck (Q6.4, E or W only)

def strip_reach(text):
    """A predicate stub with every #665 addition removed: the `// Reach:` header, the reach test, and
    the `reachNote` helper (Q6.4 step 1, parts 1-2)."""
    lines, out, skipping = text.split("\n"), [], False
    for line in lines:
        if line.startswith("// Reach:"):
            skipping = True
            continue
        if skipping and re.match(r"//\s{2,}", line):
            continue
        skipping = False
        out.append(line)
    text = "\n".join(out)
    while True:
        masked, _ = mc.mask(text)
        match = re.search(r"@Test func \w+_reachesBothOutcomes\(|(?:nonisolated )?(?:private )?static func reachNote\(",
                          masked)
        if not match:
            return text
        start = text.rfind("\n", 0, match.start()) + 1
        end = mc.matching(masked, masked.index("{", match.end()))
        tail = text.find("\n", end)
        text = text[:start] + text[tail + 1 if tail >= 0 else len(text):]


def dehoist(text):
    """Every `Self.<name>` replaced by its `static let <name> = …` text, the declarations removed."""
    masked, _ = mc.mask(text)
    declarations = {}
    for match in re.finditer(r"^[ \t]*(?:nonisolated )?(?:private )?static let (\w+)\s*=\s*", masked, re.M):
        blank = text.find("\n\n", match.end())
        end = blank if blank >= 0 else len(text)
        declarations[match.group(1)] = (match.start(), end, text[match.end():end].strip())
    for name, (start, end, _expression) in sorted(declarations.items(), key=lambda item: -item[1][0]):
        text = text[:start] + text[end:]
    for name, (_start, _end, expression) in declarations.items():
        text = re.sub(r"\bSelf\." + re.escape(name) + r"\b", lambda _m, e=expression: "(" + e + ")", text)
    return text


def normalised_predicate(text):
    """Q6.4 step 1's predicate normalisation: reach parts dropped, de-hoisted, whitespace collapsed.

    A de-hoisted generator is parenthesised the same way in both arms, so `(Self.g).run` and an
    inline `(expr).run` compare equal after the redundant parentheses are collapsed.
    """
    text = dehoist(strip_reach(text))
    text = " ".join(text.split())
    previous = None
    while previous != text:
        previous = text
        text = re.sub(r"\(\(([^()]*(?:\([^()]*\)[^()]*)*)\)\)", r"(\1)", text)
    return text


def stub_files(census, repo, package):
    """`{relative path: absolute path}` for a package's census target and the repo's set-aside dir."""
    found = {}
    target = mc.census_target_dir(os.path.join(census, "trees", repo, package))
    if target:
        for path in glob.glob(os.path.join(target, "**", "*.swift"), recursive=True):
            found[os.path.join("target", os.path.relpath(path, target))] = path
    for path in glob.glob(os.path.join(census, f"aside-{repo}", "*.swift")):
        found[os.path.join("aside", os.path.basename(path))] = path
    return found


def content_diff(census_a, census_b, repo, package):
    """`(problems, counts)` for one package's stub files in two arms (Q6.4 step 1)."""
    a, b = stub_files(census_a, repo, package), stub_files(census_b, repo, package)
    problems = [f"only in A: {path}" for path in sorted(set(a) - set(b))]
    problems += [f"only in B: {path}" for path in sorted(set(b) - set(a))]
    counts = collections.Counter()
    for path in sorted(set(a) & set(b)):
        left, right = open(a[path], encoding="utf-8").read(), open(b[path], encoding="utf-8").read()
        if "/predicate/" in "/" + path.replace(os.sep, "/") or re.search(r"^// Template: predicate$", left, re.M):
            counts["predicate"] += 1
            if normalised_predicate(left) == normalised_predicate(right):
                counts["predicate_equal"] += 1
            else:
                problems.append(f"predicate differs after normalisation: {path}")
        else:
            counts["other"] += 1
            if left == right:
                counts["other_equal"] += 1
            else:
                problems.append(f"non-predicate bytes differ: {path}")
    return problems, counts


REACH_TEST = "_reachesBothOutcomes()"


def b_verdicts(entry):
    """`{suite: verdict}` for one arm-B package entry: green, not-applied-true/false, crashed, hung,
    skipped-after-law, other."""
    reach = entry.get("reach") or {}
    verdicts = {}

    def suite_of(name):
        return name.rsplit(".", 1)[0]
    for name in reach.get("green", []):
        verdicts[suite_of(name)] = "green"
    for name, sides in (reach.get("not_applied") or {}).items():
        verdicts[suite_of(name)] = "not-applied-" + "+".join(sorted(sides))
    for field, label in (("other", "other"), ("crashed", "crashed"), ("hung", "hung"),
                         ("skipped_after_law", "skipped-after-law")):
        for name in reach.get(field, []):
            verdicts[suite_of(name)] = label
    return verdicts


def verdict_agrees(verdict, row):
    """`(state, note)`: Q6.4 step 3's table. state is agree | disagree | excused | law-level | defect."""
    expected = {"green": "BOTH", "not-applied-true": "ONLY-FALSE", "not-applied-false": "ONLY-TRUE"}
    if verdict in expected:
        if row.get("class_again") == expected[verdict]:
            return "agree", None
        if row.get("unstable"):
            return "excused", f"unstable row reads {row.get('class_again')}"
        return "disagree", f"census class_again {row.get('class_again')}"
    if verdict in ("crashed", "hung"):
        if row.get("stateful") or row.get("class_again") in ("TRAPPED", "HUNG"):
            return "agree", None
        if row.get("unstable"):
            return "excused", "unstable"
        return "disagree", f"census class_again {row.get('class_again')}, stateful {row.get('stateful')}"
    if verdict == "skipped-after-law":
        return "law-level", f"law_a {row.get('law_a')}, class100 {row.get('class100')}"
    return "defect", f"reach verdict {verdict}: an emitter defect"


def class_of_verdict(verdict):
    return {"green": "BOTH", "not-applied-true": "ONLY-FALSE", "not-applied-false": "ONLY-TRUE",
            "crashed": "TRAPPED", "hung": "HUNG"}.get(verdict)


def rerun_row(row, census_a, times):
    """Rebuild one row's clone in arm A's tree and run `law` + `Again` under random hashing `times`
    times. Returns the `class_again` readings."""
    package = real(os.path.join(census_a, "trees", row["repo"], row["package"]))
    target = real(mc.census_target_dir(package))
    stub = real(os.path.join(census_a, "trees", row["repo"], row["stub"]))
    swift = cf.toolchain(row["repo"])
    written, classes = [], []
    log_dir = tempfile.mkdtemp(prefix="reach-rerun-")
    try:
        helper = os.path.join(target, HELPER_FILE)
        open(helper, "w", encoding="utf-8").write(HELPER)
        written.append(helper)
        text, reason = clone_text(open(stub, encoding="utf-8").read(), row["subject"], row["suite"])
        if reason:
            return [f"not-cloned: {reason}"]
        path = stub[:-len(".swift")] + CLONE_SUFFIX + ".swift"
        open(path, "w", encoding="utf-8").write(text)
        written.append(path)
        ok, _output, broken = lrc.build_setting_aside(package, swift, suffix=CLONE_SUFFIX)
        if not ok or row["suite"] in broken:
            return ["clone did not build"]
        for index in range(times):
            run = probe(package, swift, row["suite"], row["subject"], f"rand{index + 1}", log_dir, RAND_SECONDS)
            classes.append(tag_class(run, "again") if completed(run, "law") else tag_class(run, "law") or NO_READING)
    finally:
        for path in written:
            if os.path.exists(path):
                os.remove(path)
        shutil.rmtree(log_dir, ignore_errors=True)
    left = orphans(package)
    if left:
        raise Abort(f"orphaned processes under {package}/.build after a re-run:\n  " + "\n  ".join(left))
    return classes


def command_crosscheck(args):
    try:
        return crosscheck(args)
    except Abort as error:
        print(f"ABORT: {error}", flush=True)
        return 2


def crosscheck(args):
    census_a, census_b = real(args.census_a), real(args.census_b)
    rows = {(row["repo"], row["package"], row["suite"]): row for row in load_rows(args.census)}
    results_a = {json.load(open(p))["repo"]: json.load(open(p)) for p in glob.glob(os.path.join(census_a, "result-*.json"))}
    results_b = {json.load(open(p))["repo"]: json.load(open(p)) for p in glob.glob(os.path.join(census_b, "result-*.json"))}
    blocking, notes = [], []
    totals = collections.Counter()
    open(args.out, "w").close()
    for repo in sorted(set(results_a) | set(results_b)):
        if repo not in results_a or repo not in results_b:
            blocking.append(f"{repo}: present in one arm only")
            continue
        entries_a = {e["package"]: e for e in results_a[repo].get("packages", [])}
        entries_b = {e["package"]: e for e in results_b[repo].get("packages", [])}
        for package in sorted(set(entries_a) | set(entries_b)):
            a, b = entries_a.get(package) or {}, entries_b.get(package) or {}
            problems, counts = content_diff(census_a, census_b, repo, package)
            totals.update(counts)
            blocking += [f"{repo}/{package}: {p}" for p in problems]
            run_a = sum(a.get("run_seconds") or [])
            flagged = run_a > 240 or bool(a.get("bisect")) or bool(b.get("bisect"))
            moved = {f: (a.get(f), b.get(f)) for f in ("compiled", "passed", "passed_behaviour",
                                                        "passed_does_not_crash", "failed", "crashed", "hung")
                     if a.get(f) != b.get(f)}
            if moved:
                note = "flagged by time: re-run both arms at 1,800 s before attributing" if flagged else "unflagged"
                (notes if flagged else blocking).append(f"{repo}/{package}: columns moved {moved} ({note})")
            for suite, verdict in sorted(b_verdicts(b).items()):
                row = rows.get((repo, package, suite))
                if row is None:
                    blocking.append(f"{repo}/{package}/{suite}: B verdict {verdict} has no census row")
                    continue
                state, note = verdict_agrees(verdict, row)
                if state == "disagree" and args.rerun:
                    reread = rerun_row(row, census_a, args.rerun)
                    if class_of_verdict(verdict) in reread:
                        state, note = "unstable-missed", f"{note}; re-run read {reread}"
                    else:
                        state, note = "redraw-defect", f"{note}; re-run read {reread}"
                if state in ("disagree", "defect", "redraw-defect"):
                    blocking.append(f"{repo}/{package}/{suite}: {state} — {note}")
                totals["verdict_" + state] += 1
                record = {"repo": repo, "package": package, "suite": suite, "b_verdict": verdict, "state": state,
                          "note": note, "class_again": row.get("class_again"), "unstable": row.get("unstable")}
                with open(args.out, "a", encoding="utf-8") as handle:
                    handle.write(json.dumps(record, sort_keys=True) + "\n")
    print(f"content: predicate {totals['predicate_equal']}/{totals['predicate']} normalised-equal, "
          f"non-predicate {totals['other_equal']}/{totals['other']} byte-equal")
    print("verdicts: " + ", ".join(f"{k[8:]} {v}" for k, v in sorted(totals.items()) if k.startswith("verdict_")))
    for line in notes:
        print(f"  {line}")
    print(f"{len(blocking)} blocking")
    for line in blocking[:60]:
        print(f"  BLOCKS: {line}")
    return 1 if blocking else 0


# ---------------------------------------------------------------- V0: the self-test

CANNED_STUB = '''// Auto-generated by `swift-infer discover --interactive` — do not edit.
// Source: Sources/Toy/Toy.swift:4
// Template: predicate

import Testing
@testable import Toy
struct RulesIsEvenPredicateTests {

    @Test func isEven_isTotal() async {
        let backend = SwiftPropertyBasedBackend()
        let seed = Seed(
            stateA: 0x9C9C98B3B07C4338,
            stateB: 0x294DEF914F4AFAAD,
            stateC: 0xCC7AC966AEC41B04,
            stateD: 0xC489C2F632059409
        )
        let result = await backend.check(
            trials: 100,
            seed: seed,
            sample: { rng in (Gen<Int>.int()).run(using: &rng) },
            property: { value in _ = Rules.isEven(value); return true }
        )
        if case let .failed(_, _, input, error) = result {
            Issue.record(
                "Rules.isEven(_:) failed totality at input \\(input). \\(error?.message ?? "")"
            )
        }
    }
}
'''

CANNED_HOISTED = '''// Source: Sources/Toy/Toy.swift:24
struct PointIsRightOfPredicateTests {

    nonisolated private static let generator = zip(Gen<Int>.int(), Gen<Int>.int()).map { drawn in
        Point(xCoord: drawn.0, yCoord: drawn.1)
    }

    @Test func isRightOf_isTotal() async {
        let backend = SwiftPropertyBasedBackend()
        let seed = Seed(
            stateA: 0xFFC75A11D38F79F4,
            stateB: 0x68AF390FD7D6AC7F,
            stateC: 0xF4B0D928035F0D85,
            stateD: 0x0EB2CB970F16E48A
        )
        let result = await backend.check(
            trials: 100,
            seed: seed,
            sample: { rng in
                let arg0 = Self.generator.run(using: &rng)
                let arg1 = Self.generator.run(using: &rng)
                return (arg0, arg1)
            },
            property: { (args: (Point, Point)) in _ = args.0.isRightOf(args.1); return true }
        )
        if case let .failed(_, _, input, error) = result {
            Issue.record(
                "isRightOf(_:) failed totality at input \\(input). \\(error?.message ?? "")"
            )
        }
    }
}
'''

# (subject, property closure, the wrapped call it must yield). Q1.11's twelve shapes.
WRAP_CASES = [
    ("isEven", 'property: { value in _ = Rules.isEven(value); return true }', "Rules.isEven(value)"),
    ("isWithin", 'property: { (args: (Int, Int)) in _ = Rules.isWithin(args.0, limit: args.1); return true }',
     "Rules.isWithin(args.0, limit: args.1)"),
    ("isRightOf", 'property: { (args: (Point, Point)) in _ = args.0.isRightOf(args.1); return true }',
     "args.0.isRightOf(args.1)"),
    ("matchesPrefix", 'property: { value in _ = Matcher().matchesPrefix(value); return true }',
     "Matcher().matchesPrefix(value)"),
    ("matches", 'property: { value in _ = Parser(matches: .strict).matches(value); return true }',
     "Parser(matches: .strict).matches(value)"),
    ("consumesPrefix", 'property: { value in var inout0 = value; _ = Rules.consumesPrefix(&inout0); return true }',
     "Rules.consumesPrefix(&inout0)"),
    ("isWide", 'property: { value in await MainActor.run { _ = Layout.isWide(value); return true } }',
     "Layout.isWide(value)"),
    ("trimsLeading", 'property: { value in\n                await MainActor.run {\n                    var inout0 = value\n'
     '                    _ = Layout.trimsLeading(&inout0)\n                    return true\n                }\n            }',
     "Layout.trimsLeading(&inout0)"),
    ("holds", 'property: { value in _ = await Registry().holds(value); return true }', "Registry().holds(value)"),
    ("consumes", 'property: { value in var inout0 = value; _ = await Buffer().consumes(&inout0); return true }',
     "Buffer().consumes(&inout0)"),
    ("_isHidden", 'property: { value in _ = Rules._isHidden(value); return true }', "Rules._isHidden(value)"),
]


def self_test(quiet=False):
    failures = []

    def check(name, condition, detail=""):
        if not condition:
            failures.append(f"{name}: {detail}")

    _selftest_wrap(check)
    _selftest_parse(check)
    _selftest_clone(check)
    _selftest_status(check)
    _selftest_flags(check)
    _selftest_sampling(check)
    _selftest_decision(check)
    _selftest_kill(check)
    _selftest_crosscheck(check)
    if not quiet:
        for failure in failures:
            print("FAIL", failure)
    if failures:
        if not quiet:
            print(f"{len(failures)} self-test failure(s)")
        return 1
    if not quiet:
        print("predicate_outcome_reach.py self-test OK  (12 wrap shapes + the `run` guard, stub parse, "
              "clone, bit packing, process status, flags, sampling, DECISION, kill match, crosscheck)")
    return 0


def _selftest_wrap(check):
    for subject, closure, call in WRAP_CASES:
        wrapped, count = mc.wrap_subject_calls(closure, [subject], "T")
        check(f"wrap {subject} count", count == 1, f"n={count}")
        check(f"wrap {subject} text", f'__mutationProbe({call}, "T")' in wrapped, wrapped)
        check(f"wrap {subject} rest intact", wrapped.replace(f'__mutationProbe({call}, "T")', call) == closure, wrapped)
    # The twelfth shape: a hoisted draw. Only the property is wrapped; `Self.generator` draws are not.
    masked, _ = mc.mask(CANNED_HOISTED)
    prop = masked.index("property:")
    region = CANNED_HOISTED[prop:mc.matching(masked, masked.index("{", prop)) + 1]
    wrapped, count = mc.wrap_subject_calls(region, ["isRightOf"], "T")
    check("wrap hoisted count", count == 1, f"n={count}")
    clone, reason = clone_text(CANNED_HOISTED, "isRightOf", "PointIsRightOfPredicateTests")
    check("wrap hoisted clone draws untouched", clone and clone.count("Self.generator.run(using: &rng)") == 6, reason)
    # A subject named `run` beside the MainActor hop: two wraps, so the clone is refused.
    hop = CANNED_STUB.replace("property: { value in _ = Rules.isEven(value); return true }",
                              "property: { value in await MainActor.run { _ = Faults.run(value); return true } }")
    hop = hop.replace("isEven_isTotal", "run_isTotal")
    _clone, reason = clone_text(hop, "run", "RulesIsEvenPredicateTests")
    check("run beside MainActor.run", reason == "wrap n=2", reason)


def _selftest_parse(check):
    row = parse_stub_text(CANNED_STUB)
    want = {"suite": "RulesIsEvenPredicateTests", "test": "isEven_isTotal", "subject": "isEven",
            "label": "Rules.isEven(_:)", "source": "Sources/Toy/Toy.swift", "line": 4,
            "seed": "9C9C98B3B07C4338294DEF914F4AFAADCC7AC966AEC41B04C489C2F632059409",
            "generators": ["Gen<Int>.int()"], "arity": 1, "receiver": "none", "isolation": "none",
            "inout": False, "kinds": ["stdlib-scalar"], "primary_kind": "stdlib-scalar", "row_kind": "unary",
            "no_reading": None}
    for key, value in want.items():
        check(f"parse {key}", row.get(key) == value, f"{row.get(key)!r}")
    row = parse_stub_text(CANNED_HOISTED)
    generator = "zip(Gen<Int>.int(), Gen<Int>.int()).map { drawn in\n        Point(xCoord: drawn.0, yCoord: drawn.1)\n    }"
    check("parse hoisted generators", row["generators"] == [generator, generator], row["generators"])
    want = {"arity": 2, "receiver": "drawn", "row_kind": "relational", "kinds": ["derived", "derived"],
            "primary_kind": "derived", "label": "isRightOf(_:)", "line": 24}
    for key, value in want.items():
        check(f"parse hoisted {key}", row.get(key) == value, f"{row.get(key)!r}")
    actor = parse_stub_text(CANNED_STUB.replace("_ = Rules.isEven(value)", "_ = await Registry().isEven(value)"))
    check("parse actor", (actor["isolation"], actor["receiver"], actor["async"]) == ("actor", "constructed", False),
          f"{actor['isolation']} {actor['receiver']}")
    held = parse_stub_text(CANNED_STUB.replace("_ = Rules.isEven(value)", "_ = await Registry.shared.isEven(value)"))
    check("parse held actor", (held["isolation"], held["async"]) == ("actor", False), f"{held['isolation']}")
    static = parse_stub_text(CANNED_STUB.replace("_ = Rules.isEven(value)", "_ = await Rules.isEven(value)"))
    check("parse async static", (static["isolation"], static["async"]) == ("none", True), f"{static['isolation']}")
    hop_closure = "await MainActor.run { var inout0 = value; _ = Rules.isEven(&inout0); return true }"
    hop = parse_stub_text(CANNED_STUB.replace("_ = Rules.isEven(value); return true", hop_closure))
    check("parse MainActor inout", (hop["isolation"], hop["inout"]) == ("MainActor", True), f"{hop['isolation']}")
    hostile = ('Gen.frequency((3.0, Gen<String?>.element(of: ["", "[[a|b]]", "]"] as [String]).compactMap(\\.self)), '
               '(1.0, Gen<String?>.element(of: ["ab"] as [String]).compactMap(\\.self)))')
    check("kind hostile + literals", generator_kind(hostile) == ("hostile-string", True), generator_kind(hostile))
    plain = 'Gen.frequency((3.0, Gen<String?>.element(of: ["", "[[a|b]]"] as [String]).compactMap(\\.self)))'
    check("kind hostile, no literals", generator_kind(plain) == ("hostile-string", False), generator_kind(plain))
    check("kind todo", generator_kind("Registry.gen() /* TODO: no generator derived */")[0] == "unresolved")
    check("kind syntax corpus", generator_kind("SwiftInferSyntaxCorpus.gen(of: X.self)")[0] == "syntax-corpus")
    check("kind held", generator_kind("Gen.always(Config())")[0] == "held-constant")
    check("kind array", generator_kind("Gen<Int>.int().array(of: 0...4)")[0] == "array")
    check("kind optional array", generator_kind(
        "Gen<Character>.letterOrNumber.string(of: 0...8).array(of: 0...8).optional")[0] == "array")
    # A kind names the outermost shape: none of these is held-constant, array or stdlib-scalar.
    for generator, kind in (
            ("zip(Gen<Int>.int(), Gen.oneOf(Gen.always(Mode.fast).eraseToAny(), Gen.always(Mode.slow)"
             ".eraseToAny())).map { Config(depth: $0.0, mode: $0.1) }", "derived"),
            ("zip(Gen<Int>.int(), Gen<Int>.int().array(of: 0...4)).map { Foo(a: $0.0, b: $0.1) }", "derived"),
            ("Gen<Int>.int().map { Level(rawValue: $0) }", "derived"),
            ("Gen<Character>.letterOrNumber.string(of: 0...8)", "other"),
            ("zip(" + hostile + ", Gen<Int>.int()).map { Named(name: $0.0, rank: $0.1) }", "derived"),
            ("Gen<Int>.int()", "stdlib-scalar"), ("Gen.int(in: 0...9)", "stdlib-scalar")):
        check(f"kind outermost {generator[:40]}", generator_kind(generator)[0] == kind, generator_kind(generator))
    check("no _isTotal", parse_stub_text("struct S {}\n")["no_reading"] == "no _isTotal")


def _selftest_clone(check):
    clone, reason = clone_text(CANNED_STUB, "isEven", "RulesIsEvenPredicateTests")
    check("clone made", clone is not None, reason)
    if not clone:
        return
    begins = re.findall(r'__reachBegin\("RulesIsEvenPredicateTests_Reach\|(\w+)"\)', clone)
    check("clone BEGIN order", begins == list(TAGS), begins)
    names = re.findall(r"@Test func (\w+)\(", clone)
    check("clone names", names == ["isEven_isTotal", "isEven_isTotalAgain", "isEven_isTotalAt1000"], names)
    check("clone budgets", re.findall(r"trials: (\d+),", clone) == ["100", "100", "1000"], "")
    probes = re.findall(r'__reachProbe\(Rules\.isEven\(value\), "RulesIsEvenPredicateTests_Reach\|(\w+)"\)', clone)
    check("clone probes", probes == list(TAGS), probes)
    check("clone suite", "struct RulesIsEvenPredicateTests_Reach {" in clone and "__mutationProbe" not in clone)
    first_body = clone[clone.index("isEven_isTotal() async {"):]
    check("clone BEGIN first statement", re.match(r"isEven_isTotal\(\) async \{\n\s+__reachBegin", first_body), "")
    _clone, reason = clone_text(CANNED_STUB.replace("trials: 100,", "trials: 50,"), "isEven", "RulesIsEvenPredicateTests")
    check("clone trials guard", reason == "trials n=0", reason)
    suite, hand = hand_stub_text(CANNED_STUB, "Faults.trapsLate", 70)
    check("hand stub", suite == "FaultsTrapsLatePredicateTests" and "Faults.trapsLate(value)" in hand
          and "trapsLate_isTotal()" in hand and "// Source: Sources/PredicateReachToy/Subjects.swift:70" in hand
          and "0x9C9C98B3B07C4338" in hand and "struct FaultsTrapsLatePredicateTests {" in hand, hand[:300])
    for bits in ([], [1], [0, 1, 1, 0, 1], [1] * 100, [0] * 999 + [1], [random.Random(7).randint(0, 1) for _ in range(1000)]):
        check(f"bits round trip {len(bits)}", unpack_bits(pack_bits(bits), len(bits)) == bits)
    check("bits width", len(pack_bits([1] * 100)) == 25 and len(pack_bits([0] * 1000)) == 250)
    log = ["RBEGIN|S_Reach|law", "RPROBE|S_Reach|law|1", "RPROBE|S_Reach|law|0", "RBEGIN|S_Reach|again",
           "RPROBE|S_Reach|again|1", "RPROBE|Other_Reach|again|1", "RPROB"]
    order, bits = read_log(log, "S_Reach")
    check("log parse", order == ["law", "again"] and bits["law"] == [1, 0] and bits["again"] == [1], f"{order} {bits}")
    found = read_oracle_log(["OBEGIN|f|law", "OPROBE|f|1", "OBEGIN|f|scale", "OPROBE|f|0", "OSTOP|f|scale|2",
                             "OPROBE|g|1"])
    check("oracle log parse", found["f"]["bits"] == {"law": [1], "scale": [0]} and found["f"]["stop"] == {"scale": 2}
          and found["g"]["bits"] == {"law": [1]}, found)
    output = ("◇ Test isEven_isTotal() started.\n✔ Test isEven_isTotal() passed after 0.001 seconds.\n"
              "✔ Test isEven_isTotalAgain() passed after 0.001 seconds.\n"
              "✘ Test isEven_isTotalAt1000() recorded an issue at X.swift:9:5: Issue recorded\n"
              "✔ Test otherSuite_isTotal() passed after 0.001 seconds.\n")
    check("output parse", read_output(output, "isEven") == ({"law", "again"}, {"scale"}), read_output(output, "isEven"))
    _selftest_oracle(check)


def _selftest_oracle(check):
    """Gate (a)'s comparison must be able to fail: a flipped bit, a moved stop, a run past the stop."""
    law, scale = [0, 1] * 50, [1, 0] * 74 + [1]
    trapped = {"runs": {"det": run_record(_fake_run("trapped", {"law": law, "again": law, "scale": scale},
                                                    trapped={"test": "scale", "at": 150}))}}
    oracle = {"bits": {"law": list(law), "again": list(law), "scale": list(scale)}, "stop": {"scale": 150}}
    check("oracle agrees", oracle_agreement(trapped, oracle)[0] is True, oracle_agreement(trapped, oracle))
    flipped = {"bits": dict(oracle["bits"], again=law[:41] + [1 - law[41]] + law[42:]), "stop": {"scale": 150}}
    same, detail = oracle_agreement(trapped, flipped)
    check("oracle flipped bit", same is False and "first difference at call 42" in detail, detail)
    check("oracle moved stop", oracle_agreement(trapped, dict(oracle, stop={"scale": 151}))[0] is False)
    hung_law = {"runs": {"det": run_record(_fake_run("hung", {"law": [1, 1]}, hung={"test": "law", "at": 3}))}}
    past = {"bits": {"law": [1, 1], "again": [1]}, "stop": {"law": 3}}
    check("oracle past the stop", oracle_agreement(hung_law, past)[0] is False, oracle_agreement(hung_law, past))
    law_only = {"bits": {"law": list(law)}, "stop": {}}
    check("oracle law only, V1", oracle_agreement(trapped, law_only)[0] is False, oracle_agreement(trapped, law_only))
    check("oracle law only, V2a", oracle_agreement(trapped, law_only, required=("law",))[0] is True)
    no_scale = {"bits": {"law": list(law), "again": list(law)}, "stop": {}}
    same, detail = oracle_agreement(trapped, no_scale)
    check("oracle never logged scale", same is False and "scale" in detail, detail)
    check("oracle process ok", oracle_process_ok({"returncode": 0, "timed_out": False})
          and not oracle_process_ok({"returncode": 1, "timed_out": False})
          and not oracle_process_ok({"returncode": None, "timed_out": True}) and not oracle_process_ok({}))
    check("oracle no det", oracle_agreement({"runs": {}}, oracle)[0] is None)


# SwiftPM's output for a trapped helper: `fixtures/predicate-outcome-reach/swift-testing-output/trap.out`.
TRAP_OUTPUT = """◇ Test isOdd_isTotal() started.
Swift/ContiguousArrayBuffer.swift:695: Fatal error: Index out of range
Note: Some test targets reported failures:
  - RulesTests (Swift Testing)
error: Process '<toolchain>/usr/libexec/swift/pm/swiftpm-testing-helper --test-bundle-path <package>/.build/out/\
Products/Debug/RulesTests.xctest/Contents/MacOS/RulesTests --testing-library swift-testing' exited with unexpected \
signal code 5
"""


def _fake_run(status, bits, **stop):
    return dict({"status": status, "bits": {tag: list(bits.get(tag, [])) for tag in TAGS}}, **stop)


def _selftest_status(check):
    both = [0, 1] * 50
    full = {"law": both, "again": both, "scale": [0, 1] * 500}
    names = ("law", "again", "scale")
    status = process_status([], {t: [] for t in TAGS}, set(), set(), False, 0, names)
    check("status missing", status == {"status": NO_READING, "no_reading": "missing"}, status)
    status = process_status([], {t: [] for t in TAGS}, set(), set(), True, None, names)
    check("status no-test-began", status.get("no_reading") == "no-test-began", status)
    for tag, prior in (("law", {}), ("again", {"law": both}), ("scale", {"law": both, "again": both})):
        bits = dict({t: [] for t in TAGS}, **prior)
        bits[tag] = [1, 0, 1]
        order = list(TAGS[:TAGS.index(tag) + 1])
        status = process_status(order, bits, set(), set(), True, -9, names)
        check(f"status hang in {tag}", status == {"status": "hung", "hung": {"test": tag, "at": 4}}, status)
    # A trap is read from SwiftPM's signal line (`TRAP_OUTPUT`, as `trap.out` captured it).
    check("exit signal parse", exit_signal(TRAP_OUTPUT) == 5 and exit_signal("Note: Some test targets reported "
                                                                          "failures:\n") is None)
    trap = exit_signal(TRAP_OUTPUT)
    bits = {"law": both, "again": both, "scale": [1, 0] * 74 + [1]}
    status = process_status(list(TAGS), bits, {"law", "again"}, set(), False, 1, names, trap)
    check("status trap in scale", status == {"status": "trapped", "trapped": {"test": "scale", "at": 150}}, status)
    out = readings(dict(status, bits=bits), [])
    check("trap@150 classes", (out["class100"], out["class1000"], out["class_again"]) == ("BOTH", "TRAPPED", "BOTH"), out)
    bits = {"law": [1] * 100, "again": [0] * 7, "scale": []}
    status = process_status(["law", "again"], bits, {"law"}, set(), False, 1, names, trap)
    out = readings(dict(status, bits=bits), [])
    check("again trap", status.get("trapped") == {"test": "again", "at": 8}, status)
    check("again trap stateful", out["stateful"] and out["class_again"] == "TRAPPED"
          and out["class1000"] == NO_READING and out["class1000_note"] == "blocked-by-again", out)
    status = process_status(["law"], {"law": [1], "again": [], "scale": []}, set(), set(), False, 1, names, 11)
    out = readings(dict(status, bits={"law": [], "again": [], "scale": []}), [])
    check("trap at 1 (SIGSEGV)", status.get("trapped") == {"test": "law", "at": 2} and out["class1000"] == "TRAPPED",
          status)
    # A helper killed from outside, or one that called exit(), is not a trap: no signal line (SIGKILL,
    # SIGTERM, SIGINT print none), or a signal another process sends. Mid-law in a rand run it must
    # read NO READING, so it neither flags the row hash-sensitive nor drops it from R.
    for signal in (None, 1, 2, 3, 9, 15):
        status = process_status(["law"], {"law": [1] * 37, "again": [], "scale": []}, set(), set(), False, 1,
                                ("law", "again"), signal)
        check(f"killed, signal {signal}", status == {"status": NO_READING, "no_reading": "killed-or-exited"}, status)
    killed = dict(status, bits={"law": [1] * 37, "again": [], "scale": []})
    out = readings(_fake_run("ran", {"law": both, "again": both, "scale": both * 10}), [killed])
    check("killed rand is not hash-sensitive", out["class100_rand"] == [NO_READING]
          and not out["hash_sensitive_class"] and not out["unstable"], out)
    # A stop in a test whose count is already full is not the subject's: the timeout landing between
    # `again` and `scale`, after the last `scale` call, or a crash after the last call.
    gap = {"law": both, "again": both, "scale": []}
    status = process_status(["law", "again"], gap, {"law", "again"}, set(), True, -9, names)
    check("timeout between tests", status == {"status": NO_READING, "no_reading": "stopped-after-complete"}, status)
    status = process_status(list(TAGS), full, set(), set(), True, -9, names)
    check("timeout after the last call", status.get("no_reading") == "stopped-after-complete", status)
    status = process_status(["law"], {"law": both, "again": [], "scale": []}, set(), set(), False, 1, names, trap)
    check("trap after the last call", status.get("no_reading") == "stopped-after-complete", status)
    status = process_status(list(TAGS), full, {"law"}, {"again"}, False, 1, names)
    check("status unexpected-failure", status.get("no_reading") == "unexpected-failure", status)
    status = process_status(list(TAGS), dict(full, scale=[1] * 999), set(TAGS), set(), False, 0, names)
    check("status miscounted", status.get("no_reading") == "miscounted", status)
    status = process_status(list(TAGS), full, set(TAGS), set(), False, 0, names)
    check("status ran", status == {"status": "ran"}, status)
    status = process_status(["law", "again"], {"law": both, "again": both, "scale": []}, {"law", "again"}, set(),
                            False, 0, ("law", "again"))
    check("status rand ran", status == {"status": "ran"}, status)


def _selftest_flags(check):
    both = [0, 1] * 50
    det = _fake_run("ran", {"law": both, "again": both, "scale": both * 10})
    out = readings(det, [])
    check("flags clean", not any(out[f] for f in ("stateful", "hash_sensitive_class", "hash_sensitive_bits",
                                                 "again_bits_differ", "scale_prefix_differs", "unstable")), out)
    check("counts", (out["true100"], out["true1000"], out["first_true_at"], out["first_false_at"], out["minority100"])
          == (50, 500, 2, 1, 50), out)
    flipped = [1, 0] * 50
    out = readings(_fake_run("ran", {"law": both, "again": flipped, "scale": flipped * 10}), [])
    check("bit flags", out["again_bits_differ"] and out["scale_prefix_differs"] and not out["stateful"], out)
    # stateful truth table: det again differs in class; or a random run does; else not.
    out = readings(_fake_run("ran", {"law": [1] * 100, "again": [0] * 100, "scale": [0] * 100 + [1] * 900}), [])
    check("stateful det", out["stateful"] and out["unstable"] and out["class_again"] == "ONLY-FALSE", out)
    rand_state = _fake_run("ran", {"law": [1] * 100, "again": [0] * 100})
    out = readings(_fake_run("ran", {"law": [1] * 100, "again": [1] * 100, "scale": [1] * 1000}), [rand_state])
    check("stateful rand", out["stateful"] and not out["hash_sensitive_class"], out)
    out = readings(_fake_run("ran", {"law": [1] * 100, "again": [1] * 100, "scale": [1] * 1000}),
                   [_fake_run("ran", {"law": [1] * 100, "again": [1] * 100})])
    check("stateful no", not out["stateful"] and not out["unstable"], out)
    # hash_sensitive_class truth table.
    out = readings(_fake_run("ran", {"law": [1] * 100, "again": [1] * 100, "scale": [1] * 1000}),
                   [_fake_run("ran", {"law": [0] * 100, "again": [0] * 100})])
    check("hash class yes", out["hash_sensitive_class"] and out["unstable"] and out["hash_sensitive_bits"], out)
    out = readings(_fake_run("ran", {"law": both, "again": both, "scale": both * 10}),
                   [_fake_run("ran", {"law": flipped, "again": flipped})])
    check("hash bits only", out["hash_sensitive_bits"] and not out["hash_sensitive_class"] and not out["unstable"], out)
    out = readings(_fake_run("ran", {"law": both, "again": both, "scale": both * 10}),
                   [_fake_run(NO_READING, {}, no_reading="missing")])
    check("hash class ignores no-reading", not out["hash_sensitive_class"] and out["class100_rand"] == [NO_READING], out)


def _row(repo, stub, class100="BOTH", unstable=False, teaching=False, law_a="passed"):
    return {"repo": repo, "stub": stub, "class100": class100, "unstable": unstable, "teaching": teaching,
            "law_a": law_a}


def _selftest_sampling(check):
    check("allocate", allocate({"A": 10, "B": 10, "C": 10}, 30) == {"A": 10, "B": 10, "C": 10})
    check("allocate remainder", allocate({"A": 1, "B": 1, "C": 1}, 2) == {"A": 1, "B": 1, "C": 0},
          allocate({"A": 1, "B": 1, "C": 1}, 2))
    check("allocate largest", allocate({"A": 7, "B": 2, "C": 1}, 5) == {"A": 4, "B": 1, "C": 0},
          allocate({"A": 7, "B": 2, "C": 1}, 5))
    check("allocate tie by name", allocate({"Z": 3, "B": 3, "M": 3}, 4) == {"B": 2, "M": 1, "Z": 1},
          allocate({"Z": 3, "B": 3, "M": 3}, 4))
    rows = ([_row("A", f"a{i}", "ONLY-FALSE") for i in range(40)] + [_row("B", f"b{i}", "ONLY-TRUE") for i in range(20)]
            + [_row("C", f"c{i}") for i in range(50)] + [_row("T", f"t{i}", "ONLY-FALSE", teaching=True) for i in range(9)])
    sample, allocation, counts = draw_sample(rows)
    check("sample size", len(sample) == 30 and allocation == {"A": 20, "B": 10} and counts == {"A": 40, "B": 20},
          f"{allocation} {counts}")
    again, _, _ = draw_sample(list(reversed(rows)))
    check("sample frozen", [r["stub"] for r in sample] == [r["stub"] for r in again])
    judgements = {row["stub"]: {"class": "constant-by-design" if row["repo"] == "A" else "generator-miss"}
                  for row in sample}
    value, k, n = cbd_share(sample, judgements, counts)
    check("cbd weighted", abs(value - 40 / 60) < 1e-9 and (k, n) == (20, 30), value)
    half = dict(judgements)
    for row in [r for r in sample if r["repo"] == "A"][:10]:
        half[row["stub"]] = {"class": "relational"}
    value, k, n = cbd_share(sample, half, counts)
    check("cbd weighted partial", abs(value - (40 / 60) * 0.5) < 1e-9 and (k, n) == (10, 30), value)
    missing = dict(judgements)
    missing.pop(sample[0]["stub"])
    check("cbd incomplete", cbd_share(sample, missing, counts)[0] is None)
    try:
        draw_sample([_row("A", "Tests/same.swift", "ONLY-FALSE"), _row("B", "Tests/same.swift", "ONLY-TRUE")])
        refused = False
    except SystemExit:
        refused = True
    check("sample refuses a stub path shared across repositories", refused)
    # Every remainder exactly 1/3: the tie goes to the earlier name, never to rounding error.
    tie = allocate({"Alpha": 4, "Beta": 1, "Gamma": 85}, 30)
    check("allocate exact tie", tie == {"Alpha": 2, "Beta": 0, "Gamma": 28}, tie)
    # An exact 1/2 is not above 1/2: 0.2 x 1/6 + 0.8 x 7/12 summed to 0.5000000000000001 as floats.
    rows = [_row("Repo0", f"r0-{i}", "ONLY-FALSE") for i in range(48)] + [_row("Repo1", f"r1-{i}", "ONLY-TRUE")
                                                                          for i in range(192)]
    sample, allocation, counts = draw_sample(rows)
    judged = {}
    for repo, cbd_count in (("Repo0", 1), ("Repo1", 14)):
        for index, row in enumerate(r for r in sample if r["repo"] == repo):
            judged[row["stub"]] = {"class": "constant-by-design" if index < cbd_count else "generator-miss"}
    value, k, n = cbd_share(sample, judged, counts)
    check("cbd exactly 1/2", allocation == {"Repo0": 6, "Repo1": 24} and value == fractions.Fraction(1, 2)
          and (k, n) == (15, 30) and decide(0.95, 0.95, 240, 0, 240, True, value) == "E", f"{allocation} {value}")
    check("cbd with no reds", cbd_share([], {}, {}) == (0, 0, 0)
          and decide(0.95, 0.95, 150, 0, 150, True, cbd_share([], {}, {})[0]) == "E")
    typo = {row["stub"]: {"class": "constant_by_design"} for row in sample}
    try:
        cbd_share(sample, typo, counts)
        check("cbd refuses an unknown class", False, "accepted constant_by_design")
    except SystemExit:
        pass
    mixed = [dict(_row("A", "a"), arm="census"), dict(_row("B", "b"), arm="control-e36da59")]
    with contextlib.redirect_stderr(io.StringIO()):
        kept = arm_rows(mixed, CENSUS_ARM)
    check("arm filter", [row["repo"] for row in kept] == ["A"], kept)
    with tempfile.TemporaryDirectory() as scratch:
        predicate = os.path.join(scratch, "predicate")
        os.makedirs(predicate)
        for name in ("A", "A_Lit", "A_N1000", "A_Probe", "A_Reach", "A_Oracle", "B"):
            open(os.path.join(predicate, name + ".swift"), "w").close()
        found = [os.path.basename(path) for path in predicate_stubs(scratch)]
        check("foreign copies are not rows", found == ["A.swift", "B.swift"], found)


def _selftest_decision(check):
    decide_at = lambda g, loo=0.95, cbd=0.0: decide(g, loo, 200, 0, 200, True, cbd)
    check("band 0.4999", decide_at(0.4999) == "NONE")
    check("band 0.50", decide_at(0.50) == "W")
    check("band 0.7999", decide_at(0.7999) == "W")
    check("band 0.80", decide_at(0.80) == "E")
    check("lower band of G and G_loo", decide(0.90, 0.60, 200, 0, 200, True, 0.0) == "W"
          and decide(0.55, 0.95, 200, 0, 200, True, 0.0) == "W" and decide(0.90, 0.40, 200, 0, 200, True, 0.0) == "NONE")
    # §0: an input §7 cannot compute is a failed gate, counted toward the two rounds, never a band.
    check("G_loo undefined", decide(0.90, None, 200, 0, 200, True, 0.0) == "NOT-DECISIVE(instrument)")
    check("G_loo undefined, terminal", decide(0.90, None, 200, 0, 200, True, 0.0, ["NOT-DECISIVE(instrument)"] * 2)
          == "NONE(instrument)")
    check("population 99", decide(0.95, 0.95, 99, 0, 200, True, 0.0) == "NONE(population)")
    check("no reading 10.1%", decide(0.95, 0.95, 150, 101, 1000, True, 0.0) == "NOT-DECISIVE(no-reading)")
    check("no reading 10.0%", decide(0.95, 0.95, 150, 100, 1000, True, 0.0) == "E")
    check("no reading terminal", decide(0.95, 0.95, 150, 101, 1000, True, 0.0, ["NOT-DECISIVE(no-reading)"])
          == "NONE(no-reading)")
    check("instrument", decide(0.95, 0.95, 150, 0, 1000, False, 0.0) == "NOT-DECISIVE(instrument)")
    check("instrument round 2", decide(0.95, 0.95, 150, 0, 1000, False, 0.0, ["NOT-DECISIVE(instrument)"])
          == "NOT-DECISIVE(instrument)")
    check("instrument terminal", decide(0.95, 0.95, 150, 0, 1000, False, 0.0, ["NOT-DECISIVE(instrument)"] * 2)
          == "NONE(instrument)")
    check("hand drop E→W", decide(0.95, 0.95, 150, 0, 1000, True, 0.51) == "W")
    check("hand drop at 0.5 none", decide(0.95, 0.95, 150, 0, 1000, True, 0.50) == "E")
    check("hand never drops W", decide(0.60, 0.95, 150, 0, 1000, True, 0.99) == "W")
    _selftest_rounds(check)
    rows = [_row("B", f"b{i}") for i in range(3)] + [_row("A", f"a{i}", "ONLY-FALSE") for i in range(3)]
    check("largest tie by name", largest_repo(rows) == "A", largest_repo(rows))
    pop = population(rows + [_row("C", "c0", unstable=True), _row("T", "t", teaching=True),
                             _row("D", "d", law_a="failed"), _row("E", "e", NO_READING)])
    check("population R", len(pop["R"]) == 7 and pop["green"] == 3 and pop["largest"] == "A"
          and abs(pop["G_loo"] - 3 / 4) < 1e-9 and len(pop["unread"]) == 1 and len(pop["readable"]) == 8,
          f"{len(pop['R'])} {pop['green']} {pop['largest']} {pop['G_loo']}")
    line = decision_line(pop, "NONE", None, 0, 0, "pass", "pass", "7/10", "abc")
    check("decision line", line.startswith("DECISION: NONE  G=42.9% (3/7)  G_loo=75.0% without A") and
          "|R|=7  unstable=1" in line and "hand: constant-by-design n/a" in line and line.endswith("input=abc"), line)


def _selftest_rounds(check):
    """A fix round is a distinct `(script, input)` pair, and the same line is never recorded twice."""
    no_reading = "NOT-DECISIVE(no-reading)"
    same = [("s1", no_reading, "d1", ""), ("s1", no_reading, "d1", "")]
    check("rounds: a repeat is no round", fix_rounds(same, "s1", "d1") == {}, fix_rounds(same, "s1", "d1"))
    check("rounds: a repeat stays NOT-DECISIVE",
          decide(0.95, 0.95, 150, 101, 1000, True, 0.0, fix_rounds(same, "s1", "d1")) == no_reading)
    check("rounds: a fix makes it terminal",
          decide(0.95, 0.95, 150, 101, 1000, True, 0.0, fix_rounds(same, "s2", "d2")) == "NONE(no-reading)")
    instrument = "NOT-DECISIVE(instrument)"
    twice = [("s1", instrument, "d1", ""), ("s1", instrument, "d1", "")]
    check("rounds: duplicates count once", fix_rounds(twice, "s2", "d2") == {instrument: 1})
    check("rounds: two distinct rounds", fix_rounds(twice + [("s2", instrument, "d2", "")], "s3", "d3")
          == {instrument: 2})
    with tempfile.TemporaryDirectory() as scratch:
        log = os.path.join(scratch, "decisions.log")
        line = "DECISION: NOT-DECISIVE(no-reading)  G=90.0% (135/150)  |R|=150  V1=pass  V2a=pass  input=abc123def456"
        args = argparse.Namespace(arm=CENSUS_ARM, v1="pass", v2a="pass", record_decision=log)
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            first = record_decision(args, recorded_decisions(log), "s1", no_reading, None, line)
            second = record_decision(args, recorded_decisions(log), "s1", no_reading, None, line)
            control = record_decision(argparse.Namespace(arm="control-e36da59", v1="pass", v2a="pass",
                                                         record_decision=log), [], "s1", "E", 0, line)
        recorded = recorded_decisions(log)
        check("record once", (first, second, control) == (0, 0, 1) and len(recorded) == 1
              and recorded[0][:3] == ("s1", no_reading, "abc123def456"), recorded)


def _selftest_kill(check):
    with tempfile.TemporaryDirectory() as scratch:
        package = os.path.join(real(scratch), "trees", "Repo")
        os.makedirs(package)
        listing = (f"  101 /usr/bin/swift-test --package-path x\n  202 {package}/.build/debug/RepoPackageTests.xctest\n"
                   f"  303 {package}-other/.build/debug/x\n")
        dotted = os.path.join(scratch, "trees", "Repo", ".")
        check("kill matches ./ path", build_process_pids(listing, dotted) == ["202"], build_process_pids(listing, dotted))
        link = os.path.join(scratch, "link")
        os.symlink(package, link)
        check("kill matches through a symlink", build_process_pids(listing, link) == ["202"])


def _selftest_crosscheck(check):
    arm_a = CANNED_HOISTED
    arm_b = arm_a.replace("// Source: Sources/Toy/Toy.swift:24",
                          "// Source: Sources/Toy/Toy.swift:24\n// Reach: a second test checks the draws reach both\n"
                          "//        answers; it is not a law.")
    arm_b = arm_b.rstrip("}\n") + ("\n    }\n\n    @Test func isRightOf_reachesBothOutcomes() {\n        var reachRNG = 1\n"
                                   "        if reachRNG == 1 { reachRNG = 2 }\n    }\n\n"
                                   "    nonisolated private static func reachNote(_ text: String) {\n"
                                   "        #if compiler(>=6.3)\n        Issue.record(\"\\(text)\", severity: .warning)\n"
                                   "        #endif\n    }\n}\n")
    check("normalise equal", normalised_predicate(arm_a) == normalised_predicate(arm_b),
          normalised_predicate(arm_b)[-200:])
    inline = arm_a.replace("Self.generator.run", "(zip(Gen<Int>.int(), Gen<Int>.int()).map { drawn in\n        "
                           "Point(xCoord: drawn.0, yCoord: drawn.1)\n    }).run")
    inline = re.sub(r"    nonisolated private static let generator = .*?\n    }\n\n", "", inline, flags=re.S)
    check("normalise de-hoist", normalised_predicate(arm_a) == normalised_predicate(inline),
          normalised_predicate(inline)[:300])
    check("normalise catches a change", normalised_predicate(arm_a) != normalised_predicate(arm_a.replace("100,", "99,")))
    entry = {"reach": {"green": ["S1.f_reachesBothOutcomes()"], "not_applied": {"S2.g_reachesBothOutcomes()": ["true"]},
                       "other": ["S3.h_reachesBothOutcomes()"], "crashed": ["S4.k_reachesBothOutcomes()"],
                       "hung": [], "skipped_after_law": ["S5.m_reachesBothOutcomes()"]}}
    verdicts = b_verdicts(entry)
    check("B verdicts", verdicts == {"S1": "green", "S2": "not-applied-true", "S3": "other", "S4": "crashed",
                                     "S5": "skipped-after-law"}, verdicts)
    check("agree green", verdict_agrees("green", {"class_again": "BOTH"})[0] == "agree")
    check("agree true side", verdict_agrees("not-applied-true", {"class_again": "ONLY-FALSE"})[0] == "agree")
    check("agree false side", verdict_agrees("not-applied-false", {"class_again": "ONLY-TRUE"})[0] == "agree")
    check("disagree", verdict_agrees("green", {"class_again": "ONLY-FALSE"})[0] == "disagree")
    check("excused", verdict_agrees("green", {"class_again": "ONLY-FALSE", "unstable": True})[0] == "excused")
    check("crash stateful", verdict_agrees("crashed", {"class_again": "BOTH", "stateful": True})[0] == "agree")
    check("crash stable", verdict_agrees("crashed", {"class_again": "BOTH"})[0] == "disagree")
    check("law level", verdict_agrees("skipped-after-law", {"law_a": "crashed"})[0] == "law-level")
    check("other is a defect", verdict_agrees("other", {})[0] == "defect")


# ---------------------------------------------------------------- main

def parse_arguments(argv):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--self-test", action="store_true")
    sub = parser.add_subparsers(dest="command")
    validate = sub.add_parser("validate", help="V1: the toy control")
    validate.add_argument("scratch")
    validate.add_argument("swift_infer")
    validate.add_argument("--rand-runs", type=int, default=8)
    run = sub.add_parser("run", help="probe every predicate stub of a census, or of --package dirs")
    run.add_argument("rest", nargs="+", help="<census-dir> <out.jsonl> [repo …], or <out.jsonl> with --package")
    run.add_argument("--package", action="append")
    run.add_argument("--arm", required=True)
    run.add_argument("--rand-runs", type=int, default=DEFAULT_RAND_RUNS)
    run.add_argument("--timeout", type=int, help="seconds for every process, replacing Q1.6's defaults")
    run.add_argument("--swift-infer", help="the binary's SHA, recorded on each row")
    run.add_argument("--cli", help="the SwiftProjectLint CLI's SHA, recorded on each row")
    oracle = sub.add_parser("oracle", help="V2a: hand oracles beside stubs against the clone's det bits")
    oracle.add_argument("out")
    oracle.add_argument("stubs", nargs="+")
    sample = sub.add_parser("sample", help="the stratified hand sample")
    sample.add_argument("out")
    sample.add_argument("--write-template", help="write an empty judgements file for the sample")
    sample.add_argument("--arm", default=CENSUS_ARM, help="the arm whose rows are sampled (default: census)")
    report = sub.add_parser("report", help="tables and the DECISION line")
    report.add_argument("out")
    report.add_argument("--judgements")
    report.add_argument("--json", action="store_true")
    report.add_argument("--record-decision", help="append the DECISION line here (census arm only)")
    report.add_argument("--arm", default=CENSUS_ARM, help="the arm R is read from (default: census)")
    report.add_argument("--v1", choices=("pass", "fail"))
    report.add_argument("--v2a", choices=("pass", "fail"))
    report.add_argument("--v2b", help="k/10")
    report.add_argument("--census", help="a census dir whose result files the arm-A invariants are checked on")
    report.add_argument("--expected-rows", type=int)
    report.add_argument("--expected-packages", type=int)
    record = sub.add_parser("record", help="the run as a portable fixture")
    record.add_argument("out")
    record.add_argument("fixture")
    cross = sub.add_parser("crosscheck", help="arm B's reach verdicts against the census (E or W only)")
    cross.add_argument("census")
    cross.add_argument("census_a")
    cross.add_argument("census_b")
    cross.add_argument("out")
    cross.add_argument("--rerun", type=int, default=10)
    return parser, parser.parse_args(argv[1:])


def main(argv):
    if "--self-test" in argv[1:2]:
        return self_test()
    parser, args = parse_arguments(argv)
    handlers = {"validate": command_validate, "run": command_run, "oracle": command_oracle,
                "sample": command_sample, "report": command_report, "record": command_record,
                "crosscheck": command_crosscheck}
    if args.command not in handlers:
        parser.print_help()
        return 2
    return handlers[args.command](args)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
