# Does a passing law notice a planted bug on subjects the catalogue never met? — thin, and it says why

> **Status:** `measured` · **As of:** 2026-09-26

Run to `docs/plans/mutation-check-new-subjects-scope.md`, whose predictions were committed (`4e1d180b`)
before any census, and whose sample was committed (`64cdb384`) before any mutant. Four subjects outside
the funnel corpus; the first check's method, operators and scoring. Record:
`fixtures/mutation-check/run-new-subjects.jsonl` — 73 rows, every mutant as a patch pinned by commit.

## The answer

**The sample came in at 38 of 60 laws, 10 baselines trapped, and 28 laws produced 35 mutants — too few to
settle the question the study was built for.** The relational stratum, the one the first check could not
test, **got 1 applicable mutant from 5 laws**. What it does show is *why*, twice over, and both are
findings about the apparatus rather than the subjects.

| | laws sampled | baseline not passing | mutants | killed | diverged, law passed | unexercised | kill rate, of changed |
|---|---:|---:|---:|---:|---:|---:|---:|
| totality | 9 | 0 | 16 | 1 | 9 | 5 | **10% of 10** |
| idempotence | 9 | 4 | 6 | 0 | 2 | 3 | 0% of 2 |
| **relational** | 5 | 0 | **1** | 1 | 0 | 0 | 1 of 1 |
| characterisation | 4 | 3 | 3 | 1 | 0 | 2 | 1 of 1 |
| round-trip | 6 | 3 | 1 | 0 | 0 | 0 | — (1 undiffable) |
| other | 5 | 0 | 8 | 0 | 6 | 2 | **0% of 6** |
| **all** | **38** | **10** | **35** | **3** | **17** | **12** | **15% of 20** |

(2 mutants did not compile and are discarded.) The first check caught **9 of 34 (26%)** on the funnel's
own corpus.

## The frozen predictions, scored

| prediction | result | verdict |
|---|---|---|
| totality ≤ 10% | 1 of 10 | ✅ at the edge — and again every inverted predicate (M3, 8 of 8) changed output and passed |
| idempotence 20–50% | 0 of 2 | ❌ on n = 2 — no reading |
| **relational ≥ 50%** | 1 of 1 | **untested in substance** — see below |
| characterisation high in scope | 1 of 1 | ✅ the one in-scope mutant (a negated guard) was killed |
| round-trip ≥ 50% | no scoreable mutant | untested |
| unexercised 30–50% | 12 of 33 scoreable (36%) | ✅ |
| 1,000 trials add ≤ 1 kill | 0 | ✅ — second check running, zero |
| ≥ 1 stratum short of quota | 5 of 6 short | ✅ |

## Why the relational question is still open — the operators, not the laws

The first check's six operators — relational boundary, negated condition, inverted `Bool`, integer
off-by-one, dropped chained call, emptied string — **find almost nothing to mutate in an arithmetic
body.** `Bounds.intersection`, `min`, `max` and `Bounds.union` are coordinate-wise `min`/`max` and
arithmetic over `Double`s with no integer literal, condition or string; four of the five relational laws got
**no applicable mutant at all**, and the one that did (`Bounds.union`, a negated condition) was killed.
The first check hit the same wall with its single relational law. **Answering the question needs an
arithmetic-operator mutant** — `+` ↔ `-`, `*` ↔ `/`, `min` ↔ `max` — which is a new operator, and so a new
pre-registered run, not an amendment to this one.

## Why a quarter of the sample never ran — a generator defect, not the subjects

**9 of BigInt's baselines trapped, and so did 14 of its census stubs.** The kit derives `BigUInt` and
`BigInt` through `init(unicodeScalarLiteral:)`, drawing arbitrary Unicode scalars:
`Gen<Unicode.Scalar>.unicodeScalar().map { BigUInt(unicodeScalarLiteral: $0) }`. That initializer is
`BigUInt(String(value), radix: 10)!`, documented *"the cluster must consist of a decimal digit"* — so
nearly every draw force-unwraps `nil`. The types also conform to `ExpressibleByIntegerLiteral`, which
takes any `Int`. **The strategy chose a literal initializer with a stated precondition over one without** —
the "generator builds what the type forbids" shape this project has recorded before, at a new site. A kit
fix, and the next thing that would enlarge this sample.

## What else it shows

- **`swift-algorithms` produced nothing** — 106 named seeds, 2 stubs, 0 passing: its API is almost
  entirely generic, and a stub naming a type parameter is withdrawn before it is written (#493).
- **The "other" stratum caught 0 of 6 changed outputs.** It was `measure-non-negativity` on BigInt's
  `count` / `bitWidth` and `monotonicity` on `quantize`: an off-by-one keeps a count non-negative, and a
  law that says `≥ 0` cannot see it. Weak laws, not unreached bugs — the mutants DID change output.
- **All three kills were negated conditions (M2)**, one under each of totality, associativity and
  guard-domain — the operator that changes the most behaviour at once.

## What this does not claim

Four subjects, one of which supplied most of the sample (Euclid), is a reading on these codebases, not a
catalogue rate. And a planted mutant has no base rate: nothing in the record is a defect.
