#!/usr/bin/env python3
"""#670's kill arm — `docs/plans/count-threshold-boundary-census-scope.md` §1.

Applies each of the three `:200` mutants swift-mutation-testing made in `compactText` (negate the condition,
`>` → `<`, `>` → `>=`) to both revisions in `fixtures/count-threshold/kill-arm/`, runs `swift test`, and records
which law noticed which mutant. The sources are restored after every variant, also on failure.

    python3 scripts/count_threshold_kill_arm.py fixtures/count-threshold/kill-arm-<date>.json
"""
import datetime
import hashlib
import json
import os
import re
import subprocess
import sys

ARM = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "fixtures", "count-threshold", "kill-arm")
SUBJECTS = ["Sources/CompactTextSubject/CompactTextE36da59.swift", "Sources/CompactTextSubject/CompactText9ad7631.swift"]
LAWS = "Tests/CompactTextLawTests/CompactTextLawTests.swift"
ORIGINAL = "if collapsed.count > 80 { // THRESHOLD"
VARIANTS = {
    "original": ORIGINAL,
    "negate": "if !(collapsed.count > 80) { // THRESHOLD",
    "lt": "if collapsed.count < 80 { // THRESHOLD",
    "gte": "if collapsed.count >= 80 { // THRESHOLD",
}
TESTS = ["law1", "law2", "idempotence"]
REVISIONS = ["e36da59", "9ad7631"]
RESULT = re.compile(r"^[✔✘] Test (\w+)\(\) (passed|failed|recorded)")


def run_variant(name, line):
    texts = {}
    for path in SUBJECTS:
        full = os.path.join(ARM, path)
        with open(full, encoding="utf-8") as handle:
            texts[full] = handle.read()
        if texts[full].count(ORIGINAL) != 1:
            sys.exit(f"{path}: the threshold line is not there exactly once")
    try:
        for full, text in texts.items():
            with open(full, "w", encoding="utf-8") as handle:
                handle.write(text.replace(ORIGINAL, line))
        output = subprocess.run(["swift", "test"], cwd=ARM, capture_output=True, text=True).stdout
    finally:
        for full, text in texts.items():
            with open(full, "w", encoding="utf-8") as handle:
                handle.write(text)
    outcomes = {}
    for raw in output.splitlines():
        match = RESULT.match(raw)
        if match:
            # A test that recorded an issue prints `✘ Test x() recorded an issue` and later `✘ Test x() failed`.
            outcomes[match.group(1)] = "FAIL" if raw.startswith("✘") else outcomes.get(match.group(1), "PASS")
    expected = {f"{law}_{revision}" for law in TESTS for revision in REVISIONS}
    if set(outcomes) != expected:
        sys.exit(f"{name}: the run reported {sorted(outcomes)}, not the six tests\n{output[-3000:]}")
    return outcomes


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    swift = subprocess.run(["swift", "--version"], capture_output=True, text=True).stdout.strip().splitlines()[0]
    with open(os.path.join(ARM, LAWS), "rb") as handle:
        law_sha = hashlib.sha256(handle.read()).hexdigest()
    resolved = json.load(open(os.path.join(ARM, "Package.resolved")))
    kit = {pin["identity"]: pin["state"].get("version") or pin["state"].get("revision") for pin in resolved["pins"]}
    matrix = {name: run_variant(name, line) for name, line in VARIANTS.items()}
    controls_passed = all(outcome == "PASS" for outcome in matrix["original"].values())
    summary = {}
    for revision in REVISIONS:
        for law in TESTS:
            killed = [m for m in ("negate", "lt", "gte") if matrix[m][f"{law}_{revision}"] == "FAIL"]
            summary[f"{law}_{revision}"] = killed
    record = {
        "date": datetime.date.today().isoformat(),
        "swift": swift,
        "pins": kit,
        "laws_sha256": law_sha,
        "variants": VARIANTS,
        "controls_passed": controls_passed,
        "matrix": matrix,
        "killed_by": summary,
    }
    with open(sys.argv[1], "w", encoding="utf-8") as handle:
        json.dump(record, handle, indent=2, sort_keys=True)
        handle.write("\n")
    for key, killed in summary.items():
        print(f"{key:22} kills {', '.join(killed) or 'nothing'}")
    print("controls passed" if controls_passed else "CONTROLS FAILED: the arm is void")
    return 0 if controls_passed else 1


if __name__ == "__main__":
    sys.exit(main())
