# SwiftInferProperties

Type-directed property inference for Swift. Surfaces idempotence, round-trip pairs, and algebraic-structure (semigroup / monoid / group / semilattice / ring) candidates from function signatures, cross-function pairs, and existing unit tests — for human review, never silent execution.

> **Status:** Pre-M1 skeleton. The full design lives in [`docs/SwiftInferProperties PRD v0.3.md`](docs/SwiftInferProperties%20PRD%20v0.3.md).

## Relationship to SwiftProtocolLaws

SwiftInfer is a one-way downstream of [SwiftProtocolLaws](https://github.com/Joseph-Cursio/SwiftProtocolLaws):

```
SwiftInferProperties → SwiftProtocolLaws (PropertyBackend, DerivationStrategist) → swift-property-based
```

Where SwiftProtocolLaws verifies the laws of *declared* protocol conformances, SwiftInfer surfaces *implicit* properties — and, when enough algebraic evidence accumulates on a type, suggests the standard-library protocol the type could conform to so SwiftProtocolLaws can keep verifying the laws on every CI run thereafter (RefactorBridge).

## Build & test

```sh
swift package clean && swift test
```

The current skeleton has no behavior; the test target only asserts the namespace compiles.

## License

MIT — see [LICENSE](LICENSE).
