# SwiftInferProperties

Type-directed property inference for Swift. Surfaces idempotence, round-trip pairs, and algebraic-structure (semigroup / monoid / group / semilattice / ring) candidates from function signatures, cross-function pairs, and existing unit tests — for human review, never silent execution.

> **Status:** v1.35.0 (thirty-second calibration cycle). Ships **carrier-aware refactor suggestions** built on the v1.34-enriched SemanticIndex — closes the PRD §20.1 motivating use case ("you have three monoids; consider unifying them under a custom Monoid protocol"). New `swift-infer suggest-refactors` subcommand reads `.swiftinfer/index.json`, groups entries by `typeName`, classifies each cluster into a 5-shape priority-ordered taxonomy (`algebraicStructure` / `idempotenceCluster` / `dualStyleCluster` / `roundTripCluster` / `generalCluster` catch-all), and renders human-readable suggestions with stable curated text per shape. CLI flags: `--min-suggestions` (default 3), `--shape`, `--limit`. Two workstreams: V1.35.A `RefactorCluster` + `RefactorClusterAnalyzer` pure-function classifier (priority-ordered, nil-typeName-filtering); V1.35.B `suggest-refactors` subcommand with curated per-shape suggestion text (stable for PR-description grep). End-to-end verified: ComplexModule → 1 cluster (`Complex` × 20, algebraic-structure); OrderedCollections → 8 clusters across 6 distinct carrier types including nested paths (`OrderedSet.UnorderedView` dualStyleCluster ×8, `OrderedDictionary.Elements.SubSequence` general, etc.). No acceptance-rate re-measurement (query/render layer; per-template inference precision unchanged). Read-only per PRD §16 #1 — never modifies source. Test count 2027 → 2059 (+32). Cycle-33 priority: **v1.36 Constraint Engine upgrade (PRD §20.2)** — the multi-cycle architectural refactor pushed back one cycle by the v1.35 carrier-aware-refactors insertion. The full design lives in [`docs/SwiftInferProperties PRD v1.0.md`](docs/SwiftInferProperties%20PRD%20v1.0.md) and the v1.35 plan at [`docs/v1.35 Calibration Plan.md`](docs/v1.35%20Calibration%20Plan.md). Current performance baseline: [`docs/perf-baseline-v1.35.md`](docs/perf-baseline-v1.35.md). [previous: v1.34.0] (twenty-third calibration cycle — **fifth empirical-only release** after cycles 6 = 26.7%, 14 = 34.8%, 17 = 52.3%, 20 = 48.8%; binary-equivalent to v1.25.0). Headline: **25/37 = 67.6%** Possible-tier acceptance rate — **outcome A** (Aggregate ≥ 60%); **+18.8pp from cycle-20's 48.8% (the largest single-cycle aggregate jump in the loop's history)**. **§19 ≥70% target now within +2.4pp** — sample-noise band on n=40. Five-point trajectory: 26.7% → 34.8% → 52.3% → 48.8% → 67.6%. The cycle-20 non-monotonic step (-3.5pp) is validated as calibration-trade-off + sample-shift — the surviving v1.25 surface composition has materially higher per-template accept rates (round-trip 85.7%, dual-style-consistency 100%, idempotence-lifted 66.7%). Drivers: V1.21.C + V1.22.B/D + V1.24.A closed cross-product round-trip noise; V1.24.B + V1.24.C + V1.25.A closed direction-op + non-deterministic lifted-idempotence rejects; V1.24.D + V1.25.A reduced idempotence non-lifted from 23 picks (5-cycle 0%) to 3 picks (all unknown) — 0% drag eliminated. **V1.18.C dual-style 100% rate-stability across 3 consecutive measurement points** (largest mechanism-class precision contribution in loop history). Cycle-24 priority list rotated post-v1.26 (top: FP approximate-equality template arm 10-cycle carry-forward; 2 NEW cycle-23 findings — Algo Iterator-like survivors + OC bucket/word inverse-pair). The full design lives in [`docs/SwiftInferProperties PRD v1.0.md`](docs/SwiftInferProperties%20PRD%20v1.0.md) and the v1.26 plan at [`docs/v1.26 Calibration Plan.md`](docs/v1.26%20Calibration%20Plan.md). Current performance baseline: [`docs/perf-baseline-v1.26.md`](docs/perf-baseline-v1.26.md) (v1.25 carry-forward; v1.25 + v1.24 + earlier baselines retained for forensic comparison).

## What it does

