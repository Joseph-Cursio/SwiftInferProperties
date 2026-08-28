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

**The sharpest is `__genMesh`.** The emitter writes

```swift
using: __genMesh(4).array(of: 0...8).map { Mesh(submeshes: $0) }
```

and **never defines `__genMesh`** — `grep -c "func __genMesh"` on the emitted file returns **0**.
It calls a recursive-generator helper it did not emit.

The 140 `.strict` / `.passed` errors are the emitted assertion
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
