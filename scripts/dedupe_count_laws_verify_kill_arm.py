#!/usr/bin/env python3
"""#711's kill arm, run through `swift-infer verify`: `docs/measurements/dedupe-count-laws.md`.

The accept-side arm (`dedupe_count_laws_kill_arm.py`) runs the stub `discover --interactive` writes.
This runs what `verify` builds instead. For the original and each mutant it reports:
- idempotence's verdict;
- each companion law's result (C1 and C2, run once after both idempotence passes);
- what the evidence store recorded;
- what `accept-check` says about the row accepted on the original. Accepting also records the row's
  route, so `accept-check` re-checks the accepted count laws after an edit the body gate refuses.
  A plain `verify` on that edit runs no companions: the code no longer reads as a dedupe.

C2 should fail the identity mutant and C1 both `[]` mutants, while idempotence's verdict stays a
pass. A companion failure must never become `measured-defaultFails`.

It copies `fixtures/dedupe-count-law/kill-arm/` to a scratch directory, adds the library product
`verify` links against (the fixture declares only a target), and then runs `index` and, per
variant, `verify --suggestion`.

    python3 scripts/dedupe_count_laws_verify_kill_arm.py <swift-infer binary>
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

ARM = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "fixtures", "dedupe-count-law", "kill-arm")
SUBJECT = "Sources/DedupeSubject/Dedupe.swift"
VARIANTS = {
    "original": None,
    "L162-delete-insert (identity)": ("                seen.insert(key) // L162", "                // L162 deleted"),
    "L161-negate-check ([])": ("            if !seen.contains(key) { // L161", "            if seen.contains(key) { // L161"),
    "L163-delete-append ([])": ("                result.append(relationship) // L163", "                // L163 deleted"),
}
COMPANION = re.compile(r"companion law: (C\d) (held|FAILED|TRAPPED)")


def run(binary, arm, *args):
    return subprocess.run([binary, *args], cwd=arm, capture_output=True, text=True)


def main(binary):
    binary = os.path.abspath(binary)
    with tempfile.TemporaryDirectory() as scratch:
        arm = os.path.join(scratch, "arm")
        shutil.copytree(ARM, arm, ignore=shutil.ignore_patterns(".build", ".swiftpm", "Tests"))
        os.makedirs(os.path.join(arm, "Tests/DedupeLawTests"))
        open(os.path.join(arm, "Tests/DedupeLawTests/Placeholder.swift"), "w").write("import Testing\n")
        manifest = os.path.join(arm, "Package.swift")
        source = open(manifest).read().replace(
            "    platforms: [.macOS(.v14)],",
            '    platforms: [.macOS(.v14)],\n    products: [.library(name: "DedupeSubject", targets: ["DedupeSubject"])],', 1)
        open(manifest, "w").write(source)
        run(binary, arm, "index", "--target", "DedupeSubject", "--include-possible")
        entries = json.load(open(os.path.join(arm, ".swiftinfer/index.json")))
        entries = entries["entries"] if isinstance(entries, dict) else entries
        row = next(e for e in entries if e["templateName"] == "idempotence")
        print(f"index row: {row['primaryFunctionName']} route={row.get('dedupeBody')}")
        accepted = subprocess.run([binary, "discover", "--sources", "Sources/DedupeSubject", "--include-possible",
                                   "--interactive"], cwd=arm, input="A\n" * 50, capture_output=True, text=True)
        decisions = json.load(open(os.path.join(arm, ".swiftinfer/decisions.json")))["records"]
        print(f"accepted: {[(d['template'], d.get('dedupeBody')) for d in decisions]} (exit {accepted.returncode})")
        subject = os.path.join(arm, SUBJECT)
        original = open(subject).read()
        for name, edit in VARIANTS.items():
            text = original if edit is None else original.replace(*edit)
            if edit is not None and text == original:
                sys.exit(f"anchor not found for {name}")
            open(subject, "w").write(text)
            out = run(binary, arm, "verify", "--suggestion", row["identityHash"][:10], "--target", "DedupeSubject")
            rendered = out.stdout + out.stderr
            verdict = next((line.strip() for line in rendered.splitlines() if line.startswith(("✓", "✗", "⚠", "?"))),
                           rendered.strip().splitlines()[-1] if rendered.strip() else "(no output)")
            laws = "  ".join(f"{law}={status}" for law, status in COMPANION.findall(rendered))
            store = json.load(open(os.path.join(arm, ".swiftinfer/verify-evidence.json")))
            records = store.get("records", store) if isinstance(store, dict) else store
            record = next(r for r in records if row["identityHash"].lstrip("0x").upper().endswith(r["identityHash"]))
            print(f"{name:<32} {verdict[:70]}")
            print(f"{'':<32} {laws}")
            print(f"{'':<32} evidence: outcome={record['outcome']} companions="
                  f"{[(c['law'], c['status']) for c in record.get('companionLaws') or []]}")
            check = run(binary, arm, "accept-check")
            lines = [line.strip() for line in (check.stdout + check.stderr).splitlines() if row["identityHash"][2:10].upper() in line.upper() or "nowFails" in line or "stillPasses" in line]
            print(f"{'':<32} accept-check: {lines[:2] if lines else (check.stdout + check.stderr).strip()[-200:]}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
