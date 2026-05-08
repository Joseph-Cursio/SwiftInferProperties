# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.9.0] — 2026-05-08

The sixth calibration cycle. **Empirical-only release** — no Sources/ changes, no test changes, no behavior changes. The headline deliverable is the first measured Possible-tier acceptance rate from a 50-decision single-runner triage of the 349-surface: **26.7%** (12 accept / 33 reject / 5 unknown). v1.9 is binary-equivalent to v1.8.0 except the version-string bump; the §13 measurements carry forward unchanged. Same hard-guarantee posture as v1.8 — §16 guarantees unchanged; §13 budgets unchanged; §14 privacy unchanged. Five prior cycles operated on conjectural per-template false-positive rates; cycle 6 is the empirical baseline they all referenced as "future work."

### Calibration cycle 6 — empirical Possible-tier triage

- **Triage rubric (V1.9.1).** New `docs/cycle-6-triage-rubric.md` defines accept/reject/unknown criteria per template (round-trip / idempotence / commutativity / associativity / inverse-pair / monotonicity / identity-element). Acceptance-rate computation: `accept / (accept + reject)` excludes `unknown` from the denominator (matches PRD §19's implicit assumption that triaged decisions are made; uncertainty rate tracked as a separate quality metric). Single-runner triage caveats explicit (one rater, public-API + commit-history evidence only, no test execution, no internal-implementation reading, no multi-rater consensus). Decisions JSON schema mirrors `.swiftinfer/decisions.json` shape so cycle-6 data is in principle replayable against the v1.8 binary.
- **50-decision stratified sample (V1.9.2).** New `docs/calibration-cycle-6-data/sample-manifest.md` lists 50 picks stratified by template × corpus (16 round-trip / 12 idempotence / 5 commutativity / 5 associativity / 6 monotonicity / 5 inverse-pair / 1 identity-element; 22 OC / 15 CM / 10 Algo / 3 PLK). Per-cell minimum 1, per-template minimum 5. Sample-selection prioritizes V1.7.1 cycle-5-re-emergence subjects (the most cycle-context-rich subset) and source-file diversity within each cell. Per-decision rationale + verdict committed at `docs/calibration-cycle-6-data/triage-notes.md`; machine-readable decisions at `docs/calibration-cycle-6-data/triage-decisions.json` mirroring `.swiftinfer/decisions.json` schema.
- **Cycle-6 findings doc (V1.9.3).** New `docs/calibration-cycle-6-findings.md` documents the 26.7% headline rate + per-template breakdown:
  - **monotonicity** (4/5 = **80%**) — calibrated tightly; OC HashTable scale/capacity functions are textbook monotonic.
  - **round-trip** (6/14 = **43%**) — V1.8.1's shape gate works; Collection-protocol `index(after:) ↔ index(before:)` accepts; cross-product elementary-functions noise on Complex rejects; `(Int) -> Int` directional surface still produces noise.
  - **associativity** (2/5 = **40%**) — `_relaxedAdd` family accepts at abstract math level; subtraction/distance reject.
  - **commutativity** (1/5 = **20%**) — same `_relaxedAdd` accept; OC `index(_:offsetBy:)` / `distance(from:to:)` directional rejects.
  - **idempotence** (0/10 = **0%**) — strongest scoring-tuning signal; all 10 sampled `(T) -> T` directional ops (`index(after:)`, `bucket(after:)`, `endOfChunk(startingAt:)`, etc.) reject. Type-symmetry `+30` is too permissive on direction-style ops.
  - **inverse-pair** (0/5 = **0%**) — same shape; SetAlgebra and Index ops over-fire.
  - **identity-element** (0/1 = 0%) — single Score 70 Likely-tier survivor (`rescaledDivide × Complex.zero`); cycle-7 op-name gate extension target.
- **Cycle-7 priority list (V1.9.3).** First data-driven priority list in the calibration trajectory:
  1. Idempotence template counter-signal on direction-named `(T) -> T` ops (after/before/next/prev/advance/succ/pred) — addresses the 0/10 rate.
  2. Inverse-pair template tightening (same shape, pair-level).
  3. FP approximate-equality template arm — `_relaxedAdd` / `_relaxedMul` are textbook examples.
  4. Math-library op-name gate extension to user-named ops (`rescaledDivide`, `_relaxed*` family) — addresses the cycle-6 #50 reject.
  5. Round-trip template counter-signal on direction-named `(T) -> T` pairs.
  6. `surfacedAt` plumbing — now meaningful with measured-rate baseline.
  7. Multi-rater triage methodology — addresses single-runner caveat.

### Documentation

- **Performance baseline carry-forward (V1.9.4).** `docs/perf-baseline-v1.9.md` documents that v1.9 ships zero Sources/ changes; §13 measurements are byte-equivalent to v1.8.0. Re-running the suite would consume 10+ minutes for zero signal. v1.8 baseline retained at `docs/perf-baseline-v1.8.md` as the substantive regression anchor; v1.9+ commits gate against either equivalently.
- **CLAUDE.md repo-state pointer index extended.** v1.9.0 release entry points at `docs/archive/v1.9 Calibration Plan.md`; "Where to look" perf-baseline pointer updated to `docs/perf-baseline-v1.9.md`; cycle-6 findings + data + rubric pointers added.

### Hard guarantees + performance

- All PRD §16 hard guarantees unchanged — v1.9 ships zero accept-flow writeout paths, zero new templates, zero new signals.
- All PRD §13 performance budgets hold at v1.9 (carried forward from v1.8). Row 4 ceiling stays at the post-v1.1.0 800 MB CI calibration. V1.6.1 flake-resistant 4.0s/6.0s budgets carry forward.
- PRD §14 + §19 runtime no-network guarantee unchanged; the cycle-6 triage data is in-source — no telemetry, no networking touches.

[1.9.0]: https://github.com/Joseph-Cursio/SwiftInferProperties/releases/tag/v1.9.0

## [1.8.0] — 2026-05-08

The fifth calibration cycle and the **first non-monotonic cycle in the calibration trajectory**. v1.8 ships one structural rule — a shape-gated Codable veto on `RoundTripTemplate.protocolCoverageVeto(...)` — that narrows V1.5.2's unconditional `[codableRoundTrip]` veto to fire only when the pair's forward/reverse signatures actually match a Codable encoder/decoder shape (`(T) -> Codec` ↔ `(Codec) -> T` for `Codec ∈ {Data, String}`). User-defined inverse pairs on Codable carriers (`(Int) -> Int`, `(Double) -> Double`, `(UInt64) -> Int?`) now fall through unsuppressed because they're not Codable round-trips by intent. Surgical empirical effect: **+23 of 326 surfaced suggestions** (+7.0% aggregate; first surface *increase* in the calibration loop), all on the round-trip template — closing the inherited V1.5.2 design question that V1.7.1's stdlib bake-in had surfaced. Cumulative across cycles 1–5: 1167 → 349 (−70.1%). Same hard-guarantee posture as v1.7 — §16 guarantees unchanged; §13 budgets re-baselined at [`docs/perf-baseline-v1.8.md`](docs/perf-baseline-v1.8.md), all rows within ±5% of v1.7.

### Calibration cycle 5 — round-trip Codable shape gate

- **`RoundTripTemplate.codableRoundTrippedType(for:)` shape gate (V1.8.1).** New `Sources/SwiftInferTemplates/RoundTripCodableShapeGate.swift` ships a `RoundTripTemplate` extension hosting a private static helper that returns the round-tripped type `T` when the pair has shape `(T) -> Codec` ↔ `(Codec) -> T` for `Codec ∈ {Data, String}` AND `T` is itself a non-codec type (the last guard rules out `(Data) -> Data` compression pairs from falsely matching). Returns nil for any other shape — `(T) -> T` user-inverse pairs and `(T) -> U` non-codec pairs both fall through. `RoundTripTemplate.protocolCoverageVeto(...)` now gates the existing `coverageVetoSignal(...)` call on this helper. Mechanism reuses V1.5.2's `coverageVetoSignal(...)` directly; no new `Signal.Kind`, no new `KnownProperty`, no template-side scoring changes outside `RoundTripTemplate`. The other five algebraic templates (idempotence / commutativity / associativity / inverse-pair / identity-element) are untouched — their candidate sets are op-class-mapped, not type-shape-mapped.
- **9 new tests.** Split into `Tests/SwiftInferTemplatesTests/RoundTripCodableShapeGateTests.swift` (7 unit tests covering: `(T) -> T` user-inverse on Codable T no longer vetoed, `(T) -> Data` + Codable T still vetoed, `(T) -> String` + Codable T still vetoed, decoder-as-forward orientation still vetoed, non-Codable T not vetoed, `(T) -> U` non-codec shape not vetoed, `(Data) -> Data` compression-shape not vetoed) and 2 end-to-end discover() integration tests in `Tests/SwiftInferTemplatesTests/ProtocolCoverageVetoIntegrationTests.swift` (`(Int) -> Int` user-inverse re-emerges, `(Doc) -> Data` Codable shape stays suppressed). 1502 → 1511 tests; all §13 perf budgets hold.
- **Cycle-5 calibration capture (V1.8.2).** Re-ran `swift-infer discover --include-possible --target X` against the four cycle-1+2+3+4 corpora at the v1.8.1 commit. Snapshots committed at `docs/calibration-cycle-5-data/post-tightening-*.discover.txt`; total surface 326 → 349 (+7.0%). Per-corpus delta: OrderedCollections 79 → 101 (+22 round-trip re-emergences — 21 `(Int) -> Int` HashTable / OrderedDictionary / OrderedSet index pairs + 1 `(UInt64) -> Int?` pair; matches the V1.7.1 suppression set exactly); Algorithms 74 → 75 (+1 round-trip — the `(Double) -> Double` pair V1.7.1's `Double: Codable` bake-in had suppressed); ComplexModule 166 → 166 (byte-identical to cycle-4 via diff); PropertyLawKit 7 → 7 (byte-identical).
- **Cycle-5 findings writeup (V1.8.3).** New `docs/calibration-cycle-5-findings.md` documents: per-corpus pre/post counts (cycle-4 → cycle-5 delta), the +23 re-emergence breakdown, the first-non-monotonic-cycle framing for the calibration narrative, the plan-vs-actual exact match (the v1.8 plan's projection landed point-for-point), and the cycle-6 priority list (Possible-tier sampling on the 349-surface as the new headline cycle-6 deliverable, FP template arm, math-library op extension to non-identity templates, surfacedAt plumbing, codec-set broadening if sampling reveals a need, SuggestionIdentity continuity fixture, SemanticIndex).

### Documentation

- **Performance baseline re-pinned.** `docs/perf-baseline-v1.8.md` is the canonical regression anchor for v1.8+. All seven §13 rows within ±5% of v1.7. Row 1a settled at 0.520s, confirming v1.7's +7.1% was machine-thermal noise (v1.6 0.495s → v1.7 0.530s → v1.8 0.520s, all within ~5% of each other). Row 4 (500-file memory) effectively unchanged at 134.5 MB (-0.7%) — the 23 additional re-emerged Suggestion structs are dwarfed by the 500-file synthetic corpus's hundreds of allocations. v1.7 baseline retained at `docs/perf-baseline-v1.7.md` for forensic comparison; v1.6 + v1.5 + v1.4 + v1.3 + v1.2 + v1.1 + v0.1.0 baselines retained for the longer trajectory window.
- **CLAUDE.md repo-state pointer index extended.** v1.8.0 release entry points at `docs/archive/v1.8 Calibration Plan.md`; "Where to look" perf-baseline pointer updated to `docs/perf-baseline-v1.8.md`; cycle-5 findings + data pointers added. The "round-trip template coverage-candidate tightening" item drops from the cycle-5 priority list (ships in this release).

### Hard guarantees + performance

- All PRD §16 hard guarantees unchanged — v1.8 ships no new accept-flow writeout paths; the cycle-5 tuning narrows an existing scoring helper.
- All PRD §13 performance budgets hold at v1.8; see `docs/perf-baseline-v1.8.md` for the row-by-row numbers. Row 4 ceiling stays at the post-v1.1.0 800 MB CI calibration. V1.6.1 flake-resistant 4.0s/6.0s budgets carry forward.
- PRD §14 + §19 runtime no-network guarantee unchanged; the curated codec set is in-source — no telemetry, no networking touches.

[1.8.0]: https://github.com/Joseph-Cursio/SwiftInferProperties/releases/tag/v1.8.0

## [1.7.0] — 2026-05-08

The fourth calibration cycle. v1.7 ships one structural rule — a curated 14-key stdlib-conformance bake-in on `ProtocolCoverageMap.inheritedTypesIndex(...)` — closing the cycle-2 0-delta finding on stdlib-typed (`Int` / `Double` / `UInt64` / etc.) carriers. Surgical empirical effect: −24 of 350 surfaced suggestions (−6.9% aggregate; −23 attributable to V1.7.1 + −1 to V1.6.1.1's math-library op-name gate which post-dated the cycle-3 capture). 22 of 23 V1.7.1 suppressions concentrate on the round-trip template via `Int: Codable` / `UInt64: Codable` / `Double: Codable` reach. Cumulative across cycles 1–4: 1167 → 326 (−72.1%). Same hard-guarantee posture as v1.6 — §16 guarantees unchanged; §13 budgets re-baselined at [`docs/perf-baseline-v1.7.md`](docs/perf-baseline-v1.7.md), six of seven rows within ±5% of v1.6 (Row 1a +7.1% machine-thermal noise, well below the 25% hard-gate).

### Calibration cycle 4 — stdlib-conformance bake-in

- **`ProtocolCoverageMap.stdlibConformances` curated table (V1.7.1).** New `Sources/SwiftInferCore/StdlibConformances.swift` ships a 14-key `[TypeName: Set<String>]` of stdlib types whose conformances are unconditional and well-known: signed integer family (`Int` / `Int8` / `Int16` / `Int32` / `Int64`) → 10 conformances including `AdditiveArithmetic` / `Numeric` / `SignedNumeric` / `Comparable` / `Hashable` / `Codable` / `Equatable` (plus documentation parents `BinaryInteger` / `FixedWidthInteger` / `SignedInteger`); unsigned integer family (`UInt` / `UInt8` / `UInt16` / `UInt32` / `UInt64`) → no `SignedNumeric` / `SignedInteger`, has `UnsignedInteger`; floating-point family (`Float` / `Double`) → adds `FloatingPoint` / `BinaryFloatingPoint`; `Bool` → `[Equatable, Hashable, Codable]`; `String` → `[Equatable, Comparable, Hashable, Codable]`. `Float80` / `Float16` / `Optional<T>` / `Array<T>` / `Set<T>` / `Dictionary<K,V>` / tuples deliberately excluded — platform-conditional or generic-conditional conformance is v1.1 constraint-engine territory (PRD §20.2).
- **`inheritedTypesIndex(from:)` seeded with bake-in (V1.7.1).** `ProtocolCoverageMap.inheritedTypesIndex(from: typeDecls)` now seeds the result with `stdlibConformances` *before* folding corpus typeDecls. Per-key `formUnion` semantics preserved — a corpus `extension Int: SomeProto` *unions* with the curated set rather than replacing it. The mechanism reuses V1.5.2's `coverageVetoSignal(...)` directly; no new `Signal.Kind`, no new `KnownProperty`, no template-side changes.
- **18 new tests** split into `Tests/SwiftInferCoreTests/ProtocolCoverageMapStdlibBakeInTests.swift` (15 unit tests covering: 14-key count + per-type conformance assertions + exclusion documentation + `inheritedTypesIndex` integration + `coverageVetoSignal` end-to-end) and 3 integration tests in `Tests/SwiftInferTemplatesTests/ProtocolCoverageVetoIntegrationTests.swift` (V1.7.1 end-to-end discover() tests: Int+ suppressed, Double* suppressed, user-named `combine` on Int still emits via op-class fall-through). 1484 → 1502 tests; all §13 perf budgets hold.
- **Cycle-4 calibration capture (V1.7.2).** Re-ran `swift-infer discover --include-possible --target X` against the four cycle-1+2+3 corpora at the v1.7.1 commit. Snapshots committed at `docs/calibration-cycle-4-data/post-bakein-*.discover.txt`; total surface 350 → 326 (−6.9%). Per-corpus delta: OrderedCollections 101 → 79 (−22, the headline corpus — round-trip template's `[codableRoundTrip]` candidate suppresses 21 `(Int) -> Int` + 1 `(UInt64) -> Int?` pairs); Algorithms 75 → 74 (−1, one `(Double) -> Double` pair); ComplexModule 167 → 166 (−1, attributable to V1.6.1.1's math-library op-name gate post-dating the cycle-3 capture); PropertyLawKit 7 → 7 (no stdlib-typed carriers — bake-in has nothing to extend coverage to).
- **Cycle-4 findings writeup (V1.7.3).** New `docs/calibration-cycle-4-findings.md` documents: per-corpus pre/post counts (cycle-3 → cycle-4 delta), V1.6.1.1 + V1.7.1 attribution split, the cumulative 1167 → 326 (−72.1%) trajectory across cycles 1–4 with four mutually-exclusive structural mechanisms, the most informative cycle-4 finding (V1.7.1 surfaces an inherited V1.5.2 design question — whether `RoundTripTemplate`'s `[codableRoundTrip]` veto candidate is the correct coverage signal for stdlib-typed user-defined inverse pairs like `minimumCapacity(forScale:) ↔ scale(forCapacity:)`), the plan-vs-actual deviation analysis (the bake-in's reach extends only as far as the per-template candidate-set design allows), and the cycle-5 priority list (round-trip template coverage-candidate tightening, approximate-equality FP template arm, Possible-tier sampling on the 326-surface, `surfacedAt` plumbing, math-library op extension to non-identity-element templates, SemanticIndex).

### Documentation

- **Performance baseline re-pinned.** `docs/perf-baseline-v1.7.md` is the canonical regression anchor for v1.7+. Six of seven §13 rows within ±5% of v1.6. Row 1a (+7.1%) flagged as machine-thermal noise (three repeat measurements consistent at 0.527/0.533/0.536s; well below the 2.0s hard budget at 73% headroom). Row 4 (500-file memory) effectively unchanged at 135.5 MB (+0.5%) — bake-in seeding overhead well below a single Suggestion struct's footprint. v1.6 baseline retained at `docs/perf-baseline-v1.6.md` for forensic comparison; v1.5 + v1.4 + v1.3 + v1.2 + v1.1 + v0.1.0 baselines retained for the longer trajectory window.
- **CLAUDE.md repo-state pointer index extended.** v1.7.0 release entry points at `docs/archive/v1.7 Calibration Plan.md`; "Where to look" perf-baseline pointer updated to `docs/perf-baseline-v1.7.md`; cycle-4 findings + data pointers added. The "curated stdlib-conformance bake-in" item drops from the cycle-4 priority list (ships in this release).

### Hard guarantees + performance

- All PRD §16 hard guarantees unchanged — v1.7 ships no new accept-flow writeout paths; the cycle-4 tuning is a curated-data extension of an existing helper.
- All PRD §13 performance budgets hold at v1.7; see `docs/perf-baseline-v1.7.md` for the row-by-row numbers + Row 1a noise discussion. Row 4 ceiling stays at the post-v1.1.0 800 MB CI calibration. V1.6.1 flake-resistant 4.0s/6.0s budgets carry forward.
- PRD §14 + §19 runtime no-network guarantee unchanged; the curated stdlib table is in-source — no telemetry, no networking touches.

[1.7.0]: https://github.com/Joseph-Cursio/SwiftInferProperties/releases/tag/v1.7.0

## [1.6.1] — 2026-05-08

Maintenance patch bundling three orthogonal cycle-4 cleanups: (a) extends V1.6.1's pair-formation skip-list filter to math-library op names (closes the cycle-3 ComplexModule survivors `pow` and `**`); (b) makes the V1.5.2 protocol-coverage citation deterministic across runs; (c) widens two perf budgets that flaked on consecutive CI pushes. No new calibration cycle, no new structural rules. Same hard-guarantee posture as v1.6.0 — §16 guarantees unchanged; §13 budget changes documented in [`docs/perf-baseline-v1.6.md`](docs/perf-baseline-v1.6.md)'s Re-baselining log.

### Cycle-4 maintenance

- **Math-library op-name gate extension (cycle-4 priority #2).** `IdentityElementPairing.stdlibBinaryOperators` extended from `{+, -, *, /, %}` to `{+, -, *, /, %, pow, **}`. Closes one of the two cycle-3 ComplexModule identity-element survivors: `(zero, pow)` × `Complex.zero` is now filtered. The other survivor — `(zero, rescaledDivide)` × `Complex.zero` — stays surfaced because `rescaledDivide` is a user-named op outside the curated math-library set; suppressing it would risk false-positives on user types where `rescaledDivide` could be a legitimate monoid combine. Rationale for `pow` / `**`: `pow(x, 0) == 1` (not `x`), so `(zero, pow)` is the same kind of cross-product mismatch as `(zero, *)`; users would not name a custom monoid combine op `pow` (math convention is well-established). Updated tests in `IdentityElementPairingFilterTests.swift` move `(zero, pow)` and `(zero, **)` into the filtered-pairs section; one prior test in the user-named-ops section was removed (now covered by the filter).
- **Citation determinism in `firstCoveringProtocol(...)` (cycle-4 priority #6).** V1.5.2's `ProtocolCoverageMap.firstCoveringProtocol(in:for:)` walked `Set<String>` non-deterministically when called from `coverageVetoSignal(...)` — suppressed-suggestion Decisions records cited different protocols across runs (e.g. cycle-1 might cite "Numeric", cycle-2 "Hashable"). Suppressed suggestions don't appear in stdout (so byte-stability of user-visible output already held), but the Decisions citation field was non-deterministic. Fixed by sorting `inheritedTypes.sorted().first { ... }` before scanning. New regression-guard test `firstCoveringProtocolIsDeterministic` confirms the fix; existing `firstCoveringProtocolReturnsFirst` test updated to expect lexicographic-first match (was input-order-first).
- **Perf budget widening for two CI-flaky tests (cycle-4 priority #7).** Two tests in `Tests/SwiftInferIntegrationTests/TestLifterPerformanceTests.swift` had structurally tight ceilings on GitHub Actions hardware:
  - **Row 2 (`syntheticHundredTestFileCorpus`): 3.0s → 4.0s.** Flaked once on the v1.5.7 push (3.115s).
  - **`discoverPipelineHundredTestFileBudgetWithM32Pipeline`: 5.0s → 6.0s.** Flaked twice in consecutive pushes (v1.5.7 at 5.189s, v1.6.6 at 5.076s).

  CI runs ~1.4–2.5× slower than Apple M1 baseline; the original ceilings provided effectively zero CI headroom. New budgets keep ≥1s headroom on the worst observed CI measurement, matching v1.1's "flake-resistant 3.0s" precedent for Row 1c (DequeModule). Local Apple M1 measurements unchanged at 1.222s (Row 2) / ~3.6s (integration test); the 25% regression rule still operates against those numbers. Documented in `docs/perf-baseline-v1.6.md`'s Re-baselining log.

### Hard guarantees + performance

- All PRD §16 hard guarantees unchanged.
- All PRD §13 performance budgets hold at v1.6.1 with the documented widenings; see `docs/perf-baseline-v1.6.md` for the row-by-row numbers + Re-baselining log.
- PRD §14 + §19 runtime no-network guarantee unchanged; v1.6.1 is pure code/test/budget changes — no telemetry, no networking touches.

[1.6.1]: https://github.com/Joseph-Cursio/SwiftInferProperties/releases/tag/v1.6.1

## [1.6.0] — 2026-05-08

The third calibration cycle. v1.6 ships one structural rule — a pair-formation skip-list filter on `IdentityElementPairing` — *complementary* to v1.5's coverage veto: where v1.5 suppressed pairs the kit already verifies, v1.6 suppresses pairs whose `(kit-blessed-constant, stdlib-operator)` combo doesn't bind to a kit-published identity law. Surgical empirical effect: −3 of 353 surfaced suggestions (−0.85% aggregate), all on swift-numerics/ComplexModule identity-element template. Combined with v1.5: ComplexModule identity-element 6 → 2 (−66.7%) over two calibration cycles. Same hard-guarantee posture as v1.5 — §16 guarantees unchanged; §13 budgets re-baselined at [`docs/perf-baseline-v1.6.md`](docs/perf-baseline-v1.6.md), all rows within ±5% of v1.5.

### Calibration cycle 3 — pair-formation skip-list filter

- **`IdentityElementPairing.skipsKnownMismatched(...)` filter (V1.6.1).** Two curated sets — `kitBlessedIdentityConstants = {zero, one, empty, identity}` and `stdlibBinaryOperators = {+, -, *, /, %}` — drive a private skip helper that fires when *all three* conditions hold: (1) the identity-constant name is kit-blessed, (2) the op-name is a stdlib operator with kit-published identity laws, (3) V1.5.2's `IdentityElementTemplate.identityCoverageCandidate(...)` returns nil for the (name, op) combo. Wired into `IdentityElementPairing.candidates(...)`'s pair-emission loop; filtered pairs skip downstream Suggestion construction. Skip-list rather than allow-list per the v1.6 plan's open-decision #1: preserves recall for unrecognized constants (e.g. `none`, `default`, custom user names) and user-named ops (e.g. `merge`, `combine`, `intersect`). Mechanism reuses V1.5.2's `identityCoverageCandidate(...)` directly — already `internal` by Swift's default access; no API surface widening required.
- **17 new tests in `IdentityElementPairingFilterTests.swift`.** Five categories per the v1.6 plan: (a) cross-product mismatches skipped (`(zero, *)`, `(zero, /)`, `(zero, -)`, `(one, +)`, `(empty, *)`); (b) kit-blessed combos still emit (`(zero, +)`, `(one, *)`, `(empty, +)` for set-union semantics); (c) constants outside kit-blessed set always emit (`(none, +)`, `(default, *)`, `(none, /)`); (d) user-named ops always emit (`(zero, merge)`, `(empty, intersect)`, `(zero, pow)`, `(identity, combine)`); (e) existing type-shape filter still gates non-`(T, T) -> T` ops.
- **Cycle-3 calibration capture (V1.6.2).** Re-ran `swift-infer discover --include-possible --target X` against the four cycle-1+2 corpora at the v1.6.1 commit. Snapshots committed at `docs/calibration-cycle-3-data/post-filter-*.discover.txt`; total surface 353 → 350 (−0.85%). Per-template suppression on ComplexModule: identity-element 5 → 2; the 3 filtered targets are exactly `(zero, -)`, `(zero, /)`, `(zero, *)`. The 2 ComplexModule survivors (`pow(_:_:)` × `Complex.zero`, `rescaledDivide(_:_:)` × `Complex.zero`) are user-named ops outside V1.6.1's stdlib-operator gate — documented as cycle-4 priority #2 (~30 min: extend the gate to math-library names like `pow`).
- **Cycle-3 findings writeup (V1.6.3).** New `docs/calibration-cycle-3-findings.md` documents: per-corpus pre/post counts (cycle-2 → cycle-3), per-pair filtering breakdown walking each of the 5 cycle-2 ComplexModule survivors through V1.6.1's three-conjunct skip predicate, the cumulative 6 → 2 trajectory across cycles 1–3 demonstrating v1.5+v1.6 *complementary* coverage of mutually-exclusive cause-of-noise classes (kit-covered vs structurally-mismatched), the continued 0-delta on the other three corpora (different reason from cycle 2's 0-delta — cycle 3's corpora had *zero identity-element pairs* at input, so the filter has nothing to filter), the plan-vs-actual deviation (5 → 0 projected, 5 → 2 actual — methodology lesson about distinguishing design-bound vs aspirational projections in calibration plans), and the cycle-4 priority list (curated stdlib-conformance bake-in + math-library op-name gate extension + approximate-equality FP template arm + Possible-tier sampling on the 350-surface + `surfacedAt` plumbing + citation-determinism fix + Row 2/1d budget widening + SemanticIndex).

### Documentation

- **Performance baseline re-pinned.** `docs/perf-baseline-v1.6.md` is the canonical regression anchor for v1.6+. All seven §13 rows within ±5% of v1.5 — the v1.6 plan's "flat" projection confirmed. Row 4 (500-file memory) effectively unchanged at 134.8 MB (+0.1%) — the v1.6 filter is upstream of `IdentityElementPair` allocation but the pair struct's memory cost is dominated by upstream-allocated `FunctionSummary` / `IdentityCandidate` references. v1.5 baseline retained at `docs/perf-baseline-v1.5.md` for forensic comparison; v1.4 + v1.3 + v1.2 + v1.1 + v0.1.0 baselines retained for the longer trajectory window.
- **CLAUDE.md repo-state pointer index extended.** v1.6.0 release entry points at `docs/archive/v1.6 Calibration Plan.md`; "Where to look" perf-baseline pointer updated to `docs/perf-baseline-v1.6.md`; cycle-3 findings + data pointers added. The "op-class-aware identity-element pair-formation" item drops from the open-trajectory list (it ships in this release).

### Hard guarantees + performance

- All PRD §16 hard guarantees unchanged — v1.6 ships no new accept-flow writeout paths; the cycle-3 tuning is a pure pair-formation skip with no scoring or rendering changes.
- All PRD §13 performance budgets hold at v1.6; see `docs/perf-baseline-v1.6.md` for the row-by-row numbers. Row 4 ceiling stays at the post-v1.1.0 800 MB CI calibration. Row 2 + Row 1d budget tightness on CI hardware (surfaced during the v1.5 push) carries forward as cycle-4 priority #7.
- PRD §14 + §19 runtime no-network guarantee unchanged; the curated skip-list is in-source — no telemetry, no networking touches.

[1.6.0]: https://github.com/Joseph-Cursio/SwiftInferProperties/releases/tag/v1.6.0

## [1.5.0] — 2026-05-08

The second calibration cycle. v1.5 ships one structural rule — a `protocolCoveredProperty` veto driven by a curated 13-protocol coverage table — and re-runs the §17.3 loop against the four cycle-1 corpora to measure the suppression delta. Surgical empirical effect: −5 of 358 surfaced suggestions across the four corpora (−1.4% aggregate), all on swift-numerics/ComplexModule, the only cycle-1 corpus that declares algebraic conformances on user types. Same hard-guarantee posture as v1.4 — §16 guarantees unchanged; §13 budgets re-baselined at [`docs/perf-baseline-v1.5.md`](docs/perf-baseline-v1.5.md), all rows within ±5% of v1.4.

### Calibration cycle 2 — protocol-coverage suppression

- **`ProtocolCoverageMap` curated catalog (V1.5.1).** New `Sources/SwiftInferCore/ProtocolCoverageMap.swift` ships a `KnownProperty` enum (22 cases — additive / multiplicative / set / equatable / hashable / codable / kit-monoid families) plus a `protocolCoverage: [String: Set<KnownProperty>]` table covering 13 stdlib + kit protocols (`Equatable` / `Comparable` / `Hashable` / `AdditiveArithmetic` / `Numeric` / `SignedNumeric` / `SetAlgebra` / `Codable` plus kit `Semigroup` / `Monoid` / `CommutativeMonoid` / `Group` / `Semilattice`). Transitive coverage hand-baked into values (`Numeric ⊇ AdditiveArithmetic`'s set) so callers don't walk inheritance chains. Helpers: `inheritedTypesIndex(from:)` (folds `[TypeDecl]` cross-file, mirrors `EquatableResolver`), `coverageVetoSignal(forTypeText:inheritedTypesByName:candidateProperties:)` factory, `firstCoveringProtocol(in:for:)` for citation. `Encodable` and `Decodable` are intentionally absent from the table — neither alone covers `codableRoundTrip`, so listing them with empty sets would add textual-match noise without behavioural benefit (documented v1 limitation).
- **`Signal.Kind.protocolCoveredProperty` veto signal (V1.5.1).** Mirrors the existing `nonDeterministicBody` / `nonEquatableOutput` posture using `Signal.vetoWeight` (full collapse to suppressed, not heavy counter-signal). Per the v1.5 plan's open-decision #3 default: protocol coverage is authoritative when it matches — the kit's `check<Protocol>PropertyLaws` *does* verify the property, so the suggestion is genuinely redundant. Calibration record preserved (suggestion still scores; lands in Suppressed; cycle-3 metrics can introspect "how many suggestions did `: AdditiveArithmetic` suppress?").
- **Six algebraic templates wired (V1.5.2).** Each template gains an optional `inheritedTypesByName: [String: Set<String>] = [:]` parameter (defaulted, backwards-compat) plus a `protocolCoverageVeto(...)` helper. **Op-class-aware where it matters:** `IdentityElementTemplate` maps the `(identity-constant, op-name)` pair to a single covered `KnownProperty` (`(zero, +)` → `additiveIdentityZero`, `(one, *)` → `multiplicativeIdentityOne`, `(empty, union/formUnion/+)` → `setUnionEmptyIdentity`, `(identity, *)` → `monoidIdentity`). `CommutativityTemplate` / `AssociativityTemplate` map the op name to additive / multiplicative / set-union variants. `IdempotenceTemplate` uses the fixed `[setIntersectionIdempotent, semilatticeIdempotence]` candidate set. `InversePairTemplate` uses `[additiveInverse, groupInverse]`. `RoundTripTemplate` uses `[codableRoundTrip]`. Critical false-positive guard: user-named `combine` / `merge` / etc. on stdlib-typed carriers fall through unsuppressed because the kit covers `+`/`*` specifically, not arbitrary commutative functions on Numeric carriers.
- **Cycle-2 calibration capture (V1.5.3).** Re-ran `swift-infer discover --include-possible --target X` against the four cycle-1 corpora at the v1.5.2 commit. Captured snapshots committed at `docs/calibration-cycle-2-data/post-rule-*.discover.txt`; per-corpus delta documented in `docs/calibration-cycle-2-data/README.md`. Total surface: 358 → 353 (−1.4%). Per-template suppression on ComplexModule: associativity 8→6, commutativity 8→6, identity-element 6→5; the suppressed targets are exactly `+(z:w:)` (covered by `: AdditiveArithmetic`), `*(z:w:)` (covered by `: Numeric`), and `+(z:w:)` × `Complex.zero` (covered by AdditiveArithmetic's identity law). The 5 noise survivors per template (`-`, `/`, `pow`, `rescaledDivide`, `_relaxedAdd/Mul`) are correctly preserved — they're either non-commutative ops or user-named functions not covered by stdlib `+`/`*` laws.
- **Cycle-2 findings writeup (V1.5.4).** New `docs/calibration-cycle-2-findings.md` documents: corpus pre/post counts, per-protocol suppression breakdown (5 hits resolve through 2 of 13 curated protocols — `AdditiveArithmetic` and `Numeric`), the operator-aware-pairing-as-fallout demonstration on the 6 ComplexModule identity-element hits (cycle-1's accepted `+ × .zero` is now suppressed by coverage; the 5 rejected noise items stay surfaced — opposite outcome to cycle-1's hypothesis, but complementary), the headline 0-delta limitation finding (textual-only conformance match misses stdlib types — corpora that build on stdlib-typed `Int` / generic `Element` carriers can't be suppressed by v1.5 alone), and the cycle-3 priority list (op-class-aware identity-element pairing at pair-formation step + curated stdlib-conformance bake-in + approximate-equality FP template arm + Possible-tier sampling on the 353-surface + `surfacedAt` plumbing + citation-determinism fix + SemanticIndex).

### Documentation

- **Performance baseline re-pinned.** `docs/perf-baseline-v1.5.md` is the canonical regression anchor for v1.5+. All seven §13 rows within ±5% of v1.4 — the v1.5 plan's "flat or slightly improved" projection confirmed. Row 4 (500-file memory) drops 136.0 → 134.6 MB (−1.0%), continuing the V1.4.3b-driven downward trajectory but in a much smaller increment (the bulk of the cross-type round-trip allocation pressure was already cleared in v1.4). v1.4 baseline retained at `docs/perf-baseline-v1.4.md` for forensic comparison; v1.3 + v1.2 + v1.1 + v0.1.0 baselines retained for the longer trajectory window.
- **CLAUDE.md repo-state pointer index extended.** v1.5.0 release entry points at `docs/archive/v1.5 Calibration Plan.md`; "Where to look" perf-baseline pointer updated to `docs/perf-baseline-v1.5.md`; cycle-2 findings + data pointers added. The "protocol-conformance suppression mechanism" item drops from the open-trajectory list (it ships in this release).

### Hard guarantees + performance

- All PRD §16 hard guarantees unchanged — v1.5 ships no new accept-flow writeout paths; the cycle-2 tuning only adds a scoring veto + curated-table consultation.
- All PRD §13 performance budgets hold at v1.5; see `docs/perf-baseline-v1.5.md` for the row-by-row numbers. Row 4 ceiling stays at the post-v1.1.0 800 MB CI calibration despite a further ~1.4 MB headroom gain.
- PRD §14 + §19 runtime no-network guarantee unchanged; the protocol-coverage map is in-source — no telemetry, no networking touches.

[1.5.0]: https://github.com/Joseph-Cursio/SwiftInferProperties/releases/tag/v1.5.0

## [1.4.0] — 2026-05-08

The first calibration cycle. v1.4 operationalizes PRD §17.3's empirical-tuning loop, ships the long-deferred PRD §17.2 `swift-infer metrics` subcommand, and lands two structural tunings derived from the cycle-1 surface analysis. Most user-visible effect: `swift-infer discover --include-possible` total surface drops 69.3% across the four cycle-1 benchmark corpora (1167 → 358 surfaced suggestions); resident memory on the 500-file synthetic perf row drops 75.4% (551.8 → 136.0 MB) from the cross-type rule eliminating Suggestion-struct allocations before tier-filter. Same hard-guarantee posture as v1.3 — §16 guarantees unchanged; §13 budgets re-baselined at [`docs/perf-baseline-v1.4.md`](docs/perf-baseline-v1.4.md).

### `swift-infer metrics` (PRD §17.2)

- **New subcommand** that aggregates one or more `.swiftinfer/decisions.json` files into per-template acceptance / rejection / suppression rates plus tier-mix acceptance. Three of PRD §17.2's five metrics ship in this MVP — the missing two (time-to-adoption + post-acceptance failure rate) require new fields on `DecisionRecord` and stay deferred to v1.5+.
- Default mode walks up to `<package-root>/.swiftinfer/decisions.json`. Aggregation mode takes one or more `--decisions <path>` flags and merges via the new `Decisions.merge(_:)` helper (identity-keyed, latest-timestamp wins on collision). Per PRD §17.2 the renderer surfaces a low-count advisory (< 20 decisions) and a retirement-candidate flag (≥ 20 decisions and < 50% acceptance).

### Calibration cycle 1 — empirical tunings

- **Cross-type round-trip counter-signal (V1.4.3b).** New `Signal.Kind.crossTypeRoundTripPair` (-25 weight) fires on `RoundTripTemplate` pairs where `forward.containingTypeName != reverse.containingTypeName`. Score 30 → 5 (Suppressed). Three exemptions: (a) both `nil` (free-function pair), (b) same containing type (cross-extension), (c) shared `@Discoverable(group:)` annotation. Empirical effect across the 4 cycle-1 corpora: round-trip Possible 990 → 181 (-81.7%); biggest cuts on swift-algorithms (728 → 75) and swift-collections (257 → 101); single-type corpora unchanged. SemanticIndex would catch the cross-type case via type resolution; this rule is the cheap pre-SemanticIndex approximation using `containingTypeName`.
- **FP-storage counter-signal + kit-FP-laws explainability pointer (V1.4.3 + V1.4.3a).** New `Signal.Kind.floatingPointStorage` (-10 weight; PRD §17.3 step-2 magnitude) fires on associativity / commutativity / inverse-pair candidates whose parameter type is in the curated FP-storage list (Float / Double / Float16-80 / CGFloat / Complex / Decimal). Drops Score 30 → 20 (Possible-tier floor) — the suggestion stays surfaced under `--include-possible` so the explainability kit-pointer is visible. The advisory text reframes FP suggestions as real algebraic candidates that need a verification-mode adjustment (finite-only generator) per PropertyLawKit's `FloatingPointLaws.swift` posture, not as noise to suppress. Identity-element exempt (FP additive identity is reliable). Round-trip / idempotence / monotonicity / reduce-equivalence exempt for cycle 1.
- **Calibration findings writeup (V1.4.4).** New `docs/calibration-cycle-1-findings.md` documents the cycle-1 narrative: corpus selection (swift-collections + swift-numerics + swift-algorithms + SwiftPropertyLaws), pre-triage observations (identity-element is the only template that escapes Score 30 without test-body cross-validation; round-trip is 84.8% of Possible-tier surface; score distribution is highly compressed), the 6-decision minimum-scope triage findings (16.7% acceptance on identity-element template), and the cycle-2 priority list (operator-aware identity-element pairing → approximate-equality template arm → Possible-tier sampling → `surfacedAt` plumbing). Decisions data committed at `docs/calibration-cycle-1-data/swift-numerics-ComplexModule.decisions.json`; pre/post-tune discover outputs for all 4 corpora committed at `docs/calibration-cycle-1-data/*.discover.txt` for cycle-2 diff target.

### Documentation

- **Performance baseline re-pinned.** `docs/perf-baseline-v1.4.md` is the canonical regression anchor for v1.4+. Headline: Row 4 (500-file memory delta) drops -75.4% (551.8 → 136.0 MB) — the cross-type round-trip rule suppresses pairs *before* `Suggestion` construction in `RoundTripTemplate.suggest`, reclaiming ~415 MB of peak resident memory on the synthetic perf corpus. Rows 1–3 within ±5% of v1.3. The post-v1.1.0 800 MB CI ceiling stays; cycle 2 may revisit if the gain holds in CI. v1.3 baseline retained for forensic comparison.
- **CLAUDE.md repo-state pointer index extended.** v1.4.0 release entry points at `docs/archive/v1.4 Calibration Plan.md`; "Where to look" perf-baseline pointer updated to `docs/perf-baseline-v1.4.md`. The `swift-infer metrics` mention drops from the open-trajectory list (it ships in this release).

### Hard guarantees + performance

- All PRD §16 hard guarantees unchanged — v1.4 ships no new accept-flow writeout paths; the cycle-1 tunings only change scoring (signal weights) and explainability text.
- All PRD §13 performance budgets hold at v1.4; see `docs/perf-baseline-v1.4.md` for the row-by-row numbers. Row 4 ceiling stays at the post-v1.1.0 800 MB CI calibration despite the dramatic (-75.4%) headroom gain.
- PRD §14 + §19 runtime no-network guarantee unchanged; metrics aggregation is purely local — `NoNetworkRuntimeTests` still passes.

[1.4.0]: https://github.com/Joseph-Cursio/SwiftInferProperties/releases/tag/v1.4.0

## [1.3.0] — 2026-05-07

Closes the PRD §7.8 trio for the v1.x scanner shape: with M16 shipping the general consumer-producer chain detection (closing M10's deferred Option A), all three §7.8 examples now have full v1.x coverage — preconditions across all four `ParameterizedValue.Kind` cases (M9 + M15), inferred domains for both round-trip-pair narrowing (M10 with generator override) and general consumer-producer chains (M16 comment-only advisory), and equivalence classes across three of four Option A axes (M11 + M13 + M14). Same hard-guarantee + perf-budget posture as v1.2 — §16 guarantees unchanged; §13 budgets re-baselined at [`docs/perf-baseline-v1.3.md`](docs/perf-baseline-v1.3.md).

### TestLifter

- **M16 — General consumer-producer chain detection (PRD §7.8 second example, generalized; closes M10's deferred Option A).** Lifts M10's round-trip-pair filter on the corpus-wide `[String: [DomainCallSite]]` map to surface advisory chains for any (consumer, producer) chain meeting a five-criterion narrow scope: ≥3 sites + homogeneous producer + producer-existence (`FunctionSummary` lookup) + textual type-alignment (`producerSummary.returnTypeText == consumer.parameters[0].typeText`) + anti-double-fire vs. M5 round-trip pairs. M16.0 added `HintOrigin` (`.roundTripPair` / `.consumerProducerChain`) on `DomainHint` with default-back-compat (every M10 call site keeps compiling). M16.1 ships `ConsumerProducerChainDetector` enforcing all five criteria; reuses M10's `ProducerVetoReason` + `DomainInferrer.computeVeto` verbatim for the four producer-veto checks (throws / async / multi-arg / non-generatable). M16.2 wires the detector through `LiftedSuggestionPipeline.promote(...)` as a sibling to the M11 advisory union; promoted suggestions enter the discover stream with `templateName == "consumer-producer-chain"` + `Tier.advisory` per PRD §7.8 (documentation, not a runnable property). M16.3 adds the accept-flow renderer arm — comment-only writeout to `Tests/Generated/SwiftInfer/consumer-producer/<consumer>_<producer>.swift` via the M11-shaped out-of-band `consumerProducerChainHintsByIdentity` side-map (preserves §13 row 4). Includes the M10 follow-up for `DomainCorpusScanner.classify(_:)` — peeling `try`/`try!`/`try?`/`await` wrappers so producer-throws / producer-async chains surface with the matching veto comment instead of falling silent (was a pre-existing M10 gap; M10 + M16 both benefit). Cross-test data-flow correlation (`let x = format(t)` in `testA` and `validate(x)` in `testB`) deferred — natural sequencing is post-SemanticIndex.

### Documentation

- **Performance baseline re-pinned.** `docs/perf-baseline-v1.3.md` is the canonical regression anchor for v1.3+. All §13 rows within ±5% of the v1.2 baseline — well inside the 25% regression rule. Row 2 (TestLifter parse +1.1%) and row 4 (memory delta +0.6%) confirm the perf-neutral posture: M16's chain detector runs once per discover invocation over already-aggregated input, and the `consumerProducerChainHintsByIdentity` side-map carrier follows the M11 posture (keyed only on qualifying chains, not on every Suggestion). v1.2 baseline retained at `docs/perf-baseline-v1.2.md` for forensic comparison; v1.1 + v0.1.0 baselines retained for the longer trajectory window.
- **CLAUDE.md repo-state pointer index extended.** M16 entry points at `docs/archive/TestLifter M16 Plan.md`; "Where to look" perf-baseline pointer updated to `docs/perf-baseline-v1.3.md`.

### Hard guarantees + performance

- All PRD §16 hard guarantees unchanged — M16 wrote only to allowlisted `Tests/Generated/SwiftInfer/consumer-producer/` paths (sibling slot to the existing `Tests/Generated/SwiftInfer/equivalence-class/`) and never modified existing source.
- All PRD §13 performance budgets hold at v1.3; see `docs/perf-baseline-v1.3.md` for the row-by-row numbers. Row 4 ceiling stays at the post-v1.1.0 800 MB CI calibration.
- PRD §14 + §19 runtime no-network guarantee unchanged; no networking-API touches in the M16 surface.

[1.3.0]: https://github.com/Joseph-Cursio/SwiftInferProperties/releases/tag/v1.3.0

## [1.2.0] — 2026-05-07

Closes the PRD §7.8 trio for the v1.x scanner shape: M9 preconditions now cover all four `ParameterizedValue.Kind` cases (M15 adds `Float`/`Double`), and the §7.8 third example covers three of four Option A axes via M13 + M14 with same-target enum exhaustiveness annotation fully wired. Same hard-guarantee + perf-budget posture as v1.1 — §16 guarantees unchanged; §13 budgets re-baselined at [`docs/perf-baseline-v1.2.md`](docs/perf-baseline-v1.2.md).

### TestLifter

- **M13 — General partition surface for equivalence classes (PRD §7.8 third example, scope A axes 1+2+4).** `MarkerPair` lifted to `SwiftInferCore.MarkerTable.swift` + `MarkerSet` added (the combined `MarkerTable` carrier + `Vocabulary.markerPairs` / `markerSets` JSON round-trip is the supporting data-model lift). M13.1 broadens the discover-loop scan from `[Valid/Invalid]` to `MarkerTable.curatedPairs` (5 pairs: `Valid`/`Invalid` + `Success`/`Failure` + `Accept`/`Reject` + `Pass`/`Fail` + `Allowed`/`Forbidden`); per-predicate ranking dedup picks the highest-site-count winner when a predicate fires under multiple pairs. M13.2 ships `NClassEquivalenceClassDetector` + `NClassEquivalenceClassHint` for ≥3-bucket partitions on `XCTAssertEqual(predicate(x), .case)` / `#expect(predicate(x) == .case)` shapes; reuses M11 vetoes + adds `PredicateVetoReason.predicateReturnNotEquatable` (textual proxy for the full Equatable check, no SemanticIndex). M13.3 wires both detectors through `LiftedSuggestionPipeline` + `EquivalenceClassHintKind` sum-type side-map + accept-flow renderer (N-class file naming `EquivalenceClasses_<predicate>_<markerSetName>.swift`); pipes `Vocabulary.markerSets` into `TestLifter.discover` as additive marker-table extension. Two-class `coversDomain` annotation fires syntactically (XCTAssertTrue + XCTAssertFalse, no `!` negation) → renderer surfaces `Exhaustiveness: forAll x: T. p(x) ∨ ¬p(x)`. Multi-predicate equivalence classes (axis 3) deferred — same SemanticIndex-sequencing constraint as M12.
- **M14 — Same-target enum coverage for N-class `coversDomain` (PRD §7.8 third example, axis 4 N-class branch).** `TypeDecl` extended with `enumCaseNames: [String]`, populated by `FunctionScannerVisitor.makeTypeDecl` for primary `enum` decls + extensions that add cases; `MemberBlockInspector.enumCaseNames(in:)` walks `EnumCaseDeclSyntax` and strips associated values + raw-value initializers. `NClassEquivalenceClassDetector.detect(...)` widened to consume `[TypeDecl]`; `computeCoversDomain` unions same-name primary + extension records, runs case-insensitive identifier coverage, sets `hint.coversDomain == true` only when every same-target enum case is matched by a marker (cross-target / unresolved / partial / empty / optional-return / function-typed all conservative-false). The M13.3 renderer's `Exhaustiveness:` comment now surfaces in production for fully-covered N-class corpora. Cross-target enum case enumeration deferred (SemanticIndex territory, sibling to M12 / M13.+).
- **M15 — `Float`/`Double` numerical-bound preconditions (PRD §7.8 first example).** Closes the M9 plan OD #1 deferral. `PreconditionPattern` extended with `positiveDouble` / `nonNegativeDouble` / `negativeDouble` / `doubleRange(low:high:)`. `PreconditionInferrer.detectFloatPattern` replaces the `case .float: return nil` arm; `parseDoubleLiteral` strips underscores, explicitly rejects `0x`/`0X` prefixes (Swift's `Double.init(_:)` natively parses `0x1.0p2` → 4.0, so the prefix check mirrors M9's hex-radix kill posture), `!isFinite` defensive kill, M9 OD #4 most-specific rule preserved (≥2 distinct → `doubleRange`; else sign-bound). End-to-end fixture exercises 5 distinct `Doc(title:, ratio:)` Double sites → `// Inferred precondition: ratio — all observed values are in [1.5, 5.5]` + `Gen.double(in: 1.5...5.5)`. After M15, the M9 inferrer covers all four `ParameterizedValue.Kind` cases the M4.1 scanner produces.

### Documentation

- **Performance baseline re-pinned.** `docs/perf-baseline-v1.2.md` is the canonical regression anchor for v1.2+. Row 4 (memory delta) matches v1.1 to ~0.05% (548.8 MB → 548.5 MB), confirming M13 + M14 + M15 added no persistent allocations. Row 2 (TestLifter parse) effectively flat at +0.2% (1.209s → 1.211s), confirming M13 marker-table broadening + M14 enum-case extraction stayed sub-millisecond per detector. v1.1 baseline retained at `docs/perf-baseline-v1.1.md` for forensic comparison across the M13/M14/M15 trajectory; v0.1.0 baseline retained at `docs/perf-baseline-v0.1.md` for the longer trajectory window.
- **CLAUDE.md repo-state pointer index extended.** M13 / M14 / M15 entries point at their archive plans; "Where to look" perf-baseline pointer updated to `docs/perf-baseline-v1.2.md`.

### Hard guarantees + performance

- All PRD §16 hard guarantees unchanged — M13 / M14 / M15 wrote only to allowlisted `Tests/Generated/SwiftInfer/` paths and never modified existing source.
- All PRD §13 performance budgets hold at v1.2; see `docs/perf-baseline-v1.2.md` for the row-by-row numbers. Row 4 ceiling stays at the post-v1.1.0 800 MB CI calibration.
- PRD §14 + §19 runtime no-network guarantee unchanged; no networking-API touches in the M13–M15 surface.

[1.2.0]: https://github.com/Joseph-Cursio/SwiftInferProperties/releases/tag/v1.2.0

## [1.1.0] — 2026-05-05

Closes the PRD §7.8 expanded-outputs row (preconditions M9 + inferred domains M10 + equivalence classes M11) and ships the TestLifter detector fan-out (M2–M7) + the `convert-counterexample` CLI subcommand (M8). Same hard-guarantee + perf-budget posture as v0.1.0 — §16 guarantees unchanged; §13 budgets re-baselined at [`docs/perf-baseline-v1.1.md`](docs/perf-baseline-v1.1.md).

### TestLifter

- **M2 — Idempotence + commutativity detection.** `AssertAfterDoubleApplyDetector` (idempotence pattern) and `AssertSymmetryDetector` (commutativity pattern) join M1's `AssertAfterTransformDetector` to feed the +20 cross-validation signal across all three M1+M2 templates.
- **M3 — Generator inference + stream entry.** `LiftedSuggestionRecovery` performs type recovery via `FunctionSummary` lookup; promoted lifted suggestions enter the discover stream end-to-end with cross-validation suppression and accept-flow writeouts.
- **M4 — Mock-based generator synthesis.** `MockGeneratorSynthesizer` synthesizes generators for ≥3-site test-corpus types via setup-region scanning (`SetupRegionTypeAnnotationScanner`, `SetupRegionConstructionScanner`); pipeline-side mock-inferred fallback supplements the kit's strategist; M4.2 annotation-fallback recovery tier.
- **M5 — Six-detector fan-out + Codable round-trip.** Adds monotonicity (`AssertOrderingPreservedDetector`), count-invariance (`AssertCountChangeDetector`), and reduce-equivalence (`AssertReduceEquivalenceDetector`) to the M2 trio; Codable round-trip generator rung lights up.
- **M6 — TestLifter workflow operationalization.** `--test-dir` CLI override + walk-up default + `// swiftinfer: skip` honoring + `.swiftinfer/decisions.json` persistence for lifted suggestions.
- **M7 — Counter-signal scanning + non-determinism suppression.** `AsymmetricAssertionDetector` scans for negative-form assertions (`XCTAssertNotEqual`, `XCTAssertFalse`) and applies a `-25` counter-signal to suggestions whose round-trip / commutativity assertions are contradicted; `MockGeneratorSynthesizer` suppresses non-deterministic constructor patterns.
- **M8 — `swift-infer convert-counterexample` subcommand.** Reads a kit-emitted counterexample JSON and writes a regression test stub to a sandboxed path; covers the 10 v1.1 templates.
- **M9 — Inferred preconditions (PRD §7.8 first example).** `PreconditionInferrer` detects `precondition()` / `assert()` / `guard let` patterns in producer functions and surfaces them as `// Inferred precondition:` advisory comments inside mock-inferred generators. Conservative narrow surface (deferred: `Float`/`Double` numerical-bound preconditions per the M9 plan's precision-class concerns).
- **M10 — Inferred domains, round-trip-pair scope (PRD §7.8 second example).** Round-trip suggestions whose reverse-side test corpus uniformly receives forward-side output get a `DomainHint` that overrides the generator with `Gen<T>.map(forward)` plus a `// Inferred domain:` provenance comment. Hard-veto on throws / async / multi-arg / non-generatable producers (comment-only fallback names the veto reason). General consumer-producer chain detection (Option A) deferred to a future v1.x.
- **M11 — Predicate equivalence-class detection (PRD §7.8 third example).** Two-class `Valid`/`Invalid` predicate partitions with both buckets reaching the M4.3 ≥3 threshold + homogeneous predicate + matched polarity surface as `equivalence-class` advisory suggestions; comment-only writeout to `Tests/Generated/SwiftInfer/equivalence-class/EquivalenceClasses_<predicate>.swift` on accept. Adds `Tier.advisory`, `AssertionInvocation.Kind.xctAssertFalse`, and a side-map carrier shape (`InteractiveTriage.Context.equivalenceClassHintsByIdentity`) that recovered the §13 row 4 memory budget after an inline-Optional regression. General partition surface (arbitrary markers, N-class, multi-predicate, cross-class relations) deferred to a future v1.x.

### Tier + scoring

- `Tier.advisory` — new tier value rendered as `[Advisory]`. Distinct from `Strong` / `Likely` / `Possible` so consumers can tell documentation surfaces apart from runnable property suggestions. `init(score:)` never returns `.advisory`; the surfacing pipeline sets it explicitly via `Score(advisorySignals:)`.
- `AssertionInvocation.Kind.xctAssertFalse` — slicer recognizes `XCTAssertFalse(...)` calls as a first-class assertion kind, used by the M11 polarity-homogeneity check (and available to future negative-assertion detectors).

### Kit coordination

- **Kit renamed: SwiftProtocolLaws → SwiftPropertyLaws (v2.0.0).** A `refactor!`-only kit release — no behavioral changes; library products `ProtocolLawKit` / `ProtoLawCore` / `ProtoLawMacro` became `PropertyLawKit` / `PropertyLawCore` / `PropertyLawMacro`. `Package.swift` now references `https://github.com/Joseph-Cursio/SwiftPropertyLaws` from `2.0.0`. Pre-rename v1.9.0 had added `CommutativeMonoid` / `Group` / `Semilattice` for M8.5's writeouts.

### Documentation

- **PRD v1.0 cut.** `docs/SwiftInferProperties PRD v1.0.md` is now the canonical product spec; v0.1–v0.4 retained as historical. The v0.4-era arg-help PRD section references in `SwiftInferCommand.swift` are intentionally left at `PRD v0.4 §X.X` since the section numbering predates v1.0; updating to v1.0 references is a future cleanup pass, not a v1.1 deliverable.
- **CLAUDE.md condensed to a milestone index.** Per-milestone narratives moved fully to `docs/archive/*.md`; the repo-state paragraph is now pointer-only.
- **Performance baseline re-pinned.** `docs/perf-baseline-v1.1.md` is the canonical regression anchor for v1.1+. Two §13 rows moved meaningfully against the v0.1.0 baseline (both inside the §13 25% rule): row 2 (TestLifter parse) +138% with 60% headroom remaining, and row 4 (memory delta) +12% leaving 9% headroom against the 600 MB ceiling.

### Hard guarantees + performance

- All PRD §16 hard guarantees unchanged — M9 / M10 / M11 wrote only to allowlisted `Tests/Generated/SwiftInfer/` paths and never modified existing source.
- All PRD §13 performance budgets hold at v1.1; see `docs/perf-baseline-v1.1.md` for the row-by-row numbers.
- PRD §14 + §19 runtime no-network guarantee unchanged; no networking-API touches in the M2–M11 surface.

[1.1.0]: https://github.com/Joseph-Cursio/SwiftInferProperties/releases/tag/v1.1.0

## [0.1.0] — 2026-05-03

First public pre-release. The TemplateEngine surface (PRD v0.4 §5) and TestLifter M1 (PRD §7.9) are feature-complete; v0.1.0 ships them under SemVer 0.x semantics (API may break in 0.2.x). The PRD's "v1.1+ trajectory" heading describes the post-v0.1.0 work, not a future v1.1 — naming carryover from the design doc.

### TemplateEngine

- **M1 — Discovery + idempotence + round-trip pairing.** SwiftSyntax pipeline; CLI discovery tool (`swift-infer discover`); idempotence + round-trip templates wired through the §4 scoring engine and §4.5 explainability block; basic cross-function pairing (type + naming filter); `// swiftinfer: skip` rejection markers honored.
- **M2 — Algebraic-structure templates.** Commutativity, associativity, identity-element templates active alongside M1's idempotence + round-trip.
- **M3 — Confidence model + cross-validation.** Per-signal weights surfaced in the explainability block; M3.4 contradiction pass; M3.5 dormant `crossValidationFromTestLifter` seam.
- **M4 — Generator inference via `DerivationStrategist`.** Per-suggestion `GeneratorMetadata` populated from the kit's strategist; `.todo` fallback for inference fall-throughs (PRD §16 #4).
- **M5 — `@Discoverable` + `@CheckProperty` macro recognition.** +35 signal for annotated functions; macro expands `@CheckProperty` into peer `@Test` declarations.
- **M6 — Workflow operationalization.** `--interactive` triage with `[A/B/B'/s/n/?]` prompts; `Tests/Generated/SwiftInfer/` writeouts; `swift-infer drift` mode with non-fatal CI-friendly warnings; `.swiftinfer/decisions.json` + `baseline.json` infrastructure.
- **M7 — Monotonicity + invariant-preservation + RefactorBridge.** Two new templates and the conformance-proposal bridge that writes to `Tests/Generated/SwiftInferRefactors/`.
- **M8 — Algebraic-structure composition cluster.** CommutativeMonoid / Group / Semilattice / Numeric (Ring) / SetAlgebra emitter arms; multi-proposal accumulator + `[A/B/B'/s/n/?]` prompt; `InversePairTemplate` (Possible-tier non-Equatable T fallback).

### TestLifter

- **M1 — Test-body parser + slicer + round-trip detector + cross-validation.** XCTest + Swift Testing parser; PRD §7.2 four-rule slicing pass; `AssertAfterTransformDetector` for the round-trip pattern; `LiftedSuggestion` + `CrossValidationKey` matching surface; CLI wiring lights up the +20 cross-validation signal end-to-end.

### Kit coordination

- Consumes [SwiftProtocolLaws](https://github.com/Joseph-Cursio/SwiftProtocolLaws) v1.9.0 (kit-defined `Semigroup`, `Monoid`, `CommutativeMonoid`, `Group`, `Semilattice`) for M7 + M8 conformance writeouts.

### Hard guarantees + performance

- All PRD §16 hard guarantees (#1 source-file-immutable, #2 never-deletes-tests, #3 drift-never-fails-CI, #4 `.todo`-on-fallthrough, #5 `--target`-required + scope guard, #6 byte-identical reproducibility) ship with explicit release-gate integration tests.
- All PRD §13 performance budgets ship with regression tests; v0.1.0 calibration revised the row 4 memory budget from 200 MB to 600 MB based on R1.1.b measurement (see `docs/perf-baseline-v0.1.md`).
- PRD §14 + §19 runtime no-network guarantee covered by URLProtocol-based runtime interception in addition to the static no-networking-APIs grep.

[0.1.0]: https://github.com/Joseph-Cursio/SwiftInferProperties/releases/tag/v0.1.0
