#!/usr/bin/env python3
"""Census: functions shaped `(String|Substring) -> [T]`, the whole-to-parts partition candidate.

Scores the P2 gate from `docs/measurements/whole-to-parts-partition-prediction.md` — *the element
type separates a lossless tokenizer from a lossy splitter* — against hand classification.

Deliberately crude regex matching over declarations. It is a POPULATION estimate, not a parser:
the question is whether enough of this shape exists to justify a template, and a shape this
distinctive does not need syntax to count. Anything it misclassifies makes the population look
SMALLER, which is the safe direction for a build/decline decision.
"""
import re
import subprocess
import sys
from pathlib import Path

# `func name(label: String) -> [Element]`, capturing name, param type, element type.
DECL = re.compile(
    r"func\s+(\w+)\s*(?:<[^>]*>)?\s*\(([^)]*)\)\s*(?:async\s+)?(?:throws\s+)?->\s*\[([\w.<>]+)\]"
)
TEXT_PARAM = re.compile(r":\s*(String|Substring|SyntaxText)\b")
# Element types that are text themselves — the lossy-splitter tell (P2).
TEXT_ELEMENTS = {"String", "Substring", "Character", "SyntaxText", "UInt8"}


def scan(repo: Path):
    rows = []
    for path in repo.rglob("*.swift"):
        parts = path.parts
        if any(p in {".build", "Tests", "checkouts", ".git"} for p in parts):
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        for match in DECL.finditer(text):
            name, params, element = match.group(1), match.group(2), match.group(3)
            if not TEXT_PARAM.search(params):
                continue
            rows.append(
                {
                    "repo": repo.name,
                    "file": str(path.relative_to(repo)),
                    "name": name,
                    "element": element,
                    "params": " ".join(params.split()),
                    # The P2 gate: element is NOT itself a text type.
                    "gate_admits": element not in TEXT_ELEMENTS,
                }
            )
    return rows


def main(repos):
    everything = []
    for spec in repos:
        repo = Path(spec).expanduser()
        if repo.is_dir():
            everything.extend(scan(repo))

    admitted = [row for row in everything if row["gate_admits"]]
    print(f"total `(text) -> [T]` declarations : {len(everything)}")
    print(f"P2 gate admits (element not text)  : {len(admitted)}")
    print()

    by_repo = {}
    for row in admitted:
        by_repo.setdefault(row["repo"], []).append(row)
    print("admitted, by corpus — P-final checks concentration:")
    for name, rows in sorted(by_repo.items(), key=lambda kv: -len(kv[1])):
        print(f"  {name:<28} {len(rows)}")
    print()

    print("admitted rows, for hand classification:")
    for row in sorted(admitted, key=lambda r: (r["repo"], r["name"])):
        print(f"  [{row['repo']}] {row['name']}({row['params']}) -> [{row['element']}]")
        print(f"      {row['file']}")
    print()
    print("REJECTED by the gate (element is itself text) — the predicted lossy splitters:")
    for row in sorted(
        (r for r in everything if not r["gate_admits"]), key=lambda r: (r["repo"], r["name"])
    )[:25]:
        print(f"  [{row['repo']}] {row['name']} -> [{row['element']}]")


if __name__ == "__main__":
    main(sys.argv[1:])
