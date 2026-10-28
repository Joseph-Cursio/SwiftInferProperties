#!/usr/bin/env python3
"""Does a regex producer's output compile on a well-formed input? — the precision arm of
`docs/plans/regex-acceptor-census-scope.md` §4 (#666).

A **stub** is one Swift file holding a producer's declaration verbatim, plus two functions the
driver calls: `produce(_:) -> String?`, which places a drawn input where the call site's argument
expression places the producer's input (`nil` when the producer declines it, or throws), and
`accepts(_:)`, which hands the result to the call site's acceptor with its options and is the
stub's last declaration. The driver runs a domain through both, one input at a time, and streams
what happens to each input. So a stub that traps or hangs on one input marks that input TRAPPED,
and the run resumes after it. It executes the real body, compiled. #666's own numbers came from a
JavaScript transcription of each body, and the harness controls reproduce them with this second
instrument before any candidate stub is read.

A candidate stub starts with `// @producer-id <ident>` (the census JSON's `producers` key) and
`// @rows <file>:<line>[, …]`. It may carry `// @domain length-1` (a `Character` input).

  --self-test           the four domain counts and the shrink rule (no compiler; `make measurement-selftest`)
  controls              compile and run the harness controls PC1-PC9; exit non-zero on any miss
  run <out.json> STUB…  run each candidate stub over all four domains and record what each rejects
"""
import collections
import itertools
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

ALPHABET = "a.()+|^${}\\*?/[]"
EXTRA = "-z:"
PAIRS = {"[": "]", "(": ")", "{": "}"}
CLOSERS = set(PAIRS.values())
CONTROLS = "fixtures/regex-acceptor-census/stubs/controls"
PINNED_SWIFTC = os.path.expanduser(
    "~/Library/Developer/Toolchains/swift-6.4.1-RELEASE.xctoolchain/usr/bin/swiftc")
HANG_SECONDS = 60

DRIVER = """import Foundation

// One line to stdout per input that is declined (D), rejected (R), or rejected by the stub's acceptor
// but accepted by an untyped `Regex(_:)` (U); the index of each input to stderr before it runs. Both
// go through FileHandle, which does not buffer, so a trap leaves the index of the input that caused it.
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let inputs = try JSONDecoder().decode([String].self, from: data)
let start = Int(CommandLine.arguments[2]) ?? 0
for index in start..<inputs.count {
    FileHandle.standardError.write(Data("\\(index)\\n".utf8))
    guard let pattern = produce(inputs[index]) else {
        FileHandle.standardOutput.write(Data("D\\t\\(index)\\n".utf8))
        continue
    }
    if !accepts(pattern) {
        let untyped = (try? Regex(pattern)) != nil
        FileHandle.standardOutput.write(Data("\\(untyped ? "U" : "R")\\t\\(index)\\n".utf8))
    }
}
"""

PARSER_PROBE = """import Foundation

// PC6: which parser each silent acceptor uses on this machine (scope §4.2). Measured on macOS 27.2:
// `String`/`Substring` `range(of:options:)` parse with Swift Regex and fall back to ICU when Regex
// throws; `replacingOccurrences(of:with:options:)` parses with ICU alone.
let result: [String: Bool] = [
    "stringRangeAcceptsBareBrace": "x{a}y".range(of: "{a}", options: .regularExpression) != nil,
    "replacingIsICU": "x{a}y".replacingOccurrences(of: "{a}", with: "Q", options: .regularExpression) == "x{a}y",
    "regexRejectsDollarPlus": (try? Regex("$+")) == nil,
    "stringRangeFallsBackToICU": "a".range(of: "$+", options: .regularExpression) != nil,
    "substringRangeFallsBackToICU": "a"[...].range(of: "$+", options: .regularExpression) != nil,
    "stringRangeICUReadsKLiterally": "aK".range(of: "\\\\K", options: .regularExpression) != nil,
    "stringRangeRejectsWhereBothReject": "a\\\\".range(of: "a\\\\", options: .regularExpression) == nil,
]
FileHandle.standardOutput.write(try JSONEncoder().encode(result))
"""


def balanced(text):
    """#666's domain: each opener closed by its partner, no nesting, one or more alphanumerics
    inside, and no closer standing alone. Reproduces the issue's 11,177 and 31,115 exactly."""
    index = 0
    while index < len(text):
        char = text[index]
        if char in CLOSERS:
            return False
        if char in PAIRS:
            end = index + 1
            while end < len(text) and text[end].isalnum():
                end += 1
            if end == index + 1 or end >= len(text) or text[end] != PAIRS[char]:
                return False
            index = end + 1
        else:
            index += 1
    return True


def strings(alphabet, longest):
    for length in range(longest + 1):
        for chars in itertools.product(alphabet, repeat=length):
            yield "".join(chars)


