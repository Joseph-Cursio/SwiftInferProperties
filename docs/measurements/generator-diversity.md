# How often does a derived generator draw only a corner of its type? — once, in 433

> **Status:** `measured` · **As of:** 2026-09-27

`mutation-reach.md` measured what one degenerate generator costs — `BigUInt(word:)` drew a thousand
numbers that were all one machine word, and swapping it for word arrays took killed mutants 35 → 58. This
asks whether that is a class. Plan, classes and predictions in `docs/plans/generator-diversity-scope.md`,
committed with the instrument (`scripts/generator_diversity.py`) before the run; every probe's reading is
in `fixtures/generator-diversity-2026-09-27.jsonl`.

## Method

Every generator expression the compiled stubs of `census-19m` use — the 19 funnel repositories, on the
SwiftPropertyLaws 4.9.3 rule — probed once per package: **433 probes** (308 distinct expression texts,
1,347 uses in 397 stubs). Each draws 1,000 values from a fixed seed and counts distinct **values** and
distinct **shapes** (numbers and string contents masked, collection sizes and enum cases kept). Every
probe compiled and ran: no build failure, no trap, **0 NO READING**.

## Result

| class | probes | uses |
|---|---:|---:|
| CONSTANT — one value | 51 | 89 |
| NARROW — 2 to 10 values | 31 | 59 |
| SHAPE-FIXED — many values, one shape, room to vary | **0** | 0 |
| VARIED | 351 | 1,199 |

**Hand-classified, the 82 flagged probes hold exactly one corner.**

- **CONSTANT, 51 — all by design.** 49 are `Gen.always(X())`, the held receiver of a type with no stored
  state (`CorrectCSV()`, `PurityInferrer()`, the workbook's `Keeper`s): one value is the whole domain, and
  holding the receiver fixed is what `held-receiver-laws.md` built. The other 2 are
  `SwiftInferSyntaxCorpus.gen(EnumDeclSyntax.self)` over a package whose tests hold one enum snippet.
- **NARROW, 31 — 30 legitimate.** `Bool`s, enums drawn over their cases, and syntax-node corpora
  bounded by the snippets a package's own tests contain.
- **The corner: `pbt-book`'s `Reading(percent:)` — 1,000 draws, 2 values.** The initializer clamps,
  `min(max(percent, 0), 100)`, and the generator draws a full-range `Int`, which almost never lands
  inside `0...100`. Every draw is **0 or 100**; the 99 interior values are never drawn. The same
  mechanism as `BigUInt(word:)` — a generator whose domain maps onto an edge of the type — reached by
  clamping instead of by storage.

## The predictions, scored

| # | prediction | result | |
|---|---|---|---|
| 1 | CONSTANT ≤ 5 | **51**, all by design (49 held receivers, 2 one-snippet corpora) | ❌ as written |
| 2 | SHAPE-FIXED 10–40 | **0** | ❌ |
| 3 | ≥ 1 corner in `BigUInt`'s sense | **1**, `Reading(percent:)` | ✅ |
| 4 | NO READING ≤ 15% | **0** | ✅ |
| 5 | ≥ half the syntax-corpus generators under 100 values | **33 of 67**, one short | ❌ by one |

**Prediction 1 missed because the scope did not anticipate held receivers**, which are single-valued on
purpose; counted as corners they would be 49 false alarms. **Prediction 2 missed outright**: the
`BigUInt` shape — a scalar initializer in front of collection or enum storage — does not occur in this
corpus. With the scope's stated blind spot (shape variation anywhere hides a fixed sub-structure) that
is a floor, but the floor is zero.

## So what

**`BigUInt` is close to a one-off here, and the corpus says why**: the funnel's subjects are app and
tooling code whose derived types are mostly plain structs of scalars and strings, where every draw is
already a whole value. The one corner found is a teaching example, clamped by design. Generator
degeneracy is not a large lever on this corpus; `mutation-reach.md`'s 35 → 58 is a fact about arithmetic
libraries. A clamping initializer is the one mechanism worth a second look elsewhere — it would bite any
full-range draw into a validating `init` — and this corpus holds one.

## What this does not answer

It measures what a generator draws, not what a law needs. It reads compiled stubs only, so a generator
no compiling stub uses is not here. And the shape statistic is blind to a fixed sub-structure beside any
varying field.
