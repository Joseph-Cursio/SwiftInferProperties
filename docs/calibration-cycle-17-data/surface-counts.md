# Calibration cycle 17 — surface re-capture (V1.20.A)

**Captured:** 2026-05-10 against the v1.19 working copy at commit `67fcb0c` (V1.20.0 plan committed; binary-equivalent to V1.19.G `7b50512`). Re-runs the cycle-1+...+14 corpora with the cumulative v1.18 (Workstreams A + C) + v1.19 (Workstream B) mechanism stack active.

Cycle 17's diff target is the **cycle-13 post-V1.16.1 baseline** (the 229-surface from `docs/calibration-cycle-13-data/`). The cycle-13 → cycle-17 delta combines:

- **v1.18.A** carrier-kind structural counter/positive signal (no surface-count change — score-only).
- **v1.18.C** dual-style consistency template + DualStylePairing (NEW template family — adds new candidates).
- **v1.19.B** mutating-method lift admission via `LiftedTransformation` + four template fan-out sites (Idempotence, Composition NEW, IdentityElement-lifted, InversePair-lifted) — adds new candidates from `mutating func` surface that pre-v1.19 was vetoed at template entry.
- **Upstream corpus drift** between cycle-13's commits (captured 2026-05-09 on a different machine) and the v1.20.A clone-at-HEAD checkouts (captured 2026-05-10). This is a confounder for cycle-17 attribution; documented per-corpus below.

## Corpus checkouts

V1.20.A clones the four corpora at HEAD per the v1.20 plan §"Corpora" decision (clone all three at HEAD into `~/GitHub_projects/`; `swift-collections` was already present at HEAD). The `joecursio` paths in cycle-13/14 captures are not available on this machine; the cycle-13 commits the prior captures used were not pinned in `docs/calibration-cycle-13-data/README.md` reproducibility section, so an exact-snapshot replay isn't possible. The HEAD-as-of-2026-05-10 commits are pinned here for V1.20.A reproducibility:

| Corpus | Path | HEAD commit |
|---|---|---|
| swift-algorithms / Algorithms | `/Users/josephcursio/GitHub_projects/swift-algorithms` | `0b43769` (`chore: restrict GitHub workflow permissions - future-proof (#263)`) |
| swift-collections / OrderedCollections | `/Users/josephcursio/GitHub_projects/swift-collections` | `19e45ab` (`Merge pull request #601 from lorentey/hashed-container-fixes`) |
| swift-numerics / ComplexModule | `/Users/josephcursio/GitHub_projects/swift-numerics` | `899af71` (`Merge pull request #328 from stephentyrone/complex-divide-docs`) |
| SwiftPropertyLaws / PropertyLawKit | `/Users/josephcursio/xcode_projects/SwiftPropertyLaws` | `eeef84e` (`docs(CLAUDE.md): rename SwiftProtocolLaws → SwiftPropertyLaws (mechanical pass 3/3)`) |

## Aggregate suppression delta

| Corpus | Cycle-13 (v1.16) total | Cycle-17 (v1.19) total | Δ |
|---|---:|---:|---:|
| swift-numerics / ComplexModule | 166 | 166 | **0** |
| swift-collections / OrderedCollections | 43 | 126 | **+83** |
| swift-algorithms / Algorithms | 13 | 36 | **+23** |
| SwiftPropertyLaws / PropertyLawKit | 7 | 7 | **0** |
| **Total** | **229** | **335** | **+106 (+46.3%)** |

Cumulative trajectory across cycles 1–17:

| Snapshot | Surface | Cumulative Δ vs cycle 1 |
|---|---:|---:|
| Cycle 1 (pre-tune) | 1167 | — |
| Cycle 11 (v1.14) | 251 | −78.49% |
| Cycle 12 (v1.15) | 235 | −79.86% |
| Cycle 13 (v1.16) | 229 | −80.38% (first cycle below 80%) |
| **Cycle 17 (v1.19)** | **335** | **−71.30% (first cycle to reverse the descending trend)** |

**Cycle 17 is the first cycle to reverse the descending trend** — the loop is +106 candidates above cycle 13, driven by Workstream B's lift admission introducing a new candidate class (the entire value-semantic-mutating-function surface) and Workstream C's dual-style consistency template introducing a second new candidate class. This is **expected and consistent with the v1.18 + v1.19 mechanism direction** (recall-positive workstreams that broaden the addressable function surface). The cycle-17 question is whether the 50-decision triage shows the new candidates have higher per-template acceptance rates than the existing pool, raising the aggregate; if not, the trend reversal is precision-negative and the cycle-18 priority list should rotate accordingly.

