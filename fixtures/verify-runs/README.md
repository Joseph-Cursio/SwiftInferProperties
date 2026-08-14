# Retained survey runs

Committed `prove-then-show` runs, kept so a later run can be compared against them **row by
row** rather than count by count.

Written by `prove-then-show --retain-run`, read by `swift-infer survey-diff`.

```
swift-infer prove-then-show --target SwiftInferCore --budget small --max-parallel 4 \
    --retain-run fixtures/verify-runs/<date>-<target>.json \
    --retain-label "<target> @ <sha> (kit <version>) — what this arm is"

swift-infer survey-diff \
    --before fixtures/verify-runs/2026-08-14-SwiftInferCore.json \
    --after  fixtures/verify-runs/<next>.json
```

## Why these are committed

Four full surveys of `SwiftInferCore` are on record —
`docs/measurements/roadtest-self-dogfood-2026-08-08.md` §8, §9 arm G, §10.10 and §11. Every one
produced a per-pick record carrying identity, bucket and decline cause. **None of those streams
survives.** §11.1 had to write down that at least one pick changed bucket and that saying which
would need the previous run's row list, "which this document does not record."

That is a discarded artifact rather than a missing feature, and it has now been diagnosed three
times without being fixed. `fixtures/whole-corpus-survey/`'s README records a run that
**overwrote the very file it was being compared against**. `VerifyEvidence.corpusProvenance`
was added because "two survey streams taken a week apart are not comparable without this." Both
of those made a single run more self-describing; neither made a run *survive*.

`.swiftinfer/` is gitignored and swept by `make clean-temp` **by design** — that is what it is
for. A comparison baseline that a routine cleanup deletes is not a baseline. Hence `fixtures/`.

Cost: about 50 KB of JSON per ~160 picks.

## What is retained, and what is deliberately not

The retained artifact is the **survey stream** (`SurveyRecord`), not
`.swiftinfer/verify-evidence.json`.

That is not a preference. The evidence store is **lossy in exactly the bucket that matters**:
`architecturalCoveragePending` collapses to `measuredError` on write, as
`VerifyCommand+AllFromIndex.swift:23` says in as many words. Unverifiable is where every
interesting movement in this repo's history has been — §9.3's nine syntax-node rows, §9.7's
re-attribution, §11.3's two `BodySignalVisitor` rows — so a diff built on the store could not
have answered a single one of those questions.

## The two readings the diff exists to give you

**A change of decline cause inside one bucket is reported as loudly as a change of bucket.**
§11.3's result was two rows moving from `unsupported-carrier: BodySignalVisitor` to `subject
not visible to tests`. Both are Unverifiable. The count went 61 → 61 and a count-level
comparison reports *nothing*, while what actually happened is that the tool stopped telling a
reader to write a `gen()` for a visitor whose subject is `private` anyway. This is §9.9's rule
— "a decline-reason count is a hypothesis, not a finding, until the rows are opened" — with the
rows opened mechanically instead of by hand for the fifth time.

**A verdict change is split by whether the subject's body moved.** `SuggestionIdentity` omits
the body on purpose (§10.2 — it also keys `decisions.json` and the user's `// swiftinfer: skip`
markers, which must survive a refactor), so a row keeps its identity across an edit. The diff
uses `subjectFingerprint` to separate:

- **body changed too** — the ordinary reading; the code moved and the verdict followed.
- **body byte-identical** — the *tool* changed, or the run is not deterministic. Read this one.
- **no fingerprint on one side** — reported as its own answer, never folded into either.

## Traps, inherited from the runs that produced these

- **Run in a fresh `git worktree`.** `.swiftinfer/` is gitignored, so a worktree gives a clean
  index by construction — no archive-and-restore, and no risk of surveying the union of every
  past run. §8's method note.
- **`--retain-label` names the ARM, not the file.** "SwiftInferCore @ c998752 (kit 3.28.0)"
  beats "run 5" to a reader six months out.
- **An identical diff is a result, not a null.** §10.1 recorded a bucket-for-bucket identical
  run as "the correct result and ... a control, not a null." The report says so explicitly
  rather than printing nothing, because silence is also what a broken diff produces.
- **Do not compare a retained run against a *remembered* count.** §10.3's rule stands: both
  arms on the same day, or the comparison is between a measurement and a memory.

## Inventory

| file | subject | taken |
|---|---|---|
| `2026-08-14-SwiftInferCore.json` | `SwiftInferCore` @ `c998752`, kit 3.28.0 | 2026-08-14 |
| `2026-08-14-SwiftFormat.json` | swift-format `SwiftFormat` @ `d2bd4b3` — first third-party run | 2026-08-14 |

**The swift-format entry is the POST-fix arm (arm C).** The pre-fix arm is not retained here on
purpose: it is 129 rows all reporting one instrument failure (the verifier's macOS floor sat
below the kit's, so every build died), and banking it as a baseline would invite a future diff
to read the instrument's repair as a change in swift-format. Its numbers are recorded in the
commit that fixed it — 0 executed before, 2 after — which is where a *superseded* measurement
belongs.

**Retaining it also caught the fix being wrong the first time.** The corpus-floor rule had two
implementations; the first repair went into the one `prove-then-show` does not call, and the
A/B came back **byte-identical, 129 rows, nothing moved**. The renderer said so explicitly
rather than printing nothing, which is the whole argument for the empty-diff wording above.
