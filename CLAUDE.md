# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository state

**Current: v1.37.0** — thirty-fourth calibration cycle; **second Constraint Engine migration** (PRD §20.2). `MonotonicityTemplate` migrated via the V1.36.D mechanical pattern: `suggest(for:vocabulary:)` is now a 4-line `ConstraintRunner.suggest` wrapper; new `makeConstraint(vocabulary:)` factory captures runtime inputs into `@Sendable` closures; `accumulatedSignals(for:vocabulary:)` + constant `makeCaveats()` helpers extracted. **Behavior preserved bit-for-bit** — all 32 pre-existing MonotonicityTemplate tests pass without modification + 3 new equivalence tests on a 7-fixture corpus. **Templates migrated: 2 / 10.** The migration pattern is now validated against two representative unary-summary shapes with different runtime-input cardinalities (Commutativity: 2 inputs incl. inheritance index; Monotonicity: 1 input + constant caveats) — strongly suggests v1.38+ batch migration is safe. No acceptance-rate re-measurement (architectural refactor; per-template inference precision unchanged by construction). Test count 2077 → 2080 (+3). Per-cycle narratives in `docs/archive/*.md` + `docs/calibration-cycle-*-findings.md` + git log; this file is a pointer-only index.

No active milestone plan. **Cycle-35 priority**: **v1.38 batch-migrate the next 3 simplest templates** — Associativity (nearly identical to Commutativity), InvariantPreservation (simplest of all; single-arg suggest), DualStyleConsistency (similar to Monotonicity). Per-cycle pacing remains an option. Remaining after v1.38 (5 templates): round-trip, idempotence (non-lifted + lifted), inverse-pair (non-lifted + lifted), identity-element (non-lifted + lifted), composition — likely v1.39 + v1.40 to complete. v1.38+ alternative paths: dominant-pattern cluster-classification refinement (v1.35), cross-type abstraction discovery (v1.35), incremental indexing (v1.33), SQLite backend (v1.33). Full list in `docs/calibration-cycle-34-findings.md` and the v1.37 plan at `docs/archive/v1.37 Calibration Plan.md`.

---

[previous: v1.36.0] — thirty-third calibration cycle; Constraint Engine foundation. Introduced `Constraint<Subject>` + `ConstraintRunner` + migrated `CommutativityTemplate` as proof-of-concept. Templates migrated: 1/10. Test count 2059 → 2077 (+18).

---

[previous: v1.35.0] — thirty-second calibration cycle; ships carrier-aware refactor suggestions via `swift-infer suggest-refactors`. 5-shape ClusterShape taxonomy. End-to-end verified on ComplexModule (1 cluster) and OrderedCollections (8 clusters across 6 distinct carrier types). Test count 2027 → 2059 (+32).

---

[previous: v1.34.0] — thirty-first calibration cycle; **focused follow-up release** closing the v1.33-deferred SemanticIndex `typeName` field. Three workstreams: V1.34.A `carrier: String?` on `Suggestion`, V1.34.B threaded through 16 construction sites, V1.34.C consumed in `IndexCommand.buildEntry`. End-to-end `query --type Foo` works. Backward-compatible; per-template inference precision unchanged.

---

[previous: v1.33.0] — thirtieth calibration cycle; **third design-completion release**. PRD §20.1 SemanticIndex: JSON-backed persistent index at `.swiftinfer/index.json` + two CLI subcommands (`swift-infer index`, `swift-infer query`). 11-column schema. Storage-format decision: JSON-first; SQLite is a non-breaking later swap. Test count 1994 → 2027 (+33).

---

[previous: v1.32.0] — twenty-ninth calibration cycle; **second design-completion release**. PRD §20.3 Domain Template Packs: monolithic 10-template registry split into 5 named packs (numeric, serialization, collections, algebraic, concurrency) with non-exclusive membership. `--packs` CLI flag + config TOML. Backward-compatible (nil filter = monolithic default). Test count 1959 → 1994 (+35).

---

[previous: v1.31.0] — twenty-eighth calibration cycle; **first design-completion release**. Closed the 13-cycle longest-running carry-forward FP approximate-equality template arm. Three workstreams: V1.31.A `FloatingPointEquatableTypes` curated set + detector, V1.31.B `LiftedTestEmitter.EqualityKind` enum, V1.31.C dispatch wiring. Mechanism-class taxonomy 15 → 16 (class 16 = emit-time equality-form dispatch; first emit-side mechanism class).

