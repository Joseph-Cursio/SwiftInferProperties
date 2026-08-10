#!/usr/bin/env python3
"""Bucket a `verify --all-from-index` JSONL stream by TIER x outcome.

The companion to `analyse.py`, which buckets by template x outcome. The tier cut
is the one `open-threads.md` calls the honest headline — the aggregate averages a
large `Possible` recall floor with a handful of high-confidence rows, and those
are different populations asked different questions.

**The stream does not carry the tier.** It records `identityHash`, `outcome`,
`outcomeDetail`, `primaryFunctionName`, `templateName` and `carrier` — so the
tier has to be joined in from the index the run was taken against. That join is
the reason this script exists rather than a `--by tier` flag on `analyse.py`: it
needs a second input, and pairing the WRONG index with a stream would silently
mis-bucket every row.

    python3 tier_split.py <stream.jsonl> <index.json>

Rows whose hash is absent from the index are reported separately rather than
dropped. A silent drop here would understate a tier, and understating the tier
that runs nothing is exactly the failure this measurement exists to detect.
"""
import json
import sys
from collections import defaultdict

TIER_ORDER = ["Strong", "Likely", "Possible"]


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
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    stream_path, index_path = sys.argv[1], sys.argv[2]

    with open(index_path) as handle:
        index = json.load(handle)
    tier_by_hash = {}
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
        tier = tier_by_hash.get(row["identityHash"])
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
