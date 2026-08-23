#!/usr/bin/env python3
"""Shared primitives for ad-hoc measurement scripts, and a self-test that guards them.

## Why this exists

**Six measurement instruments returned a wrong number in one cycle (2026-08-17 → 2026-08-23),
all with the same shape: the cheap capture answered a different question from the one asked.**

| # | instrument | reported | true |
|---|---|---|---|
| 1 | `--target System` on swift-system | "36 unsupported-carrier" | 21 were a module bug |
| 2 | availability count over `localPath: "."` | 31,541 `deprecated` | **1,163** — the walk entered `.build` |
| 3 | availability join on `discover` default output | 4 rows | **24** — the question was the index |
| 4 | swift-system baseline via `swift test \\| tail -6` | 8 tests | **78** |
| 5 | `make test \\| tail -35` | exit code only | per-stage counts lost |
| 6 | custom-`Codable` detector, 40-line window | 7 of 14 | **14 of 14** |

`docs/design-internal/open-threads.md` has recorded this shape as a standing observation since
2026-08-05. It did not prevent numbers 1–6. That document's own verdict on why is the reason
this file is code rather than another paragraph:

> restating a rule in a second prose location does not approximate a guard — **it produces the
> feeling of having one**, which is worse than a single unenforced comment, since the reader now
> finds agreement wherever they check.

## What is guardable here, and what is not

**Guardable, and guarded below:** population scope (#2, #3) and under-detecting heuristics (#6).
Those live in code that can be shared and self-tested.

**NOT guardable from inside this repo:** #4 and #5 are `| tail -N` in an interactive shell.
Nothing in a Swift package can see them. What this module does instead is make the safe capture
*shorter to write* than the unsafe one — see `capture()`. A convenience is not a guard, and this
file does not pretend otherwise.
"""
import json
import os
import re
import subprocess
import sys

#: Directories a corpus walk must never enter.
#:
#: `.build` is #2 above: a corpus whose `localPath` is `"."` has every dependency's source
#: vendored underneath it, so a walk that enters it measures the dependencies of the subject
#: rather than the subject. `checkouts` is the same hazard one level down. `Tests` is excluded
#: because every census this project has run asks about shipped code.
EXCLUDED_DIRS = (".build", ".git", "checkouts", "Tests", ".swiftinfer")


def corpus_roots(manifest="fixtures/corpora/manifest.json"):
    """Resolved corpus roots, as `(id, root, source_dirs)`, plus the denominator.

    Returns `(rows, asked)` — never just `rows`. **A population reported without the count it
    was drawn from is how a census gets quoted as if it covered everything**, and three corpora
    silently resolving to nothing is a real state this project has hit.
    """
    manifest_data = json.load(open(manifest, encoding="utf-8"))
    corpora = manifest_data["corpora"]
    rows = []
    for corpus in corpora:
        local = corpus.get("localPath")
        if not local:
            continue
        root = os.path.abspath(os.path.expanduser(local))
        if not os.path.isdir(root):
            continue
        rows.append((corpus["id"], root, source_dirs(root, corpus)))
    return rows, len(corpora)


def source_dirs(root, corpus):
    """The directories a corpus's shipped code actually lives in."""
    found = []
    values = corpus.get("sources")
    for item in values if isinstance(values, list) else [values] if values else []:
        path = os.path.join(root, item)
        if os.path.isdir(path):
            found.append(path)
    # `Sources/<target>` is a CONVENTION, not a rule, and GRDB is the standing counter-example:
    # its own manifest says `path: "GRDB"`, so the sources sit at `<root>/GRDB` and
    # `<root>/Sources/GRDB` does not exist. This is the same trap
    # `VerifyTargetInference.manifestModule` was written for — read there for the full
    # reasoning — and reading the convention as a rule here silently zeroed 167 files.
    values = corpus.get("target")
    for item in values if isinstance(values, list) else [values] if values else []:
        for candidate in (os.path.join(root, "Sources", item), os.path.join(root, item)):
            if os.path.isdir(candidate):
                found.append(candidate)
                break
    if not found and os.path.isdir(os.path.join(root, "Sources")):
        found.append(os.path.join(root, "Sources"))
    return found


def swift_files(base):
    """Every `.swift` file under `base`, with `EXCLUDED_DIRS` applied by construction."""
    for current, _, names in os.walk(base):
        if any(os.sep + skip in current or current.endswith(os.sep + skip)
               for skip in EXCLUDED_DIRS):
            continue
        for name in names:
            if name.endswith(".swift"):
                yield os.path.join(current, name)