def domains():
    """The scope's four domains, in a fixed order. §8 reads D4 and D4x only."""
    return {
        "D4": [text for text in strings(ALPHABET, 4) if balanced(text)],
        "D4x": [text for text in strings(ALPHABET + EXTRA, 4) if balanced(text)],
        "RAW2": list(strings(ALPHABET, 2)),
        "FREE3": list(strings(ALPHABET.replace("[", "").replace("]", ""), 3)),
    }


EXPECTED_COUNTS = {"D4": 11_177, "D4x": 31_115, "RAW2": 273, "FREE3": 2_955}
IN_DOMAIN = {
    "D4": lambda text: balanced(text) and set(text) <= set(ALPHABET),
    "D4x": lambda text: balanced(text) and set(text) <= set(ALPHABET + EXTRA),
    "RAW2": lambda text: set(text) <= set(ALPHABET),
    "FREE3": lambda text: set(text) <= set(ALPHABET) - {"[", "]"},
}


def minimal(text, failing, domain):
    """Scope §4.3's shrink: delete one character at a time, leftmost first, keeping the first deletion
    whose result is non-empty, in the domain and still failing the same way; repeat until none
    applies. Every domain is exhaustive over its lengths, so "still failing" is read from the run."""
    if text == "":
        return "EMPTY"
    while True:
        for index in range(len(text)):
            candidate = text[:index] + text[index + 1:]
            if candidate and IN_DOMAIN[domain](candidate) and candidate in failing:
                text = candidate
                break
        else:
            return text


def groups(failing, domain):
    found = collections.Counter(minimal(text, set(failing), domain) for text in failing)
    return dict(sorted(found.items()))


def self_test():
    counts = {name: len(values) for name, values in domains().items()}
    failures = [f"{name}: {counts[name]} inputs, expected {want}"
                for name, want in EXPECTED_COUNTS.items() if counts[name] != want]
    # The domain must keep G2's shape and drop the false region: `{a}` is in, a lone `[` is out.
    for text, want in (("{a}", True), ("[a]", True), ("(a)", True), ("[", False), ("[]", False),
                       ("}", False), ("[(a)]", False), ("[a-z]", False), ("a.b", True), ("", True)):
        if balanced(text) != want:
            failures.append(f"balanced({text!r}) is {not want}, expected {want}")
    # The shrink keeps within the domain: `{a}?` shrinks to `{a}`, not to `a}` (out of D4) or `?`.
    shrunk = groups(["{a}?", "{a}", "?{a}", ""], "D4")
    if shrunk != {"EMPTY": 1, "{a}": 3}:
        failures.append(f"shrink groups {shrunk}, expected {{'EMPTY': 1, '{{a}}': 3}}")
    for failure in failures:
        print(f"  FAIL  {failure}")
    print(f"regex_acceptor_precision self-test: {'FAILED' if failures else 'ok'} ({counts})")
    return not failures


def swiftc():
    return PINNED_SWIFTC if os.path.exists(PINNED_SWIFTC) else shutil.which("swiftc")


def toolchain():
    return subprocess.run([swiftc(), "--version"], capture_output=True, text=True).stdout.strip()


def machine():
    """What the run machine's parsers are: the OS build and SDK, beside the compiler (§4.2)."""
    def out(command):
        return subprocess.run(command, capture_output=True, text=True).stdout.strip()
    return {"swiftc": toolchain().splitlines()[0] if toolchain() else "unknown",
            "macos_build": out(["sw_vers", "-buildVersion"]), "macos": out(["sw_vers", "-productVersion"]),
            "sdk": out(["xcrun", "--sdk", "macosx", "--show-sdk-version"])}


def sdk():
    return subprocess.run(["xcrun", "--sdk", "macosx", "--show-sdk-path"],
                          capture_output=True, text=True, check=True).stdout.strip()


def compile_program(sources, workdir, binary_name):
    """`(binary, None)`, or `(None, first compiler error)`."""
    os.makedirs(workdir, exist_ok=True)
    names = []
    for name, text in sources.items():
        with open(os.path.join(workdir, name), "w", encoding="utf-8") as handle:
            handle.write(text)
        names.append(name)
    binary = os.path.join(workdir, binary_name)
    result = subprocess.run([swiftc(), "-O", "-sdk", sdk(), *names, "-o", binary], cwd=workdir,
                            capture_output=True, text=True)
    if result.returncode != 0:
        first = next((line for line in result.stderr.splitlines() if ": error:" in line), result.stderr.strip()[:300])
        return None, first
    return binary, None


class HardError(Exception):
    pass


