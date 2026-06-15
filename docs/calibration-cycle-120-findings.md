# Calibration cycle 120 — per-invariant workdir isolation → reducer-grouped parallel survey

> **STATUS: SHIPPED (v1.125.0).** `verify-interaction --all` now runs
> reducer-grouped bounded-parallel with warm-`.build/` reuse — a measured
> ~40% wall-clock cut on the widened survey (116s → 65s), all outcomes
> unchanged + deterministic. Delivered in four milestones; milestone 3
> shipped parallelism that showed *no* speedup, and milestone 4 diagnosed
> why and fixed it. Captured 2026-06-14.

## Why this was built

CLAUDE.md "What's next" optional item: a parallel `--all` survey. The
cycle-114 survey was **serial by design** because the verify workdir was
keyed per-*reducer*, so two identities on one reducer (e.g. `refresh` +
`reset`) shared a workdir and couldn't build concurrently without
clobbering each other's `main.swift` / `.build/`. Scoped first (this turn);
the scope flagged the payoff as "developer-time on the survey, ranked below
leave-it-serial" and warned the speedup would be sub-linear. Built anyway,
with the data deciding the final shape.

## The four milestones

**M1 — per-invariant workdir keying.** `workdirSegment(for:identity:)`
appends the invariant's normalized hash (`Inbox_body__<hash>`) so sibling
identities get distinct workdirs; the bare `runPipeline` / single-shot path
(no identity) keeps the reducer-only segment byte-for-byte. Extracted
`recordEvidence` → `+Evidence.swift` and `findPackageRoot` /
`workdirSegment` → `+Workdir.swift` to stay under the `file_length` cap
(and cleared a pre-existing 418-line violation on the main file).

**M2 — race-free batch recording.** `runWithInvariant` gained
`persistEvidence: Bool = true`; the survey passes `false` and calls a new
`recordEvidenceBatch` once after the fan-out — one read-modify-write of
`verify-evidence.json` instead of N interleaved ones. Single + batch paths
share a `makeEvidence` builder so they write identically.

**M3 — bounded-parallel fan-out.** Replaced the serial loop with a bounded
`withTaskGroup` (prime `maxParallel`, then drain-and-refill), mirroring the
algebraic `--all-from-index` survey. New `--max-parallel` flag (default 4),
`Sendable` `RunContext`, error-tolerant per identity (a thrown verify →
`.measuredError` entry, not an aborted survey), results re-sorted to
discovery order for deterministic output.

**M4 — reducer-grouped reuse (the actual speedup).** See below.

## The M3 finding: parallelism alone bought nothing

The cycle-116 widened survey under M3 (per-invariant, parallelism 4) ran in
**116s** — vs the ~106s serial baseline. **No speedup, slightly slower.**
Two compounding causes:

1. **`swift build` is CPU-bound and contends.** Four concurrent builds each
   already saturate cores, so wall-clock doesn't divide by 4.
2. **Per-invariant isolation forfeited build reuse.** The old serial path's
   reducer-keyed workdir meant a second identity on a reducer hit a warm
   `.build/` and rebuilt only the ~one changed stub file (fast incremental).
   M1's per-invariant workdirs are each cold → every identity does a full
   package rebuild. The reuse loss roughly cancelled the parallelism gain.

This confirmed the scope's prediction with data, and reframed the goal: the
lever isn't "more concurrency," it's "concurrency *without* losing reuse."

## The M4 fix: group by reducer

The unit of parallelism became a **reducer group**, not a single identity:

- Distinct reducer groups build **concurrently** (bounded `withTaskGroup`).
- A group's sibling identities run **serially in one shared reducer-keyed
  workdir**, so the 2nd+ rebuilds incrementally (warm `.build/` —
  `VerifierWorkdir.synthesize` leaves `.build/` untouched, overwriting only
  `main.swift`).
- Distinct groups touch distinct workdirs → no concurrent clobber.

So `runWithInvariant` reverted to a reducer-keyed workdir (M1's
per-invariant forcing dropped); `workdirSegment(for:identity:)` is retained
as a documented hook for a possible intra-reducer fan-out but is unused on
this path. The survey groups by `reducerQualifiedName` (first-appearance
order), fans out per group, flattens + re-sorts to discovery order.

For the cycle-116 corpus (5 reducers, 12 identities) this is 5 groups on 4
slots, each group `1 cold + (k-1) incremental` builds — strictly better
than both all-serial and all-cold-parallel.

## Measured result

| Path | cycle-116 survey (5 reducers / 12 identities) |
|---|---|
| Original serial (pre-cycle-120) | ~106s |
| M3 per-invariant parallel(4) | 116s (no gain) |
| **M4 reducer-grouped parallel(4)** | **65s (~40% faster)** |

All three paths produce identical outcomes: **11 `measured-bothPass` + 1
`measured-defaultFails`** (`setBadge`), `discover-interaction` promotes only
the survivors. Output + batch-record order deterministic via the
discovery-order re-sort. The cycle-114 two-witness survey (1 reducer, no
cross-group parallelism) is 36s, marginally faster than serial via the
within-group incremental reuse.

## Verification

- **Fast:** `VerifyInteractionPipelineRenderTests` (+2: per-identity vs bare
  workdir segments), `InteractionVerifyEvidencePersistenceTests` (+2: batch
  upserts all siblings in one write; empty batch is a no-op).
- **Measured (`.subprocess`):** `VerifyInteractionSurveyMeasuredTests`
  (two witnesses on one reducer — the original collision case) +
  `IdempotenceSurveyCorpusMeasuredTests` (widened corpus, 11/1 split) —
  both green under the reducer-grouped path.
- `swiftlint` clean on all touched files (net **−1** warning vs cycle start
  — the M1 extraction cleared the main file's pre-existing `file_length`).

## What's next (unchanged, minus this item)

Remaining optional follow-up: the `CorpusPackager` `dependencies:` thread
(package the dependency-bearing TCA corpora). The value-generator path stays
shelved (cycle 119). Default idempotence stays `.likely`; the other four
interaction families stay `.possible` behind `--include-possible`.

A noted **further** speedup, not pursued: a shared *prebuilt user-package
artifact* so even cross-reducer (cold) builds skip recompiling the common
dependency graph. M4's within-group reuse captured the bulk of the win; this
would chip at the residual cold-build-per-reducer cost.
