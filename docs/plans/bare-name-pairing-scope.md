# Pair round trips by the type a name MEANS, not how it is spelled

> **Status:** `shipped` · **As of:** 2026-09-28

`round-trip-pairing-evidence.md` found that 15 of 39 false pairings in its hand-check — and none of the
21 true ones — pair functions on **different nested types that share a bare name**: OpenAPIKit's
`Document.CodingKeys.stringValue` (`CodingKeys -> String`) with `Operation.CodingKeys.extendedKey(for:)`
(`String -> CodingKeys`). `FunctionPairing` compares type TEXT, and both spell their type `CodingKeys`.
Population: **1,520 rows fully qualified to different types, all in OpenAPIKit**, 0 in the other 24
corpora. It is the defect `FunctionPairing.resolvingSelf` already fixed for `Self` — a textually
symmetric spelling generating a clique — through a different spelling.

## 1. The change

Before comparing, resolve each bare type name in a function's domain and codomain the way Swift's name
lookup does: from the function's `qualifiedContainingTypeName` outward, take the first
`<scope>.<Name>` that is a type the scanned summaries declare. `Self` resolves to the qualified
containing type. A name already qualified keeps its head resolved the same way; a name that resolves
nowhere stays as written, on both sides alike.

**It cannot cost a true pairing by construction**: two functions of the same type resolve a name the same
way, and a real inverse between two different types already has different type text.

## 2. Measurement

- **Direct A/B**: the pairing census dump (`RoundTripPairingEvidenceCensusTests`) re-run on the change,
  against the 2,372 rows recorded before it, same corpora, same commits.
- **Every corpus survey**: a full `make test`, whose measured batches assert discovery baselines over the
  manifest corpora — the involution gate's lesson.

## 3. Predictions

| # | prediction |
|---|---|
| 1 | OpenAPIKit's round-trip rows fall from 1,686 by **≥ 1,400** |
| 2 | the 20 manifest corpora move by **≤ 5** round-trip rows in total, and no removed row pairs two functions with the same qualified containing type |
| 3 | all **21 TRUE** pairings in the hand-check sample survive |
| 4 | `make test` green with every batch baseline unchanged |
| 5 | the three NAMED collisions (jwt-kit's key types, `JSONReference.Path`) **survive** — one side is recorded unqualified, so this rule cannot see them |

## 4. What this does not answer

One subject carries the whole population. The rule reads declared types from the summaries, so a nested
type that declares no function is not known to it and a name referring to it stays bare — on both sides.
