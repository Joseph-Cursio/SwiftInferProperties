# `OrderedSet` generator domain — is the curated recipe too narrow?

**Status:** measured · 2026-08-08 · kit `3.27.1` (`595e400`)

Run it:

```
cd fixtures/ordered-set-generator && swift test    # ~0.1s, one dependency
```

## 1. The question

`StrategistDispatchEmitter+OCRecipes` short-circuits the kit and hand-writes the
`OrderedSet` generator for verify stubs. A Seam-C audit confirmed the
short-circuit is still *necessary* — the kit derives none of these carriers
(`CuratedRecipePremiseTests`, 0 of 25) — but not that the hand-written domain is
any **good**. This fixture asks the second question.

The shipped domain was:

```swift
Gen<Int>.int(in: 0 ... 100).map { OrderedSet([$0, $0 + 1, $0 + 2, $0 + 3]) }
```

**101 reachable values.** Every one is four consecutive ascending non-negative
integers. Three properties hold across the entire domain — fixed arity, never
negative, always an arithmetic progression with step 1 — and a subject that
depends on any of them is untestable by this generator.

## 2. The domains

| | expression | notes |
|---|---|---|
| `current` | `Gen<Int>.int(in: 0 ... 100).map { OrderedSet([$0, $0+1, $0+2, $0+3]) }` | shipped before 2026-08-08 |
| `widened` | `Gen<Int>.int(in: -100 ... 100).array(of: 1 ... 6).map { OrderedSet($0) }` | this change |
| `kit` | `Gen<Int>.int(in: -100 ... 100).array(of: 0 ... 8).map { OrderedSet($0) }` | `PropertyLawCollections.smallIntOrderedSet()`, reference arm |

The `kit` arm is carried so *"did we reach parity"* is measured rather than
asserted.

## 3. The mutant table — the headline

Law: `total(x) == x.reduce(0, +)`. Each mutant is wrong in a way that exactly one
narrowness of `current` hides. Same law, same driver, same seed — **only the
domain varies**.

| mutant | what it assumes | `current` | `widened` | `kit` |
|---|---|---|---|---|
| `arithmeticSeriesShortcut` | elements are an ascending step-1 run | **survives (all 101)** | caught @ trial 1 | caught @ trial 1 |
| `fixedArityFour` | there are exactly four elements | **survives (all 101)** | caught @ trial 7 | caught @ trial 1 |
| `nonNegativeAssumption` | no element is negative | **survives (all 101)** | caught @ trial 1 | caught @ trial 1 |
| `correct` (control) | — | holds | holds | holds |

**0 of 3 → 3 of 3, gained 3, lost 0.**

The `current` column is **exhaustive, not sampled**. The domain has 101 reachable
values and the arm enumerates all of them, so "survives" means *no counterexample
exists*, not *none was found in the budget*. That is the distinction
`fixtures/planted-defect-arm` had to plant a defect to get; here it falls out of
the domain being small enough to enumerate.

The control row is not decoration. Without it, "the new domain catches more
mutants" is satisfied by a domain that breaks everything — `correct` is asserted
to hold over 2,000 trials on all three domains.

## 4. Why the arity floor is 1 and not the kit's 0

The kit draws `array(of: 0 ... 8)` and so reaches the empty set. `widened` uses
`1 ... 6` deliberately.

These curated recipes exist partly so `index(after:)` / `index(before:)`
**monotonicity picks resolve a receiver generator**, and an empty receiver has no
valid index to advance from — `index(after: endIndex)` traps. A trap would be
parsed as `.measuredDefaultFails` and attributed to the subject, which is exactly
the conflation `docs/measurements/interaction-trap-attribution-census.md` exists
to separate.

The kit's `0 ... 8` is right for the Equatable/Hashable laws it serves and wrong
here. **The difference is purpose, not oversight**, and the arm
`arityFloorHolds` pins both halves: `widened` yields zero empties in 5,000 draws,
and `kit` yields some — asserted, so the two arms cannot silently converge.

The cost is real and stated: `widened` cannot catch an empty-collection mutant.
That class stays unreachable, by choice.

## 5. What this does NOT reach — read this before citing the table

**The `OrderedSet` order projection is not caught by any of the three domains,
and widening was the wrong lever for it.**

`fixtures/equatable-signal` names order projection as one of three real
projection bugs. The obvious hope is that a wider generator would catch it. It
does not, and the arm `orderProjectionSurvivesIndependentDraws` measures that on
all three domains at 20,000 trials each.

The reason is structural. The law `(a == b) == a.elementsEqual(b)` can only fail
on a pair that **collides on its element set while differing in order**, and two
independent draws over a 201-value alphabet essentially never do. This is the
collision-dependence rule from CLAUDE.md — *"any property whose failure needs two
generated values to collide is invisible to a generator drawing from a realistic
domain"* — and it applies to the kit's generator exactly as much as to ours,
despite the kit's own docstring hoping otherwise (*"the small element range keeps
duplicate-collapse common, which is exactly the regime where insertion-order bugs
would surface"*).

**The lever that works is a pair sampler, not an element generator.** The arm
`permutedPairingCatchesOrderProjection` shows a permuting pair sampler catches it
immediately on **every** domain, `current` included. That is a harness change and
is recorded here as the named follow-up rather than proposed as done
(falsifier: `Pairing.permuted` reaching an emitted stub).

So the honest summary of this change is **three domain-narrowness classes moved
from unreachable to reachable**, not *the projection bug is fixed*.

## 6. The modelling caveat

The three domains here are hand-modelled **reachable value sets**, driven by a
seeded LCG, not the literal `PropertyBased.Gen` pipelines. The subject under test
is which values a domain can reach, and one driver with only the domain varying
is the controlled A/B this repo asks for — but it does mean these arms would not
notice a defect in `Gen.array(of:)` itself.

The correspondence between each modelled domain and the real expression is
asserted in the main suite by `CuratedOCRecipeDomainTests`, so the two cannot
drift silently. Real `OrderedSet` is used rather than a stand-in, because the
insertion-order and duplicate-collapse semantics are the point.

## 7. Scope

Not in the main `Package.swift` and deliberately not in a Makefile batch — same
posture as `fixtures/integer-division-generator` and `fixtures/equatable-signal`.
Numbers in §3 are reproduced by the test's own `print` lines, so a re-run prints
the table rather than requiring trust in this file.
