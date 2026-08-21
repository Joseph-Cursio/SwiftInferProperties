# Does widening the generator's character class reach the branch a law is about?

> **Status:** `measured` · **As of:** 2026-08-21

Harness: `swift test --package-path fixtures/branch-reaching-generator`. Standalone; it
does not depend on the tool it is scoring.

**Reach is necessary and NOT sufficient. The lever is a NARROW alphabet, not a wider
one.** And building this refuted `criterion-a-unmet-subject.md`'s own first conclusion —
see §3.

---

## 1. The scorecard

Models `HTTPField.legalizeValue`: a validity guard with the entire transform in its `else`
branch. **100 trials — the shipped `.small` budget**, because a result at a budget the
tool never runs answers nothing (`fixtures/collision-pairing/` paid for that lesson).

| domain | branch reached | mutants killed |
|---|---:|---:|
| `letterOrNumber` — **the shipped default** | **0** | 0/1 |
| + space and tab | 6 | **0/1** |
| four-symbol alphabet with controls | 85 | **1/1** |

The emitted stub for a `String`-ish carrier uses
`Gen<Character>.letterOrNumber.string(of: 0...8)`. **Alphanumeric — it cannot produce a
space, a tab or a control character**, which is exactly the input class every validation
and legalisation function branches on. The guard is never false, so the transform never
runs.

## 2. Why widening is not the answer

Adding space and tab reaches the branch and still kills nothing. Refuting the mutant needs
a value with **two adjacent whitespace characters**, and two-in-a-row is rare when
whitespace is 2 symbols in a 64-symbol alphabet.

A four-symbol alphabet makes the interesting structure dense. **That is
`GeneratorRecipe.collidingString`'s conclusion — *a four-symbol alphabet, so substrings
REPEAT* — arriving independently on the validity axis rather than the substring one.** Two
different laws, two different failure regimes, same lever.

## 3. The correction this forced

`criterion-a-unmet-subject.md` first read a `measured-bothPass` on a planted defect as
*the law is inert on a defect its own property describes*. **That was wrong.**

Trimming only one end leaves leading whitespace — a genuine correctness bug, caught by the
package's own tests — but the result is a **fixpoint**: `f(" x") == " x"` and
`f(f(" x")) == " x"`. **Idempotence is preserved, so the pass was correct.** The second
mutant (`\n` → `\r`) is the same: mapping to a still-illegal byte maps that byte to itself
on the next pass.

**Normalisers are structurally hard to break idempotently.** Mapping is a fixpoint
operation and trimming converges. This fixture pins **three real correctness bugs that no
idempotence law can refute at any domain**, against one — trimming a single whitespace
character per call — that genuinely violates the law.

> **The transferable rule: a mutant is evidence about a law only if it VIOLATES that
> law.** Choosing a defect because it is *realistic* is not the same as choosing one the
> property forbids, and the gap is invisible until someone checks the algebra. It is
> *score refutability, not suggestion count* one level down — a refutation was scored that
> could not have happened.

## 4. What this does NOT establish

- **One law family, one subject shape.** Idempotence over a normaliser. Whether
  `predicate`, `round-trip` or `monotonicity` have the same branch-reachability problem is
  unmeasured.
- **No precision measurement.** A narrow alphabet with control characters may refute
  *correct* subjects for reasons unrelated to the defect; the control here
  (`no domain falsely refutes an idempotent subject`) covers four subjects on one shape,
  which is a floor and not a rate.
- **Not built into the emitter.** This measures the case; nothing ships.

## 5. What follows

**A validity-aware alphabet for `String`-ish carriers whose subject branches on a
predicate.** The signal is available — `HTTPField` declares `isValidValue` beside
`legalizeValue`, and the guard is in the body — so the recipe could narrow deliberately
rather than widening blindly. Whether the shape is common enough to earn a build is
unmeasured, and on this repo's record that question should be asked before the code is
written, not after.
