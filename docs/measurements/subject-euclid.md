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

⚠ **The 31 refutations are ~zero real defects — and the dominant mechanism is NOT what the first
version of this document said.** It attributed the bulk to floating-point precision. Re-checked
row by row, **precision accounts for one confirmed case and one probable one. NINE are
algebraically false laws** the catalogue should never have proposed: idempotence for an
**involution** (5), monotonicity for `sin`/`cos`/`tan` (3), and commutativity for **3D rotation
composition** (1). See §2, which is the corrected triage.

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

## 2. The 31 refutations, triaged — CORRECTED 2026-08-28

⚠ **THIS SECTION REPLACES A WRONG ONE, WRITTEN THE SAME DAY.** The first version led with
floating point and treated it as the dominant mechanism. **That is overstated by roughly an
order of magnitude**, and it pointed the next reader at the least actionable of the five
mechanisms actually present. The conclusion it reached — *~zero real defects in Euclid* —
survives unchanged; the attribution does not.

| bucket | rows | members |
|---|---:|---|
| **A. Algebraically FALSE law — should never have been proposed** | **9** | see §2.1 |
| B. Accumulating operand *(named mechanism)* | 4 | `Vector.translated(by:)`, `Vector.scaled(by:)`, `Bounds.minkowskiSum(with:)`, `Transform.transformed(by:)` |
| C. Idempotence over a **derivation** *(named mechanism)* | 3 | `deterministicHash(_:)`, `Vector.leastParallelAxis()`, `Vector.cross(_:)` |
| D. Undeclared invariant *(named mechanism)* | 2 | `Bounds.union(_:)` commutativity (`min > max`), `Color.*` associativity (components at ±5e5 in a 0…1 type) |
| E. **Floating-point precision** | **1 confirmed, 1 probable** | `Vector.normalized()` confirmed; `Rotation.*` associativity probable |
| F. **NOT ADJUDICABLE from the record** | **11** | §2.2 |

### 2.1 Bucket A — nine laws that are false before any value is generated

**None of these involves precision.** Each is false as algebra, so the refutation is correct and
the *proposal* is the defect.

- **`idempotence` on an INVOLUTION — 5 rows.** `Angle.-(angle:)`, `Rotation.-(r:)`,
  `Vector.-(rhs:)`, `LineSegment.inverted()`, `Vertex.inverted()`. Applying negation twice
  returns the ORIGINAL, so `f(f(x)) == f(x)` is exactly wrong and `f(f(x)) == x` is exactly
  right. **The catalogue owns an `involution` template and it ran 3 times on this subject.**
  ⚠ **The first version of this document counted 4 and missed `Angle.-(angle:)`.**
- **`monotonicity` on `sin`, `cos`, `tan` — 3 rows.** None is monotonic over ℝ.
- **`commutativity` on `Rotation.*` — 1 row.** **3D rotation composition is non-commutative**,
  which is among the most textbook facts in the subject area.

> **The three are one defect asked three ways: NOTHING LICENSES THE PROPOSAL.** The algebraic
> templates fire on shape — a binary operator, a self-returning unary function — with no evidence
> that the operation has the property the law asserts. This subject is the first to exercise them
> in volume, and **9 of 31 refutations are the templates proposing laws their own catalogue or
> ordinary mathematics contradicts.**

⚠ **One detail cuts the other way and is worth keeping.** `Rotation.*` drew BOTH
`commutativity` (false — bucket A) and `associativity` (true in exact arithmetic — bucket E).
The catalogue got the harder half right: composition *is* associative and *is not* commutative,
and the two templates split correctly on one operator. **The gap is not that the catalogue knows
nothing; it is that nothing gates the half it gets wrong.**

### 2.2 Bucket F — eleven that the record cannot settle

Eight `round-trip` rows (`Rotation.angle()` ×3, `Vector.clampedToScaleLimit()` ×3,
`Vector.leastParallelAxis()`, `Vector.mostParallelAxis()`) and three `codable-round-trip` rows
carry **no `secondaryFunctionName`**, so the stream does not record what the getter was paired
against.

**`Rotation` has an `angle` property, and the only `init(angle:)` in the package is on
`MiterLimit` — a different type.** Either the pairing is a bare-name cross-type collision, or it
resolved something not located here; **the record cannot distinguish those**, and guessing would
be inventing a mechanism.

⚠ **That is the same gap `SurveyRecord` closed once for `tier`** — *a survey stream cannot be
read without its index* (`open-threads.md` row 60). It is closed for tier and open for the
round-trip pairing. **The cheap next step is to re-emit one stub and read the generated law**,
which would settle all eleven and may name a fifth mechanism.

### 2.3 Floating point, correctly sized

`Vector.normalized()` is the clean case: normalizing a unit vector returns it, so the law is
**mathematically true** and fails only because `Vector` is `Hashable` over three `Double`s — a
synthesized, **exact** `==` — while the counterexample sits at magnitude 3e5.

**Euclid ships `Sources/ApproximateEquality.swift`, whose `absoluteTolerance` is an epsilon**, so
the library distinguishes exact `==` from the comparison its geometry needs, and the law used the
wrong one. **That remains a real limitation and it converges with the `OpenAPIKit` maintainer's
independent objection** — *equality checks don't need to be equivalency checks*
(`candidate-screening-pass.md` §5.4.1). **It is simply not the dominant mechanism here**, and
reporting it as such would have sent the next fix at the hardest of the five problems while nine
rows sat behind a gate nobody had asked for.

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
  and two facts about the subject; its population across corpora is unmeasured — and §2 corrects
  a first version that made it far larger than it is.
- **Not that bucket F is false.** Eleven refutations are **unadjudicated**, which is a different
  claim, and one of them could be real.
- **Not that the 60 build-stage errors are diagnosed.** They are not looked at.

## 5. What would refute this

- **A hand-check finding a REAL defect among the 31**, which would make the triage wrong in the
  expensive direction.
- **An algebraic refutation on a float-backed carrier at SMALL magnitudes**, which would separate
  precision loss from a genuine law violation and is the cheap next experiment.
- **Reading the emitted stub for one bucket-F row**, which settles eleven of the thirty-one and
  is cheaper than any of the above.
- **`involution` being inappropriate for the four `inverted()`-shaped functions**, which would
  make §2.1's fix wrong.
