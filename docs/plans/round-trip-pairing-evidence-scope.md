# What licenses a `round-trip` pairing? — a census before any gate

> **Status:** `shipped` · **As of:** 2026-09-28

Open-threads row 70: `round-trip` can choose an inverse on type signature alone — `Rotation.yaw(r.angle)
== r`, and unrelated `Vector -> Vector` functions paired as inverses on Euclid. Two gates have been
measured and closed: **degrees of freedom** (not computable from a shape, its proxy kills
`URL(string: u.absoluteString) == u`, and it covers 3 of the 8) and **the `Possible` tier** (it refutes
44% against 17% on Euclid and 19% against 39% on swift-docc — the direction reverses). Neither asked what
the pairing itself rests on. This does, and builds nothing until it knows.

## 1. Population

Every `round-trip` suggestion `TemplateRegistry.discover` produces — every tier, as the index takes
them — over the **20 manifest corpora** plus **five unmet subjects** (Euclid `a597cf5`, swift-docc
`f14e4a4`, OpenAPIKit `41a79a6`, jwt-kit `373c40c`, swift-system `1b452c2`), dumped with both functions
and every signal by the opt-in `RoundTripPairingEvidenceCensusTests`.

## 2. Classes — read from the template's own signals, fixed now

| class | rule |
|---|---|
| NAMED | an `exactNameMatch` signal (curated or project-vocabulary inverse names) |
| ANNOTATED | a `discoverableAnnotation`, no name |
| DOCUMENTED | a `docstringCorroboration`, no name or annotation |
| TYPES-ONLY | none of the above: the pairing rests on `typeSymmetrySignature` alone |

TYPES-ONLY is split by the template's own penalties: **endomorphism** (`T -> T` both ways), **cross-type**,
and **other**.

## 3. Hand-check — the only way to know if a pairing is real

A seeded sample (`random.Random(20260928)`), no corpus above a third of a class: **up to 40 TYPES-ONLY
rows and up to 20 NAMED rows**, plus every ANNOTATED and DOCUMENTED row if there are ≤ 20 of each. Each
is judged by reading both functions: **TRUE** if the inverse undoes the forward function on the forward
function's image (as documented or as implemented), **FALSE** if not, **UNCLEAR** if the source cannot
settle it — UNCLEAR is reported, never folded into either side.

## 4. Predictions

| # | prediction |
|---|---|
| 1 | TYPES-ONLY is **≥ 60%** of round-trip rows |
| 2 | Row 70's eight Euclid pairings are **all TYPES-ONLY** |
| 3 | hand-checked TYPES-ONLY rows are **≤ 20% TRUE**; NAMED rows **≥ 70% TRUE** |
| 4 | the candidate gate — *require a positive pairing signal beyond type symmetry* — would remove **≥ 80%** of the FALSE pairings in the sample and **≤ 20%** of the TRUE ones |

If 3 and 4 hold, the gate is a candidate and gets its own same-code A/B over every corpus survey before
it ships (the involution gate's lesson). If they fail, row 70 records a third closed gate.

## 5. What this does not answer

A hand-check is one reader's judgement of intent, recorded per row so it can be disagreed with. It says
nothing about pairings the template never proposed. And a real round trip can still fail its law for an
unrelated reason (floating point, a lossy field), which is a different question from whether the pairing
is licensed.
