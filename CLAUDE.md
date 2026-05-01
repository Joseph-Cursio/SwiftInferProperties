# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository state

**M1 + M2 + M3 + M4 + M5 shipped; v0.4 M6 (workflow operationalization) next.** M5 (annotation API + `--dry-run` / `--stats-only` modes per PRD v0.4 §5.8) is complete on `main`. Sub-milestones M5.1–M5.6 landed as individual `feat(M5.x):` commits on top of the M1.1–M1.7 + M2.1–M2.6 + M3.1–M3.6 + M4.1–M4.5 series. M5 ships `@Discoverable(group:)` recognize-only attribute detection in the scanner with the +35 `.discoverableAnnotation` signal at the round-trip template (M5.1), the new `SwiftInferMacro` + `SwiftInferMacroImpl` SwiftPM macro target pair shipping `@CheckProperty(.idempotent)` (M5.2) and `@CheckProperty(.roundTrip(pairedWith:))` (M5.3) peer macros that expand into `@Test func` stubs running under `SwiftPropertyBasedBackend` with the M4.3 sampling seed (now widened to 256 bits per PRD v0.4 §16 #6, also done as part of M5.2.a), the `--stats-only` mode on `swift-infer discover` with a per-template / per-tier summary block (M5.4), and the `--dry-run` placeholder flag plumbed for M6's `--interactive` writeout (M5.5). The §5.8 acceptance bar — byte-stable `assertMacroExpansion` goldens for both `.idempotent` and `.roundTrip` arms, integration tests for `@Discoverable(group:)` recognition over fixture corpora (including cross-file pairs), `--stats-only` byte-stable summary, `--dry-run` flag recognition + diagnostic, §13 perf re-check on `swift-collections` + the synthetic 50-file corpus with the new scanner extensions active — is met (M5.6). **Cross-validation `+20` from a real TestLifter is still gated** on TestLifter M1 in this repo (no TestLifter target started). The next milestone is **M6 — Workflow operationalization** (NEW in PRD v0.4 §5.8): `swift-infer discover --interactive` triage mode (PRD §8), the §3.6 step 3 writeout from accepted suggestions to `Tests/Generated/SwiftInfer/`, `swift-infer drift` mode (PRD §9), and `.swiftinfer/decisions.json` infrastructure. This is the milestone where the M5.5 `--dry-run` placeholder finally has writes to suppress.

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
| **Current milestone execution plan (M6 sub-milestones, workflow-operationalization scope)** | `docs/M6 Plan.md` |
| Closed milestone plans | `docs/archive/M1 Plan.md`, `docs/archive/M2 Plan.md`, `docs/archive/M3 Plan.md`, `docs/archive/M4 Plan.md`, `docs/archive/M5 Plan.md` |
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
