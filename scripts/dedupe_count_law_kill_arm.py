#!/usr/bin/env python3
"""#671's kill arm — `docs/plans/dedupe-count-law-census-scope.md` §1.

Applies each of the three dedupe mutants from F3 of `docs/measurements/roadtest-swiftumlstudio-mutation.md` (delete
L162's insert, negate L161's check, delete L163's append) to `fixtures/dedupe-count-law/kill-arm/`, runs
`swift test`, and records which law noticed which mutant. The source is restored after every variant, also on
failure.

    python3 scripts/dedupe_count_law_kill_arm.py fixtures/dedupe-count-law/kill-arm-<date>.json
"""
import datetime
import hashlib
import json
import os
import re
import subprocess
import sys

ARM = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "fixtures", "dedupe-count-law", "kill-arm")
SUBJECT = "Sources/DedupeSubject/Dedupe.swift"
LAWS = "Tests/DedupeLawTests/DedupeLawTests.swift"
ANCHORS = {
    "L161": "            if !seen.contains(key) { // L161",
    "L162": "                seen.insert(key) // L162",
    "L163": "                result.append(relationship) // L163",
}
#: Each mutant replaces one anchored line; `original` replaces nothing.
VARIANTS = {
    "original": None,
    "L162-delete-insert": ("L162", "                // L162 deleted"),
    "L161-negate-check": ("L161", "            if seen.contains(key) { // L161"),
    "L163-delete-append": ("L163", "                // L163 deleted"),
}
#: What each mutant becomes (§1.4), for the record.
BECOMES = {"L162-delete-insert": "identity", "L161-negate-check": "[]", "L163-delete-append": "[]"}
TESTS = ["c1", "c2", "idempotence", "sanity"]
LAW_TESTS = ["c1", "c2", "idempotence"]
RESULT = re.compile(r"^[✔✘] Test (\w+)\(\) (passed|failed|recorded)")


def run_variant(name, edit):
    full = os.path.join(ARM, SUBJECT)
    with open(full, encoding="utf-8") as handle:
        text = handle.read()
    for anchor, line in ANCHORS.items():
        if text.count(line) != 1:
            sys.exit(f"{SUBJECT}: anchor {anchor} is not there exactly once")
    try:
        if edit:
            anchor, line = edit
            with open(full, "w", encoding="utf-8") as handle:
                handle.write(text.replace(ANCHORS[anchor], line))
        output = subprocess.run(["swift", "test"], cwd=ARM, capture_output=True, text=True).stdout
    finally:
        with open(full, "w", encoding="utf-8") as handle:
            handle.write(text)
    outcomes = {}
    for raw in output.splitlines():
        match = RESULT.match(raw)
        if match:
            # A test that recorded an issue prints `✘ Test x() recorded an issue` and later `✘ Test x() failed`.
            outcomes[match.group(1)] = "FAIL" if raw.startswith("✘") else outcomes.get(match.group(1), "PASS")
    if set(outcomes) != set(TESTS):
        sys.exit(f"{name}: the run reported {sorted(outcomes)}, not the four tests\n{output[-3000:]}")
    return outcomes


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    swift = subprocess.run(["swift", "--version"], capture_output=True, text=True).stdout.strip().splitlines()[0]
    with open(os.path.join(ARM, LAWS), "rb") as handle:
        law_sha = hashlib.sha256(handle.read()).hexdigest()
    resolved = json.load(open(os.path.join(ARM, "Package.resolved")))
    pins = {pin["identity"]: pin["state"].get("version") or pin["state"].get("revision") for pin in resolved["pins"]}
    matrix = {name: run_variant(name, edit) for name, edit in VARIANTS.items()}
    controls_passed = all(outcome == "PASS" for outcome in matrix["original"].values())
    killed_by = {law: [m for m in BECOMES if matrix[m][law] == "FAIL"] for law in LAW_TESTS}
    record = {
        "date": datetime.date.today().isoformat(),
        "swift": swift,
        "pins": pins,
        "laws_sha256": law_sha,
        "variants": {name: edit and {"anchor": edit[0], "line": edit[1]} for name, edit in VARIANTS.items()},
        "becomes": BECOMES,
        "controls_passed": controls_passed,
        "matrix": matrix,
        "killed_by": killed_by,
    }
    with open(sys.argv[1], "w", encoding="utf-8") as handle:
        json.dump(record, handle, indent=2, sort_keys=True)
        handle.write("\n")
    for law, killed in killed_by.items():
        print(f"{law:12} kills {', '.join(killed) or 'nothing'}")
    for name in BECOMES:
        print(f"{name:20} sanity {matrix[name]['sanity']}")
    print("controls passed" if controls_passed else "CONTROLS FAILED: the arm is void")
    return 0 if controls_passed else 1


if __name__ == "__main__":
    sys.exit(main())
