#!/usr/bin/env python3
"""Does "nil means the default" have a population? — `docs/plans/nil-default-census-scope.md`.

For every `func` and `init` with a body, an optional parameter `p` whose every read is `p ?? D`, with the
same `D` each time, is a SHAPE row when the declaration has a value to compare (a non-`Void` result, or an
`init`). The law a template would propose is `f(…, p: nil, …) == f(…, p: D, …)`. SwiftAssist's
`ReadWindow.resolve` (`startLine ?? 1`, `maxLines ?? cap`) is the motivating case.

  controls                 run the scope's six controls and exit non-zero if any fails
  run <out.json>           census the same 53 subjects as the budgeted-truncation census
"""
import json
import os
import random
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import budgeted_truncation_census as population  # noqa: E402  (subjects, file walk, brace matching)
from mutation_check import mask  # noqa: E402

CAP = 300
SEED = 20261005
FUNC = re.compile(r"\bfunc\s+([A-Za-z_]\w*|`[^`]+`|[^\s(<]+)\s*(?:<[^{(]*?>)?\s*\(")
INIT = re.compile(r"\binit\s*[?!]?\s*(?:<[^>{(]*>)?\s*\(")
STOPS_AT_DEPTH_ZERO = (",", ")", "]", "}", ";", "{", "\n")
STOP_OPERATORS = ("==", "!=", "<=", ">=", "&&", "||", " < ", " > ", " ? ", " = ", " : ")
LITERAL = re.compile(r'-?[\d_][\d_.]*|-?0x[\da-fA-F_]+|"(?:[^"\\]|\\.)*"|true|false|nil|\[\s*\]|\[\s*:\s*\]')
MEMBER = re.compile(r"\.[A-Za-z_]\w*|(?:Self|[A-Z]\w*)(?:\.[A-Za-z_]\w*)+")
IDENTIFIER = re.compile(r"(?<![\w.$])[A-Za-z_]\w*")


def raw_parameters(text):
    """`(name, type)` for each parameter, the type as written (its `?` kept), its default value dropped."""
    found = []
    for part in population.split_top(text):
        part = re.sub(r"@\w+(?:\([^)]*\))?\s*", "", part)
        depth, colon = 0, -1
        for index, character in enumerate(part):
            if character in "([<{":
                depth += 1
            elif character in ")]>}":
                depth -= 1
            elif character == ":" and depth == 0:
                colon = index
                break
        if colon < 0:
            continue
        names = part[:colon].split()
        if not names:
            continue
        kind = part[colon + 1:]
        assignment = re.search(r"(?<![=!<>])=(?!=)", kind)
        if assignment:
            kind = kind[:assignment.start()]
        found.append((names[-1], kind.strip()))
    return found


def is_optional(kind):
    kind = re.sub(r"^(?:inout|__owned|__shared|borrowing|consuming|sending)\s+", "", kind.strip())
    return kind.endswith("?") or kind.startswith("Optional<")


def default_after(masked, text, start):
    """The default `D` after a `??` that ends at `start`: up to the first stop at depth 0, from `text`."""
    while start < len(masked) and masked[start] in " \t":
        start += 1
    # A closure default (`?? { _ in }`) is one operand: its braces nest like brackets.
    openers, closers = ("([{", ")]}") if masked[start:start + 1] == "{" else ("([", ")]")
    index, depth = start, 0
    while index < len(masked):
        character = masked[index]
        opens_the_default = index == start and character in openers
        if depth == 0 and not opens_the_default:
            if character in STOPS_AT_DEPTH_ZERO:
                break
            if any(masked.startswith(op, index) for op in STOP_OPERATORS):
                break
        if character in openers:
            depth += 1
        elif character in closers:
            depth -= 1
            if depth < 0:
                break
        index += 1
    return text[start:index].strip()


def default_kind(default, params):
    if LITERAL.fullmatch(default):
        return "literal"
    if MEMBER.fullmatch(default):
        return "enum-or-static-member"
    if "(" in default or default.startswith("{"):
        return "call-or-closure"
    if default in params:
        return "other-parameter"
    names = IDENTIFIER.findall(re.sub(r'"(?:[^"\\]|\\.)*"', '""', default))
    if names and all(name in params for name in names):
        return "expression-of-parameters"
    return "instance-state-or-other"


