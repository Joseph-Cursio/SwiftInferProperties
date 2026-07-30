# `equatable-signal` — is an `Equatable` conformance, on its own, a reason to propose a property test?

Measured 2026-07-29 against SwiftPropertyLaws v3.21.0 — the same pin as the
main `Package.swift` and `VerifierWorkdir+KitPin.swift`.

Two corpora: **swift-numerics** (2 conformances — shows the naive rule
mis-fires) and **swift-collections** (49 public ones — shows what to do
instead).

Provenance. `Package.swift`'s open-ended pins resolve swift-numerics to
**1.1.1** and swift-collections to **1.6.0**, not to main. The surveys below
were read off local main checkouts — `899af71` and `899809d3` — and every
`==` body the arms reproduce is byte-identical between the resolved tag and
that commit: `Complex+Hashable.swift`, `_TestSupport/DoubleWidth.swift`,
`OrderedSet+Equatable.swift`, `BitArray+Equatable.swift`,
`Deque+Equatable.swift`, `BitSet+Equatable.swift`. The arms measure the same
code either way.

## The assumption under test

From the pbt-book's Appendix C working notes: *whenever we see the `Equatable`
protocol, that alone should lead to the conclusion that there should be
property-based tests.* If true, it is the cheapest possible discovery rule —
conformance is a syntactic fact, no purity analysis or signature matching
needed.

**Result: false as stated.** Conformance does not predict refutability. What
predicts it is the *shape of the `==` body*, which is also syntactic and also
cheap.

## Why swift-numerics, and the corpus limitation

`swift-numerics` main declares exactly **two** `Equatable` conformances, and
they sit at opposite ends of the interesting axis:

| Conformance | `==` body |
|---|---|
| `Sources/ComplexModule/Complex+Hashable.swift:16` | hand-written; `guard a.isFinite \|\| b.isFinite else { return true }` identifies every non-finite value as one "point at infinity" |
| `Sources/_TestSupport/DoubleWidth.swift:123` | pure memberwise: `lhs.low == rhs.low && lhs.high == rhs.high` |

Nothing else in the package is `Equatable` at all — not `RoundingRule`,
`Relaxed`, `Augmented`, or `Interval`.

**n = 2 is the honest limitation of this fixture.** Two conformances can show
that the naive rule mis-fires; they cannot measure how often. The *mutation
arms* below carry the argument, not the count. See "Next corpus" at the bottom.

## The swift-numerics arms

Faithful reproductions of both conformances, plus plausible mutants of each,
run through `checkEquatablePropertyLaws` / `checkHashablePropertyLaws` at 5,000
trials with `enforcement: .strict` so every violation escalates into
`PropertyLawViolation` rather than being recorded as a non-fatal test issue.

The mutants are the point. A law suite that no plausible-but-wrong
implementation fails is a suite that cannot find a bug — score refutability,
not suggestion count.

The trial indices below are from one run and move with the seed (arm 5 landed at
trial 36 on the first run and 389 on the second). The *verdicts* — which law
fails, and whether any does — were stable across runs; those are the finding.

| Arm | Subject | `==` shape | Measured |
|---|---|---|---|
| 1 | `Complex<Double>`, as shipped | point-at-infinity guard | 4/4 Equatable + all Hashable laws pass |
| 2 | `FaithfulComplex` | reproduction — control | 4/4 pass (reproduction is faithful) |
| 3 | `ComponentwiseComplex` | `a.x == b.x && a.y == b.y` — what synthesis emits | **reflexivity fails, trial 3**, `x = (nan, 0.0)` |
| 4 | `ComponentwiseComplex` | same mutant, finite-only generator | 4/4 pass — the law goes blind |
| 5 | `NaiveHashComplex` | shipped `==`, non-finite hash normalisation dropped | **`Hashable.equalityConsistency` fails, trial 36** |
| 6 | `FaithfulWidePair` | `DoubleWidth`'s memberwise `==` | 4/4 pass |
| 7 | `LowWordOnlyPair` | **high word dropped entirely** | **4/4 pass** |
| 8 | `CrossedFieldsPair` | `lhs.low == rhs.high` — copy-paste shape | reflexivity + symmetry fail |
| 9 | `OrderedLeakPair` | `<=` slipped in for `==` | symmetry fails, trial 4 |

## The three findings

**1. Arm 7 is the refutation of the assumption.** A `DoubleWidth.==` that
forgets the high word — so `(0, 5) == (1, 5)` reports `true`, catastrophic for
a 128-bit integer — satisfies all four Equatable laws over 5,000 trials. Any
*projection* of the fields is still an equivalence relation, so the law suite
has zero refuting power there: it cannot distinguish the correct
implementation from a badly broken one. Meanwhile arm 3 kills the obvious
`Complex` mistake at trial 3. On this corpus the naive rule scores 1 of 2, and
the one it gets wrong is unrefutable by construction, not by bad luck.

