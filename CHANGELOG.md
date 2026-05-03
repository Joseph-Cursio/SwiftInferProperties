# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — 2026-05-03

First public pre-release. The TemplateEngine surface (PRD v0.4 §5) and TestLifter M1 (PRD §7.9) are feature-complete; v0.1.0 ships them under SemVer 0.x semantics (API may break in 0.2.x). The PRD's "v1.1+ trajectory" heading describes the post-v0.1.0 work, not a future v1.1 — naming carryover from the design doc.

### TemplateEngine

- **M1 — Discovery + idempotence + round-trip pairing.** SwiftSyntax pipeline; CLI discovery tool (`swift-infer discover`); idempotence + round-trip templates wired through the §4 scoring engine and §4.5 explainability block; basic cross-function pairing (type + naming filter); `// swiftinfer: skip` rejection markers honored.
- **M2 — Algebraic-structure templates.** Commutativity, associativity, identity-element templates active alongside M1's idempotence + round-trip.
- **M3 — Confidence model + cross-validation.** Per-signal weights surfaced in the explainability block; M3.4 contradiction pass; M3.5 dormant `crossValidationFromTestLifter` seam.
- **M4 — Generator inference via `DerivationStrategist`.** Per-suggestion `GeneratorMetadata` populated from the kit's strategist; `.todo` fallback for inference fall-throughs (PRD §16 #4).
- **M5 — `@Discoverable` + `@CheckProperty` macro recognition.** +35 signal for annotated functions; macro expands `@CheckProperty` into peer `@Test` declarations.
- **M6 — Workflow operationalization.** `--interactive` triage with `[A/B/B'/s/n/?]` prompts; `Tests/Generated/SwiftInfer/` writeouts; `swift-infer drift` mode with non-fatal CI-friendly warnings; `.swiftinfer/decisions.json` + `baseline.json` infrastructure.
- **M7 — Monotonicity + invariant-preservation + RefactorBridge.** Two new templates and the conformance-proposal bridge that writes to `Tests/Generated/SwiftInferRefactors/`.
- **M8 — Algebraic-structure composition cluster.** CommutativeMonoid / Group / Semilattice / Numeric (Ring) / SetAlgebra emitter arms; multi-proposal accumulator + `[A/B/B'/s/n/?]` prompt; `InversePairTemplate` (Possible-tier non-Equatable T fallback).

### TestLifter

- **M1 — Test-body parser + slicer + round-trip detector + cross-validation.** XCTest + Swift Testing parser; PRD §7.2 four-rule slicing pass; `AssertAfterTransformDetector` for the round-trip pattern; `LiftedSuggestion` + `CrossValidationKey` matching surface; CLI wiring lights up the +20 cross-validation signal end-to-end.

### Kit coordination

- Consumes [SwiftProtocolLaws](https://github.com/Joseph-Cursio/SwiftProtocolLaws) v1.9.0 (kit-defined `Semigroup`, `Monoid`, `CommutativeMonoid`, `Group`, `Semilattice`) for M7 + M8 conformance writeouts.

### Hard guarantees + performance

- All PRD §16 hard guarantees (#1 source-file-immutable, #2 never-deletes-tests, #3 drift-never-fails-CI, #4 `.todo`-on-fallthrough, #5 `--target`-required + scope guard, #6 byte-identical reproducibility) ship with explicit release-gate integration tests.
- All PRD §13 performance budgets ship with regression tests; v0.1.0 calibration revised the row 4 memory budget from 200 MB to 600 MB based on R1.1.b measurement (see `docs/perf-baseline-v0.1.md`).
- PRD §14 + §19 runtime no-network guarantee covered by URLProtocol-based runtime interception in addition to the static no-networking-APIs grep.

[0.1.0]: https://github.com/Joseph-Cursio/SwiftInferProperties/releases/tag/v0.1.0
