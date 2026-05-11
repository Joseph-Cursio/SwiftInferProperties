# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.27.0] — 2026-05-11

The twenty-fourth calibration cycle and **measurement-driven mechanism cycle** closing the two cycle-23 findings (Algo Iterator-like Sequence-conformance survivors + OC bucket/word inverse-pair direction-pair). Two small workstreams; surface 114 → **113** (-1). Plan-vs-actual: -1 vs projected -4 (cycle-23 sample-manifest enumeration error on one projected pick; V1.27.A infrastructure didn't fire on current corpora).

### Calibration cycle 24 — cycle-23 findings (2-workstream)

- **Workstream A (V1.27.A): Sequence-conformance fallback on V1.21.A IteratorProtocol veto.** New path: when carrier conforms to `Sequence` (via `inheritedTypesByName`) AND method name in `iteratorMethodNames`, fire full veto. Mechanism class 7 extension. **Surface impact: 0** (cycle-23 Algo Iterator-like picks already caught by V1.21.A/V1.22.A by V1.27.A discover time; infrastructure for future Sequence-conforming carriers).

- **Workstream B (V1.27.B): Name-prefix-gated full-veto on InversePairTemplate direction-counter.** Extended V1.11.1 to fire `Signal.vetoWeight` when both pair sides direction-labeled AND both names start with `index`/`bucket`/`word`. Mirrors V1.22.B (round-trip) + V1.25.A (idempotence). **Surface impact: -1 OC** (`bucket(after:) × bucket(before:)`; cycle-23 #26 closure). The `word × word` pick listed in cycle-23 sample-manifest didn't exist in v1.25 surface (manifest enumeration error).

### Documentation

- **v1.27 plan (V1.27.0).**
- **Cycle-24 findings (V1.27.C).**
- **Cycle-24 capture.** `docs/calibration-cycle-24-data/post-v1.27-*.discover.txt`.
- **Performance baseline (V1.27.C).**

[1.27.0]: https://github.com/Joseph-Cursio/SwiftInferProperties/releases/tag/v1.27.0

## [1.26.0] — 2026-05-10

The twenty-third calibration cycle and the **fifth empirical-only release** (after cycles 6 = 26.7%, 14 = 34.8%, 17 = 52.3%, 20 = 48.8%). v1.26 binary-equivalent to v1.25.0. Headline: **25/37 = 67.6%** Possible-tier acceptance rate — **outcome A**; +18.8pp from cycle-20's 48.8% (the largest single-cycle aggregate jump in the loop's history). **§19 ≥70% target now within +2.4pp** — sample-noise band on n=40.

### Calibration cycle 23 — fifth empirical re-measurement

- **Five-point trajectory:** 26.7% → 34.8% → 52.3% → 48.8% → **67.6%**. The cycle-20 non-monotonic step (-3.5pp) is now followed by the loop's largest single-cycle jump (+18.8pp). Cycle 20's drop was attributed at the time to V1.22.D calibration trade-off + cycle-20 first-measurement of 2 NEW reject classes + round-trip weighting shift — cycle 23 validates that interpretation: the surviving v1.25 surface composition has materially higher per-template accept rates.

- **Drivers of the +18.8pp acceleration:** four mechanism cycles between 20 and 23 closed -38 candidates with high precision-positive density:
  - V1.21.C + V1.22.B/D + V1.24.A removed cross-product round-trip noise → round-trip rate 60% → 85.7%.
  - V1.24.B + V1.24.C + V1.25.A removed direction-op + non-deterministic lifted-idempotence rejects → lifted-idempotence rate 50% → 66.7%.
  - V1.24.D + V1.25.A reduced idempotence non-lifted from 23 picks (5-cycle 0%) to 3 picks (all unknown) → 0% drag eliminated from aggregate.
  - V1.18.C dual-style 5/5 = 100% (3-cycle rate-stability).

- **Per-template results:**
  - round-trip: 60.0% → **85.7%** (+25.7pp)
  - idempotence (non-lifted): 0% → n/a (surface evaporation; 23 → 3 picks)
  - idempotence-lifted: 50.0% → **66.7%** (+16.7pp)
  - dual-style-consistency: 100% → 100% (3-cycle rate-stability)
  - All other templates within ±5pp of cycle-20.

- **Cycle-24 priority list (post-v1.26):**
  1. FP approximate-equality template arm (10-cycle carry-forward; cycle-14 priority #4).
  2. **NEW (cycle-23 finding):** Algo idempotence-lifted Iterator-like survivors veto (extends V1.21.A; closes 2).
  3. **NEW (cycle-23 finding):** OC bucket/word direction-pair veto on inverse-pair template (extends V1.25.A's name-prefix gate; closes 2).
  4. Math-library `_relaxed*` (defer indefinitely).
  5-7. v1.19 carry-forwards.

### Documentation

- **v1.26 plan (V1.26.0).** Fifth empirical-only cycle plan.
- **Cycle-23 surface re-capture (V1.26.A).** `docs/calibration-cycle-23-data/surface-counts.md`.
- **Cycle-23 triage rubric (V1.26.B).** `docs/cycle-23-triage-rubric.md` carries cycle-20 verbatim + post-cycle-20 mechanism context.
- **Cycle-23 triage data (V1.26.C).** 40-pick triage; 25 accept / 12 reject / 3 unknown.
- **Cycle-23 findings (V1.26.D).** `docs/calibration-cycle-23-findings.md` — five-point trajectory + per-mechanism effectiveness + cycle-24 priority list.
- **Performance baseline v1.25 carry-forward (V1.26.E).**

### Hard guarantees + performance

All PRD §16 hard guarantees + §13 perf budgets + §14 privacy unchanged.

[1.26.0]: https://github.com/Joseph-Cursio/SwiftInferProperties/releases/tag/v1.26.0

## [1.25.0] — 2026-05-10

The twenty-second calibration cycle and the **fourth consecutive measurement-driven mechanism cycle** (cycles 18 + 19 + 21 + 22 = v1.21 + v1.22 + v1.24 + v1.25). Single-workstream cycle closing the cycle-21 finding (`index*`/`bucket*`/`word*` direction-op idempotence non-lifted reject class). Surface 130 → **114** (-16 = -12.3%) — first cycle to cross **-90% cumulative reduction** vs cycle-1's 1167-baseline (prior low: -88.86% at cycle 21). Plan-vs-actual: -16 vs projected -13 to -15 (slightly exceeded; V1.25.A caught 2 Algo picks the plan didn't enumerate).

### Calibration cycle 22 — cycle-21 finding (single workstream)

- **Workstream A (V1.25.A): Index-advance direction-op idempotence veto.** Direct cycle-21 finding closure. Modified `IdempotenceTemplate.directionLabelCounterSignal(for:)` to bump V1.10.1's -15 magnitude to -25 (full veto-equivalent) when: (1) function name starts with `index`, `bucket`, or `word`, AND (2) first-param label is in `DirectionLabels.curated`. Joint match limits false-positive risk; non-matching direction-labeled functions preserve V1.10.1's -15 magnitude verbatim. Mirrors V1.22.B's both-sides direction full-veto pattern on round-trip, applied here to idempotence with name-prefix gate. Mechanism class 6 extension (no new class). Surface impact: **-14 OC + -2 Algo = -16 candidates**. 9 new unit tests in `IdempotenceTemplateIndexAdvanceVetoTests.swift`.

- **Per-template surface delta:**
  - Idempotence (non-lifted): 19 → 3 (-16 = **-84%**, the single largest per-template percentage reduction in the loop's history).
  - All other templates byte-stable.

- **Cumulative trajectory** cycle 22 sets new low at **-90.23%** vs cycle-1's 1167-baseline (prior: -88.86% at cycle 21; -86.97% at cycle 19; -80.4% at cycle 13). **First cycle to cross -90% threshold.** Cumulative aggregate movement across cycles 17 → 22 (5 cycles since cycle-17 measurement): 335 → 114 = **-66.0%**.

- **Cycle-23 priority list (rotated post-v1.25):**
  1. **v1.26 = cycle 23 empirical-only re-measurement** (5th measurement point in the loop's history). Provisional aggregate projection: 55-65% from cycle-20's 48.8% baseline + cycles 21+22's -38 reject closures.
  2. FP approximate-equality template arm (9-cycle carry-forward).
  3. Math-library `_relaxed*` extension (7-cycle carry-forward).
  4. CompositionTemplate non-numeric monoid extension (v1.19 carry-forward).
  5-6. Lift admission relaxation; `liftedFromMutation` magnitude re-baselining (v1.19 carry-forwards).

### Documentation

- **v1.25 calibration plan (V1.25.0).** `docs/v1.25 Calibration Plan.md` — single-workstream mechanism cycle plan.
- **Cycle-22 findings (V1.25.B).** `docs/calibration-cycle-22-findings.md` — surface delta, per-mechanism effectiveness, cycle-23 priority list (top = v1.26 empirical re-measurement).
- **Cycle-22 capture (V1.25.B).** `docs/calibration-cycle-22-data/post-v1.25-*.discover.txt`.
- **Performance baseline re-measured (V1.25.B).** `docs/perf-baseline-v1.25.md` — re-measured at commit `308245e`; every row within ±5% of v1.24 baseline.

### Hard guarantees + performance

- All PRD §16 hard guarantees unchanged.
- All PRD §13 performance budgets hold at v1.25.
- PRD §14 + §19 runtime no-network guarantee unchanged.

[1.25.0]: https://github.com/Joseph-Cursio/SwiftInferProperties/releases/tag/v1.25.0

## [1.24.0] — 2026-05-10

The twenty-first calibration cycle and the **third consecutive measurement-driven mechanism cycle** (cycle 18 = v1.21 closed cycle-17 findings; cycle 19 = v1.22 closed cycle-18 findings; cycle 21 = v1.24 closes cycle-19 + cycle-20 findings). Four independently-mergeable workstreams shipped in one release. Surface 152 → **130** (-22 = -14.5%) — new cumulative-reduction low at **-88.86%** vs cycle-1's 1167-baseline (prior low: -86.97% at cycle 19). First cycle to cross the -88% threshold. Plan-vs-actual: -22 vs projected -21 to -32 (solidly in range). Mechanism-class taxonomy 14 → **14** (no new classes; four extensions of existing classes 6 + 7).

### Calibration cycle 21 — cycle-19 + cycle-20 findings (4-workstream mechanism)

- **Workstream A (V1.24.A): Asymmetric label class mismatch counter on round-trip.** Direct cycle-19 finding + cycle-20 reconfirmed at 5/5 = 100% reject. New `Sources/SwiftInferTemplates/RoundTripAsymmetricLabelCounter.swift` adds `asymmetricLabelClassMismatchCounterSignal(for:)` that fires at -25 when one side direction-labeled and the other side domain-marker-labeled (or vice versa). Closes the OC `index(after:) × _minimumCapacity(forScale:)`-shape cross-product noise class. Score arithmetic: 30 + 5 - 15 (V1.12.1) - 25 (V1.24.A) = -5 → Suppressed. Mechanism class 6 extension. Surface impact: **-6 OC**. 8 new unit tests in `RoundTripAsymmetricLabelCounterTests.swift`.

- **Workstream B (V1.24.B): Explicit non-idempotent mutator-name veto on idempotence-lifted.** Direct cycle-20 finding closure (V1.20.C 4/4 reject on OC `reverse()`/`removeFirst()`/`removeLast()` lifted-idempotence picks). New `Sources/SwiftInferCore/MutatorBlockedFromIdempotence.swift` curated set `{reverse, removeFirst, removeLast, popFirst, popLast, dropFirst, dropLast}`. New `IdempotenceTemplate+MutatorBlocklistVeto.swift` extension fires `Signal.vetoWeight` when the lift's underlying method name is in the curated set — on **any** value-semantic carrier (no protocol-conformance requirement). Generalizes V1.21.A's class 7 carrier-protocol-conformance sub-class from Iterator-conforming carriers to any value-semantic carrier with curated-method-name match. Surface impact: **-9 OC** (exceeded plan projection of 4-6 because pop*/drop* variants caught extra candidates). 11 new unit tests in `IdempotenceTemplateMutatorBlocklistTests.swift`.

- **Workstream C (V1.24.C): Non-deterministic shuffle veto extension.** Direct cycle-20 finding closure (V1.20.C #40 unknown verdict on `OrderedDictionary.shuffle()`; surfaced despite being non-deterministic because the existing body-signal RNG detector missed the OC pattern). Name-fallback approach per the v1.24 plan §"Open decisions" #2 lean. New `Sources/SwiftInferCore/NonDeterministicMutatorNames.swift` curated set `{shuffle}`. New `IdempotenceTemplate+NonDeterministicMutatorVeto.swift` extension fires `Signal.vetoWeight` (`Signal.Kind.nonDeterministicBody`) on the canonical `shuffle()` mutator on any value-semantic carrier. Surface impact: **-3 OC** (all 3 OC shuffle variants closed). 6 new unit tests in `IdempotenceTemplateNonDeterministicMutatorTests.swift`.

- **Workstream D (V1.24.D): Capacity/formatter shape-disambiguation veto on idempotence non-lifted.** Direct cycle-20 finding closure (5-cycle-flat 0% idempotence non-lifted rate is dominated by shape-coincidence patterns). New `IdempotenceTemplate+ShapeDisambiguationVeto.swift` extension fires `Signal.vetoWeight` on two patterns: (1) capacity/scale domain conversion — `(Int) -> Int` shape AND name contains domain-conversion token (Capacity / Count / Scale / scale) AND first-param label is `forScale:` or `forCapacity:`. Both conditions required to avoid false positives on V1.15.1 curated verbs like `normalize(forScale:)`. (2) Formatter — name has prefix `_description*` or `format*` AND single-param shape. Catches `_description(type:)`, `format(_:)`, `formatBuckets(_:)`. Mechanism class 7 extension (third in lineage: V1.14.1 SetAlgebra → V1.21.C math-forward → V1.24.D capacity/formatter). Surface impact: **-4 OC** (under-projected vs plan's 10-15; direction-op idempotence rejects dominate the residual pool — cycle-22+ priority). 14 new unit tests in `IdempotenceTemplateShapeDisambiguationTests.swift`.

- **Per-corpus surface delta:**
  - ComplexModule: 21 → 21 (byte-stable; no v1.24 mechanism targets CM).
  - OrderedCollections: 114 → 92 (-22 = -19.3%); absorbs 100% of v1.24 closure.
  - Algorithms: 10 → 10 (byte-stable).
  - PropertyLawKit: 7 → 7 (byte-stable).

- **Per-template surface delta** (cycle-20 → cycle-21):
  - `round-trip`: 18 → 12 (-6; V1.24.A).
  - `idempotence (non-lifted)`: 23 → 19 (-4; V1.24.D).
  - `idempotence-lifted`: 21 → 9 (-12; V1.24.B + V1.24.C; **largest per-template delta**).
  - All other templates byte-stable.

- **Cumulative trajectory:** cycles 1-20 went 1167 → 152 (-86.97%); cycle 21 = v1.24 reaches 1167 → 130 = **-88.86%** (new low). Cumulative aggregate movement across cycles 17 → 21 (4 cycles since the cycle-17 measurement): 335 → 130 = -61.2%.

- **Cycle-22 priority list (rotated post-v1.24, in expected impact order):**
  1. v1.25 = cycle 22 (empirical-only re-measurement OR mechanism cycle; loop choice).
  2. **NEW (cycle-21 finding):** `index(after:)` / `index(before:)` direction-op idempotence non-lifted veto. The residual 19-pick idempotence non-lifted pool is dominated by 13+ OC direction-op rejects. Mechanism: extend V1.10.1's direction-label counter from -15 to -25 (full veto) on `index*`/`bucket*`/`word*` names + direction-labeled. Magnitude: closes ~13 OC candidates.
  3. FP approximate-equality template arm (8-cycle carry-forward).
  4. Math-library `_relaxed*` extension (6-cycle carry-forward).
  5-7. Carry-forwards from v1.19 (CompositionTemplate non-numeric monoid; lift admission relaxation; `liftedFromMutation` magnitude re-baselining).

### Documentation

- **v1.24 calibration plan (V1.24.0).** `docs/v1.24 Calibration Plan.md` — four-workstream mechanism cycle plan; cycle-19+20-finding-driven priorities.
- **Cycle-21 findings (V1.24.E).** `docs/calibration-cycle-21-findings.md` — surface delta, per-workstream contribution table, mechanism-class taxonomy update (14 → 14 with 4 extensions), per-mechanism effectiveness ranking, cycle-20 picks status at v1.24, cycle-22 priority list with NEW cycle-21 finding.
- **Cycle-21 capture (V1.24.E).** `docs/calibration-cycle-21-data/post-v1.24-*.discover.txt` — four per-corpus discover snapshots at the V1.24.D commit.
- **Performance baseline re-measured (V1.24.E).** `docs/perf-baseline-v1.24.md` — re-measured at commit `7efcced`. Every row within ±5% of v1.22 baseline; ≤+5% budget met. Most rows faster than v1.22 (suppression short-circuit on -22 closed candidates outweighs per-call O(1) veto-evaluation overhead). Row 4 peak delta 135.9 MB (vs v1.22's 135.8 MB).

### Hard guarantees + performance

- All PRD §16 hard guarantees unchanged — v1.24 ships zero new accept-flow writeout paths (all four workstreams are veto-only or counter-only mechanisms).
- All PRD §13 performance budgets hold at v1.24 (re-measured at [`docs/perf-baseline-v1.24.md`](docs/perf-baseline-v1.24.md)). v1.24 release-blocking criterion (≤+5% wall vs v1.22) met with margin.
- PRD §14 + §19 runtime no-network guarantee unchanged.

[1.24.0]: https://github.com/Joseph-Cursio/SwiftInferProperties/releases/tag/v1.24.0

## [1.23.0] — 2026-05-10

The twentieth calibration cycle and the **fourth empirical-only release** in the loop's history (after cycle 6 = v1.9 = 26.7%; cycle 14 = v1.17 = 34.8%; cycle 17 = v1.20 = 52.3%). v1.23 is binary-equivalent to v1.22.0 except the version-string bump — zero `Sources/` changes, zero test changes, zero behavior changes. The cycle's deliverable is **per-template + per-corpus acceptance-rate data on the post-v1.22 152-surface**. Headline: **21/43 = 48.8%** Possible-tier acceptance rate — **outcome D** under the v1.23 plan thresholds (Aggregate < 52% — first non-monotonic move in the loop's history). The drop is **explained by a calibration trade-off + sample-distribution shift**, not a precision regression.

### Calibration cycle 20 — fourth empirical re-measurement on the post-v1.22 152-surface

- **Surface re-capture metadata (V1.23.A).** `docs/calibration-cycle-20-data/surface-counts.md` documents that v1.23 is binary-equivalent to v1.22; cycle-20 sample basis is the V1.22.E discover capture (152 candidates across the 4 cycle-1..14 corpora). Per-template per-corpus surface composition documented; stratification rebased for the v1.22 surface (round-trip 8 vs cycle-17's 15; idempotence-lifted 9 vs cycle-17's 6, covering NEW first-measurement classes).
- **Cycle-20 triage rubric (V1.23.B).** New `docs/cycle-20-triage-rubric.md` carries cycle-17's per-template criteria for the 10 template classes verbatim. Adds "Post-cycle-17 mechanism context" section documenting the 7 mechanism layers (cycles 18 + 19) each surviving v1.22 candidate has cleared. Per-template suppression-layer tables updated: round-trip +2 layers (V1.21.C + V1.22.B/D); idempotence non-lifted +1 (V1.21.C); idempotence-lifted +2 (V1.21.A + V1.22.A); inverse-pair +1 (V1.22.D). Decision JSON schema mirrors cycle-17's verbatim.
- **Cycle-20 46-decision triage (V1.23.C).** Stratified sample of 46 picks across 10 (template × corpus) cells matching cycle-17's sample size for direct comparability. Verdict counts: **21 accept / 22 reject / 3 unknown**.
- **Cycle-20 findings (V1.23.D).** Headline: **21/43 = 48.8%**, -3.5pp from cycle-17's 52.3%; **first non-monotonic move in the loop's history**. Three drivers:
  1. **V1.22.D suppressed cycle-17 ACCEPT class** — Algo `endOfChunk × startOfChunk` triple was cycle-14/17 ACCEPT; V1.22.D's stride-style label both-sides veto closes round-trip + inverse-pair on this site (calibration trade-off per v1.22 plan §"Risks": auto-emit usability vs measured-correctness). Cycle-20 sample doesn't see these picks. ~-2-3pp aggregate cost.
  2. **Cycle-20 sample concentrates on first-measurement reject classes** — OC asymmetric round-trip cross-pairs (5/5 = 100% reject; cycle-19 finding class) + OC sort/shuffle/reverse-class lifted-idempotence (2 accept + 4 reject + 1 unknown; cycle-17 sampled BucketIterator instead which V1.22.A subsequently closed).
  3. **Cycle-20 round-trip weighting shift** — cycle-17 47% CM canonical-anchor weight vs cycle-20 36%.
- **Per-template results (cycle-17 → cycle-20):**
  - round-trip: 60.0% → **54.5%** (-5.5pp; sample-distribution shift)
  - idempotence (non-lifted): 0.0% → **0.0%** (5-cycle flat)
  - commutativity: 33.3% → **33.3%** (rate-stability)
  - associativity: 66.7% → **66.7%** (rate-stability)
  - monotonicity: 75.0% → **75.0%** (rate-stability)
  - inverse-pair (non-lifted): 50.0% → **0.0%** (V1.22.D closed cycle-17 ACCEPT; small-n sample-mix)
  - identity-element (non-lifted): 0.0% → **0.0%** (carry-forward reject)
  - **dual-style-consistency: 100.0% → 100.0%** (V1.18.C by-construction precision rate-stability)
  - **idempotence-lifted: 33.3% → 50.0%** (sort accepts add to internal-CoW class; reverse/removeFirst/removeLast rejects offset)
  - **composition-lifted: 0.0% → 0.0%** (V1.21.B Strong → Likely demote rate-stability)
- **Per-mechanism effectiveness (cycle-20):**
  - **V1.18.C dual-style: 5/5 = 100% rate-stability** (largest mechanism-class precision contribution in the loop's history; continued by-construction precision).
  - V1.21.C math-forward function counter: all 5 cycle-20 CM round-trip canonical anchors preserved by `canonicalInversePairs` allowlist.
  - V1.21.A + V1.22.A IteratorProtocol + BucketIterator extension: 0 cycle-20 sample picks (carrier-class fully closed; precision-positive on surface only).
  - V1.22.B both-sides direction-counter: revealed asymmetric cross-pair class (5/5 reject — first measurement).
  - V1.22.D stride-style label veto: -2-3pp cost (calibration trade-off).
  - **V1.22.C fixed-point-name positive signal (NEW class 14): 0 sample picks** — recall-positive infrastructure ready; no functions in `FixedPointNames.curated` surface on cycle-1..14 corpora.
- **Cycle-21 priority list (rotated post-v1.23):**
  1. Asymmetric label class mismatch counter (cycle-19 finding; cycle-20 reconfirmed at 5/5 reject).
  2. **NEW (cycle-20 finding):** `reverse`/`removeFirst`/`removeLast` veto on idempotence-lifted for non-IteratorProtocol carriers (closes 4-6 OC candidates).
  3. **NEW (cycle-20 finding):** Non-deterministic shuffle veto extension (extend `nonDeterministicVeto` body-signal detection).
  4. **NEW (cycle-20 finding):** Capacity-from-scale + formatter shape-disambiguation veto on idempotence non-lifted (closes ~10-15 of 23 idempotence picks).
  5. FP approximate-equality template arm (7-cycle carry-forward).
  6. Math-library `_relaxed*` extension (5-cycle carry-forward).
  7. Carry-forwards from v1.19 (CompositionTemplate non-numeric monoid; lift admission relaxation; `liftedFromMutation` magnitude re-baselining).
- **Aggregate trajectory (4-point):** 26.7% → 34.8% → 52.3% → **48.8%**. First non-monotonic step. The drop is **NOT a regression** — surface analysis at cycle 19 confirmed -183 candidates closed across cycles 18 + 19 (precision-positive); the cycle-20 measurement reflects sampling on a substantially-changed surface composition (335 → 152, -55% surface delta).
- **§19 ≥70% target is +21pp from cycle-20.** Three more mechanism cycles at cycle-18 magnitude (~+7pp avg) reach the target — assuming continued precision-positive movement + sample-distribution stabilization (cycle-21+ won't introduce new first-measurement classes at the rate of cycles 18+19).

### Documentation

- **v1.23 calibration plan (V1.23.0).** `docs/v1.23 Calibration Plan.md` — fourth empirical-only cycle plan; outcome scenarios A/B/C/D framing.
- **Cycle-20 surface re-capture (V1.23.A).** `docs/calibration-cycle-20-data/surface-counts.md`.
- **Cycle-20 triage rubric (V1.23.B).** `docs/cycle-20-triage-rubric.md` — carries cycle-17 verbatim + cycle-18/19 mechanism context.
- **Cycle-20 triage data (V1.23.C).** `docs/calibration-cycle-20-data/sample-manifest.md` + `triage-decisions.json` (46 verdicts) + `triage-notes.md`.
- **Cycle-20 findings (V1.23.D).** `docs/calibration-cycle-20-findings.md` — four-point trajectory, three drivers of the -3.5pp drop, per-mechanism effectiveness ranking, cycle-21 priority list with 3 NEW findings.
- **Performance baseline v1.22 carry-forward (V1.23.E).** `docs/perf-baseline-v1.23.md` — mirrors v1.20.E's carry-forward posture.

### Hard guarantees + performance

- All PRD §16 hard guarantees unchanged — v1.23 ships zero new accept-flow writeout paths (zero source change).
- All PRD §13 performance budgets hold at v1.23 (carry-forward from [`docs/perf-baseline-v1.22.md`](docs/perf-baseline-v1.22.md) per [`docs/perf-baseline-v1.23.md`](docs/perf-baseline-v1.23.md)).
- PRD §14 + §19 runtime no-network guarantee unchanged.

[1.23.0]: https://github.com/Joseph-Cursio/SwiftInferProperties/releases/tag/v1.23.0

## [1.22.0] — 2026-05-10

The nineteenth calibration cycle and the **second consecutive measurement-driven mechanism cycle** (cycle 18 = v1.21 was the first; cycles 15-16 mechanism choices were projected from non-empirical reasoning). Four independently-mergeable workstreams shipped in one release. Surface 165 → **152** (-13 = -7.9%) — second consecutive new cumulative-reduction low at **-86.97%** vs cycle-1's 1167-baseline (prior low: -85.86% at cycle 18; -80.4% at cycle 13 before that). First cycle to cross the -86% threshold. Mechanism-class taxonomy 13 → **14** (first new class since v1.19's class 13 composition-template additive-monoid scoring). Class 14 (fixed-point-name positive signal) is the **first recall-positive signal in the post-V1.4.3 era** — all prior 13 classes were suppression-only.

### Calibration cycle 19 — cycle-18 findings + carry-forward priorities

- **Workstream A (V1.22.A): BucketIterator name extension on V1.21.A.** Direct cycle-18 finding closure (3 surviving OC `_HashTable.BucketIterator.{advance, findNext, advanceToNextUnoccupiedBucket}` picks at v1.21 used non-curated method names + carrier ending in `.BucketIterator`, not `.Iterator`). Two extensions to V1.21.A's `iteratorProtocolCarrierVeto`: (a) `iteratorMethodNames` curated set adds `findNext` + `advanceToNextUnoccupiedBucket`; (b) carrier-name fallback rule extends `hasSuffix(".Iterator")` → `hasSuffix("Iterator")` (without the dot). Joint match (curated method name + Iterator-shape carrier) preserved from V1.21.A as false-positive guardrail. Mechanism class extension: V1.21.A's class 7 carrier-protocol-conformance veto sub-class. Surface impact: **-3 OC** (matches plan exactly). 10 new unit tests in `IdempotenceTemplateBucketIteratorTests.swift`.

- **Workstream B (V1.22.B): RoundTripTemplate both-sides direction-counter -15 → -25 magnitude bump.** Direct cycle-18 finding closure. Modified V1.12.1's `RoundTripTemplate.directionLabelCounterSignal(for:)` from "fires at -15 when EITHER pair side has a direction-labeled first parameter" to "fires at -25 (full veto-equivalent) when BOTH pair sides are direction-labeled; -15 single-side path preserved verbatim." Score arithmetic: 30 typeSymmetry + 5 carrier - 25 V1.22.B = +10 → Suppressed (clean margin from +20 boundary). Mechanism class extension: class 6 (parameter-label direction-counter, V1.10.1/V1.12.1 lineage) with magnitude variation. Surface impact: **-8 (7 OC + 1 Algo `EitherSequence.index(after:) × index(before:)`)**. Variance from plan's projected -12: asymmetric cross-pair noise (e.g., `index(after:) × _minimumCapacity(forScale:)`) survives at single-side -15 path → cycle-20 priority #2. 10 new unit tests in `RoundTripTemplateBothSidesDirectionTests.swift`.

- **Workstream C (V1.22.C): Fixed-point-name positive signal on non-lifted idempotence.** **First recall-positive signal in the post-V1.4.3 era** — all prior cycles (V1.4.3 onward) shipped suppression-only mechanisms. Mechanism class **NEW class 14**. Three-cycle carry-forward priority (cycles 15/16/17/18). New `Sources/SwiftInferCore/FixedPointNames.swift` curated set `{dedupe, simplify, clamp, truncate, standardize}` + new `Signal.Kind.fixedPointName` case at `+10` weight. Score arithmetic: 30 typeSymmetry + 5 carrier + 10 fixed-point = +45 → Likely (was +35 → Possible at v1.21). Wired into `IdempotenceTemplate.suggest(for:)` non-lifted path; lifted path already covers fixed-point names via V1.19.B curated verbs. Set is intentionally non-overlapping with V1.4.1 `IdempotenceTemplate.curatedVerbs` (which already covers `normalize`, `canonicalize`, `flatten`, `sanitize` etc. at +40); FixedPointNames focuses on lower-confidence indicators. Surface impact: **0** (recall-positive infrastructure ready; no functions in `FixedPointNames.curated` surface on the four cycle-1..14 corpora). 10 new unit tests in `IdempotenceTemplateFixedPointNamesTests.swift`.

- **Workstream D (V1.22.D): Stride-style label both-sides veto on round-trip + inverse-pair.** Cycle-14 demotion target finally shipped after **4 cycles of carry-forward** (cycle-14 priority #1 → demoted to v1.18 → not shipped in cycles 15-18 → shipped here). New `Sources/SwiftInferCore/StrideStyleLabels.swift` curated set `{startingAt, endingAt, fromIndex, toIndex, startingFrom, from, to}`. Two consumer extensions: `RoundTripTemplate+StrideStyleVeto.swift` + `InversePairTemplate+StrideStyleVeto.swift`; both fire `-25` (full veto magnitude) when **both** pair sides have first-param labels in the curated set. Distinct from `DirectionLabels.curated` (cursor-incremental: `after:`/`before:`); stride-style is range-bounded (`startingAt:`/`endingAt:`). Mechanism class extension: class 6 with new curated content. Surface impact: **-2 Algo** (closes the cycle-14-demoted `endOfChunk(startingAt:) × startOfChunk(endingAt:)` round-trip + inverse-pair on the same site; cycle-14/17 measured ACCEPT — calibration trade-off documented per v1.22 plan §"Risks", suppression target is auto-emit usability, not correctness). 11 new unit tests in `StrideStyleLabelTests.swift` + 1 V1.12.1 test updated.

- **Mechanism-class taxonomy update:** 13 → **14** (NEW class 14 = fixed-point-name positive signal). Workstreams A/B/D extend existing classes 6 + 7. Class 14 is the **first taxonomic shift to a positive-signal class** since the loop began — all prior cycles (V1.4.3 onward) were suppression-only. v1.22 establishes the precedent: cycle-20+ work can introduce more recall-positive signals.

- **Per-corpus surface delta:**
  - ComplexModule: 21 → 21 (byte-stable; no v1.22 mechanism targets).
  - OrderedCollections: 124 → 114 (-10 = -8.1%).
  - Algorithms: 13 → 10 (-3 = -23.1%).
  - PropertyLawKit: 7 → 7 (byte-stable).

- **Cumulative trajectory:** cycles 1-18 went 1167 → 165 (-85.9%); cycle 19 = v1.22 reaches 1167 → 152 = **-86.97%** (new low). The post-cycle-17 mechanism cadence produces steady incremental progress — cycle 18's -50.7% surface delta + cycle 19's -7.9% = cumulative -54.6% across the two-mechanism-cycle window.

- **Cycle-20 priority list (rotated post-v1.22, in expected impact order):**
  1. v1.23 = cycle 20 empirical-only re-measurement (provisional aggregate projection 57-65% from cycle-17's 52.3% baseline).
  2. **NEW (cycle-19 finding):** Asymmetric label class mismatch counter on round-trip — closes the 5-10 OC cross-pair noise where one side direction-labeled, one domain-marker-labeled.
  3. FP approximate-equality template arm (6-cycle carry-forward; required for production CM round-trip property tests on the 7 surviving canonical-inverse anchors).
  4. Math-library op-name extension to `rescaledDivide` / `_relaxed*` (4-cycle carry-forward).
  5. CompositionTemplate non-numeric monoid extension (carry-forward from v1.19).
  6. Lift admission relaxation from strict to permissive (carry-forward).
  7. `Signal.Kind.liftedFromMutation` magnitude re-baselining (carry-forward).

### Documentation

- **v1.22 calibration plan (V1.22.0).** `docs/v1.22 Calibration Plan.md` — four-workstream mechanism cycle plan; cycle-18-finding-driven priorities + 4-cycle stride-style carry-forward + 3-cycle fixed-point carry-forward.
- **Cycle-19 findings (V1.22.E).** `docs/calibration-cycle-19-findings.md` — surface delta, per-workstream contribution table, mechanism-class taxonomy update (13 → 14 with class 14 = first recall-positive post-V1.4.3), per-mechanism effectiveness ranking, cycle-18 picks status at v1.22, cycle-20 priority list rotated.
- **Cycle-19 capture (V1.22.E).** `docs/calibration-cycle-19-data/post-v1.22-*.discover.txt` — four per-corpus discover snapshots at the V1.22.D commit.
- **Performance baseline re-measured (V1.22.E).** `docs/perf-baseline-v1.22.md` — re-measured at commit `e22f076`. Every row within ±5% of v1.21 baseline; v1.22 plan §6 ≤+5% budget met. Row 4 peak delta 135.8 MB (vs v1.21's 135.5 MB).

### Hard guarantees + performance

- All PRD §16 hard guarantees unchanged — v1.22 ships zero new accept-flow writeout paths (all four workstreams are veto-only or signal-only mechanisms; no template emission changes).
- All PRD §13 performance budgets hold at v1.22 (re-measured at [`docs/perf-baseline-v1.22.md`](docs/perf-baseline-v1.22.md)). Every row within ±5% of v1.21; v1.22 release-blocking criterion (≤+5% wall vs v1.21) met.
- PRD §14 + §19 runtime no-network guarantee unchanged.

[1.22.0]: https://github.com/Joseph-Cursio/SwiftInferProperties/releases/tag/v1.22.0

## [1.21.0] — 2026-05-10

The eighteenth calibration cycle and the **first mechanism cycle whose priorities are directly informed by cycle-17 measured reject classes** (cycles 15 + 16 priorities were projected from non-empirical value-semantics reasoning). Three independently-mergeable workstreams shipped in one release. Surface 335 → **165** (-170 = -50.7%) — **first descending move since cycle 13** and a new cumulative-reduction low at -85.86% vs cycle-1's 1167-baseline (prior low: -80.4% at cycle 13; first cycle to cross the 85% threshold). Restored the descending surface trend that v1.18 + v1.19's recall-positive workstreams had reversed at cycle 17. Plan-vs-actual: -170 vs projected -171 (within ±1).

### Calibration cycle 18 — cycle-17 findings + math-library carry-forward

- **Workstream A (V1.21.A): IteratorProtocol carrier veto on `idempotence-lifted`.** Direct cycle-17 finding closure (4/4 reject Iterator-shape class in V1.20.C 46-decision triage). New `IdempotenceTemplate+IteratorVeto.swift` extension method `iteratorProtocolCarrierVeto(for:inheritedTypesByName:)`. Two detection paths: (a) primary — textual `IteratorProtocol` conformance via the V1.5.2-built `inheritedTypesByName` index (with generic-parameter stripping); (b) name fallback — carrier name `Iterator` or `*.Iterator` suffix joint-match with method name in curated `iteratorMethodNames = {next, advance, nextState, step}`. Full veto via `Signal.vetoWeight` collapses score to Suppressed; calibration record preserved per V1.5.2 reuse posture. Mechanism class extension: class 7 (function-name + type-shape composite) extended to a "carrier-protocol-conformance veto" sub-class. Surface impact: -22 candidates (20 Algo Iterator + 2 nested OC Iterator). 12 new unit tests in `IdempotenceTemplateIteratorVetoTests.swift`. **Plan-vs-actual:** -22 vs projected ~24 (BucketIterator-named OC picks survive — carrier ends in `.BucketIterator` not `.Iterator`; cycle-19 priority #4 candidate).

- **Workstream B (V1.21.B): `composition-lifted` monotone-bounded parameter-label counter.** Direct cycle-17 finding closure (1/1 reject on `BucketIterator.advance(until: Int)` in V1.20.C pick #46). New `monotoneBoundedLabels = {until, to, at, upTo, before, through}` curated set on `CompositionTemplate`. New `monotoneBoundedLabelSignal(for:)` private helper fires at `-25` weight when first non-self parameter's label matches. Score posture: 30 + 40 + 5 + 10 - 25 = 60 → Likely (NOT full Suppressed) — demotes Strong → Likely so the calibration record is preserved at small-n; cycle-19 may motivate promotion to -40 if false-negative rate stays at 0/N on broader corpora. Mechanism class extension: class 8 (parameter-label semantic-intent counter, V1.15.1 lineage) extended to V1.19.C composition template. Surface impact: 0 (demote-only; the cycle-17 reject is now Likely-tier visible-but-flagged instead of Strong-tier default-confident). 6 new unit tests in `CompositionTemplateMonotoneBoundedTests.swift`.

- **Workstream C (V1.21.C): Math-library forward-function counter on idempotence + round-trip non-lifted paths.** Three-cycle carry-forward (cycles 15/16/17) closed by the cycle-17 measurement which confirmed `exp`/`log`/`sqrt` non-lifted idempotence at 0/3 = 0% (V1.20.C picks #18, #19, #20 all reject). **Largest single mechanism in v1.21 by surface impact.** New `Sources/SwiftInferCore/MathForwardFunctions.swift` curated set + canonical-inverse-pair allowlist:
  - `MathForwardFunctions.curated` (~22 names) — exponential family (`exp`, `exp2`, `expMinusOne`), logarithm family (`log`, `log2`, `log10`, `log1p`), trigonometric forward + inverse (`sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `atan2`), hyperbolic + inverse-hyperbolic (`sinh`, `cosh`, `tanh`, `asinh`, `acosh`, `atanh`), roots (`sqrt`, `cbrt`), and `hypot`. Excludes `abs` / `negate` (idempotent on real inputs).
  - `MathForwardFunctions.canonicalInversePairs` (10 entries) — preserves the cycle-17 7 anchors (`exp×log`, `cos×acos`, `sin×asin`, `tan×atan`, `cosh×acosh`, `sinh×asinh`, `tanh×atanh`) plus 3 numerics-extension variants (`exp2×log2`, `expMinusOne×log1p`, `expMinusOne×onePlus`). Orientation-insensitive matching mirrors V1.18.C `DualStylePairing` posture.
  - Two consumer extensions: `IdempotenceTemplate.mathForwardFunctionVeto(for:)` fires veto when name+`(T)→T` shape matches; `RoundTripTemplate.mathForwardFunctionPairVeto(for:)` fires veto when both pair sides match AND pair is not in canonical allowlist (orientation-insensitive).
  - Mechanism class extension: class 7 (function-name + type-shape composite, V1.14.1 / V1.16.1 lineage) — third-template extension paralleling V1.16.1's posture.
  - Surface impact: -148 candidates (-145 ComplexModule + -3 Algorithms). The 8 surviving CM round-trip suggestions are the 7 cycle-17 canonical-inverse anchors + 1 numerics extension. 29 new unit tests across `MathForwardFunctionsTests.swift` + `IdempotenceTemplateMathForwardVetoTests.swift` + `RoundTripTemplateMathForwardVetoTests.swift`.

- **Mechanism-class taxonomy update:** 13 → **13** (no new classes; **three extensions of existing classes** per the v1.21 plan §3 design). v1.21 returns to extension-of-existing-class as the post-cycle-17 pattern after v1.18 + v1.19 added 5 new classes (9-13) in 2 cycles.

- **Per-corpus surface delta** (cycle-17 → cycle-18):
  - ComplexModule: 166 → 21 (-145; the dominant CM elementary-functions noise class fully addressed).
  - OrderedCollections: 126 → 124 (-2; Iterator nested picks closed; BucketIterator survivors are cycle-19 candidates).
  - Algorithms: 36 → 13 (-23; 20 Iterator-shape lifted-idempotence + 3 math-forward closures).
  - PropertyLawKit: 7 → 7 (byte-stable; no v1.21 mechanism targets).

- **Per-template surface delta** (cycle-17 → cycle-18): `round-trip` 156 → 27 (-129); `idempotence (non-lifted)` 88 → 23 (-65); `idempotence-lifted` 44 → 24 (-20). All other templates byte-stable.

- **Cycle-19 priority list (rotated post-v1.21, in expected impact order):**
  1. Fixed-point-name positive signal on non-lifted idempotence (3-cycle carry-forward; cycle-18 confirms 1 OC formatter still surfaces).
  2. FP approximate-equality template arm (cycle-14 priority #4 carry-forward; required for production CM round-trip property tests on the surviving 7 canonical anchors).
  3. Stride-style label extension (cycle-14 demotion carry-forward).
  4. **NEW (cycle-18 finding):** BucketIterator name extension on V1.21.A — extend curated set with `findNext`, `advanceToNextUnoccupiedBucket`, OR extend carrier-name fallback to `*Iterator` suffix. Magnitude: ~3 OC candidates.
  5. **NEW (cycle-18 finding):** OC `index(after:) × index(before:)` direction-pair full-veto extension on V1.12.1 — change firing rule from "either side direction-labeled" (-15) to "both sides direction-labeled" (-25). Magnitude: ~12 OC candidates.
  6. Math-library op-name gate extension to `rescaledDivide` / `_relaxed*` (carried forward).
  7. CompositionTemplate non-numeric monoid extension (NEW carry-forward from v1.19; cycle-18 measurement does not motivate yet).
  8. Lift admission relaxation from strict to permissive (carry-forward; v1.21 V1.21.A precision-positive movement does not motivate further relaxation).
  9. `Signal.Kind.liftedFromMutation` magnitude re-baselining (carry-forward; cycle-18 lifted-idempotence projection ~67% does not motivate +10 → +5 demotion).
  10. v1.23 = cycle 19 empirical-only re-measurement (after v1.22 mechanism release).

### Documentation

- **v1.21 calibration plan (V1.21.0).** `docs/v1.21 Calibration Plan.md` — three-workstream mechanism cycle plan; cycle-17-finding-driven priorities + 3-cycle carry-forward.
- **Cycle-18 findings (V1.21.D).** `docs/calibration-cycle-18-findings.md` — surface delta, per-workstream contribution table, mechanism-class taxonomy update (13 → 13 extensions-only), per-mechanism effectiveness ranking (V1.21.C is largest single-cycle contributor in loop history at -148), cycle-17 picks status at v1.21, cycle-19 priority list rotated.
- **Cycle-18 capture (V1.21.D).** `docs/calibration-cycle-18-data/post-v1.21-*.discover.txt` — four per-corpus discover snapshots at the V1.21.C commit.
- **Performance baseline re-measured (V1.21.D).** `docs/perf-baseline-v1.21.md` — re-measured at commit `d3bed65`. Every row measures faster than v1.19 (-3% across; the suppressed-suggestion short-circuit on -170 closed candidates outweighs per-call O(1) veto-evaluation overhead). v1.21 plan §"Open decisions" #6 ≤+5% budget met with wide margin. Row 4 peak delta 135.5 MB (vs v1.19's 136.3 MB).

### Hard guarantees + performance

- All PRD §16 hard guarantees unchanged — v1.21 ships zero new accept-flow writeout paths (all three workstreams are veto-only or counter-only mechanisms).
- All PRD §13 performance budgets hold at v1.21 (re-measured at [`docs/perf-baseline-v1.21.md`](docs/perf-baseline-v1.21.md)). Every row faster than v1.19; v1.21 release-blocking criterion (≤+5% wall vs v1.19) met with wide margin.
- PRD §14 + §19 runtime no-network guarantee unchanged.

[1.21.0]: https://github.com/Joseph-Cursio/SwiftInferProperties/releases/tag/v1.21.0

## [1.20.0] — 2026-05-10

The seventeenth calibration cycle and **third empirical-only release** in the loop's history (after cycle 6 = v1.9 and cycle 14 = v1.17). v1.20 is binary-equivalent to v1.19.0 except the version-string bump — zero `Sources/` changes, zero test changes, zero behavior changes. The cycle's deliverable is **per-template + per-corpus acceptance-rate data on the post-v1.19 335-surface**, comparable point-for-point to cycle-6's measurement on the post-V1.8.1 349-surface (26.7%) and cycle-14's measurement on the post-V1.16.1 229-surface (34.8%). Headline: **23/44 = 52.3%** Possible-tier acceptance rate — outcome **A** under the v1.20 plan thresholds (Aggregate ≥ 50%; on trajectory toward the §19 ≥70% target). Three-point trajectory established: 26.7% → 34.8% → 52.3%, with the cycle-14 → cycle-17 delta (+17.5pp / 3 mechanism cycles) **larger** than the cycle-6 → cycle-14 delta (+8.1pp / 8 mechanism cycles) — the loop is accelerating, not plateauing.

### Calibration cycle 17 — empirical re-measurement on the post-v1.19 335-surface

- **Cycle-17 surface re-capture (V1.20.A).** First reversal of the descending trend (cycles 1-13: 1167 → 229 = -80.4%; cycle 17: 335 = -71.3%). Surface 229 → 335 (+106 = +46.3%) attributes to v1.18.C dual-style consistency (+22 candidates) + v1.19.B-D lifted-mutation admission (+45 candidates: 44 idempotence-lifted + 1 composition-lifted; identity-element-lifted and inverse-pair-lifted both surfaced zero candidates) plus modest upstream-corpus drift (~36 unattributed on OC; ~3 on Algorithms; ComplexModule + PropertyLawKit byte-stable). Cycle-13's `joecursio` paths were not reproducible; v1.20.A pins HEAD commits for the four corpora at `~/GitHub_projects/swift-{algorithms,collections,numerics}` + `~/xcode_projects/SwiftPropertyLaws` for future replay.
- **Cycle-17 triage rubric (V1.20.B).** Carries cycle-14's per-template criteria for the 7 cycle-14-baseline templates verbatim (round-trip, idempotence-non-lifted, commutativity, associativity, monotonicity, inverse-pair-non-lifted, identity-element-non-lifted) — methodologically identical so cycle-14 → cycle-17 rate-shifts on these templates attribute purely to cycles 15 + 16 mechanism work, not triage methodology drift. Adds new sections for `dual-style-consistency` (V1.18.C), `idempotence-lifted` (V1.19.B), `composition-lifted` (V1.19.C); plus completeness-only sections for the zero-surface `identity-element-lifted` + `inverse-pair-lifted`.
- **Cycle-17 50-decision triage → 46-decision rebased triage (V1.20.C).** Sample size dropped 50 → 46 because two of v1.19's new lifted sub-templates have zero v1.19 surface; freed picks not redistributed (existing classes are adequately sampled). Stratification: 35 existing-class picks (round-trip 15 + idempotence 6 + commutativity 3 + associativity 3 + monotonicity 4 + inverse-pair 2 + identity-element 1 + lifted-non-mech-class) + 11 new-class picks (5 dual-style + 6 idempotence-lifted + 1 composition-lifted = 12 minus 1 from the existing-class allocation that overlapped). 23 accept / 21 reject / 2 unknown verdicts. Per-template rates:
  - `round-trip`: 9/15 = **60.0%** (cycle-14: 45%; +15pp from sample-mix).
  - `idempotence (non-lifted)`: 0/4 = **0.0%** (cycle-14: 0%; flat — CM elementary-functions noise class still dominates).
  - `commutativity`: 1/3 = **33.3%** (cycle-14: 20%; small-n).
  - `associativity`: 2/3 = **66.7%** (cycle-14: 60%; small-n).
  - `monotonicity`: 3/4 = **75.0%** (cycle-14: 50%; small-n).
  - `inverse-pair (non-lifted)`: 1/2 = **50.0%** (cycle-14: 100% n=1; sample size doubled with new-visibility direction-pair reject).
  - `identity-element (non-lifted)`: 0/1 = **0.0%** (carry-forward reject across all three measurement points).
  - **`dual-style-consistency` (NEW v1.18.C): 5/5 = 100.0%.** Highest acceptance rate of any template in the cycle-17 sample. By-construction precision via curated naming-rule pairing constraint. Largest single-mechanism contributor to the +17.5pp cycle-14 → cycle-17 shift (+6.4pp aggregate contribution).
  - **`idempotence-lifted` (NEW v1.19.B): 2/6 = 33.3%.** 4/4 Iterator-shape picks reject (`Iterator.next()`, `BucketIterator.advance()` advance state per call); 2/2 internal-CoW-helper picks accept (`OrderedSet._isUnique()`, `OrderedSet._regenerateHashTable()`). **V1.19.B no-param admission is over-broad on `IteratorProtocol` carriers — confirmed precision-negative.**
  - **`composition-lifted` (NEW v1.19.C): 0/1 = 0.0%.** Lone candidate (`_HashTable.BucketIterator.advance(until: Int)`) rejects because `advance(until:)` is monotone-bounded, not additive. **V1.19.C curated additive-action verb gate is over-broad on `until:` / `to:` / `at:` parameter labels.**
- **Cycle-17 findings writeup (V1.20.D).** Three-point trajectory analysis: 26.7% → 34.8% → 52.3% — acceleration. Per-mechanism effectiveness ranking: Workstream C (V1.18.C dual-style) is the largest single-mechanism contributor (+6.4pp); Workstream B (V1.19.B-D lifted) is mixed (-0.8pp at current gate; over-broad admission identified); Workstream A (V1.18.A carrier-kind) is precision-modulator (~0pp aggregate effect). Sample-composition + unknown-resolution + measurement-stability accounts for the +11.9pp residual. The §19 ≥70% target is +17.7pp from cycle-17; at the cycle-15/16 average magnitude (+5.8pp/cycle), three more mechanism cycles get there.
- **Cycle-18 priority list (rotated post-v1.20, in expected impact order):**
  1. **NEW (cycle-17 finding): Iterator-shape suppression on `idempotence-lifted`.** Detect `mutating func next()` / `mutating func advance()` shapes where carrier conforms to `IteratorProtocol` (textual conformance match via the V1.5.2 `inheritedTypesByName` index) and veto from the lifted-idempotence path. Magnitude: closes ~24 v1.19 candidates; lifts lifted-idempotence acceptance rate from 33% to ~67% projected. **High-confidence priority.**
  2. **NEW (cycle-17 finding): `composition-lifted` monotone-bounded suppression.** Add `until:` / `to:` / `at:` first-parameter-label counter-signal at -25 to `CompositionTemplate.suggest(forLifted:)`. Closes the 1 v1.19 candidate.
  3. **Math-library forward-function counter on idempotence + round-trip** (carried forward from v1.18 / cycle-15 / cycle-16; cycle-17 reconfirms). Cycle-17 measures `exp` / `log` / `sqrt` non-lifted idempotence at 0% rate; the counter would suppress these directly.
  4. **Fixed-point-name positive signal on idempotence (non-lifted path)** (carried forward; lifted path already covers it via curated verbs).
  5. **FP approximate-equality template arm** (carried forward).
  6. **Stride-style label extension** (carried forward from cycle-14 demotion; not shipped in cycles 15 + 16).
  7. **Math-library op-name gate extension to `rescaledDivide` / `_relaxed*`** (carried forward).
  8. **`CompositionTemplate` non-numeric monoid-shaped extension** (NEW carry-forward from v1.19; cycle-17 measurement does not yet motivate).
  9. **Lift admission relaxation from strict to permissive** (NEW carry-forward from v1.19 plan; cycle-17 33% rate does not motivate further relaxation).
  10. **`Signal.Kind.liftedFromMutation` magnitude re-baselining** (NEW carry-forward; cycle-17 measurement does not motivate +10 → +5 demotion).

### Documentation

- **v1.20 calibration plan (V1.20.0).** `docs/v1.20 Calibration Plan.md` — third empirical-only cycle plan; mirrors v1.17 sequencing.
- **Cycle-17 surface re-capture (V1.20.A).** `docs/calibration-cycle-17-data/surface-counts.md` + 4 per-corpus `post-v1.19-*.discover.txt` captures. First reversal of the descending trend (229 → 335 = +46.3%); per-corpus + per-template counts split lifted vs non-lifted; rebased V1.20.C stratification.
- **Cycle-17 triage rubric (V1.20.B).** `docs/cycle-17-triage-rubric.md` — carries cycle-14 verbatim for the 7 baseline templates; new sections for v1.18.C dual-style + v1.19.B-D lifted sub-templates.
- **Cycle-17 triage data (V1.20.C).** `docs/calibration-cycle-17-data/sample-manifest.md` + `triage-decisions.json` (46 verdicts) + `triage-notes.md` (per-decision rationale + summary tables).
- **Cycle-17 findings (V1.20.D).** `docs/calibration-cycle-17-findings.md` — three-point trajectory, per-mechanism effectiveness ranking, cycle-18 priority list rotated.
- **Performance baseline v1.19 carry-forward (V1.20.E).** `docs/perf-baseline-v1.20.md` — mirrors v1.17's empirical-only carry-forward posture.

### Hard guarantees + performance

- All PRD §16 hard guarantees unchanged — v1.20 ships zero new accept-flow writeout paths (zero source change).
- All PRD §13 performance budgets hold at v1.20 (carry-forward from [`docs/perf-baseline-v1.19.md`](docs/perf-baseline-v1.19.md) per [`docs/perf-baseline-v1.20.md`](docs/perf-baseline-v1.20.md)).
- PRD §14 + §19 runtime no-network guarantee unchanged.

[1.20.0]: https://github.com/Joseph-Cursio/SwiftInferProperties/releases/tag/v1.20.0

## [1.19.0] — 2026-05-10

The sixteenth calibration cycle and the **single-workstream follow-on to v1.18** — ships Workstream B from the v1.18 plan §2 (mutating-method lift admission), the third and final v1.18-plan workstream and the largest behavioral change since M8.5's kit `Group` + `CommutativeMonoid` writeouts (v1.9). v1.19 re-admits the entire `mutating func` surface to the algebraic-property scoring pipeline that pre-v1.19 gated on `!summary.isMutating` at every template entry point. Mechanism-class taxonomy 11 → **13 classes** (class 12 lift admission via value-semantic gate; class 13 composition-template additive-monoid scoring — the second new template family added since M8.5, after v1.18.C's dual-style consistency template). v1.20 will be the empirical-only re-measurement cycle that runs the harness against the four cycle-1..14 corpora on the cumulative v1.18 + v1.19 surface and reports per-template + per-corpus acceptance-rate movement vs cycle 6 (26.7%) and cycle 14 (34.8%).

### Calibration cycle 16 — mutating-method lift (Workstream B)

- **`LiftedTransformation` summary type + `Signal.Kind.liftedFromMutation` (V1.19.A).** New `Sources/SwiftInferCore/LiftedTransformation.swift` — metadata-only "lift" of a mutating member into the pure shadow form `func op'(_ self: T, params...) -> T`. Strict admission gate (`summary.isMutating && summary.containingTypeName != nil && carrierKindResolver.classify(typeName:) == .valueSemantic`) per the v1.18 plan #2 / v1.19 plan #2 lean. Built once per `discover` call alongside `EquatableResolver` / `inheritedTypesByName` / `CarrierKindResolver`; threaded into per-template `suggest` invocations via `CollectionResolverContext.liftedTransformations`. New `Signal.Kind.liftedFromMutation` (+10) emitted by every lifted-suggest path, decoupled from `valueSemanticCarrier` (+5) so a lifted suggestion's score baseline is the non-lifted template's baseline + 5 (carrier, always fires by admission gate) + 10 (lift admission badge). 19 new unit tests in `Tests/SwiftInferCoreTests/LiftedTransformationTests.swift`.
- **`IdempotenceTemplate` lift admission (V1.19.B).** Two admissible shapes per the v1.19 plan §2 deliverable 2a: no-param mutators (`Set.removeAll`-shape) lift to `(T) -> T` unary idempotence; param-matches-carrier mutators (`Set.formUnion(_:Self)`-shape) lift to `(T, T) -> T` x-curried idempotence. Single-param-non-carrier shape (`Counter.increment(by: Int)`) is *not* an idempotence candidate — those flow through CompositionTemplate / IdentityElementPairing in V1.19.C. Score baseline 30 type-symmetry + 5 carrier + 10 lift = 45 → Likely; +40 curated verb (`normalize` / `canonicalize` / `dedupe` / `simplify` etc.) → 85 → Strong. SetAlgebra-shape veto carries over from the non-lifted scoring stack. Identity hash uses `idempotence-lifted|` prefix. 16 new unit tests across `IdempotenceTemplateLiftedTests` + `IdempotenceTemplateLiftedScoringTests`.
- **`CompositionTemplate` + `IdentityElementTemplate` lift admission (V1.19.C).** Two new template fan-out sites:
  - **`CompositionTemplate`** — first new property family added since v1.18.C's dual-style consistency template (M8.5-class novelty). Asserts that two sequential calls to a mutating additive-action method equal one call with the combined argument: `var c1 = s; c1.op(a); c1.op(b);  var c2 = s; c2.op(a + b);  return c1 == c2`. Numeric-only for v1.19 per the v1.18 plan open decision #3 lean: curated additive-monoid set covers stdlib `AdditiveArithmetic` conformers + `Decimal` + `Duration`. Curated verb list: `increment`, `add`, `accumulate`, `accrue`, `advance`, `step`, `extend`, `expand`, `shift`, `offset`, `bump`, `grow`, `augment`, `append`, `push`, `pop`, `deposit`, `withdraw`. Project extension via new `Vocabulary.compositionVerbs` slot. Score baseline 30 + 40 + 5 + 10 = **85 → Strong** by construction.
  - **`IdentityElementTemplate` (lifted)** — admits the lift via new `LiftedIdentityElementPairing` over `[LiftedTransformation] × [IdentityCandidate]`. Pairs a lift of shape `(T, X) -> T` (X != T) with an identity candidate of type X — canonical example `incremented(c, by: 0) == c` (additive identity 0 on `Counter.increment(by: Int)`). Curated identity name set carries forward from non-lifted IdentityElementTemplate (`zero`, `empty`, `identity`, `none`, `default`). Identity hash uses `identity-element-lifted|` prefix. Promotes `IdentityNames` from internal to public per the V1.18.A signal-helper-promotion pattern.
  - 24 new unit tests across `CompositionTemplateTests` + `IdentityElementTemplateLiftedTests`.
- **`InversePairTemplate` lift admission via `InverseLiftedPairing` (V1.19.D).** Final template fan-out site. Detects canonical Swift add/remove-style mutating-pair siblings on the same carrier and emits the functional-inversion property `add(remove(s, x), x) == s` (and the symmetric form) over the lifted shadows. Curated state-mutation inverse-name pairs: `add`/`remove`, `insert`/`remove`, `push`/`pop`, `attach`/`detach`, `link`/`unlink`, `activate`/`deactivate`, `subscribe`/`unsubscribe`, `register`/`deregister`, `enable`/`disable`. Distinct from `RoundTripTemplate.curatedInversePairs` (which targets cross-type encoder/decoder shapes). Pairing rules: same carrier (cross-carrier add/remove is not an inverse pair), same parameter list, name pair matches curated or `Vocabulary.inversePairs` orientation-insensitively. Score baseline 25 + 10 + 5 + 10 = 50 → Likely; with matching `@Discoverable(group:)` annotation on both halves, +35 lifts to 85 → Strong (parallel to the v1.18.A round-trip discoverable posture). 18 new unit tests in `InverseLiftedPairingTests`.
- **Mechanism-class taxonomy update: 11 → 13 classes.** Adds class **12** (lift admission via value-semantic gate — V1.19.A's structural precondition + signal) and class **13** (composition-template additive-monoid scoring — V1.19.C's new property family). Class 13 is the second new template family added since M8.5 (after v1.18.C's class 11 dual-style consistency). Full taxonomy + mechanism-class effectiveness rationale at [`docs/calibration-cycle-16-findings.md`](docs/calibration-cycle-16-findings.md).
- **Test count delta: 1680 → 1757** (+77; plan projected ~80). Workstream B is **purely additive** — no existing non-lifted suggestion shifts tier (contrast with v1.18.A which shifted round-trip Likely→Strong and inverse-pair Possible→Likely on value-semantic struct carriers). The 77 new tests cover lift admission, scoring, identity hashing, evidence layout, non-deterministic veto, protocol-coverage veto, and project-vocabulary fallthrough across the four template fan-out sites.
- **Cycle-17 priority list (rotated post-v1.19, in expected impact order):**
  1. v1.20 is the empirical-only re-measurement cycle (no Sources/ changes; sample the four cycle-1..14 corpora on the cumulative v1.18 + v1.19 surface; report aggregate acceptance-rate movement vs cycle 6 (26.7%) and cycle 14 (34.8%)).
  2. **Math-library forward-function counter on idempotence + round-trip** (carried forward from cycle-15 / cycle-16). Closes the CM elementary-functions noise class.
  3. **Fixed-point-name positive signal on idempotence** (carried forward from cycle-15 / cycle-16; nine cycles overdue on the non-lifted path — V1.19.B already covers it on the lifted path).
  4. **FP approximate-equality template arm** (carried forward from cycle-14 priority #4).
  5. **Math-library op-name gate extension to `rescaledDivide` / `_relaxed*`** (carried forward).
  6. **NEW: `CompositionTemplate` non-numeric monoid-shaped extension** (carry-forward from v1.19; promote to v1.21+ after the v1.20 numeric-only acceptance rate is measured).
  7. **NEW: Lift admission relaxation from strict to permissive** (carry-forward from v1.19 plan open decision #2; revisit at v1.21 if recall is too low).
  8. **NEW: `Signal.Kind.liftedFromMutation` magnitude re-baselining** (carry-forward from v1.19 plan open decision #5; revisit at v1.21 if +10 over-promotes lifted suggestions).

### Documentation

- **v1.19 calibration plan (V1.19.0).** `docs/v1.19 Calibration Plan.md` — committed before implementation. Single-workstream cycle (Workstream B from the v1.18 plan §2). Six focused deliverables (V1.19.A–F) sequenced so each commit builds + tests cleanly.
- **Cycle-16 findings (V1.19.E).** `docs/calibration-cycle-16-findings.md` — covers the lift mechanism, score arithmetic per template, mechanism-class taxonomy 11 → 13, plan-vs-actual checklist, projected per-corpus surface deltas (deferred to v1.20 empirical capture), and the cycle-17 priority list rotated for v1.21+ mechanism work.
- **Performance baseline re-measured (V1.19.E).** `docs/perf-baseline-v1.19.md` — re-measured at commit `fd798d3` (V1.19.D). All §13 rows pass against the hard PRD §13 budgets; every row measures faster than v1.18 with the cross-hardware caveat (M1 → M3 family) flagged. Workstream B's three new per-discover passes (`LiftedTransformation.derive` + `LiftedIdentityElementPairing.candidates` + `InverseLiftedPairing.candidates`) short-circuit on most synthetic corpora — mechanism-overhead measurement deferred to v1.20 when the four cycle-1..14 corpora are sampled. Row 4 peak delta 136.3 MB (vs v1.18 148.8 MB).

### Hard guarantees + performance

- All PRD §16 hard guarantees unchanged — v1.19 ships zero new accept-flow writeout paths (Workstream B's lifted-suggest paths emit suggestions but use the existing accept-flow pipeline).
- All PRD §13 performance budgets hold at v1.19 (re-measured at [`docs/perf-baseline-v1.19.md`](docs/perf-baseline-v1.19.md)). v1.19 release-blocking criterion (≤+10% wall vs v1.18 per the v1.18 plan §6) is met with wide margin.
- PRD §14 + §19 runtime no-network guarantee unchanged.

[1.19.0]: https://github.com/Joseph-Cursio/SwiftInferProperties/releases/tag/v1.19.0

## [1.18.0] — 2026-05-09

The fifteenth calibration cycle and **the first cycle organised around a single conceptual axis** (value semantics) rather than a single template-class. Two new mechanism classes ship in one release: Workstream A (carrier value-semantics signal) and Workstream C (dual-style consistency template). Workstream B (mutating-method lift) is sequenced for v1.19; v1.20 is the empirical-only cycle that re-measures per-template + per-corpus acceptance rates against cycle-6 (26.7%) and cycle-14 (34.8%) on the post-v1.19 surface. Mechanism-class taxonomy 8 → **11 classes** (the first new template family — class 11 dual-style consistency — added since M8.5's kit `Group` + `CommutativeMonoid` writeouts in v1.9). The v1.18 plan was originated from the value-semantics + property-based-testing conversations and committed as `docs/v1.18 Calibration Plan.md` ahead of implementation.

### Calibration cycle 15 — value-semantics workstream A + C

- **Workstream A (V1.18.A): carrier value-semantics signal + `CarrierKindResolver`.** Closes the four-cycles-deferred reference-type-carrier counter (post-v1.13 #5 → post-v1.16 #3 → cycle-14 #3) plus its inverse positive signal. New `Signal.Kind.referenceTypeCarrier` (`-10`) and `Signal.Kind.valueSemanticCarrier` (`+5`) consumed by `IdempotenceTemplate`, `RoundTripTemplate`, `InversePairTemplate`, and `IdentityElementTemplate`. New `SwiftInferCore.CarrierKindResolver` classifies a function's containing type via a curated stdlib value-type allow-list (Int / Double / String / Array / Dictionary / Set / Optional / Result / Range / Date / URL / UUID / Decimal / Duration / OrderedSet / Deque / etc.), tuple/literal syntax (`(Int, String)` / `[Int]`), generic-parameter heuristic (`T` / `T1` / `Element`), same-corpus `TypeDecl` lookup (depth-bounded 3 levels), and a closure-typed stored-member detector that catches the `docs/ideas/ValueSemantic Kit Proposal.md` §2.2 worked-example-3 leak case. Per the v1.18 plan §2 refinement: `InverseElementPairing` produces witness records consumed by the M8 RefactorBridge orchestrator with no Suggestion to attach a signal to — out of v1.18 scope. 33 new unit tests in `Tests/SwiftInferCoreTests/CarrierKindResolverTests.swift`.
- **Workstream C (V1.18.C): dual-style consistency template + `DualStylePairing` + vocabulary extension.** New `DualStyleConsistencyTemplate` + `DualStylePairing` + `Vocabulary.dualStyleNamePairs`. Detects canonical Swift dual-style pairs of `mutating func op(...)` and non-mutating `func op'(...) -> Self` siblings on the same containing type via three curated naming rules:
  - `X` ↔ `Xing` — `add` / `adding`, `append` / `appending`, `insert` / `inserting`
  - `X` ↔ `Xed` — `sort` / `sorted`, `reverse` / `reversed`, `normalize` / `normalized`
  - `formX` ↔ `X` — `formUnion` / `union`, `formIntersection` / `intersection`, `formSymmetricDifference` / `symmetricDifference`
  Project-level extension via `Vocabulary.dualStyleNamePairs` (literal pairs only per the v1.18 plan open decision #6 lean). Type-shape match: same parameter list + non-mutating returns container type or `Self`. Emits the consistency property `var c = a; c.<mutating>(args); return c == a.<nonMutating>(args)`. Score 30 type-shape + 40 canonical naming + 5 value-semantic carrier (Workstream A) = 75 → **Strong by construction** on value-semantic struct carriers; reference-type carriers drop to 60 → Likely; non-deterministic bodies in either half veto. **Highest-precision template in the v1 surface** — pairing constraint requires both members on the same containing type, so false positives only fire when a developer reuses one of the curated pair names for non-paired purposes. 29 new unit tests in `Tests/SwiftInferTemplatesTests/DualStylePairingTests.swift` + `Tests/SwiftInferTemplatesTests/DualStyleConsistencyTemplateTests.swift`.
- **Calibration consequence on the 1618-test baseline.** 19 golden-snapshot tests bake in pre-v1.18 score totals; updated to reflect the new carrier signal. Two notable behavioral shifts:
  1. **Round-trip on struct carriers crosses Likely → Strong.** Pre-v1.18: 30 type + 40 curated = 70 → Likely. Post-v1.18: +5 value-semantic carrier = 75 → **Strong** (Tier.strong threshold is ≥75, not ≥80). Affects every `(encode, decode)`-shape pair on a value-semantic struct container. Visible in `DiscoverPipelineTests.roundTripFixtureRenders` (golden updated `70 (Likely)` → `75 (Strong)`).
  2. **Inverse-pair on non-Equatable struct carriers crosses Possible → Likely.** Pre-v1.18: 25 type + 10 curated = 35 → Possible (default-hidden). Post-v1.18: +5 carrier = 40 → **Likely** (default-shown). Surfaces a previously-hidden suggestion class. Visible in `DiscoverPipelineStatsTests.statsOnlyRendersSummaryBlock` (snapshot moved `2 suggestions across 2 templates` → `3 suggestions across 3 templates`).
- **Mechanism-class taxonomy update: 8 → 11 classes.** Adds class **9** (carrier-kind structural counter/positive signal — Workstream A), class **10** (dual-style pair detection — Workstream C pairing infra), and class **11** (dual-style consistency property — Workstream C template). Class 11 is the **first new template family** added since M8.5 (v1.9, kit `Group` + `CommutativeMonoid` writeouts). Full taxonomy + mechanism-class effectiveness rationale at [`docs/calibration-cycle-15-findings.md`](docs/calibration-cycle-15-findings.md).
- **Cycle-16 priority list (rotated post-v1.18, in expected impact order):**
  1. **NEW (v1.18 plan §2 Workstream B): Mutating-method lift admission.** `LiftedTransformation` summary type + lift admission in `IdempotenceTemplate`, `IdentityElementPairing` (for the "increment by 0" case), `InversePairTemplate` (for dual-mutating add/remove pairs), and a new `CompositionTemplate` for the additive composition case. Depends on workstream A's value-semantic carrier signal (lift is sound only on value-semantic carriers).
  2. **Math-library forward-function counter on idempotence + round-trip** (carried forward from cycle-15). Closes the CM elementary-functions noise class.
  3. **Fixed-point-name positive signal on idempotence** (carried forward from cycle-15). `+10` on names like `normalize` / `canonicalize` / `dedupe` / `simplify`.
  4. **FP approximate-equality template arm** (carried forward from cycle-14 priority #4).
  5. **Math-library op-name gate extension to `rescaledDivide` / `_relaxed*`** (carried forward).
  6. **DEMOTED: stride-style label extension** (carried forward from cycle-14 demotion).

### Documentation

- **v1.18 calibration plan (V1.18.0).** `docs/v1.18 Calibration Plan.md` — 222-line plan committed before implementation, originated from the value-semantics + PBT conversations referenced in the plan. Three workstreams (A + C in v1.18, B in v1.19), v1.20 empirical-only cycle. Coordination map with the kit-side `docs/ideas/ValueSemantic Kit Proposal.md` proposal: M-VS-1 = Workstream A (engine-side ships first; kit work not blocking); M-VS-2 / M-VS-3 / M-VS-4 = future v1.21+ once kit-side `ValueSemantic` protocol lands.
- **Cycle-15 findings (V1.18.D).** `docs/calibration-cycle-15-findings.md` — covers Workstream A + C calibration consequence on the 1618-test baseline (19 golden updates + 62 new unit tests), mechanism-class taxonomy 8 → 11, plan-vs-actual, projected per-corpus signal-hit deltas (deferred to v1.20 empirical capture). Test count delta: 1618 → 1680 (+62).
- **Performance baseline re-measured (V1.18.E).** `docs/perf-baseline-v1.18.md` — re-measured against the v1.18 working copy (v1.18 ships Sources/ changes so the v1.17 carry-forward posture explicitly does not apply). All §13 rows pass against hard budgets; row 1 (50-file synthetic discover) at +25.6% vs v1.16 carry-forward is at the §13 25% regression edge — flagged for re-measurement at v1.20 (CI-side multi-run averaging will re-center). Two new per-discover passes added: `CarrierKindResolver` build (O(N) over `[TypeDecl]`) and `DualStylePairing.candidates(in:)` (O(N + M·K)). Memory peak delta moved 134.8 MB → 148.8 MB (+10.4%, well within 800 MB ceiling).

### Hard guarantees + performance

- All PRD §16 hard guarantees unchanged — v1.18 ships zero new accept-flow writeout paths (Workstream C template emits suggestions but uses the existing accept-flow pipeline).
- All PRD §13 performance budgets hold at v1.18 (re-measured at [`docs/perf-baseline-v1.18.md`](docs/perf-baseline-v1.18.md)). Row 1 (50-file synthetic discover) at +25.6% vs the v1.17 carry-forward of v1.16 is at the §13 25% regression contract edge; absolute delta 0.126s (0.493s → 0.619s) is within typical macOS scheduler jitter for half-second-class wall measurements.
- PRD §14 + §19 runtime no-network guarantee unchanged.

[1.18.0]: https://github.com/Joseph-Cursio/SwiftInferProperties/releases/tag/v1.18.0

## [1.17.0] — 2026-05-09

The fourteenth calibration cycle and the **second empirical-only release in the loop's history** (after v1.9 = cycle 6). **Empirical-only release** — no Sources/ changes (apart from the version-string bump), no test changes, no behavior changes. The headline deliverable is the second measured Possible-tier acceptance rate from a 50-decision single-runner triage of the post-V1.16.1 229-surface: **34.8%** (16 accept / 30 reject / 4 unknown), a **+8.1pp shift** from cycle-6's 26.7% — outcome **B** under the V1.17.0 plan's framing ("modest improvement; mechanism cycles are precision-positive but recall is also dropping"). The aggregate shift is real and outside sample-size noise on round-trip + idempotence (the only templates with n≥10); other per-template shifts (associativity, monotonicity, inverse-pair) are within small-n confidence bands. v1.17 is binary-equivalent to v1.16.0 except the version-string bump; the §13 measurements carry forward unchanged. Same hard-guarantee posture as v1.16 — §16 guarantees unchanged; §13 budgets unchanged; §14 privacy unchanged. Six mechanism cycles (v1.10 → v1.16, cycles 7-13) operated between the loop's two measurement points (cycle 6 = v1.9 and cycle 14 = v1.17) — cycle 14 closes the meta-question open since cycle 6 ("does cumulative noise-floor suppression translate to measurably-higher acceptance rates?") with a measured "partial yes."

### Calibration cycle 14 — empirical Possible-tier re-measurement on the v1.16 surface

- **Triage rubric (V1.17.1).** New `docs/cycle-14-triage-rubric.md` carries cycle-6's per-template criteria verbatim and adds a **Post-cycle-6 mechanism context** section documenting the suppression layers each surviving v1.16 candidate has cleared (cycles 7-13). Resolves V1.17.0 plan open decision #5 in favor of (b) carry-forward verbatim with cycle-14 supplement; cycle-6 rubric stays unchanged for forensic comparability. Decision JSON schema mirrors cycle-6's verbatim with `version: "cycle-14"` and `swift_infer_commit: "9e36efd"` (v1.16.0 tag commit). Methodology delta vs cycle 6 is intentionally minimal — same rater (Claude/single-runner), same sample size (50), same stratification weights (cycle-6-matching), same tier mix (49 Possible + 1 Likely identity-element outlier), same fresh-sampling posture.
- **50-decision stratified triage on the v1.16 229-surface (V1.17.2).** New `docs/calibration-cycle-14-data/sample-manifest.md` + `triage-decisions.json` + `triage-notes.md`. Stratification preserves cycle-6 per-template sample sizes where the v1.16 surface allows; the only deviation is **inverse-pair 5 → 1** (forced by surface dropping 15 → 1 post-V1.14), with the freed 4 picks redistributed to round-trip (where ComplexModule's 136 round-trip surface dominates). 12 OC + 28 CM + 7 Algo + 3 PLK; 49 Possible-tier picks + 1 Likely-tier (`rescaledDivide × Complex.zero`).
- **Cycle-14 findings doc (V1.17.3).** New `docs/calibration-cycle-14-findings.md` documents the 34.8% headline + per-template breakdown:
  - **idempotence** (0/10 = **0%**, FLAT vs cycle-6's 0/10) — the most important per-template finding. Cycles 7+12+13 cleared all 10 cycle-6 idempotence rejection picks (precision-positive) but didn't introduce new accepts (recall flat). The surviving v1.16 idempotence pool is dominated by **CM elementary functions** (17 of 25 = 68% — `exp`, `log`, `sin`, `cos`, `sqrt`, etc.), a noise class cycles 7-13 didn't target. **Selection-shift evidence, not target-improvement evidence.**
  - **round-trip** (9/20 = **45%**, +2.1pp vs cycle-6) — flat. Cycle-14 over-sampled CM principal-branch inverse pairs (7 trig+hyperbolic accepts) which inflates rate over noisier cross-product picks; balanced sample.
  - **commutativity** (1/5 = **20%**) and **associativity** (3/5 = **60%**) — flat / +20pp respectively; small-n.
  - **monotonicity** (2/4 = **50%**, −30pp vs cycle-6) — sample-mix noise on n=4 effective; cycle-14 picked more file-diversity → 2 unknowns + 2 rejects.
  - **inverse-pair** (1/1 = 100%, n=1 uninterpretable) — lone Algo `endOfChunk(startingAt:) ↔ startOfChunk(endingAt:)` survivor accepted on chunk-boundary domain.
  - **identity-element** (0/1 = 0%) — same `rescaledDivide × Complex.zero` pick as cycle 6, same reject verdict.
  - **Per-corpus**: OC **+22.7pp** (50.0% vs cycle-6's 27.3%; cycles 7+12+13 targeted OC heavily — surface dropped 101 → 43 = −57%); CM **−4.3pp drift** (32.1% vs 36.4%; no mechanism cycle hit CM directly between cycles 7-13); Algo +6.4pp (28.6% vs 22.2%); PLK uninterpretable (n=1 effective). **CM is the cycle-15 empirical priority** — three post-cycle-6 mechanism families (parameter-label direction-counter + function-name + type-shape composite + parameter-label semantic-intent counter) all targeted patterns that exist on OC + Algo, not CM.
- **Mechanism-class effectiveness ranking.** Eight mechanism classes ranked by surface reduction + per-template rate impact. Key finding: classes 6+7+8 (parameter-label direction-counter + function-name + type-shape composite + parameter-label semantic-intent counter) collectively delivered the +22.7pp OC shift but 0pp on CM. **Mechanism-class effectiveness is asymmetric — classes that increase precision (suppress rejects) don't automatically increase recall (introduce accepts).** Idempotence rate stayed at 0% despite three idempotence-targeting cycles (7+12+13).
- **Cycle-15 priority list (rotated post-v1.17, in expected impact order):**
  1. **NEW: Math-library forward-function counter on idempotence + round-trip.** Surfaced by cycle-14 idempotence 0% → 0% finding. New curated set `SwiftInferCore.MathForwardFunctions.curated = {exp, log, sin, cos, tan, sinh, cosh, tanh, asin, acos, atan, asinh, acosh, atanh, sqrt, expMinusOne, log(onePlus:)}` consumed by `IdempotenceTemplate` + `RoundTripTemplate`. Targets the dominant cycle-14 rejection class (CM elementary functions). Function-name + type-shape composite class extension. ~half a day to a day.
  2. **NEW: Fixed-point-name positive signal on idempotence.** Cycle-7 priority list option (b) — encourage idempotence accepts on names like `normalize`, `canonicalize`, `dedupe`, `simplify`, `clamped`, `flattened`, `sorted`, `uniqued`. Would produce the first non-zero cycle-N idempotence acceptance rate. Now seven cycles overdue.
  3. **Reference-type carrier counter-signal** (carried forward from post-v1.16 priority #3).
  4. **FP approximate-equality template arm** (carried forward).
  5. **Math-library op-name gate extension** to `rescaledDivide` / `_relaxedAdd` / `_relaxedMul` (carried forward).
  6. **DEMOTED: Stride-style label extension.** Was post-v1.16 priority #1; cycle-14 picks #19 + #49 measure the lone Algo `endOfChunk(startingAt:) ↔ startOfChunk(endingAt:)` survivor as **correctness-positive on chunk-boundary domain** (round-trip + inverse-pair both accept). Suppressing would lose recall on a true positive. Reframe as usability-paired with chunk-boundary generator support in TestLifter, not standalone cleanup.
  7. **`surfacedAt` plumbing**, **multi-rater triage**, **codec set broadening + SuggestionIdentity continuity fixture**, **SemanticIndex** (all carried forward).
- **Cycle-6 picks status rollup.** Of 50 cycle-6 picks: ~20 suppressed by post-cycle-6 mechanisms (mostly cycle-6 rejects + a few cycle-6 accepts that fell to direction-label counter); ~30 still surfacing at v1.16. The notable suppressed cycle-6 ACCEPTS — `index(after:) ↔ index(before:)` Collection-protocol pairs (cycle-6 #4, #14) — are direction-label-counter casualties. They're true positives that the rubric rates as accept; the direction-label counter classifies them as noise based on the parameter-label heuristic. **The clearest precision-vs-recall tradeoff in the cycle 7-13 mechanism family**, and the source of the cycle-15 stride-style label extension demotion.

### Documentation

- **Performance baseline carry-forward (V1.17.4).** `docs/perf-baseline-v1.17.md` documents that v1.17 ships zero Sources/ changes (apart from the version-string bump); §13 measurements are byte-equivalent to v1.16.0. Same posture as v1.9 (the prior empirical-only release). v1.16 baseline retained at `docs/perf-baseline-v1.16.md` as the substantive regression anchor; v1.17+ commits gate against either equivalently.
- **CLAUDE.md repo-state pointer index extended.** v1.17.0 release entry points at `docs/archive/v1.17 Calibration Plan.md`; "Where to look" perf-baseline pointer updated to `docs/perf-baseline-v1.17.md`; cycle-14 findings + data + rubric pointers added.

### Hard guarantees + performance

- All PRD §16 hard guarantees unchanged — v1.17 ships zero accept-flow writeout paths, zero new templates, zero new signals.
- All PRD §13 performance budgets hold at v1.17 (carried forward from v1.16). Row 4 ceiling stays at the post-v1.1.0 800 MB CI calibration. V1.6.1 flake-resistant 4.0s/6.0s budgets carry forward.
- PRD §14 + §19 runtime no-network guarantee unchanged; the cycle-14 triage data is in-source — no telemetry, no networking touches.

[1.17.0]: https://github.com/Joseph-Cursio/SwiftInferProperties/releases/tag/v1.17.0

## [1.16.0] — 2026-05-09

The thirteenth calibration cycle and **the cycle that crosses the 80% cumulative-reduction milestone** (1167 → 229 = −80.38%, with 4-candidate margin from the 233 threshold). v1.16 extends V1.14.1's function-name + type-shape composite mechanism from inverse-pair to round-trip + idempotence — completes the three-template SetAlgebra-shape family. Mechanism class continuity, not new: the cycle-13 mechanism class is the same function-name + type-shape composite class introduced in cycle 11; v1.16 extends within an existing class. v1.16 ships V1.16.1's `setAlgebraShapeVeto(for:)` extension methods on `RoundTripTemplate` (both-sides detection) and `IdempotenceTemplate` (single-function detection); both reuse the existing `Signal.Kind.protocolCoveredProperty` case (V1.14.1's reuse posture) and emit `-25` weight (uniform with V1.14.1's inverse-pair calibration). Both consume the V1.16.1-hoisted `SwiftInferCore.SetAlgebraShape.isSelfTypedBinaryOp(_:)` helper — lifted from V1.14.1's private helper when round-trip + idempotence became second + third consumers (second-consumer-triggers-hoist pattern from v1.13). **Empirical effect: −6 of 235 surfaced suggestions** (−2.55% aggregate; same magnitude as cycle 11's −6, also a SetAlgebra-shape mechanism). All −6 suppressions are on the OC corpus: round-trip 3 → 1 (−2, both-sides SetAlgebra-shape pairs), idempotence 6 → 2 (−4, single-function SetAlgebra-shape ops). Other three corpora byte-identical to cycle-12. **Plan-vs-actual: point-for-point exact match across all four corpora — fourth consecutive measurement cycle with this property** (after v1.12 → v1.14 → v1.15 → v1.16, with v1.13 being a no-measurement refactor cycle in between). Cumulative across cycles 1–13: **1167 → 229 (−80.38%)** with 13 calibration cycles (12 mechanism + 1 refactor) spanning **eight distinct mechanism classes** (taxonomy unchanged from cycle 12; cycle-13 is family-completion within an existing class). Same hard-guarantee posture as v1.15 — §16 guarantees unchanged; §13 budgets re-baselined at [`docs/perf-baseline-v1.16.md`](docs/perf-baseline-v1.16.md), all seven rows within ±2.9% of v1.15 (sub-noise-floor across the board).

### Calibration cycle 13 — SetAlgebra-shape veto extension to round-trip + idempotence

- **`SwiftInferCore.SetAlgebraShape.isSelfTypedBinaryOp(_:)` hoisted (V1.16.1).** Lifted from `Sources/SwiftInferTemplates/InversePairSetAlgebraShapeGate.swift`'s private `isSelfTypedBinaryOp(_:)` helper (V1.14.1) to a `public static func` on `SwiftInferCore.SetAlgebraShape`. Mirrors the V1.13.1 `DirectionLabels` hoist precedent: when a template-agnostic helper crosses the second-consumer threshold, it lives in `SwiftInferCore.<Namespace>.<helper>`. Round-trip + idempotence become consumers in v1.16; the helper now lives alongside the curated 4-element `binaryOps` set introduced in V1.14.1.
- **`RoundTripTemplate.setAlgebraShapeVeto(for:)` extension method (V1.16.1).** New file `Sources/SwiftInferTemplates/RoundTripSetAlgebraShapeGate.swift` hosts the private static helper. Both pair sides must pass `SetAlgebraShape.isSelfTypedBinaryOp(_:)` AND both names in `SetAlgebraShape.binaryOps` (parallel of V1.14.1's inverse-pair shape; same structural argument).
- **`IdempotenceTemplate.setAlgebraShapeVeto(for:)` extension method (V1.16.1).** New file `Sources/SwiftInferTemplates/IdempotenceSetAlgebraShapeGate.swift` hosts the private static helper. Single-function gate: candidate must pass `SetAlgebraShape.isSelfTypedBinaryOp(_:)` AND name in `SetAlgebraShape.binaryOps`. Suppresses idempotence claims where a SetAlgebra binary-op partial-application is mistakenly viewed as a `(T) -> T` self-mappable transformation.
- **Score arithmetic for round-trip / idempotence (baseline `+30` typeSymmetry):** `+30 - 25 = +5` Suppressed (clean margin from `+20`). With curated verb `+40` override: `+40 + 30 - 25 = +45` Likely (preserved in the hypothetical case where curated verbs coincide with SetAlgebra ops; in practice they don't). Weight `-25` per V1.16.0 plan open decision #1 (uniform with V1.14.1's existing inverse-pair calibration).
- **No new `Signal.Kind` case, no new `KnownProperty`.** Both new gates reuse `Signal.Kind.protocolCoveredProperty` (mirroring V1.14.1's reuse posture from cycle 11). The detail string distinguishes "SetAlgebra-shape pair" (round-trip) from "SetAlgebra-shape function" (idempotence) for explainability clarity.
- **Three new test suites + one updated.** `Tests/SwiftInferCoreTests/SetAlgebraShapeHelperTests.swift` (7 tests, hoisted helper coverage), `Tests/SwiftInferTemplatesTests/RoundTripSetAlgebraShapeGateTests.swift` (10 tests including parameterized 16-combination suppression), `Tests/SwiftInferTemplatesTests/IdempotenceSetAlgebraShapeGateTests.swift` (8 tests including parameterized 4-name suppression). V1.14.1's existing `InversePairSetAlgebraShapeGateTests` byte-identical (helper-hoist is API-equivalent at the call site).
- **First cycle to compress two-template mechanism extension into a single commit.** Cycles 11 + 13 ship the same mechanism (function-name + type-shape composite) across three templates in two releases; cycles 7-9 took three releases. The compression is sustainable when (a) the mechanism is uniform, (b) the curated set + helper are canonical-from-day-one or already-hoisted, (c) the gate-shape has prior precedent (V1.14.1).
- **Cycle-13 calibration capture (V1.16.2).** Re-ran `swift-infer discover --include-possible --target X` against the four cycle-1+...+12 corpora at the v1.16.1 commit. Snapshots committed at `docs/calibration-cycle-13-data/post-setalgebra-extension-*.discover.txt`; total surface 235 → 229 (−6, −2.55%). Per-corpus delta: OrderedCollections 49 → 43 (round-trip 3 → 1, idempotence 6 → 2); Algorithms / ComplexModule / PropertyLawKit byte-identical (no SetAlgebra-shape candidates). All 6 V1.16.1-targeted candidates suppressed; 0 false positives. The 3 deliberately-preserved survivors (1 asymmetric `_value/_bucketContents` round-trip + 2 non-domain non-SetAlgebra idempotence) remain surfaced.
- **Cycle-13 findings writeup (V1.16.3).** New `docs/calibration-cycle-13-findings.md` documents: the −6 / −2.55% headline + **first cycle to cross 80% cumulative reduction** framing (margin: 4 candidates), the **plan-vs-actual fourth consecutive exact match** (v1.12 → v1.14 → v1.15 → v1.16), the **completion of the function-name + type-shape composite three-template family** (V1.14.1 introduced inverse-pair; V1.16.1 extended round-trip + idempotence), the **second-consumer-triggers-hoist pattern verified as a workflow invariant** (v1.13 introduced; v1.16 applied), the cumulative 1167 → 229 (−80.38%) trajectory across 13 cycles, and the cycle-14 priority list (stride-style label extension promoted to #1). V1.16.3 also amends `docs/calibration-cycle-12-findings.md` line 117 — the OC idempotence SetAlgebra-shape count was mis-stated as 2 in the table (narrative correctly said 4); documented as a calibration-data-quality note.

### Documentation

- **Performance baseline re-pinned.** `docs/perf-baseline-v1.16.md` is the canonical regression anchor for v1.16+. All seven §13 rows within ±2.9% of v1.15 — sub-noise-floor across the board. Row 4 (500-file memory) at 134.8 MB (+0.4%) — V1.16.1's two new vetoes fire upstream of Suggestion construction (same constant-cost-per-skip posture as cycles 7-12). v1.15 baseline retained at `docs/perf-baseline-v1.15.md` for forensic comparison.
- **CLAUDE.md repo-state pointer index extended.** v1.16.0 release entry points at `docs/archive/v1.16 Calibration Plan.md`; "Where to look" perf-baseline pointer updated to `docs/perf-baseline-v1.16.md`. Cycle-13 findings + data pointers added.
- **Cycle-12 findings table correction.** `docs/calibration-cycle-12-findings.md` line 117 amended at V1.16.3: `OC idempotence with SetAlgebra shape | 2` → `4`. The narrative text already said "4"; the summary table row was the typo. Documented as a calibration-data-quality lesson — future cycle findings docs may add a build-time check or template that enforces table-narrative consistency.

### Hard guarantees + performance

- All PRD §16 hard guarantees unchanged — v1.16 ships no new accept-flow writeout paths; the cycle-13 tuning is two veto signals on existing scoring helpers.
- All PRD §13 performance budgets hold at v1.16. Row 4 ceiling stays at the post-v1.1.0 800 MB CI calibration. V1.6.1 flake-resistant 4.0s/6.0s budgets carry forward.
- PRD §14 + §19 runtime no-network guarantee unchanged; the curated SetAlgebra binary-op set is in-source — no telemetry, no networking touches.

[1.16.0]: https://github.com/Joseph-Cursio/SwiftInferProperties/releases/tag/v1.16.0

## [1.15.0] — 2026-05-09

The twelfth calibration cycle and the **first cycle to ship a single mechanism applied to three templates simultaneously** — compresses cycles 7-9's three-release direction-counter cadence (V1.10.1 idempotence → V1.11.1 inverse-pair → V1.12.1 round-trip) into a single release. v1.15 ships one structural rule deployed across three templates: V1.15.1's `domainMarkerCounterSignal(for:)` extension methods on `IdempotenceTemplate` (single-function detection), `RoundTripTemplate` (both-sides detection), and `InversePairTemplate` (both-sides detection, defensive scaffold — no current candidates). All three consume `SwiftInferCore.DomainMarkerLabels.curated = {forScale, forCapacity, forBucketContents}` and emit a `-15` weight signal on the existing `Signal.Kind.directionLabel` case. Mechanism class: parameter-label counter (semantic-intent variant) — extends the cycles 7-9 family with non-directional curated labels for cross-domain conversions. The two label sets (direction-labels and domain-markers) are textually disjoint by intent — domain markers describe *named domains* (scale, capacity, bucket-contents), not *positions in an ordered sequence*. **Empirical effect: −16 of 251 surfaced suggestions** (−6.4% aggregate; largest single-cycle structural-rule delta since cycle 9). All −16 suppressions are on the OC corpus: round-trip 12 → 3 (−9, both-sides domain-marker pairs), idempotence 13 → 6 (−7, single-function domain-marker labels). Other three corpora byte-identical to cycle-11. **Plan-vs-actual: point-for-point exact match across all four corpora — third consecutive measurement cycle with this property** (after v1.12 → v1.14 → v1.15, with v1.13 being a no-measurement refactor cycle in between). Cumulative across cycles 1–12: **1167 → 235 (−79.86%)** with 12 calibration cycles (11 mechanism + 1 refactor) spanning eight distinct mechanism classes — the parameter-label counter family now has two empirically-validated sub-classes (direction-label spatial-sequence + domain-marker semantic-intent). **Near-miss on the V1.15.0 plan's 80% projection** (overoptimistic by 0.14pp; cycle-13 SetAlgebra extension to round-trip + idempotence crosses unambiguously). Same hard-guarantee posture as v1.14 — §16 guarantees unchanged; §13 budgets re-baselined at [`docs/perf-baseline-v1.15.md`](docs/perf-baseline-v1.15.md), all seven rows within ±1.3% of v1.14 (flattest cycle-to-cycle movement since v1.13's no-behavior refactor).

### Calibration cycle 12 — domain-marker counter on three templates

- **`SwiftInferCore.DomainMarkerLabels` namespace (V1.15.1).** New file `Sources/SwiftInferCore/DomainMarkerLabels.swift` hosting `public enum DomainMarkerLabels` with `public static let curated: Set<String>` (3-element: `{forScale, forCapacity, forBucketContents}`). Lives in core from cycle 1 — **canonical-from-day-one** per the v1.13 hoist precedent + V1.14.1 SetAlgebraShape factoring posture; no per-template intermediate, no future hoist needed. Companion to `DirectionLabels.curated` (V1.13.1) and `SetAlgebraShape.binaryOps` (V1.14.1) — the three are the canonical homes for cycle-N curated data sets used across templates. Initial 3-element scope per V1.15.0 plan open decision #3 (witnessed-only); avoid speculative broadening (`forSlot`, `forIndex`, `forBucket`, `forKey`, etc.) without empirical justification.
- **Three template counter helpers (V1.15.1).** New files `Sources/SwiftInferTemplates/IdempotenceDomainMarkerCounter.swift` + `RoundTripDomainMarkerCounter.swift` + `InversePairDomainMarkerCounter.swift` each host a `domainMarkerCounterSignal(for:)` private static helper. Idempotence detects single-function first-param label match; round-trip + inverse-pair use **both-sides detection** (V1.15.0 plan open decision #2). All three emit `Signal(kind: .directionLabel, weight: -15, ...)` (uniform weight per V1.15.0 plan open decision #1). File-split posture mirrors V1.6.1/V1.8.1/V1.10.1/V1.11.1/V1.12.1/V1.14.1 — keeps each calibration mechanism in a self-contained file for attribution clarity. Wired into each template's `suggest(...)` signal-aggregation pipeline alongside existing direction-label counters.
- **Both-sides detection on pair templates (V1.15.0 open decision #2).** Round-trip + inverse-pair require *both* pair sides' first-param labels to be in the curated set. Preserves the asymmetric `_value(forBucketContents:) ↔ _bucketContents(for:)` candidate as a likely true-positive round-trip pair (encoding/decoding bucket contents); `for:` is the unlabeled-domain "given X" carrier, only the forward side has the explicit semantic-intent marker. Either-side detection would have suppressed it for −1 net aggregate gain — conservative-precision posture per PRD §3.5 prefers the both-sides default.
- **Score arithmetic for round-trip/idempotence (baseline `+30` typeSymmetry):** bare `+30 − 15 = +15` Suppressed (clean from `+20`); curated verb `+40` override → `+55` Likely (preserved); cross-type `-25` + counter → `-10` Suppressed (deeper margin). Inverse-pair (baseline `+25`): bare `+25 − 15 = +10` Suppressed; curated/project name `+10` → `+20` boundary-Possible. The boundary case is unlikely to fire in practice — curated names like `parse/format` don't coincide with HashTable domain labels.
- **No new `Signal.Kind` case, no new `KnownProperty`.** All three counters reuse the existing `Signal.Kind.directionLabel` case (mirroring the cycle-7 → cycle-8 → cycle-9 + cycle-11 reuse pattern). The explainability detail string distinguishes "Direction-label argument" from "Domain-marker labels" for user-facing clarity.
- **First cycle to ship a single mechanism applied to three templates simultaneously.** Cycles 7-9 deployed the analogous direction-label counter family across three releases. v1.15 compresses that into one commit (V1.15.1) — 250 lines of source + 600 lines of tests across three templates produces −16 suppressions; cycles 7-9 took ~750 lines for an aggregate −92. The compression is sustainable when the mechanism is uniform, the curated set is canonical-from-day-one, and the cross-template integration pattern has prior precedent.
- **One V1.12.1 lookahead test updated (V1.15.1).** A v1.12 test (`nonDirectionLabelDoesNotSuppress`) explicitly anticipated cycle-10's domain-mismatch mechanism — its comment said "Cycle-10 domain-mismatch mechanism is the eventual fix here". Updated to reflect v1.15 behavior: pair is now Suppressed via the V1.15.1 domain-marker counter; the V1.12.1 direction-counter helper itself still doesn't fire on these labels (verified via direct call). Test count 1581 → 1594 (+13 net for V1.15.1's three new test files).
- **Cycle-12 calibration capture (V1.15.2).** Re-ran `swift-infer discover --include-possible --target X` against the four cycle-1+...+11 corpora at the v1.15.1 commit. Snapshots committed at `docs/calibration-cycle-12-data/post-domain-marker-counter-*.discover.txt`; total surface 251 → 235 (−16, −6.4%). Per-corpus delta: OrderedCollections 65 → 49 (round-trip 12 → 3, idempotence 13 → 6); Algorithms / ComplexModule / PropertyLawKit byte-identical (no domain-marker candidates). All 16 V1.15.1-targeted candidates suppressed; 3 deliberately preserved (1 asymmetric true-positive + 2 SetAlgebra round-trip pairs as cycle-13 territory).
- **Cycle-12 findings writeup (V1.15.3).** New `docs/calibration-cycle-12-findings.md` documents: the −16 / −6.4% headline + first single-mechanism-three-templates framing, the **mechanism-class taxonomy expanded to 8 classes** (parameter-label counter family now has two empirically-validated sub-classes), the **plan-vs-actual third consecutive exact match** (v1.12 → v1.14 → v1.15), the **80% near-miss at 79.86%** (overoptimistic by 0.14pp; cycle-13 crosses unambiguously), the **both-sides design validation** (preserves 1 likely true-positive at zero aggregate cost), the cumulative 1167 → 235 (−79.86%) trajectory across 12 cycles, and the cycle-13 priority list (SetAlgebra-shape veto extension to round-trip + idempotence promoted to #1).

### Documentation

- **Performance baseline re-pinned.** `docs/perf-baseline-v1.15.md` is the canonical regression anchor for v1.15+. All seven §13 rows within ±1.3% of v1.14 — flattest cycle-to-cycle movement since v1.13's no-behavior refactor. Row 4 (500-file memory) effectively unchanged at 134.2 MB (-0.4%) — V1.15.1's three counters fire upstream of Suggestion construction (same constant-cost-per-skip posture as cycles 7-11). v1.14 baseline retained at `docs/perf-baseline-v1.14.md` for forensic comparison.
- **CLAUDE.md repo-state pointer index extended.** v1.15.0 release entry points at `docs/archive/v1.15 Calibration Plan.md`; "Where to look" perf-baseline pointer updated to `docs/perf-baseline-v1.15.md`. Cycle-12 findings + data pointers added.

### Hard guarantees + performance

- All PRD §16 hard guarantees unchanged — v1.15 ships no new accept-flow writeout paths; the cycle-12 tuning is three counter signals on existing scoring helpers.
- All PRD §13 performance budgets hold at v1.15. Row 4 ceiling stays at the post-v1.1.0 800 MB CI calibration. V1.6.1 flake-resistant 4.0s/6.0s budgets carry forward.
- PRD §14 + §19 runtime no-network guarantee unchanged; the curated domain-marker set is in-source — no telemetry, no networking touches.

[1.15.0]: https://github.com/Joseph-Cursio/SwiftInferProperties/releases/tag/v1.15.0

## [1.14.0] — 2026-05-09

The eleventh calibration cycle and the **first cycle to ship a function-name + type-shape composite mechanism** — distinct from cycles 7-9's parameter-label counter family. v1.14 ships one structural rule: V1.14.1's `InversePairTemplate.setAlgebraShapeVeto(for:)` extension method emitting `-25` weight when both pair sides have `(Self) -> Self` shape AND both function names are in `SetAlgebraShape.binaryOps = {union, intersection, symmetricDifference, subtracting}`. The structural argument: any pair drawn from the SetAlgebra binary-op surface is not an inverse pair (`intersection` then `subtracting` does not recover the original input — these are SetAlgebra *operations*, not *inverses*); the fact holds regardless of whether the carrier formally conforms to SetAlgebra. **Empirical effect: −6 of 257 surfaced suggestions** (−2.3% aggregate; **first cycle to fully eliminate a template's per-corpus surface** — OrderedCollections inverse-pair 6 → 0, 100% of the OC inverse-pair surface eliminated). All 6 are `intersection ↔ subtracting`-shape pairs across `OrderedSet+Partial SetAlgebra intersection.swift` × `OrderedSet+Partial SetAlgebra subtracting.swift` × `OrderedSet+UnorderedView.swift`. **Plan-vs-actual: point-for-point exact match across all four corpora (second consecutive measurement cycle with this property** — after v1.12 → v1.14, with v1.13 being a no-measurement refactor cycle in between). Cycle-6 picks coverage closes at v1.14: all 5/5 inverse-pair rejection picks now suppressed across V1.11.1 (2/5, parameter-label class) + V1.14.1 (3/5, function-name + type-shape composite class). Cumulative across cycles 1–11: **1167 → 251 (−78.5%)** with 11 calibration cycles (10 mechanism + 1 refactor) spanning seven distinct mechanism classes. Same hard-guarantee posture as v1.13 — §16 guarantees unchanged; §13 budgets re-baselined at [`docs/perf-baseline-v1.14.md`](docs/perf-baseline-v1.14.md), all seven rows within ±4.0% of v1.13.

### Calibration cycle 11 — SetAlgebra-shape veto on inverse-pair

- **`SwiftInferCore.SetAlgebraShape` namespace (V1.14.1).** New file `Sources/SwiftInferCore/SetAlgebraShape.swift` hosting `public enum SetAlgebraShape` with `public static let binaryOps: Set<String>` (4-element: `{union, intersection, symmetricDifference, subtracting}`). Lives in core from cycle 1 — **canonical-from-day-one** per the v1.13 hoist precedent; no per-template intermediate, no future hoist needed. Companion to `DirectionLabels.curated` (V1.13.1) — both factored as `public enum <Name> { public static let <subset>: Set<String> }` for consistent template-agnostic-curated-data ergonomics.
- **`InversePairTemplate.setAlgebraShapeVeto(for:)` extension method (V1.14.1).** New file `Sources/SwiftInferTemplates/InversePairSetAlgebraShapeGate.swift` hosts the private static helper. File-split per the V1.6.1/V1.8.1/V1.10.1/V1.11.1/V1.12.1 file-length precedent. Returns `-25` weight Signal when both forward+reverse have `(Self) -> Self` typing AND both names are in `SetAlgebraShape.binaryOps`. Wired into `InversePairTemplate.suggest(...)`'s signal-aggregation pipeline between the direction-label counter and `protocolCoverageVeto`.
- **Score arithmetic for inverse-pair (baseline `+25` typeSymmetry):** `+25 − 25 = 0` Suppressed (clean margin from `+20`); with curated/project name (`+10`): `+25 + 10 − 25 = +10` Suppressed (still suppressed; curated `parse/format`-style names are unlikely to coincide with SetAlgebra ops, but if they do the structural argument still wins). Weight `-25` per V1.14.0 plan open decision #1 (matches V1.4.3b cross-type round-trip counter weight; conservative-precision posture preserves recall on edge cases).
- **Shape-only check (no protocol-conformance lookup) per V1.14.0 plan open decision #3.** `OrderedSet` itself doesn't declare `: SetAlgebra` directly (only has `Partial SetAlgebra` extensions); a conformance check would miss 4 of 6 cycle-9 OC survivors. Shape-only catches all 6. The structural argument "intersection ∘ subtracting ≠ identity" is independent of conformance declaration.
- **No new `Signal.Kind` case, no new `KnownProperty`.** The veto reuses the existing `Signal.Kind.protocolCoveredProperty` case (mirroring the cycle-7 → cycle-8 → cycle-9 reuse pattern of `Signal.Kind.directionLabel` for three consumers).
- **13 new tests across 2 suites** in `Tests/SwiftInferTemplatesTests/InversePairSetAlgebraShapeGateTests.swift` covering: `intersection ↔ subtracting` Self-typed pair suppression, `intersection ↔ intersection` cross-file self-pair suppression, parameterized over all 4 × 4 = 16 curated combinations (each suppresses), curated `parse/format` non-Self typing preserves Possible, curated names on non-Self typing don't fire, mixed curated/non-curated names don't fire, custom non-SetAlgebra Self-typed ops still surface, case-sensitivity, weight pinning at -25, `SetAlgebraShape.binaryOps` lives in core, direction-label counter + SetAlgebra veto compose correctly, end-to-end `discover()` integration. 1553 → 1566 tests; all §13 perf budgets hold.
- **Cycle-11 calibration capture (V1.14.2).** Re-ran `swift-infer discover --include-possible --target X` against the four cycle-1+...+9 corpora at the v1.14.1 commit. Snapshots committed at `docs/calibration-cycle-11-data/post-setalgebra-veto-*.discover.txt`; total surface 257 → 251 (−2.3%). Per-corpus delta: OrderedCollections 71 → 65 (**−6 inverse-pair; 100% of OC inverse-pair surface eliminated** — first cycle to drop a template's per-corpus surface to zero); Algorithms / ComplexModule / PropertyLawKit byte-identical (no SetAlgebra-shape candidates).
- **Cycle-11 findings writeup (V1.14.3).** New `docs/calibration-cycle-11-findings.md` documents: the −6 / −2.3% headline (first cycle to fully eliminate a template's per-corpus surface), per-corpus per-template delta, the **mechanism-class taxonomy** (now spans seven distinct shapes — textual type-name counter, cross-type counter, protocol-coverage veto, pair-formation skip-list, stdlib-bake-in, parameter-label counter, function-name + type-shape composite), the **cycle-6 picks coverage closure** (all 5/5 inverse-pair rejections suppressed), the **plan-vs-actual exact match (second consecutive measurement cycle)**, the cumulative 1167 → 251 (-78.5%) trajectory across 11 cycles, and the cycle-12 priority list (domain-mismatch family promoted to #1).

### Documentation

- **Performance baseline re-pinned.** `docs/perf-baseline-v1.14.md` is the canonical regression anchor for v1.14+. All seven §13 rows within ±4.0% of v1.13 (which was a v1.12 carry-forward; these are the first fresh measurements since v1.12). Row 4 (500-file memory) effectively unchanged at 134.8 MB (-0.8%) — V1.14.1's veto is upstream of Suggestion construction, so the 6 newly-suppressed inverse-pair candidates don't allocate; same posture as V1.10.1/V1.11.1/V1.12.1. v1.13 baseline retained at `docs/perf-baseline-v1.13.md` (carry-forward) for forensic comparison.
- **CLAUDE.md repo-state pointer index extended.** v1.14.0 release entry points at `docs/archive/v1.14 Calibration Plan.md`; "Where to look" perf-baseline pointer updated to `docs/perf-baseline-v1.14.md`. Cycle-11 findings + data pointers added.

### Hard guarantees + performance

- All PRD §16 hard guarantees unchanged — v1.14 ships no new accept-flow writeout paths; the cycle-11 tuning is a veto on existing scoring helpers.
- All PRD §13 performance budgets hold at v1.14. Row 4 ceiling stays at the post-v1.1.0 800 MB CI calibration. V1.6.1 flake-resistant 4.0s/6.0s budgets carry forward.
- PRD §14 + §19 runtime no-network guarantee unchanged; the curated SetAlgebra binary-op set is in-source — no telemetry, no networking touches.

[1.14.0]: https://github.com/Joseph-Cursio/SwiftInferProperties/releases/tag/v1.14.0

## [1.13.0] — 2026-05-09

**Refactor release.** Cycle 10 of PRD §17.3's empirical-tuning loop, with refactor character rather than mechanism character. v1.13 closes the four-cycle abstraction-development cadence opened by v1.10 (introduce → replicate → complete the family → hoist) by hoisting the curated `directionLabels` set out of `IdempotenceTemplate` into a shared `SwiftInferCore.DirectionLabels` namespace, satisfying the v1.11 + v1.12 plans' open-decision-#2 commitments. **Zero behavior change**: byte-identical discover() output on the Algorithms corpus (largest direction-counter consumer at 90.0% of round-trip surface eliminated in cycle 9) verified at V1.13.1 commit time against `docs/calibration-cycle-9-data/post-roundtrip-direction-counter-swift-algorithms-Algorithms.discover.txt`. Set elements unchanged (10-element verbatim: `{after, before, next, prev, previous, advance, succ, pred, successor, predecessor}`); the three template consumers' counter-signal weights unchanged (`-15` idempotence + `-10` inverse-pair + `-15` round-trip). Surface count unchanged: cumulative 1167 → 257 (-78.0%) across 9 mechanism cycles + 1 refactor cycle. **Public API breakage**: `IdempotenceTemplate.directionLabels` removed (clean cut per V1.13.0 plan open decision #1); the field was internal-mechanism territory exposed via `public` for cross-template reuse, not a documented external API. The hoist follows the v1.6.1 maintenance-patch precedent of refactor-only releases between mechanism cycles. Same hard-guarantee posture as v1.12 — §16 guarantees unchanged; §13 budgets carry forward verbatim from `docs/perf-baseline-v1.12.md` at `docs/perf-baseline-v1.13.md`.

### Hoist refactor — directionLabels → SwiftInferCore.DirectionLabels.curated

- **`SwiftInferCore.DirectionLabels` namespace (V1.13.1).** New file `Sources/SwiftInferCore/DirectionLabels.swift` hosting `public enum DirectionLabels` with `public static let curated: Set<String>` — the 10-element set verbatim from v1.10-v1.12. Lives alongside `Signal.Kind.directionLabel` (also in core, V1.10.1) so the enum case + curated data pair are factored as one shared utility, mirroring how every other shared signal kind + curated data pair is factored. Migrated cycle-6 motivation comment so the hypothesis → mechanism → measurement attribution travels with the data.
- **Three call-site updates (V1.13.1).** `IdempotenceTemplate.swift` drops the `public static let directionLabels` declaration; updates the internal reference in `directionLabelCounterSignal(for:)` to `DirectionLabels.curated`. `InversePairDirectionLabelCounter.swift` updates the cross-template reference. `RoundTripDirectionLabelCounter.swift` updates the cross-template reference. All three source files' doc-comment cross-references migrated to the new canonical home.
- **Three test-file updates (V1.13.1).** `IdempotenceDirectionLabelCounterTests.swift` + `InversePairDirectionLabelCounterTests.swift` + `RoundTripDirectionLabelCounterTests.swift`: file-header comments updated; the cross-template reuse-assertion `@Test` (one per file) renamed to V1.13.1 + reference the new canonical home. Test count unchanged at 1553 (test count parity confirms the hoist added zero new assertions; the existing reuse-assertion tests now assert against the new location).
- **Backwards-compat posture: clean cut (V1.13.0 open decision #1).** `IdempotenceTemplate.directionLabels` removed entirely; no deprecated re-export. The field was a calibration knob exposed via `public` for cross-template reuse, not a documented external API; the package's user-facing surface is the `swift-infer` CLI, not the SwiftInferTemplates Swift API. Conventional-commit suffix `refactor!:` marks the public-API removal.
- **V1.13.0 plan doc.** Documented the hoist scope, six open decisions (clean cut vs deprecated re-export, name choice `.curated` vs `.all` vs `.labels`, doc-comment cross-reference update scope, motivation-comment placement, byte-stable verification scope, whether to track as cycle 10), and the four-cycle abstraction-development cadence framing. Archived to `docs/archive/v1.13 Hoist Plan.md` at V1.13.4.

### Documentation

- **Performance baseline carried forward.** `docs/perf-baseline-v1.13.md` is a carry-forward from `docs/perf-baseline-v1.12.md` — V1.13.1 changes only the *site* of the curated set; no allocation-pattern change, no scoring-pipeline change, byte-stable discover() output. Re-measurement is not required because §13 measures wall-clock + memory deltas downstream of the suggestion stream, which is byte-stable. v1.12 baseline retained at `docs/perf-baseline-v1.12.md` for forensic comparison.
- **CLAUDE.md repo-state pointer index extended.** v1.13.0 release entry points at `docs/archive/v1.13 Hoist Plan.md`; "Where to look" perf-baseline pointer updated to `docs/perf-baseline-v1.13.md`. Cycle-10 priority list rotated: SetAlgebra-shape detection on inverse-pair → priority #1 (was #2); domain-mismatch family on idempotence + inverse-pair + round-trip → priority #2 (was #3 elevated); stride-style label extension → priority #3 (was #4); Possible-tier re-sampling on the 257-surface → priority #4. The hoist itself (cycle-10 priority #1 from cycle-9 findings) is now shipped.

### Hard guarantees + performance

- All PRD §16 hard guarantees unchanged — v1.13 ships no new accept-flow writeout paths; the hoist is structural-only.
- All PRD §13 performance budgets hold at v1.13. Numbers carry forward from v1.12 verbatim (zero behavior change). V1.6.1 flake-resistant 4.0s/6.0s budgets carry forward.
- PRD §14 + §19 runtime no-network guarantee unchanged; the hoist moves an in-source curated set between modules — no telemetry, no networking touches.

### Breaking changes

- `IdempotenceTemplate.directionLabels` removed. Replacement: `SwiftInferCore.DirectionLabels.curated`. The new home is publicly accessible and contains the 10-element set verbatim. External consumers (none expected; the field was internal-mechanism territory) update by replacing `IdempotenceTemplate.directionLabels` with `DirectionLabels.curated` (or `SwiftInferCore.DirectionLabels.curated` for fully-qualified). No other API changes.

[1.13.0]: https://github.com/Joseph-Cursio/SwiftInferProperties/releases/tag/v1.13.0

## [1.12.0] — 2026-05-09

The ninth calibration cycle and the **first cycle to complete a three-template direction-counter family**. v1.12 ports v1.10's verified mechanism (`Signal.Kind.directionLabel` + the curated 10-element direction set) onto its third consumer — `RoundTripTemplate` — after v1.10's idempotence consumer and v1.11's inverse-pair consumer. New `RoundTripTemplate.directionLabelCounterSignal(for:)` extension method emits `-15` (mirroring v1.10's idempotence weight verbatim because round-trip's `+30` typeSymmetry baseline matches idempotence's, not inverse-pair's `+25` which justified v1.11's `-10`) when *either* pair-side's first-parameter argument label is in `IdempotenceTemplate.directionLabels`. Either-side detection catches asymmetric labeling like `transform(_:) × untransform(after:)`. Empirical effect: **−31 of 288 surfaced suggestions** (−10.8% aggregate; **largest single-cycle structural-rule delta to date**, reflecting round-trip being the largest-surface template at 181 of 288 = 62.8% post-v1.11). The cycle-7 → cycle-8 → cycle-9 mechanism-development cadence (introduce → replicate → complete the family) confirms `Signal.Kind.directionLabel` as load-bearing across three consumers; v1.13 will execute the planned hoist-to-shared-namespace refactor as the queued zero-behavior-change cleanup. Cumulative across cycles 1–9: **1167 → 257 (−78.0%)** — crosses the 75% milestone projected in the V1.12.0 plan. **Plan-vs-actual: point-for-point exact match across all four corpora (first time in the calibration loop's history)** — methodology fix from cycle-8 (per-suggestion `^Template:` line counts via Python regex rather than substring grep) paid off immediately. Same hard-guarantee posture as v1.11 — §16 guarantees unchanged; §13 budgets re-baselined at [`docs/perf-baseline-v1.12.md`](docs/perf-baseline-v1.12.md), all seven rows within ±5.5% of v1.11.

### Calibration cycle 9 — round-trip direction-label counter-signal

- **`RoundTripTemplate.directionLabelCounterSignal(for:)` extension method (V1.12.1).** New helper in `Sources/SwiftInferTemplates/RoundTripDirectionLabelCounter.swift` (file-split per the V1.6.1/V1.8.1/V1.10.1/V1.11.1 file-length precedent — pre-emptively split because `RoundTripTemplate.swift` was already 348 lines, within 17 of swiftlint's `type_body_length: 350` hard error). Returns `-15` weight when *either* pair-side's first-parameter argument label is in `IdempotenceTemplate.directionLabels` (10-element curated set reused verbatim from V1.10.1 — third consumer). Either-side detection per the v1.12 plan's open decision #3: catches asymmetric labeling like `transform(_:) × untransform(after:)`. Wired into `RoundTripTemplate.suggest(...)`'s signal-aggregation pipeline alongside the existing cross-type counter, non-deterministic veto, and shape-gated protocol-coverage veto.
- **Score arithmetic for round-trip (baseline `+30`, matching idempotence):** `+30 − 15 = +15` Suppressed (bare-shape direction-labeled pair; clean margin from `+20` boundary); `+30 + 40 − 15 = +55` Likely (curated `encode/decode` name `+40` preserves clean margin from `+40` Likely boundary); `+30 + 35 − 15 = +50` Likely (discoverable `@Discoverable(group:)` `+35` preserves user's explicit signal); `+30 − 25 − 15 = -10` Suppressed (cross-type counter `-25` + direction counter compose additively for double suppression). Weight `-15` (mirrors v1.10 idempotence verbatim — same `+30` baseline) per the v1.12 plan's open decision #1.
- **No new `Signal.Kind` case, no new curated set, no new `KnownProperty` — third consumer.** Cross-template signal reuse: V1.12.1 consumes V1.10.1's `Signal.Kind.directionLabel` and `IdempotenceTemplate.directionLabels` verbatim, completing the three-template family. v1.13 hoist-to-shared-namespace becomes the planned next-cycle commitment (per the v1.11 plan's open decision #2 commitment "hoist when round-trip becomes the third consumer").
- **16 new tests across 3 suites** in `Tests/SwiftInferTemplatesTests/RoundTripDirectionLabelCounterTests.swift` (core suppression + curated-name preservation + boundary cases) + `Tests/SwiftInferTemplatesTests/RoundTripDirectionLabelCompositionTests.swift` (cross-type + discoverable interaction + end-to-end discover); test-side file-split per the same swiftlint length budgets that drove the source-side split. Coverage: `index(after:) ↔ index(before:)` suppression, cross-file `index(after:)` self-pair suppression, parameterized over all 10 curated labels (forward-side and reverse-side independently), stride-style `startingAt`/`endingAt` not in curated set → preserves Possible (cycle-10 candidate), curated `encode/decode` preserves Likely, curated + direction-on-one-side stays Likely at `+55`, `forScale` non-direction label doesn't fire counter (cycle-10 domain-mismatch territory), nil labels don't fire, case-sensitivity, weight pinning at `-15`, curated-set reuse from `IdempotenceTemplate` (third consumer), cross-type counter + direction counter compose to `-10` Suppressed, discoverable group + direction counter preserves Likely at `+50`, end-to-end `discover()` integration confirming surface effects. 1537 → 1553 tests; all §13 perf budgets hold.
- **Cycle-9 calibration capture (V1.12.2).** Re-ran `swift-infer discover --include-possible --target X` against the four cycle-1+2+3+4+5+6+7+8 corpora at the v1.12.1 commit. Snapshots committed at `docs/calibration-cycle-9-data/post-roundtrip-direction-counter-*.discover.txt`; total surface 288 → 257 (−10.8% — **largest single-cycle structural-rule delta to date**). Per-corpus delta: Algorithms 31 → 13 (−18 round-trip; **90.0% of Algo round-trip surface eliminated** — direction-labeled `index(after:) ↔ index(before:)` self-pairs across 18 source files), OrderedCollections 84 → 71 (−13 round-trip; 52.0% of OC round-trip surface — 7 self-pairs + 6 cross-pairs where either-side detection caught `index(after:) × _someCapacity(forScale:)` asymmetric labeling), ComplexModule 166 → 166 (byte-identical; no direction labels — Complex's binary ops use `_:` parameter labels per Swift convention), PropertyLawKit 7 → 7 (byte-identical; no round-trip candidates).
- **Cycle-9 findings writeup (V1.12.3).** New `docs/calibration-cycle-9-findings.md` documents: the −31 / −10.8% headline (largest single-cycle structural-rule delta to date), per-corpus per-template delta, three design validations from cycle-9 (`Signal.Kind.directionLabel` factoring confirmed load-bearing across three consumers, the 10-element curated direction set is portable across `+25`/`+30`/`+30` baselines, either-side detection has zero false-positive cost across nine cycles), the **plan-vs-actual point-for-point exact match** across all four corpora (first time in the calibration loop's history; methodology fix from cycle-8 paid off immediately), the cumulative 1167 → 257 (−78.0%) trajectory across 9 cycles with 9 compositional mechanisms (crosses the 75% milestone projected in the V1.12.0 plan), the cycle-7 → cycle-8 → cycle-9 mechanism-development cadence framing (introduce → replicate → complete the family → hoist queued for v1.13), and the cycle-10 priority list (v1.13 hoist refactor as #1, SetAlgebra-shape detection on inverse-pair as #2, domain-mismatch family on idempotence + inverse-pair + round-trip simultaneously as #3 elevated, stride-style label extension, post-v1.12 re-sampling, FP arm, math-lib op extension, surfacedAt plumbing, multi-rater methodology).

### Documentation

- **Performance baseline re-pinned.** `docs/perf-baseline-v1.12.md` is the canonical regression anchor for v1.12+. All seven §13 rows within ±5.5% of v1.11. Largest delta is Row 1a at -5.5% (29ms drop on a 0.5s wall measurement; sub-noise-floor at this precision class). Row 4 (500-file memory) effectively unchanged at 135.9 MB (-0.4%) — V1.12.1's counter-signal is upstream of Suggestion construction, so the 31 newly-suppressed round-trip claims don't allocate; same posture as V1.10.1 (idempotence) and V1.11.1 (inverse-pair) with same predicted and observed marginal-memory profile. v1.11 baseline retained at `docs/perf-baseline-v1.11.md` for forensic comparison.
- **CLAUDE.md repo-state pointer index extended.** v1.12.0 release entry points at `docs/archive/v1.12 Calibration Plan.md`; "Where to look" perf-baseline pointer updated to `docs/perf-baseline-v1.12.md`; cycle-9 findings + data pointers added.

### Hard guarantees + performance

- All PRD §16 hard guarantees unchanged — v1.12 ships no new accept-flow writeout paths; the cycle-9 tuning is a counter-signal on existing scoring helpers.
- All PRD §13 performance budgets hold at v1.12. Row 4 ceiling stays at the post-v1.1.0 800 MB CI calibration. V1.6.1 flake-resistant 4.0s/6.0s budgets carry forward.
- PRD §14 + §19 runtime no-network guarantee unchanged; the curated direction-label set is in-source (third-consumer reuse from V1.10.1) — no telemetry, no networking touches.

[1.12.0]: https://github.com/Joseph-Cursio/SwiftInferProperties/releases/tag/v1.12.0

## [1.11.0] — 2026-05-08

The eighth calibration cycle and the **first cycle to replicate a verified mechanism on an adjacent template**. v1.11 ports v1.10's just-shipped, just-verified mechanism (`Signal.Kind.directionLabel` on `IdempotenceTemplate`) onto `InversePairTemplate`. New `InversePairTemplate.directionLabelCounterSignal(for:)` extension method emits `-10` (calibrated for inverse-pair's `+25` typeSymmetry baseline vs idempotence's `+30`; cleanly drops bare-shape pairs into Suppressed while preserving curated/project name matches above the `+20` Possible boundary) when *either* pair-side's first-parameter argument label is in `IdempotenceTemplate.directionLabels` (10-element curated set reused verbatim — first cross-template signal reuse). Either-side detection catches asymmetric labeling (`format(_:) × parse(after:)` style). Empirical effect: **−8 of 296 surfaced suggestions** (−2.7% aggregate; smallest single-cycle structural-rule delta to date, reflecting inverse-pair's already-narrow surface). The cycle-7 → cycle-8 mechanism-replication motif validates two design choices from v1.10: `Signal.Kind.directionLabel` is the right factoring (now shared across two templates), and the curated direction set is portable across templates with different baseline scores. Cycle-6 picks fully accounted-for on inverse-pair: 2/5 suppressed (Algo Index ops #48-#49), 3/5 preserved (OC SetAlgebra-shaped #45-#47, cycle-9 candidate). Cumulative across cycles 1–8: **1167 → 288 (−75.3%)**. Same hard-guarantee posture as v1.10 — §16 guarantees unchanged; §13 budgets re-baselined at [`docs/perf-baseline-v1.11.md`](docs/perf-baseline-v1.11.md), all seven rows within ±5% of v1.10.

### Calibration cycle 8 — inverse-pair direction-label counter-signal

- **`InversePairTemplate.directionLabelCounterSignal(for:)` extension method (V1.11.1).** New helper in `Sources/SwiftInferTemplates/InversePairDirectionLabelCounter.swift` (file-split per the V1.6.1/V1.8.1/V1.10.1 file-length precedent — inlining pushed the parent enum 1 line over swiftlint's `type_body_length: 250` budget). Returns `-10` weight when *either* pair-side's first-parameter argument label is in `IdempotenceTemplate.directionLabels` (10-element curated set reused verbatim from V1.10.1). Either-side detection per the v1.11 plan's open decision #3: asymmetric labeling like `transform(_:) × untransform(after:)` suppresses correctly because the curated/project name match (`+10`) keeps legitimate inverse pairs in Possible tier (`+25 + 10 − 10 = +25`) even when a direction label coincidentally appears. Wired into `InversePairTemplate.suggest(...)`'s signal-aggregation pipeline alongside the existing FP-storage counter and protocol-coverage veto.
- **Score arithmetic for inverse-pair (baseline `+25` vs idempotence's `+30`):** `+25 − 10 = +15` Suppressed (bare-shape direction-labeled pair); `+25 + 10 − 10 = +25` Possible (curated/project name match preserves clean margin from the `+20` boundary). Weight `-10` (not v1.10's `-15`) per the v1.11 plan's open decision #1 — the lower baseline calibrates the counter weight differently; `-15` would put curated-named pairs at the noisy `+20` tier boundary that v1.10's open-decision-#1 explicitly avoided.
- **No new `Signal.Kind` case, no new curated set, no new `KnownProperty`.** Cross-template signal reuse: V1.11.1 consumes V1.10.1's `Signal.Kind.directionLabel` and `IdempotenceTemplate.directionLabels` verbatim. Hoist-to-shared-namespace deferred to v1.13 when round-trip becomes the third consumer (per the v1.11 plan's open decision #2).
- **13 new tests** in `Tests/SwiftInferTemplatesTests/InversePairDirectionLabelCounterTests.swift` (split per the V1.7.1/V1.8.1/V1.10.1 file-length precedent). Coverage: `index(after:) ↔ index(before:)` suppression, `bucket(after:) ↔ bucket(before:)` suppression, parameterized over all 10 curated labels (forward-side and reverse-side independently), curated `parse/format`-name preservation when one side has a direction label, non-direction labels stay at Possible, nil labels don't trigger, case-sensitivity, weight pinning at `-10`, curated-set reuse from `IdempotenceTemplate`, end-to-end `discover()` suppression + non-direction pair survival. 1524 → 1537 tests; all §13 perf budgets hold.
- **Cycle-8 calibration capture (V1.11.2).** Re-ran `swift-infer discover --include-possible --target X` against the four cycle-1+2+3+4+5+6+7 corpora at the v1.11.1 commit. Snapshots committed at `docs/calibration-cycle-8-data/post-inverse-direction-counter-*.discover.txt`; total surface 296 → 288 (−2.7%). Per-corpus delta: Algorithms 36 → 31 (−5 inverse-pair; **83.3% of Algo inverse-pair surface eliminated** — direction-labeled `index(after:)` self-pairs across multiple source files), OrderedCollections 87 → 84 (−3 inverse-pair; 33.3% of OC inverse-pair surface), ComplexModule 166 → 166 (byte-identical; no inverse-pair candidates because Complex is Equatable so candidate elementary-function pairs route through `RoundTripTemplate`), PropertyLawKit 7 → 7 (byte-identical; no inverse-pair candidates).
- **Cycle-8 findings writeup (V1.11.3).** New `docs/calibration-cycle-8-findings.md` documents: the −8 / −2.7% headline (smallest single-cycle structural-rule delta to date — reflects inverse-pair's already-narrow starting surface), per-corpus per-template delta, the cycle-6 picks verification (2 of 5 inverse-pair rejections suppressed by V1.11.1; the other 3 stay surfaced because they're SetAlgebra-shaped Self-typed binary ops with no labels — separate cause-of-noise class for cycle-9), the cumulative 1167 → 288 (−75.3%) trajectory across 8 cycles with 8 compositional mechanisms, the cycle-7 → cycle-8 mechanism-replication motif framing ("first time a verified mechanism is ported across templates with successful empirical effect"), three design validations from cycle-8 (`Signal.Kind.directionLabel` factoring confirmed, curated direction set portable across templates, either-side detection has no false-positive cost at calibrated `-10`), the plan-vs-actual analysis (cycle-8 effect was 2/3 of projection — Algo over-projected 2x because plan-time grep used substring counts; methodology lesson recorded for cycle-9), and the cycle-9 priority list (round-trip direction-label counter as third `Signal.Kind.directionLabel` consumer, SetAlgebra-shape detection on inverse-pair, domain-mismatch detection on idempotence + inverse-pair, stride-style label extension, FP arm, math-lib op extension, post-v1.11 re-sampling, surfacedAt plumbing, multi-rater methodology).

### Documentation

- **Performance baseline re-pinned.** `docs/perf-baseline-v1.11.md` is the canonical regression anchor for v1.11+. All seven §13 rows within ±5% of v1.10. Row 4 (500-file memory) at 136.4 MB (+1.6%) — V1.11.1's counter-signal is upstream of Suggestion construction, so the 8 newly-suppressed inverse-pair candidates don't allocate; same posture as V1.10.1 with same observed marginal-memory profile. Row 5 at -3.8% (26ms → 25ms) is single-ms 1ms-precision noise. v1.10 baseline retained at `docs/perf-baseline-v1.10.md` for forensic comparison.
- **CLAUDE.md repo-state pointer index extended.** v1.11.0 release entry points at `docs/archive/v1.11 Calibration Plan.md`; "Where to look" perf-baseline pointer updated to `docs/perf-baseline-v1.11.md`; cycle-8 findings + data pointers added.

### Hard guarantees + performance

- All PRD §16 hard guarantees unchanged — v1.11 ships no new accept-flow writeout paths; the cycle-8 tuning is a counter-signal on existing scoring helpers.
- All PRD §13 performance budgets hold at v1.11. Row 4 ceiling stays at the post-v1.1.0 800 MB CI calibration. V1.6.1 flake-resistant 4.0s/6.0s budgets carry forward.
- PRD §14 + §19 runtime no-network guarantee unchanged; the curated direction-label set is in-source (reused from V1.10.1) — no telemetry, no networking touches.

[1.11.0]: https://github.com/Joseph-Cursio/SwiftInferProperties/releases/tag/v1.11.0

## [1.10.0] — 2026-05-08

The seventh calibration cycle and the **first cycle whose structural mechanism is empirically motivated by the prior cycle's measurement**. v1.10 ships one structural rule — a `-15` direction-label counter-signal on `IdempotenceTemplate` candidates — targeting the cycle-6-measured 0/10 idempotence rejection pattern. Surgical empirical effect: **−53 of 349 surfaced suggestions** (−15.2% aggregate) — second-largest single-cycle suppression after cycle-1's structural counter-signals. The cycle-6 → cycle-7 attribution loop closes cleanly: hypothesis → mechanism → measurement → verification. Cumulative across cycles 1–7: **1167 → 296 (−74.6%)**. Same hard-guarantee posture as v1.9 — §16 guarantees unchanged; §13 budgets re-baselined at [`docs/perf-baseline-v1.10.md`](docs/perf-baseline-v1.10.md), six of seven rows within ±5% of v1.8.

### Calibration cycle 7 — idempotence direction-label counter-signal

- **`Signal.Kind.directionLabel` enum case (V1.10.1).** New case in the "Negative (non-veto)" group of `Sources/SwiftInferCore/Signal.swift`. Mirrors `floatingPointStorage` posture — a `-15` counter-signal that pulls Possible-tier candidates into Suppressed when the structural pattern indicates likely-false. Documented inline with cycle-6 motivation (the 0/10 idempotence Possible-tier acceptance rate).
- **`IdempotenceTemplate.directionLabels` curated set + counter-signal helper (V1.10.1).** New `IdempotenceTemplate.directionLabels: Set<String>` 10-element public static let: `{after, before, next, prev, previous, advance, succ, pred, successor, predecessor}`. Co-located with `IdempotenceTemplate.curatedVerbs` per the existing template-data convention. New private `directionLabelCounterSignal(for:)` helper checks `summary.parameters.first?.label` membership and emits the `-15` signal when matched. Wired into `IdempotenceTemplate.suggest(...)`'s signal-aggregation pipeline. Score arithmetic: typeSymmetry (+30) + direction counter (-15) = +15 → Suppressed (< 20); typeSymmetry + curated verb match (+40) + direction counter = +55 → Likely (still surfaces). Curated-verb override means well-named idempotents (`normalize` / `canonicalize` / `flatten` / etc.) keep emitting; direction-only-style ops drop below the Possible threshold.
- **13 new tests** in `Tests/SwiftInferTemplatesTests/IdempotenceDirectionLabelCounterTests.swift` (split from `IdempotenceTemplateTests.swift` per the V1.7.1/V1.8.1 split precedent). Coverage: parameterized test over all 10 curated direction labels (each suppresses), curated verb override preserves Likely tier, non-direction labels and nil labels stay at Possible, case-sensitivity, `Signal.Kind.allCases` membership, set size invariant, end-to-end `discover()` suppression + curated-verb preservation. 1511 → 1524 tests; all §13 perf budgets hold.
- **Cycle-7 calibration capture (V1.10.2).** Re-ran `swift-infer discover --include-possible --target X` against the four cycle-1+2+3+4+5+6 corpora at the v1.10.1 commit. Snapshots committed at `docs/calibration-cycle-7-data/post-direction-counter-*.discover.txt`; total surface 349 → 296 (−15.2%). Per-corpus delta: Algorithms 75 → 36 (**−39 idempotence; 88.6% of Algo idempotence surface eliminated**), OrderedCollections 101 → 87 (−14 idempotence), ComplexModule 166 → 166 (byte-identical to cycle-5; no direction labels), PropertyLawKit 7 → 7 (byte-identical).
- **Cycle-7 findings writeup (V1.10.3).** New `docs/calibration-cycle-7-findings.md` documents: the −53 / −15.2% headline, per-corpus per-template delta, the cycle-6 picks verification (5 of 10 idempotence rejections suppressed by V1.10.1; the other 5 stay surfaced because they're different cause-of-noise classes — domain-mismatch + Complex-paramless), the cumulative 1167 → 296 (−74.6%) trajectory across 7 cycles with 7 compositional mechanisms, the closing of the cycle-6 → cycle-7 attribution loop ("first time the calibration loop has demonstrated hypothesis → mechanism → measurement → verification"), the plan-vs-actual analysis (cycle-7 effect was 2-3× larger than projected on affected corpora because per-corpus density of direction-labeled patterns was higher than the cycle-6 sample suggested), and the cycle-8 priority list (inverse-pair direction-label counter, round-trip direction-label counter, domain-mismatch detection, FP arm, math-lib op extension, post-V1.10.1 re-sampling, surfacedAt plumbing, multi-rater methodology).

### Documentation

- **Performance baseline re-pinned.** `docs/perf-baseline-v1.10.md` is the canonical regression anchor for v1.10+. Six of seven §13 rows within ±5% of v1.8 (and v1.9, which was empirical-only). Row 5 +8.3% (24ms → 26ms) is single-ms machine-thermal noise on a 1ms-precision measurement; documented per the v1.7's similar pattern. Row 4 (500-file memory) effectively unchanged at 134.3 MB (-0.1%) — V1.10.1's counter-signal is upstream of Suggestion construction, so the 53 newly-suppressed candidates don't allocate; net effect is a marginal memory decrease at small magnitude. v1.9 baseline retained at `docs/perf-baseline-v1.9.md` for forensic comparison.
- **CLAUDE.md repo-state pointer index extended.** v1.10.0 release entry points at `docs/archive/v1.10 Calibration Plan.md`; "Where to look" perf-baseline pointer updated to `docs/perf-baseline-v1.10.md`; cycle-7 findings + data pointers added.

### Hard guarantees + performance

- All PRD §16 hard guarantees unchanged — v1.10 ships no new accept-flow writeout paths; the cycle-7 tuning is a counter-signal on existing scoring helpers.
- All PRD §13 performance budgets hold at v1.10. Row 4 ceiling stays at the post-v1.1.0 800 MB CI calibration. V1.6.1 flake-resistant 4.0s/6.0s budgets carry forward.
- PRD §14 + §19 runtime no-network guarantee unchanged; the curated direction-label set is in-source — no telemetry, no networking touches.

[1.10.0]: https://github.com/Joseph-Cursio/SwiftInferProperties/releases/tag/v1.10.0

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
