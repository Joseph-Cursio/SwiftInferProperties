# How often does a derived generator draw only a corner of its type?

> **Status:** `shipped` · **As of:** 2026-09-27

`mutation-reach.md` measured what one degenerate generator costs: `BigUInt(word:)` derived, compiled and
ran, drew 1,000 different numbers — and every one was a single machine word, so multiplication's long
path was reached by no draw. Swapping it for word arrays took killed mutants **35 → 58**. Nothing in the
pipeline flags such a generator. This asks whether `BigUInt` is a one-off or a class.

## 1. Population

Every generator expression the compiled stubs of the latest full census use: `census-19m`, the 19
funnel repositories on `swift-infer` built against SwiftPropertyLaws 4.9.3's rule. **943 compiled stub
files, 1,350 generator uses, 310 distinct expressions** (11 bare kit primitives).

## 2. Instrument

`scripts/generator_diversity.py` appends one probe per distinct expression to the first stub using it,
as an extension of that stub's suite so file-private helpers stay in scope, and draws **1,000 values**
from a fixed seed. It counts **values** (distinct `dump`s) and **shapes** (`dump`s with numbers and
string contents masked, collection sizes and enum cases kept). A probe that cannot compile outside its
test, or traps while drawing, is recorded as NO READING and the rest of the package still runs.

**Validated before this scope on the BigInt pair**, the one case whose answer is known: single-word
`BigUInt(word:)` reads **1,000 values, 1 shape**; word-array `BigUInt(words:)` reads **902 values,
9 shapes**.

## 3. Classes — fixed before the run

| class | rule |
|---|---|
| CONSTANT | 1 distinct value in 1,000 draws |
| NARROW | 2–10 distinct values |
| SHAPE-FIXED | > 10 values, **1 shape**, and the sample dump shows room to vary — a collection, an optional or an enum case |
| VARIED | everything else |

Every CONSTANT, NARROW and SHAPE-FIXED expression is then hand-classified: **a corner of its type**
(the `BigUInt` case — a law over it checks less than it appears to) or **a legitimately small domain**
(a `Bool`, a three-case enum, a type whose value is its one field).

⚠ **A known blind spot, found on the control**: single-word `BigInt` reads 2 shapes only because its sign
varies, so it is VARIED although its magnitude is the same corner. Shape variation anywhere hides a fixed
sub-structure. This census is a floor on SHAPE-FIXED, not a count.

## 4. Predictions

| # | prediction |
|---|---|
| 1 | CONSTANT ≤ 5 expressions |
| 2 | SHAPE-FIXED 10–40 expressions (≈ 3–13%) |
| 3 | of the hand-classified CONSTANT + NARROW + SHAPE-FIXED, **at least one** is a corner in `BigUInt`'s sense |
| 4 | NO READING ≤ 15% of expressions |
| 5 | the `SwiftInferSyntaxCorpus.gen` generators are corpus-bounded: at least half read < 100 distinct values — by design, reported not flagged |

## 5. What this does not answer

It measures what a generator draws, not what a law needs: a corner matters only where some behaviour
lives outside it, which `mutation-reach.md` could show for one subject by planting mutants and this
cannot. And it reads the census's compiled stubs, so a generator no compiling stub uses is not in it.
