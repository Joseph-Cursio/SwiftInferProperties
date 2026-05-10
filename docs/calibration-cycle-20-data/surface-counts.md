# Calibration cycle 20 — surface re-capture (V1.23.A)

**Captured:** 2026-05-10 against the v1.22.0 release tag (`66f9da0`); v1.23 binary-equivalent. Re-uses the V1.22.E discover capture in `docs/calibration-cycle-19-data/post-v1.22-*.discover.txt` (no Sources/ change between v1.22 and v1.23 → suggestion stream byte-stable).

Cycle 20 is the **fourth empirical-only cycle** (after cycles 6 = v1.9, 14 = v1.17, 17 = v1.20). Sample basis: post-v1.22 152-surface across the 4 cycle-1..14 corpora.

## Corpus checkouts

Same as V1.20.A (cycle-17) — sibling checkouts at the same HEAD commits used for V1.21.D + V1.22.E:

| Corpus | Path | HEAD commit |
|---|---|---|
| swift-algorithms / Algorithms | `~/GitHub_projects/swift-algorithms` | `0b43769` |
| swift-collections / OrderedCollections | `~/GitHub_projects/swift-collections` | `19e45ab` |
| swift-numerics / ComplexModule | `~/GitHub_projects/swift-numerics` | `899af71` |
| SwiftPropertyLaws / PropertyLawKit | `~/xcode_projects/SwiftPropertyLaws` | `eeef84e` |

## Aggregate surface delta (cycles 13 + 14 + 17 + 18 + 19 + 20)

| Cycle | Surface | Δ surface | Cumulative Δ vs cycle-1 (1167) |
|---|---:|---:|---:|
| 13 (v1.16) | 229 | -120 vs cycle-6 | −80.4% |
| 14 (v1.17) | 229 | 0 (carry) | −80.4% |
| 17 (v1.20) | 335 | +106 (first reversal) | −71.3% |
| 18 (v1.21) | 165 | -170 (-50.7%) | −85.86% |
| 19 (v1.22) | 152 | -13 (-7.9%) | −86.97% |
| **20 (v1.23)** | **152** | **0 (cycle-19 carry)** | **−86.97%** |

v1.23 ships zero Sources/ changes — surface count carries forward verbatim from cycle 19. The cycle-20 sample basis is the same 152-suggestion pool that V1.22.E captured.

## Per-template per-corpus surface composition

Captured from `docs/calibration-cycle-19-data/post-v1.22-*.discover.txt`:

| Template | Algo | OC | CM | PLK | Total | Δ vs cycle 17 (335) |
|---|---:|---:|---:|---:|---:|---:|
| round-trip | 0 | 10 | 8 | 0 | **18** | **−138** (V1.21.C math-forward + V1.22.B/D direction-+stride-veto) |
| idempotence (non-lifted) | 0 | 22 | 0 | 1 | **23** | **−65** (V1.21.C math-forward closed all 17 CM elementary-functions picks) |
| idempotence-lifted | 5 | 16 | 0 | 0 | **21** | **−23** (V1.21.A + V1.22.A IteratorProtocol veto) |
| monotonicity | 3 | 20 | 0 | 6 | **29** | 0 |
| commutativity | 1 | 10 | 6 | 0 | **17** | 0 |
| associativity | 1 | 10 | 6 | 0 | **17** | 0 |
| inverse-pair (non-lifted) | 0 | 3 | 0 | 0 | **3** | **−1** (V1.22.D Algo `endOfChunk × startOfChunk`) |
| identity-element (non-lifted) | 0 | 0 | 1 | 0 | **1** | 0 |
| dual-style-consistency | 0 | 22 | 0 | 0 | **22** | 0 |
| composition (lifted) | 0 | 1 | 0 | 0 | **1** | 0 (demote-only at V1.21.B) |
| **Total** | **10** | **114** | **21** | **7** | **152** | **−183 (cycle 17 → cycle 20)** |

**Idempotence aggregate (lifted + non-lifted): 44 picks (38 OC + 5 Algo + 1 PLK + 0 CM).** Discover output combines both shapes under the same `Template: idempotence` line; the 38 OC count = 22 non-lifted + 16 lifted; the 5 Algo count = 0 non-lifted + 5 lifted (V1.21.A + V1.22.A closed the Iterator-shape lifted picks but a few sort/shuffle-style OC mutators remain).

## Surviving lifted-suggestion sub-classes

Of the 21 idempotence-lifted picks at v1.22:

- **OC internal-CoW helpers (predicted accept class):** 2 picks per cycle-17 measurement (`OrderedSet._isUnique()`, `OrderedSet._regenerateHashTable()`).
- **OC mutators (predominantly sort / shuffle / reverse / removeFirst / removeLast):** ~14-16 picks. **First measurement of this sub-class on cycle-20 sample** — cycle-17 sampled the BucketIterator class which V1.22.A subsequently closed; this OC mutator class wasn't sampled at cycle-17.
- **Algo lifted survivors:** 5 picks (varies by corpus drift; cycle-19 measurement had `_HashTable.BucketIterator.advance(until:)` (composition-lifted), not idempotence-lifted; the Algo idempotence-lifted picks must be on Sequence-shape mutators not caught by V1.21.A/V1.22.A IteratorProtocol veto).

The 1 composition-lifted pick (`BucketIterator.advance(until:)`) is **demoted from cycle-17's Strong tier to Likely** by V1.21.B — same underlying function, different score. Cycle-20 re-samples this exact pick.

