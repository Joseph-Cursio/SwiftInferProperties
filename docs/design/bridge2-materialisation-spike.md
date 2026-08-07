# Bridge 2 spike — idempotence on `self -> OtherType` (the materialisation case)

**Status:** spike complete — **decision: (B) document the boundary, no code change**
(owner call, 2026-07-18). Discovery stays silent on `self -> OtherType` (its current,
correct behaviour); the boundary is recorded here and in
`docs/dogfood-new-templates-findings.md` beside the sibling `reversed()` round-trip note.
**Predecessor:** B32 (bridge 1) added the instance *self-form* `self -> Self`; it deferred
`self -> OtherType` ("the materialisation case, bridge 2") explicitly.

## What bridge 2 is

A nullary non-mutating instance transform whose return type is **not** the receiver —
a lazy/computed view that *materialises* to a concrete type:
`LazySortedView.sortedForm() -> [Int]`, `path.canonicalised() -> Document`, etc.

## The checkable law

The only single-function idempotence law expressible for a materialiser is

```
value.f().f() == value.f()
```

— which is the **exact emit shape bridge 1 already uses**
(`StrategistDispatchEmitter+Templates.swift:201-202`,
`composeSelfReturningIdempotencePass`), and it is *type-agnostic*: it only needs
`value.f()`'s result type to itself expose a nullary `.f()`.

## Spike results (compiled, `scratchpad/bridge2_*.swift`)

1. **Case A — materialisation (the target): compiles and works.**
   `LazySortedView.sortedForm() -> [Int]` with `Array.sortedForm() -> [Int]` present:
   `value.sortedForm().sortedForm() == value.sortedForm()` compiles, and
   - a correct materialiser **passes** (`once == twice == [1,2,3]`);
   - a buggy one (`rotl`, non-idempotent) **fails** → execution disproves it.

2. **Case B — cross-type round-trip (`reversed()`-style): does NOT compile.**
   For `TokenSeq.flip() -> ReversedTokenSeq` / `ReversedTokenSeq.flip() -> TokenSeq`,
   the oracle `onceResult != twiceResult` is a **type error**
   (`ReversedTokenSeq` vs `TokenSeq`). So a round-trip candidate admitted as
   bridge-2 idempotence produces a **compile error → `measured-error`**, not a
   clean verdict. This is the swift-syntax `reversed()` near-miss the dogfood
   already classified as a round-trip, not an involution.

## The precondition, and why it's the real cost

Case A compiles only because the **materialised type `C` has a nullary `f() -> C`**.
That is exactly the gate that distinguishes materialisation-idempotence (admit)
from a round-trip (exclude): admit `self.f() -> C` (C ≠ Self) **iff** `C.f() -> C`
exists.

- **Discovery today cleanly rejects all bridge-2 shapes** — `typeSymmetrySignal`'s
  instance branch requires `container == returnType`, and a nullary method matches
  neither the free `(T)->T` nor the `self->Self` branch. So the current baseline
  misfires nothing; there is no correctness bug to fix, only recall to add.
- **The gate needs a cross-type lookup the scanner can't answer today.** `TypeDecl`
  records conformances / stored members / enum cases / inits — **no methods**
  (`grep methods TypeDecl.swift` → 0). Answering "does `C` have a nullary `f() -> C`"
  requires a new resolver that indexes the whole-corpus `FunctionSummary` set by
  `(containingTypeName, name)` — feasible (the summaries already exist at discovery
  time) but real plumbing, mirroring `carrierKindResolver` / `EquatableResolver`.
- **The emitter needs a routing change too.** `composeIdempotencePass` gates the
  working `value.f().f()` shape on `inputs.returnsSelfType`; a materialiser has
  `returnsSelfType == false` and would fall through to the free-function form
  `C.f(C.f(candidate))`, which won't compile. Bridge 2 needs a new flag
  (`returnsMaterialisableType`) that routes to the same self-returning emit.

## Recall reality

- The dogfood (`docs/dogfood-new-templates-findings.md`) found **zero**
  materialisation-idempotence across **1166 real picks** (ComplexModule / RealModule
  / BigInt). The only `self -> OtherType` near-miss (swift-syntax `reversed()`) is a
  **round-trip bridge 2 must exclude**.
- The pattern lives in **stdlib lazy views** (`LazySequence.sorted() -> [Element]`
  with `Array.sorted()`), which are the domain of **`known-properties`**, not
  `discover`. In the user library/app code `discover` scans, the shape is rare.

## Decision fork

- **(A) Build it (coverage-completeness).** New corpus-summary resolver gating
  `self.f() -> C` on `C.f() -> C`; new `returnsMaterialisableType` emitter flag
  routing to the existing self-returning shape; a crafted corpus fixture (one TP
  materialiser + one FP). Clean parity with bridge 1 / involution, but likely
  ~0 recall on real scanned code — like `measure-non-negativity`, it earns its keep
  on coverage, not discovery volume.
- **(B) Document the boundary, don't build.** Bridge-2 materialisation-idempotence
  is either already covered (round-trip, when an inverse exists) or requires
  cross-type resolution for a shape absent from scanned user code. Record it beside
  the existing "cross-type `reversed()` is a round-trip, not idempotence" boundary
  and keep discovery silent (its current, correct behaviour). Matches the
  conservative posture ("when in doubt, fewer suggestions").

**Spike recommendation:** lean **(B)** given zero observed recall + the cross-type
cost, with **(A)** on the table if catalogue-shape parity with bridge 1 is wanted.

**Decision (owner, 2026-07-18): (B).** No code change. The `self.f() -> C`
materialisation shape is either already covered (round-trip, when an inverse exists)
or requires cross-type resolution for a pattern absent from scanned user code; keeping
discovery silent matches the conservative posture. Revisit only if a real
materialisation-idempotence instance surfaces in a future dogfood (option (A)'s
fixture + resolver become the build plan at that point).
