# The kit-evidence surface — flagged, live, and what actually compiles

> **Status:** `measured` · **As of:** 2026-08-28

**The question**: `discover` and `index` print *"N carrier(s) have conformances whose laws
PropertyLawKit checks, and there is no kit evidence saying it ran"*. Is that a large usable
surface — larger than any template that could be added?

**Measured across four subjects: the flagged count converts unevenly (2% to 74%), it converts to
348 "live" laws, and ZERO of them compile.**

⚠ **This document exists because I quoted the flagged count as if it were value, twice**, which
is the mistake `docs/plans/kit-suite-backtest-plan.md` §1 names and rejects in its opening
paragraph — *"'N laws, all green' is strong evidence of reach and almost no evidence of value."*

---

## 1. The backtest — a MISS, and the predicted MECHANISM was wrong

Per the plan's design, run at `<fix>^` where green cannot mean *the library is correct*.

**Subject**: `swift-docc-symbolkit`, fix `7191ad4` *"Fix the init method in SemanticVersion"*
(2021-10-28), parent `cdaf2be`. **Observer**: `SwiftInferProperties@d53af6e`. **Kit**: v4.2.0.

The bug is ideal for this: `SemanticVersion` is one of the ten hand-written `Codable` ∩
`Equatable` types, and its memberwise initializer **accepted `prerelease` and `buildMetadata`
and assigned neither** — two of five parameters silently dropped.

**Pre-registered before running**: MISS, because the generator constructs through the broken
initializer, so the dropped fields are unreachable and every law is evaluated only over values
where the bug is invisible.

**Result: MISS — and that mechanism is WRONG.** At `cdaf2be` the scaffold emits **0 carriers /
0 laws live, 1 blocked**, and **`SemanticVersion` appears nowhere at all** — not live, not
blocked. No law about the buggy type was generated, so nothing ran and nothing was blind to
anything. **Writing the prediction down first is what makes that visible**; without it, *"it
missed"* reads as confirmation of whatever story is nearest.

---

## 2. The conversion, across four subjects

| subject | revision | flagged carriers | live | blocked |
|---|---|---:|---|---|
| `swift-docc` | `f160765` | **260** | 76 carriers / **254 laws** | 82 / 233 |
| `OpenAPIKit` | `41a79a6` | 84 | 4 / 10 | 32 / 97 |
| `Euclid` | `0b00927` | 19 | **14 / 80** | 3 / 11 |
| `SymbolKit` | `c1f9484` | 45 | 1 / 4 | 1 / 1 |

**Carrier conversion ranges from 2% (`SymbolKit`) to 74% (`Euclid`)** — a spread wide enough
that a single subject predicts nothing.

⚠ **I generalized from `SymbolKit` and it is the WORST of the four.** Having measured 45 → 4, I
reported that the surface was "a few dozen live laws" across all subjects. It is **348**.
⚠ **And the per-subject attribution in that same report was wrong**: the flagged counts were read
off a `sort -u` list without attributing them to files, which swapped three of four rows. The
correct figures are the table above; the total was right by coincidence.

**The blocked half is generator-bound.** Aggregated reasons across all four:

| reason | laws |
|---|---:|
| `Cannot derive a generator … no non-failable, non-throwing initializer …` | 65 |
| `… memberwise derivation supports structs only` | 13 |
| `… associated value of type X resolves to no generator` | 8 |
| `… no stored properties visible to the macro` | 4 |

**342 laws blocked against 348 live**, and essentially every block is generator derivation.

---

## 3. "LIVE" DOES NOT MEAN IT COMPILES — 0 of 80

The scaffold's own banner says **NOT GUARANTEED TO COMPILE**. Measured on `Euclid`, the subject
with the *best* conversion:

**80 live laws → 240 compile errors → 0 runnable.**

⚠ **Checked for the trap first.** CLAUDE.md warns that a kit-pin mismatch makes every entry fail
in a way that *"reads as an architectural limitation rather than a broken manifest"*. The local
`SwiftPropertyLaws` checkout is at **v4.2.0**, which is exactly `Package.swift:112` and
`VerifierWorkdir.swiftPropertyLawsRequirement`. **Not a mismatch.**

| compiler error | count |
|---|---:|
| `cannot infer contextual base in reference to member 'strict'` | 70 |
| `cannot infer contextual base in reference to member 'passed'` | 70 |
| `missing argument for parameter 'position' in call` | 40 |
| `generic parameter 'Shrinker' could not be inferred` | 20 |
| `cannot find 'IndexPair' in scope` | 20 |
| `cannot find '__genMesh' in scope` | 20 |

