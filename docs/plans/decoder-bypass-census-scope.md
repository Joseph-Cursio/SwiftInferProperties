# Do decoders skip the validation their own initializers make?

> **Status:** `proposed` · **As of:** 2026-09-29

`subject-harbeth.md` found a real, latent defect by reading a generator trap: five Harbeth types check
their element count in `init(values:)` and **not** in `init(from decoder:)`, so decoding `[1,2]` produces
a value `to_factor()` then crashes on. Every real defect this repo has found is an encode/decode
disagreement found one subject at a time. This shape can be read statically, so this census asks whether
it has a population — the first route to that class of defect that does not depend on choosing the
right subject.

## 1. The shape — fixed now

A type is **flagged** when both hold, within its declaration and its extensions (brace-matched, all files):

1. **A validating initializer.** Some `init(` other than `init(from decoder:)` whose body contains a
   rejection: `precondition(` / `assert(` / `fatalError(` / `preconditionFailure(`, a `throw`, a
   `return nil` (failable), or a `guard … else` — or an `if` whose block calls a function named like a
   failure (`fail`, `fatal`, `crash`, `abort`, `error`), the Harbeth form.
2. **A decoder that neither delegates nor validates.** Its `init(from decoder:)` contains no `self.init(`
   and none of the rejection forms above.

## 2. Population

Three groups, reported separately: the **20 manifest corpora**; the **19 funnel repositories**; and the
**unmet subjects** on disk — Euclid, swift-docc, OpenAPIKit, jwt-kit, swift-system, Harbeth and the seven
other screened candidates. Instrument: `scripts/decoder_bypass_census.py`, built on `measurement.py`.

**Controls, asserted before the population is read:** Harbeth's `Matrix3x3` is flagged; a synthetic type
whose decoder delegates `self.init(values:)` is not; one whose decoder re-checks is not.

## 3. Hand-check

Every flagged type if ≤ 60, else a seeded 60 (`random.Random(20260929)`). **TRUE** if the decoder admits a
value the validating initializer rejects *and* that value reaches code relying on the check (as
`to_factor()` does); **BENIGN** if it admits it but nothing relies on it; **FALSE** if the initializer's
check does not concern a decoded field. Recorded per row.

## 4. Predictions

| # | prediction |
|---|---|
| 1 | the controls hold, including all five Harbeth types flagged |
| 2 | the 20 manifest corpora flag **≤ 30** types — library code validates less in initializers |
| 3 | **≥ 30% TRUE** among hand-checked rows |
| 4 | **≥ 1 TRUE outside Harbeth** |

## 5. What this does not answer

A text census, not a parse: it sees a rejection spelled in the initializer body, not one in a helper it
calls (Harbeth's own `HarbethError.failed` is caught only by the name rule). And a TRUE here is a latent
defect by reading — confirming one needs the decode-then-use execution Harbeth got.
