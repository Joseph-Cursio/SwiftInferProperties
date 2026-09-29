#!/usr/bin/env python3
"""Do decoders skip the validation their own initializers make? — `docs/plans/decoder-bypass-census-scope.md`.

A type is FLAGGED when, across its declaration and extensions, some initializer other than
`init(from decoder:)` rejects input, and its `init(from decoder:)` neither delegates (`self.init(`) nor
rejects anything itself — Harbeth's `Matrix3x3`, whose decoder admits `[1,2]` and whose `to_factor()`
then traps.

  controls                          run the scope's three controls and exit non-zero if any fails
  run <out.json> <group>=<dir> …    census each directory (a package root) under a named group
"""
import collections
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import measurement  # noqa: E402
from mutation_check import mask  # noqa: E402

DECL = re.compile(r"\b(struct|class|enum|actor|extension)\s+([A-Za-z_][\w.]*)")
INIT = re.compile(r"\binit\s*[?!]?\s*(?:<[^>{]*>)?\s*\(")
DECODER = re.compile(r"^\(\s*from\s+decoder\b")
REJECTS = re.compile(
    r"\b(?:precondition|assert|fatalError|preconditionFailure|assertionFailure)\s*\("
    r"|\bthrow\b|\breturn\s+nil\b|\bguard\b[^{}]*\belse\b"
)
# Harbeth's form: `if values.count != 9 { HarbethError.failed("…") }` — a failure-named call in an `if`.
FAILURE_CALL = re.compile(r"\bif\b[^{}]*\{[^{}]*\b\w*(?:[Ff]ail|[Ff]atal|[Cc]rash|[Aa]bort|[Ee]rror)\w*\s*\(")


