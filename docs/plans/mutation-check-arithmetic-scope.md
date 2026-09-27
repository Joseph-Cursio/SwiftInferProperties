# Do relational laws notice an arithmetic bug? — the mutation check's untested stratum

> **Status:** `proposed` · **As of:** 2026-09-27

Both mutation checks predicted relational laws (`commutativity`, `associativity`) would kill **≥ 50%** of
the mutants that change output, and neither could test it. The first had one passing relational law
outside teaching code; the second (`mutation-check-new-subjects.md`) had five and got **one mutant**,
because M1–M6 — boundaries, conditions, Bool results, integer literals, chained calls, string literals —
find nothing to change in an arithmetic body. BigInt's `+`/`*` laws now compile and pass (PR #598), so
this run supplies the missing mutant class and asks the question again.

## 1. Subjects and census

`Euclid` @ `a597cf5` and `BigInt` @ `63feef7`, the same checkouts as the second check, censused on
`main` (`6bbfebd5`, kit 4.9.2): Euclid 47 passing, BigInt 21. **72 compiled, passing laws** are candidates.

## 2. Method — the first check's, with one mutant class replaced

`MUTATION_STRATA=arithmetic python3 scripts/mutation_check.py sample|run|report`.

**M7 arithmetic swap** replaces M1–M6: the first three BINARY arithmetic operators in the subject body
(spaces on both sides — never a unary minus, `->` or a generic bracket), each swapped once:
`+`↔`-`, `*`↔`/`, `&+`↔`&-`, `&*`→`&+`, and the compound-assignment forms. Body only, as before: a
subject that delegates (`a.adding(b)`) has no site, and is **reported, not followed**.

| stratum | templates | quota | eligible |
|---|---|---:|---|
| relational | `commutativity`, `associativity` | 40 | **every** passing law — 16 |
| comparison | the other behaviour templates | 20 | laws whose subject body HAS a site — 16 |

The asymmetry is deliberate: the relational stratum is the question, so it takes every law and reports
the ones with nothing to mutate; the comparison asks what a NON-relational law does with the same
mutant class, so it is drawn only where there is one. Seeded, per-repo cap a half (two subjects).
Scored KILLED / DIVERGED / UNEXERCISED by the same-seed probe, at 100 and 1,000 trials; a kill by
trap or hang is reported apart from a kill by the law's own check.

**Known before running — population, not prediction:** of the 16 relational laws, **9 have no site**
(Euclid's `min`, `max`, `union`, `intersection` ×2 each hold no arithmetic; `BigUInt.+` delegates, in
both its laws). So at most **7 laws, 21 mutants** can answer the question, 6 of them BigInt's. And the
comparison stratum is **short, 16 of 20**.

## 3. Predictions — written before sampling

| # | prediction | why |
|---|---|---|
| 1 | **relational kill rate ≥ 50%** of exercised mutants | both operands are compared, so a changed result usually breaks the symmetry — the prediction twice made and never tested |
| 2 | **`BigUInt.*`: ≥ ⅔ of its mutants UNEXERCISED** | the generator draws single-word values (`BigUInt(word:)`), which return through `yc == 1` / `xc == 1` before any later arithmetic site |
| 3 | **≥ 1 kill is a TRAP**, not a failed check | `BigInt.+` swapped to `a.magnitude - b.magnitude` underflows `BigUInt` whenever `|a| < |b|` |
| 4 | **comparison kill rate ≤ 35%** of exercised | idempotence, totality and round-trip laws each compare the subject with itself, which an arithmetic change often preserves |
| 5 | **1,000 trials add at most one kill** | measured zero in both earlier checks |

## 4. What this does not answer

A kill rate on ~21 mutants across two subjects is a reading, not a rate. It does not follow a
delegating body into its callee, so `BigUInt.+`'s real arithmetic (`adding`) is untested by
construction. And a planted mutant has no base rate: this measures whether the laws discriminate, not
how many real bugs they would find.
