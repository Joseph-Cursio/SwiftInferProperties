# Whole-corpus verify survey — frozen streams (2026-08-05, 2026-08-19)

The raw `verify --all-from-index` JSON streams behind the numbers in
`docs/design-internal/open-threads.md` → *Decisions* → *The whole-corpus number*.

**Committed because the run destroyed its own comparison artifact.** The survey's
`persistSurveyBatch` overwrote `.swiftinfer/verify-evidence.json`, which is gitignored, so the
figure that run was being compared against no longer exists anywhere. A measurement whose evidence
lives only in a temp directory is not re-checkable, and this project's standing rule is that a
remembered count carries no record of the flags it was taken with.

## Files

| file | what |
|---|---|
| `2026-08-19-whole-corpus.jsonl` | **538 records**, one per index entry, no `--template` filter — the re-take |
| `2026-08-05-whole-corpus.jsonl` | 281 records, one per index entry, no `--template` filter |
| `2026-08-05-predicate-ab-before.jsonl` | 129 records, the `--template predicate` A/B **before**-arm |
| `analyse.py` | buckets a stream by template × outcome; `python3 analyse.py <file>` |
| `tier_split.py` | buckets by **tier** × outcome — the cut `open-threads.md` calls the honest headline; `python3 tier_split.py <stream.jsonl> <index.json>`. **Needs a second input**, which is why it is not a `--by tier` flag: the stream carries no tier, so it must be joined in from the index the run was taken against |

## Provenance — everything needed to re-run

| | |
|---|---|
| subject | `SwiftInferProperties@1ef71283ce5100a11f0dffc10daf6bbec74b8fda` |
| A/B before-binary | `SwiftInferProperties@2f65f92` |
| command | `swift-infer verify --all-from-index --max-parallel 4` (release binary) |
| whole-corpus run | 2026-08-05 02:24–03:41 UTC · 76 min · 7.7 CPU-hours · 107 GB workdirs |
| A/B before-arm | 2026-08-05 07:58–08:32 UTC · 129 entries |

Both SHAs are reachable in this repo, so either binary rebuilds with `swift build -c release`.

## The 2026-08-19 re-take

| | |
|---|---|
| subject | `SwiftInferProperties@15bb86c` |
| index | **rebuilt from scratch**, `swift-infer index --target …` over all seven library targets |
| command | `swift-infer verify --all-from-index --max-parallel 4` (release binary) |
| run | 2026-08-19 12:31–12:42 UTC · **11 min** |
| result | **178 of 538 execute** — 163 held, 15 refuted, 16 errored, 344 declined |

**The counts are NOT comparable to 2026-08-05's; the ratio is.** This README records the
*verify* command the first run used and not how its index was built, so the 281-entry
population cannot be reconstructed. What can be said is that **the executing share fell
from 49% to 33%** while the corpus grew 281 → 538: the population nearly doubled and
executing laws grew by 28%.

**The 76-minute figure above no longer holds** — the re-take took 11 minutes over nearly
twice the population. Do not budget from the older number.

## Two caveats that matter when re-running

1. **The index must be deleted first.** `IndexStore.upsert` keeps historical entries, so an A/B
   against an existing index reports the union of every run that ever happened.
2. **The AFTER-arm's counts are not in here**, because it was the whole-corpus run itself. Per
   §10.3 the comparison must be two binaries **on the same day over the same corpus** — do not
   compare a fresh run against the numbers in this directory. Re-take both arms.

## What these streams already settled

- 139 of 281 entries execute a law: 130 hold, 9 refute.
- The `predicate` A/B: BEFORE 74 / AFTER 76 ran, carrier declines **49 in both arms** — which
  refuted a suspected regression rather than confirming one.


## The tier cut recorded here cannot be regenerated from this directory

`tier_split.py` needs the **index the stream was taken against**, and that index was never
frozen beside the stream. `.swiftinfer/index.json` is gitignored and has been rewritten many
times since 2026-08-05, so the join has no second input any more.

Pairing the stream with a *later* index does not degrade gracefully — it mis-buckets almost
everything. Run today against the current index, 187 of 281 rows have no matching entry, and the
94 that do match land in a completely different shape from the recorded one:

```
tier             n   ran  held   ref   err  declined      ← today's index, NOT the recorded cut
Strong           7     4     0     4     0         3
Likely          18    17    17     0     0         1
Possible        69    45    45     0     6        18

  !! 187 stream row(s) had no matching index entry — wrong index for this stream?
```

**The recorded cut — `Strong` 3/0 run, `Likely` 27/23/4 refute, `Possible` 249/116/5 refute —
therefore stands on its 2026-08-05 write-up and cannot be re-derived here.** It is not wrong; it
is unreproducible, which is a weaker thing than the rest of this directory offers and should be
said rather than assumed.

**The script's unmatched-row report is what makes that visible**, and it is the reason to prefer
it over a flag that silently inner-joins: it declines to answer rather than answering wrongly.
This is the same failure this fixture already records about itself — *"committed because the run
destroyed its own comparison artifact"* — arriving a second time, for the index rather than the
evidence file.

**For any future frozen stream: freeze a `hash → tier` sidecar beside it.** It is 281 lines of
JSON for this one, it makes the headline checkable forever, and it is the only part of this
measurement that depends on state the repo does not keep.
