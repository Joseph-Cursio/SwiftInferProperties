#!/usr/bin/env python3
"""Where do #647's two laws fire? — `docs/measurements/input-order-independence.md` §3.

Runs `swift-infer discover --include-possible --no-docstring-advice` on every scan root of the
budgeted-truncation census's universe, and keeps the `sorted-output` and `input-order-independence`
rows: subject, signature, location, the body reading the template printed, and whether the row
carries the `private` caveat. Uses the binary this checkout built, so build first.

  run <out.json> [subject …]   census every subject, or only the ones named
"""
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import budgeted_truncation_census as population  # noqa: E402  (the subject universe)

TEMPLATES = ("sorted-output", "input-order-independence")
TIMEOUT = 600


def binary():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    for candidate in (".build/out/Products/Debug/swift-infer", ".build/debug/swift-infer"):
        path = os.path.join(root, candidate)
        if os.path.isfile(path):
            return path
    raise SystemExit("no swift-infer binary — run `swift build --product swift-infer` first")


def rows_in(output, subject):
    found = []
    for block in output.split("Template: ")[1:]:
        template = block.split("\n", 1)[0].strip()
        if template not in TEMPLATES:
            continue
        signature = re.search(r"✓ (.+?) — (/\S+:\d+)", block)
        reading = re.search(r"✓ the body sorts (.+?) \(\+40\)", block)
        found.append({
            "subject": subject,
            "template": template,
            "signature": signature.group(1) if signature else None,
            "location": signature.group(2) if signature else None,
            "reading": reading.group(1) if reading else None,
            "private": "NO TEST CAN RUN THIS LAW" in block,
        })
    return found


def run(out_path, only):
    tool = binary()
    found, missing = population.subjects()
    report = {"missing": [name for _, name in missing], "failures": [], "rows": []}
    for _, name, root, roots in found:
        if only and name not in only:
            continue
        for scan in roots:
            try:
                out = subprocess.run(
                    [tool, "discover", "--sources", scan, "--include-possible", "--no-docstring-advice"],
                    capture_output=True, text=True, timeout=TIMEOUT, cwd=root,
                )
            except subprocess.TimeoutExpired:
                report["failures"].append({"subject": name, "scan": scan, "reason": "timeout"})
                continue
            if out.returncode != 0:
                report["failures"].append({"subject": name, "scan": scan, "reason": out.stderr.strip()[-300:]})
                continue
            report["rows"].extend(rows_in(out.stdout, name))
        print(name, sum(row["subject"] == name for row in report["rows"]), flush=True)
    for template in TEMPLATES:
        print(template, sum(row["template"] == template for row in report["rows"]))
    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=1)


def main(argv):
    if len(argv) >= 2 and argv[0] == "run":
        run(argv[1], set(argv[2:]))
    else:
        print(__doc__)
        raise SystemExit(2)


if __name__ == "__main__":
    main(sys.argv[1:])
