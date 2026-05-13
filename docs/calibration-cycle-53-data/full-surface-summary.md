# Cycle-53 full-surface measurement summary

Captured: 2026-05-13 via `swift-infer verify --all-from-index --index-path fixtures/cycle27-surface/.swiftinfer/index.json --max-parallel 4`. swift-infer at v1.56 (post-V1.56.A). **First cycle with `.measured-error` count at 0 — clean baseline.**

## Aggregate

| Classification | Cycle-51 (v1.54) | Cycle-52 (v1.55) | Cycle-53 (v1.56) | Δ vs c52 |
|---|---:|---:|---:|---:|
| measured-bothPass | 6 | 6 | 6 | 0 |
| measured-edgeCaseAdvisory | 0 | 8 | 8 | 0 |
| measured-defaultFails | 14 | 6 | 6 | 0 |
| **measured-error** | **2** | **2** | **0** | **-2** |
| architectural-coverage-pending | 87 | 87 | **89** | **+2** |
| **Measured-execution total** | 20 | 20 | 20 | 0 |

**No change in measured-execution count.** The 2 cycle-52 `.measured-error` picks (both `Complex.rescaledDivide(_:_:)` × commutativity + associativity) shift to `.architectural-coverage-pending` with detail `"internal-api-not-accessible"` — the function is declared `internal` in swift-numerics; the verifier workdir's executable target can't access it.

**Headline shift: `.measured-error` category is now empty.** Every cycle-27 pick is correctly classified into one of `.bothPass` / `.edgeCaseAdvisory` / `.defaultFails` (real measurement) or `.architectural-coverage-pending` (known measurement-tooling gap with specific detail).

## Per-template breakdown

| Template | Surface | pending | .bothPass | .defaultFails | .edgeCaseAdvisory |
|---|---:|---:|---:|---:|---:|
| round-trip | 12 | 4 | 0 | 0 | 8 |
| idempotence | 12 | 12 | 0 | 0 | 0 |
| monotonicity | 29 | 27 | 2 | 0 | 0 |
| commutativity | 17 | 12 (+1) | 2 | 3 | 0 |
| associativity | 17 | 12 (+1) | 2 | 3 | 0 |
| dual-style-consistency | 22 | 22 | 0 | 0 | 0 |
| **Total** | **109** | **89** | **6** | **6** | **8** |

The +1 for commutativity and associativity in `pending` is the 2 reclassified `rescaledDivide` picks (one per template).

## .architectural-coverage-pending detail breakdown (89 picks)

V1.56.A's reclassification adds a new detail string. The full breakdown:

| Detail | Count | What it means |
|---|---:|---|
| `unsupported-carrier: OrderedSet` | 29 | OC bare-type generic; needs TypeShape-driven Element binding (v1.57+) |
| `unsupported-carrier: OrderedSet.UnorderedView` | 8 | OC nested generic; same |
| `unsupported-carrier: OrderedDictionary.Elements` | 7 | OC nested generic; same |
| `unsupported-carrier: OrderedSet.SubSequence` | 6 | OC nested generic; same |
| `unsupported-carrier: OrderedDictionary.Values` | 6 | OC nested generic; same |
| `unsupported-carrier: OrderedDictionary.Elements.SubSequence` | 6 | OC nested generic; same |
| `unsupported-carrier: ViolationFormatter` | 4 | Kit-side type; same |
| `unsupported-carrier: _HashTable.UnsafeHandle` | 4 | OC internal generic; same |
| `unsupported-carrier: _HashTable` | 4 | OC internal generic; same |
| `unsupported-carrier: OrderedDictionary` | 3 | OC bare-type generic; same |
| `unsupported-carrier: (none)` | 3 | Likely indexer bug — typeName field is null; v1.57+ |
| `unsupported-carrier: EvenlyChunkedCollection` | 2 | Algo bare-type generic; needs TypeShape (v1.57+) |
| `unsupported-carrier: CombinationsSequence` | 2 | Algo bare-type generic; same |
| `unsupported-carrier: ChunkedByCollection` | 2 | Algo bare-type generic; same |
| `unsupported-carrier: _UnsafeHashTable` | 1 | OC internal generic; same |
| **`internal-api-not-accessible`** | **2** | **V1.56.A NEW: `rescaledDivide(_:_:)` × {commutativity, associativity}; fix via @testable or indexer-time filter** |

The 87 pre-V1.56 `.architectural-coverage-pending` picks have detail strings starting with `"unsupported-carrier:"` — all OC + Algo generic types pending v1.57+ TypeShape work. The 2 new V1.56.A entries have a different detail string indicating a different fix path (access-level, not generic-instantiation).

