# Sort walkthrough — a legible end-to-end example

**2026-08-01.** A bowling leaderboard: `PlayerScore` values sorted high-to-low, member form
(`Leaderboard.sorted()`) with free functions as the control. Built to answer *"what is
actually happening"* rather than to close a known gap — but it found four things anyway.

Run it:

```
cd fixtures/leaderboard-sort && swift test     # 15 tests, ~0.005s, no network
swift run swift-infer discover --sources fixtures/leaderboard-sort/Sources --include-possible
```

Discovery only — no `swift-infer verify`, no real builds. The laws are run by this
package's own tests against deliberate mutants.

---

## 1. What `discover` proposes

13 suggestions: 6 `predicate`, 4 `idempotence`, 1 `comparator`, 1 `measure-non-negativity`,
1 `filter-subset`. One Strong, two Likely, ten Possible.

The Strong one is the member form working as intended:

```
Template: idempotence      Score: 85 (Strong)
  ✓ Leaderboard.sorted() mutating () -> Void  // lifted to (Leaderboard) -> Leaderboard
  ✓ Curated idempotence verb match: 'sorted' (+40)
```

## 2. The measured mutant × law matrix

Generated from the code by `MatrixReportTests`, and every cell is an assertion — the table
cannot drift. `oracle` is "agrees with the reference implementation".

| mutant | idempotence | ordering | permutation | oracle |
|---|---|---|---|---|
| `dropsLastWhenOddCount` | passes | passes | **kills** | **kills** |
| `duplicatesFirst` | **kills** | passes | **kills** | **kills** |
| `ascendingInsteadOfDescending` | passes | **kills** | passes | **kills** |
| `unstableTieHandling` | passes | passes | passes | passes |
| `sortsByNameNotScore` | passes | **kills** | passes | **kills** |
| `returnsInputUnchanged` | passes | **kills** | passes | **kills** |
| `leavesLastElementUnsorted` | **kills** | **kills** | **kills** | **kills** |

Three things the table says that prose would not:

**Ordering and permutation are complements.** Each catches mutants the other passes, and
`dropsLastWhenOddCount` is the sharp case — a shorter sorted list is still sorted, so only
permutation and the oracle see it.

**Idempotence rejects 2 of 7** — the weakest of the four. Most mutants are stable under
re-application, so applying them twice equals applying them once.

**One row is all-passes, and it is correct.** `unstableTieHandling` fails nothing under arm
B, because a total order leaves no ties to mishandle — under this comparator it is not a
defect. The identical mutant is refuted at trial 0 under arm A. Whether something IS a bug
depends on the comparator, not on the sort.

## 3. Perfect world vs actual: what the code owes

The laws a competent reader would state for this code, against what `discover` proposed.

**Most of this list was named in the design discussion before any code was written** —
permutation, comparator SWO, the uniqueness invariant, cache coherence, the bounded measure.
That is the closest thing to a frozen key here, and the honest caveat is that it is not a
*committed* one: rows marked ☆ were added after seeing the output and should be discounted.

| # | law the code owes | proposed? | why not |
|---|---|---|---|
| 1 | `sorted()` output is a **permutation** of the input | **no** | not templated — `partition` is dead |
| 2 | output is **ordered** by the comparator | **no** | not templated |
| 3 | `sorted()` is **idempotent** | **yes** — Strong (85) | — |
| 4 | the comparator is a **strict weak ordering** | **partial** — 1 of 4 | name-gated (§5) |
| 5 | `sorted().count == count` (conservation) | **no** | not templated |
| 6 | `namesAreUnique` holds for every board | **no** | scanned, not templated — a *nullary* `Bool` is an invariant, not a `predicate` |
| 7 | `score` lies in `0...300` | **half** — lower bound only | no upper-bound template |
| 8 | after `add`, `sorted()` reflects the new entry | **no** | not paired — needs a mutation + observation pair |
| 9 | `add` grows `count` by exactly 1 | **no** | not paired |
| 10 | the free function agrees with the member ☆ | **no** | not paired |
| 11 | `sorted().map(\.score)` is non-increasing ☆ | **no** | not templated |

**2 of 11 fully found, 2 partial.** Recall on the laws this code actually owes is roughly
**20%**, against a suggestion count of 13.

### A third category the first version of this list missed: covered elsewhere

