# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] — 2026-05-07

Closes the PRD §7.8 trio for the v1.x scanner shape: M9 preconditions now cover all four `ParameterizedValue.Kind` cases (M15 adds `Float`/`Double`), and the §7.8 third example covers three of four Option A axes via M13 + M14 with same-target enum exhaustiveness annotation fully wired. Same hard-guarantee + perf-budget posture as v1.1 — §16 guarantees unchanged; §13 budgets re-baselined at [`docs/perf-baseline-v1.2.md`](docs/perf-baseline-v1.2.md).

### TestLifter

- **M13 — General partition surface for equivalence classes (PRD §7.8 third example, scope A axes 1+2+4).** `MarkerPair` lifted to `SwiftInferCore.MarkerTable.swift` + `MarkerSet` added (the combined `MarkerTable` carrier + `Vocabulary.markerPairs` / `markerSets` JSON round-trip is the supporting data-model lift). M13.1 broadens the discover-loop scan from `[Valid/Invalid]` to `MarkerTable.curatedPairs` (5 pairs: `Valid`/`Invalid` + `Success`/`Failure` + `Accept`/`Reject` + `Pass`/`Fail` + `Allowed`/`Forbidden`); per-predicate ranking dedup picks the highest-site-count winner when a predicate fires under multiple pairs. M13.2 ships `NClassEquivalenceClassDetector` + `NClassEquivalenceClassHint` for ≥3-bucket partitions on `XCTAssertEqual(predicate(x), .case)` / `#expect(predicate(x) == .case)` shapes; reuses M11 vetoes + adds `PredicateVetoReason.predicateReturnNotEquatable` (textual proxy for the full Equatable check, no SemanticIndex). M13.3 wires both detectors through `LiftedSuggestionPipeline` + `EquivalenceClassHintKind` sum-type side-map + accept-flow renderer (N-class file naming `EquivalenceClasses_<predicate>_<markerSetName>.swift`); pipes `Vocabulary.markerSets` into `TestLifter.discover` as additive marker-table extension. Two-class `coversDomain` annotation fires syntactically (XCTAssertTrue + XCTAssertFalse, no `!` negation) → renderer surfaces `Exhaustiveness: forAll x: T. p(x) ∨ ¬p(x)`. Multi-predicate equivalence classes (axis 3) deferred — same SemanticIndex-sequencing constraint as M12.
- **M14 — Same-target enum coverage for N-class `coversDomain` (PRD §7.8 third example, axis 4 N-class branch).** `TypeDecl` extended with `enumCaseNames: [String]`, populated by `FunctionScannerVisitor.makeTypeDecl` for primary `enum` decls + extensions that add cases; `MemberBlockInspector.enumCaseNames(in:)` walks `EnumCaseDeclSyntax` and strips associated values + raw-value initializers. `NClassEquivalenceClassDetector.detect(...)` widened to consume `[TypeDecl]`; `computeCoversDomain` unions same-name primary + extension records, runs case-insensitive identifier coverage, sets `hint.coversDomain == true` only when every same-target enum case is matched by a marker (cross-target / unresolved / partial / empty / optional-return / function-typed all conservative-false). The M13.3 renderer's `Exhaustiveness:` comment now surfaces in production for fully-covered N-class corpora. Cross-target enum case enumeration deferred (SemanticIndex territory, sibling to M12 / M13.+).
- **M15 — `Float`/`Double` numerical-bound preconditions (PRD §7.8 first example).** Closes the M9 plan OD #1 deferral. `PreconditionPattern` extended with `positiveDouble` / `nonNegativeDouble` / `negativeDouble` / `doubleRange(low:high:)`. `PreconditionInferrer.detectFloatPattern` replaces the `case .float: return nil` arm; `parseDoubleLiteral` strips underscores, explicitly rejects `0x`/`0X` prefixes (Swift's `Double.init(_:)` natively parses `0x1.0p2` → 4.0, so the prefix check mirrors M9's hex-radix kill posture), `!isFinite` defensive kill, M9 OD #4 most-specific rule preserved (≥2 distinct → `doubleRange`; else sign-bound). End-to-end fixture exercises 5 distinct `Doc(title:, ratio:)` Double sites → `// Inferred precondition: ratio — all observed values are in [1.5, 5.5]` + `Gen.double(in: 1.5...5.5)`. After M15, the M9 inferrer covers all four `ParameterizedValue.Kind` cases the M4.1 scanner produces.

