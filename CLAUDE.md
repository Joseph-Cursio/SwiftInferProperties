# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository state

**Current: v1.17.0** — fourteenth calibration cycle and **second empirical-only release in the loop's history** (after v1.9 = cycle 6). v1.17 is binary-equivalent to v1.16.0 except the version-string bump; no Sources/ changes, no test changes, no behavior changes. Headline: aggregate Possible-tier acceptance rate **26.7% → 34.8%** (+8.1pp) on the post-V1.16.1 229-surface — outcome **B** under the v1.17 plan's framing (modest improvement; mechanism cycles are precision-positive but recall is also dropping). **Idempotence stays at 0/10 = 0%** unchanged from cycle 6 — selection-shift evidence, not target-improvement evidence (cycles 7+12+13 cleared all 10 cycle-6 idempotence rejection picks but didn't introduce new accepts; surviving v1.16 idempotence pool is dominated by CM elementary functions, a noise class cycles 7-13 didn't target). Per-corpus: OC **+22.7pp** (cycles 7+12+13 targeted OC heavily — surface dropped 101 → 43); CM −4.3pp drift (no mechanism cycle hit CM directly); **CM is the cycle-15 empirical priority**. Cumulative surface 1167 → 229 (−80.38%) unchanged from v1.16; mechanism-class taxonomy stays at 8 classes. Per-cycle narratives in `docs/archive/*.md` + `docs/calibration-cycle-*-findings.md` + git log; this file is a pointer-only index.

No active milestone plan. Cycle-15 priorities (rotated post-v1.17): (1) **NEW** math-library forward-function counter on idempotence + round-trip — new curated set `MathForwardFunctions = {exp, log, sin, cos, sqrt, ...}` × `(T) -> T` shape gate, targets the dominant cycle-14 rejection class (CM elementary functions). Function-name + type-shape composite class extension. (2) **NEW** fixed-point-name positive signal on idempotence — `+10` on names like `normalize`/`canonicalize`/`dedupe`/`simplify` (cycle-7 priority list option (b), 7 cycles overdue). (3) Reference-type carrier counter, (4) FP approximate-equality template arm, (5) Math-library op-name gate extension to `rescaledDivide`/`_relaxed*` — all carried forward. (6) **DEMOTED** stride-style label extension — was post-v1.16 priority #1; cycle-14 picks #19 + #49 measure the lone Algo `endOfChunk(startingAt:) ↔ startOfChunk(endingAt:)` survivor as correctness-positive (suppressing would lose recall on a true positive). Reframe as usability-paired with chunk-boundary generator support. Full list + open SemanticIndex-blocked trajectory in `docs/calibration-cycle-14-findings.md`. PRD §20 v1.1+ work (SemanticIndex, IDE integration, `swift-infer apply`) deferred until SemanticIndex lands — its arrival lifts most current textual-only approximations (v1.5 coverage, v1.6 op-name gate, v1.7 stdlib bake-in, v1.8 codec gate, v1.10/11/12 direction labels, v1.14/16 SetAlgebra ops, v1.15 domain markers) and would close most cycle-14 unknown verdicts.

## Shipped

- **TemplateEngine M1–M8**, **TestLifter M1–M16** — full v1 surface; per-milestone plans in `docs/archive/`.
- **Releases v0.1.0, v1.1.0, v1.2.0, v1.3.0** — initial release through TestLifter M16; plans in `docs/archive/v*.md`.
- **Releases v1.4.0–v1.17.0** — calibration cycles 1–14 (cycle 10 was the v1.13 hoist refactor, zero behavior change; cycles 6 and 14 are empirical-only measurement releases — v1.9 and v1.17). Each cycle has a plan in `docs/archive/v1.N Calibration Plan.md`, findings in `docs/calibration-cycle-N-findings.md`, raw data in `docs/calibration-cycle-N-data/`, and a perf baseline in `docs/perf-baseline-v1.N.md` (v1.17 is a v1.16 carry-forward).

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
| Current perf baseline | `docs/perf-baseline-v1.17.md` (v1.16 carry-forward; prior baselines retained for forensic comparison) |
| Calibration cycle N findings + data | `docs/calibration-cycle-N-findings.md` + `docs/calibration-cycle-N-data/` (cycles 1–14; cycle 10 = v1.13 hoist, no findings doc) |
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
