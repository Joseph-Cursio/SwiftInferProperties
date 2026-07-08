# Standard-library confidence anchor (V1.147)

Connects a discovered candidate to the **proven standard-library truth (or trap)
it resembles**, as explainability provenance. When a candidate's `(template
family, stdlib carrier)` matches the known-properties catalog, `discover` appends:

- a **"Proven analog"** line for a matching **law** (`Set.union` is commutative —
  `Semilattice`), and
- a **"Known counter-example"** line for a matching **caveat** (`Set.subtracting`
  is not commutative).

## Score-neutral, by design

The anchor adds **no score**. Two reasons:

1. The scoring engine already covers the caveats (`antiCommutativityNaming`,
   `floatingPointStorage`), so a counter-signal would double-count.
2. A carrier match is *suggestive, not proof* — a user's `(Set, Set) -> Set`
   might be `union` (commutative) or `subtracting` (not). Boosting on carrier
   alone would risk the "shared shape ≠ shared purpose" false positive.

So the value is **provenance the engine doesn't cite by name**, leaving scoring
to the existing signals. The `Set` commutativity case is why both halves ship:
`union` is a proven analog *and* `subtracting` is a proven trap, so the candidate
gets both lines and the reader sees the ambiguity to resolve.

## Example

`discover` on `static func combine(_ a: Set<Int>, _ b: Set<Int>) -> Set<Int>`:

```
Template: commutativity
Why suggested:
  ✓ Type-symmetry signature: (T, T) -> T (T = Set<Int>) (+30)
  ✓ Curated commutativity verb match: 'combine' (+40)
  ✓ Proven analog: `Set` satisfies `a.union(b) == b.union(a)` — semilattice under union (SwiftPropertyLaws `Semilattice`).
Why this might be wrong:
  ⚠ Known counter-example on `Set`: subtracting is NOT commutative (`a.subtracting(b) != b.subtracting(a)` in general.)
```

## How it works

- Catalog entries (`StandardLibraryProperties`) carry a `template` tag (the
  `discover` family they correspond to) so a candidate's `templateName` +
  carrier can be matched to laws (analogs) and caveats (traps).
- The operand type of a `(T, T) -> T` pick lives in the evidence **signature**
  (`T`), not the carrier (the enclosing type), so `StdlibAnchor` parses the
  first parameter type and also considers `carrier` / `carrierTypeName`.
- Provenance is injected **at render time** (`Discover+Render`), score-neutral,
  via `Suggestion.withExplainability`. Fires only for the bare stdlib carriers
  in the catalog, so custom-type output is unchanged.

## Files / tests

- `StdlibAnchor.swift` (pure: provenance + signature parsing + carrier
  normalization), `Suggestion.withExplainability` (Core), catalog `template`
  tags, one wire-in at `Discover+Render`.
- Tests: `StdlibAnchorTests` (6). Fast suite green; enriching discover output
  broke no golden/explainability tests (the anchor is scoped to bare stdlib
  carriers, which the fixtures don't use).
