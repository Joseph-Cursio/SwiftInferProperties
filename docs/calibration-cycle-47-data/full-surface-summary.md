# Cycle-47 full-surface measurement summary

Captured: 2026-05-12 via `swift-infer verify --all-from-index --index-path fixtures/cycle27-surface/.swiftinfer/index.json --max-parallel 4`. swift-infer at v1.50 (post-V1.50.B).

## Aggregate

| Classification | Count | Share |
|---|---:|---:|
| measured-bothPass | 0 | 0.0% |
| measured-edgeCaseAdvisory | 0 | 0.0% |
| measured-defaultFails | 0 | 0.0% |
| measured-error | 0 | 0.0% |
| architectural-coverage-pending | 109 | **100.0%** |
| **Total** | **109** | **100.0%** |

**Full-surface verifiable-fraction: 0/109 = 0.0% (measured-execution)**. The first full-surface run produces a 100% architectural-coverage-pending classification — every cycle-27 pick hits a `VerifyError` *before* the verify subprocess builds. See §"Failure-reason breakdown" for the gap shape.

## Per-template breakdown

| Template | Count | unsupported-carrier | unsupported-pair | unsupported-template |
|---|---:|---:|---:|---:|
| round-trip | 12 | 12 | 0 | 0 |
| idempotence | 12 | 12 | 0 | 0 |
| monotonicity | 29 | 27 | 0 | 2 |
| commutativity | 17 | 17 | 0 | 0 |
| associativity | 17 | 17 | 0 | 0 |
| dual-style-consistency | 22 | 0 | 22 | 0 |
| **Total** | **109** | **85** | **22** | **2** |

## Failure-reason breakdown (post V1.50.B routing fix)

| Reason | Count | Examples |
|---|---:|---|
| `unsupported-carrier: Complex` | 20 | All ComplexModule picks — indexer stores bare `Complex` (no generic args); v1.46 hardcoded path expects `Complex<Double>`. |
| `unsupported-carrier: OrderedSet` | 17 | OrderedCollections public-surface picks. |
| `unsupported-pair: ...` | 22 | All dual-style-consistency picks. Curated pair list (sorted/sort, reversed/reverse, shuffled/shuffle) doesn't cover `formIntersection`, `formSymmetricDifference`, `formUnion`, `subtract`, `merge`, etc. |
| `unsupported-carrier: OrderedDictionary.Elements` | 7 | + 6 SubSequence variants + 6 Values variants. |
| `unsupported-carrier: ViolationFormatter` | 4 | PropertyLawKit-internal. |
| `unsupported-carrier: _HashTable` / `_HashTable.UnsafeHandle` | 8 | OrderedCollections internals. Indexer reaches them (the source is in `.build/checkouts/`); the verify subprocess can't import them via plain `import OrderedCollections`. |
| `unsupported-carrier: (none)` | 3 | Free-function picks (no carrier). |
| `unsupported-carrier: Chunked*` | 6 | Algorithms package's chunked-collection types. |
| `unsupported-template: monotonicity` | 2 | The 2 Double-carrier monotonicity picks that route through v1_46HardcodedBundle's default branch — v1.46 doesn't handle monotonicity. V1.50.B's routing fix mitigated 49 other cases that hit the same default. |

## Comparison vs cycle-46

| Metric | Cycle-46 (32-pick sample) | Cycle-47 (109-surface) |
|---|---:|---:|
| Picks classified | 30/32 (in-scope predicted) | 109/109 (measured) |
| Verifiable-fraction | 93.8% (measured) / 100% (architectural) | 0.0% (measured-execution) |
| Verifier-mode REJECT lift | 8/8 = 100% | n/a (no REJECTs measured) |
| Per-pick agreement | 30/30 = 100% (predicted) | n/a (no measured outcomes to compare) |

Cycle-46's measurement was **synthetic-shape-class agreement** (hand-crafted SemanticIndexEntry instances matching v1.49 emitter expectations); cycle-47 is the **first real-indexed verify run** and reveals a substantial measurement-tooling gap between cycle-27's discover-side surface and v1.49's verify-side expectations.

## Methodology note

The 109 surface entries were reconstructed from cycle-27's discover output via the `fixtures/cycle27-surface/` SwiftPM workspace (V1.50.A): four package deps (swift-numerics + swift-collections + swift-algorithms + SwiftPropertyLaws) resolved into `.build/checkouts/`, indexed via `swift-infer index --target <module>`, merged into a single 109-entry JSON file sorted by identityHash.

The 109-pick total matches cycle-27's v1.29 final surface (Algo 8 + ComplexModule 20 + OrderedCollections 74 + PropertyLawKit 7).

Survey wall-clock: ~109 verifications × ~5s each / 4-parallel = **~3 minutes** total. None of the verify subprocesses reached `swift build` because all 109 picks errored at carrier/pair/template resolution before workdir synthesis.
