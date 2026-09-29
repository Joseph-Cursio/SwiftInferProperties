# Would structural name rules name the round trips the vocabulary misses? — not at a usable precision

> **Status:** `measured` · **As of:** 2026-09-28

`round-trip-pairing-evidence.md` pointed at the vocabulary: type-only pairings are 15% true, and the true
ones are inverses named in ways a curated list of 18 exact base-name pairs cannot match. This tried four
structural rules — each derived from one of those true pairings — over the 763 type-only rows of the
post-`bare-name-pairing.md` dump. Plan and predictions in `docs/plans/inverse-name-vocabulary-scope.md`;
the matcher is `scripts/inverse_name_rules.py`; the matched rows were frozen before being read
(`fixtures/inverse-name-sample.json`) and every judgement is recorded (`fixtures/inverse-name-judgements.json`).

## Result

**The rules match 14 of 763 type-only rows**; 4 are the pairings they were derived from and prove nothing,
so precision is read on the other **10: 6 TRUE, 4 FALSE — 60%**, below the 70% bar.

| rule | matched (excluding derivation) | TRUE |
|---|---:|---:|
| R1 from/to labels | 0 | — |
| R2 antonym word (`successor`/`predecessor`, `next`/`previous`, …) | 3 | 2 |
| R3 `to`-conversions (`_toUTF16Offset` / `_toUTF16Index`) | 1 | 1 |
| R4 named after the result (rank/select) | 7 | 4 |

The TRUE ones are real inverses — `_successor` / `_predecessor`, `_toUTF16Offset` / `_toUTF16Index`,
`_bridgeObject(fromNativeObject:)` / `_nativeObject(fromBridge:)`, `_toUTF16CodeUnit` / `_fromUTF16CodeUnit`
on ASCII. The FALSE ones are instructive: `nextPowerOf2` / `previousPowerOf2` share an antonym and are not
inverses; `capacity` / `allocateStorage(capacity:)` rounds up; and two rows pair
`ObjectiveCConvertibleAttributedStringKey`'s **Int-backed** `objectiveCValue(for:)` (an `NSNumber`) with its
**String-backed** `value(for:)` — the same type, but two constrained extensions whose `ObjectiveCValue`
differs, a pairing across `where` clauses rather than a name failure.

## The predictions, scored

| # | prediction | result | |
|---|---|---|---|
| 1 | the rules match 10–60 type-only rows | **14** | ✅ |
| 2 | ≥ 70% TRUE outside the derivation pairings | **60%** (6 of 10) | ❌ |
| 3 | R4 is the weakest rule | R4 **57%**, R2 67%, R3 100% (n = 7, 3, 1) | ✅, on tiny counts |

## So what

**Not built.** Below the bar, and small either way: the rules reach 10 rows of 763, while the census's 15%
estimates on the order of a hundred true type-only pairings — so even a perfect version of these rules
would name about one in ten of them. The rest have no pattern in their names that a rule could read. The
census's conclusion that *the vocabulary is the lever* is refined, not reversed: the lever exists, and it
is short. The cross-extension pairing (`where Value.RawValue == Int` against `== String`) is a second
instance of pairing by a spelling that does not identify a type, and is recorded here, not fixed.

## What this does not answer

Ten judgements. A rule's precision on n = 1–7 is an anecdote, reported because the prediction named it.
