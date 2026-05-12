# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository state

**Current: v1.45.0** — forty-second calibration cycle and **first cycle of the Phase 1.5 verifiable-fraction expansion arc** (post-completion of the v1.42–v1.44 Phase 1 architectural shift). v1.45 ships **commutativity verify support** (third template after round-trip + idempotence) and a **curated round-trip pair-list expansion** (6 hyperbolic entries), lifting the cycle-27-corpus verifiable-fraction from 6.25% to 21.9% and surfacing the **first measured verify-mode REJECT confirmation**. **Six workstreams shipped**: V1.45.A adds `CommutativityStubEmitter` — single-function `(T, T) -> T` analog with three-carrier dispatch from the start (Complex<Double> two-pass via `Gen<Complex<Double>>.edgeCaseBiased()` with lhs-only edge bias to avoid the point-at-infinity equality collapse; Double two-pass with inlined `doubleWithNaN`; Int single-pass with zero-edge sentinel); V1.45.B adds `CommutativityPairResolver` — single-function two-argument analog of `IdempotencePairResolver`; V1.45.C extends `Verify.runPipeline` dispatch to commutativity + extends `RenderShape` with the `.commutativity` case (renders `f(lhs, rhs)` / `f(rhs, lhs)` value lines and `expected ≈ f(rhs, lhs)`); V1.45.D appends 6 hyperbolic entries (`sinh/asinh`, `cosh/acosh`, `tanh/atanh` bidirectional) to `RoundTripPairResolver.curated` — zero new code, unblocks 2 cycle-27 ACCEPTs (#4, #5); V1.45.E ships 3 always-on subprocess integration tests covering commutativity × each carrier × each outcome class — and surfaced a real bug (Pass 2 of the FP commutativity stubs was re-declaring `defaultGenerator` at top-level, clashing with Pass 1); V1.45.F lands the cycle-42 findings doc — **verifiable-fraction 21.9%** with **first verify-mode REJECT confirmation on `binomial(n: k:)` + `distance(from: to:)`** (both predicted `.defaultFails`; 7/7 in-scope picks show 100% agreement between name-heuristic and verify-mode evidence). The doc supersedes cycle-41's "+27.6pp aggregate ceiling" framing — verify-confirmed REJECTs don't change the aggregate rate; the meaningful measurement is the per-pick agreement-rate signal. **Test count 2220 → 2254 (+34)** across 4 new test files; full `swift test` wall-clock ~131s (was ~65s — nine subprocess-based integration tests now run in parallel; SwiftPM cold-resolve dominates). All v1.42–v1.44 §13 budgets unchanged (discover/index/drift paths untouched). Per-cycle narratives in `docs/archive/*.md` + `docs/calibration-cycle-*-findings.md` + git log; this file is a pointer-only index.

v1.46+ priority is user's call. Top candidates:

1. **v1.46 — associativity verify support** — natural continuation of v1.45's commutativity pattern. Three-value generation (extends the v1.45 two-value `Gen<T>.zip` pattern with one more factor) + `f(f(a, b), c) == f(a, f(b, c))` check. Unlocks 2 more cycle-27 REJECTs (#25 `distance`, #27 `-`). Estimated effort: similar to v1.45.
2. **v1.46+ — `DerivationStrategist` integration at verify-time** — opens the carrier set to `Base.Index`, `_Bucket`, domain types, and user-defined carriers. Bigger architectural lift than template extension; unlocks 3 cycle-27 idempotence REJECTs (`endOfChunk` / `startOfChunk` / `sizeOfChunk` on chunked indices). Candidate for v1.46 if scoped tightly (one new carrier) or v1.47 if scoped broadly.
3. **V1.42.C.5 deferred** — implicit reindex on demand (`IndexCommand`-side refactor; carried from v1.42). UX polish for `verify --suggestion <hash>` when the index is stale.
4. **Higher-order property composition** (PRD §20.2 lookahead) — express "a Group constraint composes Semigroup + identity-element + inverse-pair." Multi-cycle architectural extension built on the v1.36–v1.40 Constraint abstraction.
5. **Backlog items**: cross-type abstraction discovery (v1.35), incremental indexing (v1.33), natural-language query DSL (v1.33), SQLite backend (v1.33).

Full list in `docs/archive/v1.45 Calibration Plan.md` (v1.45 specifics), `docs/calibration-cycle-42-findings.md` (v1.46+ roadmap implications + verifiable-fraction trajectory through v1.48), and the test-execution evidence proposal at `docs/ideas/Edge-Case-Biased Generators Kit Proposal.md` (cross-cycle Phase 1 roadmap).

---

[previous: v1.44.0] — forty-first calibration cycle and **third of 3 cycles delivering the test-execution-evidence architectural shift** (v1.42 step 1; v1.43 step 2; v1.44 step 3). v1.44 extended the verify pipeline to a second template (idempotence non-lifted) and two new carriers (Double, Int beyond v1.42/v1.43's Complex<Double>), then took the first verify-mode calibration measurement on the cycle-27 corpus. Six workstreams: V1.44.A `IdempotenceStubEmitter`; V1.44.B `RoundTripStubEmitter` carrier dispatch via private `CarrierKind` enum (3 carriers + zero-edge sentinel for Int); V1.44.C mirror B for idempotence; V1.44.D `IdempotencePairResolver` + `Verify.runPipeline` template dispatch + template-aware renderer; V1.44.E 3 always-on subprocess integration tests for idempotence × each carrier; V1.44.F cycle-41 findings doc (verifiable-fraction 2/32 = 6.25%; all 8 cycle-27 REJECTs out of scope; planned aggregate-rate-shift didn't materialize). Test count 2178 → 2220 (+42); full `swift test` wall-clock ~65s.

---

[previous: v1.43.0] — fortieth calibration cycle and **second of 3 cycles delivering the test-execution-evidence architectural shift** (v1.42 shipped step 1; v1.44 is step 3). v1.43 layered the **edge-case-biased second pass** on top of v1.42's single-pass round-trip verifier and expanded the user-facing result to the four-outcome two-pass table. Five workstreams: V1.43.A wires `PropertyLawComplex` (the kit's v2.1.0 opt-in product) into the synthesized verifier workdir's `Package.swift`; V1.43.B rewrites `RoundTripStubEmitter` to emit two passes (default finite-domain + `Gen<Complex<Double>>.edgeCaseBiased()`), short-circuiting the edge pass on default fail; V1.43.C/D rewrite `VerifyOutcome` to a 4-case shape (`bothPass` / `edgeCaseAdvisory` / `defaultFails` / `error`) + parser + renderer with the 12-entry curated-label table; V1.43.E.3.b adds the `edgeCaseAdvisory` integration test and fixes a latent V1.43.B bug (`matchEdgeCaseIndex` now uses `Complex.rawStorage`). Test count 2171 → 2178 (+7); full `swift test` wall-clock ~41s.

