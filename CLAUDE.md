# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository state

**Current: v1.18.0** — fifteenth calibration cycle and **first cycle organised around a single conceptual axis** (value semantics) rather than a single template-class. Two new mechanism classes ship in one release: **Workstream A** (carrier value-semantics signal — closes the four-cycles-deferred reference-type-carrier counter; new `Signal.Kind.{referenceTypeCarrier (-10), valueSemanticCarrier (+5)}` + `SwiftInferCore.CarrierKindResolver`; consumed by Idempotence + RoundTrip + InversePair + IdentityElement templates) and **Workstream C** (dual-style consistency template — `var c = a; c.<mut>(args); return c == a.<nonMut>(args)` over canonical Swift `add`/`adding`, `sort`/`sorted`, `formUnion`/`union` siblings; high-precision by construction). Mechanism-class taxonomy **8 → 11 classes** (class 11 dual-style consistency is the **first new template family** added since M8.5's kit `Group`+`CommutativeMonoid` writeouts in v1.9). Two notable behavioral shifts on the existing 1618-test baseline: **Round-trip Likely → Strong** on value-semantic struct carriers (70 → 75 crosses Tier.strong threshold ≥75) and **Inverse-pair Possible → Likely** on non-Equatable struct carriers (35 → 40 crosses default-visible boundary). Per-corpus signal-hit data deferred to v1.20 empirical cycle (the four cycle-1..14 corpora are re-captured there alongside the v1.19 workstream-B lifted surface). Test count 1618 → 1680 (+62: 33 carrier-resolver + 29 dual-style). Per-cycle narratives in `docs/archive/*.md` + `docs/calibration-cycle-*-findings.md` + git log; this file is a pointer-only index.

No active milestone plan. Cycle-16 priorities (rotated post-v1.18): (1) **NEW** Workstream B from the v1.18 plan — mutating-method lift admission. `LiftedTransformation` summary type + lift admission in `IdempotenceTemplate`, `IdentityElementPairing` (the "increment by 0" case), `InversePairTemplate` (dual-mutating add/remove pairs), and a new `CompositionTemplate` for the additive composition case. Depends on Workstream A's value-semantic carrier signal (lift is sound only on value-semantic carriers). Doubles the addressable function surface — every `mutating func` in stdlib + domain code becomes evaluable. v1.19 cycle. (2) Math-library forward-function counter on idempotence + round-trip — new curated set `MathForwardFunctions = {exp, log, sin, cos, sqrt, ...}` × `(T) -> T` shape gate (carried forward from cycle-15). (3) Fixed-point-name positive signal on idempotence — `+10` on `normalize`/`canonicalize`/`dedupe`/`simplify` (carried forward; 8 cycles overdue). (4) FP approximate-equality template arm, (5) Math-library op-name gate extension to `rescaledDivide`/`_relaxed*` — all carried forward. (6) **DEMOTED** stride-style label extension (carried forward from cycle-14 demotion). Full list in `docs/calibration-cycle-15-findings.md` and the v1.18 plan workstream B at `docs/archive/v1.18 Calibration Plan.md`. PRD §20 v1.1+ work (SemanticIndex, IDE integration, `swift-infer apply`) deferred until SemanticIndex lands. Kit-side `ValueSemantic` proposal at `docs/ideas/ValueSemantic Kit Proposal.md` M-VS-2/M-VS-3/M-VS-4 deferred to v1.21+ once kit-side `ValueSemantic` protocol ships.

## Shipped

- **TemplateEngine M1–M8**, **TestLifter M1–M16** — full v1 surface; per-milestone plans in `docs/archive/`.
- **Releases v0.1.0, v1.1.0, v1.2.0, v1.3.0** — initial release through TestLifter M16; plans in `docs/archive/v*.md`.
- **Releases v1.4.0–v1.18.0** — calibration cycles 1–15 (cycle 10 was the v1.13 hoist refactor, zero behavior change; cycles 6 and 14 are empirical-only measurement releases — v1.9 and v1.17; cycle 15 = v1.18 ships two mechanism workstreams in one release). Each cycle has a plan in `docs/archive/v1.N Calibration Plan.md`, findings in `docs/calibration-cycle-N-findings.md`, raw data in `docs/calibration-cycle-N-data/` (cycle-15 per-corpus data deferred to v1.20 empirical cycle), and a perf baseline in `docs/perf-baseline-v1.N.md` (v1.17 is a v1.16 carry-forward; v1.18 re-measured).

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
| Current perf baseline | `docs/perf-baseline-v1.18.md` (re-measured; prior baselines retained for forensic comparison) |
| Calibration cycle N findings + data | `docs/calibration-cycle-N-findings.md` + `docs/calibration-cycle-N-data/` (cycles 1–15; cycle 10 = v1.13 hoist, no findings doc; cycle-15 per-corpus data deferred to v1.20 empirical cycle) |
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
