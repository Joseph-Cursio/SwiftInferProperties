# Pairing round trips by the type a name means — built, and it costs no true pairing

> **Status:** `measured` · **As of:** 2026-09-28

`round-trip-pairing-evidence.md` found `FunctionPairing` comparing type TEXT, so OpenAPIKit's dozens of
nested `CodingKeys` — each with `var stringValue: String` and `static func extendedKey(for: String) ->
CodingKeys` — paired with one another: `Document.CodingKeys.stringValue` proposed as the inverse of
`Operation.CodingKeys.extendedKey(for:)`. Plan and predictions in `docs/plans/bare-name-pairing-scope.md`,
committed before any code.

## The change

A bare type name in a function's domain or codomain now resolves the way Swift's lookup does — from the
function's qualified containing type outward, the first `<scope>.<Name>` the scanned summaries declare —
after `Self` resolution, which fixed the same clique through a different spelling. Resolved once per
function; the pairing loop is quadratic.

## A second defect the A/B found first

**The first A/B lost 8 of the 21 true pairings in the hand-check sample** — every one an initializer:
`Bucket(offset:)` against `_HTable.Bucket.offset`. `InitializerDecodeSynthesizer` built each synthetic
init summary from the declaration's **bare** name, so an init on `_HTable.Bucket` claimed a top-level
`Bucket` and resolved differently from its own type's methods. `TypeDecl.qualifiedName` already held the
path; the synthesizer dropped it. Fixed as its own commit, and the A/B re-run.

## Result — same-code A/B, 25 corpora, the pairing census dump before and after

| | before | after |
|---|---:|---:|
| round-trip rows, all 25 corpora | 2,372 | **838** |
| OpenAPIKit | 1,686 | **166** |
| the 20 manifest corpora | 567 | 564 |
| rows removed / added | — | 1,539 / 5 |

**No removed row pairs two functions of the same qualified type.** The three manifest removals are
initializers paired with a different type's method (`Index(_offset:)` against `EnumeratedSequence._offset(of:)`).
The 5 added rows are same-type pairs (`JSONSchema.VendorExtensionKeys`, swift-docc's `Platform.Name`) that
no longer lose to a cross-type pair sharing their signature text — inferred, not traced.

**Against the hand-check:** all **21 TRUE** pairings survive, and of the 39 FALSE ones exactly the **15
collisions** are removed and nothing else.

## The predictions, scored

| # | prediction | result | |
|---|---|---|---|
| 1 | OpenAPIKit falls by ≥ 1,400 | **−1,520** | ✅ |
| 2 | manifest corpora move ≤ 5, no same-type row removed | **−3**, 0 same-type | ✅ |
| 3 | all 21 TRUE sample pairings survive | **21 of 21** (after the initializer fix; 13 before it) | ✅ |
| 4 | `make test` green, every batch unchanged | green, every batch to the digit | ✅ |
| 5 | the 3 NAMED collisions survive | **removed** — once initializers carry their real scope, jwt-kit's `ECDSA.PublicKey(pem:)` no longer pairs with RSA's | ❌ in the good direction |

## What this does not answer

Its population is one subject: outside OpenAPIKit the change moves 18 rows over 24 corpora. A nested type
that declares no function is not in the declared set, so a name referring to it stays bare on both sides.
And the round trips it leaves are still 96% type-only — this removes a clique, not the vocabulary gap.
