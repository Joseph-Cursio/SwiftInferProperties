# What licenses a `round-trip` pairing? — mostly nothing, and the obvious gate still fails

> **Status:** `measured` · **As of:** 2026-09-28

Open-threads row 70 found `round-trip` choosing an inverse on type signature alone and closed two gates
for it. This census asked what the pairing itself rests on, before building a third. Plan, classes and
predictions in `docs/plans/round-trip-pairing-evidence-scope.md`, committed with the dump
(`RoundTripPairingEvidenceCensusTests`) before it ran; the hand-check sample, frozen before any row was
read, is `fixtures/round-trip-pairing-sample.json`, and **every judgement is recorded per row** in
`fixtures/round-trip-pairing-judgements.json` so any one of them can be disputed.

## Population

**2,372 `round-trip` suggestions**, every tier, over the 20 manifest corpora and five unmet subjects
(Euclid, swift-docc, OpenAPIKit, jwt-kit, swift-system). ⚠ **OpenAPIKit alone is 1,686 of them (71%)** —
see the collision below — so every share is also given without it.

| class (the template's own signals) | all | without OpenAPIKit |
|---|---:|---:|
| NAMED — `exactNameMatch` | 93 | 73 |
| DOCUMENTED — `docstringCorroboration` | 1 | 1 |
| ANNOTATED — `discoverableAnnotation` | 0 | 0 |
| **TYPES-ONLY — type symmetry alone** | **2,278 (96%)** | **612 (89%)** |

The template's own `endomorphismRoundTripPair` and `crossTypeRoundTripPair` penalties appear on **none** of
the 2,372 rows, so the scope's TYPES-ONLY sub-split read *other* for every row.

## Hand-check — 61 rows, read one by one

| class | TRUE | FALSE | UNCLEAR |
|---|---:|---:|---:|
| TYPES-ONLY (40) | **6** (15%) | 34 | 0 |
| NAMED (20) | **14** (70%) | 5 | 1 |
| DOCUMENTED (1) | 1 | 0 | 0 |

The six TRUE type-only pairings are real inverses **whose names say so in a way no vocabulary entry
matches**: `successor()` / `predecessor()`, `_bridgeObject(fromTagged:)` / `(toTagged:)`,
`_toUTF16Offsets` / `_toUTF16Indices`, `_Bitmap.slot(of:)` / `bucket(at:)` (rank and select), and two
`stringValue` pairs. The FALSE ones are what row 70 described — a projection paired with an unrelated
construction (`byteSize` / `newlines`, `appendingPath` / `lastPathComponent`, `pitch` / `roll`), siblings
(`leftChild` / `rightChild`), two functions that both set bits.

## The predictions, scored

| # | prediction | result | |
|---|---|---|---|
| 1 | TYPES-ONLY ≥ 60% of rows | **96%**; 89% without OpenAPIKit | ✅ |
| 2 | row 70's eight Euclid pairings all TYPES-ONLY | all eight, and every Euclid row | ✅ |
| 3 | TYPES-ONLY ≤ 20% TRUE; NAMED ≥ 70% TRUE | **15%**; **70%** (14 of 20, 74% of those decided) | ✅ |
| 4 | *require a positive pairing signal* removes ≥ 80% of FALSE and ≤ 20% of TRUE | **87%** of FALSE — and **29%** of TRUE | ❌ |

**So row 70's third gate is closed too.** Requiring a name would remove most false pairings and 6 of the
21 true ones in the sample; weighted by population it is worse, since TYPES-ONLY is so large that its 15%
true rate is more real round trips than the whole NAMED class holds. The true type-only pairs are named
in a way the curated vocabulary does not know — which says the vocabulary is the lever, not a gate.

## The separable defect this found: pairing by BARE type name

**15 of the 39 FALSE pairings (38%), and none of the TRUE ones, pair functions on different nested types
that share a bare name.** Twelve are OpenAPIKit's `X.CodingKeys.stringValue` paired with
`Y.CodingKeys.extendedKey(for:)` — `String ↔ CodingKeys` reads symmetric because both spell their type
`CodingKeys`. The other three are NAMED: jwt-kit pairs `ECDSA.PublicKey(pem:)` with
`RSA.PublicKey.pemRepresentation`, and `ECDSA.PrivateKey` with EdDSA's; OpenAPIKit pairs
`JSONReference.Path.rawValue` with a different `Path(rawValue:)`.

**Population: 1,520 rows where both sides are fully qualified to different types — every one in
OpenAPIKit, whose many nested `CodingKeys` each declare `extendedKey(for:)` and pair quadratically.**
Zero in the other 24 corpora and zero in the 20 manifest corpora. The three NAMED cases are not in that
count: one side is recorded unqualified, so only resolving the declaring type — not comparing names —
would catch them.

A fix would resolve a bare nested type in a signature to its declaring scope before pairing, the way the
accept path now resolves a nested alias. It cannot cost a true pairing, since a real inverse between two
different types already has different type text. ⚠ **Its population is one subject**, which is the
concentration objection this repo has declined fixes on — and also the shape of the module-qualified
leaf fix, built as a correctness fix at population 1. Not built here.

## What this does not answer

Sixty-one judgements by one reader, recorded so they can be checked. The sample is stratified by class,
not proportional, so the class rates are rates within a class. And it says nothing about round trips
the template never proposed — including the ones a better vocabulary would let it name.