### Documentation

- **Performance baseline re-pinned.** `docs/perf-baseline-v1.2.md` is the canonical regression anchor for v1.2+. Row 4 (memory delta) matches v1.1 to ~0.05% (548.8 MB → 548.5 MB), confirming M13 + M14 + M15 added no persistent allocations. Row 2 (TestLifter parse) effectively flat at +0.2% (1.209s → 1.211s), confirming M13 marker-table broadening + M14 enum-case extraction stayed sub-millisecond per detector. v1.1 baseline retained at `docs/perf-baseline-v1.1.md` for forensic comparison across the M13/M14/M15 trajectory; v0.1.0 baseline retained at `docs/perf-baseline-v0.1.md` for the longer trajectory window.
- **CLAUDE.md repo-state pointer index extended.** M13 / M14 / M15 entries point at their archive plans; "Where to look" perf-baseline pointer updated to `docs/perf-baseline-v1.2.md`.

### Hard guarantees + performance

- All PRD §16 hard guarantees unchanged — M13 / M14 / M15 wrote only to allowlisted `Tests/Generated/SwiftInfer/` paths and never modified existing source.
- All PRD §13 performance budgets hold at v1.2; see `docs/perf-baseline-v1.2.md` for the row-by-row numbers. Row 4 ceiling stays at the post-v1.1.0 800 MB CI calibration.
- PRD §14 + §19 runtime no-network guarantee unchanged; no networking-API touches in the M13–M15 surface.

[1.2.0]: https://github.com/Joseph-Cursio/SwiftInferProperties/releases/tag/v1.2.0

## [1.1.0] — 2026-05-05

Closes the PRD §7.8 expanded-outputs row (preconditions M9 + inferred domains M10 + equivalence classes M11) and ships the TestLifter detector fan-out (M2–M7) + the `convert-counterexample` CLI subcommand (M8). Same hard-guarantee + perf-budget posture as v0.1.0 — §16 guarantees unchanged; §13 budgets re-baselined at [`docs/perf-baseline-v1.1.md`](docs/perf-baseline-v1.1.md).

### TestLifter

