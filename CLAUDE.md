# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository state

**M1 + M2 + M3 + M4 shipped; M5 next. PRD bumped to v0.4 between M4.5 and M5 to close audit-surfaced scope gaps (new TemplateEngine M6 "workflow operationalization" inserted; existing v0.3 M6/M7 → v0.4 M7/M8; sampling seed widened to 256 bits in §16 #6; capability ↔ milestone cross-reference table added as new §5.9).** M4 (generator inference via `DerivationStrategist.strategy(for:)` + the M5+ lifted-test sampling-seed plumbing) is complete on `main`. Sub-milestones M4.1–M4.5 landed as individual `feat(M4.x):` / `refactor(M4.x):` commits on top of the M1.1–M1.7 + M2.1–M2.6 + M3.1–M3.6 series. M4 ships the `TypeShapeBuilder` (M4.1) bridging SwiftInfer's `TypeDecl` records to `ProtoLawCore.TypeShape`, the `GeneratorSelection` pass (M4.2) wiring `DerivationStrategist.strategy(for:)` into the discover pipeline between contradiction filter and cross-validation, the §16 #6 `SamplingSeed` derivation surfaced inline on the renderer's `Sampling: not run; lifted test seed: 0x...` line (M4.3), and the `Signal.formattedLine` consolidation that collapsed the five duplicate template-side bullet formatters into one value-type extension (M4.4). The §5.8 acceptance bar — byte-stable goldens for every `DerivationStrategy` arm (`.derivedMemberwise`, `.derivedCaseIterable`, `.derivedRawRepresentable`, `.userGen` → `.registered`, `.todo`), §13 perf re-check on `swift-collections` + the synthetic 50-file corpus *with M4.2's selection pass active*, and a §16 #6 seed-reproducibility test in `HardGuaranteeTests` — is met (M4.5). **Workstream-B interpretation called out at planning time held**: SwiftInfer never claims a property held dynamically; sampling itself stays `.notRun` in v1, and the seed is rendered for the M5+ lifted-test stub to consume. Cross-validation `+20` from a real TestLifter is still gated on TestLifter M1 in SwiftProtocolLaws (no `TestLifter` target in the v1.6 product set). The next milestone is M5 — `@CheckProperty` / `@Discoverable` annotation API (PRD §5.7) + `--dry-run` / `--stats-only` modes; this is also the milestone that finally writes lifted property tests to `Tests/Generated/SwiftInfer/` and consumes the M4.3 sampling seed.

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
| Product scope, milestones (M1–M8), success criteria | `docs/SwiftInferProperties PRD v0.4.md` |
| Closed milestone plans | `docs/archive/M1 Plan.md`, `docs/archive/M2 Plan.md`, `docs/archive/M3 Plan.md`, `docs/archive/M4 Plan.md` |
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