## Per-template breakdown

| Template | Algo | OC | CM | PLK | Total | Cycle-13 total | Δ |
|---|---:|---:|---:|---:|---:|---:|---:|
| round-trip | 3 | 17 | 136 | 0 | 156 | 139 | **+17** |
| idempotence | 27 | 43 | 17 | 1 | 88 | 25 | **+63** |
| monotonicity | 3 | 20 | 0 | 6 | 29 | 29 | 0 |
| commutativity | 1 | 10 | 6 | 0 | 17 | 17 | 0 |
| associativity | 1 | 10 | 6 | 0 | 17 | 17 | 0 |
| inverse-pair | 1 | 3 | 0 | 0 | 4 | 1 | **+3** |
| identity-element | 0 | 0 | 1 | 0 | 1 | 1 | 0 |
| **dual-style-consistency** (NEW v1.18.C) | 0 | 22 | 0 | 0 | 22 | 0 | **+22** |
| **composition** (NEW v1.19.C) | 0 | 1 | 0 | 0 | 1 | 0 | **+1** |
| **Total** | **36** | **126** | **166** | **7** | **335** | **229** | **+106** |

The per-template delta breakdown:

- **idempotence: +63.** Largest absolute gain. **44 of 63 are lifted suggestions** (V1.19.B `IdempotenceTemplate.suggest(forLifted:)` no-param + x-curried shapes); the remaining +19 is roughly split between OC's `mutating func` admissions on `OrderedSet` / `OrderedDictionary` and Algo's Iterator `next()` admissions, both lifted via Workstream B.
- **dual-style-consistency: +22.** Entirely new template family from V1.18.C. All 22 hits are on OrderedCollections — `OrderedSet` follows the `formX`/`X` and `X`/`Xed` conventions rigorously (`formUnion`/`union`, `formIntersection`/`intersection`, `formSymmetricDifference`/`symmetricDifference`, `sort`/`sorted`, etc.).
- **round-trip: +17.** Modest gain, mostly OC growth. ComplexModule held at 136. Most of the +17 is upstream OC drift (the +83 OC delta minus the new-template gains = ~36 unattributed, which spreads across non-lifted templates including round-trip).
- **inverse-pair: +3.** Modest gain on OC (1 → 3) — likely upstream drift; no inverse-pair-lifted suggestions surfaced (curated pair table didn't match any admitted lifts on these four corpora).
- **composition: +1.** Lone composition-lifted hit on OC. The numeric-only curated additive-monoid gate restricts the surface; OC's mutating APIs that match the gate (`OrderedSet`/`OrderedDictionary` add-style methods on element types) are mostly captured by other template forms.
- **identity-element: 0.** No identity-element-lifted suggestions surfaced. The "increment by 0" canonical case requires a `(T, X) -> T` lift with X in the curated identity name set — none of the four corpora had an `Int` / `Double` parameter on a value-semantic mutating method paired with a curated identity constant in the same compilation unit.

## Lifted vs non-lifted breakdown

V1.19's lift admission contributes 45 of the 335 candidates (13.4% of surface). Per-corpus:

| Corpus | Total | Lifted (V1.19) | Non-lifted |
|---|---:|---:|---:|
| Algorithms | 36 | **20** (all idempotence-lifted: Iterator `next()`-shape) | 16 |
| OrderedCollections | 126 | **25** (24 idempotence-lifted + 1 composition-lifted) | 101 |
| ComplexModule | 166 | 0 | 166 |
| PropertyLawKit | 7 | 0 | 7 |
| **Total** | **335** | **45** | **290** |

Lifted-suggestion class composition:

| Sub-template | Algo | OC | CM | PLK | Total |
|---|---:|---:|---:|---:|---:|
| idempotence-lifted (no-param + x-curried) | 20 | 24 | 0 | 0 | **44** |
| composition-lifted (NEW template family) | 0 | 1 | 0 | 0 | **1** |
| identity-element-lifted | 0 | 0 | 0 | 0 | **0** |
| inverse-pair-lifted | 0 | 0 | 0 | 0 | **0** |
| **Total lifted** | **20** | **25** | **0** | **0** | **45** |

**Algorithms lifted-idempotence dominance (20 of 36).** The Algorithms library is heavy on `IteratorProtocol` conformers (`AdjacentPairsSequence.Iterator`, `ChunksIterator`, `CombinationsIterator`, etc.) — each Iterator's `mutating func next() -> Element?` lifts to a no-param `(Iterator) -> Iterator` shape that admits IdempotenceTemplate's no-param case. The strict admission gate (`isMutating && containingType != nil && carrierKind == .valueSemantic`) holds because Iterator structs are value-semantic; the resulting suggestion baseline is 30 type-symmetry + 5 carrier + 10 lift = **45 → Likely** (the 20 Algorithms lifted-idempotence candidates are all Likely-tier, no curated-verb match). **Per-construction precision concern:** `Iterator.next()` is *not* idempotent (each call advances the iterator); these 20 are predicted false-positives. The cycle-17 50-decision triage will measure whether this prediction holds — if 20/20 reject, the V1.19.B no-param admission is over-broad and cycle-18 priority #1 should suppress `IteratorProtocol` conformers from the lift pool.

**OrderedCollections lifted-idempotence (24 of 126).** Mix of `OrderedSet.removeAll()` and similar no-param mutators on `OrderedSet` / `OrderedDictionary`. Higher per-construction precision than Algo Iterator surface: `removeAll()` *is* idempotent (calling it twice is the same as once); `formUnion(_:Self)` *is* idempotent on the lifted `(OrderedSet, OrderedSet) -> OrderedSet` shape (canonical SetAlgebra idempotent-union). The Algo Iterator class likely dominates the lift's false-positive rate; the OC SetAlgebra-shape class likely dominates its true-positive rate.

## Per-corpus delta attribution

| Corpus | Δ | Attribution |
|---|---:|---|
| ComplexModule | **0** | Byte-stable. `Complex<RealType>` is value-semantic but the corpus is dominated by `static func` ops, not `mutating func` (form-prefix mutating siblings exist but their counts in the AST are small). v1.18+v1.19 mechanisms produced no measurable surface change here; the cycle-13 commit was likely identical to or near `899af71`. |
| PropertyLawKit | **0** | Byte-stable. Consumer-side library with no value-semantic struct mutating APIs. |
| OrderedCollections | **+83** | **+47 attributed to v1.18.C dual-style (22) + v1.19.B lifted (24) + composition (1).** Remaining **+36 attributed to upstream corpus drift** between cycle-13's `joecursio`-machine snapshot and `19e45ab` HEAD. The corpus has been actively developed between captures (the `lorentey/hashed-container-fixes` PR was merged recently). The +36 spreads across non-lifted templates (round-trip, monotonicity, commutativity, associativity, inverse-pair) and is not separable from new-mechanism effects without a same-commit replay. |
| Algorithms | **+23** | **+20 attributed to v1.19.B lifted-idempotence on Iterator structs.** Remaining **+3 attributed to upstream corpus drift** — small, consistent with Algorithms being a more stable library than OC. |

The **upstream-drift confounder is significant for OC (+36 of +83)** and small-but-present for Algo (+3 of +23). For ComplexModule + PropertyLawKit, the zero deltas confirm cycle-13's commit was effectively the same code (or close enough that no surface count moved).

## Stratification rebasing for V1.20.C

The v1.20 plan §"Stratification proposal" was provisional. With V1.20.A's actual surface counts in hand, the rebase:

| Template | Plan provisional | Actual surface | V1.20.C sample (rebased) | Why |
|---|---:|---:|---:|---|
| round-trip | 15 | 156 | **15** | Hold; round-trip dominates ComplexModule which was byte-stable. Sample preserves cycle-14 comparability. |
| idempotence (non-lifted) | 8 | 44 | **6** | Reduce from 8 to 6; non-lifted idempotence rate has been 0% across cycles 6 + 14 (stale measurement); free 2 picks for the high-volume lifted class. |
| commutativity | 3 | 17 | **3** | Hold; small surface, byte-stable. |
| associativity | 3 | 17 | **3** | Hold; small surface, byte-stable. |
| monotonicity | 4 | 29 | **4** | Hold; cycle-14 rate 83% well-characterised. |
| inverse-pair (non-lifted) | 1 | 4 | **2** | Increase from 1 to 2; surface jumped 1 → 4 (mostly OC drift), one extra pick gives modest additional CI. |
| identity-element (non-lifted) | 1 | 1 | **1** | Hold; lone outlier. |
| **dual-style-consistency** (NEW v1.18.C) | 5 | 22 | **5** | Hold; first measurement of new template family. |
| **idempotence-lifted** (NEW v1.19.B) | 3 | 44 | **6** | **Increase from 3 to 6.** Largest new class by volume; need finer-grained rate per sub-corpus (Algo Iterator-dominated 20 picks vs OC SetAlgebra-shape 24 picks have very different precision priors per analysis above). 6 splits as 3 Algo + 3 OC. |
| **composition-lifted** (NEW v1.19.C) | 3 | 1 | **1** | **Reduce from 3 to 1.** Surface only has 1 candidate; sampling 1/1 is full-coverage. |
| **identity-element-lifted** (NEW v1.19.C) | 2 | 0 | **0** | **Drop.** Zero surface; nothing to sample. |
| **inverse-pair-lifted** (NEW v1.19.D) | 2 | 0 | **0** | **Drop.** Zero surface; nothing to sample. |
| **Total** | 50 | 335 | **46** | Down from 50 — the four picks freed by zero-surface lifted classes (composition was 3 → 1 and identity/inverse lifted were 2+2 → 0+0) are not redistributed, since the existing classes are already adequately sampled at the cycle-14-comparable weights. v1.20 ships at **46 picks** rather than 50, with the difference attributed to the actual lifted-class surface composition (only 2 of 4 sub-templates surfaced any candidates). |

**Per-corpus sample weight (rebased):**

- **OrderedCollections** dominates: 5 dual-style + 3 idempotence-lifted + 1 composition-lifted = 9 OC-only picks for new classes, plus existing-class weight from non-lifted surface.
- **ComplexModule**: 11 round-trip + ~3 idempotence (non-lifted) + small associativity/commutativity = ~17–20 picks.
- **Algorithms**: 3 idempotence-lifted + small monotonicity + lone inverse-pair = ~6 picks.
- **PropertyLawKit**: monotonicity + lone idempotence = ~3 picks.

V1.20.C will commit the final per-cell stratification table in `sample-manifest.md`.

## Reproducibility — capture commands

```sh
cd /Users/josephcursio/xcode_projects/SwiftInferProperties
# Debug binary at .build/debug/swift-infer (rebuilt by `swift test`).
INFER=/Users/josephcursio/xcode_projects/SwiftInferProperties/.build/debug/swift-infer
OUT=/Users/josephcursio/xcode_projects/SwiftInferProperties/docs/calibration-cycle-17-data

# swift-numerics / ComplexModule (HEAD 899af71)
(cd /Users/josephcursio/GitHub_projects/swift-numerics && \
  $INFER discover --target ComplexModule --include-possible) \
  > "$OUT/post-v1.19-swift-numerics-ComplexModule.discover.txt"

# swift-collections / OrderedCollections (HEAD 19e45ab)
(cd /Users/josephcursio/GitHub_projects/swift-collections && \
  $INFER discover --target OrderedCollections --include-possible) \
  > "$OUT/post-v1.19-swift-collections-OrderedCollections.discover.txt"

# swift-algorithms / Algorithms (HEAD 0b43769)
(cd /Users/josephcursio/GitHub_projects/swift-algorithms && \
  $INFER discover --target Algorithms --include-possible) \
  > "$OUT/post-v1.19-swift-algorithms-Algorithms.discover.txt"

# SwiftPropertyLaws / PropertyLawKit (HEAD eeef84e)
(cd /Users/josephcursio/xcode_projects/SwiftPropertyLaws && \
  $INFER discover --target PropertyLawKit --include-possible) \
  > "$OUT/post-v1.19-SwiftPropertyLaws-PropertyLawKit.discover.txt"
```

## Handoff to V1.20.B (triage rubric refresh) + V1.20.C (50-decision triage)

V1.20.B carries cycle-14's rubric verbatim and adds new sections for:

- **Dual-style consistency** (V1.18.C). Accept criterion: curated pair name describes a real dual-style sibling and the mutating method's effect equals the non-mutating sibling's return value. Reject criterion: name match without semantic correspondence.
- **Idempotence-lifted** (V1.19.B). Accept criterion: the underlying `mutating func` is genuinely idempotent in its lifted shadow form (e.g., `removeAll()` lifted is idempotent; `formUnion(_:Self)` x-curried is idempotent). Reject criterion: lift admission was structurally sound but the underlying method is not idempotent (e.g., `Iterator.next()` advances state — predicted reject for all 20 Algo picks).
- **Composition-lifted** (V1.19.C). Accept criterion: `op(op(s, a), b) == op(s, a + b)` actually holds for the underlying `mutating func` (i.e., the parameter contributes additively without clamping/saturation). Reject criterion: clamp / non-linear / non-additive transform.

V1.20.C samples 46 picks per the rebased stratification above and produces `sample-manifest.md` + `triage-decisions.json` + `triage-notes.md` per the cycles 6 + 14 schema.
