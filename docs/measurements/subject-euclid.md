# `Euclid` — the algebraic half of the catalogue finally has a subject

> **Status:** `measured` · **As of:** 2026-08-28

**Subject: `Euclid` @ `0b00927`** (nicklockwood's 3D geometry library), target `Euclid`. Left
clean.

**84 verdicts from 293 rows — the largest reading the toolchain has taken**, against
`swift-docc`'s 49 and `OpenAPIKit`'s 5, out of a **47-file** package.

**The headline is not the 31 refutations. It is WHICH TEMPLATES RAN.** Every subject before this
one exercised the same three — `codable-round-trip`, `idempotence`, `predicate`. Euclid ran
**associativity 7 · commutativity 7 · monotonicity 4 · binary-idempotence 4 · involution 3**.
`catalog-health-census.md` has measured four templates firing on nothing across twenty corpora;
this is the first subject that exercises the algebraic half of the catalogue at all.

⚠ **And the 31 refutations look like ~zero real defects, for a NEW and large mechanism**: the
laws assert exact `==` over floating point at magnitudes where `Double` cannot satisfy them, in
a library that **ships its own approximate-equality API** for exactly that reason.

---

## 1. The reading

| | |
|---|---|
| revision | `0b00927` |
| in manifest / prior mentions | no / **0** |
| source files · C files | 47 · **0** |
| macOS floor | `.v10_15`, builds clean in 31s |
| hand-written `Codable` ∩ `Equatable` | **15 of 15** — a 100% hand-written intersection |
| sum types (the column added the same day) | **0** |
| index rows | **293** |
| rows reaching the build stage | 144 |
| rows that ERRORED at the build stage | 60 |
| **rows reaching a VERDICT** | **84** |
| verdicts | **53 pass · 31 refutations** |
| templates among verdicts | idempotence 32 · predicate 10 · codable-round-trip 9 · round-trip 8 · **associativity 7 · commutativity 7 · monotonicity 4 · binary-idempotence 4 · involution 3** |

Decline causes across the 149 pending rows: `unsupported-carrier` 52,
`instance-method-shape-not-supported` 40, `not-a-candidate` 34,
`monotonicity-domain-not-comparable` 9, `unsupported-template` 6.

### 1.1 How it was selected, and what that refutes

**By querying the population rather than by guessing.** Two batches picked on my own theories
came back near zero — *models an external wire format* (`sourcekit-lsp` **4**, and it implements
the whole Language Server Protocol) and *polymorphic domain model* (`XcodeGen` 0,
`opentelemetry-swift` 0, `swift-configuration` 0). GitHub code search reports **136,192** Swift
files hand-writing `encode(to encoder:`, and ranking repositories by density surfaced Euclid.

⚠ **The sum-type column, added hours earlier, scores Euclid at ZERO and would have skipped it.**
That column was proposed as a better predictor than the hand-written count and it *does* rank
better among already-screened subjects — it correctly demoted `SymbolKit`, which the hand-written
count over-ranked. **As a SELECTOR it is worthless, and not only because it was wrong here: it
cannot be computed without cloning the subject first.** Ranking and selection are different
problems and the column only solves one.

---

## 2. Why the 31 refutations are (almost certainly) not defects

**Every counterexample sits at magnitude 1e5–1e6** — `Vector(-579769.03, 488482.40, 516170.40)`,
`Angle(radians: -874841.49)`, `Bounds(min: [737890.44, …])`.

**`Vector` is `public struct Vector: Hashable`** — a synthesized `==` over three `Double`s, so
the equality the law uses is **exact**. And Euclid ships `Sources/ApproximateEquality.swift`,
whose `absoluteTolerance` is an `epsilon`: **the library explicitly distinguishes exact `==` from
the comparison its own geometry needs**, and the law used the wrong one.

> **New named false-law mechanism — *an algebraic law asserted with exact `==` over
> floating-point carriers*.** It is not a generator-domain bug and not narrow: it applies to
> every algebraic template on every float-backed type. The sharper version is that **the subject
> had already published the tolerance-aware comparison the law should have used**, so the signal
> existed and nothing consumed it.

⚠ **This converges with the `OpenAPIKit` maintainer's objection, arrived at independently.** He
wrote *"equality checks don't need to be equivalency checks"*
(`candidate-screening-pass.md` §5.4.1). Here the law needs a **tolerance-aware** equivalence and
`==` is not it. **Two unrelated subjects, one underlying limit on the template**, and neither was
prompted by the other.

### 2.1 Two of them are TEMPLATE-SELECTION errors, not floating point

**`idempotence` proposed for an INVOLUTION — 4 rows.** `Vector.-(rhs:)` (unary negation),
`LineSegment.inverted()`, `Vertex.inverted()`, `Rotation.-(r:)`. Applying negation twice returns
the original, so `f(f(x)) == f(x)` is exactly the wrong law and `f(f(x)) == x` is exactly the
right one. **The catalogue HAS an `involution` template, and it ran 3 times on this same
subject.** The refutations are correct; the laws should never have been emitted.

**`monotonicity` proposed for `sin`, `cos` and `tan` — 3 rows.** None is monotonic over ℝ. Again
the refutation is right and the proposal was wrong.

**Both are nameable, cheap to gate, and neither is about the generator.** They are the clearest
actionable output of this subject.

### 2.2 One is the undeclared-invariant shape already named

`Bounds.init(min:max:)` enforces nothing, so the generator built `min > max` on every axis and
`union(_:)` commutativity failed on a value the type's semantics exclude. Same mechanism as the
`anyOf` wrappers in `refutation-hand-check.md`. `Color` multiplication with components far
outside `0…1` is the same shape.

---

## 3. What was NOT done, stated plainly

**The 31 refutations were TRIAGED, not hand-checked one by one.** What was verified: that
`Vector`'s `==` is synthesized and exact, that `ApproximateEquality` exists with an epsilon, that
`Bounds` enforces no invariant, that the `involution` template exists and ran, and that
`sin`/`cos`/`tan` are not monotonic. **What was not done is 31 individual adjudications.**

**So the tally is NOT moved by this subject.** It stays at **40 hand-checked, 3 real + 1
contested**. Adding 31 triaged rows to a hand-checked count would be exactly the arithmetic this
project refuses elsewhere — `visibility-widenability.md`'s *a decline-reason count is an upper
bound* in a different costume.

⚠ **The honest reading of a 31-refutation haul with ~0 real is not "the tool did badly".** It is
that **a whole class of carrier — float-backed algebraic types — is not yet in scope for exact
equality**, and the subject that finally exercises the algebraic templates is the subject that
shows why they have been quiet.

---

## 4. What this does NOT claim

- **Not that Euclid has zero defects.** Nothing here searched for one outside the emitted laws.
- **Not that 84 verdicts is a quality number.** It is reach.
- **Not that the floating-point mechanism is measured.** It is diagnosed from the counterexamples
  and two facts about the subject; its population across corpora is unmeasured.
- **Not that the 60 build-stage errors are diagnosed.** They are not looked at.

## 5. What would refute this

- **A hand-check finding a REAL defect among the 31**, which would make the triage wrong in the
  expensive direction.
- **An algebraic refutation on a float-backed carrier at SMALL magnitudes**, which would separate
  precision loss from a genuine law violation and is the cheap next experiment.
- **`involution` being inappropriate for the four `inverted()`-shaped functions**, which would
  make §2.1's fix wrong.