def evaluate(binary, inputs, workdir):
    """`{rejected, declined, untyped, trapped}`. A death by signal, or no progress for HANG_SECONDS,
    marks the input in flight TRAPPED and resumes after it (§4.2). A non-zero exit is a hard error,
    never zero rejections."""
    path = os.path.join(workdir, "inputs.json")
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(inputs, handle)
    found = {"rejected": [], "declined": [], "untyped": [], "trapped": []}
    start = 0
    while start < len(inputs):
        try:
            result = subprocess.run([binary, path, str(start)], capture_output=True, timeout=HANG_SECONDS)
            code, out, err = result.returncode, result.stdout, result.stderr
        except subprocess.TimeoutExpired as expired:
            code, out, err = None, expired.stdout or b"", expired.stderr or b""
        for line in out.decode(errors="replace").splitlines():
            tag, index = line.split("\t")
            text = inputs[int(index)]
            if tag == "D":
                found["declined"].append(text)
            else:
                found["rejected"].append(text)
                if tag == "U":
                    found["untyped"].append(text)
        if code == 0:
            return found
        if code is not None and code > 0:
            raise HardError(f"exit {code}: {err.decode(errors='replace')[-500:]}")
        progress = [int(line) for line in err.decode(errors="replace").splitlines() if line.strip().isdigit()]
        if not progress:
            raise HardError(f"{'hung' if code is None else f'signal {-code}'} before any input: "
                            f"{err.decode(errors='replace')[-500:]}")
        found["trapped"].append(inputs[progress[-1]])
        start = progress[-1] + 1
    return found


def typed_acceptor(source):
    """CAPTURE-TYPE applies only when the stub's `accepts(_:)` uses a typed `Regex<…>` or `as:`."""
    return bool(re.search(r"\bRegex\s*<|\bas\s*:", source[source.index("func accepts"):]))


def run_stub(stub, workdir, all_domains):
    source = open(stub, encoding="utf-8").read()
    binary, error = compile_program({"main.swift": DRIVER, "stub.swift": source}, workdir, "run")
    if binary is None:
        return {"status": "UNSTUBBABLE", "first_error": error}
    typed = typed_acceptor(source)
    results = {}
    for name, values in all_domains.items():
        if "// @domain length-1" in source:
            values = [text for text in values if len(text) == 1]
        try:
            found = evaluate(binary, values, workdir)
        except HardError as error_:
            return {"status": "HARD-ERROR", "error": str(error_), "results": results}
        capture = set(found["untyped"]) if typed else set()
        syntax = [text for text in found["rejected"] if text not in capture]
        results[name] = {"inputs": len(values), "rejected": syntax, "capture_type": sorted(capture),
                         "declined": found["declined"], "trapped": found["trapped"],
                         "dialect_gap": found["untyped"] if not typed else [],
                         "groups": groups(syntax, name), "capture_type_groups": groups(sorted(capture), name),
                         "trapped_groups": groups(found["trapped"], name)}
    return {"status": "RUN", "typed": typed, "results": results}


def run_program(source, workdir):
    binary, error = compile_program({"main.swift": source}, workdir, "probe")
    if binary is None:
        raise SystemExit(f"parser probe does not compile: {error}")
    return json.loads(subprocess.run([binary], capture_output=True, text=True, check=True).stdout)


