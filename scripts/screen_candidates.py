#!/usr/bin/env python3
"""Screen candidate subjects against toolchain-exit-criteria.md §6.1, as amended 2026-08-24.

**What this answers.** Which unmet Swift packages are worth spending a `verify` run on, for
the `codable-round-trip` refutation-rate question (`open-threads.md` row 65).

**What it does NOT answer.** Whether a law will run there. §6.1's pre-check — point
`verify --all-from-index` at the subject and read rows-reaching-a-verdict — is the only thing
that answers that, and it costs one run per subject. This is the cheap filter placed in FRONT
of that run, so the run is spent on a subject that can pay.

**The clause it implements is the AMENDED one.** Counting `Codable` types and `Equatable`
types separately predicts a rich subject and is wrong: `lottie-ios` declares 32 and 48 and
emits ONE row, because the law lives on types in the INTERSECTION. The further clause is that
the `Codable` half must be HAND-WRITTEN — a synthesized round trip is symmetric by
construction and cannot refute.

Built on `measurement.py` rather than beside it: `declares_custom_codable` exists there
because a 40-line window answered this same question wrongly (instrument #6), and a
conformance written in a separate `+Codable.swift` extension is the case it was written for.

Denominators are printed beside every population, per that module's contract.
"""
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import measurement

# `Codable` is `Encodable & Decodable`; a Decodable-only type cannot round-trip.
CODABLE = {"Codable"}
CODABLE_HALVES = {"Encodable", "Decodable"}
# Hashable refines Equatable, so a Hashable type has `==` whether or not it says so.
EQUATABLE = {"Equatable", "Hashable"}

C_SUFFIXES = (".c", ".h", ".m", ".mm", ".cc", ".cpp", ".hpp")

# Type names declared as `enum` per corpus root, filled in by `conformance_index`.
# Module-level because the index is built once per root and read by `sum_types`.
KINDS: dict = {}

# `case foo(Bar)` — an enum case carrying associated values.
PAYLOAD_CASE = re.compile(r"^\s*(?:indirect\s+)?case\s+\w+\s*\(", re.MULTILINE)

DECL = re.compile(
    r"^\s*(?:public\s+|internal\s+|package\s+|open\s+|final\s+|private\s+|fileprivate\s+)*"
    r"(?:struct|enum|class|actor)\s+([A-Z_]\w*)\s*(<[^{]*?>)?\s*:\s*([^{]+)\{",
    re.MULTILINE)
EXT = re.compile(
    r"^\s*(?:public\s+|internal\s+|package\s+)?extension\s+([A-Z_][\w.]*)\s*:\s*([^{]+)\{",
    re.MULTILINE)


def _conformances(clause):
    """The protocol names in an inheritance clause, generic parameters stripped."""
    clause = re.sub(r"where\b.*", "", clause, flags=re.DOTALL)
    clause = re.sub(r"<[^>]*>", "", clause)
    return {part.strip().split(".")[-1] for part in clause.split(",") if part.strip()}


