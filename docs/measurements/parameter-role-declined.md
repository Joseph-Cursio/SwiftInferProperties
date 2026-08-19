# Do commutativity and associativity fire on operands that cannot be swapped?

> **Status:** `declined` · **As of:** 2026-08-19

Re-derivable at any time — `ParameterRoleCensusMeasuredTests` *is* the harness, and
`make batch2` runs it.

**Measured: the signal separates PERFECTLY and the population is 5 rows on one corpus.
Declined as *measured-not-buildable*, and the reason is the sharper finding.**

---

## Why it looked worth building

`docs/measurements/refutation-hand-check.md` hand-checked all 15 refutations in the
2026-08-19 survey and found **3 of 3 `Likely` refutations** were laws over operands with
distinct roles — `pairShrinkPhase(carrier:oracle:)` interpolates `carrier` into a *type*
position and `oracle` into an *expression* position, so a swap would not compile.

**3 of 3 reads like a pattern.** It is not: those 3 are 3 of the 5 rows that exist.

---

## This is NOT a reopen of the same-name decline

`docs/measurements/same-name-differential-pairing.md` declined a rule whose dominant false
positive it called *"undeclared role interfaces"*. **A different mechanism**: a shared
*function name* naming a role across types, where the false positive is *pairing two
functions*. This is two *parameters of one function*, where the false positive is *a law
over non-interchangeable operands*.

The two were briefly written up as one cause on 2026-08-19 and corrected the same day. This
measurement therefore stands on its own bar rather than inheriting that document's ≥50%.

---

## The signal, stated before the count

**A `(T, T) -> T` whose two parameters carry different external labels, neither `_`, is
role-distinct.** `carrier:oracle:` and `functionCall:carrier:` qualify; `merge(_:)` and
`merge(_:_:)` do not. It reads **labels, not bodies** — which is what makes it cheap, and
also what bounds it: symmetric labels over asymmetric roles would be missed.

---

## The measurement

| corpus | commutativity + associativity | **role-distinct** |
|---|---|---|
| self (`Sources/`, CLI) | 13 | **5** |
| OrderedCollections | 9 | **0** |
| SwiftPropertyLaws | 0 | 0 |
| **total** | **22** | **5** |

### Where it fires, it separates perfectly

Joined to the survey outcomes on the self corpus:

| | rows | held | refuted | declined |
|---|---|---|---|---|
| **role-distinct** | **5** | **0** | **3** | 2 |
| symmetric | 8 | 7 | **0** | 1 error |

**It removes every refutation in the family and no law that held.** Precision 5/5, and it
catches 3 of 3 of the false laws the hand-check identified.

### And that is not enough

**5 rows, on one corpus, and they are all this repository's own stub emitters.**
`scalarShrinkPhase`, `pairShrinkPhase`, `tripleShrinkPhase`, `ternarySweep` — four
functions, five suggestions.

**OrderedCollections is the control that closes it**: 9 binary-operator suggestions,
**zero** role-distinct. A collections library's binary operations are genuine — `merge`,
`union` — and take positional operands. The role-distinct shape is what a **code generator**
produces, not what a library does.

---

## The finding worth keeping

**The evidence that made this look like a class was the class.** *3 of 3 `Likely`
refutations* is a compelling-sounding ratio, and it turned out to be 3 of the 5 rows in
existence — a denominator small enough that any ratio over it reads as a pattern.

This is the same shape as item 33 (premise measured false at 27 rows, 1.1%) and item 31
(13–31 rows of leverage behind a 135-row population): **a real mechanism, correctly
identified, with nothing behind it.** The rule this repo keeps re-deriving is *state a gain
as rows moved, never as a ratio over a population you have not counted* — and the count is
what was missing.

---

## What this does NOT establish

**That the signal is wrong.** It is right on every row it touches. What is missing is
rows.

**That another corpus has none.** A codebase heavy in code generation — a compiler, a
serialiser, another inference tool — is exactly where `(String, String) -> String` helpers
with named roles live. This measured three corpora, one of which is a code generator, and
that one is where all 5 are.

**That the 5 rows are harmless.** Three of them are false laws that a reader must dismiss
by hand, and `discover` gives no hint. The cost is real; it is just small.

---

## The verdict

**Declined: measured-not-buildable at 5 rows.**

**Reopens on** a corpus with a materially larger role-distinct population — the harness
prints the count per corpus, so pointing it at a new subject answers the question in one
run. A count in the tens, on a corpus this repo does not own, would make the same rule
worth shipping unchanged.
