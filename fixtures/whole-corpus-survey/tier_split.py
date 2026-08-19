#!/usr/bin/env python3
"""Bucket a `verify --all-from-index` JSONL stream by TIER x outcome.

The companion to `analyse.py`, which buckets by template x outcome. The tier cut
is the one `open-threads.md` calls the honest headline — the aggregate averages a
large `Possible` recall floor with a handful of high-confidence rows, and those
are different populations asked different questions.

**Streams from 2026-08-19 onward carry the tier**, so the index argument is now
optional and this reads one file:

    python3 tier_split.py <stream.jsonl> [index.json]

Before that the tier had to be joined in from the index the run was taken
against, and that join is what made the ratio easy to get wrong: the index can
be — and twice in one day was — overwritten between the run and the reading.
On 2026-08-19 the re-take was first reported as "178 of 538 execute, down from
139 of 281". 266 of those 538 are `Advisory`, which cannot execute a law by
construction; the honest comparison is 178 of 272 against 139 of 279, an
INCREASE from 50% to 65%.

That is why RUNNABLE is printed below the table and the total is not. The tier
cut is not a nicety here — the aggregate averages populations asked different
questions, and one of them can never answer.

Rows with no tier from either source are reported separately rather than
dropped. A silent drop would understate a tier, and understating the tier that
runs nothing is exactly the failure this measurement exists to detect.
"""
import json
import sys
from collections import defaultdict

TIER_ORDER = ["Strong", "Likely", "Possible", "Advisory"]

# Tiers whose rows CAN execute a law. `Advisory` cannot, by construction —
# `Tier.advisory` is "an informational tier for stand-alone advisory findings that
# don't carry a runnable property".
RUNNABLE_TIERS = {"Strong", "Likely", "Possible"}


def classify(outcome: str) -> str:
    """Bucket an outcome string into ran/held/refuted/declined."""
    if outcome.startswith("measured-"):
        if "bothPass" in outcome:
            return "held"
        if "Fails" in outcome or "refut" in outcome:
            return "refuted"
        return "error"
    return "declined"


def main() -> int:
    if len(sys.argv) not in (2, 3):
        print(__doc__)
        return 2
    stream_path = sys.argv[1]

    # The index is a FALLBACK for streams frozen before the tier was recorded.
    tier_by_hash = {}
    if len(sys.argv) == 3:
        with open(sys.argv[2]) as handle:
            index = json.load(handle)
        for entry in index.get("entries", []):
            tier_by_hash[entry["identityHash"]] = entry.get("tier", "(no tier)")

    rows = []
    with open(stream_path) as handle:
        for line in handle:
            line = line.strip()
            if line.startswith("{"):
                rows.append(json.loads(line))

    buckets = defaultdict(lambda: defaultdict(int))
    declines = defaultdict(lambda: defaultdict(int))
    unmatched = 0
    for row in rows:
        # Stream first: it cannot be paired with the wrong index.
        tier = row.get("tier") or tier_by_hash.get(row["identityHash"])
        if tier is None:
            unmatched += 1
            continue
        kind = classify(row.get("outcome", ""))
        buckets[tier][kind] += 1
        buckets[tier]["n"] += 1
        if kind == "declined":
            declines[tier][row.get("outcomeDetail", "(none)").split(":")[0]] += 1

    print(f"{'tier':<12}{'n':>6}{'ran':>6}{'held':>6}{'ref':>6}{'err':>6}{'declined':>10}")
    print("-" * 52)
    for tier in TIER_ORDER + sorted(set(buckets) - set(TIER_ORDER)):
        if tier not in buckets:
            continue
        row = buckets[tier]
        ran = row["held"] + row["refuted"]
        print(
            f"{tier:<12}{row['n']:>6}{ran:>6}{row['held']:>6}"
            f"{row['refuted']:>6}{row['error']:>6}{row['declined']:>10}"
        )

    runnable = sum(buckets[t]["n"] for t in buckets if t in RUNNABLE_TIERS)
    ran_runnable = sum(
        buckets[t]["held"] + buckets[t]["refuted"] for t in buckets if t in RUNNABLE_TIERS
    )
    total = sum(buckets[t]["n"] for t in buckets)
    share = f"{100 * ran_runnable / runnable:.1f}%" if runnable else "n/a"
    print()
    print(f"RUNNABLE tiers: {ran_runnable} of {runnable} ran = {share}")
    print(f"  (the total is {ran_runnable} of {total}; quoting it counts rows that cannot run)")
    if unmatched:
        print(f"  {unmatched} row(s) carried no tier from stream or index")

    print()
    for tier in TIER_ORDER:
        if declines.get(tier):
            reasons = ", ".join(
                f"{reason} x{count}" for reason, count in sorted(
                    declines[tier].items(), key=lambda item: -item[1]
                )
            )
            print(f"  {tier} declines: {reasons}")

    if unmatched:
        print(f"\n  !! {unmatched} stream row(s) had no matching index entry — "
              f"wrong index for this stream?")
    return 0


if __name__ == "__main__":
    sys.exit(main())
