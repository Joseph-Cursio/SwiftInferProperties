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
| `tier_split.py` | buckets by **tier** × outcome — the cut `open-threads.md` calls the honest headline; `python3 tier_split.py <stream.jsonl> [index.json]`. **The index argument is now optional**: streams from 2026-08-19 carry `tier`, so the stream is read alone and **cannot be paired with the wrong index**. It prints `RUNNABLE tiers` and says outright that the total counts rows which cannot run. The second input remains for older streams |

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
| result | 178 of 538 rows execute — 163 held, 15 refuted, 16 errored, 344 declined |
| **the number that means something** | **178 of 272 RUNNABLE-tier entries = 65%**, against 139 of 279 = **50%** on 2026-08-05 |

> **CORRECTED 2026-08-19, same day, and the error is worth more than the number.** This
> first read *"the executing share fell from 49% to 33%"*. **It rose, 50% → 65%.**
>
> **266 of the 538 rows are `Advisory`, and an `Advisory` row cannot execute a law by
> construction** — `Tier.advisory`'s own doc calls it an *"informational tier for
> stand-alone advisory findings that don't carry a runnable property"*, and all 266
> decline `architectural-coverage-pending`. The 2026-08-05 index contained **none**; this
> one contains 266. Dividing by a denominator that gained 266 structurally-unrunnable rows
> manufactures a decline out of an increase.
>
> **The row that carries this figure in `CLAUDE.md` says "Read the tier cut, not the
> total", and the total is what got quoted.** A rule stated in the index did not survive
> contact with the person writing the next number into it.

**The counts are NOT comparable to 2026-08-05's; the runnable-tier ratio is.** This README
records the *verify* command the first run used and not **how its index was built**, so
the 281-entry population cannot be reconstructed.

**The 76-minute figure above no longer holds** — the re-take took 11 minutes over nearly
twice the population. Do not budget from the older number.

## The 2026-08-22 A/B — raising the trial budget, measured

**Both arms on the same binary and the SAME FROZEN INDEX**, because the delta against
2026-08-19 is confounded: this repo has since gained the module-resolution fix, the
computed-property emitter fix, the availability gate, and SwiftPropertyLaws 4.1.0. Only a
same-binary A/B attributes anything to the budget.

| | |
|---|---|
| subject | `SwiftInferProperties@1abd772a`, SwiftPropertyLaws **4.1.0** |
| **index command** | `swift-infer index --target T` for each of the **six** library targets — `SwiftInferCore`, `SwiftInferTemplates`, `SwiftInferTestLifter`, `SwiftInferCLI`, `SwiftInferMacro`, `SwiftInferKitEvidence` → **543 entries**, then copied aside and passed via `--index-path` so neither arm could silently reindex |
| verify command | `swift-infer verify --all-from-index --max-parallel 4 --index-path <frozen> --budget {small,standard}` (release binary) |
| arm A | `2026-08-22-whole-corpus-N100.jsonl` — 543 records, 23:01–23:12 UTC · 11 min |
| arm B | `2026-08-22-whole-corpus-N1000.jsonl` — 543 records, 23:14–23:25 UTC · 11 min |

*(The README elsewhere says seven library targets; the manifest declares six. Recorded as
used, not as remembered.)*

### Result — the budget moved ONE row of 543

| tier | n | ran | held @100 → @1000 | refuted @100 → @1000 |
|---|---:|---:|---|---|
| Strong | 9 | 5 | 5 → 5 | 0 → 0 |
| Likely | 28 | 25 | 22 → 22 | 3 → 3 |
| Possible | 238 | 149 | **137 → 136** | **12 → 13** |
| Advisory | 268 | 0 | — | — |

**RUNNABLE: 179 of 275 = 65.1% at BOTH budgets**, against 178 of 272 = 65% on 2026-08-19.
**A 10× trial budget and four shipped fixes moved the executing ratio by nothing.**

Exactly one outcome changed, and no previously-refuting row started passing:

```
measured-bothPass → measured-defaultFails   at trial 164
  idempotence · ViewModelRefintResolver.selectionStem(_:) · counterexample "RYFsS"
```

**Hand-checked: a false law.** `selectionStem` strips one trailing `s` / `id` / `ids`, so
`"RYFsS" → "ryfs" → "ryf"`. A one-shot suffix stripper applied twice strips two suffixes —
which is *verbatim* the example the tool's own **"why this might be wrong"** text gives. Same
mechanism as `removingLastComponent()` on swift-system. **The tally is now 18 of 18
hand-checked refutations being false laws.**

### ⚠ What this does NOT settle, and it is the important part

**The home corpus is the corpus the catalogue was built against.** It is the *least* likely
place for a false law to survive, so *one new refutation in 543 rows* is close to the best
case and must not be read as a rate.

The contrast is worth keeping, with its small numbers stated:

| corpus | executing rows | new refutations at N=1000 |
|---|---:|---:|
| home (this survey) | 179 | 1 |
| `swift-system` (unmet) | 8 | 1 |

**Suggestive and not a rate** — n=1 in each arm. But it points the catalogue-truth question
where it belongs: at **unmet subjects**, not here. A survey of the corpus the tool was tuned
on cannot answer whether the tool's laws are true in general.

## The stream now carries its own tier

**Added 2026-08-19, because its absence inverted a headline.** The re-take was first
reported as *"178 of 538 execute, down from 139 of 281"*; 266 of those 538 are `Advisory`
and cannot execute a law by construction, so the honest comparison is 178 of 272 against
139 of 279 — an **increase**, 50% → 65%.

Getting that right required joining to the index the run was taken against, **and that
index had already been overwritten twice the same day**. A stream carrying its own tier
cannot be paired with the wrong index, and `analyse.py` now prints the runnable-tier ratio
beside the total rather than leaving the reader to compute it.

Streams frozen before that date have no `tier`, and both tools say so rather than reporting
the total as if it were the ratio.

## Record the INDEX command, not only the verify command

**Index scope is an unrecorded variable, and it produced three populations of one corpus in
a single day**: 281 (2026-08-05, method unrecorded), **538** (`swift-infer index --target`
over each of the seven library targets), **712** (`verify --all-from-index`'s own wholesale
reindex of `Sources`, which fires when the index is stale).

That is why the first run cannot be reproduced, and it is a provenance gap rather than a
disagreement — the three numbers are all correct about different questions. **Any future
run must record the index command beside the verify command**, and prefer `--index-path`
against a frozen index so a mid-run reindex cannot move the population underneath it.

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
