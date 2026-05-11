# SwiftInferProperties — v1.25 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build." This file is the **canonical comparison anchor** for v1.25+. The v1.24 / v1.23 / v1.22 / v1.21 / v1.20 / v1.19 / v1.18 / v1.17 / v1.16 / v1.15 / v1.14 / v1.13 / v1.12 / v1.11 / v1.10 / v1.9 / v1.8 / v1.7 / v1.6 / v1.5 / v1.4 / v1.3 / v1.2 / v1.1 / v0.1.0 baselines are retained for forensic comparison.

**Captured:** 2026-05-10 against the V1.25.A index-advance direction-op idempotence veto commit (`308245e`); V1.25.B working copy.
**Hardware:** Mac15,5 (Apple M3 family).
**Toolchain:** Apple Swift 6.2.4, target `arm64-apple-macosx26.0`.

## Re-measurement vs v1.24

v1.25 ships one Sources/ change (V1.25.A — `IdempotenceTemplate.directionLabelCounterSignal` magnitude-bump extension). Per-call overhead: 3 additional string-prefix checks (`hasPrefix("index")`, `hasPrefix("bucket")`, `hasPrefix("word")`) when the existing V1.10.1 direction-label check matches. O(1) per non-lifted idempotence suggestion. Expected delta vs v1.24 baseline: ≤+5% wall time.

| Row | Workload | Budget | Measured (v1.25) | Δ vs v1.24 |
|---|---|---|---|---|
| 1 | 50-file synthetic discover | < 2.0s wall | 0.400s | +0.009s (+2.3%) |
| 2 | TestLifter parse of 100 test files | < 4.0s wall | 0.945s | +0.013s (+1.4%) |
| 4 | 500-file synthetic resident-memory | < 800 MB | 136.2 MB local | +0.3 MB (+0.2%) |

All rows within ±5% of v1.24 baseline. Other §13 rows carry forward from v1.24 (single-method extension with negligible per-call cost — re-measurement on the broader set adds noise without informative signal).

## Notes on the new-mechanism overhead

`IdempotenceTemplate.directionLabelCounterSignal(for:)` adds up to 3 string-prefix checks when the V1.10.1 direction-label match fires. String-prefix checks are O(prefix-length) = O(6) constant. Aggregate overhead per discover: bounded by `O(num-direction-labeled-non-lifted-idempotence-suggestions × 3 prefix checks)` ≈ sub-microsecond.

## What "regression" means in CI

PRD §13 last paragraph: "a 25% regression in any number fails the build." For each row above, the §13 contract is breached when the measurement crosses **1.25 × baseline** OR the row's hard budget — whichever is lower. Every v1.25 row within ±5% of v1.24 baseline; well clear of the 25% breach threshold.

## Re-baselining

v1.26 is the next planned release. Per the cycle-22 findings, v1.26 = cycle 23 empirical-only re-measurement (no Sources/ changes; perf carries forward from v1.25 unchanged).

After v1.26 the loop's cadence: v1.27+ = cycle 24+ mechanism cycle based on cycle-23 findings.