def doc_comment(lines, declaration_line):
    """The `///` lines directly above a declaration (attributes skipped), joined."""
    index, doc = declaration_line - 2, []
    while index >= 0:
        stripped = lines[index].strip()
        if stripped.startswith("@"):
            index -= 1
            continue
        if stripped.startswith("///"):
            doc.insert(0, stripped[3:].strip())
            index -= 1
            continue
        break
    return " ".join(doc)[:600]


def declarations(text):
    """Every optional parameter of every `func`/`init` with a body, classified SHAPE, MIXED, VOID or unread."""
    masked, _ = mask(text)
    pairs = population.brace_pairs(masked)
    lines = text.splitlines()
    spans = []
    for match in population.DECL.finditer(masked):
        brace = masked.find("{", match.end())
        if brace < 0 or masked[match.end():brace].count("\n") > 3:
            continue
        line_start = masked.rfind("\n", 0, match.start()) + 1
        visibility = population.VISIBILITY.findall(masked[line_start:match.start()])
        spans.append((match.start(), pairs.get(brace, len(masked) - 1), population.base_name(match.group(2)),
                      visibility[-1] if visibility else ""))
    found = []
    for kind, pattern in (("func", FUNC), ("init", INIT)):
        for match in pattern.finditer(masked):
            if kind == "init" and masked[max(0, match.start() - 1)] in ".":
                continue  # `.init(` is a call, not a declaration
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
            if brace < 0:
                continue
            tail = masked[index + 1:brace]
            if tail.count("\n") > 4 or any(t in tail for t in (";", "}", "func ", " var ", " let ")):
                continue
            params = raw_parameters(masked[open_paren + 1:index])
            optional = [name for name, kind_text in params if is_optional(kind_text) and name != "_"]
            if not optional:
                continue
            result = tail.split("->", 1)[1] if "->" in tail else ""
            result = re.split(r"\bwhere\b", result)[0]
            for effect in ("async", "throws", "rethrows"):
                result = re.sub(rf"\b{effect}\b", "", result)
            result = result.strip()
            has_value = kind == "init" or result not in ("", "Void", "()")
            end = pairs.get(brace, len(masked) - 1)
            body_start = brace + 1
            body = masked[body_start:end]
            owners = [s for s in spans if s[0] < match.start() < s[1]]
            owner = min(owners, key=lambda s: s[1] - s[0]) if owners else None
            line_start = masked.rfind("\n", 0, match.start()) + 1
            visibility = population.VISIBILITY.findall(masked[line_start:match.start()])
            line = text.count("\n", 0, match.start()) + 1
            names = [name for name, _ in params]
            for name in optional:
                reads = [m for m in re.finditer(rf"(?<![\w.$\\]){re.escape(name)}\b(?!\s*:(?!:))", body)]
                if not reads:
                    continue
                defaults, coalesced = [], True
                for read in reads:
                    after = body_start + read.end()
                    operator = re.match(r"\s*\?\?(?!\?)", masked[after:])
                    if not operator:
                        coalesced = False
                        break
                    defaults.append(default_after(masked, text, after + operator.end()))
                same = coalesced and len({" ".join(d.split()) for d in defaults}) == 1
                category = "MIXED" if not same else ("SHAPE" if has_value else "VOID")
                default = defaults[0] if same else ""
                found.append({
                    "category": category, "kind": kind, "name": match.group(1) if kind == "func" else "init",
                    "signature": " ".join(masked[match.start():brace].split())[:240], "line": line,
                    "owner": owner[2] if owner else "", "param": name, "reads": len(reads),
                    "default": default, "default_kind": default_kind(default, names) if same else "",
                    "result": result if kind == "func" else (owner[2] if owner else ""),
                    "visibility": visibility[-1] if visibility else (owner[3] if owner else ""),
                    "doc": doc_comment(lines, line) if category == "SHAPE" else "",
                })
    return found