---

[previous: v1.30.0] — twenty-seventh calibration cycle; seventh empirical-only release. Headline: 21/29 = 72.4% — **§19 ≥70% TARGET REACHED** after 27 calibration cycles. Seven-point trajectory: 26.7% → 34.8% → 52.3% → 48.8% → 67.6% → 63.6% → 72.4%. Cycle-26's mechanism-precision projection (72.4%) matched cycle-27's measurement exactly. Dual-style-consistency 5-cycle 100% rate-stability.

---

[previous: v1.29.0] — twenty-sixth calibration cycle; **fifth consecutive measurement-driven mechanism release** closing cycle-25 findings (V1.29.A inverse-pair asymmetric full-veto, V1.29.B identity-element algebraic-family-mismatch veto, V1.29.C composition-lifted monotone-bounded full-veto). Surface 113 → 109 (-4; exact plan-vs-actual match). Cumulative reduction -90.66%. Mechanism-class taxonomy 14 → 15.

---

[previous: v1.28.0] — twenty-fifth calibration cycle and **sixth empirical-only release**; binary-equivalent to v1.27.0. Headline: 21/33 = 63.6% Possible-tier acceptance rate — Outcome B (60-69% plateau range); -4.0pp from cycle-23's 67.6%. §19 ≥70% target NOT reached within 25 cycles. Six-point trajectory: 26.7% → 34.8% → 52.3% → 48.8% → 67.6% → 63.6% — first plateau confirmation in the loop's history, bracketing the true rate at 63-68%. Two cycle-25 mechanism findings closed by v1.29: (1) V1.27.B closure gap on asymmetric inverse-pair (now V1.29.A); (2) IdentityElementTemplate curated-constant match (now V1.29.B).

---

[previous: v1.27.0] — twenty-fourth calibration cycle; measurement-driven mechanism release closing 2 cycle-23 findings. Two workstreams: V1.27.A Sequence-conformance fallback on V1.21.A IteratorProtocol veto (class 7 extension; infrastructure for future Sequence-conforming carriers); V1.27.B name-prefix-gated full-veto on V1.11.1 inverse-pair direction-counter (class 6 extension; mirrors V1.22.B + V1.25.A patterns). Surface 114 → 113 (-1; plan-vs-actual -1 vs -4). Cumulative reduction -90.32% vs cycle-1's 1167-baseline. Test count 1893 → 1905 (+12).

---

[previous: v1.26.0] — twenty-third calibration cycle and **fifth empirical-only release** (after cycles 6 = 26.7%, 14 = 34.8%, 17 = 52.3%, 20 = 48.8%). v1.26 binary-equivalent to v1.25.0. **Headline: 25/37 = 67.6% Possible-tier acceptance rate — Outcome A**; +18.8pp from cycle-20's 48.8% (**largest single-cycle aggregate jump in the loop's history**). **§19 ≥70% target now within +2.4pp** — sample-noise band on n=40. Five-point trajectory: **26.7% → 34.8% → 52.3% → 48.8% → 67.6%**. Cycle-20's non-monotonic step (-3.5pp) validated as calibration-trade-off + sample-shift; cycle-23 measurement shows the v1.25 surface composition has materially higher per-template accept rates (round-trip 85.7%, dual-style-consistency 100% over 3 measurement points, idempotence-lifted 66.7%). Drivers: cycles 21+22 mechanism work closed -38 cross-product/direction-op/asymmetric/non-deterministic/capacity-formatter/index-advance rejects with high precision-positive density. V1.18.C dual-style 100% rate-stability across 3 consecutive measurement points = largest mechanism-class precision contribution in loop history. Per-cycle narratives in `docs/archive/*.md` + `docs/calibration-cycle-*-findings.md` + git log; this file is a pointer-only index.

