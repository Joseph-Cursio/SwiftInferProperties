#!/usr/bin/env python3
"""Find source files that nothing else in the package reaches.

Written after `StatefulRoleDiscoverer` / `RolePolicy` — a per-declaration policy
engine that compiled, passed its own tests, and had **zero production
conformances** for a month. Phase 1 had rejected it on granularity grounds and
nobody deleted it, so it sat reachable from nothing while its header still read
as a roadmap. Nothing reported it; it was found by hand, on the third pass of
someone asking "is anything left to do?".

## Why files, not declarations

The first version of this script reported *types*, and drowned. A type declared
beside the type that uses it — `StateSurface` next to `StatefulRole`, `Verdict`
next to `OrderedCarrierDiscriminator` — has no external reference and is not
remotely dead. 36 of its 88 findings were that one false positive.

Reachability is a property of the *cluster*, and in this codebase the cluster is
the file. `RolePolicy.swift` declared three types that referenced each other
happily; what made them dead is that **nothing outside the file named any of
them**. So: a file is reached if any name it declares appears in another file.

## The three verdicts

  live        some other file in Sources names something this file declares.
  test-only   only Tests names it. THIS is the RolePolicy shape, and the reason
              the script exists — a green test suite makes dead code look
              maintained.
  unreached   nothing outside the file names anything it declares.

## Two things that are load-bearing, not hygiene

**Comments are stripped before counting.** When `RolePolicy` was deleted, *every*
surviving mention of it in the package was a doc comment. So was every Sources
mention of `ParadigmDiscoverer`, `UnifiedRoleDiscoverer` and
`ViewModelInvariantStubEmitter` when this script first ran. A raw grep calls all
of them live. Naming a thing in prose is not depending on it.

**This does not fail a build.** Four targets are `.library` products, so public
API with no in-repo caller can be exactly right — that is what a library is.
Entry points reached only by the CLI's argument parser look unreached too. The
output is a list to read, not a verdict.

Usage:  python3 scripts/dead_public_api.py [--json]
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# **Top level only** — no leading whitespace. A NESTED type is unreferencable
# without its parent, and its bare name collides wildly: `Inputs` is declared
# inside 40-odd emitters, so matching it made every one of those files vouch for
# every other. That hid `ViewModelInvariantStubEmitter.swift`, whose only
# external mentions were doc comments, behind 43 unrelated `Inputs`. A false
# NEGATIVE, which is the direction that matters when the job is finding dead code.
DECL = re.compile(
    r"^(?:public|package|internal)?\s*(?:final\s+)?"
    r"(?:protocol|struct|enum|class|actor)\s+([A-Z][A-Za-z0-9_]*)"
)
EXTENSION = re.compile(r"^(?:public|package)?\s*extension\s+([A-Z][A-Za-z0-9_]*)")


def strip_comments(text: str) -> str:
    """Remove block and line comments.

    Load-bearing: every Sources mention of the four clusters this script first
    surfaced was a `///` doc comment.
    """
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.DOTALL)
    return "\n".join(re.sub(r"//.*$", "", line) for line in text.split("\n"))


def swift_files(root):
    return [p for p in sorted((ROOT / root).rglob("*.swift")) if ".build" not in p.parts]


def main() -> int:
    sources, tests = swift_files("Sources"), swift_files("Tests")
    stripped = {p: strip_comments(p.read_text(errors="ignore")) for p in sources + tests}

    declares: dict[Path, set[str]] = {}
    for path in sources:
        names, extends = set(), set()
        for line in stripped[path].split("\n"):
            if match := DECL.match(line):
                names.add(match.group(1))
            elif match := EXTENSION.match(line):
                extends.add(match.group(1))
        # An extension file is reached iff the type it extends is reached — so
        # the extended names count as this file's own. Conservative on purpose:
        # `VerifyCommand+Pipeline.swift` declares a private helper AND extends a
        # live command, and judging it on the helper alone called it dead. The
        # cost is that a dead *member* of a live type is invisible here; that
        # needs call-graph analysis, not a regex.
        declares[path] = names | extends

    findings = []
    for path, names in declares.items():
        if not names:
            continue
        pattern = re.compile(r"\b(?:" + "|".join(re.escape(n) for n in names) + r")\b")
        in_sources = [
            p.relative_to(ROOT).as_posix()
            for p in sources
            if p != path and pattern.search(stripped[p])
        ]
        in_tests = [p for p in tests if pattern.search(stripped[p])]
        if in_sources:
            continue
        findings.append({
            "file": path.relative_to(ROOT).as_posix(),
            "declares": sorted(names),
            "verdict": "test-only" if in_tests else "unreached",
            "testFiles": len(in_tests),
            "lines": len(stripped[path].split("\n")),
        })

    if "--json" in sys.argv:
        print(json.dumps(findings, indent=2))
        return 0

    print(f"{len(sources)} files in Sources/; {len(findings)} reached by no other Sources file\n")
    for verdict, blurb in [
        ("unreached", "nothing outside the file names anything it declares"),
        ("test-only", "only Tests reaches it — the RolePolicy shape"),
    ]:
        rows = [f for f in findings if f["verdict"] == verdict]
        total = sum(r["lines"] for r in rows)
        print(f"── {verdict}: {len(rows)} file(s), {total} lines  ({blurb})")
        for row in sorted(rows, key=lambda r: -r["lines"]):
            print(f"     {row['lines']:5}L  {row['file']}")
            print(f"            declares: {', '.join(row['declares'][:6])}")
        print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
