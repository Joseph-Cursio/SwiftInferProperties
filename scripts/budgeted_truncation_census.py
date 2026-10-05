#!/usr/bin/env python3
"""Is budgeted truncation a role with a population? — `docs/plans/budgeted-truncation-census-scope.md`.

A `func` with a body is a SHAPE row when it takes an integer budget, returns a sequence (String,
Substring, Data, an array, Self, a SubSequence, its own type, or a tuple led by one) and has a sequence
input (a parameter, or the type it extends). A SHAPE row with a truncation cue in its name, labels,
parameter names or body is a CANDIDATE; the rest are SHAPE-ONLY. SwiftAssist's
`String.prefix(utf8Bytes:)` is the motivating CANDIDATE.

  controls                 run the scope's four controls and exit non-zero if any fails
  run <out.json>           census the manifest corpora, the funnel repositories and the unmet subjects
"""
import json
import os
import random
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import measurement  # noqa: E402
from mutation_check import mask  # noqa: E402

HOME = os.path.expanduser("~")
FUNNEL = [
    "LintStudioUI", "MacCloud_client_MacOS", "MacCloud_server", "pbt-book", "pbt-workbook-corpus",
    "pbt-workbook-grader", "pbt-workbook-sampler", "pbt-workbook", "SwiftAssist", "SwiftCloneDetector",
    "SwiftEffectInference", "SwiftFormatRuleStudio", "SwiftIdempotency", "SwiftLintRuleStudio",
    "SwiftLintRuleStudioTeam", "SwiftMarkdownWiki", "SwiftProjectLint", "SwiftPropertyLaws", "SwiftUMLStudio",
]
UNMET = [
    "Euclid", "swift-docc", "OpenAPIKit", "jwt-kit", "swift-system", "Harbeth", "JiraKit", "nocturne-swift",
    "Open-Jellycore", "scale-codec-swift", "sora-ios-sdk", "StripeKit", "swift-codex",
]
CANDIDATE_CAP = 300
SHAPE_ONLY_SAMPLE = 40
SEED = 20261005

DECL = re.compile(r"\b(struct|class|enum|actor|extension|protocol)\s+([A-Za-z_][\w.]*)")
FUNC = re.compile(r"\bfunc\s+([A-Za-z_]\w*|`[^`]+`|[^\s(<]+)\s*(?:<[^{(]*?>)?\s*\(")
VISIBILITY = re.compile(r"\b(public|open|package|internal|fileprivate|private)\b")
INT_TYPES = {"Int", "UInt", "Int8", "Int16", "Int32", "Int64", "UInt8", "UInt16", "UInt32", "UInt64"}
SEQUENCE_RESULT = re.compile(
    r"^(?:Swift\.)?(?:String|Substring|Data|ByteBuffer|AttributedString|AttributedSubstring|Self"
    r"|SubSequence|[\w.]+\.SubSequence|(?:Array|ArraySlice|ContiguousArray)<.+>)$"
)
OWNER_FAMILY = {
    "String", "Substring", "StringProtocol", "Array", "ArraySlice", "ContiguousArray", "Data", "ByteBuffer",
    "AttributedString", "Sequence",
}
STEMS = ("truncat", "prefix", "suffix", "clip", "limit", "max", "trim", "shorten", "abbreviat", "ellips",
         "elid", "fit", "budget", "cut", "head", "tail", "byte", "width", "column", "length")
EXACT = {"cap", "capped", "capping", "char", "chars", "character", "characters"}
BODY_CALL = re.compile(r"\b(prefix|suffix|dropLast|dropFirst)\s*\(|limitedBy\s*:")
COMPARISON = re.compile(r"<=|>=|<|>")
MODIFIERS = re.compile(
    r"^(?:@\w+(?:\([^)]*\))?\s*|inout\s+|__owned\s+|__shared\s+|borrowing\s+|consuming\s+|sending\s+"
    r"|some\s+|any\s+)+"
)


