#!/usr/bin/env python3
"""Bucket a `verify --all-from-index` JSONL stream by template x outcome.

Mirrors the bucketing the `predicate` survey used in open-threads.md so the two
are comparable: `ran and held` = measured-bothPass, refuted = measured-defaultFails,
and the declines split by the reason carried in outcomeDetail.
"""
import json
import re
import sys
import collections

PATH = sys.argv[1] if len(sys.argv) > 1 else "whole-corpus-survey.jsonl"

records = []
for line in open(PATH):
    line = line.strip()
    if line:
        records.append(json.loads(line))


def reason(rec):
    """Collapse outcomeDetail into the census buckets."""
    outcome = rec["outcome"]
    detail = rec.get("outcomeDetail") or ""
    if outcome == "measured-bothPass":
        return "ran and held"
    if outcome == "measured-defaultFails":
        return "ran and REFUTED"
    if outcome == "measured-edgeCaseAdvisory":
        return "ran, edge advisory"
    if outcome == "architectural-coverage-pending":
        if detail.startswith("unsupported-carrier"):
            return "decline: no generator for carrier"
        if detail.startswith("unsupported-template"):
            return "decline: no composer for template"
        if detail.startswith("unsupported-pair"):
            return "decline: no pair resolved"
        if detail.startswith("monotonicity-domain"):
            return "decline: domain not Comparable"
        if "no such module" in detail:
            return "decline: no such module"
        return "decline: " + detail[:60]
    if outcome == "measured-error":
        if "timed-out" in detail:
            return "error: timed out"
        if detail.startswith("parse-error"):
            return "error: parse"
        return "error: build-failed"
    return outcome


for rec in records:
    rec["bucket"] = reason(rec)

# ---- headline ------------------------------------------------------------
total = len(records)
ran = sum(1 for r in records if r["bucket"].startswith("ran"))
held = sum(1 for r in records if r["bucket"] == "ran and held")
refuted = sum(1 for r in records if r["bucket"] == "ran and REFUTED")
print(f"records: {total}")
print(f"LAWS THAT RAN: {ran}  ({held} held, {refuted} refuted, "
      f"{ran - held - refuted} edge-advisory)")

# The denominator that means something. `Advisory` rows cannot execute a law by
# construction, so counting them makes the ratio smaller for reasons that have
# nothing to do with the tool getting worse — which is exactly how the 2026-08-19
# re-take was first reported as a decline when it was a 50% -> 65% increase.
# Streams from that date carry `tier`; older ones do not, and the line says so
# rather than silently reporting the total as if it were the ratio.
runnable = [r for r in records if r.get("tier") in ("Strong", "Likely", "Possible")]
advisory = [r for r in records if r.get("tier") == "Advisory"]
if runnable or advisory:
    ran_runnable = sum(1 for r in runnable if r["bucket"].startswith("ran"))
    share = f"{100 * ran_runnable / len(runnable):.1f}%" if runnable else "n/a"
    print(f"OF THE RUNNABLE TIERS: {ran_runnable} of {len(runnable)} = {share}"
          f"   ({len(advisory)} Advisory rows excluded — they cannot execute a law)")
else:
    print("(no `tier` in this stream — pre-2026-08-19; run tier_split.py with an index "
          "to get the runnable-tier ratio, and do not read the total as one)")
print()

# ---- per template --------------------------------------------------------
by_template = collections.defaultdict(collections.Counter)
for rec in records:
    by_template[rec["templateName"]][rec["bucket"]] += 1

order = sorted(by_template, key=lambda t: -sum(by_template[t].values()))
print(f"{'template':28} {'n':>4} {'ran':>4} {'held':>5} {'ref':>4}  breakdown")
print("-" * 100)
for template in order:
    counts = by_template[template]
    n = sum(counts.values())
    r = sum(v for k, v in counts.items() if k.startswith("ran"))
    h = counts["ran and held"]
    f = counts["ran and REFUTED"]
    rest = ", ".join(
        f"{k}={v}" for k, v in counts.most_common() if not k.startswith("ran")
    )
    print(f"{template:28} {n:4} {r:4} {h:5} {f:4}  {rest}")
print("-" * 100)
tot = collections.Counter()
for counts in by_template.values():
    tot.update(counts)
print(f"{'TOTAL':28} {total:4} {ran:4} {held:5} {refuted:4}")
print()

# ---- every bucket, corpus-wide ------------------------------------------
print("all buckets, corpus-wide:")
for k, v in tot.most_common():
    print(f"  {v:4}  {k}")
print()

# ---- refutations, named --------------------------------------------------
refs = [r for r in records if r["bucket"] == "ran and REFUTED"]
if refs:
    print(f"refutations ({len(refs)}):")
    for r in sorted(refs, key=lambda x: (x["templateName"], x["primaryFunctionName"])):
        ce = (r.get("shrunkCounterexample") or r.get("counterexample") or "")
        ce = re.sub(r"\s+", " ", ce)[:60]
        print(f"  {r['templateName']:24} {r['primaryFunctionName'][:44]:46}"
              f" carrier={str(r['carrier'])[:24]:26} {ce}")
    print()

# ---- errors, named (these are defects, not coverage boundaries) ----------
errs = [r for r in records if r["bucket"].startswith("error")]
if errs:
    print(f"errors ({len(errs)}) — defects in what we generated, not coverage limits:")
    for r in sorted(errs, key=lambda x: x["templateName"]):
        detail = re.sub(r"\s+", " ", r.get("outcomeDetail") or "")[:110]
        print(f"  {r['templateName']:24} {r['primaryFunctionName'][:38]:40} {detail}")
    print()

# ---- carrier declines, grouped by carrier -------------------------------
carrier_declines = collections.Counter(
    str(r["carrier"]) for r in records
    if r["bucket"] == "decline: no generator for carrier"
)
if carrier_declines:
    print("carriers with no derivable generator:")
    for k, v in carrier_declines.most_common():
        print(f"  {v:4}  {k}")
