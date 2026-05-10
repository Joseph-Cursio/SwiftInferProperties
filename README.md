# SwiftInferProperties

Type-directed property inference for Swift. Surfaces idempotence, round-trip pairs, and algebraic-structure (semigroup / monoid / group / semilattice / ring) candidates from function signatures, cross-function pairs, and existing unit tests — for human review, never silent execution.

> **Status:** v1.22.0 (nineteenth calibration cycle — **second consecutive measurement-driven mechanism cycle**; cycle 18 = v1.21 was the first; cycles 15-16 priorities were projected from non-empirical reasoning). Four independently-mergeable workstreams shipped in one release: V1.22.A BucketIterator name extension on V1.21.A's IteratorProtocol carrier veto (closes 3 OC `_HashTable.BucketIterator.*` picks); V1.22.B `RoundTripTemplate` both-sides direction-counter -15 → -25 magnitude bump on V1.12.1 (closes 8 truly-symmetric direction-pairs across OC + 1 Algo); V1.22.C fixed-point-name positive signal on non-lifted idempotence (**first recall-positive signal in the post-V1.4.3 era**, mechanism class 14 — the first new class since v1.19; +10 weight on `{dedupe, simplify, clamp, truncate, standardize}`); V1.22.D stride-style label both-sides veto on round-trip + inverse-pair (cycle-14 demotion target shipped after 4-cycle carry-forward; closes 2 Algo `endOfChunk × startOfChunk` picks). Surface 165 → **152** (-13 = -7.9%) — **second consecutive new cumulative-reduction low at -86.97%** vs cycle-1's 1167-baseline (prior low: -85.86% at cycle 18; -80.4% at cycle 13 before that). First cycle to cross the -86% threshold. Mechanism-class taxonomy 13 → **14** (NEW class 14 — first recall-positive signal in the post-V1.4.3 era). Test count 1804 → 1845 (+41). Cycle-20 priority list rotated post-v1.22 (top: v1.23 = cycle 20 empirical-only re-measurement; NEW cycle-19 finding for asymmetric label class mismatch counter on round-trip; FP approximate-equality 6-cycle carry-forward; math-library `_relaxed*` extension 4-cycle carry-forward). The full design lives in [`docs/SwiftInferProperties PRD v1.0.md`](docs/SwiftInferProperties%20PRD%20v1.0.md) and the v1.22 plan at [`docs/v1.22 Calibration Plan.md`](docs/v1.22%20Calibration%20Plan.md). Current performance baseline: [`docs/perf-baseline-v1.22.md`](docs/perf-baseline-v1.22.md) (re-measured; every row within ±5% of v1.21 baseline, ≤+5% budget met; v1.21 + v1.20 + v1.19 + v1.18 + v1.17 + v1.16 + v1.15 + v1.14 + v1.13 + v1.12 + v1.11 + v1.10 + v1.9 + v1.8 + v1.7 + v1.6 + v1.5 + v1.4 + v1.3 + v1.2 + v1.1 + v0.1.0 baselines retained for forensic comparison).

## What it does

`swift-infer discover --target Foo` walks `Sources/Foo/`, runs the M1–M8 template engine + the M1.4 cross-function pairing pass + the TestLifter M1–M16 test-side cross-validation (round-trip / idempotence / commutativity / monotonicity / count-invariance / reduce-equivalence detectors, plus `Int`/`String`/`Bool`/`Double` inferred preconditions, inferred domains for both round-trip pairs and general consumer-producer chains, and predicate equivalence-class advisories with multi-marker partitions + N-class same-target enum exhaustiveness), and emits ranked suggestions per [PRD §4](docs/SwiftInferProperties%20PRD%20v1.0.md). Each suggestion ships an explainability block with both "why suggested" and "why this might be wrong" (PRD §4.5). Strong-tier suggestions can be triaged with `--interactive`; accepted suggestions emit property-test stubs to `Tests/Generated/SwiftInfer/<TypeName>/` and conformance stubs to `Tests/Generated/SwiftInferRefactors/<TypeName>/` (PRD §16 #1 — never edits existing source).

`swift-infer drift --target Foo` diffs current discovery output against a `.swiftinfer/baseline.json` snapshot and emits non-fatal CI-friendly warnings for new Strong-tier suggestions that lack a recorded decision (PRD §9). Drift never fails the build.

`swift-infer metrics` aggregates `.swiftinfer/decisions.json` files into per-template acceptance / rejection / suppression rates (PRD §17.2). Useful for the empirical-tuning loop SwiftInfer's signal weights are calibrated against — see [`docs/calibration-cycle-1-findings.md`](docs/calibration-cycle-1-findings.md), [`docs/calibration-cycle-2-findings.md`](docs/calibration-cycle-2-findings.md), [`docs/calibration-cycle-3-findings.md`](docs/calibration-cycle-3-findings.md), [`docs/calibration-cycle-4-findings.md`](docs/calibration-cycle-4-findings.md), [`docs/calibration-cycle-5-findings.md`](docs/calibration-cycle-5-findings.md), [`docs/calibration-cycle-6-findings.md`](docs/calibration-cycle-6-findings.md), [`docs/calibration-cycle-7-findings.md`](docs/calibration-cycle-7-findings.md), [`docs/calibration-cycle-8-findings.md`](docs/calibration-cycle-8-findings.md), [`docs/calibration-cycle-9-findings.md`](docs/calibration-cycle-9-findings.md), [`docs/calibration-cycle-11-findings.md`](docs/calibration-cycle-11-findings.md), [`docs/calibration-cycle-12-findings.md`](docs/calibration-cycle-12-findings.md), [`docs/calibration-cycle-13-findings.md`](docs/calibration-cycle-13-findings.md), [`docs/calibration-cycle-14-findings.md`](docs/calibration-cycle-14-findings.md), [`docs/calibration-cycle-15-findings.md`](docs/calibration-cycle-15-findings.md), [`docs/calibration-cycle-16-findings.md`](docs/calibration-cycle-16-findings.md), [`docs/calibration-cycle-17-findings.md`](docs/calibration-cycle-17-findings.md), [`docs/calibration-cycle-18-findings.md`](docs/calibration-cycle-18-findings.md), and [`docs/calibration-cycle-19-findings.md`](docs/calibration-cycle-19-findings.md) for cycle-1 through cycle-19 results (cycle 10 was the v1.13 zero-behavior-change hoist refactor; no findings doc).

## Relationship to SwiftPropertyLaws

SwiftInfer is a one-way downstream of [SwiftPropertyLaws](https://github.com/Joseph-Cursio/SwiftPropertyLaws):

```
SwiftInferProperties → SwiftPropertyLaws (PropertyBackend, DerivationStrategist) → swift-property-based
```

Where SwiftPropertyLaws verifies the laws of *declared* protocol conformances, SwiftInfer surfaces *implicit* properties — and, when enough algebraic evidence accumulates on a type, suggests the standard-library or kit-defined protocol the type could conform to so SwiftPropertyLaws keeps verifying the laws on every CI run thereafter (RefactorBridge). v1.1 emits conformance proposals against `Equatable`, `Comparable`, `Numeric`, `SetAlgebra`, and (kit-defined) `Semigroup`, `Monoid`, `CommutativeMonoid`, `Group`, `Semilattice`.

## Add to your project

```swift
.package(url: "https://github.com/Joseph-Cursio/SwiftInferProperties", from: "1.22.0")
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