## What V1.56.A accomplished

| Cycle | `.measured-error` count | What changed |
|---|---:|---|
| Cycle-50 (v1.53) | 10 | 8 V1.52.A regressions + 2 `rescaledDivide` |
| Cycle-51 (v1.54) | 2 | V1.54.A free-fn revert cleared the 8; `rescaledDivide` remained |
| Cycle-52 (v1.55) | 2 | unchanged from cycle-51 |
| Cycle-53 (v1.56) | **0** | V1.56.A reclassified `rescaledDivide` picks |

The `.measured-error` category is now an alarm — anything in it after v1.56 represents an unexpected build/runtime failure, not a known measurement-tooling gap.

## Cycle-46 predictions vs cycle-53 actuals

Unchanged from cycle-52. 13 of 32 sample picks have measurable outcomes:

- **Strict 4-category match**: 5 / 13 = 38% (unchanged).
- **Semantic "property holds" match**: 13 / 13 = **100%** (unchanged).

V1.56.A doesn't change either rate — the 2 reclassified picks weren't in the 32-pick stratified sample.

## What cycle-53 establishes

1. **V1.56.A closes the cycle-52 `.measured-error` residual.** All 109 cycle-27 picks now classify correctly: 20 with real measurement, 89 with specific tooling-gap detail strings. **0 unexplained build failures.**

2. **The reclassification pattern works as designed.** Stdout-based detection (not stderr) is the right call for `swift build` subprocess diagnostics. V1.56.B's unit tests pin the behavior; the helper is extension-ready for v1.57+ (e.g. `@_spi` symbols, internal-typed parameters).

3. **The `.architectural-coverage-pending` category is now informative**. Pre-V1.56 it was a catch-all for any "non-public" gap. Post-V1.56 it has structured detail strings (`unsupported-carrier: X` / `internal-api-not-accessible` / etc.) so the dominant gaps are visible at a glance.

4. **Methodology lesson: stdout-vs-stderr matters.** The first cycle-53 run with stderr-only check produced 2 unchanged `.measured-error` outcomes — the V1.56.A code didn't fire. Switching to both-stream check resolved it. v1.57+ should validate stream assumptions in unit tests rather than relying on integration-level smoke tests.

5. **The remaining 87 `unsupported-carrier` picks are still the dominant single gap**. v1.57+'s TypeShape-driven OC instantiation is the next-biggest workstream.

## v1.57+ priorities (per cycle-53 evidence)

In priority order:

1. **v1.57-v1.58 — TypeShape-driven generic instantiation** for OC + Algo types. Dominant remaining category (87 picks; ~60 OC + 27 monotonicity OC + Algo wrappers). Substantial scope; multi-cycle.

2. **v1.57 — Instance-method emission** for OC + Algo wrappers. The current emitters assume free or static functions; OC picks like `OrderedSet.insert(_:)` are instance methods. Closes a subset of the OC picks once TypeShape work lands.

3. **v1.57 — Methodology guard for binding tables**. Fixture-level check that every `GenericBindingResolver.curatedBindings` key matches at least one indexer-produced carrier name. Prevents V1.51.B + V1.52.C latent-key recurrence.

4. **v1.57 — Indexer-time non-public-symbol filter (optional)**. The 2 V1.56.A-reclassified picks are noise; filtering at indexer time would drop the cycle-27 fixture from 109 to 107. Decision deferred — preserves the v1.29-frozen baseline by default; v1.57 may flip if cycle-N reveals more internal-API noise.

5. **v1.57-v1.58 — Investigate the 3 `(none)`-typeName picks** in cycle-53's pending bucket — likely indexer-side bug.

6. **v1.58+ — Phase 2 accept-flow integration**. The 20-pick measurable sample + clean `.measured-error = 0` baseline make accept-flow viable.

## Methodology notes

- **Wall-clock**: ~5 min for the 109-pick survey (matched cycles 50-52).
- **First-cycle V1.56.A bug**: the initial implementation checked only stderr; cycle-53 first run produced 2 unchanged `.measured-error`. Debugging via `swift build 2>/tmp/stderr.txt 1>/tmp/stdout.txt; grep` revealed compiler diagnostics land on stdout. Fix: both-stream check + extracted testable helper. ~10 min iteration.
- **The `.measured-error = 0` baseline is now a CI-able alarm.** A future cycle producing `.measured-error > 0` indicates an unexpected build/runtime failure (not a known measurement-tooling gap), motivating immediate investigation.