✅ **`__genMesh` FIXED 2026-08-28 — 240 errors became 160.** `KitSuiteEmitter` never read
`GeneratorResolver.supportingDeclarations`, so it rendered the *call* and dropped the
*declaration*. The verify-stub emitter never had this bug: `StrategistDispatchEmitter` carries
the same helpers through `GeneratorRecipe.declarations`, so **the fix is a render, not a
derivation — the helper was built all along.** Removing that one symbol took out **80 errors,
not 20**: the 20 missing-symbol errors plus 20 `Shrinker` generic-inference failures downstream
of an unresolved call, plus 40 of the `.strict`/`.passed` pairs. **The suite still does not
compile** — 160 errors remain, and they are separate defects (§3.1).

**The sharpest is `__genMesh`.** The emitter writes

```swift
using: __genMesh(4).array(of: 0...8).map { Mesh(submeshes: $0) }
```

and **never defines `__genMesh`** — `grep -c "func __genMesh"` on the emitted file returns **0**.
It calls a recursive-generator helper it did not emit.

### 3.1 240 → 160 → 40, and `.strict` / `.passed` were never a defect at all

| after | errors | what was fixed |
|---|---:|---|
| (original) | **240** | — |
| `__genMesh` | 160 | the scaffold called a helper it never declared |
| observed properties | **40** | `willSet`/`didSet` do not make a property computed |

⚠ **`.strict` / `.passed` — 100 of the original 240 — were NEVER A DEFECT.** They are
`cannot infer contextual base`, which is what the compiler says when `results` is error-typed
because the `check…` call above it failed to type-check. **Both enum cases exist in the pinned
kit** — `StrictnessTier.strict` and `CheckResult.Outcome.passed`, verified in the v4.2.0 source.
**Chasing them directly would have been chasing a symptom of two unrelated bugs**, and the
original triage in this document listed them first because they were the largest count.

> **A compile-error histogram is not a defect list.** 240 errors were 3 defects; the largest two
> buckets were downstream of the smallest. The `__genMesh` fix removed **80** errors for **20**
> missing symbols, and the observed-property fix removed **120** for **40** wrong call sites.

**The observed-property defect**: `MemberBlockInspector.storedMembers` skipped every binding with
an accessor block, so `Euclid.PathPoint`'s `public var position: Vector { didSet { … } }`
vanished from the shape and the emitter derived
`PathPoint(texcoord:color:isCurved:)` — three arguments against a four-argument initializer. It
now emits `PathPoint(position:texcoord:color:isCurved:)`. **Second time an accessor list has been
read too coarsely here**, after `isReadOnlyGetter` admitted `_modify`
(`modify-accessor-misclassification.md`), so the rule is now an **allowlist** of the kinds that
keep a property stored.

✅ **240 → 160 → 40 → 0. THE SUITE COMPILES, AND IT RUNS.** The third fix gated the `private`
carrier (row 71, shipped): `TypeDecl` now carries `isVisibleToTestableImport`, computed by the
`access(of:)` the scanner **already had and dropped** — the third defect in this sequence whose
fix was a render rather than a derivation. `IndexPair` moved from live to blocked with its reason,
and Euclid's suite became **the first generated kit suite anyone has compiled: 13 carriers, 76
laws, 0 errors.**

### 3.2 What running it found

**Two violations, and they are the SAME two this project's own pipeline found** —
`Codable.roundTripFidelity[JSON]` on `Rotation` and `Vertex`, at `.conventional` tier, recorded
rather than escalated because enforcement is `.default`. The counterexample is the float
mechanism verbatim:

```
x        = Vertex(…, normal: [-0.8958982600249268, 0.43400385750347037, …])
restored = Vertex(…, normal: [-0.8958982600249269, 0.43400385750347040, …])
```

**A last-digit difference under exact `==`.** `subject-euclid.md` §2.4 diagnosed exactly this from
our verify stubs; the kit reached it independently, with its own law implementation and its own
generator. **Two independent implementations, one finding** — which is the strongest form the
floating-point result has taken.

⚠ **THE RUN DOES NOT COMPLETE.** It exits on signal 5 at `Euclid/Plane.swift:230` —
`init(unchecked normal:w:)` asserts `normal.isNormalized`, and the derived generator handed it an
unnormalized `Vector`. **Fifth instance of the same wall**: `SystemString`'s interior NUL,
`Bounds` with `min > max`, `Color` outside `0…1`, `Mesh` reaching only fixed points, and now this.
**The generator builds values the type's own invariants forbid**, and here it stops the first
compiling suite from finishing.

**So the honest status is: compiles yes, runs yes, completes no.**

### 3.3 The trap has a root cause, and it is a dropped field rather than a missing analysis

**`Plane`'s picked initializer does not assert — it DELEGATES to the one that does.**

```swift
init(unchecked normal: Vector, pointOnPlane: Vector) {
    self.init(unchecked: normal, w: normal.dot(pointOnPlane))   // line 229 asserts isNormalized
}
```

