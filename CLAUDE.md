# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository state

**Current: v1.22.0** — nineteenth calibration cycle and the **second consecutive measurement-driven mechanism cycle** (cycle 18 = v1.21 was the first; cycles 15-16 priorities were projected from non-empirical reasoning). Four independently-mergeable workstreams shipped in one release: V1.22.A BucketIterator name extension on V1.21.A's IteratorProtocol carrier veto (closes 3 OC); V1.22.B `RoundTripTemplate` both-sides direction-counter -15 → -25 magnitude bump on V1.12.1 (closes 7 OC + 1 Algo); V1.22.C fixed-point-name positive signal on non-lifted idempotence (**first recall-positive signal in the post-V1.4.3 era**; mechanism class 14 = first new class since v1.19's class 13; +10 weight on `{dedupe, simplify, clamp, truncate, standardize}`; recall-positive infrastructure ready, no surfacing on cycle-1..14 corpora); V1.22.D stride-style label both-sides veto on round-trip + inverse-pair (cycle-14 demotion target shipped after 4-cycle carry-forward; closes 2 Algo `endOfChunk × startOfChunk`). Surface 165 → **152** (-13 = -7.9%) — second consecutive new cumulative-reduction low at **-86.97%** vs cycle-1's 1167-baseline (prior: -85.86% at cycle 18; -80.4% at cycle 13). First cycle to cross the -86% threshold. Mechanism-class taxonomy **13 → 14** (NEW class 14 — first taxonomic shift to recall-positive class since the loop began; all prior 13 classes are suppression-only). Test count 1804 → 1845 (+41). Per-cycle narratives in `docs/archive/*.md` + `docs/calibration-cycle-*-findings.md` + git log; this file is a pointer-only index.

No active milestone plan. Cycle-20 priorities (rotated post-v1.22, in expected impact order): (1) v1.23 = cycle 20 empirical-only re-measurement (provisional aggregate projection 57-65% from cycle-17's 52.3% baseline; fourth measurement point in the loop's history after cycles 6 + 14 + 17). (2) **NEW (cycle-19 finding):** Asymmetric label class mismatch counter on round-trip — closes the 5-10 OC cross-pair noise where one side direction-labeled, one domain-marker-labeled (e.g., `index(after:) × _minimumCapacity(forScale:)` survives V1.22.B at score 20). (3) FP approximate-equality template arm (6-cycle carry-forward; cycle-14 priority #4; required for production CM round-trip property tests on the 7 surviving canonical-inverse anchors). (4) Math-library op-name extension to `rescaledDivide`/`_relaxed*` (4-cycle carry-forward). (5) **NEW** `CompositionTemplate` non-numeric monoid extension (carry-forward from v1.19; cycle-18/19 measurement does not yet motivate). (6) **NEW** Lift admission relaxation (carry-forward; v1.21 + v1.22 precision-positive movement on lifted-idempotence continues to support strict-only). (7) **NEW** `Signal.Kind.liftedFromMutation` magnitude re-baselining (carry-forward; cycle-19 lifted-idempotence projection ~67% does not motivate +10 → +5). Full list in `docs/calibration-cycle-19-findings.md` and the v1.22 plan at `docs/archive/v1.22 Calibration Plan.md`. PRD §20 v1.1+ work (SemanticIndex, IDE integration, `swift-infer apply`) deferred until SemanticIndex lands. Kit-side `ValueSemantic` proposal at `docs/ideas/ValueSemantic Kit Proposal.md` M-VS-2/M-VS-3/M-VS-4 deferred to v1.24+ once kit-side `ValueSemantic` protocol ships.

## Shipped

- **TemplateEngine M1–M8**, **TestLifter M1–M16** — full v1 surface; per-milestone plans in `docs/archive/`.
- **Releases v0.1.0, v1.1.0, v1.2.0, v1.3.0** — initial release through TestLifter M16; plans in `docs/archive/v*.md`.
- **Releases v1.4.0–v1.22.0** — calibration cycles 1–19 (cycle 10 was the v1.13 hoist refactor, zero behavior change; cycles 6 + 14 + 17 are empirical-only measurement releases — v1.9 + v1.17 + v1.20; cycle 15 = v1.18 ships two mechanism workstreams; cycle 16 = v1.19 ships v1.18-plan Workstream B; cycle 17 = v1.20 third empirical-only; cycle 18 = v1.21 ships three workstreams driven by cycle-17 findings; cycle 19 = v1.22 ships four workstreams driven by cycle-18 findings + 4-cycle stride-style carry-forward; introduces class 14 = first recall-positive signal post-V1.4.3). Each cycle has a plan in `docs/archive/v1.N Calibration Plan.md`, findings in `docs/calibration-cycle-N-findings.md`, raw data in `docs/calibration-cycle-N-data/`, and a perf baseline in `docs/perf-baseline-v1.N.md` (v1.17 is a v1.16 carry-forward; v1.20 is a v1.19 carry-forward; v1.18 + v1.19 + v1.21 + v1.22 re-measured).

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
| Current perf baseline | `docs/perf-baseline-v1.22.md` (re-measured; prior baselines retained for forensic comparison) |
| Calibration cycle N findings + data | `docs/calibration-cycle-N-findings.md` + `docs/calibration-cycle-N-data/` (cycles 1–19; cycle 10 = v1.13 hoist, no findings doc) |
| Triage rubrics (cycles 6 + 14) | `docs/cycle-6-triage-rubric.md` (canonical per-template criteria) + `docs/cycle-14-triage-rubric.md` (verbatim carry-forward + post-cycle-6 mechanism context supplement) |
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
