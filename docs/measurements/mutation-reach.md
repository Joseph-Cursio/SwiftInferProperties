# Does generator reach bound what a law can kill? — yes, and here is by how much

> **Status:** `measured` · **As of:** 2026-09-27

`mutation-check-arithmetic.md` found every `BigUInt.*` mutant UNEXERCISED and blamed the generator,
which draws `BigUInt(word:)` — one machine word. This runs **one frozen mutant set twice, changing only
the generator**: plan and predictions in `docs/plans/mutation-reach-scope.md`, committed with the 97
mutants (`fixtures/mutation-check/reach-plan.json`) before either arm ran; every mutant's outcome per law
in `fixtures/mutation-check/reach-outcomes.json`.

The generator change is a local SwiftPropertyLaws branch (`prefer-collection-initializer`, `15e59fe`,
**not released**): where a type offers `init(x: T)` and a later `init(xs: [T])`, derive through the
collection form, so `BigUInt` draws zero to several words.

## Result — BigInt's 8 relational laws, 97 mutants

| | single word (arm A) | word arrays (arm B) |
|---|---:|---:|
| KILLED | 35 | **58** |
| DIVERGED | 6 | 3 |
| UNEXERCISED | 56 | **36** |
| kill rate, exercised | 35 of 41 (85%) | **58 of 61 (95%)** |

**Every move went one way: 20 UNEXERCISED → KILLED and 3 DIVERGED → KILLED, none back.** Of arm B's 58
kills, 40 are by a law's own check and 18 only by trap (13 of arm A's 35).

| function | arm A killed / exercised / all | arm B |
|---|---:|---:|
| `BigUInt.*` | 3 / 8 / 34 | **11 / 13 / 34** |
| `multiplyAndAdd` (long multiplication) | **0 / 0 / 21** | **15 / 15 / 21** |
| `BigInt.+` | 8 / 8 / 10 | 8 / 8 / 10 |
| `add` (via `BigUInt.+` → `adding`) | 9 / 9 / 10 | 9 / 9 / 10 |
| `multiply(byWord:)` | 5 / 6 / 9 | 5 / 6 / 9 |
| `subtractReportingOverflow` | 9 / 9 / 12 | 9 / 9 / 12 |
| `BigInt.*` | 1 / 1 / 1 | 1 / 1 / 1 |

## The predictions, scored

| # | prediction | result | |
|---|---|---|---|
| 1 | corpus side effect ≤ 5 stubs, compiles / passes ± 3 | **0 of 943 stub files changed**; all 19 repositories identical on every bar | ✅ |
| 2 | BigInt: `BigUInt(words:`, compiles 31, passes 21 ± 2 | 80 of 80 constructions `words:`; 31 compiles; **20** passes | ✅ |
| 3 | arm A: `multiplyAndAdd` and the long-multiplication loop UNEXERCISED | 21 of 21, and lines 101–104 3 of 3 | ✅ |
| 4 | ≥ 10 move to exercised, ≤ 2 back | **23** move, **0** back | ✅ |
| 5 | the 20 split / Karatsuba mutants UNEXERCISED in both arms | **20 of 20** | ✅ |
| 6 | arm B relational kill rate ≥ 50% | **95%** | ✅ |

## What moved, and what could not

**The long-multiplication path is where reach was the whole story.** `multiplyAndAdd` went from no mutant
exercised to every one killed, and `BigUInt.*`'s own loop-bound and early-return mutants followed. The
functions single words already reached (`add`'s carry loop, `multiply(byWord:)`, subtraction) did not move
at all — reach there was never the binding constraint.

**Reach is necessary and not sufficient, measured three ways here**:

- **The split and Karatsuba branches (20 mutants) need both operands above 1,024 words.** A generator of a
  handful of words reaches none of them; a law cannot kill code no draw enters.
- **3 mutants are exercised and law-blind in both arms.** Negating `xc == 0` makes every product zero, and
  zero is commutative and associative; no relational law can notice a function that became a constant.
- **The rest of the 36** are equivalent or outside what any draw here reaches (the `<= 1024` boundary itself).

## The census side of the change

Word arrays moved BigInt's passes **21 → 20**, and both halves are improvements. `BigUInt.high` and
`BigUInt.low` idempotence now **fail** — false laws single words hid, since the low half of a multi-word
value's low half is not its low half. And the `greatestCommonDivisor` guard-domain law, which reported
NOT APPLIED because no single word is zero, is now **checked and passes**: an empty word array is zero.

## What this does not answer

One subject, and a generator change chosen for it. The corpus A/B says the rule moves nothing else in 19
repositories, which is also why it is safe to release — and why it will not move the funnel. Releasing it
is a separate step.
