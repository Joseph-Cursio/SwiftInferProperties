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

⚠ **The 31 refutations are ~zero real defects, and 17 of them — 55% — are the tool proposing a
law with NO EVIDENCE**: 9 algebraically false laws (§2.1) and 8 `round-trip` laws whose "inverse"
was paired **on type signature alone** (§2.2). Floating point is 4 confirmed and 1 probable.

⚠ **The dominant mechanism is NOT what the first version of this document said.** It attributed the bulk to floating-point precision. Re-checked
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
| E. **Floating-point precision** | **4 confirmed, 1 probable** | `Vector.normalized()`; the 3 `codable-round-trip` rows (§2.2); `Rotation.*` associativity probable |
| **A′. WRONG PAIRING — `round-trip` composed on type signature alone** | **8** | §2.2 — settled by reading the emitted stubs |

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

✅ **THE INVOLUTION HALF WAS BUILT AND A/B'd THE SAME DAY** — `TemplateRegistry.applyInvolutionIdempotenceExclusion`, `open-threads.md` row 69. **The contradiction is already in the tool's own output**, so the rule needs no new analysis: two mutually exclusive templates proposed for one `(file, line)`. **Same-binary A/B over `make batch8`, both arms green at 21 tests: `idempotence` 794 → 789, exactly −5 across the 20 corpora, with `involution` unchanged at 5 and `binary-idempotence` unchanged.** ⚠ **CO-OCCURRENCE IS 100%** — 5 involution rows, 5 removed idempotence rows, so every declaration where `involution` fires also carried the contradicting proposal, in the manifest and here. **The other two shapes are NOT reachable by it**: `monotonicity` on trig and `commutativity` on `Rotation.*` have no sibling proposal to contradict them.

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

### 2.2 Bucket F — SETTLED 2026-08-28 by reading the emitted stubs

**Re-emitted with `verify --all-from-index --template round-trip`, which leaves the generated
`main.swift` in `.swiftinfer/verify-workdir/shared-survey/Sources/V<identityHash>/`.** All three
`Rotation.angle()` rows reproduced, so the stubs are the ones that refuted.

**The eight `round-trip` rows are a WRONG PAIRING — and it is the worst defect this subject
found.** The emitted law for `Rotation.angle()`:

```swift
let forwardResult = { $0.angle }(value)
let inverseResult = Rotation.yaw(forwardResult)
if inverseResult != value { FAIL }
```

It asserts **`Rotation.yaw(r.angle) == r`**. `Rotation.yaw(_:)` is documented *"Creates a
rotation around the Y axis"* — it is not the inverse of `angle`, it is one of three
axis-specific constructors beside `pitch` and `roll`. The generator builds rotations from four
random doubles, so the axis is essentially never Y and the law is false for almost every value.

**The other three pairings show the mechanism plainly:**

| forward | "inverse" it was paired with |
|---|---|
| `Vector.leastParallelAxis` | `clampedToScaleLimit()` |
| `Vector.mostParallelAxis` | `clampedToScaleLimit()` |
| `Vector.clampedToScaleLimit()` | `_quantized()` |

**These functions are unrelated. The template is pairing on TYPE SIGNATURE alone** — any
`Vector -> Vector` is treated as any other `Vector -> Vector`'s inverse — and asserting
`g(f(x)) == x` with no evidence that `g` inverts `f`.

> ⚠ **`Rotation.angle` is LOSSY, so no one-argument constructor can invert it.** It returns a
> scalar from a value with three degrees of freedom.

⚠ **A degrees-of-freedom GATE was proposed on that observation and is DECLINED on measurement —
see §2.3.** The observation is true; the gate built from it is not sound on the data available,
and the distinction it was trying to recover is **already encoded by the tier**.

**This is row 69's defect at a different site** — nothing licenses the *pairing*, exactly as
nothing licenses the *algebraic property*. Filed separately as row **70**, because the two need
different gates. **Together they are 17 of 31 refutations — 55%.**