---

[previous: v1.42.0] — thirty-ninth calibration cycle and **first of 3 cycles delivering the test-execution-evidence architectural shift** (originally raised at v1.25; design + kit-side prerequisite landed earlier this cycle). v1.42 shipped the **minimum-viable verify pipeline**: an opt-in `swift-infer verify --suggestion <id>` subcommand that compiles + runs a synthesized round-trip property test in a throwaway SwiftPM workdir and reports pass / fail / error. Eight workstreams: V1.42.A kit pin bump 2.0.0 → 2.1.0 (`PropertyLawComplex` product at SwiftPropertyLaws commit ba19ab7 / tag v2.1.0); V1.42.B `Verify` subcommand argument surface; V1.42.C.1 `VerifyHarness` for hash-prefix suggestion lookup; V1.42.C.2 `RoundTripStubEmitter` (pure-function source emission, `Complex<Double>` only); V1.42.C.3 `VerifierWorkdir` + `VerifierSubprocess` for SwiftPM workdir synthesis at `<packageRoot>/.swiftinfer/verify-workdir/<hashPrefix>/` (PRD §14 hard-guarantee exemption for `VerifierSubprocess.swift`); V1.42.C.4 `VerifyOutcome` + `VerifyResultParser` + `VerifyResultRenderer` for stdout-marker parsing and ✓/✗/! rendering; V1.42.D two always-on end-to-end integration tests; V1.42.C.6 `Verify.run()` end-to-end with a curated 8-entry round-trip pair list (exp/log, cos/acos, sin/asin, tan/atan; bidirectional). `VerifyError` ships 11 cases; the kit's main `PropertyLawKit` line keeps a zero `swift-numerics` footprint. Test count 2103 → 2171 (+68) across 6 new test files; full `swift test` wall-clock 4s → 37s (dominated by the V1.42.D subprocess tests).

---

[previous: v1.41.0] — thirty-eighth calibration cycle. Closes the v1.35 cycle-32 finding: **`RefactorClusterAnalyzer.classify` now uses a two-layer dominant-pattern rule.** OrderedSet's 29-suggestion cluster reclassifies from the misleading `algebraicStructure` (only 14% algebraic — fired under the pre-v1.41 "any 2 distinct templates wins" rule) to `dual-style-consistency cluster` (dual-style 12 entries is the dominant single template). The curated suggestion text now correctly points at SetAlgebra conformance. Layer 1: algebraic-collective dominance (2+ distinct algebraic templates AND their sum ≥50% of total → algebraicStructure). Layer 2: single-template most-numerous wins among per-template shapes meeting ≥3 threshold (with the pre-v1.41 priority order retained as tie-breaker). Layer 3: ≥4 total → generalCluster catch-all. **End-to-end verified**: only OrderedSet changes classification on OrderedCollections; ComplexModule stays algebraicStructure (12/20 = 60%); the other 6 OC clusters had genuine algebraic dominance (57–67%) and are unchanged. Constraint Engine refactor (v1.36–v1.40) untouched — v1.41 modifies only the cluster-classification layer. No acceptance-rate re-measurement (cycle-27's 72.4% holds). Test count 2097 → 2103 (+6). Per-cycle narratives in `docs/archive/*.md` + `docs/calibration-cycle-*-findings.md` + git log; this file is a pointer-only index.

---

[previous: v1.38.0] — thirty-fifth calibration cycle; first batch-migration cycle. Associativity + InvariantPreservation + DualStyleConsistency migrated (5/10 templates after this cycle). Test count 2080 → 2088 (+8).

---

[previous: v1.37.0] — thirty-fourth calibration cycle; second Constraint Engine migration. MonotonicityTemplate migrated. Templates migrated: 2/10. Test count 2077 → 2080.

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
