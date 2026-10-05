#!/usr/bin/env python3
r"""The per-item before/after table of the reference-oracle scaffold census.

Usage:

  scripts/reference_oracle_scaffold_rows.py --out DIR --before LABEL --after LABEL SUBJECT... \
      > fixtures/reference-oracle-scaffold-census/items-<date>.tsv
  scripts/reference_oracle_scaffold_rows.py --self-test

  DIR      the census work directory (`scripts/reference_oracle_scaffold_census.py --out`)
  LABEL    two runs in it, `runs/<label>-<SUBJECT>/results.json`, on the same seed manifest
  SUBJECT  each subject's directory name (`SwiftAssist`, `swift-format`)

One row per scaffold the BEFORE run printed, per run mode (seeded / unseeded), joined to what the
AFTER run printed or declined for the same function, matched by subject-relative file, line and
display name. Tab-separated, with a header line. Columns:

  subject, run, function   the subject, the run mode, and discover's display name
  location                 `<file>:<line>`, relative to the subject worktree
  shape, access            the declaration facts the BEFORE run read (static-member, instance-method,
                           free-function; private, fileprivate, internal, …)
  before                   `compiles`, or `fails:<primary cause>`
  before_causes            every cause the compiler reported before, comma-separated
  after                    `compiles`, `fails:<primary cause>`, `declined:<category>`, or `MISSING`
                           (neither printed nor declined after: the census's printed + declined
                           check would fail)
  after_detail             the decline reason; for a printed scaffold that fails, EVERY compiler
                           error as `line N: message`, `; `-separated; empty when it compiles

The counts per (subject, run, after) go to stderr, with the number of MISSING rows.
"""
import argparse
import collections
import json
import os
import sys
import tempfile

HEADER = ["subject", "run", "function", "location", "shape", "access", "before", "before_causes",
          "after", "after_detail"]


def relative(path, tree):
    """`path` relative to the subject worktree it was printed from, or as given if outside it."""
    if not path:
        return ""
    real = os.path.realpath(path)
    return os.path.relpath(real, tree) if real.startswith(tree + os.sep) else path


def outcome(entry):
    """`compiles` or `fails:<primary>`, and the detail: every error of a scaffold that fails."""
    if entry.get("compiled"):
        return "compiles", ""
    errors = "; ".join(f"line {e['line']}: {e['message']}" for e in entry.get("errors", []))
    return "fails:" + (entry.get("primary") or "?"), errors


def clean(text):
    return text.replace("\t", " ").replace("\n", " ")


def rows_for(subject, before, after, tree):
    """The rows of one subject, from its two runs' results.json contents."""
    before_by_id = {s["id"]: s for s in before["scaffolds"]}
    after_by_id = {s["id"]: s for s in after["scaffolds"]}
    rows = []
    for mode, run in before["runs"].items():
        after_run = after["runs"].get(mode, {"ids": [], "declined": []})
        printed = {}
        for file_id in after_run["ids"]:
            entry = after_by_id[file_id]
            printed[(relative(entry.get("file"), tree), entry.get("line"), entry["display"])] = entry
        declined = {(relative(d.get("file"), tree), d.get("line"), d["display"]): d
                    for d in after_run["declined"]}
        for file_id in run["ids"]:
            entry = before_by_id[file_id]
            key = (relative(entry.get("file"), tree), entry.get("line"), entry["display"])
            facts = entry.get("facts", {})
            before_cell, _ = outcome(entry)
            if key in printed:
                after_cell, detail = outcome(printed[key])
            elif key in declined:
                after_cell, detail = "declined:" + declined[key]["category"], declined[key]["reason"]
            else:
                after_cell, detail = "MISSING", ""
            rows.append([subject, mode, entry["display"], f"{key[0]}:{key[1]}",
                         facts.get("shape", "?"), facts.get("access", "?"), before_cell,
                         ",".join(entry.get("causes", [])), after_cell, clean(detail)])
    return rows


