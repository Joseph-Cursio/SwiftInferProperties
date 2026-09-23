#!/usr/bin/env python3
"""How many `String -> String` functions are a pure chain of `replacingOccurrences(of:with:)`, and how
many of those are NOT idempotent — the population for an "idempotence except for escape" rule.

`docs/measurements/funnel-mutation-check.md` §8 found six false `idempotence` laws, four of them
escapers of exactly this shape: `HTMLEscaping.escape` rewrites `&` to `&amp;`, whose output contains
`&` again, so escaping twice escapes the escape. `idempotence` applies to every `(T) -> T`, so every
such chain gets the law proposed under `--include-possible`.

## The rule is decided by evaluation, not by a text check

The obvious static rule — *not idempotent when some replacement contains some pattern* — is wrong in
one direction: `x → y` then `y → z` has an output containing a later pattern and is idempotent,
because the later step rewrites it in the same pass. So each chain is EVALUATED: `f(f(s)) == f(s)`
over every string up to length 3 drawn from the chain's own characters plus a neutral one. That is
exact on the domain it covers, and a counterexample it finds is a real one.

    python3 scripts/replacement_chain_census.py            # 20-corpus manifest + the funnel repos
    python3 scripts/replacement_chain_census.py --self-test
"""
import itertools
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import measurement  # noqa: E402
import mutation_check as mc  # noqa: E402

FUNNEL_REPOS = ["SwiftProjectLint", "SwiftUMLStudio", "SwiftAssist", "SwiftLintRuleStudio",
                "SwiftFormatRuleStudio", "SwiftMarkdownWiki", "SwiftCloneDetector", "LintStudioUI",
                "MacCloud_server", "SwiftIdempotency", "SwiftPropertyLaws", "SwiftEffectInference",
                "MacCloud_client_MacOS", "SwiftLintRuleStudioTeam"]

DECL = re.compile(r"\bfunc\s+(\w+)\s*\(\s*(?:\w+\s+)?\w+\s*:\s*String\s*\)\s*->\s*String\s*\{"
                  r"|\bvar\s+(\w+)\s*:\s*String\s*\{")
LIT = r'"(?:[^"\\\n]|\\.)*"'
STEP = re.compile(r"\s*\.replacingOccurrences\(\s*of:\s*(" + LIT + r")\s*,\s*with:\s*(" + LIT + r")\s*\)")
ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "0": "\0", '"': '"', "\\": "\\", "'": "'"}


def decode(literal):
    body, out, index = literal[1:-1], [], 0
    while index < len(body):
        if body[index] == "\\":
            nxt = body[index + 1]
            if nxt == "u":
                close = body.index("}", index)
                out.append(chr(int(body[index + 3:close], 16)))
                index = close + 1
                continue
            out.append(ESCAPES.get(nxt, nxt))
            index += 2
        else:
            out.append(body[index])
            index += 1
    return "".join(out)


def chain_of(body):
    """The `(pattern, replacement)` steps if `body` is ONLY a replacement chain, else `None`."""
    text = body.strip()
    text = re.sub(r"^return\s+", "", text)
    # ⚠ **Implicit `self`**: `var xmlEscaped: String { replacingOccurrences(of: …) … }` has no
    # receiver and no leading dot, and the first version read the method name AS the receiver —
    # missing both `String` extension escapers the funnel had already shown to be false laws.
    if text.startswith("replacingOccurrences("):
        text = "." + text
    head = re.match(r"(?:self|\w+)?", text)
    rest, steps = text[head.end():], []
    while rest.strip():
        step = STEP.match(rest)
        if not step:
            return None
        steps.append((decode(step.group(1)), decode(step.group(2))))
        rest = rest[step.end():]
    return steps or None


def apply(steps, text):
    for pattern, replacement in steps:
        if pattern:
            text = text.replace(pattern, replacement)
    return text


def counterexample(steps, length=3):
    """A string `s` with `f(f(s)) != f(s)`, or `None` if none exists up to `length`."""
    alphabet = sorted({ch for pattern, replacement in steps for ch in pattern + replacement} | {"x"})[:9]
    for size in range(1, length + 1):
        for letters in itertools.product(alphabet, repeat=size):
            text = "".join(letters)
            once = apply(steps, text)
            if apply(steps, once) != once:
                return text
    return None


def functions_in(path):
    source = open(path, encoding="utf-8", errors="ignore").read()
    masked, _ = mc.mask(source)
    for match in DECL.finditer(masked):
        brace = match.end() - 1
        try:
            end = mc.matching(masked, brace)
        except ValueError:
            continue
        yield match.group(1) or match.group(2), source[brace + 1:end]


def census(files):
    rows, mixed = [], 0
    for path in files:
        for name, body in functions_in(path):
            steps = chain_of(body)
            if not steps and "replacingOccurrences(" in body:
                mixed += 1
            if steps:
                witness = counterexample(steps)
                rows.append({"file": path, "name": name, "steps": len(steps),
                             "idempotent": witness is None, "witness": witness})
    return rows, mixed


def universes():
    manifest = []
    rows, asked = measurement.corpus_roots()
    print(f"manifest: {len(rows)} of {asked} corpora resolve on this machine")
    for _identifier, _root, directories in rows:
        for directory in directories:
            manifest += measurement.swift_files(directory)
    funnel = []
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    for repo in FUNNEL_REPOS:
        base = os.path.join(os.path.dirname(here), repo)
        funnel += [p for p in measurement.swift_files(base) if "/Tests/" not in p]
    return {f"manifest ({len(rows)} of {asked} corpora)": manifest, "funnel repositories": funnel}


def self_test():
    """Positive controls: the detector must see each shape and the rule must decide each correctly."""
    cases = {
        "html": ('text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")', False),
        "mermaid": ('text.replacingOccurrences(of: "\\"", with: "&quot;").replacingOccurrences(of: "|", with: "&#124;")', True),
        "later-step": ('text.replacingOccurrences(of: "x", with: "y").replacingOccurrences(of: "y", with: "z")', True),
        "quote": ('text.replacingOccurrences(of: "\\"", with: "\\\\\\"")', False),
        "implicit-self": ('replacingOccurrences(of: "&", with: "&amp;")\n    .replacingOccurrences(of: ">", with: "&gt;")', False),
        "not-a-chain": ('text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "a", with: "b")', None),
    }
    for label, (body, expected) in cases.items():
        steps = chain_of(body)
        verdict = None if steps is None else counterexample(steps) is None
        assert verdict == expected, f"{label}: expected {expected}, got {verdict}"
    print(f"self-test: {len(cases)} of {len(cases)} controls decided correctly")


def main(argv):
    if "--self-test" in argv:
        self_test()
        return 0
    self_test()
    report = {}
    for label, files in universes().items():
        rows, mixed = census(files)
        closed = [r for r in rows if r["idempotent"]]
        broken = [r for r in rows if not r["idempotent"]]
        print(f"\n{label}: {len(files)} files, {len(rows)} pure replacement chains — "
              f"{len(closed)} idempotent, {len(broken)} NOT idempotent; "
              f"{mixed} more use a replacement inside a longer body (not classified)")
        for row in broken:
            print(f"   ✗ {row['name']:28} {row['steps']} steps  witness {row['witness']!r:10} {row['file'].split('/xcode_projects/')[-1]}")
        for row in closed:
            print(f"   ✓ {row['name']:28} {row['steps']} steps  {row['file'].split('/xcode_projects/')[-1]}")
        report[label] = {"files": len(files), "chains": len(rows), "idempotent": len(closed),
                         "not_idempotent": len(broken), "mixed_not_classified": mixed}
    print("\n" + json.dumps(report))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
