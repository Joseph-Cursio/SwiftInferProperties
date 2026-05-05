# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository state

**v1.1.0 cut (the §7.8 expanded-outputs row is fully closed — preconditions M9 + inferred domains M10 + equivalence-class detection M11). No active milestone plan.** Per-milestone narratives, sub-commit breakdowns, and plan deviations live in `docs/archive/*.md` and the git log; this section is a pointer-only index.

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

No active milestone plan at the v1.1 cut. Open trajectory:
- **PRD §20 v1.1+** — SemanticIndex, IDE integration, `swift-infer apply`, `swift-infer metrics`. Largest single lift is SemanticIndex (originally deferred from v1.0); the constraint-engine + index unlock the IDE integration + `apply`/`metrics` items downstream.
- **General consumer-producer chain detection** — the deferred Option A from M10 (extends §7.8 example 2 beyond round-trip pairs). Narrow follow-up; not §20.
- **General partition surface** — the deferred Option A from M11 (extends §7.8 example 3 beyond `Valid`/`Invalid` to arbitrary marker labels, N-class, multi-predicate, cross-class relations). Narrow follow-up; not §20.
- **`Float`/`Double` numerical-bound preconditions** — deferred at M9 per the precision-class concerns. Post-§7.8-trio work.

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
| Current perf baseline (regression comparison anchor) | `docs/perf-baseline-v1.1.md` (v0.1.0 retained at `docs/perf-baseline-v0.1.md` for forensic comparison) |
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
