# v1.71 Calibration Cycle 68 — Findings (time-to-adoption: PRD §17.2 reaches 4/5, no schema bump)

Captured: 2026-05-14. swift-infer at v1.71.

## Headline

**A metrics-infrastructure cycle.** v1.71 ships PRD §17.2's
**time-to-adoption** metric — the fourth of the section's five derived
metrics. `swift-infer metrics` has carried three since V1.4.1
(acceptance / rejection / suppression rate); the two holdouts were
flagged "v1.5+, needs new `DecisionRecord` fields (a schema-v3 bump)."
That framing was wrong for time-to-adoption: **it needs no schema
change.** Cycle 67 left the roadmap empty; cycle 68 picks up one of its
named candidate directions.

Cycle-66's **52/103 = 50.5% measured-execution** carries forward
unchanged — v1.71 touches no emitter, resolver, or carrier path.

## The reframe — why no schema-v3 bump

The v1.4 plan assumed time-to-adoption needed a new
`DecisionRecord.surfacedAt: Date` field, plumbed through the discover
render path. Two facts overturn that:

1. **The anchors already persist.** Time-to-adoption is
   `timestamp(accept) − timestamp(first surfaced)`. The decision
   timestamp is on `DecisionRecord`; the "first surfaced" anchor is
   `SemanticIndexEntry.firstSeenAt` — stamped on the first
   `swift-infer index` run and *preserved across upserts*. Both are
   already on disk; the metric is a **join**, not a new field.
2. **A `surfacedAt` field would have been worse.** Stamped at
   interactive-triage time, it would read ≈0 — interactive triage *is*
   the surfacing moment. `firstSeenAt → decision timestamp` is the
   genuine UX-friction signal the PRD's "long times suggest the
   suggestion is unclear" intends.

So time-to-adoption is a `metrics` enhancement that joins the
SemanticIndex by identity hash — exactly the shape of the V1.64.D
verify-evidence cross-reference and the V1.70.A `--decisions` join.

## What shipped — V1.71.A

- `MetricsRenderer.timeToAdoptionRows` joins accepted `DecisionRecord`s
  against `[SemanticIndexEntry]` by identity hash
  (`VerifyEvidenceRecorder.normalizedIdentityHash` bridges the index's
  `0x`-prefixed form to the decision store's stripped form), computes
  `record.timestamp − entry.firstSeenAt` clamped at 0, and buckets per
  template into count + min/median/max.
- `MetricsCommand` loads the SemanticIndex alongside decisions +
  verify evidence: default mode from the package root's `index.json`,
  `--decisions` mode from each corpus's sibling `index.json` — the
  same opt-in-per-corpus, skip-missing-sibling-silently shape as
  V1.70.A.
- New `Time-to-adoption (PRD §17.2)` render section, with two
  sentinels: no SemanticIndex loaded, or an index with no
  accepted-and-joined decisions.
- The clamp-at-0 rule means a decision recorded *before* its first
  `index` run reads as "adopted instantly" rather than as a negative
  duration.

The logic lives in `MetricsRenderer+TimeToAdoption.swift` — extracted
so `MetricsRenderer.swift`'s already-large enum body stays at its prior
length.

## The fifth metric — still deferred, and why it's *not* a schema problem

**Post-acceptance failure rate** ("accepted suggestions whose test
fails on commit / total accepted") remains the one unshipped §17.2
metric. It is genuinely deferred — but **not** because of schema:

- *Storage* is the easy part — a parallel `post-acceptance-outcomes.json`
  keyed by identity hash, joined at `metrics` render time, exactly
  mirroring `verify-evidence.json` (V1.64.D) and the V1.70.A /
  V1.71.A join pattern. No `Decisions` schema bump.
- The real blocker is **trigger design**: nothing records "the emitted
  test later failed on commit." `DecisionRecord` is written once at
  triage time; the failure happens later, in the consuming repo's CI.
  *What* records the outcome, and *when* — a CI hook the consuming repo
  installs, a manual `swift-infer accept-check` gesture, or
  swift-infer running the generated tests itself — is an open UX
  decision, not an engineering one.

This matches the v1.4 plan's own note ("v1.5+ at earliest; depends on
UX design for the hook"). It is correctly parked pending that decision.

## Test count

**2512 → 2523 (+11)** — `MetricsTimeToAdoptionTests` (the join +
median arithmetic, `formatDuration` unit boundaries, the section's two
sentinels + populated table) and `MetricsTimeToAdoptionLoadTests` (the
`--decisions` sibling-`index.json` join end-to-end). §13 budgets
unchanged — the renderer is pure.

## What's next (post-v1.71)

PRD §17.2 is at **4/5** metrics. Remaining candidate directions, none
currently scoped:

1. **Post-acceptance failure rate** — the 5th §17.2 metric; gated on
   the trigger-design decision above, not on schema or storage.
2. **Kit-side deferrals** — `Ring` / `CommutativeGroup` / `Group acting
   on T`, parked per `CLAUDE.md` "Kit-side coordination".
3. **Incremental index analysis** — `swift-infer index` rebuilds from
   a full discover each run; PRD §20.1 mentions incremental as a
   future optimization, deferred until profiling shows it's needed.

## Artifacts

- v1.71 source: `Sources/SwiftInferCLI/MetricsRenderer+TimeToAdoption.swift`
  (the join + section), `Sources/SwiftInferCLI/MetricsCommand.swift`
  (SemanticIndex load in both modes).
- Prior cycle: `docs/calibration-cycle-67-findings.md` (v1.70 roadmap
  cleanup — `metrics --decisions` evidence join + V1.42.C.5 implicit
  reindex).
