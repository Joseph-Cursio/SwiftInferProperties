# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository state

**Current: v1.20.0** — seventeenth calibration cycle and **third empirical-only release** in the loop's history (after cycle 6 = v1.9 and cycle 14 = v1.17). Binary-equivalent to v1.19.0; cycle's deliverable is per-template + per-corpus acceptance-rate data on the post-v1.19 335-surface. Headline: **23/44 = 52.3%** Possible-tier acceptance rate — outcome **A** under the v1.20 plan thresholds (Aggregate ≥ 50%; on trajectory toward §19's ≥70% target). Three-point trajectory now established: 26.7% (cycle 6) → 34.8% (cycle 14) → 52.3% (cycle 17), with the cycle-14 → cycle-17 delta (+17.5pp / 3 mechanism cycles) **larger** than cycle-6 → cycle-14 delta (+8.1pp / 8 mechanism cycles) — the loop is **accelerating, not plateauing**. Cycle 17 is the **first cycle to reverse the descending surface trend** (229 → 335 = +46.3%; cycles 1-13 went 1167 → 229 = -80.4%) — expected and consistent with v1.18 + v1.19's recall-positive direction. Per-mechanism effectiveness: Workstream C (V1.18.C dual-style) is the largest single contributor at **5/5 = 100% by-construction precision** (+6.4pp aggregate); Workstream B (V1.19.B-D lifted) is mixed (2/7 = 28.6%; -0.8pp at current gate — over-broad admission identified on Iterator-shape (4/4 reject) and monotone-bounded (1/1 reject) sub-classes; cycle-18 #1+#2 priorities target directly); Workstream A (V1.18.A carrier-kind) is score-only modulator (~0pp aggregate). Per-cycle narratives in `docs/archive/*.md` + `docs/calibration-cycle-*-findings.md` + git log; this file is a pointer-only index.

No active milestone plan. Cycle-18 priorities (rotated post-v1.20, in expected impact order): (1) **NEW (cycle-17 finding):** Iterator-shape suppression on `idempotence-lifted` — detect `mutating func next()`/`advance()` shapes where carrier conforms to `IteratorProtocol` and veto from the lifted-idempotence path; closes ~24 v1.19 candidates; lifts lifted-idempotence acceptance rate from 33% to projected ~67%. **High-confidence priority** based on direct cycle-17 measurement. (2) **NEW (cycle-17 finding):** `composition-lifted` monotone-bounded suppression — add `until:`/`to:`/`at:` first-parameter-label counter-signal at -25 to `CompositionTemplate.suggest(forLifted:)`; closes the 1 v1.19 candidate. (3) Math-library forward-function counter on idempotence + round-trip (carried forward from v1.18 / cycle-15 / cycle-16; cycle-17 reconfirms — measures `exp`/`log`/`sqrt` non-lifted idempotence at 0% rate). (4) Fixed-point-name positive signal on idempotence (non-lifted path) (carried forward; lifted path already covered). (5) FP approximate-equality template arm (carried forward). (6) Stride-style label extension (carried forward from cycle-14 demotion; not shipped in cycles 15 + 16). (7) Math-library op-name extension. (8) **NEW** `CompositionTemplate` non-numeric monoid extension (carry-forward from v1.19; cycle-17 measurement does not yet motivate). (9) **NEW** Lift admission relaxation from strict to permissive (carry-forward; cycle-17 33% rate does not motivate). (10) **NEW** `Signal.Kind.liftedFromMutation` magnitude re-baselining (carry-forward; cycle-17 measurement does not motivate +10 → +5). Full list in `docs/calibration-cycle-17-findings.md` and the v1.20 plan at `docs/archive/v1.20 Calibration Plan.md`. PRD §20 v1.1+ work (SemanticIndex, IDE integration, `swift-infer apply`) deferred until SemanticIndex lands. Kit-side `ValueSemantic` proposal at `docs/ideas/ValueSemantic Kit Proposal.md` M-VS-2/M-VS-3/M-VS-4 deferred to v1.22+ once kit-side `ValueSemantic` protocol ships.

## Shipped

- **TemplateEngine M1–M8**, **TestLifter M1–M16** — full v1 surface; per-milestone plans in `docs/archive/`.
- **Releases v0.1.0, v1.1.0, v1.2.0, v1.3.0** — initial release through TestLifter M16; plans in `docs/archive/v*.md`.
- **Releases v1.4.0–v1.20.0** — calibration cycles 1–17 (cycle 10 was the v1.13 hoist refactor, zero behavior change; cycles 6 + 14 + 17 are empirical-only measurement releases — v1.9 + v1.17 + v1.20; cycle 15 = v1.18 ships two mechanism workstreams in one release; cycle 16 = v1.19 ships the v1.18-plan Workstream B mutating-method lift; cycle 17 = v1.20 ships the third empirical-only re-measurement). Each cycle has a plan in `docs/archive/v1.N Calibration Plan.md`, findings in `docs/calibration-cycle-N-findings.md`, raw data in `docs/calibration-cycle-N-data/` (cycle-17 captures post-v1.19 surface counts + 46-decision triage), and a perf baseline in `docs/perf-baseline-v1.N.md` (v1.17 is a v1.16 carry-forward; v1.20 is a v1.19 carry-forward; v1.18 + v1.19 re-measured).

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
| Current perf baseline | `docs/perf-baseline-v1.20.md` (v1.19 carry-forward; prior baselines retained for forensic comparison) |
| Calibration cycle N findings + data | `docs/calibration-cycle-N-findings.md` + `docs/calibration-cycle-N-data/` (cycles 1–17; cycle 10 = v1.13 hoist, no findings doc) |
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