def brace_pairs(masked):
    pairs, stack = {}, []
    for index, character in enumerate(masked):
        if character == "{":
            stack.append(index)
        elif character == "}" and stack:
            pairs[stack.pop()] = index
    return pairs


def split_top(text, separator=","):
    """`text` split on `separator` outside (), [], <> and {}."""
    parts, depth, current = [], 0, []
    for character in text:
        if character in "([<{":
            depth += 1
        elif character in ")]>}":
            depth -= 1
        if character == separator and depth == 0:
            parts.append("".join(current))
            current = []
        else:
            current.append(character)
    parts.append("".join(current))
    return [part.strip() for part in parts if part.strip()]


def strip_type(text):
    text = MODIFIERS.sub("", text.strip()).strip()
    text = text.split("=", 1)[0].strip() if "=" in text and "==" not in text else text
    while text.endswith(("?", "!")):
        text = text[:-1].strip()
    if text.endswith("..."):
        text = text[:-3].strip()
    return text


def base_name(text):
    return re.split(r"[<\s:]", text.strip(), maxsplit=1)[0].split(".")[-1]


def _top_level_colon(text):
    depth = 0
    for character in text:
        if character in "([<{":
            depth += 1
        elif character in ")]>}":
            depth -= 1
        elif character == ":" and depth == 0:
            return True
    return False


def is_sequence(text, owner):
    text = strip_type(text)
    if text.startswith("[") and text.endswith("]"):
        return not _top_level_colon(text[1:-1])
    return bool(SEQUENCE_RESULT.match(text)) or (owner is not None and base_name(text) == owner)


def result_head(result):
    """The type a result leads with: a tuple's first element, without its label."""
    text = strip_type(result)
    if text.startswith("(") and text.endswith(")"):
        elements = split_top(text[1:-1])
        if not elements:
            return ""
        first = elements[0]
        label = re.match(r"^[A-Za-z_]\w*\s*:(?!:)", first)
        return strip_type(first[label.end():] if label else first)
    return text


def parameters(text):
    """`(label, name, type)` for each parameter in a parameter list's text."""
    found = []
    for part in split_top(text):
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
        label, name = (names[0], names[-1]) if len(names) > 1 else (names[0], names[0])
        found.append((label, name, strip_type(part[colon + 1:])))
    return found


def words(identifier):
    return [w.lower() for w in re.findall(r"[A-Z]+(?![a-z])|[A-Z]?[a-z]+|\d+", identifier.strip("`"))]


def name_cue(identifiers):
    hits = []
    for identifier in identifiers:
        for word in words(identifier):
            if word in EXACT or word.startswith(STEMS):
                hits.append(word)
    return sorted(set(hits))


def body_cue(body, budgets):
    hits = sorted({m.group(1) or "limitedBy" for m in BODY_CALL.finditer(body)})
    if re.search(r"\bbreak\b", body):
        for line in body.splitlines():
            if COMPARISON.search(line) and any(re.search(rf"\b{re.escape(b)}\b", line) for b in budgets):
                hits.append("break-on-budget")
                break
    return hits