`PlayerScore` is `Equatable` and `Hashable`, which **does** imply laws — reflexivity,
symmetry, transitivity, and `a == b ⟹ a.hashValue == b.hashValue`. `discover` proposes none
of them, and that is correct rather than a miss: `ProtocolCoverageMap` maps `Equatable` to
`{equatableReflexive, equatableSymmetric, equatableTransitive}` and `Hashable` to those plus
`hashableConsistency`, and vetoes any template that would restate a law PropertyLawKit
already runs.

So the scorecard needs three buckets, not two — **found**, **missed**, and **covered
elsewhere**. Omitting the third made the tool look blind to laws it is deliberately, and
correctly, silent about.

## 3a. …and those laws are the weak ones

The interesting part is what happens once they are covered. `EquatableLawsTests` runs all
four against `ProjectedPlayerScore` — the projecting-`==` type — and **all four pass**:

| law | verdict |
|---|---|
| reflexive | passes |
| symmetric | passes |
| transitive | passes |
| **hash consistency** | **REFUTED** |

A projection is a perfectly good equivalence relation. That is the trap: the three Equatable
laws are satisfied *because* it is one, and they cannot see what it forgot. This is
`fixtures/equatable-signal`'s finding — conformance does not predict refutability, the shape
of the `==` body does; three real swift-collections bugs pass 4 of 4 — reproduced in one
file.

**Hash consistency is the law that catches it.** Swift synthesizes `hash(into:)` from *all*
stored properties even when `==` is hand-written, so a projecting `==` violates
`a == b ⟹ a.hashValue == b.hashValue` the moment the ignored field differs. And the
consequence is not theoretical:

```swift
let set: Set<ProjectedPlayerScore> = [ann, bob]   // ann == bob
#expect(set.count == 2)                            // a Set holding two equal elements
```

Which sharpens the standing advice. It was *"propose the model law, not the Equatable laws,
for projections."* The `Hashable` half is not in that indictment — **it is the one
conformance-derived law that does catch a projection bug**, and it is free wherever the type
is `Hashable`. The model law is still needed for the `Equatable`-only case.

The diagnosis is not one gap but three, and only one of them is "add a template": five rows
are **not templated**, three are **not paired** (the shape needs two members considered
together, which is what pairings are for and what `homomorphism` needed to wake up), and one
is a **near-miss on subject shape** (row 6 — the tool scans the property and has no law for
a nullary `Bool`).

**The near-miss on row 1 is the sharpest.** `filter-subset` WAS proposed on `selectionSorted`
— "result ⊆ the collection it selects from". That is a strictly weaker permutation law: it
catches an output containing a foreign element, and misses both `dropsLastWhenOddCount` and
`duplicatesFirst`. So the tool is not blind to the shape; **it proposes the weak version of
the law it is standing next to.**

## 4. What should have been rejected

The other half of the scorecard. 13 suggestions, classified by what a reader would do with
them:

| class | count | which |
|---|---|---|
| **true and useful** | 4 | `idempotence` on `Leaderboard.sorted` (85), on both free-function controls, `comparator` on `byScoreDescending` |
| **true but weak** | 2 | `filter-subset` on `selectionSorted` (the weak permutation), `measure-non-negativity` on `count` (an `Array`-backed count is never negative) |
| **true but wrong subject** | 6 | `predicate` on `differential`, `differentialUnderScoreProjection`, `isStrictWeakOrdering`, `idempotence`, `isPermutation`, `isOrdered` |
| **FALSE** | 1 | `idempotence` on `Generators.next` — Likely (45) |

**Only one is actually false**, and precision in the strict sense is 12/13. That is the
tool's real strength and it should not be understated.

But **6 of 13 — 46% — are totality laws about this fixture's own law helpers**, not about
the code under test. They are true (a `-> Bool` function does owe totality) and useless: no
one wants a property test on their property test's oracle. The tool cannot tell a subject
from an apparatus, and on any repo with a test-shaped helper layer that is a large, quiet
fraction of the output.

So the honest headline is not precision but **yield: 4 of 13 suggestions are worth a
reader's time, and they cover 2 of the 11 laws the code owes.**

## 5. Score vs truth — the calibration is inverted in the middle band

The same 13, ranked by score, against what a reader would do with each:

| rank | score | tier | subject | verdict |
|---|---|---|---|---|
| 1 | 85 | Strong | `Leaderboard.sorted` idempotence | **useful** |
| 2 | 45 | Likely | `Generators.next` idempotence | **FALSE** |
| 3 | 40 | Likely | `byScoreDescending` comparator | **useful** |
| 4 | 35 | Possible | `selectionSorted` filter-subset | weak |
| 5 | 35 | Possible | `count` measure-non-negativity | trivial |
| 6 | 30 | Possible | `sortedByScoreThenName` idempotence | **useful** |
| 7 | 30 | Possible | `sortedByScore` idempotence | **useful** |
| 8–13 | 20 | Possible | `predicate` × 6 on law helpers | wrong subject |