def conformance_index(base):
    """`{bare type name: set(protocol names)}`, unioned across declarations and extensions.

    ⚠ Keyed on the BARE name, so two same-named nested types in different namespaces merge.
    That is the `SymbolJoinKey` hazard, and it inflates rather than deflates — acceptable in a
    screen whose output is *which subject deserves a run*, and stated so it is not carried into
    a measurement.
    """
    index = {}
    for path in measurement.swift_files(base):
        try:
            text = open(path, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        for match in DECL.finditer(text):
            index.setdefault(match.group(1), set()).update(_conformances(match.group(3)))
            if match.group(0).lstrip().split()[0] in ("enum",) or " enum " in match.group(0):
                KINDS.setdefault(base, set()).add(match.group(1))
        for match in EXT.finditer(text):
            name = match.group(1).split(".")[-1]
            index.setdefault(name, set()).update(_conformances(match.group(2)))
    return index


def host_platform(base):
    """What the root manifest says about macOS — the clause that disqualified IceCubesApp.

    The verifier BUILDS AND RUNS its stub on the host, so a subject that cannot resolve for
    macOS reports `build-failed` on every row — which CLAUDE.md warns reads as an
    architectural limitation rather than a broken manifest. An app's local packages routinely
    declare `.iOS` only, and that is exactly where hand-written wire types are richest, so this
    is cheap to check and expensive to discover from a spent run.

    ⚠ **A declared floor is necessary, not sufficient** — a dependency can still out-require it,
    which is how `IceCubesApp/Packages/Models` failed (no macOS declared => defaults to 10.13,
    against SwiftSoup's 10.15). Only an actual `swift build` settles it.
    """
    manifest = os.path.join(base, "Package.swift")
    if not os.path.exists(manifest):
        return "no root manifest"
    text = open(manifest, encoding="utf-8", errors="ignore").read()
    match = re.search(r"\.macOS\(([^)]*)\)", text)
    if match:
        return match.group(1).strip()
    return "NOT DECLARED" if "platforms" in text else "no platforms block"


def sum_types(base, names):
    """Of `names`, those declared as an `enum` with at least one case carrying a payload.

    **Why this is the column worth having.** Swift synthesizes `Codable` for ordinary structs,
    so a library that merely models a wire format hand-writes almost nothing —
    `sourcekit-lsp` implements the whole Language Server Protocol and has FOUR hand-written
    `Codable` ∩ `Equatable` types. What forces a hand-written coder is a **sum type**: an enum
    with associated values cannot be synthesized into an external schema's shape, so the author
    must write `init(from:)` / `encode(to:)` by hand — and a hand-written coder is where the
    encoder and the decoder get the chance to disagree.

    Reported beside the hand-written count rather than instead of it: this is a HYPOTHESIS about
    which subjects will be rich, and the hand-written count is the thing it is trying to predict.
    """
    enums = KINDS.get(base, set())
    found = []
    for name in names:
        if name not in enums:
            continue
        if any(PAYLOAD_CASE.search(block) for block in measurement.declaration_blocks(base, name)):
            found.append(name)
    return found


def screen(base):
    files = list(measurement.swift_files(base))
    # Two file counts, because they answer different questions and the published tables use
    # the narrower one. `swift_files` walks the whole tree minus EXCLUDED_DIRS (84 for
    # jwt-kit); §1 of refutation-rate-third-fourth-subject.md counts `Sources/` (74). Both are
    # right; labelling one with the other's number is instrument error #2's exact shape.
    sources_root = os.path.join(base, "Sources")
    sources_files = (list(measurement.swift_files(sources_root))
                     if os.path.isdir(sources_root) else [])
    c_files = sum(1 for current, _, names in os.walk(base)
                  for name in names
                  if name.endswith(C_SUFFIXES)
                  and not any(os.sep + skip in current for skip in measurement.EXCLUDED_DIRS))

    index = conformance_index(base)
    codable = {n for n, c in index.items() if (c & CODABLE) or CODABLE_HALVES <= c}
    equatable = {n for n, c in index.items() if c & EQUATABLE}
    both = sorted(codable & equatable)
    handwritten = [n for n in both if measurement.declares_custom_codable(base, n)]
    sums = sum_types(base, both)

    return {
        "macos": host_platform(base),
        "swift_files": len(files),
        "sources_swift_files": len(sources_files),
        "c_files": c_files,
        "types_with_any_conformance": len(index),
        "codable": len(codable),
        "equatable": len(equatable),
        "intersection": len(both),
        "handwritten": len(handwritten),
        "handwritten_names": handwritten,
        "sum_types": len(sums),
        "sum_type_names": sums,
    }


def revision(base):
    try:
        out = subprocess.run(["git", "-C", base, "rev-parse", "--short", "HEAD"],
                             capture_output=True, text=True, timeout=30)
        return out.stdout.strip() or "?"
    except Exception:
        return "?"


def prior_mentions(name, docs="docs"):
    """How many lines across `docs/` name this subject — §6.1's spent-subject disqualifier."""
    try:
        out = subprocess.run(["grep", "-ril", name, docs],
                             capture_output=True, text=True, timeout=60)
        return len([line for line in out.stdout.splitlines() if line.strip()])
    except Exception:
        return -1


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    rows = []
    for base in argv:
        base = os.path.expanduser(base)
        if not os.path.isdir(base):
            print(f"skip (no such directory): {base}", file=sys.stderr)
            continue
        row = screen(base)
        row["subject"] = os.path.basename(base.rstrip("/"))
        row["path"] = base
        row["revision"] = revision(base)
        rows.append(row)
    print(json.dumps(rows, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
