# v1.34 Calibration Cycle 31 — Findings (typeName Enrichment)

Captured: 2026-05-11. swift-infer at v1.34 development tip. The thirty-first execution of PRD §17.3's empirical-tuning loop and a **focused follow-up cycle** to v1.33's PRD §20.1 SemanticIndex.

## Headline

**`typeName` enrichment shipped.** v1.33 SemanticIndex shipped `typeName: String?` in the schema but every emitted entry had `typeName == nil`. v1.34 closes the gap so `swift-infer query --type Foo` works end-to-end. **No acceptance-rate re-measurement** — v1.34 is data-model widening with no per-template inference precision change.

| Metric | Cycle 30 (post-v1.33) | Cycle 31 (post-v1.34) | Δ |
|---|---:|---:|---|
| Surface (default mode) | 109 | 109 | 0 (no inference changes) |
| Acceptance rate | 72.4% (cycle-27 carries) | 72.4% (no re-measurement) | 0pp |
| Mechanism classes | 16 | 16 (no new) | 0 |
| **% entries with `typeName` populated** | **0%** | **100%** | **+100pp** |
| Test count | 2027 | 2027 | 0 (no new tests; behavioral verification end-to-end) |

## What v1.34 ships

Three workstreams:

- **V1.34.A**: `carrier: String?` field added to `Suggestion` in `SwiftInferCore`. Optional with default nil for backward compatibility. Existing call sites compile unchanged.

- **V1.34.B**: Carrier threaded through **16 construction sites** — 11 template `suggest()` emitters + 4 post-template rebuilders + 1 TestLifter promotion path:

  | Template | Carrier source |
  |---|---|
  | IdempotenceTemplate | `summary.containingTypeName` |
  | IdempotenceTemplate+Lifted | `lifted.carrier` |
  | RoundTripTemplate | `pair.forward.containingTypeName` |
  | InversePairTemplate | `pair.forward.containingTypeName` |
  | InversePairTemplate+Lifted | `pair.forward.carrier` |
  | MonotonicityTemplate | `summary.containingTypeName` |
  | CommutativityTemplate | `summary.containingTypeName` |
  | AssociativityTemplate | `summary.containingTypeName` |
  | IdentityElementTemplate | `pair.operation.containingTypeName` |
  | IdentityElementTemplate+Lifted | `pair.operation.carrier` |
  | DualStyleConsistencyTemplate | `pair.mutatingMember.containingTypeName` |
  | CompositionTemplate | `lifted.carrier` |
  | InvariantPreservationTemplate | `summary.containingTypeName` |
  | GeneratorSelection.rebuild (M3 pass) | preserves `suggestion.carrier` |
  | GeneratorSelection.rebuildWithCodableRoundTrip (M5.4) | preserves `suggestion.carrier` |
  | LiftedSuggestionPipeline domain-hint rebuild | preserves `suggestion.carrier` |
  | LiftedSuggestionPipeline mock-generator rebuild | preserves `suggestion.carrier` |
  | LiftedSuggestionPromotion.toSuggestion | `typeName` parameter |

- **V1.34.C**: `IndexCommand.buildEntry.carrierType(for:)` reads `suggestion.carrier` directly (previously returned nil).

## End-to-end verification

### swift-numerics ComplexModule (20 suggestions)

All 20 entries now have `typeName: "Complex"` populated. `query --type Complex` matches all 20; `query --type none` matches 0 (every CM suggestion is a method on the Complex struct).

### swift-collections OrderedCollections (74 suggestions)

**10 distinct carrier types** surfaced — a richer index surface than ComplexModule's single-type pattern:

| Carrier type | Entry count |
|---|---:|
| OrderedSet | 29 |
| OrderedSet.UnorderedView | 8 |
| OrderedDictionary.Elements | 7 |
| OrderedSet.SubSequence | 6 |
| OrderedDictionary.Elements.SubSequence | 6 |
| OrderedDictionary.Values | 6 |
| _HashTable | 4 |
| _HashTable.UnsafeHandle | 4 |
| OrderedDictionary | 3 |
| _UnsafeHashTable | 1 |

Nested type names (`OrderedDictionary.Elements.SubSequence`, `_HashTable.UnsafeHandle`) work transparently — the carrier is the full qualified path from `FunctionSummary.containingTypeName`, which the SyntaxScanner already produces correctly. No additional escaping or normalization needed for the v1.34 query path.

## Scope boundaries observed

- **In scope**: data-model widening + thread-through + end-to-end consumption. `query --type Foo` works on exact-string match.
- **Out of scope**: query-side carrier normalization (e.g., matching `OrderedSet` vs `OrderedCollections.OrderedSet`). Exact-string match for v1.34; future cycle if users report friction.
- **Out of scope**: carrier-aware suggestion filtering at discover time. The carrier is metadata for display + query; it doesn't change which suggestions surface.
- **Out of scope**: cross-module type resolution. SemanticIndex integration with SourceKit-LSP (PRD §20.4) is the right place for that; v1.34 stays within the v1 source-walk scope.

## Cycle-32 priority

Per the 4-cycle design-completion sequence: v1.32 Domain Template Packs → v1.33 SemanticIndex → v1.34 typeName enrichment → **v1.35 Constraint Engine upgrade (PRD §20.2)**.

The Constraint Engine replaces "templates as patterns over signatures" with "constraints over a function graph + types + usage." The v1 architecture is constraint-engine-ready per PRD §20.2's "the scoring engine can be replaced without touching downstream contracts" guarantee.

## Conclusion

v1.34 closes the v1.33-deferred `typeName` field with a small, well-scoped 3-workstream cycle. The `Suggestion` data model widening + thread-through across 16 sites + index-emitter consumption ships in one cycle without regressions. The end-to-end `query --type Foo` filter now works on every corpus that runs through `swift-infer index`, surfacing the carrier-rich semantic structure that's been latent in the codebase all along.

v1.35 Constraint Engine upgrade (PRD §20.2) begins next.
