# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository state

**Post-v1.2: tag captures M13 + M14 + M15 (the §7.8 trio is now functionally complete for the v1.x scanner shape — three of four Option A axes shipped on the third example with same-target enum exhaustiveness annotation; the first example's M9 inferrer now covers all four `ParameterizedValue.Kind` cases).** No active milestone plan. Per-milestone narratives, sub-commit breakdowns, and plan deviations live in `docs/archive/*.md` and the git log; this section is a pointer-only index.

Shipped (each line points at its archive plan for the full story):

- **TemplateEngine M1–M7** — eight-template surface (round-trip, idempotence, commutativity, associativity, identity-element, inverse-pair, monotonicity, invariant-preservation, count-invariance, reduce-equivalence) → `docs/archive/M1 Plan.md` … `docs/archive/M7 Plan.md`.
- **TemplateEngine M8** — algebraic-structure composition cluster (CommutativeMonoid / Group / Semilattice / Ring / SetAlgebra) via RefactorBridgeOrchestrator + LiftedConformanceEmitter; closes PRD §5.4 + §5.8 → `docs/archive/M8 Plan.md`.
- **TestLifter M1–M3** — cross-validation `+20` for round-trip, idempotence, commutativity; lifted suggestions enter the discover stream and write to `Tests/Generated/SwiftInfer/` on accept → `docs/archive/TestLifter M1 Plan.md` … `M3 Plan.md`.
- **TestLifter M4** — mock-inferred generators for ≥3-site test-corpus types → `docs/archive/TestLifter M4 Plan.md`.
- **TestLifter M5** — six-detector fan-out (adds monotonicity / count-invariance / reduce-equivalence) + Codable round-trip generator rung → `docs/archive/TestLifter M5 Plan.md`.
- **TestLifter M6** — `--test-dir` CLI override + walk-up default + `// swiftinfer: skip` honoring + decisions.json persistence for lifted suggestions → `docs/archive/TestLifter M6 Plan.md`.
- **TestLifter M7** — counter-signal scanning (`-25` on asymmetric assertions) + non-determinism suppression in mock-inference → `docs/archive/TestLifter M7 Plan.md`.
- **TestLifter M8** — `swift-infer convert-counterexample` CLI subcommand → `docs/archive/TestLifter M8 Plan.md`.
- **TestLifter M9** — inferred preconditions surface as advisory comments in mock-inferred generators (PRD §7.8 first example) → `docs/archive/TestLifter M9 Plan.md`.
- **v0.1.0 release** — version bumped, CHANGELOG added, perf baselines pinned, §13 row 4 budget recalibrated to 600 MB → `docs/archive/v0.1.0 Release Plan.md`, `docs/perf-baseline-v0.1.md`.
- **TestLifter M10 (v1.1)** — round-trip-pair domain narrowing (PRD §7.8 second example, scope B). Round-trip suggestions whose reverse-side test corpus uniformly receives forward-side output get a `DomainHint` that overrides the generator with `Gen<T>.map(forward)` plus a `// Inferred domain:` provenance comment. Hard-veto on throws / async / multi-arg producers (comment-only fallback names the veto reason) → `docs/archive/TestLifter M10 Plan.md`.
- **TestLifter M11 (v1.1)** — predicate equivalence-class detection (PRD §7.8 third example, scope B). `Valid`/`Invalid` method-name partitions with both buckets reaching the M4.3 ≥3 threshold + homogeneous predicate + matched polarity surface as `equivalence-class` advisory suggestions; comment-only writeout to `Tests/Generated/SwiftInfer/equivalence-class/EquivalenceClasses_<predicate>.swift` on accept. Adds `Tier.advisory`, `AssertionInvocation.Kind.xctAssertFalse`, and the side-map carrier shape (hint travels via `InteractiveTriage.Context.equivalenceClassHintsByIdentity` to keep the §13 row 4 memory ceiling). General partition surface (arbitrary markers, N-class, multi-predicate, cross-class relations) deferred → `docs/archive/TestLifter M11 Plan.md`.
- **v1.1.0 release** — CLI version `1.1.0`, CHANGELOG `[1.1.0]` entry covering TestLifter M2–M11 + kit rename + PRD v1.0 cut, perf re-baseline pinned at `docs/perf-baseline-v1.1.md` (now the canonical regression anchor; v0.1.0 retained for forensic comparison), README refresh → `docs/archive/v1.1 Release Plan.md`, `docs/perf-baseline-v1.1.md`.
- **TestLifter M13 (post-v1.1)** — general partition surface for equivalence-class detection (PRD §7.8 third example, scope A axes 1+2+4). Lifts `MarkerPair` to `SwiftInferCore.MarkerTable.swift` + adds `MarkerSet` + the combined `MarkerTable` carrier; `Vocabulary.markerPairs` / `markerSets` JSON round-trip. M13.1 broadens the discover-loop scan from `[Valid/Invalid]` to `MarkerTable.curatedPairs` (5 pairs: `Valid`/`Invalid` + `Success`/`Failure` + `Accept`/`Reject` + `Pass`/`Fail` + `Allowed`/`Forbidden`); per-predicate ranking dedup picks the highest-site-count winner when a predicate fires under multiple pairs. M13.2 ships `NClassEquivalenceClassDetector` + `NClassEquivalenceClassHint` for ≥3-bucket partitions on `XCTAssertEqual(predicate(x), .case)` / `#expect(predicate(x) == .case)` shapes; reuses M11 vetoes + adds `PredicateVetoReason.predicateReturnNotEquatable` (textual proxy for the full Equatable check, no SemanticIndex). M13.3 wires both detectors through `LiftedSuggestionPipeline` + `EquivalenceClassHintKind` sum-type side-map + accept-flow renderer (N-class file naming `EquivalenceClasses_<predicate>_<markerSetName>.swift`); pipes `Vocabulary.markerSets` into `TestLifter.discover` as additive marker-table extension. Two-class `coversDomain` annotation fires syntactically (XCTAssertTrue + XCTAssertFalse, no `!` negation) → renderer surfaces `Exhaustiveness: forAll x: T. p(x) ∨ ¬p(x)` → `docs/archive/TestLifter M13 Plan.md`.
- **TestLifter M14 (post-v1.1)** — closes the M13-deferred N-class `coversDomain` annotation (PRD §7.8 third example, axis 4 N-class branch). M14.0 extends `TypeDecl` with `enumCaseNames: [String]`, populated by `FunctionScannerVisitor.makeTypeDecl` for primary `enum` decls + extensions that add cases; `MemberBlockInspector.enumCaseNames(in:)` walks `EnumCaseDeclSyntax` and strips associated values + raw-value initializers. M14.1 widens `NClassEquivalenceClassDetector.detect(...)` with `typeDecls: [TypeDecl] = []`; `computeCoversDomain` unions same-name primary + extension records, runs case-insensitive identifier coverage, sets `hint.coversDomain == true` only when every same-target enum case is matched by a marker (cross-target / unresolved / partial / empty / optional-return / function-typed all conservative-false). M14.2 threads `artifacts.typeDecls` through `LiftedSuggestionPipeline.equivalenceClassLifted` + `equivalenceClassHintMap` from `Discover+Pipeline`; the M13.3 renderer's `Exhaustiveness:` comment now surfaces in production for fully-covered N-class corpora. **Deferred from M14:** cross-target enum case enumeration (SemanticIndex territory, sibling to M12 / M13.+) → `docs/archive/TestLifter M14 Plan.md`.
- **TestLifter M15 (post-v1.1)** — closes the M9 plan OD #1 deferral on `Float`/`Double` numerical-bound preconditions (PRD §7.8 first example, completing the M4.1-scanner kind coverage). M15.0 extends `PreconditionPattern` with `positiveDouble` / `nonNegativeDouble` / `negativeDouble` / `doubleRange(low:high:)`; renderer + accept-flow stay string-driven (per-kind `describePattern` / `suggestedGenerator` helpers in `LiftedTestEmitter+Generators` + `PreconditionInferrer`). M15.1 replaces `case .float: return nil` with `detectFloatPattern` + `parseDoubleLiteral`; underscore-tolerant, explicit `0x`/`0X` rejection (mirrors M9's hex-radix kill — Swift's `Double.init(_:)` natively parses `0x1.0p2` → 4.0), `!isFinite` defensive kill, M9 OD #4 most-specific rule preserved (≥2 distinct → `doubleRange`; else sign-bound). M15.2 ships an end-to-end fixture in `MockInferredPreconditionIntegrationTests` exercising 5 distinct `Doc(title:, ratio:)` Double sites; `// Inferred precondition: ratio — all observed values are in [1.5, 5.5]` + `Gen.double(in: 1.5...5.5)` surface in production output → `docs/archive/TestLifter M15 Plan.md`.
- **v1.2.0 release** — CLI version `1.2.0`, CHANGELOG `[1.2.0]` entry covering M13 + M14 + M15 + perf re-baseline pin, perf re-baseline pinned at `docs/perf-baseline-v1.2.md` (now the canonical regression anchor; v1.1.0 + v0.1.0 retained for forensic comparison), README refresh → `docs/archive/v1.2 Release Plan.md`, `docs/perf-baseline-v1.2.md`.

No active milestone plan post-v1.2. Open trajectory:
- **PRD §20 v1.1+** — SemanticIndex, IDE integration, `swift-infer apply`, `swift-infer metrics`. Largest single lift is SemanticIndex (originally deferred from v1.0); the constraint-engine + index unlock the IDE integration + `apply`/`metrics` items downstream.
- **General consumer-producer chain detection** — the deferred Option A from M10 (extends §7.8 example 2 beyond round-trip pairs). Narrow follow-up; not §20. SemanticIndex-independent.
- **Multi-predicate equivalence classes** — the deferred Option A axis 3 from M13 (different predicates per bucket where they're not negations of each other). Same SemanticIndex-sequencing constraint as M12.
- **Cross-target enum coverage for N-class `coversDomain`** — the deferred bit of M14 (extends axis 4 beyond same-target enums). Same SemanticIndex-sequencing constraint.

**Kit-side coordination.** `Package.swift` references **SwiftPropertyLaws** as `from: "2.0.0"`. The kit was renamed from SwiftProtocolLaws at v2.0.0 (a `refactor!`-only release — no behavioral changes; library products `ProtocolLawKit` / `ProtoLawCore` / `ProtoLawMacro` became `PropertyLawKit` / `PropertyLawCore` / `PropertyLawMacro`). The pre-rename v1.9.0 had added `CommutativeMonoid` + `Group` + `Semilattice` for M8.5's writeouts (commit `69e6618` pinned that). Still deferred: kit-side `Ring` (Numeric stays the canonical writeout target per PRD §5.4 row 5), kit-side `CommutativeGroup` (M8.4.b.1 emits separate proposals when both apply), kit-side `Group acting on T` (function-space carrier doesn't fit the per-type protocol shape).

## What this repo is

**SwiftInferProperties** — type-directed property inference for Swift. Surfaces idempotence, round-trip pairs, and algebraic-structure (semigroup / monoid / group / semilattice / ring) candidates from function signatures, cross-function pairs, and existing unit tests. All output is human-reviewed; nothing auto-executes.

The package is a one-way downstream of [SwiftPropertyLaws](https://github.com/Joseph-Cursio/SwiftPropertyLaws):

```
SwiftInferProperties → SwiftPropertyLaws (PropertyBackend, DerivationStrategist) → swift-property-based
```

## Where to look

| Question | File |
|---|---|
| Product scope, milestones, success criteria | `docs/SwiftInferProperties PRD v1.0.md` (canonical; v0.1–v0.4 retained as historical) |
| Current milestone execution plan | None open — see "Repository state" above for what's next |
| Current perf baseline (regression comparison anchor) | `docs/perf-baseline-v1.2.md` (v1.1 + v0.1.0 retained at `docs/perf-baseline-v1.1.md` + `docs/perf-baseline-v0.1.md` for forensic comparison) |
| Closed milestone plans | `docs/archive/*.md` |
| PropertyLawKit / PropertyLawMacro source of truth | The SwiftPropertyLaws repo, not this one |

## Design decisions baked into v0.3

A future Claude implementing the package should follow these decisions rather than re-litigate them. They live in the PRD; this is a quick map.

- **Conservative inference engine — high precision, low recall.** PRD §3.5. False positives are more damaging than missed opportunities; when in doubt, default to whichever option produces fewer suggestions.
- **All output is opt-in and human-reviewed.** Never auto-applies, never auto-executes, never auto-commits. Even in CI mode (PRD §9), it emits warnings, not failures.
- **The Daikon trap is the failure mode to avoid.** If benchmark calibration shows we're producing too many suggestions, the answer is to raise thresholds, not to add filters on top.
- **Three v1 contributions, one v1.1.** TemplateEngine + RefactorBridge + TestLifter ship in v1. SemanticIndex is deferred to v1.1 with the Constraint Engine, Domain Template Packs, IDE integration, and Semantic Linting bridge listed as the v1.1+ trajectory in PRD §20.
- **Explainability is a first-class output.** Every suggestion ships both "why suggested" and "why this might be wrong." PRD §4.5.
- **Generator inference delegates to SwiftPropertyLaws.** Don't reimplement the priority list — call into the shared `DerivationStrategist`. PRD §11.

## Build & test

- `swift package clean && swift test` (per the global `~/CLAUDE.md`) on session start.
- The skeleton expects `../SwiftPropertyLaws` to exist as a sibling checkout of [Joseph-Cursio/SwiftPropertyLaws](https://github.com/Joseph-Cursio/SwiftPropertyLaws). CI checks both repos out side-by-side; locally, your `~/xcode_projects/` should already have both.
- SwiftLint config lives at `.swiftlint.yml`; `swiftlint lint --quiet` should be silent.