def functions(text):
    """Every `func` with a body in `text`, as a dict, with whether it is a SHAPE row and its cues."""
    masked, _ = mask(text)
    pairs = brace_pairs(masked)
    spans = []
    for match in DECL.finditer(masked):
        brace = masked.find("{", match.end())
        if brace < 0 or masked[match.end():brace].count("\n") > 3:
            continue
        line_start = masked.rfind("\n", 0, match.start()) + 1
        visibility = VISIBILITY.findall(masked[line_start:match.start()])
        spans.append((match.start(), pairs.get(brace, len(masked) - 1), base_name(match.group(2)),
                      match.group(1), visibility[-1] if visibility else ""))
    found = []
    for match in FUNC.finditer(masked):
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
        end = pairs.get(brace, len(masked) - 1)
        owners = [s for s in spans if s[0] < match.start() < s[1]]
        owner = min(owners, key=lambda s: s[1] - s[0]) if owners else None
        result = tail.split("->", 1)[1] if "->" in tail else ""
        result = re.split(r"\bwhere\b", result)[0].strip()
        for effect in ("async", "throws", "rethrows"):
            result = re.sub(rf"\b{effect}\b", "", result)
        params = parameters(masked[open_paren + 1:index])
        budgets = [name for _, name, kind in params if kind in INT_TYPES]
        owner_name = owner[2] if owner else None
        head = result_head(result) if result else ""
        sequence_result = bool(head) and is_sequence(head, owner_name)
        sequence_input = (
            any(is_sequence(kind, owner_name) for _, name, kind in params if name not in budgets)
            or (owner_name in OWNER_FAMILY or (owner_name or "").endswith("Collection"))
            or head in ("Self",) or head.endswith("SubSequence")
            or (owner_name is not None and base_name(head) == owner_name)
        )
        shape = bool(budgets) and sequence_result and sequence_input
        body = masked[brace + 1:end]
        line_start = masked.rfind("\n", 0, match.start()) + 1
        visibility = VISIBILITY.findall(masked[line_start:match.start()])
        name = match.group(1)
        found.append({
            "name": name,
            "signature": " ".join(masked[match.start():brace].split()),
            "line": text.count("\n", 0, match.start()) + 1,
            "owner": owner_name or "",
            "owner_kind": owner[3] if owner else "",
            "visibility": visibility[-1] if visibility else (owner[4] if owner else ""),
            "result": head,
            "budgets": budgets,
            "shape": shape,
            "name_cue": name_cue([name] + [l for l, _, _ in params if l != "_"] + [n for _, n, _ in params])
            if shape else [],
            "body_cue": body_cue(body, budgets) if shape else [],
        })
    return found


def controls():
    swiftassist = '''
extension String {
    public func prefix(utf8Bytes limit: Int) -> (text: String, didTruncate: Bool) {
        guard limit > 0 else { return ("", !isEmpty) }
        guard utf8.count > limit else { return (self, false) }

        var result = ""
        var used = 0
        for character in self {
            let width = String(character).utf8.count
            guard used + width <= limit else { break }
            result.append(character)
            used += width
        }
        return (result, true)
    }
}'''
    truncated = "extension String {\n    func truncated(to limit: Int) -> String { String(prefix(limit)) }\n}"
    repeated = ("extension String {\n    func repeated(_ times: Int) -> String {\n"
                "        String(repeating: self, count: times)\n    }\n}")
    count = "struct Bag {\n    func count(of x: Int) -> Int { x }\n}"

    def only(source):
        rows = functions(source)
        return rows[0] if len(rows) == 1 else None

    first, second, third, fourth = only(swiftassist), only(truncated), only(repeated), only(count)
    results = {
        "prefix(utf8Bytes:) is a CANDIDATE with both cues": bool(
            first and first["shape"] and first["name_cue"] and "break-on-budget" in first["body_cue"]),
        "truncated(to:) is a CANDIDATE": bool(second and second["shape"] and (second["name_cue"] or second["body_cue"])),
        "repeated(_:) is SHAPE-ONLY": bool(third and third["shape"] and not third["name_cue"] and not third["body_cue"]),
        "count(of:) is not a SHAPE row": bool(fourth and not fourth["shape"]),
    }
    for name, ok in results.items():
        print(f"  control {'ok ' if ok else 'FAIL'} {name}")
    return all(results.values())


def swift_files(base):
    """`measurement.swift_files`, also skipping hidden directories: a checkout's `.claude/worktrees`
    holds whole copies of its sources, which would count each function once per copy."""
    for path in measurement.swift_files(base):
        relative = os.path.relpath(path, base)
        if not any(part.startswith(".") for part in relative.split(os.sep)[:-1]):
            yield path


