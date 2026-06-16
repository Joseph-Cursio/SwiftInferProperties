# Calibration cycle 150 — Lever C-1: bare OrderedDictionary carrier (recipe + merge closure)

**Captured 2026-06-16.** Third build cycle of the v1-algebraic-rate epic
(cycle 147). Owner chose **C-1** (the OrderedDictionary half of Lever C) after
the scoping split Lever C into two unrelated problems.

## The scoping correction (Lever C ≠ 6 uniform recall wins)

Cycle 147 sized Lever C as "pair/recipe gaps for real public types
(`OrderedSet<Int>` round-trip ×3, `OrderedDictionary` ×3) → +6 measured →
~92%". Tracing all 6 against the live 62-entry index split them into two
problems that have nothing to do with each other:

- **`OrderedDictionary` ×3** (`merge(_:uniquingKeysWith:)` dual-style ×2 +
  `OrderedDictionary.sort()` idempotence ×1) — a **genuine recall gain**.
  Failing `unsupported-carrier: OrderedDictionary`. **This is C-1.**
- **`OrderedSet<Int>` round-trip ×3** — the three picks are
  `_minimumCapacity(forScale:)` ×2 + `_maximumCapacity(forScale:)` ×1, all in
  `OrderedSet+Testing.swift`. They are `_`-prefixed **test-support capacity
  shims** with no inverse — false positives, not a missing round-trip pair.
  `RoundTripPairResolver.curated` is Complex-trig-only and rightly has no
  OrderedSet entry. **This is a filter (Lever D), not a recipe — deferred.**

So C-1 is the OrderedDictionary recall lever only; the OrderedSet round-trip
"pair gap" from cycle 147 was a misread of three FPs.

## The root cause (bare carrier never registered)

The OrderedDictionary **views** (`.Elements` / `.Values` /
`.Elements.SubSequence`) were each wired across all three carrier-support
layers (V1.63.A / V1.69), but the **bare** `OrderedDictionary<Int, Int>` was
never registered. Its `merge` / `sort()` picks therefore had no generator and
stalled at `unsupported-carrier`. Fixed across the same three layers the views
already used:

1. **`GenericBindingResolver`** — `"OrderedDictionary"` → `"OrderedDictionary<Int, Int>"`
   (mirrors the existing `"OrderedSet"` → `"OrderedSet<Int>"` base binding).
2. **`StrategistDispatchEmitter+OCRecipes`** — a `"OrderedDictionary<Int, Int>"`
   recipe via the existing `ocDictExpression(viewSuffix: "")` (returns the
   whole `dict`, no view projection).
3. **`StrategistDispatchEmitter+Templates.mutatingInstanceCarriers`** — add the
   bare carrier so `merge` / `sort()` emit the `var copy; copy.method()` shape.

## The one real emitter gap — `merge`'s uniquing closure

The recipe add alone unlocked `sort()` (verifies `bothPass` immediately), but
the two `merge` dual-style picks **failed to build**: the V1.61.B mutating
dual-style emitter emits `original.merging(other)` / `mutCopy.merge(other)`,
but `merge(_:uniquingKeysWith:)` / `merging(_:uniquingKeysWith:)` **require** a
`uniquingKeysWith:` closure the SetAlgebra ops (`union(_:)` etc.) don't.

Fix: `dualStyleTrailingArgument(forMutating:)` appends
`, uniquingKeysWith: { (_, new) in new }` for the `merge` family (empty for all
other pairs). Both halves use the **same** keep-new conflict closure, so the
dual-style equivalence still holds (the closure is a pure conflict policy,
identical on each side). Keyed on the bare mutating name, consistent with the
codebase's curated-name style (`mutatingInstanceCarriers`).

## Result

| | before (Lever B) | after C-1 |
|---|---|---|
| index entries (denominator) | 62 | 62 (unchanged — outcomes change, not the set) |
| measured | 50 | **53** (+3 OrderedDictionary picks) |
| measured-execution rate | 80.6% | **85.5%** |

**Survey-confirmed** (re-ran `verify --all-from-index` over the live index —
C-1 changes verify *outcomes*, so it cannot be derived by subtraction like
Levers A/B): **39 bothPass + 6 defaultFails + 8 edgeCaseAdvisory = 53 measured
/ 62 = 85.5%**; 9 `architectural-coverage-pending` remain. The three
OrderedDictionary picks moved ACP → `measured-bothPass`.

Cumulative: 50.5% (frozen) → 61.0% (A) → 80.6% (B) → **85.5% (C-1)**.

## Verification

- `verify --suggestion` on each of the three picks individually — all
  `verify holds (strong)`: `OrderedDictionary.sort` idempotence + two
  `OrderedDictionary.merging/merge` dual-style, 100 trials all pass.
- `verify --all-from-index` re-survey → 53/62, evidence regenerated (the
  committed `verify-evidence.json` is now exactly the 62 live-index records at
  v1.133.0; the 41 stale pre-Lever-A/B records were pruned).
- Unit: `GenericBindingResolverTests` (bare-OrderedDictionary binding) +
  `StrategistDispatchEmitterRecipeTests` (bare recipe resolves) +
  `StrategistDispatchEmitterEmitTests` (merge emits the uniquing closure on
  both halves; union takes none — regression guard; `dualStyleTrailingArgument`
  lookup). `make test-fast` green (3210).
- **swiftlint now silent project-wide** — this cycle also swept three
  pre-existing warnings the `make test-fast` path doesn't catch: the cycle-149
  commit pushed `CommutativityTemplateTests.swift` to 425 lines (file_length;
  the cycle-149 doc's "green" was test-only, not lint) — split the Lever-B
  index-traversal tests into `CommutativityIndexTraversalTests.swift`; and two
  cycle-148 `FunctionScannerTests` line_length violations (trimmed `@Test`
  descriptions).

## Notes

- **Evidence regeneration vs subtraction.** Levers A/B were discovery
  *filters*, so the committed index/evidence were faithfully derived by
  removing the dropped picks. C-1 changes *outcomes* (ACP → bothPass) on picks
  that stay in the index, so it requires a real `--all-from-index` re-survey.
  Determinism (cycle 118) means outcomes are byte-stable; only `capturedAt` +
  `swiftInferVersion` vary between runs.
- **`OrderedSet+Testing.swift` round-trip FPs** join Lever D (filter), with the
  lazy-wrapper (`CombinationsSequence`) + `ViolationFormatter` FPs. Of the 9
  remaining ACP, these are the addressable precision tail.
- Next: **Lever D** — filter the remaining FPs → ~90%+ of the legitimate
  denominator. The genuine-recall levers (A recall side, B, C-1) are now spent;
  D is pure precision/filtering.