- **M2 — Idempotence + commutativity detection.** `AssertAfterDoubleApplyDetector` (idempotence pattern) and `AssertSymmetryDetector` (commutativity pattern) join M1's `AssertAfterTransformDetector` to feed the +20 cross-validation signal across all three M1+M2 templates.
- **M3 — Generator inference + stream entry.** `LiftedSuggestionRecovery` performs type recovery via `FunctionSummary` lookup; promoted lifted suggestions enter the discover stream end-to-end with cross-validation suppression and accept-flow writeouts.
- **M4 — Mock-based generator synthesis.** `MockGeneratorSynthesizer` synthesizes generators for ≥3-site test-corpus types via setup-region scanning (`SetupRegionTypeAnnotationScanner`, `SetupRegionConstructionScanner`); pipeline-side mock-inferred fallback supplements the kit's strategist; M4.2 annotation-fallback recovery tier.
- **M5 — Six-detector fan-out + Codable round-trip.** Adds monotonicity (`AssertOrderingPreservedDetector`), count-invariance (`AssertCountChangeDetector`), and reduce-equivalence (`AssertReduceEquivalenceDetector`) to the M2 trio; Codable round-trip generator rung lights up.
- **M6 — TestLifter workflow operationalization.** `--test-dir` CLI override + walk-up default + `// swiftinfer: skip` honoring + `.swiftinfer/decisions.json` persistence for lifted suggestions.
- **M7 — Counter-signal scanning + non-determinism suppression.** `AsymmetricAssertionDetector` scans for negative-form assertions (`XCTAssertNotEqual`, `XCTAssertFalse`) and applies a `-25` counter-signal to suggestions whose round-trip / commutativity assertions are contradicted; `MockGeneratorSynthesizer` suppresses non-deterministic constructor patterns.
- **M8 — `swift-infer convert-counterexample` subcommand.** Reads a kit-emitted counterexample JSON and writes a regression test stub to a sandboxed path; covers the 10 v1.1 templates.
- **M9 — Inferred preconditions (PRD §7.8 first example).** `PreconditionInferrer` detects `precondition()` / `assert()` / `guard let` patterns in producer functions and surfaces them as `// Inferred precondition:` advisory comments inside mock-inferred generators. Conservative narrow surface (deferred: `Float`/`Double` numerical-bound preconditions per the M9 plan's precision-class concerns).
- **M10 — Inferred domains, round-trip-pair scope (PRD §7.8 second example).** Round-trip suggestions whose reverse-side test corpus uniformly receives forward-side output get a `DomainHint` that overrides the generator with `Gen<T>.map(forward)` plus a `// Inferred domain:` provenance comment. Hard-veto on throws / async / multi-arg / non-generatable producers (comment-only fallback names the veto reason). General consumer-producer chain detection (Option A) deferred to a future v1.x.
- **M11 — Predicate equivalence-class detection (PRD §7.8 third example).** Two-class `Valid`/`Invalid` predicate partitions with both buckets reaching the M4.3 ≥3 threshold + homogeneous predicate + matched polarity surface as `equivalence-class` advisory suggestions; comment-only writeout to `Tests/Generated/SwiftInfer/equivalence-class/EquivalenceClasses_<predicate>.swift` on accept. Adds `Tier.advisory`, `AssertionInvocation.Kind.xctAssertFalse`, and a side-map carrier shape (`InteractiveTriage.Context.equivalenceClassHintsByIdentity`) that recovered the §13 row 4 memory budget after an inline-Optional regression. General partition surface (arbitrary markers, N-class, multi-predicate, cross-class relations) deferred to a future v1.x.

### Tier + scoring

- `Tier.advisory` — new tier value rendered as `[Advisory]`. Distinct from `Strong` / `Likely` / `Possible` so consumers can tell documentation surfaces apart from runnable property suggestions. `init(score:)` never returns `.advisory`; the surfacing pipeline sets it explicitly via `Score(advisorySignals:)`.
- `AssertionInvocation.Kind.xctAssertFalse` — slicer recognizes `XCTAssertFalse(...)` calls as a first-class assertion kind, used by the M11 polarity-homogeneity check (and available to future negative-assertion detectors).

### Kit coordination

- **Kit renamed: SwiftProtocolLaws → SwiftPropertyLaws (v2.0.0).** A `refactor!`-only kit release — no behavioral changes; library products `ProtocolLawKit` / `ProtoLawCore` / `ProtoLawMacro` became `PropertyLawKit` / `PropertyLawCore` / `PropertyLawMacro`. `Package.swift` now references `https://github.com/Joseph-Cursio/SwiftPropertyLaws` from `2.0.0`. Pre-rename v1.9.0 had added `CommutativeMonoid` / `Group` / `Semilattice` for M8.5's writeouts.

### Documentation

- **PRD v1.0 cut.** `docs/SwiftInferProperties PRD v1.0.md` is now the canonical product spec; v0.1–v0.4 retained as historical. The v0.4-era arg-help PRD section references in `SwiftInferCommand.swift` are intentionally left at `PRD v0.4 §X.X` since the section numbering predates v1.0; updating to v1.0 references is a future cleanup pass, not a v1.1 deliverable.
- **CLAUDE.md condensed to a milestone index.** Per-milestone narratives moved fully to `docs/archive/*.md`; the repo-state paragraph is now pointer-only.
- **Performance baseline re-pinned.** `docs/perf-baseline-v1.1.md` is the canonical regression anchor for v1.1+. Two §13 rows moved meaningfully against the v0.1.0 baseline (both inside the §13 25% rule): row 2 (TestLifter parse) +138% with 60% headroom remaining, and row 4 (memory delta) +12% leaving 9% headroom against the 600 MB ceiling.

### Hard guarantees + performance

- All PRD §16 hard guarantees unchanged — M9 / M10 / M11 wrote only to allowlisted `Tests/Generated/SwiftInfer/` paths and never modified existing source.
- All PRD §13 performance budgets hold at v1.1; see `docs/perf-baseline-v1.1.md` for the row-by-row numbers.
- PRD §14 + §19 runtime no-network guarantee unchanged; no networking-API touches in the M2–M11 surface.

[1.1.0]: https://github.com/Joseph-Cursio/SwiftInferProperties/releases/tag/v1.1.0

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