def revision(root):
    try:
        out = subprocess.run(["git", "-C", root, "rev-parse", "HEAD"], capture_output=True, text=True, check=True)
        return out.stdout.strip()
    except (subprocess.CalledProcessError, OSError):
        return None


def subjects():
    """`(group, name, repo root, scan roots)` for every subject, and the missing ones."""
    found, missing = [], []
    manifest = json.load(open("fixtures/corpora/manifest.json", encoding="utf-8"))["corpora"]
    for corpus in manifest:
        local = corpus.get("localPath")
        candidates = [os.path.abspath(os.path.expanduser(local))] if local else []
        if local:
            candidates.append(os.path.join(HOME, "github_projects", os.path.basename(local.rstrip("/"))))
        root = next((c for c in candidates if os.path.isdir(c)), None)
        if root is None:
            missing.append(("manifest", corpus["id"]))
            continue
        if candidates and root != candidates[0]:
            print(f"  manifest {corpus['id']}: localPath missing, using {root}")
        found.append(("manifest", corpus["id"], root, measurement.source_dirs(root, corpus) or [root]))
    for group, names, base in (("funnel", FUNNEL, "xcode_projects"), ("unmet", UNMET, "github_projects")):
        for name in names:
            root = os.path.join(HOME, base, name)
            if os.path.isdir(root):
                found.append((group, name, root, [root]))
            else:
                missing.append((group, name))
    return found, missing


def run(out_path):
    if not controls():
        raise SystemExit("a control failed — not reporting a population")
    found, missing = subjects()
    report = {"subjects": [], "missing": [{"group": g, "subject": n} for g, n in missing], "rows": []}
    for group, name, root, roots in found:
        files = functions_scanned = shape = candidates = 0
        for scan_root in roots:
            for path in swift_files(scan_root):
                try:
                    text = open(path, encoding="utf-8", errors="ignore").read()
                except OSError:
                    continue
                files += 1
                for row in functions(text):
                    functions_scanned += 1
                    if not row["shape"]:
                        continue
                    shape += 1
                    is_candidate = bool(row["name_cue"] or row["body_cue"])
                    candidates += is_candidate
                    report["rows"].append(dict(row, group=group, subject=name,
                                               file=os.path.relpath(path, root),
                                               realpath=os.path.realpath(path),
                                               kind="CANDIDATE" if is_candidate else "SHAPE-ONLY"))
        report["subjects"].append({"group": group, "subject": name, "revision": revision(root),
                                   "swift_files": files, "functions": functions_scanned,
                                   "shape": shape, "candidates": candidates})
        print(f"{group:9} {name:26} files {files:>5}  funcs {functions_scanned:>6}  shape {shape:>4}  "
              f"candidates {candidates:>3}")
    seen, unique = set(), {"CANDIDATE": [], "SHAPE-ONLY": []}
    for row in report["rows"]:
        key = (row["realpath"], row["line"])
        if key not in seen:
            seen.add(key)
            unique[row["kind"]].append(row)
    rng = random.Random(SEED)
    checked = unique["CANDIDATE"] if len(unique["CANDIDATE"]) <= CANDIDATE_CAP \
        else rng.sample(unique["CANDIDATE"], CANDIDATE_CAP)
    sample = rng.sample(unique["SHAPE-ONLY"], min(SHAPE_ONLY_SAMPLE, len(unique["SHAPE-ONLY"])))
    for index, row in enumerate(sorted(checked, key=lambda r: (r["realpath"], r["line"]))):
        row["check_id"] = f"C{index + 1:03d}"
    for index, row in enumerate(sorted(sample, key=lambda r: (r["realpath"], r["line"]))):
        row["check_id"] = f"S{index + 1:03d}"
    report["totals"] = {"subjects": len(found), "missing": len(missing),
                        "unique_candidates": len(unique["CANDIDATE"]),
                        "unique_shape_only": len(unique["SHAPE-ONLY"]),
                        "checked_candidates": len(checked), "checked_shape_only": len(sample)}
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
