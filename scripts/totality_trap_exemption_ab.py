#!/usr/bin/env python3
"""A/B: what does exempting `input-totality` from the impure-subject veto on a trap-only
witness move? See `docs/measurements/totality-trap-exemption.md`.

Runs two `swift-infer` binaries — built from the commit before the change and the commit with it
— over the same corpus directories on the same day, with the same flags, from the same empty
working directory, and diffs the printed suggestions by `(template, Identity)`.

**Every template other than `input-totality` is the control.** The change can only un-veto
`input-totality` rows, so any other template moving means the A/B measured something else (a
different flag, a stale binary, an evidence store read from the working directory).

Usage: totality_trap_exemption_ab.py BEFORE AFTER [EXTRA_DIR ...]
  EXTRA_DIRS are scanned beside the manifest corpora and reported separately.
"""
import collections
import concurrent.futures
import os
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from measurement import corpus_roots  # noqa: E402

TEMPLATE = re.compile(r"^Template:\s+(\S+)")
IDENTITY = re.compile(r"^Identity:\s+(0x[0-9A-F]+)")
SUBJECT = re.compile(r"^\s+✓ (\S+?\(.*?\)).*— (\S+):(\d+)$")


def relative(path, source_dir):
    """`path` under `source_dir`, compared without case: `discover` prints the path as the
    filesystem spells it, which on a case-insensitive volume need not match the manifest's."""
    root = os.path.normpath(source_dir) + os.sep
    return path[len(root):] if path.lower().startswith(root.lower()) else path


def rows(binary, source_dir, workdir):
    """`{(template, identity): subject}` for every suggestion `discover` prints."""
    result = subprocess.run(
        [binary, "discover", "--sources", source_dir, "--include-possible"],
        cwd=workdir, capture_output=True, text=True, timeout=3600,
    )
    found, template, subject = {}, None, None
    for line in result.stdout.splitlines():
        if line.startswith("[Suggestion]"):
            template, subject = None, None
        elif match := TEMPLATE.match(line):
            template = match.group(1)
        elif subject is None and (match := SUBJECT.match(line)):
            subject = f"{match.group(1)} — {relative(match.group(2), source_dir)}:{match.group(3)}"
        elif (match := IDENTITY.match(line)) and template:
            found[(template, match.group(1))] = subject
    return found, result.returncode


def revision(source_dir):
    """The checkout's HEAD plus a digest of its uncommitted state, or `None` outside git.

    Read before the first scan and after the second: **a tree that moves between the two scans is
    measured as the change.** Found the first time this ran (2026-11-21) — another session
    fast-forwarded swift-syntax, swiftlang-swift and swift-foundation three minutes in, and 606
    `predicate` rows "moved" on swift-syntax with the control flagged.
    """
    def git(*args):
        result = subprocess.run(["git", "-C", source_dir, *args], capture_output=True, text=True)
        return result.stdout if result.returncode == 0 else None
    head = git("rev-parse", "HEAD")
    return None if head is None else (head.strip(), hash(git("status", "--porcelain", "--", ".")))


def compare(label, source_dir, before, after, workdir):
    start = revision(source_dir)
    (old, old_status), (new, new_status) = rows(before, source_dir, workdir), rows(after, source_dir, workdir)
    return label, source_dir, old, new, (old_status, new_status), start != revision(source_dir)


def main(before, after, extra):
    manifest_rows, asked = corpus_roots()
    jobs = [(corpus_id, directory) for corpus_id, _, dirs in manifest_rows for directory in dirs]
    jobs += [(f"extra:{os.path.basename(os.path.normpath(d))}", os.path.abspath(d)) for d in extra]
    print(f"manifest corpora resolved: {len(manifest_rows)} of {asked}; directories scanned: {len(jobs)}")

    with tempfile.TemporaryDirectory() as workdir, concurrent.futures.ThreadPoolExecutor(4) as pool:
        results = list(pool.map(lambda job: compare(*job, before, after, workdir), jobs))

    totals = collections.Counter()
    for label, directory, old, new, statuses, moved in sorted(results):
        gained, lost = sorted(set(new) - set(old)), sorted(set(old) - set(new))
        by_template = collections.Counter(template for template, _ in gained + lost)
        totals["rows before"] += len(old)
        totals["rows after"] += len(new)
        for template, _ in gained:
            totals[f"+ {template}"] += 1
        for template, _ in lost:
            totals[f"- {template}"] += 1
        status = "" if statuses == (0, 0) else f"  ⚠ exit codes {statuses}"
        if moved:
            status += "  ⚠ TREE MOVED DURING THE A/B — this directory's diff is void"
            totals["directories void (tree moved)"] += 1
        print(f"\n[{label}] {os.path.basename(directory)}: {len(old)} → {len(new)} rows{status}")
        for key in gained:
            print(f"  + {key[0]:<16} {new[key]}")
        for key in lost:
            print(f"  - {key[0]:<16} {old[key]}")
        if set(by_template) - {"input-totality"} and not moved:
            print(f"  ⚠ CONTROL MOVED: {dict(by_template)}")

    print("\n== totals")
    for key, value in sorted(totals.items()):
        print(f"  {key:<28} {value}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2], sys.argv[3:])