**The only false law in the run is the second-highest-scored thing in it.** It outranks the
comparator law, and both correct free-function laws sit *below* a trivial non-negativity
claim and a weak subset claim.

Two conclusions, and they point in opposite directions:

**The score-20 floor is real signal.** All six wrong-subject suggestions sit at exactly 20,
and nothing useful does. Separating "floor" from "candidate" is something the score does
well, and this reproduces the repo's own observation that 738 of 1,115 swift-syntax
suggestions sit at that floor.

**Inside the candidate band (30–45) the score carries no information, and here it is
actively inverted.** Ranked 2, 4, 5 are false/weak/trivial; ranked 3, 6, 7 are useful. A
reader working top-down hits the false one second.

### The mechanism, and why `--require-corroboration` would not catch it

The false law scored 45 from **three shape signals and no semantic one**:

```
+30  type-symmetry signature (Generators) -> Generators
+10  lifted from a no-param mutating method
 +5  value-semantic carrier
```

The correct comparator law scored 40 from a *name* signal — the strongest evidence available
for that template. So **three weak structural signals outscored one strong semantic one**,
30 + 10 + 5 = 45 > 40, and the arithmetic is the whole defect.

`--require-corroboration` exists for the neighbouring problem — it withholds default
visibility from a suggestion resting on a *single* positive signal. It would not fire here:
this suggestion has three. **Corroboration counts signals, not signal kinds**, and three
readings of "this is shaped like `T -> T`" are one observation counted thrice, not three
independent ones.

That is a concrete, testable proposal the fixture produced: corroboration should require
signals of *distinct kinds*, and a shape-only stack should not reach `Likely` without a name
or a body signal agreeing.

## 6. The strongest law is not proposed

**`sorted(xs)` is a permutation of `xs`** — multiset equality. It is the only law here that
catches a sort **dropping or duplicating** an element, and the tests prove neither of the
other two sees those:

| mutant | ordering | permutation |
|---|---|---|
| drops last element on odd count | **passes** | rejects |
| duplicates the first element | **passes** | rejects |
| ascending instead of descending | rejects | **passes** |
| sorts by name not score | rejects | **passes** |
| returns input unchanged | rejects | **passes** |

**Neither law subsumes the other**, and a suite carrying only one reports green on half the
mutant set. A shorter sorted list is still sorted; a reordering is still a permutation.

`discover` proposes no permutation law. `partition` is one of five templates still measuring
**zero rows** across eight corpora, and this is the shape that would wake it — so the
fixture is a diagnosis for one of the five, which was the open work left from this morning.

There is a small irony in the output: the two occurrences of "permutation" are `discover`
reading *this fixture's own `isPermutation` law* as a subject to state laws **about**, not
as a law to propose.

Idempotence, meanwhile, is the weak one of the three — most mutants are stable under
re-application, so applying them twice equals applying them once. It rejects **≤3 of 7**.

## 7. The re-tag pays off, measured

`[PlayerScore]` normalises to `Array` in `StdlibAnchor.catalogType`, and PR #31 tagged the
catalog's `Array | idempotent under sort` row `idempotence`. Before/after, by restoring the
pre-#31 catalog and rebuilding:

```
BEFORE PR#31: 0 "Proven analog" lines
AFTER  PR#31: 2
```

> ✓ Proven analog: `Array` satisfies `a.sorted().sorted() == a.sorted()` — idempotent under sort.

Independent confirmation on a different carrier from the `Stack` case used in PR #32.

## 8. Two defects the fixture found

**A `comparator` law is proposed for 1 of 4 comparators — and not for either deliberate
defect.** `ComparatorTemplate.orderingNameStems` gates on the *name*: `byScoreDescending`
contains `descending` and is admitted; `byScoreThenName`, `brokenDisjunctive` and
`nonStrict` carry no stem and are suppressed **even at `--include-possible`**.

That gate is deliberate and measured — its doc records *"11 of 22 candidates on this repo
were false, including all three already visible at `Likely`"*. So this is not a bug report;
it is the **recall cost of that precision decision, priced on a case built to need it**. The
two mutants a comparator law exists to catch — the non-transitive `||` form and the
reflexive `>=` — are exactly the ones a name-keyed gate cannot see, because a broken
comparator is not usually named for its brokenness.

