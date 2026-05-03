# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository state

**M1 + M2 + M3 + M4 + M5 + M6 + M7 + M8 shipped — the v1 TemplateEngine surface is feature-complete.** M8 (algebraic-structure composition cluster per PRD v0.4 §5.4 + §5.8) is complete on `main`. Sub-milestones M8.0–M8.6 landed as individual `feat(M8.x):` commits on top of the M1.1–M1.7 + M2.1–M2.6 + M3.1–M3.6 + M4.1–M4.5 + M5.1–M5.6 + M6.1–M6.6 + M7.1–M7.6 series. M8 ships **InversePairTemplate** (M8.1 — Possible-tier non-Equatable T fallback when RoundTrip vetos; hidden behind `--include-possible`); **four new LiftedTestEmitter arms** (M8.2 — `commutative` / `associative` / `identityElement` / `inversePair` retire the "no stub writeout available for template X in v1" diagnostic across the entire shipped template surface); **InverseElementPairing** (M8.3 — curated unary inverse-name detector + `inverseElementVerbs` Vocabulary key feeding M8.4's Group orchestrator arm); **RefactorBridgeOrchestrator widening** (M8.4.a — TemplateSignal grows from `{associativity, identityElement}` to `{associativity, identityElement, commutativity, idempotence}` + the M8.3 inverse-element witness threading; CommutativeMonoid / Group / Semilattice promotion arms with strict-greatest ranking within each chain branch); **LiftedConformanceEmitter kit-protocol arms** (M8.5 — `commutativeMonoid` / `group` / `semilattice` against `import ProtocolLawKit` v1.9.0; Group threads `inverseWitness` for the kit's `static func inverse(_:)` aliasing); **multi-proposal + `[A/B/B'/s/n/?]` prompt + SetAlgebra secondary** (M8.4.b.1 — open decisions #3 + #6 resolution; `proposalsByType: [String: [RefactorBridgeProposal]]` end-to-end; incomparable arms (CommutativeMonoid + Group on same type) emit separately; Semilattice + curated set-named ops fires the SetAlgebra secondary); **Ring detection + Numeric emitter** (M8.4.b.2 — per-(type, op-set) accumulator + curated additive/multiplicative naming detect "two monoids on same type"; PRD §5.4 row 5 closes); **validation suite + PRD §5.4 docs refresh** (M8.6 — §16 #1 hard-guarantee extension covering all M8 arms; per-arm B-accept integration tests for CMon / Group / Semilattice / Numeric / SetAlgebra; §5.4 kit-protocol-target column refreshed to drop the "no kit protocol yet" language for the now-shipped Group / Semilattice / CommutativeMonoid rows). **The §5.8 M8 acceptance bar (a–i) is met (M8.6):** every PRD §5.4 row is end-to-end implemented through the orchestrator → emitter → InteractiveTriage chain; the §13 perf budget holds at ~0.7s synthetic / ~1.6s swift-collections *with all eight templates + the M8.3 pairing pass + the M8.4 orchestrator widening active*; the §16 #1 hard-guarantee confirms RefactorBridge writeouts go ONLY to `Tests/Generated/SwiftInferRefactors/<TypeName>/<ProtocolName>.swift` for every M8 arm; SwiftLint clean across 692 tests / 54 suites.

**Kit-side coordination.** M7's emits target `Semigroup` + `Monoid` from **SwiftProtocolLaws v1.8.0** (commits `362322e`/v1.8.1 Semigroup + `88cc4a1`/v1.8.2 Monoid + `6c4ec2a`/v1.8.3 macro/discovery integration + `1b3af7d`/v1.8.4 release docs), the kit's first kit-defined protocol cluster. M8.0 extended the kit with **`CommutativeMonoid` + `Group` + `Semilattice`** as **SwiftProtocolLaws v1.9.0** (commits `9c5df0a`/v1.9.1 CommutativeMonoid + `6d80cc1`/v1.9.2 Group + `cfbe99a`/v1.9.3 Semilattice + `9732c7f`/v1.9.4 macro/discovery integration + `5566e4e`/v1.9.4.1 SwiftLint fixup + `c0f5e27`/v1.9.5 release docs), mirroring the v1.8.0 four-commit cadence. SwiftInferProperties consumes the kit via versioned dep (`from: "1.9.0"`) as of commit `69e6618` (2026-05-02). Out of v1.9.0 scope and deferred to v1.10+: kit-side `Ring` (two-op shape — Numeric stays the canonical Ring writeout target per PRD §5.4 row 5), kit-side `CommutativeGroup` (rare in idiomatic Swift; M8.4.b.1's incomparable-arm split emits separate CommutativeMonoid + Group proposals when both apply), kit-side `Group acting on T` (function-space carrier doesn't fit the per-type protocol shape).

**TestLifter M1 shipped — cross-validation `+20` lights up end-to-end.** TestLifter M1 (PRD §7.9) closed on top of the M8 line via sub-commits M1.0–M1.6: SwiftInferTestLifter target + TestSuiteParser (XCTest + Swift Testing) + Slicer (PRD §7.2 four-rule pass) + AssertAfterTransformDetector (round-trip explicit + collapsed shapes) + LiftedSuggestion + new `CrossValidationKey` matching surface + CLI wiring + validation suite. The M3.5 dormant seam (`crossValidationFromTestLifter`) has been widened from `Set<SuggestionIdentity>` to `Set<CrossValidationKey>` (the lighter-weight key TestLifter can derive from a test body without semantic resolution) and is now load-bearing — projects with `Sources/Foo/Codec.swift` (encode/decode pair) AND `Tests/FooTests/CodecTests.swift` (testRoundTrip body) get the +20 PRD §4.1 signal automatically. **TestLifter M1 acceptance bar (a–h) met:** §13 `TestLifter parse of 100 test files < 3s` budget holds at ~0.66s wall; §16 #1 hard-guarantee extended to confirm TestLifter never writes to source files; §15 slicer-never-throws contract backed by a 100-AST seeded fuzz; SwiftLint clean across 755 tests / 104 suites. Out of M1 scope: idempotence/commutativity/etc. detection (M2+); generator inference (M3+); decisions.json persistence + `// swiftinfer: skip` honoring on the test side (M6); counter-signal scanning (M7); convert-counterexample (M8); expanded outputs — preconditions/domains/equivalence-classes (M9). The §5.4 algebraic-structure composition cluster closed at M8.4.b.2's Ring detection; M6.4's "no stub writeout available for template X in v1" diagnostic is now defensive cover for hypothetical future templates rather than a v1 limitation.

**v1.0 cut.** R1.0–R1.4 shipped on top of the M8 + TestLifter M1 line: R1.1.a–h closed every release-blocking PRD §13 perf budget + §16 hard guarantee + §14 runtime-no-network gap with named regression tests (`DriftIncrementalPerformanceTests`, `MemoryCeilingPerformanceTests`, `InteractiveFirstPromptPerformanceTests`, `TestLifterHardGuaranteeTests` §16 #2 extension, `DriftNeverFailsCITests`, `TodoFallbackHardGuaranteeTests`, `TargetScopeHardGuaranteeTests`, `NoNetworkRuntimeTests`); R1.1.b's measurement on the 500-file synthetic surfaced a calibration miss (492 MB vs the v0.3 200 MB target) and the §13 row 4 budget was revised to 600 MB per the §13 calibration authorization, recorded in `docs/perf-baseline-v1.0.md`; R1.3 bumped `Sources/SwiftInferCLI/SwiftInferCommand.swift:26` from `0.0.0-scaffold` → `1.0.0`, refreshed the README and the stale `discussion`/docstring at the same file, added Keep-a-Changelog `CHANGELOG.md` at repo root, and reflected the §13 row 4 calibration in PRD v0.4. The `v1.0.0` git tag (R1.5) is pushed by the user. SwiftLint clean across 764 tests / 111 suites.

With v1.0 cut, the next focus areas are **TestLifter M2** (idempotence + commutativity detection in test bodies, per PRD §7.9 M2+) or **v1.1+ trajectory** (SemanticIndex / IDE integration / `swift-infer apply` / `swift-infer metrics` per PRD §20). The §13 row 4 600 MB calibration also opens a v1.1 perf-tuning target (streaming `FunctionScanner.scanCorpus` + cross-function-pairing bucket pre-filter — both noted in `docs/perf-baseline-v1.0.md`).

## What this repo is

**SwiftInferProperties** — type-directed property inference for Swift. Surfaces idempotence, round-trip pairs, and algebraic-structure (semigroup / monoid / group / semilattice / ring) candidates from function signatures, cross-function pairs, and existing unit tests. All output is human-reviewed; nothing auto-executes.

The package is a one-way downstream of [SwiftProtocolLaws](https://github.com/Joseph-Cursio/SwiftProtocolLaws):

```
SwiftInferProperties → SwiftProtocolLaws (PropertyBackend, DerivationStrategist) → swift-property-based
```

`Package.swift` references SwiftProtocolLaws via a versioned URL dep (`from: "1.9.0"`) as of commit `69e6618`. The dep tracked v1.8.0 from commit `c143258` (when M7.4 needed the kit-defined Semigroup + Monoid) until M8.0 shipped v1.9.0's second kit-defined cluster (CommutativeMonoid + Group + Semilattice) for M8.5's writeouts.

## Where to look

| Question | File |
|---|---|
| Product scope, milestones (M1–M8), success criteria | `docs/SwiftInferProperties PRD v0.4.md` |
| **Current milestone execution plan** | (none — TemplateEngine M1–M8 + TestLifter M1 + v1.0 release prep all closed. Next contributions are TestLifter M2 or v1.1+ trajectory, not yet planned.) |
| v1.0 perf baseline (regression comparison anchor) | `docs/perf-baseline-v1.0.md` |
| Closed milestone plans | `docs/archive/M1 Plan.md` ... `docs/archive/M8 Plan.md`, `docs/archive/TestLifter M1 Plan.md`, `docs/archive/v1.0 Release Plan.md` |
| What v0.3 changed vs v0.1/v0.2 | The `Supersedes:` line points at git history of the SwiftProtocolLaws repo, where v0.1 and v0.2 lived before the split |
| ProtocolLawKit / ProtoLawMacro source of truth | the SwiftProtocolLaws repo, not this one |

## Design decisions baked into v0.3

A future Claude implementing the package should follow these decisions rather than re-litigate them. They live in the PRD; this is a quick map.

- **Conservative inference engine — high precision, low recall.** PRD §3.5. False positives are more damaging than missed opportunities; when in doubt, default to whichever option produces fewer suggestions.
- **All output is opt-in and human-reviewed.** Never auto-applies, never auto-executes, never auto-commits. Even in CI mode (PRD §9), it emits warnings, not failures.
- **The Daikon trap is the failure mode to avoid.** If benchmark calibration shows we're producing too many suggestions, the answer is to raise thresholds, not to add filters on top.
- **Three v1 contributions, one v1.1.** TemplateEngine + RefactorBridge + TestLifter ship in v1. SemanticIndex is deferred to v1.1 with the Constraint Engine, Domain Template Packs, IDE integration, and Semantic Linting bridge listed as the v1.1+ trajectory in PRD §20.
- **Explainability is a first-class output.** Every suggestion ships both "why suggested" and "why this might be wrong." PRD §4.5.
- **Generator inference delegates to SwiftProtocolLaws.** Don't reimplement the priority list — call into the shared `DerivationStrategist`. PRD §11.

## Build & test

- `swift package clean && swift test` (per the global `~/CLAUDE.md`) on session start.
- The skeleton expects `../SwiftProtocolLaws` to exist as a sibling checkout of [Joseph-Cursio/SwiftProtocolLaws](https://github.com/Joseph-Cursio/SwiftProtocolLaws). CI checks both repos out side-by-side; locally, your `~/xcode_projects/` should already have both.
- SwiftLint config lives at `.swiftlint.yml`; `swiftlint lint --quiet` should be silent.
