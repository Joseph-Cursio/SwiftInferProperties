# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository state

**Current: v1.21.0** — eighteenth calibration cycle and **first mechanism cycle whose priorities are directly informed by cycle-17 measured reject classes** (cycles 15 + 16 priorities were projected from non-empirical value-semantics reasoning). Three independently-mergeable workstreams shipped in one release: V1.21.A IteratorProtocol carrier veto on idempotence-lifted (-22 candidates closed; direct cycle-17 finding); V1.21.B composition-lifted monotone-bounded parameter-label counter (Strong → Likely demote-only on `until:`/`to:`/`at:`/`upTo:`/`before:`/`through:` labels; direct cycle-17 finding); V1.21.C math-library forward-function counter on idempotence + round-trip non-lifted paths (-148 candidates closed; **largest single-cycle mechanism contributor in the loop's history**; 3-cycle carry-forward; preserves the 7 cycle-17 canonical-inverse anchors via `MathForwardFunctions.canonicalInversePairs` allowlist). Surface 335 → **165** (-170 = -50.7%; plan-vs-actual within ±1) — **first descending move since cycle 13** and a new cumulative-reduction low at **-85.86%** vs cycle-1's 1167-baseline (prior low: -80.4% at cycle 13; first cycle to cross the 85% threshold). Restored the descending surface trend that v1.18 + v1.19's recall-positive workstreams had reversed at cycle 17. Mechanism-class taxonomy **13 → 13 classes (no new classes; three extensions of existing classes)** — class 7 (function-name + type-shape composite) extended with carrier-protocol-conformance + math-forward sub-classes; class 8 (parameter-label semantic-intent counter) extended with monotone-bounded labels on V1.19.C composition. Test count 1757 → 1804 (+47). Per-cycle narratives in `docs/archive/*.md` + `docs/calibration-cycle-*-findings.md` + git log; this file is a pointer-only index.

No active milestone plan. Cycle-19 priorities (rotated post-v1.21, in expected impact order): (1) Fixed-point-name positive signal on non-lifted idempotence (3-cycle carry-forward; cycle-18 confirms 1 OC formatter still surfaces). (2) FP approximate-equality template arm (cycle-14 priority #4 carry-forward; required for production CM round-trip property tests on the surviving 7 canonical-inverse anchors). (3) Stride-style label extension (cycle-14 demotion carry-forward; not shipped in cycles 15-18). (4) **NEW (cycle-18 finding):** BucketIterator name extension on V1.21.A — extend `iteratorMethodNames` curated set with `findNext`, `advanceToNextUnoccupiedBucket`, OR extend carrier-name fallback to `*Iterator` suffix; closes ~3 OC `_HashTable.BucketIterator` survivors. (5) **NEW (cycle-18 finding):** OC `index(after:) × index(before:)` direction-pair full-veto extension on V1.12.1 — change firing rule from "either side direction-labeled" (-15) to "both sides direction-labeled" (-25); closes ~12 OC candidates. (6) Math-library op-name gate extension to `rescaledDivide`/`_relaxed*` (carried forward). (7) **NEW** `CompositionTemplate` non-numeric monoid extension (carry-forward from v1.19; cycle-18 measurement does not yet motivate). (8) **NEW** Lift admission relaxation (carry-forward; v1.21 V1.21.A precision-positive movement does not motivate further relaxation). (9) **NEW** `Signal.Kind.liftedFromMutation` magnitude re-baselining (carry-forward; cycle-18 lifted-idempotence projection ~67% does not motivate +10 → +5). (10) v1.23 = cycle 19 empirical-only re-measurement after v1.22 mechanism release. Full list in `docs/calibration-cycle-18-findings.md` and the v1.21 plan at `docs/archive/v1.21 Calibration Plan.md`. PRD §20 v1.1+ work (SemanticIndex, IDE integration, `swift-infer apply`) deferred until SemanticIndex lands. Kit-side `ValueSemantic` proposal at `docs/ideas/ValueSemantic Kit Proposal.md` M-VS-2/M-VS-3/M-VS-4 deferred to v1.22+ once kit-side `ValueSemantic` protocol ships.

## Shipped

- **TemplateEngine M1–M8**, **TestLifter M1–M16** — full v1 surface; per-milestone plans in `docs/archive/`.
- **Releases v0.1.0, v1.1.0, v1.2.0, v1.3.0** — initial release through TestLifter M16; plans in `docs/archive/v*.md`.
- **Releases v1.4.0–v1.21.0** — calibration cycles 1–18 (cycle 10 was the v1.13 hoist refactor, zero behavior change; cycles 6 + 14 + 17 are empirical-only measurement releases — v1.9 + v1.17 + v1.20; cycle 15 = v1.18 ships two mechanism workstreams; cycle 16 = v1.19 ships v1.18-plan Workstream B; cycle 17 = v1.20 third empirical-only; cycle 18 = v1.21 ships three workstreams driven by cycle-17 findings + 3-cycle carry-forward). Each cycle has a plan in `docs/archive/v1.N Calibration Plan.md`, findings in `docs/calibration-cycle-N-findings.md`, raw data in `docs/calibration-cycle-N-data/`, and a perf baseline in `docs/perf-baseline-v1.N.md` (v1.17 is a v1.16 carry-forward; v1.20 is a v1.19 carry-forward; v1.18 + v1.19 + v1.21 re-measured).

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
| Current perf baseline | `docs/perf-baseline-v1.21.md` (re-measured; prior baselines retained for forensic comparison) |
| Calibration cycle N findings + data | `docs/calibration-cycle-N-findings.md` + `docs/calibration-cycle-N-data/` (cycles 1–18; cycle 10 = v1.13 hoist, no findings doc) |
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
