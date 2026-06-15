# Calibration cycle 129 — shared prebuilt artifact (warm TCA survey workdir)

> **STATUS: SHIPPED (v1.128.0).** The cycle-120 perf tail: the measured
> survey no longer cold-builds the heavy TCA dependency graph once per
> reducer. TCA identities now share one corpus-keyed workdir and reuse its
> warm `.build` (deps compile once; each later identity is a stub-only
> incremental rebuild). Measured: the C2 survey dropped **~200s → 90s
> (~2.2×)**, outcomes unchanged. Spike-first (cold 63s vs stub-only
> incremental 4.4s). Captured 2026-06-15.

## The lever (spike-measured)

A `.tca` verifier inlines the *whole* corpus + the dependency graph (TCA +
swift-syntax + kit + PropertyBased); across a reducer's identities — and
across reducers in the same corpus — **only the per-identity stub differs.**
A hand spike measured the gap directly:

| Build | Time |
|---|---|
| Cold (deps + corpus + stub) | **63.4s** |
| Stub-only incremental (same warm workdir) | **4.4s** |

~14× per identity. The pre-129 survey keyed the verify workdir
per-reducer, so each reducer-group cold-built the identical deps — and
running them concurrently (cycle 120) *contended* (4 concurrent cold TCA
builds ≈ 200s, not 4× faster). The fix turns that into one cold build + N
serial stub-only incrementals.

## What shipped

1. **`VerifierWorkdir.synthesize` skips unchanged writes** (`writeIfChanged`)
   — an identical co-compiled corpus file or Package.swift keeps its mtime,
   so SwiftPM/llbuild sees no change and the rebuild stays incremental.
   General + safe; the prerequisite for warm reuse.
2. **Shared corpus-keyed TCA workdir** — `.tca` identities resolve to one
   `tca-corpus-<module>` workdir (not per-reducer), so all identities of a
   corpus survey reuse the same warm `.build`. Non-`.tca` keeps the
   per-(reducer, identity) segment (cycle 120).
3. **Per-workdir build lock** — `executeAndParse` serializes
   synthesize → build → run per workdir path. The shared TCA workdir thus
   warm-reuses serially (no parallel rebuild clobbering the in-flight one);
   distinct non-TCA workdirs hold distinct locks and **still run in
   parallel** (cycle-120 behavior preserved exactly).

## Why serial-for-TCA beats parallel-for-TCA

The two are mutually exclusive (parallel builds into one workdir corrupt
llbuild). The numbers decide it: serial-shared = 1 cold + 9 incremental ≈
63 + 9×4.4 ≈ 103s of *work*, measured at **90s** wall-clock; parallel-cold =
4 concurrent cold builds contending for cores ≈ **200s**. Serial-shared wins
*and* uses far less peak memory (one swift-syntax compile, not four).

## Verification

- **C2 survey (`TCAVerifyCorpusMeasuredTests`)** — same outcomes (10
  identities → 9 `bothPass` + 1 `defaultFails`; disclosures intact; discover
  renders `(Verified)`) in **90s vs ~200s**.
- **No regression in shared infra** — `synthesize` is used by every verify
  path: `MeasuredPromotionDeterminismMeasuredTests` (identical `Result` —
  determinism preserved), `VerifyInteractionSurveyMeasuredTests`,
  `IdempotenceSurveyCorpusMeasuredTests` (11/1 baseline holds) all green.
  Non-`.tca` surveys behave identically (distinct workdirs → parallel).
- `VerifierWorkdirTests` (14) green; `swiftlint` clean on touched files.

## What's next

This was the last item with a clear payoff. The `.tca` epic is complete
(Phase A/B + C2) and now scales: each added curated reducer costs ~one
stub-only incremental, not a cold build. Remaining genuinely-optional: C1's
literal discovery-corpus extractor (only if that number is ever required).
Default idempotence stays `.likely`; the other four interaction families
stay `.possible` behind `--include-possible`.
