# SwiftInferProperties

Type-directed property inference for Swift. Surfaces idempotence, round-trip pairs, and algebraic-structure (semigroup / monoid / group / semilattice / ring) candidates from function signatures, cross-function pairs, and existing unit tests — for human review, never silent execution.

> **Status:** v1.24.0 (twenty-first calibration cycle — **third consecutive measurement-driven mechanism cycle** after cycles 18 + 19; cycle 21 closes the 1 cycle-19 finding + 3 cycle-20 findings identified in the cycle-20 V1.23.D triage). Four independently-mergeable workstreams shipped in one release: V1.24.A asymmetric label class mismatch counter on round-trip (closes 6 OC cycle-19/20 asymmetric cross-pair rejects); V1.24.B explicit non-idempotent mutator-name veto on idempotence-lifted (closes 9 OC reverse/removeFirst/removeLast/pop*/drop* variants; generalizes V1.21.A's class 7 carrier-protocol-conformance sub-class from Iterator-conforming to any value-semantic carrier); V1.24.C non-deterministic shuffle veto extension (closes 3 OC shuffle variants via name-fallback); V1.24.D capacity/formatter shape-disambiguation veto on idempotence non-lifted (closes 4 OC `_description`/`_minimumCapacity(forScale:)`/`_maximumCapacity(forScale:)`/`_scale(forCapacity:)` shape-coincidence picks). Surface 152 → **130** (-22 = -14.5%; plan-vs-actual within projection -21 to -32) — **new cumulative-reduction low at -88.86%** vs cycle-1's 1167-baseline (prior low: -86.97% at cycle 19). First cycle to cross the -88% threshold. Mechanism-class taxonomy 13 → **14** classes (V1.22.C class 14 first recall-positive; v1.24 adds **0 new classes; 4 extensions** of existing classes 6 + 7). Test count 1845 → 1884 (+39). Cycle-22 priority list rotated post-v1.24: v1.25 = cycle 22 (empirical OR mechanism, loop choice); **NEW cycle-21 finding** for `index(after:)`/`index(before:)` direction-op idempotence non-lifted veto (closes ~13 OC; dominant residual reject class); 8-cycle FP approximate-equality carry-forward; 6-cycle math-library `_relaxed*` carry-forward. §19 ≥70% target reachability remains on-track: cycle-20's 48.8% baseline + cycle-22's projected +5-10pp from v1.24's precision-positive movement → 53-58% projected for cycle-22. The full design lives in [`docs/SwiftInferProperties PRD v1.0.md`](docs/SwiftInferProperties%20PRD%20v1.0.md) and the v1.24 plan at [`docs/v1.24 Calibration Plan.md`](docs/v1.24%20Calibration%20Plan.md). Current performance baseline: [`docs/perf-baseline-v1.24.md`](docs/perf-baseline-v1.24.md) (re-measured; every row within ±5% of v1.22 baseline, ≤+5% budget met; v1.23 + v1.22 + v1.21 + v1.20 + v1.19 + v1.18 + v1.17 + v1.16 + v1.15 + v1.14 + v1.13 + v1.12 + v1.11 + v1.10 + v1.9 + v1.8 + v1.7 + v1.6 + v1.5 + v1.4 + v1.3 + v1.2 + v1.1 + v0.1.0 baselines retained for forensic comparison).

## What it does

`swift-infer discover --target Foo` walks `Sources/Foo/`, runs the M1–M8 template engine + the M1.4 cross-function pairing pass + the TestLifter M1–M16 test-side cross-validation (round-trip / idempotence / commutativity / monotonicity / count-invariance / reduce-equivalence detectors, plus `Int`/`String`/`Bool`/`Double` inferred preconditions, inferred domains for both round-trip pairs and general consumer-producer chains, and predicate equivalence-class advisories with multi-marker partitions + N-class same-target enum exhaustiveness), and emits ranked suggestions per [PRD §4](docs/SwiftInferProperties%20PRD%20v1.0.md). Each suggestion ships an explainability block with both "why suggested" and "why this might be wrong" (PRD §4.5). Strong-tier suggestions can be triaged with `--interactive`; accepted suggestions emit property-test stubs to `Tests/Generated/SwiftInfer/<TypeName>/` and conformance stubs to `Tests/Generated/SwiftInferRefactors/<TypeName>/` (PRD §16 #1 — never edits existing source).

`swift-infer drift --target Foo` diffs current discovery output against a `.swiftinfer/baseline.json` snapshot and emits non-fatal CI-friendly warnings for new Strong-tier suggestions that lack a recorded decision (PRD §9). Drift never fails the build.

`swift-infer metrics` aggregates `.swiftinfer/decisions.json` files into per-template acceptance / rejection / suppression rates (PRD §17.2). Useful for the empirical-tuning loop SwiftInfer's signal weights are calibrated against — see [`docs/calibration-cycle-1-findings.md`](docs/calibration-cycle-1-findings.md), [`docs/calibration-cycle-2-findings.md`](docs/calibration-cycle-2-findings.md), [`docs/calibration-cycle-3-findings.md`](docs/calibration-cycle-3-findings.md), [`docs/calibration-cycle-4-findings.md`](docs/calibration-cycle-4-findings.md), [`docs/calibration-cycle-5-findings.md`](docs/calibration-cycle-5-findings.md), [`docs/calibration-cycle-6-findings.md`](docs/calibration-cycle-6-findings.md), [`docs/calibration-cycle-7-findings.md`](docs/calibration-cycle-7-findings.md), [`docs/calibration-cycle-8-findings.md`](docs/calibration-cycle-8-findings.md), [`docs/calibration-cycle-9-findings.md`](docs/calibration-cycle-9-findings.md), [`docs/calibration-cycle-11-findings.md`](docs/calibration-cycle-11-findings.md), [`docs/calibration-cycle-12-findings.md`](docs/calibration-cycle-12-findings.md), [`docs/calibration-cycle-13-findings.md`](docs/calibration-cycle-13-findings.md), [`docs/calibration-cycle-14-findings.md`](docs/calibration-cycle-14-findings.md), [`docs/calibration-cycle-15-findings.md`](docs/calibration-cycle-15-findings.md), [`docs/calibration-cycle-16-findings.md`](docs/calibration-cycle-16-findings.md), [`docs/calibration-cycle-17-findings.md`](docs/calibration-cycle-17-findings.md), [`docs/calibration-cycle-18-findings.md`](docs/calibration-cycle-18-findings.md), [`docs/calibration-cycle-19-findings.md`](docs/calibration-cycle-19-findings.md), [`docs/calibration-cycle-20-findings.md`](docs/calibration-cycle-20-findings.md), and [`docs/calibration-cycle-21-findings.md`](docs/calibration-cycle-21-findings.md) for cycle-1 through cycle-21 results (cycle 10 was the v1.13 zero-behavior-change hoist refactor; no findings doc).

## Relationship to SwiftPropertyLaws

SwiftInfer is a one-way downstream of [SwiftPropertyLaws](https://github.com/Joseph-Cursio/SwiftPropertyLaws):

```
SwiftInferProperties → SwiftPropertyLaws (PropertyBackend, DerivationStrategist) → swift-property-based
```

Where SwiftPropertyLaws verifies the laws of *declared* protocol conformances, SwiftInfer surfaces *implicit* properties — and, when enough algebraic evidence accumulates on a type, suggests the standard-library or kit-defined protocol the type could conform to so SwiftPropertyLaws keeps verifying the laws on every CI run thereafter (RefactorBridge). v1.1 emits conformance proposals against `Equatable`, `Comparable`, `Numeric`, `SetAlgebra`, and (kit-defined) `Semigroup`, `Monoid`, `CommutativeMonoid`, `Group`, `Semilattice`.

## Add to your project

```swift
.package(url: "https://github.com/Joseph-Cursio/SwiftInferProperties", from: "1.24.0")
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