**The three `codable-round-trip` rows are NOT a pairing defect.** Their law is correctly formed:

```swift
let encoded = try JSONEncoder().encode(value)
let decoded = try JSONDecoder().decode(Rotation.self, from: encoded)
if decoded != value { FAIL }
```

`encode`/`decode` is a genuine inverse pair. These fail for the §2.4 reason: `Rotation.init(_:_:_:_:)`
calls `simd_normalize`, so a normalized quaternion is written as four `Double`s and re-normalized
on decode, drifting in the last bits under an exact `==`. **They move from bucket F to bucket E**,
which is what the bucket was for.

### 2.3 The degrees-of-freedom gate — proposed, probed, DECLINED

Row 70 named a *degrees-of-freedom* gate as the cheapest fix: refuse a `round-trip` pairing when
the getter's return type carries fewer degrees of freedom than its carrier, because a lossy
getter has no single-argument inverse. **Probing that before building it refuted it three ways.**

**1. It is not computable from stored members.** `Rotation` stores exactly one thing —
`var storage: simd_quatd` — so the shape records `storedMembers = 1`. `Angle` records **0** (its
`radians` is computed). A stored-member comparison reads **1 against 0** and would fire the wrong
way round. The four components that make a rotation four-dimensional are inside an opaque SIMD
leaf the scanner never enters.

**2. The computable proxy is crude and would veto legitimate laws.** Initializer arity *is*
recorded — `Rotation` max 4, `Vector` 3, `Angle` 1 — so `Rotation -> Angle` reads as lossy. But
arity is not dimensionality: a type with a rich convenience initializer would be judged
high-dimensional, and the obvious casualty is the canonical round trip
`URL(string: u.absoluteString) == u`, where a many-argument `URL` initializer sits beside a
one-argument `String`. **A veto that removes 8 noisy rows and one canonical law is not a fix.**

**3. It covers 3 of the 8 rows.** Only the `Rotation.angle` pairings cross a type boundary. The
other five are `Vector -> Vector` on both sides — `leastParallelAxis`, `mostParallelAxis`,
`clampedToScaleLimit()`, `_quantized()` — where **degrees of freedom are equal by construction**
and the gate cannot fire however it is computed.

#### What the gate was reaching for is already in the tier

`RoundTripTemplate+InverseNames.swift` ships a **curated inverse-name vocabulary**, and
`FunctionPairing`'s own docstring states the design: *"naming is a signal, not a pre-filter, so
the scoring engine can still see Possible-tier pairs"*. Name evidence is what lifts a pairing
above `Possible`.

**All eight refuting rows are tier `Possible`.** The legitimate round trips observed on other
subjects are name-linked and higher — `ContentType.rawValue(rawValue:)`,
`CallbackURL.rawValue(rawValue:)` and `Path.rawValue(rawValue:)` on `OpenAPIKit` are `Strong`;
`KindIdentifier.identifier(identifier:)` on `SymbolKit` likewise. **The tier already separates
the clique from the real thing, using name evidence, which is exactly the distinction a
degrees-of-freedom rule was trying to reconstruct from type shapes.**

**So the defect is not a missing gate.** It is that **`Possible`-tier cross-function pairs enter
the index by default** — 204 of Euclid's 293 entries are `Possible`, and 55 of its 60
`round-trip` rows — and the index is what `verify --all-from-index` and the whole-corpus survey
consume. The tier is computed, recorded, and then not consulted at the boundary where it would
do the most good.

⚠ **That is a bigger change than a veto and is NOT made here.** Whatever the whole-corpus survey's
executing ratio means, it is measured over an index that includes `Possible`; changing what is
indexed moves that denominator, and the movement has to be measured rather than assumed.
`fixtures/whole-corpus-survey/`.

### 2.4 Floating point, correctly sized

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