`swift-infer discover --target Foo` walks `Sources/Foo/`, runs the M1–M8 template engine + the M1.4 cross-function pairing pass + the TestLifter M1–M16 test-side cross-validation (round-trip / idempotence / commutativity / monotonicity / count-invariance / reduce-equivalence detectors, plus `Int`/`String`/`Bool`/`Double` inferred preconditions, inferred domains for both round-trip pairs and general consumer-producer chains, and predicate equivalence-class advisories with multi-marker partitions + N-class same-target enum exhaustiveness), and emits ranked suggestions per [PRD §4](docs/SwiftInferProperties%20PRD%20v1.0.md). Each suggestion ships an explainability block with both "why suggested" and "why this might be wrong" (PRD §4.5). Strong-tier suggestions can be triaged with `--interactive`; accepted suggestions emit property-test stubs to `Tests/Generated/SwiftInfer/<TypeName>/` and conformance stubs to `Tests/Generated/SwiftInferRefactors/<TypeName>/` (PRD §16 #1 — never edits existing source).

`swift-infer drift --target Foo` diffs current discovery output against a `.swiftinfer/baseline.json` snapshot and emits non-fatal CI-friendly warnings for new Strong-tier suggestions that lack a recorded decision (PRD §9). Drift never fails the build.

`swift-infer metrics` aggregates `.swiftinfer/decisions.json` files into per-template acceptance / rejection / suppression rates (PRD §17.2). Useful for the empirical-tuning loop SwiftInfer's signal weights are calibrated against — see [`docs/calibration-cycle-1-findings.md`](docs/calibration-cycle-1-findings.md), [`docs/calibration-cycle-2-findings.md`](docs/calibration-cycle-2-findings.md), [`docs/calibration-cycle-3-findings.md`](docs/calibration-cycle-3-findings.md), [`docs/calibration-cycle-4-findings.md`](docs/calibration-cycle-4-findings.md), [`docs/calibration-cycle-5-findings.md`](docs/calibration-cycle-5-findings.md), [`docs/calibration-cycle-6-findings.md`](docs/calibration-cycle-6-findings.md), [`docs/calibration-cycle-7-findings.md`](docs/calibration-cycle-7-findings.md), [`docs/calibration-cycle-8-findings.md`](docs/calibration-cycle-8-findings.md), [`docs/calibration-cycle-9-findings.md`](docs/calibration-cycle-9-findings.md), [`docs/calibration-cycle-11-findings.md`](docs/calibration-cycle-11-findings.md), [`docs/calibration-cycle-12-findings.md`](docs/calibration-cycle-12-findings.md), [`docs/calibration-cycle-13-findings.md`](docs/calibration-cycle-13-findings.md), [`docs/calibration-cycle-14-findings.md`](docs/calibration-cycle-14-findings.md), [`docs/calibration-cycle-15-findings.md`](docs/calibration-cycle-15-findings.md), [`docs/calibration-cycle-16-findings.md`](docs/calibration-cycle-16-findings.md), [`docs/calibration-cycle-17-findings.md`](docs/calibration-cycle-17-findings.md), [`docs/calibration-cycle-18-findings.md`](docs/calibration-cycle-18-findings.md), [`docs/calibration-cycle-19-findings.md`](docs/calibration-cycle-19-findings.md), [`docs/calibration-cycle-20-findings.md`](docs/calibration-cycle-20-findings.md), [`docs/calibration-cycle-21-findings.md`](docs/calibration-cycle-21-findings.md), [`docs/calibration-cycle-22-findings.md`](docs/calibration-cycle-22-findings.md), [`docs/calibration-cycle-23-findings.md`](docs/calibration-cycle-23-findings.md), [`docs/calibration-cycle-24-findings.md`](docs/calibration-cycle-24-findings.md), [`docs/calibration-cycle-25-findings.md`](docs/calibration-cycle-25-findings.md), [`docs/calibration-cycle-26-findings.md`](docs/calibration-cycle-26-findings.md), [`docs/calibration-cycle-27-findings.md`](docs/calibration-cycle-27-findings.md), [`docs/calibration-cycle-28-findings.md`](docs/calibration-cycle-28-findings.md), [`docs/calibration-cycle-29-findings.md`](docs/calibration-cycle-29-findings.md), [`docs/calibration-cycle-30-findings.md`](docs/calibration-cycle-30-findings.md), [`docs/calibration-cycle-31-findings.md`](docs/calibration-cycle-31-findings.md), and [`docs/calibration-cycle-32-findings.md`](docs/calibration-cycle-32-findings.md) for cycle-1 through cycle-32 results (cycle 10 was the v1.13 zero-behavior-change hoist refactor; no findings doc).

## Relationship to SwiftPropertyLaws

SwiftInfer is a one-way downstream of [SwiftPropertyLaws](https://github.com/Joseph-Cursio/SwiftPropertyLaws):

```
SwiftInferProperties → SwiftPropertyLaws (PropertyBackend, DerivationStrategist) → swift-property-based
```

Where SwiftPropertyLaws verifies the laws of *declared* protocol conformances, SwiftInfer surfaces *implicit* properties — and, when enough algebraic evidence accumulates on a type, suggests the standard-library or kit-defined protocol the type could conform to so SwiftPropertyLaws keeps verifying the laws on every CI run thereafter (RefactorBridge). v1.1 emits conformance proposals against `Equatable`, `Comparable`, `Numeric`, `SetAlgebra`, and (kit-defined) `Semigroup`, `Monoid`, `CommutativeMonoid`, `Group`, `Semilattice`.

## Add to your project

```swift
.package(url: "https://github.com/Joseph-Cursio/SwiftInferProperties", from: "1.35.0")
```

Or run as a one-off against an existing target:

```sh
swift run swift-infer discover --target Foo
swift run swift-infer drift --target Foo
```

## Build & test

```sh
swift package clean && swift test
```

The test suite is 1200+ tests across 180+ suites covering every shipped template, every TestLifter detector, the §13 performance budgets, and the §16 hard guarantees. SwiftLint config lives at `.swiftlint.yml`; `swiftlint lint --quiet` should be silent.

## License

MIT — see [LICENSE](LICENSE).