No active milestone plan. Cycle-24 priorities (rotated post-v1.26): (1) FP approximate-equality template arm (**10-cycle carry-forward**; cycle-14 priority #4; correctness-emission work). (2) **NEW (cycle-23 finding):** Algo idempotence-lifted Iterator-like survivors veto — extend V1.21.A's Iterator detection to catch 2 Algo carriers without explicit IteratorProtocol conformance. (3) **NEW (cycle-23 finding):** OC bucket/word direction-pair veto on inverse-pair template — extend V1.25.A's name-prefix gate to inverse-pair; closes 2 OC. (4) Math-library `_relaxed*` (defer indefinitely; ACCEPT-class). (5-7) v1.19 carry-forwards (defer). §19 ≥70% within sample-noise band — one more mechanism cycle reaches the target. Full list in `docs/calibration-cycle-23-findings.md`. PRD §20 v1.1+ work deferred. Kit-side `ValueSemantic` proposal M-VS-2/M-VS-3/M-VS-4 deferred to v1.28+.

---

[previous: v1.25.0] — twenty-second calibration cycle and **fourth consecutive measurement-driven mechanism cycle** (cycles 18 + 19 + 21 + 22 = v1.21 + v1.22 + v1.24 + v1.25). Single-workstream cycle closing the cycle-21 finding: V1.25.A extends V1.10.1's idempotence direction-counter from -15 to -25 (full veto) when function name starts with `index`/`bucket`/`word` AND parameter is direction-labeled. Closes 14 OC + 2 Algo direction-op idempotence rejects = -16 total. Mirrors V1.22.B's both-sides direction full-veto pattern on round-trip with name-prefix gate. Surface 130 → **114** (-12.3%). **First cycle to cross -90% cumulative reduction** (-90.23% vs cycle-1's 1167-baseline; prior: -88.86% at cycle 21). Idempotence non-lifted drops 19 → 3 (**-84%, single largest per-template percentage reduction in the loop's history**). Mechanism-class taxonomy 14 → 14 (no new classes; one extension of class 6). Test count 1884 → 1893 (+9). Per-cycle narratives in `docs/archive/*.md` + `docs/calibration-cycle-*-findings.md` + git log; this file is a pointer-only index.

No active milestone plan. Cycle-23 priorities (rotated post-v1.25, in expected impact order): (1) **v1.26 = cycle 23 empirical-only re-measurement** — fifth measurement point in the loop's history (after cycles 6 + 14 + 17 + 20). Provisional aggregate projection: 55-65% from cycle-20's 48.8% baseline + cycles 21+22's -38 reject closures. (2) FP approximate-equality template arm (9-cycle carry-forward; correctness-emission work). (3) Math-library `_relaxed*` extension (7-cycle carry-forward; cycle-20 ACCEPT; extension unclear). (4-6) v1.19 carry-forwards (CompositionTemplate non-numeric monoid; lift admission relaxation; `liftedFromMutation` magnitude). Full list in `docs/calibration-cycle-22-findings.md` and the v1.25 plan at `docs/archive/v1.25 Calibration Plan.md`. §19 ≥70% target reachability on-track. PRD §20 v1.1+ work deferred until SemanticIndex lands. Kit-side `ValueSemantic` proposal M-VS-2/M-VS-3/M-VS-4 deferred to v1.27+.

---

[previous: v1.24.0] — twenty-first calibration cycle and the **third consecutive measurement-driven mechanism cycle** (cycle 18 = v1.21 closed cycle-17 findings; cycle 19 = v1.22 closed cycle-18 findings; cycle 21 = v1.24 closes cycle-19 + cycle-20 findings). Four independently-mergeable workstreams: V1.24.A asymmetric label class mismatch counter on round-trip (closes 6 OC cycle-19/20 cross-pair rejects); V1.24.B explicit non-idempotent mutator-name veto on idempotence-lifted (closes 9 OC reverse/removeFirst/removeLast/pop*/drop* variants; generalizes V1.21.A's class 7 sub-class to any value-semantic carrier); V1.24.C non-deterministic shuffle veto extension (closes 3 OC shuffle variants via name-fallback); V1.24.D capacity/formatter shape-disambiguation veto on idempotence non-lifted (closes 4 OC `_description`/`_minimumCapacity(forScale:)`-shape picks). Surface 152 → **130** (-22 = -14.5%; plan-vs-actual within projection -21 to -32). New cumulative-reduction low at **-88.86%** vs cycle-1's 1167-baseline (prior: -86.97% at cycle 19). First cycle to cross the -88% threshold. Mechanism-class taxonomy **14 → 14** (no new classes; 4 extensions of existing classes 6 + 7). Test count 1845 → 1884 (+39). Per-cycle narratives in `docs/archive/*.md` + `docs/calibration-cycle-*-findings.md` + git log; this file is a pointer-only index.

No active milestone plan. Cycle-22 priorities (rotated post-v1.24, in expected impact order): (1) v1.25 = cycle 22 — empirical-only re-measurement OR mechanism cycle (loop choice). Provisional aggregate projection: 53-60% from cycle-20's 48.8% baseline + cycle-21's removal of 22 reject picks. (2) **NEW (cycle-21 finding):** `index(after:)` / `index(before:)` direction-op idempotence non-lifted veto — the residual 19-pick idempotence non-lifted pool is dominated by 13+ OC direction-op rejects. Mechanism: extend V1.10.1's direction-label counter from -15 to -25 (full veto) on `index*`/`bucket*`/`word*` names + direction-labeled. Magnitude: closes ~13 OC candidates. (3) FP approximate-equality template arm (8-cycle carry-forward; correctness-emission work). (4) Math-library `_relaxed*` extension (6-cycle carry-forward; cycle-20 measured ACCEPT — extension target unclear; defer indefinitely). (5-7) v1.19 carry-forwards (CompositionTemplate non-numeric monoid; lift admission relaxation; `liftedFromMutation` magnitude re-baselining — none motivated by cycle-20/21 measurements). §19 ≥70% target reachability remains on-track: cycle-22 projection 53-58%; two more mechanism cycles at v1.24 magnitude reach the target. Full list in `docs/calibration-cycle-21-findings.md` and the v1.24 plan at `docs/archive/v1.24 Calibration Plan.md`. PRD §20 v1.1+ work (SemanticIndex, IDE integration, `swift-infer apply`) deferred until SemanticIndex lands. Kit-side `ValueSemantic` proposal at `docs/ideas/ValueSemantic Kit Proposal.md` M-VS-2/M-VS-3/M-VS-4 deferred to v1.26+ once kit-side `ValueSemantic` protocol ships.

## Shipped

- **TemplateEngine M1–M8**, **TestLifter M1–M16** — full v1 surface; per-milestone plans in `docs/archive/`.
- **Releases v0.1.0, v1.1.0, v1.2.0, v1.3.0** — initial release through TestLifter M16; plans in `docs/archive/v*.md`.
- **Releases v1.4.0–v1.24.0** — calibration cycles 1–21 (cycle 10 was the v1.13 hoist refactor, zero behavior change; cycles 6 + 14 + 17 + 20 are empirical-only measurement releases — v1.9 + v1.17 + v1.20 + v1.23; cycle 15 = v1.18 two workstreams; cycle 16 = v1.19 lift admission; cycle 17 = v1.20 third empirical-only; cycle 18 = v1.21 closes cycle-17 findings; cycle 19 = v1.22 closes cycle-18 findings + introduces class 14 = first recall-positive signal post-V1.4.3; cycle 20 = v1.23 fourth empirical re-measurement (first non-monotonic move at 48.8%); cycle 21 = v1.24 closes cycle-19 + cycle-20 findings with 4 workstreams; new cumulative-reduction low at -88.86%). Each cycle has a plan in `docs/archive/v1.N Calibration Plan.md`, findings in `docs/calibration-cycle-N-findings.md`, raw data in `docs/calibration-cycle-N-data/`, and a perf baseline in `docs/perf-baseline-v1.N.md` (v1.17 is a v1.16 carry-forward; v1.20 is a v1.19 carry-forward; v1.23 is a v1.22 carry-forward; v1.18 + v1.19 + v1.21 + v1.22 + v1.24 re-measured).

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
| Current perf baseline | `docs/perf-baseline-v1.24.md` (re-measured; prior baselines retained for forensic comparison) |
| Calibration cycle N findings + data | `docs/calibration-cycle-N-findings.md` + `docs/calibration-cycle-N-data/` (cycles 1–21; cycle 10 = v1.13 hoist, no findings doc) |
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
