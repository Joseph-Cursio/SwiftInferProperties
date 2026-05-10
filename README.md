# SwiftInferProperties

Type-directed property inference for Swift. Surfaces idempotence, round-trip pairs, and algebraic-structure (semigroup / monoid / group / semilattice / ring) candidates from function signatures, cross-function pairs, and existing unit tests — for human review, never silent execution.

> **Status:** v1.23.0 (twentieth calibration cycle — **fourth empirical-only release** in the loop's history after cycles 6 = v1.9 = 26.7%, 14 = v1.17 = 34.8%, 17 = v1.20 = 52.3%; binary-equivalent to v1.22.0). Headline: **21/43 = 48.8%** Possible-tier acceptance rate on the post-v1.22 152-surface — **outcome D** under the v1.23 plan thresholds (Aggregate < 52%; **first non-monotonic move in the loop's history** at -3.5pp from cycle-17). The drop is **explained by a calibration trade-off + sample-distribution shift, NOT a precision regression**: (1) V1.22.D suppressed cycle-14/17 ACCEPT Algo `endOfChunk × startOfChunk` triple (calibration trade-off per v1.22 plan §"Risks"; ~-2-3pp aggregate cost); (2) cycle-20 sample concentrates on first-measurement reject classes (OC asymmetric round-trip cross-pairs at 5/5 reject + OC sort/shuffle/reverse-class lifted-idempotence at 4 reject + 1 unknown); (3) cycle-20 round-trip weighting shift (47% → 36% CM canonical-anchor weight). Surface analysis at cycle 19 confirmed -183 candidates closed across cycles 18 + 19 (precision-positive on the surface). Per-mechanism: **V1.18.C dual-style 5/5 = 100% rate-stability** (largest mechanism-class precision contribution in the loop's history); V1.22.C fixed-point-name positive signal (class 14) ships infrastructure but 0 sample picks (no surfacing on cycle-1..14 corpora). Four-point trajectory: 26.7% → 34.8% → 52.3% → 48.8%. Cycle-21 priority list rotated post-v1.23 (top: asymmetric label class mismatch counter cycle-19+20 reconfirmed; **3 NEW cycle-20 findings**: reverse/removeFirst/removeLast veto for non-Iterator carriers; non-deterministic shuffle veto extension; capacity-from-scale + formatter shape-disambiguation veto on idempotence non-lifted). §19 ≥70% target is +21pp from cycle-20; three more mechanism cycles at cycle-18 magnitude reach it. The full design lives in [`docs/SwiftInferProperties PRD v1.0.md`](docs/SwiftInferProperties%20PRD%20v1.0.md) and the v1.23 plan at [`docs/v1.23 Calibration Plan.md`](docs/v1.23%20Calibration%20Plan.md). Current performance baseline: [`docs/perf-baseline-v1.23.md`](docs/perf-baseline-v1.23.md) (v1.22 carry-forward; v1.22 + v1.21 + v1.20 + v1.19 + v1.18 + v1.17 + v1.16 + v1.15 + v1.14 + v1.13 + v1.12 + v1.11 + v1.10 + v1.9 + v1.8 + v1.7 + v1.6 + v1.5 + v1.4 + v1.3 + v1.2 + v1.1 + v0.1.0 baselines retained for forensic comparison).

## What it does

`swift-infer discover --target Foo` walks `Sources/Foo/`, runs the M1–M8 template engine + the M1.4 cross-function pairing pass + the TestLifter M1–M16 test-side cross-validation (round-trip / idempotence / commutativity / monotonicity / count-invariance / reduce-equivalence detectors, plus `Int`/`String`/`Bool`/`Double` inferred preconditions, inferred domains for both round-trip pairs and general consumer-producer chains, and predicate equivalence-class advisories with multi-marker partitions + N-class same-target enum exhaustiveness), and emits ranked suggestions per [PRD §4](docs/SwiftInferProperties%20PRD%20v1.0.md). Each suggestion ships an explainability block with both "why suggested" and "why this might be wrong" (PRD §4.5). Strong-tier suggestions can be triaged with `--interactive`; accepted suggestions emit property-test stubs to `Tests/Generated/SwiftInfer/<TypeName>/` and conformance stubs to `Tests/Generated/SwiftInferRefactors/<TypeName>/` (PRD §16 #1 — never edits existing source).

`swift-infer drift --target Foo` diffs current discovery output against a `.swiftinfer/baseline.json` snapshot and emits non-fatal CI-friendly warnings for new Strong-tier suggestions that lack a recorded decision (PRD §9). Drift never fails the build.

`swift-infer metrics` aggregates `.swiftinfer/decisions.json` files into per-template acceptance / rejection / suppression rates (PRD §17.2). Useful for the empirical-tuning loop SwiftInfer's signal weights are calibrated against — see [`docs/calibration-cycle-1-findings.md`](docs/calibration-cycle-1-findings.md), [`docs/calibration-cycle-2-findings.md`](docs/calibration-cycle-2-findings.md), [`docs/calibration-cycle-3-findings.md`](docs/calibration-cycle-3-findings.md), [`docs/calibration-cycle-4-findings.md`](docs/calibration-cycle-4-findings.md), [`docs/calibration-cycle-5-findings.md`](docs/calibration-cycle-5-findings.md), [`docs/calibration-cycle-6-findings.md`](docs/calibration-cycle-6-findings.md), [`docs/calibration-cycle-7-findings.md`](docs/calibration-cycle-7-findings.md), [`docs/calibration-cycle-8-findings.md`](docs/calibration-cycle-8-findings.md), [`docs/calibration-cycle-9-findings.md`](docs/calibration-cycle-9-findings.md), [`docs/calibration-cycle-11-findings.md`](docs/calibration-cycle-11-findings.md), [`docs/calibration-cycle-12-findings.md`](docs/calibration-cycle-12-findings.md), [`docs/calibration-cycle-13-findings.md`](docs/calibration-cycle-13-findings.md), [`docs/calibration-cycle-14-findings.md`](docs/calibration-cycle-14-findings.md), [`docs/calibration-cycle-15-findings.md`](docs/calibration-cycle-15-findings.md), [`docs/calibration-cycle-16-findings.md`](docs/calibration-cycle-16-findings.md), [`docs/calibration-cycle-17-findings.md`](docs/calibration-cycle-17-findings.md), [`docs/calibration-cycle-18-findings.md`](docs/calibration-cycle-18-findings.md), [`docs/calibration-cycle-19-findings.md`](docs/calibration-cycle-19-findings.md), and [`docs/calibration-cycle-20-findings.md`](docs/calibration-cycle-20-findings.md) for cycle-1 through cycle-20 results (cycle 10 was the v1.13 zero-behavior-change hoist refactor; no findings doc).

## Relationship to SwiftPropertyLaws

SwiftInfer is a one-way downstream of [SwiftPropertyLaws](https://github.com/Joseph-Cursio/SwiftPropertyLaws):

```
SwiftInferProperties → SwiftPropertyLaws (PropertyBackend, DerivationStrategist) → swift-property-based
```

Where SwiftPropertyLaws verifies the laws of *declared* protocol conformances, SwiftInfer surfaces *implicit* properties — and, when enough algebraic evidence accumulates on a type, suggests the standard-library or kit-defined protocol the type could conform to so SwiftPropertyLaws keeps verifying the laws on every CI run thereafter (RefactorBridge). v1.1 emits conformance proposals against `Equatable`, `Comparable`, `Numeric`, `SetAlgebra`, and (kit-defined) `Semigroup`, `Monoid`, `CommutativeMonoid`, `Group`, `Semilattice`.

## Add to your project

```swift
.package(url: "https://github.com/Joseph-Cursio/SwiftInferProperties", from: "1.23.0")
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