def matching(text, open_index):
    depth = 0
    for index in range(open_index, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return index
    return len(text) - 1


def rejects(body):
    return bool(REJECTS.search(body) or FAILURE_CALL.search(body))


def brace_pairs(masked):
    """{open index: close index} for every brace, in one pass — rescanning per declaration was
    quadratic on the compiler corpus's largest files."""
    pairs, stack = {}, []
    for index, character in enumerate(masked):
        if character == "{":
            stack.append(index)
        elif character == "}" and stack:
            pairs[stack.pop()] = index
    return pairs


def initializers(text):
    """`(type name, is_decoder, signature, body, rejects, delegates, line)` for every init in `text`."""
    masked, _ = mask(text)
    pairs = brace_pairs(masked)
    spans = []
    for match in DECL.finditer(masked):
        brace = masked.find("{", match.end())
        # A declaration's body opens within a few lines (a long `where` clause at most).
        if brace < 0 or masked[match.end():brace].count("\n") > 3:
            continue
        spans.append((match.start(), pairs.get(brace, len(masked) - 1), match.group(2).split(".")[-1].split("<")[0]))
    found = []
    for match in INIT.finditer(masked):
        open_paren = match.end() - 1
        depth, index = 0, open_paren
        while index < len(masked):
            if masked[index] == "(":
                depth += 1
            elif masked[index] == ")":
                depth -= 1
                if depth == 0:
                    break
            index += 1
        brace = masked.find("{", index)
        if brace < 0 or masked[index:brace].count("\n") > 4 or ";" in masked[index:brace]:
            continue
        end = pairs.get(brace, len(masked) - 1)
        owners = [s for s in spans if s[0] < match.start() < s[1]]
        if not owners:
            continue
        owner = min(owners, key=lambda s: s[1] - s[0])[2]
        body = masked[brace + 1:end]
        signature = masked[match.start():brace].strip()
        found.append((owner, bool(DECODER.match(masked[open_paren:index + 1])), " ".join(signature.split()),
                      body, rejects(body), "self.init(" in body, text.count("\n", 0, match.start()) + 1))
    return found


def census_text(files):
    """{type: {'validating': [...], 'decoders': [...]}} over `(path, text)` pairs."""
    types = collections.defaultdict(lambda: {"validating": [], "decoders": []})
    for path, text in files:
        for owner, is_decoder, signature, _body, rejecting, delegating, line in initializers(text):
            entry = {"file": path, "line": line, "signature": signature, "rejects": rejecting,
                     "delegates": delegating}
            if is_decoder:
                types[owner]["decoders"].append(entry)
            elif rejecting:
                types[owner]["validating"].append(entry)
    return types


def flagged(types):
    rows = []
    for name, entry in sorted(types.items()):
        bypassing = [d for d in entry["decoders"] if not d["delegates"] and not d["rejects"]]
        if entry["validating"] and bypassing:
            rows.append({"type": name, "validating": entry["validating"][:3], "decoder": bypassing[0]})
    return rows


def controls():
    harbeth = """
    public struct Matrix3x3: Codable {
        public var values: [Float]
        public init(values: [Float]) {
            if values.count != 9 {
                HarbethError.failed("There must be nine values for 3x3 Matrix.")
            }
            self.values = values
        }
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            self.values = try container.decode([Float].self)
        }
    }"""
    delegating = """
    struct Pair: Codable {
        let values: [Int]
        init(values: [Int]) { precondition(values.count == 2); self.values = values }
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            self.init(values: try container.decode([Int].self))
        }
    }"""
    rechecking = """
    struct Pair: Codable {
        let values: [Int]
        init(values: [Int]) { precondition(values.count == 2); self.values = values }
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let values = try container.decode([Int].self)
            guard values.count == 2 else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "") }
            self.values = values
        }
    }"""
    results = {
        "harbeth flagged": [r["type"] for r in flagged(census_text([("h.swift", harbeth)]))] == ["Matrix3x3"],
        "delegating decoder not flagged": not flagged(census_text([("d.swift", delegating)])),
        "re-checking decoder not flagged": not flagged(census_text([("r.swift", rechecking)])),
    }
    for name, ok in results.items():
        print(f"  control {'ok ' if ok else 'FAIL'} {name}")
    return all(results.values())


def package_files(roots):
    """`(path, text)` for every Swift file under `roots`, streamed — holding the compiler corpus in
    memory at once got the process killed."""
    for root in roots:
        for path in measurement.swift_files(root):
            try:
                yield path, open(path, encoding="utf-8", errors="ignore").read()
            except OSError:
                pass


def run(out_path, groups):
    if not controls():
        raise SystemExit("a control failed — not reporting a population")
    report = {"groups": {}}
    # Manifest corpora are scanned through `measurement.source_dirs`, the scope every census here
    # uses; `manifest=*` expands to all of them. Other groups name a package root.
    specs = []
    for spec in groups:
        group, value = spec.split("=", 1)
        if group == "manifest" and value == "*":
            rows, asked = measurement.corpus_roots()
            print(f"manifest: {len(rows)} of {asked} corpora resolve")
            specs += [("manifest", corpus_id, dirs or [root]) for corpus_id, root, dirs in rows]
        else:
            specs.append((group, os.path.basename(os.path.normpath(value)), [value]))
    for group, name, roots in specs:
        counted = []

        def stream():
            for item in package_files(roots):
                counted.append(1)
                yield item
        types = census_text(stream())
        rows = flagged(types)
        with_decoder = sum(1 for t in types.values() if t["decoders"])
        report["groups"].setdefault(group, []).append({
            "subject": name, "roots": roots, "swift_files": len(counted),
            "types_with_decoder": with_decoder, "flagged": rows})
        print(f"{group:10} {name:28} files {len(counted):>5}  types with init(from:) {with_decoder:>4}  flagged {len(rows):>3}")
    json.dump(report, open(out_path, "w"), indent=1, sort_keys=True)
    return 0


def main(argv):
    if len(argv) > 1 and argv[1] == "controls":
        return 0 if controls() else 1
    if len(argv) > 2 and argv[1] == "run":
        return run(argv[2], argv[3:])
    raise SystemExit(__doc__)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