## Round-trip surface composition

Of the 18 round-trip picks at v1.22:

- **CM canonical-inverse anchors (cycle-17 7/7 = 100% accept class):** 7 picks (`exp×log`, `cos×acos`, `sin×asin`, `tan×atan`, `cosh×acosh`, `sinh×asinh`, `tanh×atanh`).
- **CM numerics-extension pair (V1.21.C `canonicalInversePairs` allowlist preserves):** 1 pick (likely `expMinusOne × log1p`).
- **OC `_value(forBucketContents:) × _bucketContents(for:)` codec (cycle-14 #1 / cycle-17 #1 ACCEPT):** 1 pick.
- **OC `index(after:) × _minimumCapacity/_maximumCapacity/_scale(forCapacity:)` asymmetric cross-pairs:** ~9 picks. **First measurement of asymmetric cross-pair class** — cycle-19 finding identifies these as the V1.22.B variance source (single-side direction-counter -15 doesn't suppress; both-sides full-veto requires both labels in DirectionLabels.curated, but `forScale:` is a domain-marker not a direction-label).

## Stratification rebasing for V1.23.C

The v1.23 plan §"Stratification proposal" was provisional. With V1.23.A's surface composition documented, the v1.23 sample of 50 picks rebases:

| Template | v1.22 surface | V1.23.C sample (rebased) | Why |
|---|---:|---:|---|
| round-trip | 18 | **8** | Hold from plan; 4 CM canonical anchors + 1 OC codec + 3 OC asymmetric cross-pair (first measurement of cycle-19-finding class). |
| idempotence (non-lifted) | 23 | **6** | Hold; 4-cycle 0% rate-stability check. |
| idempotence-lifted | 21 | **6** | Hold; 2 OC internal-CoW carry-forward + 4 OC sort/shuffle/reverse first measurement. |
| commutativity | 17 | **3** | Hold. |
| associativity | 17 | **3** | Hold. |
| monotonicity | 29 | **4** | Hold. |
| inverse-pair (non-lifted) | 3 | **2** | Hold. |
| identity-element (non-lifted) | 1 | **1** | Hold; lone outlier carry-forward. |
| dual-style-consistency | 22 | **5** | Hold; 100% by-construction precision rate-stability. |
| composition (lifted) | 1 | **1** | Hold; full coverage at 1/1 (cycle-17 reject demoted by V1.21.B). |
| **NEW class 14 (fixed-point-name)** | 0 | **0** | No surfacing on cycle-1..14 corpora. |
| **Total** | **152** | **39 + 11 = 50** | Sample +4 vs cycle-17's 46 (cycle-17 dropped 4 picks for zero-surface lifted sub-templates; cycle-20 redistributes them — round-trip 8 (vs 7 at cycle-17 had 15 but 7 were CM cross-product noise that V1.21.C closed); idempotence-lifted 6 covers the new OC sort/shuffle/reverse class). |

**Per-corpus sample weight (rebased):**
- **OrderedCollections** dominates: 4 round-trip asymmetric + 1 round-trip codec + 4 idempotence non-lifted + 4 idempotence-lifted + 3 commutativity + 3 associativity + 3 monotonicity + 1 inverse-pair + 5 dual-style + 1 composition-lifted = **~29 OC picks**.
- **ComplexModule**: 4 round-trip canonical anchors + 0 idempotence (V1.21.C closed all) + 0 commutativity + 0 associativity + 0 monotonicity + 0 inverse-pair + 1 identity-element = **~5 CM picks**.
- **Algorithms**: 0 round-trip (V1.22.D closed lone survivor) + 1 idempotence non-lifted + 2 idempotence-lifted + 1 monotonicity + 0 inverse-pair (V1.22.D closed) + 1 commutativity + 1 associativity = **~6 Algo picks**.
- **PropertyLawKit**: 1 idempotence non-lifted + 1 monotonicity = **~2 PLK picks**.

V1.23.C will commit the final per-cell stratification table in `sample-manifest.md`.

## Reproducibility

V1.23.A reuses the V1.22.E capture commands; rerunning is unnecessary since v1.23 binary-equivalent to v1.22:

```sh
INFER=/Users/josephcursio/xcode_projects/SwiftInferProperties/.build/debug/swift-infer
OUT=docs/calibration-cycle-19-data  # V1.22.E captures; v1.23 carries forward

(cd ~/GitHub_projects/swift-numerics && $INFER discover --target ComplexModule --include-possible) \
  > "$OUT/post-v1.22-swift-numerics-ComplexModule.discover.txt"
# … and 3 more for the other corpora
```

## Handoff to V1.23.B (triage rubric refresh) + V1.23.C (50-decision triage)

V1.23.B carries cycle-17's rubric verbatim and adds new sections for:

- **Post-cycle-17 mechanism context** — documents the 7 cycle-18+19 mechanism layers each surviving v1.22 candidate has cleared.
- **NEW lifted-idempotence sub-class: OC sort/shuffle/reverse mutators.** Accept criterion: TBD per cycle-20 measurement (sort is idempotent on already-sorted; shuffle is non-deterministic; reverse is non-idempotent). Reject criterion likely dominates.

V1.23.C samples 50 picks per the rebased stratification above and produces `sample-manifest.md` + `triage-decisions.json` + `triage-notes.md` per the cycles 6 + 14 + 17 schema.
