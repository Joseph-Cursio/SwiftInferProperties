# Would structural name rules name the round trips the vocabulary misses?

> **Status:** `shipped` · **As of:** 2026-09-28

`round-trip-pairing-evidence.md` found type-only pairings 15% true, and the true ones are real inverses
**named in ways the curated vocabulary cannot match**: it compares base names for exact equality against
18 pairs (`encode`/`decode`, `parse`/`format`, …), so `successor`/`predecessor`, `_bridgeObject(fromTagged:)`
/ `(toTagged:)`, `_toUTF16Offsets` / `_toUTF16Indices` and rank/select `slot(of:)` / `bucket(at:)` all read
as type symmetry alone. The census concluded the vocabulary is the lever, not a gate. This measures
whether a few structural rules can pull the true pairings out of the type-only class at a precision worth
a name signal.

## 1. Population

The type-only rows of the post-fix pairing dump — the 838 `round-trip` rows the 25 corpora produce after
`bare-name-pairing.md` — from `RoundTripPairingEvidenceCensusTests`.

## 2. Rules — fixed now, each derived from ONE known true pairing

Names are split into lower-cased camel-case words, leading underscores dropped; a function's *words* are
its base name's words followed by its first argument label's.

| rule | matches when | derived from |
|---|---|---|
| R1 from/to labels | same base name, first labels `from…` / `to…` with the same remainder | `_bridgeObject(fromTagged:)` / `(toTagged:)` |
| R2 antonym word | the two word lists differ in exactly one position, and that pair is one of: successor/predecessor, next/previous, next/prior, after/before, increment/decrement, forward/backward, wrap/unwrap, box/unbox, escape/unescape, quote/unquote, to/from | `successor` / `predecessor` |
| R3 `to`-conversions | both base names are `to…` conversions sharing at least one word after `to`, and differing after it | `_toUTF16Offsets` / `_toUTF16Indices` |
| R4 named after the result | each base name's last word equals the last word of its own return type's bare name | `slot(of:)` → `_HashSlot`, `bucket(at:)` → `_Bucket` |

## 3. Hand-check

Every type-only row any rule matches if there are ≤ 60, else a seeded 60 (`random.Random(20260929)`),
judged by the census's criteria (TRUE / FALSE / UNCLEAR, recorded per row). **The four derivation pairings
are excluded from the precision figure** — a rule built from a pair proves nothing by matching it.

## 4. Predictions

| # | prediction |
|---|---|
| 1 | the rules match **10–60** type-only rows |
| 2 | **≥ 70% TRUE** among matched rows other than the four derivation pairings |
| 3 | R4 is the weakest rule — it has the lowest precision of the four |

**If 2 holds**, the rules become a round-trip name signal and get their own same-code A/B. **If it fails**,
the vocabulary stays curated and the census records why.
