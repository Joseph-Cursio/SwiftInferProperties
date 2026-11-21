#!/usr/bin/env python3
"""#711's kill arm, run on the stub the tool EMITS: `docs/measurements/dedupe-count-laws.md`.

`scripts/dedupe_count_law_kill_arm.py` ran #671's hand-written C1/C2 against the three mutants. This
runs what `swift-infer` writes instead. It copies `fixtures/dedupe-count-law/kill-arm/` to a scratch
directory, drops the hand-written laws, accepts every suggestion through `discover --interactive`,
then runs `swift test` on the original and on each mutant. The emitted stub must fail each mutant
where the hand-written laws did.

    python3 scripts/dedupe_count_laws_kill_arm.py <swift-infer binary>

Needs network access the first time, to resolve the fixture's SwiftPropertyLaws dependency.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

ARM = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "fixtures", "dedupe-count-law", "kill-arm")
SUBJECT = "Sources/DedupeSubject/Dedupe.swift"
#: Each mutant replaces one anchored line, as `dedupe_count_law_kill_arm.py` does.
VARIANTS = {
    "original": None,
    "L162-delete-insert (identity)": ("                seen.insert(key) // L162", "                // L162 deleted"),
    "L161-negate-check ([])": ("            if !seen.contains(key) { // L161", "            if seen.contains(key) { // L161"),
    "L163-delete-append ([])": ("                result.append(relationship) // L163", "                // L163 deleted"),
}
RESULT = re.compile(r"Test (dedupe_\w+)\(\) (passed|failed|recorded an issue)")


def main(binary):
    with tempfile.TemporaryDirectory() as scratch:
        arm = os.path.join(scratch, "arm")
        shutil.copytree(ARM, arm, ignore=shutil.ignore_patterns(".build", ".swiftpm", "DedupeLawTests.swift"))
        open(os.path.join(arm, "Tests/DedupeLawTests/Placeholder.swift"), "w").write("import Testing\n")
        accepted = subprocess.run(
            [os.path.abspath(binary), "discover", "--sources", "Sources/DedupeSubject",
             "--include-possible", "--interactive"],
            cwd=arm, input="A\n" * 50, capture_output=True, text=True, check=True,
        )
        written = [line for line in accepted.stdout.splitlines() if line.startswith("Wrote ")]
        print("\n".join(written) or "⚠ nothing written")
        subject = os.path.join(arm, SUBJECT)
        original = open(subject).read()
        for name, edit in VARIANTS.items():
            source = original if edit is None else original.replace(*edit)
            if edit is not None and source == original:
                sys.exit(f"anchor not found for {name}")
            open(subject, "w").write(source)
            out = subprocess.run(["swift", "test"], cwd=arm, capture_output=True, text=True).stdout
            verdicts = {}
            for match in RESULT.finditer(out):
                law = match.group(1).split("_", 1)[1]
                verdicts[law] = "FAIL" if match.group(2) != "passed" else verdicts.get(law, "pass")
            cells = "  ".join(f"{law}={verdict}" for law, verdict in sorted(verdicts.items()))
            print(f"{name:<32} {cells or '⚠ no emitted test ran'}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
