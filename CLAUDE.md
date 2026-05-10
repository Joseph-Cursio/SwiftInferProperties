# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository state

**Current: v1.19.0** — sixteenth calibration cycle and **single-workstream follow-on to v1.18** that ships the largest behavioral change since M8.5: re-admitting the entire `mutating func` surface to the algebraic-property scoring pipeline that pre-v1.19 gated on `!summary.isMutating` at every template entry point. Workstream B from the v1.18 plan §2 ships in four focused commits: V1.19.A `LiftedTransformation` summary type + `Signal.Kind.liftedFromMutation` (+10) with strict admission gate (`isMutating && containingType != nil && carrierKind == .valueSemantic`); V1.19.B `IdempotenceTemplate` lift admission (no-param + x-curried shapes); V1.19.C new `CompositionTemplate` (additive-action composition `op(op(s, a), b) == op(s, a + b)` over the curated additive-monoid set — the **second new template family added since M8.5**, after v1.18.C's dual-style consistency) + `IdentityElementTemplate` lift admission via new `LiftedIdentityElementPairing` (the "increment by 0" canonical case); V1.19.D `InversePairTemplate` lift admission via new `InverseLiftedPairing` (curated state-mutation pairs `add`/`remove`, `insert`/`remove`, `push`/`pop`, `attach`/`detach`, `subscribe`/`unsubscribe`, etc.). Mechanism-class taxonomy **11 → 13 classes** (class 12 lift admission via value-semantic gate; class 13 composition-template additive-monoid scoring). Workstream B is **purely additive** — no existing non-lifted suggestion shifts tier (contrast with v1.18.A's Likely→Strong + Possible→Likely shifts). Per-corpus lifted-surface data deferred to v1.20 empirical cycle alongside the v1.18 carry-forwards. Test count 1680 → 1757 (+77: 19 LiftedTransformation + 16 Idempotence-lifted + 12 Composition + 12 IdentityElement-lifted + 18 InverseLifted). Per-cycle narratives in `docs/archive/*.md` + `docs/calibration-cycle-*-findings.md` + git log; this file is a pointer-only index.

No active milestone plan. Cycle-17 priorities (rotated post-v1.19): (1) v1.20 is the empirical-only re-measurement cycle (no Sources/ changes; sample the four cycle-1..14 corpora on the cumulative v1.18 + v1.19 surface; report aggregate acceptance-rate movement vs cycle-6 (26.7%) and cycle-14 (34.8%)). (2) Math-library forward-function counter on idempotence + round-trip — new curated set `MathForwardFunctions = {exp, log, sin, cos, sqrt, ...}` × `(T) -> T` shape gate (carried forward from cycle-15 / cycle-16). (3) Fixed-point-name positive signal on idempotence on the **non-lifted path** — `+10` on `normalize`/`canonicalize`/`dedupe`/`simplify` (carried forward; 9 cycles overdue; V1.19.B already covers it on the lifted path via the curated verb signal). (4) FP approximate-equality template arm, (5) Math-library op-name gate extension to `rescaledDivide`/`_relaxed*` — all carried forward. (6) **NEW** `CompositionTemplate` non-numeric monoid-shaped extension (carry-forward from v1.19; promote to v1.21+ after the v1.20 numeric-only acceptance rate is measured). (7) **NEW** Lift admission relaxation from strict to permissive (carry-forward from v1.19 plan open decision #2; revisit at v1.21 if recall is too low). (8) **NEW** `Signal.Kind.liftedFromMutation` magnitude re-baselining (carry-forward from v1.19 plan open decision #5; revisit at v1.21 if +10 over-promotes lifted suggestions). Full list in `docs/calibration-cycle-16-findings.md` and the v1.19 plan at `docs/archive/v1.19 Calibration Plan.md`. PRD §20 v1.1+ work (SemanticIndex, IDE integration, `swift-infer apply`) deferred until SemanticIndex lands. Kit-side `ValueSemantic` proposal at `docs/ideas/ValueSemantic Kit Proposal.md` M-VS-2/M-VS-3/M-VS-4 deferred to v1.21+ once kit-side `ValueSemantic` protocol ships.

## Shipped

- **TemplateEngine M1–M8**, **TestLifter M1–M16** — full v1 surface; per-milestone plans in `docs/archive/`.
- **Releases v0.1.0, v1.1.0, v1.2.0, v1.3.0** — initial release through TestLifter M16; plans in `docs/archive/v*.md`.
- **Releases v1.4.0–v1.19.0** — calibration cycles 1–16 (cycle 10 was the v1.13 hoist refactor, zero behavior change; cycles 6 and 14 are empirical-only measurement releases — v1.9 and v1.17; cycle 15 = v1.18 ships two mechanism workstreams in one release; cycle 16 = v1.19 ships the v1.18-plan Workstream B mutating-method lift). Each cycle has a plan in `docs/archive/v1.N Calibration Plan.md`, findings in `docs/calibration-cycle-N-findings.md`, raw data in `docs/calibration-cycle-N-data/` (cycle-15 + cycle-16 per-corpus data deferred to v1.20 empirical cycle), and a perf baseline in `docs/perf-baseline-v1.N.md` (v1.17 is a v1.16 carry-forward; v1.18 + v1.19 re-measured).

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
| Current perf baseline | `docs/perf-baseline-v1.19.md` (re-measured; prior baselines retained for forensic comparison) |
| Calibration cycle N findings + data | `docs/calibration-cycle-N-findings.md` + `docs/calibration-cycle-N-data/` (cycles 1–16; cycle 10 = v1.13 hoist, no findings doc; cycle-15 + cycle-16 per-corpus data deferred to v1.20 empirical cycle) |
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
