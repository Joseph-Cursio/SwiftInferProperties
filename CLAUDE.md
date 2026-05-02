# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository state

**M1 + M2 + M3 + M4 + M5 + M6 shipped; v0.4 M7 (RefactorBridge + Option B prompt + monotonicity / invariant-preservation templates) next.** M6 (workflow operationalization per PRD v0.4 §5.8) is complete on `main`. Sub-milestones M6.1–M6.6 landed as individual `feat(M6.x):` commits on top of the M1.1–M1.7 + M2.1–M2.6 + M3.1–M3.6 + M4.1–M4.5 + M5.1–M5.6 series. M6 ships the `Decisions` value type + `.swiftinfer/decisions.json` walk-up read + atomic write (M6.1), the `Baseline` value type + `.swiftinfer/baseline.json` I/O (M6.2), the shared `LiftedTestEmitter` that backs both the M5.2/M5.3 `@CheckProperty` macro arms and the M6.4 interactive accept path (M6.3), `swift-infer discover --interactive` triage mode walking surviving suggestions through `[A/s/n/?]` and writing accepted property-test stubs to `Tests/Generated/SwiftInfer/<TemplateName>/<FunctionName>.swift` (M6.4 — M5.5's `--dry-run` placeholder finally has real meaning here), and `swift-infer drift` plus the `discover --update-baseline` flag emitting CI-annotation-friendly stderr warnings on new Strong-tier suggestions that lack a recorded decision (M6.5). The §5.8 acceptance bar (a–h) — decisions/baseline JSON byte-stable round-trip, lifted-test stub goldens, interactive prompt-loop coverage, dry-run path, drift line shape, §13 perf re-check on the synthetic 50-file corpus *with M6.1 decisions-load active*, and the §16 #1 hard guarantee that `--interactive` accept + `--update-baseline` write only to `Tests/Generated/SwiftInfer/` and `.swiftinfer/` respectively — is met (M6.6). **Cross-validation `+20` from a real TestLifter is still gated** on TestLifter M1 in this repo (no TestLifter target started); M3.5's `crossValidationFromTestLifter` parameter remains dormant. The next milestone is **M7 — RefactorBridge + Option B prompt + algebraic-structure cluster** (PRD v0.4 §5.8): `[A/B/s/n/?]` interactive prompt with the protocol-conformance `B` arm writing to `Tests/Generated/SwiftInferRefactors/`, monotonicity / invariant-preservation templates, and the M6.4 unsupported-template diagnostic ("no stub writeout available for template X in v1") finally going away as the algebraic-structure templates get their own `LiftedTestEmitter` arms.

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
| **Current milestone execution plan (M7 — not yet drafted)** | (to be created at the start of M7) |
| Closed milestone plans | `docs/archive/M1 Plan.md` ... `docs/archive/M6 Plan.md` |
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
