# Whole-corpus verify survey — frozen streams (2026-08-05)

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
| `2026-08-05-whole-corpus.jsonl` | 281 records, one per index entry, no `--template` filter |
| `2026-08-05-predicate-ab-before.jsonl` | 129 records, the `--template predicate` A/B **before**-arm |
| `analyse.py` | buckets a stream by template × outcome; `python3 analyse.py <file>` |

## Provenance — everything needed to re-run

| | |
|---|---|
| subject | `SwiftInferProperties@1ef71283ce5100a11f0dffc10daf6bbec74b8fda` |
| A/B before-binary | `SwiftInferProperties@2f65f92` |
| command | `swift-infer verify --all-from-index --max-parallel 4` (release binary) |
| whole-corpus run | 2026-08-05 02:24–03:41 UTC · 76 min · 7.7 CPU-hours · 107 GB workdirs |
| A/B before-arm | 2026-08-05 07:58–08:32 UTC · 129 entries |

Both SHAs are reachable in this repo, so either binary rebuilds with `swift build -c release`.

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
