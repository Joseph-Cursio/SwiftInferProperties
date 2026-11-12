#!/usr/bin/env python3
"""#672's kill arm — `docs/plans/sanitizer-alphabet-census-scope.md` §1.

Applies each of the five mutants swift-mutation-testing `3be0c11` generates in `ERScript.sanitizeType` (#672) to
`fixtures/sanitizer-alphabet/kill-arm/`, runs `swift test`, and records which law noticed which mutant. The
source is restored after every variant, also on failure.

    python3 scripts/sanitizer_alphabet_kill_arm.py fixtures/sanitizer-alphabet/kill-arm-<date>.json
"""
import datetime
import hashlib
import json
import os
import re
import subprocess
import sys

ARM = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "fixtures", "sanitizer-alphabet", "kill-arm")
SUBJECT = "Sources/SanitizerSubject/SanitizeType.swift"
LAWS = "Tests/SanitizerLawTests/SanitizerLawTests.swift"
ANCHORS = {
    "L172": '            if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" { // L172',
    "L173": "                sanitized.unicodeScalars.append(scalar) // L173",
    "L178": '        return sanitized.isEmpty ? "Unknown" : sanitized // L178',
}
#: Each mutant replaces one anchored line; `original` replaces nothing (§1.3).
VARIANTS = {
    "original": None,
    "L172-NegateConditional": ("L172", '            if !(CharacterSet.alphanumerics.contains(scalar) || scalar == "_") { // L172'),
    "L172-or-to-and": ("L172", '            if CharacterSet.alphanumerics.contains(scalar) && scalar == "_" { // L172'),
    "L172-eq-to-neq": ("L172", '            if CharacterSet.alphanumerics.contains(scalar) || scalar != "_" { // L172'),
    "L173-RemoveSideEffects": ("L173", "                // L173 deleted"),
    "L178-SwapTernary": ("L178", '        return sanitized.isEmpty ? sanitized : "Unknown" // L178'),
}
MUTANTS = [name for name in VARIANTS if name != "original"]
TESTS = ["idempotence", "law1", "law2", "emptyDraws"]
LAW_TESTS = ["idempotence", "law1", "law2"]
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
    empty = re.search(r"EMPTY-DRAWS (\d+)", output)
    outcomes["emptyDrawsCount"] = int(empty.group(1)) if empty else None
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
    controls_passed = all(matrix["original"][test] == "PASS" for test in TESTS)
    killed_by = {law: [m for m in MUTANTS if matrix[m][law] == "FAIL"] for law in LAW_TESTS}
    record = {
        "date": datetime.date.today().isoformat(),
        "swift": swift,
        "pins": pins,
        "laws_sha256": law_sha,
        "variants": {name: edit and {"anchor": edit[0], "line": edit[1]} for name, edit in VARIANTS.items()},
        "note": "emptyDrawsCount is the empty strings among 100 draws of the idempotence generator under a Xoshiro on the seed state; the backend may sequence its draws differently, so it is indicative only",
        "controls_passed": controls_passed,
        "matrix": matrix,
        "killed_by": killed_by,
    }
    with open(sys.argv[1], "w", encoding="utf-8") as handle:
        json.dump(record, handle, indent=2, sort_keys=True)
        handle.write("\n")
    for law, killed in killed_by.items():
        print(f"{law:12} kills {', '.join(killed) or 'nothing'}")
    print(f"empty draws on the original's seed (indicative): {matrix['original']['emptyDrawsCount']}")
    together = [m for m in MUTANTS if matrix[m]["law1"] == "FAIL" or matrix[m]["law2"] == "FAIL"]
    print(f"law 1 + law 2 together kill {len(together)} of {len(MUTANTS)}")
    print("controls passed" if controls_passed else "CONTROLS FAILED: the arm is void")
    return 0 if controls_passed else 1


if __name__ == "__main__":
    sys.exit(main())
