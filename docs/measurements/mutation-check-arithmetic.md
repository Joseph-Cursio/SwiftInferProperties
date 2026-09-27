# Do relational laws notice an arithmetic bug? — yes, every one they reach

> **Status:** `measured` · **As of:** 2026-09-27

Both mutation checks predicted that relational laws (`commutativity`, `associativity`) kill **≥ 50%** of
the mutants that change output, and neither could test it: the second got one mutant from five laws,
because M1–M6 find nothing to change in an arithmetic body. This run swaps arithmetic operators
instead (M7), on `Euclid` @ `a597cf5` and `BigInt` @ `63feef7`, with the plan and predictions in
`docs/plans/mutation-check-arithmetic-scope.md` (committed before sampling) and the sample frozen in
`fixtures/mutation-check/sample-arithmetic.json` before any mutant ran. Every row — 31 baselines,
50 mutants with their patches, 9 site-less laws — is in `fixtures/mutation-check/run-arithmetic.jsonl`.

## Result

| stratum | laws | mutants | KILLED | — by trap | DIVERGED | UNEXERCISED | kill rate, exercised |
|---|---:|---:|---:|---:|---:|---:|---|
| relational | 16 (7 with a site) | 17 | **11** | 4 | 0 | 6 | **11 of 11** |
| comparison | 15 (14 passing baselines) | 33 | 7 | 5 | 5 | 20 | 7 of 12 |

One comparison mutant did not compile (discarded). One comparison baseline, `BigUInt.advanced(by:)`'s
guard-domain law, traps on its own documented precondition and is excluded, as in the census.

## The predictions, scored

| # | prediction | result | |
|---|---|---|---|
| 1 | relational kill rate ≥ 50% of exercised | **11 of 11 (100%)**; 7 of 11 by the law's own check, the other 4 by trap | ✅ |
| 2 | `BigUInt.*`: ≥ ⅔ of its mutants UNEXERCISED | **6 of 6** | ✅ |
| 3 | ≥ 1 kill is a trap | **9** (4 relational, 5 comparison) | ✅ |
| 4 | comparison kill rate ≤ 35% of exercised | **7 of 12 (58%)** | ❌ refuted as written |
| 5 | 1,000 trials add at most one kill | **0** | ✅ |

**Prediction 4 is refuted, and the refutation is traps, not laws.** Five of the seven comparison kills
are crashes in the subject: an arithmetic swap in Euclid's point-set predicates and deduplicators turns
an index computation out of range, and the process dies before the law says anything. By the law's own
check the comparison stratum kills **2 of 12** (`Line.nearestPoint` idempotence, twice), which is inside
the prediction. The scope counted a trap as a kill, as both earlier checks did, so the prediction is
scored as written.

## What the relational laws did

**Every relational mutant that changed output was killed.** `Color.*` (component-wise) swapped to `/`
fails commutativity at all three sites. `BigInt.*` swapped to `/` fails commutativity by the check and
associativity by a trap. `BigInt.+`'s three sites: `a.magnitude + b.magnitude` swapped to `-` traps
whenever `|a| < |b|` — `BigUInt` subtraction's underflow precondition, which prediction 3 named — and
the `-` swapped to `+` in the mixed-sign arms fails both laws by the check.

**Which is the half this answers. The other half is reach**:

- **9 of 16 relational laws have nothing to mutate.** Euclid's `min`, `max`, `union` and `intersection`
  hold no arithmetic; `BigUInt.+` is `a.adding(b)`, a delegation this method does not follow. Known
  before running and stated in the scope.
- **`BigUInt.*`'s 6 mutants are all UNEXERCISED.** The generator draws `BigUInt(word:)`, one machine
  word, and the body returns through `yc == 1` / `xc == 1` before any of its arithmetic. Its Karatsuba
  and long-multiplication paths are reached by no draw. A relational law cannot kill a bug no input
  reaches — the funnel mutation check's *generator reach* finding, in the one stratum that had not
  shown it.

So the relational laws' discrimination is as high as predicted, on the **7 laws and 11 exercised
mutants** that reach arithmetic. That is a reading on two subjects, not a catalogue-wide rate.

## What the comparison laws did

Of 20 UNEXERCISED comparison mutants, most sit in bodies the law's inputs never drive through the
changed arithmetic: bounding-box predicates whose swapped `+ epsilon` flips no answer on generated
boxes, and a guard-domain law whose guarded branch holds none of its sites. The 5 DIVERGED are the
shape the funnel check named law-blind: `measure-non-negativity` over `count` / `bitWidth` /
`leadingZeroBitCount` still sees a non-negative number after the swap, and `quantize`'s `/` swapped to
`*` stays monotonic.

## What this does not answer

It does not follow a delegation, so `BigUInt`'s real addition (`adding`) is untested by construction,
and a generator drawing multi-word `BigUInt`s — the lever for the 6 unexercised mutants — is not built.
A planted mutant has no base rate: this says the relational laws discriminate when they are reached,
not how many real bugs they would find.
