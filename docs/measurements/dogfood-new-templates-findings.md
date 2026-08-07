# Dogfood — involution / binary-idempotence / homomorphism on real packages

> **Update (2026-07-15): the two follow-ups below were built** as the
> recall-widening epics. **Epic 2** widened `binaryOperatorTypeSymmetrySignal`
> to instance-method binary operators (`x.union(y)`), so commutativity /
> associativity / binary-idempotence now all fire on them (broader than
> follow-up #2, which scoped only binary-idempotence). **Epic 1** made the
> scanner surface read-only computed properties as nullary `self -> T` summaries,
> so involution now fires on `Complex.conjugate` (verified: +1 pick on real
> swift-numerics ComplexModule). Two near-misses recorded below are now
> *correctly covered* rather than *correctly silent* — `Complex.conjugate`
> (involution) and instance joins like `x.union(y)`. **Still open** (deliberately):
> **computed-property MEASURES** (`var count`) — a 0-param `-> N` property has no
> template home (homomorphism needs a `[T]` param), so the scanner surfaces it but
> nothing fires; and **mutating involutions** (`BigInt.negate()`), gated out as
> `mutating`. The precision conclusion held through both epics: no default-tier
> false positives; the recall boundary narrowed exactly where measured to be safe.

**No binary change.** A precision/recall validation of the three catalogue-work
templates (`involution`, `binary-idempotence`, `homomorphism`) against real,
unseen algebraic code. Conclusion: **precision is perfect (zero false positives
across 1166 picks); recall is narrow by design** — the templates target
free/static algebraic function shapes that idiomatic Swift expresses as operators,
mutating methods, computed properties, or cross-type views instead.

## What was scanned

`discover --include-possible` over three algebraic packages (checked out as
dependencies; the new templates had never run on them):

| Package / module | Total picks | Families surfaced | involution / binary-idem / homomorphism |
|---|---:|---|---:|
| swift-numerics `ComplexModule` | 18 | commutativity 5, associativity 5, round-trip 8 | **0** |
| swift-numerics `RealModule` | 1092 | (many) | **0** |
| attaswift/BigInt | 56 | comm 14, assoc 14, idempotence 10, round-trip 11, predicate 5, dual-style 1, inverse-pair 1 | **0** |

Plus a source scan of swift-syntax / swift-argument-parser / SwiftEffectInference
for the exact shapes.

## The result: zero false positives, and the near-misses are correct

Across **1166 picks** the three new templates fired **nothing** — and every case
where they *could* have misfired, they correctly did not:

- **swift-numerics `Complex.conjugate`** is a genuine involution
  (`conjugate(conjugate(z)) == z`), but it is a **computed property**, not a
  function — so `InvolutionTemplate` (which scans `FunctionSummary`) never sees
  it. Correct scope, not a false positive.
- **`BigInt.negate()`** is an involution but **mutating** (`-> Void`) — excluded
  by the non-mutating gate. Same as `Complex` arithmetic, which is **operators**
  (`+`/`*`) — those fire `commutativity`/`associativity` (no name gate) but never
  the name-gated new templates.
- **swift-syntax `reversed()`** is the sharpest near-miss and the best validation:
  it returns a **cross-type** view (`TokenSequence.reversed() ->
  ReversedTokenSequence`, and back), so `returnType != containingType` and
  involution correctly stays silent. That pair is a **round-trip**, not a unary
  self-inverse — exactly the distinction the type-symmetry gate is there to keep.
- **No free/static `min`/`max`/`union`/`gcd`** (binary-idempotence) and **no free
  `count`/`tally` over `[T]`** (homomorphism) exist in the scanned code — real
  measures are the `.count` **property**, real joins are **instance methods**
  (`x.union(y)`, 1 parameter) or **operators**.

## Reading

- **Precision is validated.** The name gate (each template requires a curated
  verb) does exactly its job: on 1166 real picks it produced no flood, no wrong
  law. This is the fourth+ independent confirmation of the conservative posture.
- **Recall is deliberately narrow.** The templates fire on free/static
  `(T) -> T` / `(T, T) -> T` / `[T] -> Int` and self-returning instance methods —
  the **library-shaped algebraic API**. Idiomatic Swift hides the same algebra
  behind operators, mutating methods, computed properties, and instance methods
  with an implicit receiver, none of which these (or the existing
  commutativity/associativity) templates read. The templates earn their keep on
  library-shaped code (proven end-to-end on the `algebraic-laws-corpus`) and by
  promoting the catalog's reference rows to anchors — not by firing on every app.

## Decision: no code change

The recall boundary (properties / operators / mutating / instance-with-receiver)
is **shared with every existing algebraic template** and is a deliberate scope,
not a defect this dogfood exposed. Extending any one template to read computed
properties or instance-method receivers is a cross-cutting recall feature with
real precision risk — out of scope for a dogfood, and against the "raise
thresholds, don't pile on filters / when in doubt, fewer suggestions" posture.
The dogfood's value is the **precision confirmation** and this documented boundary.

**Follow-ups (each its own epic) — status as of 2026-07-15:**
1. **Computed-property involutions — DONE (Epic 1).** The scanner surfaces a
   read-only computed property as a nullary `self -> T` summary, so involution
   fires on `var conjugate: Self`. Gated to a single read-only getter with a
   declared type (stored / read-write / effectful / top-level / non-public
   excluded). Empirically de-risked: only involution fires on the 0-param shape
   (idempotence / monotonicity / homomorphism all need >= 1 param), so no flood.
   **Computed-property MEASURES (`var count`) — now DONE too (`MeasureTemplate`).**
   The `measure-non-negativity` template gives a lone measure a home via the one
   free law it owes: `measure >= 0`. Fires on a curated non-negative cardinality /
   magnitude name (`count` / `size` / `length` / `cardinality` / `magnitude` /
   `depth` / `height` / `width`) returning a SIGNED integer (`UInt` is a
   compile-time tautology, excluded), in three shapes — a 0-param computed
   property (`value.count`), a 0-param method (`value.size()`), and a 1-param
   function (`length(value)`). Deliberately **Possible-tier** (35, surfaced with
   `--include-possible`): non-negativity is the weakest law in the catalogue,
   nearly always true for a correctly-named measure, so it sits one tier below the
   additive `homomorphism` on the same measure and adds no default-tier noise. It
   earns its keep only on the integer-underflow edge (`capacity - used`,
   `end - start`). Verified end-to-end: `magnitude(value) >= 0` bothPasses through
   the `--all-from-index` survey, and all three shapes bothPass in the emitter
   compile-matrix.
2. **Instance-method binary ops — DONE (Epic 2), broader than scoped.** Widened
   `binaryOperatorTypeSymmetrySignal` itself to accept `self: T`,
   `func op(_ other: T) -> T`, so commutativity / associativity /
   binary-idempotence all fire on `x.union(y)`. The receiver-closure verify path
   already existed; the fix was the discovery signal (plus routing
   binary-idempotence through the receiver shape).

**Still open (deliberately):**
- **Mutating involutions** (`BigInt.negate()` returning `Void`) — gated out by the
  non-mutating requirement; would need a lifted `var copy; copy.negate()` shape.
- **Cross-type `reversed()`** is NOT a gap — it is a round-trip, not a unary
  involution, and correctly stays out of the involution template.
- **Materialisation idempotence** (`self.f() -> C` where `C != Self`, e.g. a lazy
  view materialising to a concrete type) — **deliberate boundary, not built**
  (bridge 2 spike, `docs/bridge2-materialisation-spike.md`, 2026-07-18). Its only
  checkable law is `value.f().f() == value.f()`, which compiles **only** when the
  materialised type `C` has a nullary `f() -> C` — the exact gate that separates a
  materialiser (admit) from a `reversed()`-style round-trip (which won't even
  typecheck the oracle). That gate needs a cross-type resolver (`TypeDecl` records
  no methods today), and the dogfood found **zero** materialisation-idempotence in
  1166 real picks — the shape lives in stdlib lazy views (`known-properties`'
  domain), not the user code `discover` scans. Discovery stays silent on it (its
  current, correct behaviour). B32 (bridge 1) shipped the sibling `self -> Self`
  instance form.
