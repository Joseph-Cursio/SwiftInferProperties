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

## 2. The strongest law is not proposed

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

## 3. The re-tag pays off, measured

`[PlayerScore]` normalises to `Array` in `StdlibAnchor.catalogType`, and PR #31 tagged the
catalog's `Array | idempotent under sort` row `idempotence`. Before/after, by restoring the
pre-#31 catalog and rebuilding:

```
BEFORE PR#31: 0 "Proven analog" lines
AFTER  PR#31: 2
```

> ✓ Proven analog: `Array` satisfies `a.sorted().sorted() == a.sorted()` — idempotent under sort.

Independent confirmation on a different carrier from the `Stack` case used in PR #32.

## 4. Two defects the fixture found

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

## 5. Two design claims of mine that were wrong

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

## 6. The generator is the experiment

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

## 7. Two arms, one line apart

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

## 8. Scope

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
