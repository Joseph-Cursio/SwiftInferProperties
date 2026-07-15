# Dogfood — involution / binary-idempotence / homomorphism on real packages

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

**Follow-ups, only if recall on real code becomes a goal (each is its own epic):**
1. Recognize **computed-property** involutions/measures (`var conjugate`,
   `var count`) — a `FunctionSummary`-vs-property scope widening across the
   algebraic family.
2. Recognize **instance-method** binary ops with an implicit receiver
   (`x.union(y)`) for binary-idempotence — the same widening
   `binaryOperatorTypeSymmetrySignal` would need for commutativity/associativity.
