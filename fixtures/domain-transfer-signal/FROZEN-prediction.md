# Domain transfer — a candidate discriminator, frozen before scoring

Committed **before** the scorer exists, so the rule cannot be tuned to the answer. Same posture as
`fixtures/swiftorg-study/q2-answer-key.json` and item 18's `classification-FROZEN.json`.

Issue: [#93](https://github.com/Joseph-Cursio/SwiftInferProperties/issues/93).

## The class

`IdempotenceReturnShapeClassifier`'s documented miss: `T -> T` where the output is a different
*kind* of thing, so `f(f(x))` is meaningless though it type-checks. Its doc declines to veto on it —
*"not characterised well enough, and a veto that fires on a guess suppresses true laws"*. This is an
attempt to characterise it, not a decision to ship one.

## The scored population

The 47 `idempotence` rows that **executed** in the 2026-08-05 whole-corpus survey
(`fixtures/whole-corpus-survey/`): **5 refuted, 42 held**. The 42 are the ones a veto must not
touch — they are the whole reason a guess is dangerous.

## The candidate rule

> **The parameter does not appear in the returned expression.**

The reasoning: an idempotent function *projects* its input onto a normal form, so the input, or
something named from it, is present in what it hands back. A function whose result is assembled from
values the parameter merely *seeded* — a hash, a rendered template — has changed domain: `f(f(x))`
feeds a rendering back in as though it were a name.

Deliberately **return-expression-only**, matching `IdempotenceReturnShape`'s measured finding that
*where* you look beats *what* you look for. That constraint is also the rule's most likely
weakness, and predicting so is the point of freezing this.

## Predictions, stated before measuring

**Recall — 4 of 5.** By hand:

| witness | parameter in return expression? | predicted |
|---|---|---|
| `seedTuple(from:)` | `lanes.joined(separator: ", ")` — no | **flagged** |
| `seedString(for:)` | `[seed.stateA…].map{…}.joined(…)` — no | **flagged** |
| `regressionFileHash(for:)` | `String(hex.prefix(8))` — no | **flagged** |
| `markovSynthesized(from:)` | `synthesized.map{…}` — no | **flagged** |
| `codableRoundTripGenerator(for:)` | `renderGenerator(for: typeName)` — **yes** | **missed** |

**Precision — predicted POOR, and this is the real prediction.** Any function that accumulates into
a local and returns it has no parameter in its return expression while being perfectly idempotent.
`dedupedByStateAndAction(_:)` is the named suspect: item 18 already recorded it as the false alarm a
body-wide scan produced, and a loop-and-return shape will trip this rule too.

**Stated numerically so it can be wrong: precision below 50%** — i.e. more than 4 false positives
among the 42 held.

## What each outcome would mean

- **Precision high (≥80%)** — the class is characterisable from the return expression, and a veto
  becomes a live proposal needing only an A/B.
- **Precision poor, as predicted** — the signal is not in the return expression's *shape* but in
  **dataflow**: whether the parameter's value survives to the result at all. That is a different and
  more expensive analysis than anything this classifier does, and the honest close for #93 is to say
  so with a number rather than keep the class open as a vague *someday*.

A rule that cannot be built is a finding, provided it is measured rather than asserted.
