#!/usr/bin/env python3
"""#673's kill arm — `docs/plans/emitter-presence-census-scope.md` §1.

Applies each of the nine `RemoveSideEffects` mutants swift-mutation-testing `3be0c11` recorded in SwiftUMLBridge's
`ComponentScript.buildPlantUMLText` / `buildMermaidText` at `e36da59`
(`fixtures/mutation-check/roadtest-swiftumlstudio-2026-10-10.jsonl`) to `fixtures/emitter-presence/kill-arm/`, runs
`swift test`, and records which law, under which generator, noticed which mutant. The source is restored after
every variant, also on failure.

    python3 scripts/emitter_presence_kill_arm.py fixtures/emitter-presence/kill-arm-<date>.json
"""
import datetime
import hashlib
import json
import os
import re
import subprocess
import sys

ARM = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "fixtures", "emitter-presence", "kill-arm")
SUBJECT = "Sources/EmitterSubject/ComponentScript.swift"
LAWS = "Tests/EmitterLawTests/EmitterLawTests.swift"
#: The anchored lines (§1.1), read from the subject so the anchor text is exactly the copied line.
ANCHOR_LINES = ["L48", "L50", "L52", "L55", "L57", "L80", "L82", "L84", "L87"]
ELEMENT = ["L48", "L50", "L55", "L80", "L82", "L87"]
FRAME = ["L52", "L57", "L84"]
TESTS = ["determinismNaive", "determinismDisciplined", "bareNaive", "bareDisciplined",
         "templateNaive", "templateDisciplined", "reach"]
LAW_TESTS = TESTS[:-1]
RESULT = re.compile(r"^[✔✘] Test (\w+)\(\) (passed|failed|recorded)")


def anchors(text):
    """Each anchor's full line in the subject, asserted to occur exactly once."""
    found = {}
    for anchor in ANCHOR_LINES:
        lines = [line for line in text.splitlines() if line.endswith(f"// {anchor}")]
        if len(lines) != 1 or text.count(lines[0]) != 1:
            sys.exit(f"{SUBJECT}: anchor {anchor} is not there exactly once")
        found[anchor] = lines[0]
    return found


def run_variant(name, anchor):
    full = os.path.join(ARM, SUBJECT)
    with open(full, encoding="utf-8") as handle:
        text = handle.read()
    lines = anchors(text)
    try:
        if anchor:
            indent = lines[anchor][: len(lines[anchor]) - len(lines[anchor].lstrip())]
            with open(full, "w", encoding="utf-8") as handle:
                handle.write(text.replace(lines[anchor], f"{indent}// {anchor} deleted"))
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
        sys.exit(f"{name}: the run reported {sorted(outcomes)}, not the seven tests\n{output[-3000:]}")
    outcomes["reachLines"] = re.findall(r"REACH .*", output)
    return outcomes, anchor and lines[anchor].strip()


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    swift = subprocess.run(["swift", "--version"], capture_output=True, text=True).stdout.strip().splitlines()[0]
    with open(os.path.join(ARM, LAWS), "rb") as handle:
        law_sha = hashlib.sha256(handle.read()).hexdigest()
    resolved = json.load(open(os.path.join(ARM, "Package.resolved")))
    pins = {pin["identity"]: pin["state"].get("version") or pin["state"].get("revision") for pin in resolved["pins"]}
    variants = {"original": None, **{f"{a}-RemoveSideEffects": a for a in ANCHOR_LINES}}
    matrix, deleted = {}, {}
    for name, anchor in variants.items():
        matrix[name], deleted[name] = run_variant(name, anchor)
    mutants = [name for name in variants if name != "original"]
    controls_passed = all(matrix["original"][test] == "PASS" for test in TESTS)
    killed_by = {law: [m for m in mutants if matrix[m][law] == "FAIL"] for law in LAW_TESTS}
    record = {
        "date": datetime.date.today().isoformat(),
        "swift": swift,
        "pins": pins,
        "laws_sha256": law_sha,
        "subject": "SwiftUMLStudio e36da59, ComponentScript.swift lines 41-100 (builders, stereotypeText, safeAlias)",
        "element_lines": ELEMENT,
        "frame_lines": FRAME,
        "deleted_line": deleted,
        "note": "reach lines count, among 100 draws under a Xoshiro on the seed state, the draws that fill each loop; the backend may sequence its draws differently, so they are indicative only",
        "controls_passed": controls_passed,
        "matrix": matrix,
        "killed_by": killed_by,
    }
    with open(sys.argv[1], "w", encoding="utf-8") as handle:
        json.dump(record, handle, indent=2, sort_keys=True)
        handle.write("\n")
    for law, killed in killed_by.items():
        element = [m for m in killed if m.split("-")[0] in ELEMENT]
        frame = [m for m in killed if m.split("-")[0] in FRAME]
        print(f"{law:24} element {len(element)}/{len(ELEMENT)} {[m.split('-')[0] for m in element]}  "
              f"frame {len(frame)}/{len(FRAME)}")
    for line in matrix["original"]["reachLines"]:
        print(line)
    print("controls passed" if controls_passed else "CONTROLS FAILED: the arm is void")
    return 0 if controls_passed else 1


if __name__ == "__main__":
    sys.exit(main())