**A Likely-tier false positive on a PRNG step.** `Generators.next()` is
`mutating func next() -> UInt64`; the lifter renders it `(Generators) -> Generators` and
`idempotence` scores it **45 (Likely)**. Stepping a PRNG twice is not stepping it once — it
is the definition of non-idempotent.

All its signals are shape-only (+30 type symmetry, +5 value semantics, +10 lifted); no
idempotence verb matched. `IdempotenceTemplate+IteratorVeto` exists for exactly this shape
and misses it, because it keys on `IteratorProtocol` conformance and on type-name suffixes —
and this is a struct called `Generators` with no conformance. **The signal is the method
name `next`, not the type.** Same for `advance`, `step`, `tick`.

## 9. Two design claims of mine that were wrong

Recorded because both were wrong in the same direction — I reasoned about the experiment
instead of running it.

**A tie is not sufficient for the stability defect; it has to be *positioned*.** The first
`forcedTieBoard` tied the even indices and produced `[300, 144, 300, 29, 300]` — three ties,
and selection sort agreed with the built-in exactly. The ties were the **maximum**, so no
swap ever moved them. Selection sort destabilises only when a swap jumps an element over an
equal one, which needs the tied pair followed by something *larger*: `[200, 200, 300]`.

That refines CLAUDE.md's collision rule rather than restating it: it is not enough for two
generated values to **collide**, the collision must be **positioned** where the code treats
the two differently.

**Uniqueness is not a precondition for totality — I had the dependency backwards.** The
design claim was that arm B's comparator is total only because names are unique. Under
*memberwise* equality that is false: two entries sharing name and score are **the same
value**, so swapping them is unobservable and every law still holds; duplicate names with
different scores are still totally ordered because score breaks the tie.

It becomes a precondition the moment equality stops seeing the whole value — which is
`ProjectedPlayerScore`. There two distinct players compare `==`, so `[ann, bob] == [bob, ann]`
while presenting a different leaderboard to a reader. That is the `storedFieldProjection`
blindness `fixtures/equatable-signal` measured, reached from the sort side.

## 10. The generator is the experiment

Bowling is a rare **positive** control for the collision rule, because the real domain is
narrow enough that ties arise unaided — with 5 players from `0...300`, P(tie) ≈ 6.5% per
trial.

| generator | `differential` law |
|---|---|
| `0...300` (realistic) | **refuted** within 200 trials |
| `0...Int32.max` (wide) | **green, 200/200** — same law, same code |
| forced tie, positioned | refuted at trial 0 |

The wide-domain arm is the failure mode, not a curiosity: the law is false, the sort is
unstable, and the suite is green — because the generator was chosen for the *type* rather
than for the *law*. The forced-tie arm is what makes the green interpretable; without it,
"no counterexample" and "no counterexample reachable" look identical.

## 11. Two arms, one line apart

| arm | comparator | order | `differential` |
|---|---|---|---|
| **A** | score only | preorder | **false** — ties expose selection sort's instability |
| **B** | score desc, name asc | total | **true** — and therefore says nothing about stability |

Arm A's failure is rescued by the model law: `sort(xs).map(\.score)` agrees on exactly the
inputs where `sort(xs)` does not, because the disagreement lives entirely inside tie groups.
That is *"propose the model law, not the equality laws, for projections"* demonstrated in
ten lines rather than 22 hand-run arms.

**Why selection sort and not insertion sort.** Swift's `sorted(by:)` is documented as *not
guaranteed stable*, but since Swift 5 it is a modified timsort that **is** stable in
practice. Pairing it with a hand-rolled insertion sort — also stable — gives two
implementations that agree on every input and a differential law that cannot fail, while
reading exactly like a passing one. Selection sort is naturally unstable, which makes the
disagreement real.

## 12. Scope

Member form throughout, free functions as the control — the free-vs-member split is the most
reliable way to make the tool go silent for structural rather than semantic reasons, which is
why `homomorphism` measured zero for months.

Not in the main `Package.swift`, not in a Makefile batch, same posture as
`fixtures/integer-division-generator` and `fixtures/equatable-signal`.

The merge false positive discussed alongside this design — a name-keyed `Leaderboard + Leaderboard`
whose `count` is sub-additive, which `HomomorphismMemberPairing` would wrongly admit — is
deliberately **not** here. It measures what the tool *wrongly claims*, where this fixture
measures what laws *catch*; bundling them would produce a README arguing two things at once,
which is what made `docs/roadtest-self-dogfood.md` need withdrawing.
