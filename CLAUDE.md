# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository state

**v0.1.0 cut. The v1 surface is feature-complete: TemplateEngine M1–M8, TestLifter M1–M9, plus the §7.8 first-example expanded output (preconditions).** Per-milestone narratives, sub-commit breakdowns, and plan deviations live in `docs/archive/*.md` and the git log; this section is a pointer-only index.

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

Out of v1 scope (post-v0.1.0): §7.8 inferred domains (would-be M10), equivalence-class detection (M11), and PRD §20 v1.1+ trajectory items (SemanticIndex, IDE integration, `swift-infer apply`, `swift-infer metrics`). No active milestone plan is open.

**Kit-side coordination.** `Package.swift` references SwiftProtocolLaws as `from: "1.9.0"` (commit `69e6618`, 2026-05-02). v1.9.0 added `CommutativeMonoid` + `Group` + `Semilattice` for M8.5's writeouts. Out of v1.9.0 scope: kit-side `Ring` (Numeric stays the canonical writeout target per PRD §5.4 row 5), kit-side `CommutativeGroup` (M8.4.b.1 emits separate proposals when both apply), kit-side `Group acting on T` (function-space carrier doesn't fit the per-type protocol shape).

## What this repo is

**SwiftInferProperties** — type-directed property inference for Swift. Surfaces idempotence, round-trip pairs, and algebraic-structure (semigroup / monoid / group / semilattice / ring) candidates from function signatures, cross-function pairs, and existing unit tests. All output is human-reviewed; nothing auto-executes.

The package is a one-way downstream of [SwiftProtocolLaws](https://github.com/Joseph-Cursio/SwiftProtocolLaws):

```
SwiftInferProperties → SwiftProtocolLaws (PropertyBackend, DerivationStrategist) → swift-property-based
```

## Where to look

| Question | File |
|---|---|
| Product scope, milestones, success criteria | `docs/SwiftInferProperties PRD v1.0.md` (canonical; v0.1–v0.4 retained as historical) |
| Current milestone execution plan | None open — see "Repository state" above for what's next |
| v0.1.0 perf baseline (regression comparison anchor) | `docs/perf-baseline-v0.1.md` |
| Closed milestone plans | `docs/archive/*.md` |
| ProtocolLawKit / ProtoLawMacro source of truth | The SwiftProtocolLaws repo, not this one |

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