def table(rows):
    return "".join("\t".join(str(cell) for cell in row) + "\n" for row in [HEADER] + rows)


def load(out, label, subject):
    path = os.path.join(out, "runs", f"{label}-{subject}", "results.json")
    return json.load(open(path, encoding="utf-8"))


def self_test():
    """The join, on two hand-built runs: each `after` outcome, a subject-relative location, and
    every error of a scaffold that still fails — not only the first."""
    with tempfile.TemporaryDirectory() as scratch:
        tree = os.path.realpath(scratch)
        source = os.path.join(tree, "Sources", "M", "F.swift")

        def scaffold(file_id, display, line, compiled, errors=(), primary=None):
            return {"id": file_id, "display": display, "file": source, "line": line,
                    "compiled": compiled, "errors": list(errors), "primary": primary,
                    "causes": [primary] if primary else [],
                    "facts": {"shape": "static-member", "access": "internal"}}
        before = {"runs": {"seeded": {"ids": ["a", "b", "c", "d"], "declined": []}},
                  "scaffolds": [scaffold(k, f"{k}(_:)", n, False, [{"line": 3, "message": "x"}],
                                         "bare-call:static-member")
                                for n, k in enumerate("abcd", start=1)]}
        two_errors = [{"line": 26, "message": "'oneOf' is unavailable in Swift"},
                      {"line": 32, "message": "'frequency' is unavailable in Swift"}]
        after = {"runs": {"seeded": {"ids": ["A", "B"], "declined": [
                    {"display": "c(_:)", "file": source, "line": 3, "category": "access",
                     "reason": "`c(_:)` is private"}]}},
                 "scaffolds": [scaffold("A", "a(_:)", 1, True),
                               scaffold("B", "b(_:)", 2, False, two_errors, "gen-frequency")]}
        got = {row[2]: row for row in rows_for("S", before, after, tree)}
        expected = {
            "a(_:)": ("compiles", ""),
            "b(_:)": ("fails:gen-frequency", "line 26: 'oneOf' is unavailable in Swift; "
                                             "line 32: 'frequency' is unavailable in Swift"),
            "c(_:)": ("declined:access", "`c(_:)` is private"),
            "d(_:)": ("MISSING", ""),
        }
        failures = [f"{name}: {tuple(got[name][8:])} != {want}"
                    for name, want in expected.items() if tuple(got[name][8:]) != want]
        if got["a(_:)"][3] != "Sources/M/F.swift:1":
            failures.append(f"location not subject-relative: {got['a(_:)'][3]}")
        if table([])[:-1].split("\t") != HEADER:
            failures.append("header line")
    for failure in failures:
        print("FAIL", failure)
    if failures:
        print(f"{len(failures)} self-test failure(s)")
        return 1
    print(f"reference_oracle_scaffold_rows.py self-test OK  ({len(expected)} outcomes)")
    return 0


def main(argv):
    if "--self-test" in argv[1:]:
        return self_test()
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--out", required=True, help="the census work directory")
    parser.add_argument("--before", required=True, help="the BEFORE run's label")
    parser.add_argument("--after", required=True, help="the AFTER run's label")
    parser.add_argument("subjects", nargs="+", help="subject directory names")
    args = parser.parse_args(argv[1:])
    out = os.path.realpath(os.path.expanduser(args.out))
    rows = []
    for subject in args.subjects:
        tree = os.path.join(out, "subjects", subject)
        rows += rows_for(subject, load(out, args.before, subject), load(out, args.after, subject),
                         tree)
    sys.stdout.write(table(rows))
    counts = collections.Counter((r[0], r[1], r[8].split(":")[0]) for r in rows)
    for (subject, mode, after), count in sorted(counts.items()):
        print(f"{subject} {mode} {after}: {count}", file=sys.stderr)
    missing = sum(1 for r in rows if r[8] == "MISSING")
    print(f"{len(rows)} rows, {missing} MISSING", file=sys.stderr)
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