def controls():
    resolve = '''
public struct ReadWindow: Equatable, Sendable {
    public static func resolve(
        lineCount: Int,
        startLine: Int?,
        maxLines: Int?,
        cap: Int
    ) -> Self? {
        let start = max(startLine ?? 1, 1)
        let span = min(max(maxLines ?? cap, 1), max(cap, 1))
        let beginIndex = start - 1

        // Ordered before the addition below, which is also what keeps `startLine: .max` from
        // overflowing: any start past the end leaves here first.
        guard beginIndex < lineCount else { return nil }

        let endIndex = min(beginIndex + span, lineCount)
        return Self(
            beginIndex: beginIndex,
            endIndex: endIndex,
            isTruncated: endIndex < lineCount
        )
    }
}'''

    def rows(source):
        return declarations(source)

    shapes = sorted((r["param"], r["default"]) for r in rows(resolve) if r["category"] == "SHAPE")
    literal = rows('func k(label x: String?) -> String { x ?? "none" }')
    parenthesised = rows("func m(_ x: Int?) -> Int { (x ?? 1) + 2 }")
    unwrapped = rows("func f(x: Int?) -> Int { if let x { return x }; return 0 }")
    mixed = rows("func g(x: Int?) -> Int { let y = x ?? 0; return x == nil ? y : y + 1 }")
    void = rows("func h(x: Int?) { print(x ?? 0) }")
    results = {
        "resolve gives startLine = 1 and maxLines = cap": shapes == [("maxLines", "cap"), ("startLine", "1")],
        'x ?? "none" keeps its string literal': [(r["category"], r["default"]) for r in literal] == [("SHAPE", '"none"')],
        "(x ?? 1) + 2 gives D = 1": [(r["category"], r["default"]) for r in parenthesised] == [("SHAPE", "1")],
        "if let x gives no SHAPE row": all(r["category"] != "SHAPE" for r in unwrapped),
        "x ?? 0 beside x == nil is MIXED": [r["category"] for r in mixed] == ["MIXED"],
        "print(x ?? 0) in a Void func is VOID": [r["category"] for r in void] == ["VOID"],
    }
    for name, ok in results.items():
        print(f"  control {'ok ' if ok else 'FAIL'} {name}")
    return all(results.values())


def run(out_path):
    if not controls():
        raise SystemExit("a control failed — not reporting a population")
    found, missing = population.subjects()
    report = {"subjects": [], "missing": [{"group": g, "subject": n} for g, n in missing], "rows": []}
    seen = set()
    unique = []
    for group, name, root, roots in found:
        counts = {"swift_files": 0, "SHAPE": 0, "MIXED": 0, "VOID": 0}
        for scan_root in roots:
            for path in population.swift_files(scan_root):
                try:
                    text = open(path, encoding="utf-8", errors="ignore").read()
                except OSError:
                    continue
                counts["swift_files"] += 1
                for row in declarations(text):
                    counts[row["category"]] += 1
                    if row["category"] != "SHAPE":
                        continue
                    key = (os.path.realpath(path), row["line"], row["param"])
                    row = dict(row, group=group, subject=name, file=os.path.relpath(path, root))
                    report["rows"].append(row)
                    if key not in seen:
                        seen.add(key)
                        unique.append(row)
        report["subjects"].append(dict(counts, group=group, subject=name, revision=population.revision(root)))
        print(f"{group:9} {name:26} files {counts['swift_files']:>5}  SHAPE {counts['SHAPE']:>4}  "
              f"MIXED {counts['MIXED']:>4}  VOID {counts['VOID']:>4}")
    checked = unique if len(unique) <= CAP else random.Random(SEED).sample(unique, CAP)
    for index, row in enumerate(sorted(checked, key=lambda r: (r["subject"], r["file"], r["line"], r["param"]))):
        row["check_id"] = f"N{index + 1:03d}"
    report["totals"] = {"subjects": len(found), "missing": len(missing), "unique_shape": len(unique),
                        "checked": len(checked)}
    print(json.dumps(report["totals"]))
    json.dump(report, open(out_path, "w"), indent=1, sort_keys=True)
    return 0


def main(argv):
    if len(argv) > 1 and argv[1] == "controls":
        return 0 if controls() else 1
    if len(argv) > 2 and argv[1] == "run":
        return run(argv[2])
    raise SystemExit(__doc__)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
