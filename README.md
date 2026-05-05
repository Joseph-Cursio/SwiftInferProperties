# SwiftInferProperties

Type-directed property inference for Swift. Surfaces idempotence, round-trip pairs, and algebraic-structure (semigroup / monoid / group / semilattice / ring) candidates from function signatures, cross-function pairs, and existing unit tests — for human review, never silent execution.

> **Status:** v1.1.0 (SemVer 0.x → 1.x; M10 inferred domains + M11 equivalence-class advisories shipped on top of the v0.1.0 surface). The full design lives in [`docs/SwiftInferProperties PRD v1.0.md`](docs/SwiftInferProperties%20PRD%20v1.0.md). Current performance baseline: [`docs/perf-baseline-v1.1.md`](docs/perf-baseline-v1.1.md) (v0.1.0 baseline retained for forensic comparison at [`docs/perf-baseline-v0.1.md`](docs/perf-baseline-v0.1.md)).

## What it does

`swift-infer discover --target Foo` walks `Sources/Foo/`, runs the M1–M8 template engine + the M1.4 cross-function pairing pass + the TestLifter M1–M11 test-side cross-validation (round-trip / idempotence / commutativity / monotonicity / count-invariance / reduce-equivalence detectors, plus inferred preconditions, inferred domains, and predicate equivalence-class advisories), and emits ranked suggestions per [PRD §4](docs/SwiftInferProperties%20PRD%20v1.0.md). Each suggestion ships an explainability block with both "why suggested" and "why this might be wrong" (PRD §4.5). Strong-tier suggestions can be triaged with `--interactive`; accepted suggestions emit property-test stubs to `Tests/Generated/SwiftInfer/<TypeName>/` and conformance stubs to `Tests/Generated/SwiftInferRefactors/<TypeName>/` (PRD §16 #1 — never edits existing source).

`swift-infer drift --target Foo` diffs current discovery output against a `.swiftinfer/baseline.json` snapshot and emits non-fatal CI-friendly warnings for new Strong-tier suggestions that lack a recorded decision (PRD §9). Drift never fails the build.

## Relationship to SwiftPropertyLaws

SwiftInfer is a one-way downstream of [SwiftPropertyLaws](https://github.com/Joseph-Cursio/SwiftPropertyLaws):

```
SwiftInferProperties → SwiftPropertyLaws (PropertyBackend, DerivationStrategist) → swift-property-based
```

Where SwiftPropertyLaws verifies the laws of *declared* protocol conformances, SwiftInfer surfaces *implicit* properties — and, when enough algebraic evidence accumulates on a type, suggests the standard-library or kit-defined protocol the type could conform to so SwiftPropertyLaws keeps verifying the laws on every CI run thereafter (RefactorBridge). v1.1 emits conformance proposals against `Equatable`, `Comparable`, `Numeric`, `SetAlgebra`, and (kit-defined) `Semigroup`, `Monoid`, `CommutativeMonoid`, `Group`, `Semilattice`.

## Add to your project

```swift
.package(url: "https://github.com/Joseph-Cursio/SwiftInferProperties", from: "1.1.0")
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
