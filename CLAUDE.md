# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository state

**Current: v1.15.0** — twelfth calibration cycle (domain-marker counter on three templates simultaneously; first cycle to compress cycles 7-9's three-release direction-counter cadence into a single release; near-miss on the 80% cumulative reduction milestone at 79.86%). Cumulative surface 1167 → 235 (−79.86%) across 12 cycles, 8 mechanism classes (textual type-name counter, cross-type counter, protocol-coverage veto, pair-formation skip-list, stdlib-conformance bake-in, shape-gated veto, function-name + type-shape composite, parameter-label counter family — now with two empirically-validated sub-classes: direction-label spatial-sequence + domain-marker semantic-intent). Three consecutive plan-vs-actual exact matches (v1.12 → v1.14 → v1.15). Per-cycle narratives in `docs/archive/*.md` + `docs/calibration-cycle-*-findings.md` + git log; this file is a pointer-only index.

No active milestone plan. Cycle-13 priorities (SetAlgebra-shape veto extension to round-trip + idempotence — promoted to #1, crosses 80% unambiguously; stride-style label extension; post-v1.15 Possible-tier re-sampling; reference-type carrier counter) + open SemanticIndex-blocked trajectory (multi-predicate equivalence classes, cross-target enum coverage, cross-test data-flow correlation) live in `docs/calibration-cycle-12-findings.md`. PRD §20 v1.1+ work (SemanticIndex, IDE integration, `swift-infer apply`) deferred until SemanticIndex lands — its arrival lifts most current textual-only approximations (v1.5 coverage, v1.6 op-name gate, v1.7 stdlib bake-in, v1.8 codec gate, v1.10/11/12 direction labels, v1.14 SetAlgebra ops, v1.15 domain markers).

## Shipped

- **TemplateEngine M1–M8**, **TestLifter M1–M16** — full v1 surface; per-milestone plans in `docs/archive/`.
- **Releases v0.1.0, v1.1.0, v1.2.0, v1.3.0** — initial release through TestLifter M16; plans in `docs/archive/v*.md`.
- **Releases v1.4.0–v1.15.0** — calibration cycles 1–12 (cycle 10 was the v1.13 hoist refactor, zero behavior change). Each cycle has a plan in `docs/archive/v1.N Calibration Plan.md`, findings in `docs/calibration-cycle-N-findings.md`, raw data in `docs/calibration-cycle-N-data/`, and a perf baseline in `docs/perf-baseline-v1.N.md`.

## Kit-side coordination

`Package.swift` pins **SwiftPropertyLaws** at `from: "2.0.0"`. The kit was renamed from SwiftProtocolLaws at v2.0.0 (refactor-only — `ProtocolLawKit`/`ProtoLawCore`/`ProtoLawMacro` → `PropertyLawKit`/`PropertyLawCore`/`PropertyLawMacro`). Pre-rename v1.9.0 added `CommutativeMonoid` + `Group` + `Semilattice` for M8.5 writeouts. Still deferred kit-side: `Ring` (Numeric stays the canonical writeout target per PRD §5.4 row 5), `CommutativeGroup` (M8.4.b.1 emits separate proposals), `Group acting on T` (function-space carrier doesn't fit per-type protocol shape).

## What this repo is

**SwiftInferProperties** — type-directed property inference for Swift. Surfaces idempotence, round-trip pairs, and algebraic-structure (semigroup / monoid / group / semilattice / ring) candidates from function signatures, cross-function pairs, and existing unit tests. All output is human-reviewed; nothing auto-executes.

One-way downstream of [SwiftPropertyLaws](https://github.com/Joseph-Cursio/SwiftPropertyLaws):

```
SwiftInferProperties → SwiftPropertyLaws (PropertyBackend, DerivationStrategist) → swift-property-based
```

## Where to look

| Question | File |
|---|---|
| Product scope, milestones, success criteria | `docs/SwiftInferProperties PRD v1.0.md` (canonical; v0.1–v0.4 retained as historical) |
| Current milestone plan | None open — see "Repository state" above |
| Current perf baseline | `docs/perf-baseline-v1.15.md` (prior baselines retained for forensic comparison) |
| Calibration cycle N findings + data | `docs/calibration-cycle-N-findings.md` + `docs/calibration-cycle-N-data/` (cycles 1–12; cycle 10 = v1.13 hoist, no findings doc) |
| Cycle-6 triage rubric | `docs/cycle-6-triage-rubric.md` |
| Closed milestone plans | `docs/archive/*.md` |
| PropertyLawKit / PropertyLawMacro source of truth | The SwiftPropertyLaws repo, not this one |

## Design decisions baked into v0.3

These live in the PRD; this is a quick map. Follow them rather than re-litigating.

- **Conservative inference — high precision, low recall.** PRD §3.5. When in doubt, default to fewer suggestions.
- **Opt-in, human-reviewed output.** Never auto-applies/executes/commits. Even CI mode (PRD §9) emits warnings, not failures.
- **Avoid the Daikon trap.** If calibration shows too many suggestions, raise thresholds — don't add filters on top.
- **Three v1 contributions, one v1.1.** TemplateEngine + RefactorBridge + TestLifter ship in v1; SemanticIndex + Constraint Engine + Domain Template Packs + IDE integration + Semantic Linting bridge are PRD §20 v1.1+.
- **Explainability is a first-class output.** Every suggestion ships both "why suggested" and "why this might be wrong." PRD §4.5.
- **Generator inference delegates to SwiftPropertyLaws.** Call `DerivationStrategist`; don't reimplement. PRD §11.

## Build & test

- `swift package clean && swift test` (per global `~/CLAUDE.md`) on session start.
- Skeleton expects `../SwiftPropertyLaws` as a sibling checkout. CI checks both repos out side-by-side.
- SwiftLint config at `.swiftlint.yml`; `swiftlint lint --quiet` should be silent.