That is exactly the case `InitializerPreconditionDetector.delegatesToSelf` exists for, and whose
doc pairs it with *"does any initializer on this type assert"* — **conservative in the right
direction: it can decline a delegation to a clean sibling, and cannot admit one to a dirty
sibling.** `Plane` would be declined by that pairing.

⚠ **The kit's `MemberBlockInspector` computes both flags. Ours computes only
`assertsPrecondition`** (`SwiftInferCore/MemberBlockInspector.swift:167`), so the delegation
pairing cannot fire on this side however good the detector is.

⚠ **A second, latent copy of the same drop.** `TypeShapeBuilder.swift:236` carries
`assertsPrecondition` through, with a comment warning that *any field added to
`InitializerSignature` has to be carried through this map* — and naming `_DequeSlot`, `_HeapNode`
and `_HashTable.Bucket` as the symptom of failing to, *"kept deriving and kept aborting"*, **which
is the `Plane` symptom verbatim**. The INDEX round-trip at `IndexedTypeShape.swift:264` builds
`PropertyLawCore.InitializerSignature` from `parameters` / `isFailable` / `isThrowing` alone and
drops both flags.

**So this is the fourth "computed upstream, dropped on our side" finding of the day**, after
`__genMesh`'s declarations, `access(of:)`'s visibility, and the observed-property rule. The
scoped fix is to compute `delegatesToSelf` here, add both flags to
`IndexedTypeShape.InitializerSignature`, and carry them both ways. `open-threads.md` row **72**.

### 3.4 The cheaper signal was measured and has no population

The live exhibit suggested a simpler gate than any of that: the strategist picked
`Plane(unchecked: … )`, and an argument label of `unchecked` is the author saying the
precondition is the caller's problem. **Measured over 12 manifest corpora through the real
parser — the index's `typeShapes`, never a regex:**

| | count | share |
|---|---:|---:|
| types with initializers | 1,251 | — |
| initializers | 3,035 | — |
| types with an `unchecked` label | **1** | **0.1%** |
| such initializers | **1** | **0.0%** |

**`unchecked` is `Euclid`'s local convention, and `Euclid` is not a manifest corpus.** Third
signal this session that was exact on one subject and had no population, after the monotonicity
blocklist and `parameter-role`. **Declined.**

**All 40 errors before that fix traced to ONE cause**: `IndexPair` is `private struct IndexPair` in
`Polygon.swift`, and the emitter emits a **live** suite for it — 20 `cannot find` plus 20
downstream `.strict`/`.passed`. `@testable import` exposes `internal`, not `private`. The
scaffold's banner warns the reader ("*A carrier may be `private` … Delete what does not fit*"),
which puts the check on the person pasting the file. ⚠ **Not fixed here**: `TypeDecl` carries no
access level and the scanner captures none, so this needs a field added across scanner, shape and
emitter rather than a rule change. `open-threads.md` row **71**.

The `.strict` / `.passed` errors are the emitted assertion
`results.allSatisfy { $0.tier != .strict || $0.outcome == .passed }` failing to resolve its enum
bases against the pinned kit — API drift between emitter and kit, not a user error.

**Method**: measured on a COPY of the subject with the two kit dependencies added, so the subject
itself was never modified. That is also the real adoption step — `Euclid` does not depend on
SwiftPropertyLaws, so no generated suite can compile there until someone adds it.

---

## 4. What this answers

**"Do we need more generators or templates?" — neither, yet.** The conformance-law surface that
already exists is **348 live laws that do not compile**, plus **342 blocked on generator
derivation**. Adding templates would add proposals to a pipeline whose existing high-precision
output cannot be built; adding generators would unblock the 342 only after the 348 compile.

**The order is: make the emitted suites compile, then unblock the generators, then consider new
laws.** This is `criterion-a-unmet-subject.md`'s finding arriving on a second surface — there,
**145 of 163 verify stubs (89%) did not compile**; here the kit scaffold is at 100%.

## 5. What this does NOT claim

- **Not that the laws are wrong.** Nothing here ran one. They may be excellent.
- **Not that all four subjects fail to compile.** Only `Euclid` was compiled; it was chosen as the
  best-converting subject, so it is a favourable case, not a representative one.
- **Not that the blocked 342 would pass if unblocked.** Generator derivation is a precondition.
- **Not a verdict on `scaffold-kit-suites`' 2026-08-13 fix.** That fix addressed
  `defaultIsolation`; these are different causes, and the command has clearly improved since.

## 6. What would refute this

- **The 240 errors reducing to a pin or wiring mistake in the trial package.** Checked once (kit
  at v4.2.0, matching both pins); a second reading would be worth having.
- **`swift-docc`'s 254 live laws compiling**, which would make `Euclid` the unrepresentative one
  and re-open the surface as large and usable.
- **A generated law failing at `<fix>^` and passing at `<fix>`** on any subject, which is the
  HIT this backtest did not produce.
