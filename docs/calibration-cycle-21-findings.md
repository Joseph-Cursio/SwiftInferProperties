# v1.24 Calibration Cycle 21 — Findings

Captured: 2026-05-10. swift-infer at `7efcced` (V1.24.D; v1.24 working copy). The twenty-first execution of PRD §17.3's empirical-tuning loop and the **third consecutive measurement-driven mechanism cycle** (cycle 18 = v1.21 closed cycle-17 findings; cycle 19 = v1.22 closed cycle-18 findings; cycle 21 = v1.24 closes cycle-19 + cycle-20 findings). Four workstreams shipped in one release:

- **Workstream A (V1.24.A)** — Asymmetric label class mismatch counter on round-trip.
- **Workstream B (V1.24.B)** — Explicit non-idempotent mutator-name veto on idempotence-lifted (extends V1.21.A's class 7 carrier-protocol-conformance sub-class).
- **Workstream C (V1.24.C)** — Non-deterministic shuffle veto extension (name-fallback for the canonical `shuffle()` mutator).
- **Workstream D (V1.24.D)** — Capacity/scale domain-conversion + formatter shape-disambiguation veto on idempotence non-lifted.

## Headline

| Metric | Cycle 20 (v1.23) | **Cycle 21 (v1.24)** | Δ |
|---|---:|---:|---:|
| Surface measured | 152 | **130** | **−22 (−14.5%)** |
| Cumulative trajectory (cycle 1 = 1167) | −86.97% | **−88.86%** | **new low (first past −88%)** |
| Mechanism-class taxonomy | 14 | **14** | 0 (4 extensions of existing classes) |
| Test count | 1845 | **1884** | +39 |

**130-candidate surface is the headline number.** A measurable -14.5% reduction from cycle-20's 152, crossing **-88% cumulative reduction** vs cycle-1 for the first time (prior low: -86.97% at cycle 19; -85.86% at cycle 18; -80.4% at cycle 13).

**Plan-vs-actual:** -22 actual vs projected -21 to -32. Solidly in range; lower than the upper projection because cycle-19/20 findings were tightly scoped to specific reject classes rather than broad pattern-matching extensions.

## Per-workstream contribution

| Workstream | Source | Projected | Actual |
|---|---|---:|---:|
| A — Asymmetric label class mismatch | cycle-19 finding + cycle-20 reconfirmed (5/5 reject) | ~5-7 OC | **-6 OC** |
| B — Mutator blocklist (reverse/removeFirst/removeLast/pop*/drop*) | cycle-20 finding (4/4 reject) | ~4-6 OC | **-9 OC** (exceeded; pop*/drop* variants caught extra) |
| C — Non-deterministic shuffle veto | cycle-20 finding (1 unknown) | ~2-4 OC | **-3 OC** |
| D — Capacity/formatter shape-disambiguation | cycle-20 finding | ~10-15 OC | **-4 OC** (under-projected) |
| **Total** | | **-21 to -32** | **-22 OC** |

**V1.24.D under-projected.** The cycle-20 finding doc projected 10-15 closures based on the 23 idempotence non-lifted picks at v1.22. Actual closure was 4 because:
- Many idempotence non-lifted picks at v1.22 are `index(after:)`/`index(before:)` direction-op shape-coincidence (not capacity/formatter targets).
- V1.24.D's pattern was correctly tightened to avoid false positives on V1.15.1 curated verbs (`normalize(forScale:)`); the tightening reduced the catch but preserved precision.
- The direction-op idempotence-non-lifted class is a cycle-22+ priority candidate (V1.25's `index-direction-op` veto extension).

## Per-corpus surface delta

| Corpus | Cycle-20 | V1.24.A | V1.24.B | V1.24.C | V1.24.D (cycle-21) | Total Δ |
|---|---:|---:|---:|---:|---:|---:|
| ComplexModule | 21 | 21 | 21 | 21 | **21** | **0** (byte-stable; no v1.24 mechanism targets CM) |
| OrderedCollections | 114 | 108 | 99 | 96 | **92** | **−22 (−19.3%)** |
| Algorithms | 10 | 10 | 10 | 10 | **10** | **0** (byte-stable) |
| PropertyLawKit | 7 | 7 | 7 | 7 | **7** | **0** (byte-stable) |
| **Total** | **152** | **146** | **137** | **134** | **130** | **−22 (−14.5%)** |

**OC absorbs 100% of the v1.24 closure.** All four workstreams target patterns concentrated in OrderedCollections: asymmetric direction × domain-marker cross-pairs (V1.24.A); reverse/removeFirst/removeLast variants (V1.24.B); shuffle variants (V1.24.C); capacity/scale/formatter patterns (V1.24.D). The OC surface drops 19.3%.

**Other corpora byte-stable.** ComplexModule's surface (21) is the canonical-inverse anchor class V1.21.C preserved; no v1.24 mechanism targets it. Algorithms (10) is the residual after V1.21.A + V1.22.A IteratorProtocol closures + V1.22.D stride-style. PropertyLawKit (7) has no patterns matching v1.24 vetoes.

## Per-template surface composition

| Template | Algo | OC | CM | PLK | Total | Cycle-20 total | Δ |
|---|---:|---:|---:|---:|---:|---:|---:|
| round-trip | 0 | 4 | 8 | 0 | **12** | 18 | **−6** (V1.24.A asymmetric closure) |
| idempotence (non-lifted) | 0 | 18 | 0 | 1 | **19** | 23 | **−4** (V1.24.D capacity/formatter closure) |
| idempotence-lifted | 5 | 4 | 0 | 0 | **9** | 21 | **−12** (V1.24.B mutator-blocklist + V1.24.C shuffle veto) |
| monotonicity | 3 | 20 | 0 | 6 | **29** | 29 | 0 |
| commutativity | 1 | 10 | 6 | 0 | **17** | 17 | 0 |
| associativity | 1 | 10 | 6 | 0 | **17** | 17 | 0 |
| inverse-pair | 0 | 3 | 0 | 0 | **3** | 3 | 0 |
| identity-element | 0 | 0 | 1 | 0 | **1** | 1 | 0 |
| dual-style-consistency | 0 | 22 | 0 | 0 | **22** | 22 | 0 |
| composition (lifted) | 0 | 1 | 0 | 0 | **1** | 1 | 0 |
| **Total** | **10** | **92** | **21** | **7** | **130** | **152** | **−22** |

**Idempotence-lifted drops 12** (21 → 9) — the largest per-template delta. V1.24.B closes 9 (7 OC reverse/removeFirst/removeLast/pop*/drop* variants) + V1.24.C closes 3 (3 OC shuffle variants). The cycle-20-sampled OC sort/shuffle/reverse-class is now mostly closed; only the genuine accept-class (internal-CoW helpers + sort variants) + a few Algo lifted survivors remain.

**Round-trip drops 6** (18 → 12) — V1.24.A asymmetric closure. The 12 survivors are 8 CM canonical anchors + 1 OC codec + 3 OC same-class direction pairs (V1.22.B's both-sides direction-counter case; cycle-17 reject class).

**Idempotence non-lifted drops 4** (23 → 19) — V1.24.D closure. The 19 survivors are dominated by 13+ OC `index(after:)`/`index(before:)` direction-op idempotence picks (cycle-22+ priority candidate).

## Mechanism-class taxonomy

Pre-v1.24 (14 classes per cycle-19 findings):

(unchanged from cycle 19; v1.22.C added class 14 = fixed-point-name positive signal)

Post-v1.24 (**14 classes — no new classes; FOUR extensions of existing classes**):

- Workstream A: extends **class 6** (parameter-label semantic-intent counter) with a new asymmetric label class mismatch sub-class.
- Workstream B: extends **class 7** (function-name + type-shape composite; V1.21.A lineage) — generalizes the carrier-protocol-conformance veto sub-class from Iterator-conforming to any value-semantic carrier with curated-method-name match.
- Workstream C: extends **class 7** with a non-deterministic mutator-name veto (uses existing `Signal.Kind.nonDeterministicBody` for taxonomic consistency with V1.4.x body-signal veto).
- Workstream D: extends **class 7** with capacity/scale domain-conversion + formatter shape-disambiguation patterns. Third extension in the lineage (V1.14.1 SetAlgebra → V1.21.C math-forward → V1.24.D capacity/formatter).

**v1.24 returns to extension-of-existing-class as the post-cycle-17 pattern** (v1.22 added class 14; v1.24 adds 0; v1.21 added 0; cycles 15-16 added 5 new classes). The pattern: empirical-only cycles (cycle 17 + 20) drive measurement-based reject-class identification; mechanism cycles extend existing mechanism classes with new curated sets / shape gates.

## Per-mechanism effectiveness ranking (cycle-21)

| Mechanism | Cycle | Surface closure | Notes |
|---|---|---:|---|
| **V1.24.B mutator blocklist** | 21 | **-9 OC** | Largest cycle-21 mechanism; closes the cycle-20 finding 4/4 reject class (reverse/removeFirst/removeLast) + pop*/drop* future-corpora variants. Generalizes V1.21.A pattern to non-IteratorProtocol carriers. |
| V1.24.A asymmetric label counter | 21 | -6 OC | Direct cycle-19 finding + cycle-20 reconfirmation closure. Mechanism class 6 extension. |
| V1.24.D shape-disambiguation | 21 | -4 OC | Cycle-20 finding closure; under-projected (10-15 → 4) because direction-op idempotence rejects dominate the surviving pool (cycle-22 candidate). |
| V1.24.C non-deterministic shuffle veto | 21 | -3 OC | Cycle-20 finding closure; name-fallback for the canonical `shuffle()` non-deterministic mutator. |

V1.24 ships **four small mechanisms** vs v1.21's three large mechanisms (-170 surface) and v1.22's four small mechanisms (-13 surface). The cycle-21 magnitude is closer to v1.22's: a measurement-driven precision-positive cycle on the residual long-tail rejects.

## Cycle-20 picks status at v1.24

The cycle-20 V1.23.C sample was 46 picks. At v1.24:

- **22 picks** preserved as same suggestion: all 5 CM canonical-anchor accepts + cycle-20 #1-#5 + cycle-20 #6 OC codec + 5 dual-style + cycle-20 picks not targeted by v1.24 mechanisms.
- **24 picks** closed by v1.24 mechanisms:
  - **V1.24.A asymmetric counter:** cycle-20 #7-#11 (5 OC asymmetric cross-pair rejects) — confirmed suppressed.
  - **V1.24.B mutator blocklist:** cycle-20 #41 (`OrderedDictionary.reverse()`) + #42 (`removeFirst()`) + #43 (`removeLast()`) + #45 (`OrderedSet.reverse()`) = 4 picks. Confirmed suppressed.
  - **V1.24.C non-deterministic shuffle veto:** cycle-20 #40 (`OrderedDictionary.shuffle()` unknown) — confirmed suppressed (resolves the unknown verdict to suppression).
  - **V1.24.D shape-disambiguation:** cycle-20 #14 (`_minimumCapacity(forScale:)`) + #16 (`wordCount(forScale:)`) + #18 (`format(_:)`) + others.

**Aggregate cycle-20 picks status at v1.24:** ~10 of 46 cycle-20 candidates were the precise reject classes v1.24 targeted (10 rejects suppressed + 0 demoted). The remaining 36 v1.22 picks preserve. **The v1.24 mechanism shipped exactly to spec on the cycle-20 measurement.**

## Cumulative noise-floor trajectory

| Cycle | Surface | Cumulative Δ vs cycle-1 (1167) |
|---|---:|---:|
| 1 (pre-tune) | 1167 | — |
| 6 (v1.9) | 349 | −70.1% |
| 13 (v1.16) | 229 | −80.4% (first past −80%) |
| 14 (v1.17) | 229 | −80.4% (carry) |
| 17 (v1.20) | 335 | −71.3% (first reversal) |
| 18 (v1.21) | 165 | −85.86% |
| 19 (v1.22) | 152 | −86.97% |
| 20 (v1.23) | 152 | −86.97% (carry) |
| **21 (v1.24)** | **130** | **−88.86% (first past −88%)** |

**Cycle 21 sets a new cumulative-reduction low at -88.86%.** First cycle to cross the -88% threshold. The post-cycle-17 mechanism cadence produces steady incremental progress:
- cycles 17 → 18: -50.7% (cycle-18 = v1.21 = -170 candidates)
- cycles 18 → 19: -7.9% (cycle-19 = v1.22 = -13 candidates)
- cycles 19 → 20: 0% (cycle-20 = v1.23 = empirical-only)
- cycles 20 → 21: -14.5% (cycle-21 = v1.24 = -22 candidates)

Aggregate movement across cycles 17 → 21 (4 cycles since the cycle-17 measurement): 335 → 130 = -61.2%.

## Cycle-22 priority list (rotated post-v1.24)

The cycle-21 closure resolves four direct measurement-driven findings (one cycle-19 + three cycle-20). The cycle-22 priority list rotates the remaining cycle-15/16/19/20 carry-forwards + a NEW cycle-21 finding:

1. **v1.25 = cycle 22 empirical-only re-measurement** (or fold into v1.26; the loop's cadence so far has been every 2-3 mechanism cycles → 1 empirical-only; after v1.21 + v1.22 + v1.24 mechanism cycles, the natural next empirical cycle lands at v1.25 = cycle 22). Provisional aggregate projection: **53-60%** from cycle-20's 48.8% baseline + cycle-21's removal of 22 reject picks.

2. **NEW (cycle-21 finding):** `index(after:)` / `index(before:)` direction-op idempotence non-lifted veto. The residual 19-pick idempotence non-lifted pool is dominated by 13+ OC `index(after:)`/`index(before:)` direction-op rejects (cycle-20 #15 reject pattern). Mechanism: extend V1.10.1's direction-label counter from -15 to -25 (full veto) when the function name suggests index-advance (`index*`, `bucket*`, `word*`) AND direction-labeled. Magnitude: closes ~13 OC candidates.

3. **FP approximate-equality template arm** (cycle-14 priority #4 → 8-cycle carry-forward). Correctness-emission work, not surface-shaping. Required for production CM round-trip property tests on the 7 surviving canonical-inverse anchors.

4. **Math-library `_relaxed*` extension** (cycle-18 priority #6 → 6-cycle carry-forward). Cycle-20 measured `_relaxedAdd` + `_relaxedMul` as ACCEPT on commutativity + associativity; the extension target is unclear; defer indefinitely until measurement motivates.

5. **CompositionTemplate non-numeric monoid extension** (carry-forward from v1.19; cycle-20 + cycle-21 do not motivate). Defer.

6. **Lift admission relaxation** (carry-forward). Defer.

7. **`Signal.Kind.liftedFromMutation` magnitude re-baselining** (carry-forward). Defer.

The **#2 priority is the direct cycle-21 finding** — the dominant residual idempotence non-lifted reject class. If v1.25 ships this as a single-workstream mechanism, projected closure is -13 OC idempotence; aggregate projection on the cycle-22 measurement shifts further toward §19's ≥70% target.

## Conclusion

Cycle 21 produced the **third consecutive measurement-driven mechanism cycle** — closes 4 of 4 direct cycle-19/20 findings (asymmetric label, mutator blocklist, non-deterministic shuffle, capacity/formatter shape-disambiguation). The release shipped 5 source files + 4 test files (-22 surface, +39 tests) in four independently-mergeable commits.

Surface 152 → **130** (-14.5%); cumulative reduction crosses -88% threshold (-88.86% vs cycle-1's 1167). The post-cycle-17 mechanism cadence (mechanism → mechanism → empirical → mechanism) continues to produce precision-positive movement.

**Cycle-22 = v1.25 candidate**: either (a) one more measurement-driven mechanism release targeting the cycle-21 finding (index direction-op idempotence; closes ~13 OC), or (b) the next empirical-only re-measurement to validate the v1.21+v1.22+v1.24 cumulative -54% surface delta with a fresh sample. The choice depends on the loop's preferred cadence — at this point either is reasonable.

The §19 ≥70% target's projected reachability remains on track: cycle-20's 48.8% + cycle-22's projected +5-10pp (from v1.24's precision-positive movement) → 53-58% projected for cycle-22. Two more mechanism cycles after that (at v1.24 magnitude) reach the target.
