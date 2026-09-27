# Does generator reach bound what a law can kill? — one mutant set, two generators

> **Status:** `proposed` · **As of:** 2026-09-27

`mutation-check-arithmetic.md` found relational laws killing **11 of 11** exercised arithmetic mutants —
and **all 6** of `BigUInt.*`'s UNEXERCISED, because the generator draws `BigUInt(word:)`, one machine
word, and the body returns through its `count == 1` fast path. That blames reach, and blame is not a
measurement. This runs one frozen mutant set twice, changing only the generator.

## 1. The generator change

SwiftPropertyLaws `prefer-collection-initializer` (local, `15e59fe`, not released): where a type offers
a one-parameter `init(x: T)` and a later one-parameter `init(xs: [T])`, derive through the collection
form. First-in-declaration-order picked `init(word:)` for `BigUInt`; this picks `init(words:)`, drawing
zero to several words. Nothing else moves: only the exact `T` / `[T]` pair, and a declined collection
form leaves the scalar one. Measured with a `swift-infer` built against that checkout (`6a65c1c4`
plus a path dependency), so nothing is released to measure it.

## 2. Two arms, one mutant set

- **Arm A — single word:** BigInt's census stubs from `swift-infer` `6bbfebd5` (kit 4.9.2).
- **Arm B — word arrays:** the same subject, censused with the changed kit.
- **Laws:** BigInt's 8 relational laws (`+`, `*` × commutativity, associativity × `BigInt`, `BigUInt`).
- **Mutants: frozen in `fixtures/mutation-check/reach-plan.json` before either arm runs** — every
  M1 / M2 / M4 / M7 site (not the first three) in each subject body and in each package function it
  calls, resolved by name and first argument label, followed one level further only through a callee
  with no site of its own (`BigUInt.+` → `adding` → `add`). **97 mutants in 11 functions.**
- `scripts/mutation_reach.py` plants each mutant once, builds once, runs all 8 laws; a mutant's outcome
  is its best over the laws (KILLED, else DIVERGED, else UNEXERCISED), scored as `mutation_check.py`
  scores, against each law's own baseline.

## 3. Predictions — written before either arm runs

| # | prediction | why |
|---|---|---|
| 1 | **Corpus side effect small**: over the 19 funnel repositories, same code, ≤ 5 stubs change generator and compiles / passes move by ≤ 3 | a `T` / `[T]` initializer pair on one type is rare |
| 2 | **BigInt census**: `BigUInt` stubs draw `BigUInt(words:`; compiles stay 31, passes 21 ± 2 | the laws are true of multi-word values too |
| 3 | **Arm A**: every mutant in `multiplyAndAdd` and in `BigUInt.*`'s long-multiplication loop (lines 101–104) is UNEXERCISED | single words return before the loop |
| 4 | **Arm B**: ≥ 10 mutants move UNEXERCISED → exercised, and ≤ 2 move the other way | word arrays enter the loop; a length-1 draw still reaches the fast path |
| 5 | **Both arms**: all 20 mutants in `BigUInt.*`'s split and Karatsuba branches (line 110 on) stay UNEXERCISED | they need both operands above 1,024 words, and draws hold at most a handful |
| 6 | **Arm B relational kill rate ≥ 50%** of exercised mutants | as in the arithmetic check |

## 4. What this does not answer

One subject, and a generator change chosen for it. A mutant a law does not claim anything about stays
unkilled however it is reached. And the kit change is not released: releasing it is a separate step,
with its own census A/B (prediction 1 is that A/B).
