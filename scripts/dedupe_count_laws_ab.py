#!/usr/bin/env python3
"""A/B: what does carrying #671's count laws on gated dedupe rows move? See
`docs/measurements/dedupe-count-laws.md` (SwiftInferProperties#711).

Runs two `swift-infer` binaries — built from the commit before the change and the commit with it —
over the manifest corpora (plus any extra directories) on the same day, with the same flags, from
the same empty working directory. Diffs the printed suggestions by `(template, Identity)` and reads
each row's score line and whether it carries the dedupe route line.

**The change may move no row and no score.** It adds a `TemplateMatch`, one "why suggested" line
and one caveat to idempotence rows whose body passes the gate, and nothing else. So every row is
the control: a row gained or lost, or a score changed, means the A/B measured something else. The
expected movement is the route line appearing, on idempotence rows only.

Usage: dedupe_count_laws_ab.py BEFORE AFTER [EXTRA_DIR ...]
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
SCORE = re.compile(r"^Score:\s+(.+)$")
IDENTITY = re.compile(r"^Identity:\s+(0x[0-9A-F]+)")
SUBJECT = re.compile(r"^\s+✓ (\S+?\(.*?\)).*— (\S+):(\d+)$")
ROUTE_LINE = "The body keeps one element per key"


def relative(path, source_dir):
    """`path` under `source_dir`, compared without case (a case-insensitive volume)."""
    root = os.path.normpath(source_dir) + os.sep
    return path[len(root):] if path.lower().startswith(root.lower()) else path


def rows(binary, source_dir, workdir):
    """`{(template, identity): (subject, score, carries route line)}` for every printed row."""
    result = subprocess.run(
        [binary, "discover", "--sources", source_dir, "--include-possible"],
        cwd=workdir, capture_output=True, text=True, timeout=3600,
    )
    found, template, subject, score, routed = {}, None, None, None, False
    for line in result.stdout.splitlines():
        if line.startswith("[Suggestion]"):
            template, subject, score, routed = None, None, None, False
        elif match := TEMPLATE.match(line):
            template = match.group(1)
        elif match := SCORE.match(line):
            score = match.group(1).strip()
        elif subject is None and (match := SUBJECT.match(line)):
            subject = f"{match.group(1)} — {relative(match.group(2), source_dir)}:{match.group(3)}"
        elif ROUTE_LINE in line:
            routed = True
        elif (match := IDENTITY.match(line)) and template:
            found[(template, match.group(1))] = (subject, score, routed)
    return found, result.returncode


def revision(source_dir):
    """HEAD plus a digest of the uncommitted state, read before the first scan and after the
    second: a tree that moves between them is measured as the change
    (`docs/measurements/totality-trap-exemption.md` §3.1)."""
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
    jobs = [(corpus_id, d) for corpus_id, _, dirs in manifest_rows for d in dict.fromkeys(dirs)]
    jobs += [(f"extra:{os.path.basename(os.path.normpath(d))}", os.path.abspath(d)) for d in extra]
    print(f"manifest corpora resolved: {len(manifest_rows)} of {asked}; directories scanned: {len(jobs)}")

    with tempfile.TemporaryDirectory() as workdir, concurrent.futures.ThreadPoolExecutor(4) as pool:
        results = list(pool.map(lambda job: compare(*job, before, after, workdir), jobs))

    totals = collections.Counter()
    for label, directory, old, new, statuses, moved in sorted(results):
        if moved:
            print(f"\n[{label}] ⚠ TREE MOVED DURING THE A/B — void")
            totals["directories void (tree moved)"] += 1
            continue
        totals["rows before"] += len(old)
        totals["rows after"] += len(new)
        gained, lost = sorted(set(new) - set(old)), sorted(set(old) - set(new))
        rescored = sorted(k for k in set(old) & set(new) if old[k][1] != new[k][1])
        routed = sorted(k for k in new if new[k][2])
        totals["rows gained (control)"] += len(gained)
        totals["rows lost (control)"] += len(lost)
        totals["rows rescored (control)"] += len(rescored)
        totals["rows carrying the route line before"] += sum(1 for k in old if old[k][2])
        for template, _ in routed:
            totals[f"route line after: {template}"] += 1
        if not (gained or lost or rescored or routed) and statuses == (0, 0):
            continue
        status = "" if statuses == (0, 0) else f"  ⚠ exit codes {statuses}"
        print(f"\n[{label}] {os.path.basename(directory)}: {len(old)} → {len(new)} rows{status}")
        for key in routed:
            print(f"  ✓ route  {key[0]:<14} {new[key][0]}  [{new[key][1]}]")
        for key in gained:
            print(f"  ⚠ +      {key[0]:<14} {new[key][0]}")
        for key in lost:
            print(f"  ⚠ -      {key[0]:<14} {old[key][0]}")
        for key in rescored:
            print(f"  ⚠ score  {key[0]:<14} {old[key][0]}: {old[key][1]} → {new[key][1]}")

    print("\n== totals")
    for key, value in sorted(totals.items()):
        print(f"  {key:<40} {value}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2], sys.argv[3:])
