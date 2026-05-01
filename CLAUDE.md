# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository state

**M1 + M2 + M3 shipped; M4 next.** M3 (contradiction detection per PRD §5.6 + the dormant cross-validation seam) is complete on `main`. Sub-milestones M3.1–M3.6 landed as individual `feat(M3.x):` commits on top of the M1.1–M1.7 + M2.1–M2.6 series. M3 ships the `ProtoLawCore` dep wiring (M3.1), `TypeDecl` records emitted from the single-pass scan (M3.2), the textual `EquatableResolver` (M3.3), the `ContradictionDetector` cross-cutting filter for §5.6 contradictions #2 / #3 with stderr diagnostics (M3.4), and the `crossValidationFromTestLifter` parameter as a callable-but-dormant TestLifter seam (M3.5). The §5.8 acceptance bar — byte-stable diagnostic goldens for both contradiction shapes, §13 perf budget on `swift-collections` + the synthetic 50-file corpus *with all five M2 templates active plus the new contradiction pass*, and `EquatableResolver` integration tests against fixture corpora exercising all three classification states — is met (M3.6). Contradictions #1 + #4 stay structurally inert until M7 ships the involutive + binary-op-idempotence templates that would emit the conflicting suggestions. The next milestone is M4 — sampling (PRD §4.3) + generator inference via `DerivationStrategist.strategy(for:)` (PRD §11).

## What this repo is

**SwiftInferProperties** — type-directed property inference for Swift. Surfaces idempotence, round-trip pairs, and algebraic-structure (semigroup / monoid / group / semilattice / ring) candidates from function signatures, cross-function pairs, and existing unit tests. All output is human-reviewed; nothing auto-executes.

The package is a one-way downstream of [SwiftProtocolLaws](https://github.com/Joseph-Cursio/SwiftProtocolLaws):

```
SwiftInferProperties → SwiftProtocolLaws (PropertyBackend, DerivationStrategist) → swift-property-based
```

During pre-1.0 development, `Package.swift` references SwiftProtocolLaws via a local path (`../SwiftProtocolLaws`) so SwiftInfer can iterate against unreleased ProtocolLawKit changes. Swap to a versioned URL dep before tagging 1.0.

## Where to look

| Question | File |
|---|---|
| Product scope, milestones (M1–M9), success criteria | `docs/SwiftInferProperties PRD v0.3.md` |
| **Current milestone execution plan (M4 sub-milestones, generator-inference scope, sampling interpretation)** | `docs/M4 Plan.md` |
| Closed milestone plans | `docs/archive/M1 Plan.md`, `docs/archive/M2 Plan.md`, `docs/archive/M3 Plan.md` |
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
