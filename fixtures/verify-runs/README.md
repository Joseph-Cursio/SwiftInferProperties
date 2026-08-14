# Retained survey runs

Committed `prove-then-show` runs, kept so a later run can be compared against them **row by
row** rather than count by count.

Written by `prove-then-show --retain-run`, read by `swift-infer survey-diff`.

**Which subject each of these is, and where it came from, lives in
`fixtures/corpora/manifest.json`** — see that directory's README. Prefer `--corpus <id>` over
`--target`: it resolves the tree, the target and the label out of the manifest, so the label
cannot be mistyped and an off-pin checkout says so *in the retained artifact* rather than only
in the memory of whoever ran it.

```
swift-infer corpus                       # what is in the corpus, and whether it has moved
swift-infer prove-then-show --corpus swift-infer-core --budget small --max-parallel 4 \
    --retain-run fixtures/verify-runs/<date>-<target>.json

swift-infer survey-diff \
    --before fixtures/verify-runs/2026-08-14-SwiftInferCore.json \
    --after  fixtures/verify-runs/<next>.json
```

`--retain-label` still wins where it is passed; the manifest removes the *need* to hand-type
one, not the ability to name an unusual arm.

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

## Baselines are REPLACED, not accumulated

Each corpus keeps **one** retained run, refreshed when a sweep confirms a newer commit
reproduces it. Git history holds the superseded ones, which is the retention that matters —
the failure this directory exists to prevent is a run being *destroyed*, and a committed file
replaced in a tracked tree has not been destroyed.

Accumulating a dated file per run would be worse than it looks: every future diff would keep
reporting the same stale differences forever. The swift-format baseline carried two
`build-failed` rows differing only by `:106` → `:107` — the `import PropertyLawKit` line added
in #273 shifting every stub down by one — and re-basing clears that noise from every
comparison that follows.

**The exception is `2026-08-14-GRDB-staged.json`, which is never refreshed.** It is not a
baseline; it is the other half of a pair. Its whole value is that a hand-staged checkout and a
manifest-resolved one agree, and re-running it would defeat the comparison.

### Sweep of 2026-08-14 (`ecaa66f`)

Ten changes landed in the verify path that day — platform floor, stub imports, layout
resolution, the diff engine, the remedy text — each verified against its own corpus and none
against the other two. The sweep is the check none of them got:

| corpus | result |
|---|---|
| `SwiftInferCore` | identical at row level |
| swift-format | identical but for 2 known line shifts |
| GRDB (native) | identical at row level |

**All three are controls.** The prediction going in was that `SwiftInferCore` would move,
because Core gained code that day — wrong: the Core-side change was a remedy *string* inside an
existing function, which adds no public surface for a template to propose a law about. The rest
was `SwiftInferCLI`, not the surveyed target.

A clean sweep is the weak-but-correct outcome. The informative version of this run would have
been a surprise, and there wasn't one.

## Inventory

**This table is prose; `fixtures/corpora/manifest.json` is the checked copy.**
`CorpusManifestTests` asserts in both directions — every manifest run exists and is a run of
the target its entry claims, and every `.json` here is registered by exactly one corpus. The
silent direction is the second: an unregistered run sits in this directory looking like a
baseline while carrying no remote, no revision binding and no reason for existing.

| file | subject | taken |
|---|---|---|
| `2026-08-14-SwiftInferCore.json` | `SwiftInferCore` @ `ecaa66f` — post-fix sweep | 2026-08-14 |
| `2026-08-14-SwiftFormat.json` | swift-format `SwiftFormat` @ `d2bd4b3` — post-fix sweep | 2026-08-14 |
| `2026-08-14-GRDB-staged.json` | GRDB `GRDB` @ `b83108d10` — **STAGED**, see below | 2026-08-14 |
| `2026-08-14-GRDB-native.json` | GRDB `GRDB` @ `b83108d10` — **NATIVE**, untouched checkout, post-fix sweep | 2026-08-14 |

**The two GRDB runs are the same subject reached by different routes, and keeping both is the
point.** The staged arm moved 167 files and edited a manifest; the native arm reads
`path: "GRDB"` from the manifest as it ships. They agree bucket-for-bucket — 307 picks,
5 Proven / 1 Refuted / 277 Unverifiable / 24 Inconclusive — with 42 stubs carrying
`@testable import GRDB` in both. That agreement is the strongest evidence available that the
layout resolver finds the same tree a human `git mv` found, and it is only checkable because
both runs were retained.

The 5 rows that differ are cause-only, all from the `PropertyLawKit` import line shifting stub
line numbers — the documented cost of that fix, not a layout effect.

**GRDB is a STAGED subject and its numbers must never be quoted as GRDB-as-shipped.** GRDB
declares `path: "GRDB"`, so its 167 sources sit at repo root and `prove-then-show --target X`
— which resolves `Sources/<target>` unconditionally and has no `--sources` escape hatch —
cannot reach the package at all. The run was obtained by `git mv GRDB Sources/GRDB` and
deleting the `path:` line in a throwaway worktree: two edits, package otherwise untouched,
builds clean. That is the MacCloud shim precedent (CLAUDE.md's `--sources` row) reused for a
SwiftPM library rather than an Xcode project.

**The workaround does not close the gap.** Reach is unchanged for any package laid out this
way; a human moved the files. Recorded as an open finding, not as a fixed one.

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
