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

## 4. Which law refutes a normaliser's bugs — and it is not idempotence

`LawComparisonTests` runs the same four mutants against six law shapes, narrow domain,
100 trials. **No law refutes the correct implementation**, which is the control.

| law | bugs killed |
|---|---:|
| **postcondition — `isValid(f(x))`** | **4/4** |
| **oracle — vs an independent implementation** | **4/4** |
| metamorphic — `f(" " + x) == f(x)` | 2/4 |
| metamorphic — `f(x + " ") == f(x)` | 2/4 |
| **idempotence** | **1/4** |
| identity-on-normal — `isValid(x) ⟹ f(x) == x` | 0/4 |

**The postcondition is the defining property of a normaliser and the cheapest of the
strong ones.** It needs no reference implementation, because the predicate already exists
— `HTTPField` declares `isValidValue` immediately above `legalizeValue`. **The tool
emitted the 1/4 law and walked past the 4/4 one in the same file.**

**The oracle also scores 4/4** but requires writing a second correct implementation, which
is the expensive end of the trade.

**The two metamorphic relations are directional and complementary** — prefix-noise catches
`trailing-trim-only`, suffix-noise catches `leading-trim-only`, together 3/4, and neither
catches `maps-to-illegal`. A single metamorphic relation reads as a general law and covers
one direction.

**`identity-on-normal` scores 0/4**, honestly: it is a true law that exercises only the
guard, and every mutant leaves the guard intact.

**Five of the nine common shapes do not apply at all.** Round-trip, inverse, commutativity,
associativity and identity-element need an inverse or a second operand; a normaliser is
lossy and unary. Monotonicity has no meaningful order. That is a fact about the
catalogue's algebraic core being blind to this subject family.

## 5. The template this suggests was DECLINED on population

`CatalogHealthCensusMeasuredTests.normaliserPairCensus` asked, across the 17 corpora,
how many types declare a `(T) -> Bool` beside a `(T) -> T` over the same `T`:
**349 shape pairs of 2,926 containers, 35 sharing a trailing noun** — and a hand-check of
the 12 named pairs printed found **one clearly genuine** (`ViewModelNameHeuristics:
isOptional / stripOptional`, in this repo) and one plausible (`Substring: _isValidIndex /
index`). The rest merely share a suffix: `formCharacterIndex / utf16AlignIndex` both end
in `Index`.

**Population is on the order of 1–5 genuine pairs.** Same verdict as `parameter-role`
(2 of 118) and `cross-type-roundtrip` (1.1%): the law is right and the population is not
there.

**Two instrument limits, stated rather than buried.** The binary-op exclusion compares the
parameter type against the container's *name*, so `OrderedSet`'s `isDisjoint(Self)` leaks
through — the 349 is still contaminated. And the first version's name rule stripped verb
prefixes, producing `validvalue` against `value`, so **the motivating example itself would
not have counted**; it was caught by reading sample rows, not the summary.

### The better route the census pointed at

Matching predicate to normaliser **by name across a type is guesswork** — the shape this
repo already measured at 61% false. **The predicate does not need finding: it is in the
body.** `legalizeValue` opens with `if _isValidValue(value) { return value }`, so the
guard *is* the postcondition, inside the function the law is about. Reading it off the
body would find the `HTTPField` case exactly, with no name matching and no `isDisjoint`
false pairs. **Its population is a different and unmeasured question** — how many
normaliser-shaped functions open with a Bool-returning guard on their own parameter — and
should be measured before anything is built.

## 6. What this does NOT establish

- **One law family, one subject shape.** Idempotence over a normaliser. Whether
  `predicate`, `round-trip` or `monotonicity` have the same branch-reachability problem is
  unmeasured.
- **No precision measurement.** A narrow alphabet with control characters may refute
  *correct* subjects for reasons unrelated to the defect; the control here
  (`no domain falsely refutes an idempotent subject`) covers four subjects on one shape,
  which is a floor and not a rate.
- **Not built into the emitter.** This measures the case; nothing ships.

## 7. What follows

**A validity-aware alphabet for `String`-ish carriers whose subject branches on a
predicate**, and **the body-guard route in §5** for the law itself. Both read the same
signal — the guard in the body — and neither needs the name matching the population census
declined. **Neither is built, and the body-guard population is unmeasured**; on this
repo's record that question gets asked before the code is written, not after.