**2. Arms 8 and 9 stop the conclusion being "memberwise ⇒ never refutable."**
A *malformed relation* is refutable. The unrefutable class is precisely `==`
built only from `&&`/`||` of member `==`s — which is exactly what synthesis
emits and exactly what `DoubleWidth` hand-wrote. `Complex`'s `guard … else {
return true }` is the greppable tell that something departs from that.

**3. Arm 4 is the generator, not the signal.** The same componentwise mutant
that dies at trial 3 under `Gen<Complex<Double>>.edgeCaseBiased()` passes 4/4
over 5,000 trials under a finite-only generator. This is the mistuned-generator
rule from `CLAUDE.md` again, on a new law family: an Equatable-law suggestion
that does not *bind* an edge-biased generator is a suggestion that cannot fail.
A template here would have to emit the generator, not just the law.

## Two things the conformance-keyed rule cannot see

**The one place in the package where equality laws are actually violated.**
`isApproximatelyEqual` is documented three times over
(`RealModule/ApproximateEquality.swift:42`, `:110`, `:180`) as **not
transitive**, with "you must not use approximate equality to implement a
conformance to Equatable." It is equality-shaped and carries four refutable
documented properties — reflexive-except-NaN, symmetric, scale-invariant,
convex — and a conformance-keyed rule skips it entirely because it is not a
conformance. That is `DocstringPropertyCorroborator` territory.

**What the library authors already do.** swift-numerics *does* test this
conformance by hand, at `Tests/ComplexTests/PropertyTests.swift:50`. But it is
30 enumerated values arranged in a star around `infs[0]`: it asserts
`infs[0] == i` and hash equality, and never `i == infs[0]` (symmetry), never
`infs[i] == infs[j]` for two non-zero indices (transitivity), never bare
reflexivity. So the property suite is not redundant with the example test — it
covers the three relation laws the example test skips. That is an argument for
the template on `Complex` specifically, and it comes from the authors'
behaviour rather than from us.

## Proposed rule

Three rules, in the order the two corpora established them:

> **1.** Propose `Equatable` / `Hashable` law suites only when `==` is
> **hand-written and not a pure conjunction/disjunction of member `==`s** —
> `Complex`'s point-at-infinity guard qualifies, `DoubleWidth`'s and
> `OrderedSet`'s do not. Bind an edge-biased generator to the suggestion, or
> arm 4 says it cannot fail.
>
> **2.** When `==` *is* a projection, propose the **model law** instead:
> `left == right ⟺ model(left) == model(right)`, against the type's canonical
> `Sequence` / `Collection` view. This is the rule the swift-collections arms
> add, and it is where the recall is — projections are the overwhelming
> majority of conformances in that package, and the Equatable laws are
> structurally unable to say anything about any of them.
>
> **Status of #2 (2026-07-30): PARTIALLY BUILT.** A `model-law` template shipped, but
> against a *membership* view rather than a `Sequence` view: `(a.union(b)).contains(x) ==
> (a.contains(x) || b.contains(x))`, keyed on a curated set operation plus an element-typed
> `contains`. It was driven by the swift.org `loops` study, where `RangeSet` states five such
> laws by hand (`docs/swiftorg-property-test-study-findings.md` §1.25), and it measures 6 rows
> on `stdlib/public/core`.
>
> **It does not close this recommendation.** The three bugs above are ORDER and REPRESENTATION
> bugs; a membership law is order-insensitive by construction and cannot see any of them. The
> `Sequence`-view family this item actually asks for is still unbuilt, and the reason is
> recorded rather than forgotten: `Set` is a `Sequence` with unspecified iteration order and
> would fail `a == b ⟺ Array(a) == Array(b)` spuriously, so the family needs an
> ordered-carrier discriminator first. That is a measurement, not a coding task.
>
> **3.** Treat `Equatable` conformance itself as a *precondition* that unlocks
> other templates — which is what `StdlibConformances` /
> `ProtocolCoverageMap` already do — never as a suggestion of its own.

No template in the current catalog fires on `Equatable` conformance; rules 1 and
2 would both be new. `codable-round-trip` is the nearest precedent for a
conformance-keyed template. Rule 2 needs a *model* to compare against, so its
real gate is "does this type expose a canonical sequence view," not "is it
`Equatable`" — which makes it a narrower rule than the assumption under test,
and a much more productive one.

## The swift-collections corpus

`swift-collections` @ `899809d3` declares **64 `Equatable` conformances in
`Sources/`, 49 on public non-underscored types** — 32× swift-numerics' 2, and
the corpus that turns the discriminator from an illustration into a
measurement.

### Two predictions this corpus falsified

Reading the bodies rather than the file names corrected the first survey, and
the corrections both point the same way:

**`BitSet.==` is not logic — it is a projection.** It forwards to
`isEqualSet(to:)`, and that method's entire body is `self._storage ==
other._storage` (`BitSet+SetAlgebra isEqualSet.swift:25`). It does *not* ignore
trailing zero words; it relies on every mutating path keeping storage
canonical. Same for `OrderedDictionary.==` (`_keys == _keys && _values ==
_values`).

**`Deque.==`'s referential fast path is not the interesting part.** The count
guard runs first, so the identity check can only ever short-circuit a
comparison that was going to return `true` anyway. The refutable defect in a
ring buffer is forgetting to rotate by `head`, which is a projection bug.

Net effect: the *logic* class is far thinner than the first pass claimed.
`TreeSet` / `TreeDictionary` (structural HAMT comparison, and canonical by
hash, so structural equality *is* semantic equality) and `BigString` — whose
`==` carries a literal `FIXME: Implement properly normalized comparisons &
hashing` — are what is left. Almost every public conformance here is a
projection.

### The measurement

Six real types through the real law suite, then three real projection bodies
reproduced with the bug each one's correctness depends on not having, run
through **both** law families.

| Subject | Real `==` body | Equatable laws | Model law |
|---|---|---|---|
| `OrderedSet<Int>` | `_elements == _elements` | 4/4 pass | — |
| `OrderedDictionary<Int, Int>` | `_keys ==` && `_values ==` | 4/4 pass | — |
| `BitSet` | `_storage == _storage` | 4/4 pass | — |
| `Deque<Int>` | count, identity, `elementsEqual` | 4/4 pass | — |
| `TreeSet<Int>` | structural, via `_root.isEqualSet` | 4/4 pass | — |
| `TreeDictionary<Int, Int>` | structural | 4/4 pass | — |
| **mutant:** order-insensitive `OrderedSet` | compares as a `Set` | **4/4 pass** | **fails, trial 3** |
| **mutant:** raw-storage `BitArray` | *the shipped body*, with padding unmasked | **4/4 pass** | **fails, trial 2** |
| **mutant:** unrotated `Deque` | forgets to rotate by `head` | **4/4 pass** | **fails, trial 1** |

**3 of 3 semantic bugs are invisible to all four Equatable laws. 3 of 3 are
caught by the model law, at trial ≤ 3.**

The reason is structural, not statistical, and it is why more trials will never
help: each mutant is *still an equivalence relation*. `Set(a) == Set(b)`,
`(count, words)` equality, `(count, slots)` equality — every one is reflexive,
symmetric, transitive and negation-consistent. The Equatable laws ask "is this
an equivalence relation," and the answer is yes. The question that distinguishes
these implementations is "is it the *right* equivalence relation," which needs
an independent reference definition of the value.

That reference is what `ModelLaw.swift` supplies: `left == right` ⟺
`model(left) == model(right)`, with `model` the type's canonical sequence view
(`elements`, `logicalBits`, `logicalOrder`). Note the mutant in row 8 is not a
strawman — it is `BitArray+Equatable.swift`'s actual shipped body, which is
correct only while an invariant `==` does not itself enforce continues to hold.

### The collision caveat, again

Every model-law sampler here draws **pairs**, not independent values, because
all three laws are collision-dependent: they need the two values to be
permutations of each other, or to share logical contents while differing in
representation. Independently drawn values collide far too rarely. Half of each
sampler's pairs are constructed to collide, and each sampler says so in a
comment — the repo's standing rule about narrowing a generator's alphabet
deliberately, applied to a new law family.

`swift-collections` is also where the appendix's one clean historical hit came
from: `symmetricDifference` on the type now called `TreeSet`.

## Running it

Developer-only. Resolves three packages over the network, not wired into any
Makefile batch — same posture as `fixtures/cycle27-surface`. 18 arms, ~2s once
built.

```sh
cd fixtures/equatable-signal && swift test --no-parallel
```

Every arm asserts its *expected* outcome, including the six whose expected
outcome is "the law is blind here" — swift-numerics arms 4 and 7, and the
Equatable half of all three projection mutants. A green run means the
measurement reproduced; a red one means a finding moved.

Trial indices in the tables move with the seed. The *verdicts* — which law
fails, and whether any does — are what the arms assert, and those were stable
across runs.
