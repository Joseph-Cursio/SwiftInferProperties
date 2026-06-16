# Calibration cycle 149 — Lever B: Collection index-traversal exclusion

**Captured 2026-06-16.** Second build cycle of the v1-algebraic-rate epic
(cycle 147). Owner chose **B1 (filter)** after the scoping revealed Lever B's
20 picks aren't what cycle-147 projected.

## The correction (Lever B ≠ SetAlgebra emitter)

Cycle 147 projected Lever B as an "instance/mutating-method emitter for
SetAlgebra ops (formUnion etc.), +20 measured bothPass → ~85%". The actual 20
`instance-method-shape-not-supported` picks are all **`distance(from:to:)`
and `index(_:offsetBy:)`** on `OrderedSet` / `OrderedDictionary` views —
Collection **index-traversal** methods, not SetAlgebra operators.

They match the `(T, T) -> T` binary-operator signature only because
**`OrderedSet.Index == Int`**, so `distance(from:to:) -> Int` is literally
`(Int, Int) -> Int`. But they are **semantic false positives**: `distance`
is antisymmetric (not commutative), and index/offset arithmetic over indices
is neither commutative nor associative. They could never `bothPass`; the
cycle-147 "+20 bothPass" sizing was wrong.

So the right move is **precision (filter)**, not an emitter to execute them:
surfacing "is `OrderedSet.distance` commutative?" is noise (PRD §3.5), and
building a receiver+index emitter to disprove obvious false positives is
disproportionate.

## The change

`FunctionSummary.binaryOperatorTypeSymmetrySignal` (the shared signal feeding
both `CommutativityTemplate` and `AssociativityTemplate`) now returns `nil`
for the stdlib Collection index-traversal requirements, identified by **base
name + argument labels** (robust against a same-named user method with
different labels):

- `distance` with labels `[from, to]`
- `index` with labels `[_, offsetBy]`

## Result

| | before (Lever A) | after Lever B |
|---|---|---|
| index entries (denominator) | 82 | **62** (−20 false positives) |
| measured | 50 | 50 |
| measured-execution rate | 61.0% | **80.6%** |

**Survey-confirmed**: 36 bothPass + 6 defaultFails + 8 edgeCaseAdvisory = 50
measured / 62 = **80.6%**; 12 architectural-coverage-pending remain (6
lazy-wrapper false positives + 6 real public types for Lever C).

Cumulative: 50.5% (frozen) → 61.0% (Lever A) → 80.6% (Lever B). Precision
also improves: 20 non-algebraic suggestions no longer surfaced.

## Verification

- `CommutativityTemplateTests` — `distance(from:to:)` / `index(_:offsetBy:)`
  excluded; a same-named method with different labels still matches.
- **Clean-discovery check**: deleted the swift-collections per-corpus index
  and re-ran `swift-infer index` — no `distance`/`index`
  commutativity/associativity entries emitted (filter works end-to-end in the
  indexer, not just in `suggest`).
- cycle27 index = the Lever-A 82-entry index minus exactly the 20 traversal
  picks → 62 (faithful to the filter; avoids the index command's incremental
  join + rebuild-scope churn). Re-surveyed to confirm the rate.
- `make test-fast` green.

## Notes

- The `swift-infer index` command is **incremental** (joins fresh discovery
  with the prior on-disk index), so a plain re-run retains already-indexed
  entries. Deriving the committed index from the prior one minus the dropped
  picks is the clean way to reflect a discovery-filter change (same approach
  as cycle-148 Lever A).
- Next: **Lever C** — pair/recipe gaps for the real public types
  (`OrderedSet<Int>` round-trip, `OrderedDictionary`; ~6 picks → measured) →
  projected ~90%.