def declaration_blocks(base, name):
    """Every `struct/enum/class/extension <name> { … }` body under `base`, brace-matched.

    **Brace-matched across the whole tree rather than a fixed line window**, which is #6: a
    40-line window past the `struct` declaration cannot see a conformance written in a separate
    `+Codable.swift` extension, and Swift codebases put them there constantly. The self-test
    pins that exact case.
    """
    pattern = re.compile(r"\b(?:struct|enum|final class|class|extension)\s+"
                         + re.escape(name) + r"\b")
    for path in swift_files(base):
        try:
            text = open(path, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        for match in pattern.finditer(text):
            start = text.find("{", match.end())
            if start < 0:
                continue
            depth, index = 0, start
            while index < len(text):
                if text[index] == "{":
                    depth += 1
                elif text[index] == "}":
                    depth -= 1
                    if depth == 0:
                        break
                index += 1
            yield text[start:index + 1]


def declares_custom_codable(base, name):
    """Does `name` hand-write either half of `Codable` anywhere under `base`?"""
    for block in declaration_blocks(base, name):
        if re.search(r"func\s+encode\s*\(\s*to\s+encoder", block):
            return True
        if re.search(r"init\s*\(\s*from\s+decoder", block):
            return True
    return False


def capture(command, path, shell=True):
    """Run `command`, write its FULL output to `path`, return `(exit_code, path)`.

    The safe capture, made shorter than the unsafe one. `capture(cmd, log)` against
    `cmd | tail -6` is the whole of #4 and #5 — a run that proved an exit code and discarded
    every number it was taken for.

    **This is a convenience, not a guard.** Nothing stops a caller piping anyway.
    """
    with open(path, "w", encoding="utf-8") as handle:
        completed = subprocess.run(command, shell=shell, stdout=handle,
                                   stderr=subprocess.STDOUT, check=False)
    return completed.returncode, path


# --------------------------------------------------------------------------- self-test

def _fail(message):
    print(f"FAIL: {message}")
    return 1


def self_test():
    """Validate the primitives against cases that ACTUALLY broke, not invented ones.

    Every arm below is a regression test for a specific wrong number in the table at the top of
    this file. An arm that is not traceable to one does not belong here.
    """
    import tempfile
    failures = 0

    # --- #2: a walk must never enter .build / checkouts / Tests -------------------------
    with tempfile.TemporaryDirectory() as tmp:
        for rel in ("Sources/Keep.swift", ".build/Skip.swift", "Tests/Skip.swift",
                    "checkouts/dep/Skip.swift", ".swiftinfer/Skip.swift"):
            full = os.path.join(tmp, rel)
            os.makedirs(os.path.dirname(full), exist_ok=True)
            open(full, "w", encoding="utf-8").write("// x\n")
        found = sorted(os.path.basename(p) for p in swift_files(tmp))
        if found != ["Keep.swift"]:
            failures += _fail(f"exclusions leaked: expected ['Keep.swift'], got {found}")

    # --- #6: a conformance in a SEPARATE +Codable.swift extension must be found ---------
    #
    # `SemanticIndexEntry` is declared in SemanticIndexEntry.swift and writes its Codable
    # halves in SemanticIndexEntry+Codable.swift. The 40-line-window detector said False.
    if not declares_custom_codable("Sources", "SemanticIndexEntry"):
        failures += _fail("SemanticIndexEntry: custom Codable in a separate extension file "
                          "was NOT found — this is the exact miss of 2026-08-23")

    # A known NEGATIVE, so the arm above cannot be satisfied by always returning True.
    if declares_custom_codable("Sources", "ZZZNoSuchTypeExists"):
        failures += _fail("a type that does not exist reported custom Codable")

    # --- the denominator must travel with the population (#2's reporting half) ----------
    rows, asked = corpus_roots()
    if not isinstance(asked, int) or asked <= 0:
        failures += _fail("corpus_roots did not return the count it was asked for")
    if len(rows) > asked:
        failures += _fail(f"resolved {len(rows)} of {asked} — more than the manifest declares")
    # --- a resolved corpus must yield FILES, not merely a directory ----------------------
    #
    # Found by this arm on its first run, 2026-08-23: THREE corpora resolved to a directory
    # that contained no Swift at all, so every manifest-iterating census had been excluding
    # them while counting them in its denominator.
    #
    #   maccloud-client-ios  sources ["Shared"]              → no such dir      →  22 files
    #   grdb                 target "GRDB" → Sources/GRDB    → does not exist   → 167 files
    #   swiftlint-rule-studio sources ["SwiftLintRuleStudio"] → only Info.plist → 171 files
    #
    # GRDB is the same `path: "GRDB"` shape that `VerifyTargetInference.manifestModule`
    # exists for — a manifest relocating its target, read here by a convention that assumed
    # `Sources/<target>`. Asserting on the DIRECTORY would have passed all three.
    for corpus_id, _, dirs in rows:
        if not dirs:
            failures += _fail(f"{corpus_id}: resolved with NO source dir — a silent zero")
            continue
        count = sum(1 for directory in dirs for _ in swift_files(directory))
        if count == 0:
            failures += _fail(f"{corpus_id}: resolved to {dirs} containing ZERO .swift files "
                              "— counted in the denominator, contributing nothing")

    if failures:
        print(f"\n{failures} self-test failure(s)")
        return 1
    print(f"measurement.py self-test OK  ({len(rows)} of {asked} corpora resolve)")
    return 0


if __name__ == "__main__":
    sys.exit(self_test() if "--self-test" in sys.argv else
             print(__doc__.split("##")[0].strip()) or 0)