def controls():
    """PC1-PC9: #666's transcription numbers, re-taken by executing the real bodies; the run machine's
    parsers; and the TRAPPED and UNSTUBBABLE paths."""
    if not self_test():
        return False
    all_domains = domains()
    work = tempfile.mkdtemp(prefix="regex-acceptor-controls-")
    failures = []

    def check(label, condition, detail):
        print(f"  {'ok  ' if condition else 'FAIL'}  {label}: {detail}")
        if not condition:
            failures.append(label)

    def control(stub, label, wanted=None):
        result = run_stub(f"{CONTROLS}/{stub}", f"{work}/{label}",
                          all_domains if wanted is None else {name: all_domains[name] for name in wanted})
        if result["status"] != "RUN":
            check(label, False, f"{stub} did not run: {result}")
            return None
        return result["results"]

    try:
        g2 = control("g2-111d8bd.swift", "PC2")
        if g2:
            for name, want, want_groups in (("D4", 22, {"{a}": 22}), ("D4x", 58, {"{a}": 29, "{z}": 29})):
                hits = g2[name]["rejected"]
                check(f"PC2 {name}", len(hits) == want and all("}" in hit for hit in hits)
                      and g2[name]["groups"] == want_groups and not g2[name]["trapped"],
                      f"{len(hits)} rejected (want {want}), all containing '}}': {all('}' in hit for hit in hits)}, "
                      f"groups {g2[name]['groups']} (want {want_groups})")
        bracket = sorted(text for text in all_domains["RAW2"] if "[" in text)
        for label, stub in (("PC3", "glob-e36da59.swift"), ("PC4", "translate-12b0e90-wrapped.swift")):
            result = control(stub, label)
            if not result:
                continue
            for name in ("D4", "D4x", "FREE3"):
                check(f"{label} {name}", not result[name]["rejected"] and not result[name]["trapped"],
                      f"{len(result[name]['rejected'])} rejected (want 0)")
            check(f"{label} RAW2", sorted(result["RAW2"]["rejected"]) == bracket and result["RAW2"]["groups"] == {"[": 32},
                  f"{len(result['RAW2']['rejected'])} rejected (want the {len(bracket)} containing '['), "
                  f"groups {result['RAW2']['groups']}")
        bare = control("translate-12b0e90-unwrapped.swift", "PC5", ["D4"])
        if bare:
            check("PC5", bare["D4"]["rejected"] == [""] and bare["D4"]["groups"] == {"EMPTY": 1},
                  f"D4 rejects {bare['D4']['rejected'][:5]} (want only the empty input)")
        parsers = run_program(PARSER_PROBE, f"{work}/PC6")
        check("PC6", set(parsers.values()) == {True} and len(parsers) == 7, f"{parsers}")
        untyped = control("g2-111d8bd-regex.swift", "PC7a", ["D4"])
        if untyped:
            check("PC7 untyped", not untyped["D4"]["rejected"] and not untyped["D4"]["capture_type"],
                  f"111d8bd under Regex(_:) rejects {len(untyped['D4']['rejected'])} (want 0)")
        typed = control("glob-e36da59-regex-substring.swift", "PC7b", ["D4"])
        if typed:
            check("PC7 typed", len(typed["D4"]["capture_type"]) == 3492 and not typed["D4"]["rejected"],
                  f"e36da59 under Regex<Substring>: {len(typed['D4']['capture_type'])} CAPTURE-TYPE (want 3,492), "
                  f"{len(typed['D4']['rejected'])} syntax rejections (want 0)")
        trap = control("trap-on-brace.swift", "PC8", ["D4"])
        if trap:
            check("PC8", trap["D4"]["trapped"] == ["{a}"] and trap["D4"]["rejected"] == [""],
                  f"trapped {trap['D4']['trapped']} (want ['{{a}}']), rejected {trap['D4']['rejected'][:3]} (want [''])")
        broken = run_stub(f"{CONTROLS}/does-not-compile.swift", f"{work}/PC9", {"D4": all_domains["D4"]})
        check("PC9", broken["status"] == "UNSTUBBABLE" and "undefinedHelper" in broken["first_error"],
              f"{broken['status']}: {broken.get('first_error', '')[:120]}")
    finally:
        shutil.rmtree(work, ignore_errors=True)
    print(f"machine: {machine()}")
    print(f"regex_acceptor_precision controls: {'FAILED ' + str(failures) if failures else 'ok'}")
    return not failures


def run(out_path, stubs):
    if not controls():
        raise SystemExit("a harness control failed — not running any candidate stub")
    headers = {}
    for stub in stubs:
        source = open(stub, encoding="utf-8").read()
        ident = re.search(r"^// @producer-id (\S+)$", source, re.MULTILINE)
        rows = re.search(r"^// @rows (.+)$", source, re.MULTILINE)
        if not ident or not rows:
            raise SystemExit(f"{stub} has no `// @producer-id` or `// @rows` line (§4.2)")
        headers[stub] = (ident.group(1), [item.strip() for item in rows.group(1).split(",")])
    all_domains = domains()
    work = tempfile.mkdtemp(prefix="regex-acceptor-run-")
    report = {"machine": machine(), "domains": EXPECTED_COUNTS, "stubs": {}, "producers": {}}
    try:
        for index, stub in enumerate(stubs):
            ident, rows = headers[stub]
            result = run_stub(stub, f"{work}/{index}", all_domains)
            result.update({"producer_id": ident, "rows": rows})
            report["stubs"][os.path.relpath(stub)] = result
            entry = report["producers"].setdefault(ident, {"stubs": [], "statuses": []})
            entry["stubs"].append(os.path.relpath(stub))
            entry["statuses"].append(result["status"])
            summary = result["status"] if result["status"] != "RUN" else "  ".join(
                f"{name} {len(value['rejected'])}+{len(value['trapped'])}t {value['groups']}"
                for name, value in result["results"].items())
            print(f"  {os.path.basename(stub)}: {summary}")
    finally:
        shutil.rmtree(work, ignore_errors=True)
    for entry in report["producers"].values():
        entry["status"] = "RUN" if entry["statuses"] and all(status == "RUN" for status in entry["statuses"]) \
            else "UNSTUBBABLE"
    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=1, sort_keys=True)
        handle.write("\n")


def main(argv):
    if argv[1:] == ["--self-test"]:
        return 0 if self_test() else 1
    if argv[1:] == ["controls"]:
        return 0 if controls() else 1
    if len(argv) >= 4 and argv[1] == "run":
        run(argv[2], argv[3:])
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
