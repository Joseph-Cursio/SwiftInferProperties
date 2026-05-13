# Cycle-55 full-surface measurement summary

Captured: 2026-05-13 via `swift-infer verify --all-from-index --index-path fixtures/cycle27-surface/.swiftinfer/index.json --max-parallel 4`. swift-infer at v1.58 (post-V1.58.A + V1.58.B).

## Aggregate

| Classification | Cycle-53 (109) | Cycle-54 (103) | Cycle-55 (103) | Δ vs c54 |
|---|---:|---:|---:|---:|
| measured-bothPass | 6 | 6 | 6 | 0 |
| measured-edgeCaseAdvisory | 8 | 8 | 8 | 0 |
| measured-defaultFails | 6 | 6 | 6 | 0 |
| measured-error | 0 | 0 | 0 | 0 |
| architectural-coverage-pending | 89 | 83 | 83 | 0 |
| **Total** | **109** | **103** | **103** | 0 |

**All aggregate counts unchanged from cycle-54.** V1.58.A's `OrderedSet → OrderedSet<Int>` binding fires but the strategist still rejects the bound carrier (no curated recipe for `OrderedSet<Int>`); the 29 OS picks stay in `.architectural-coverage-pending`. **Forward progress at the resolution layer** is visible only in the outcome-detail strings.

## What V1.58.A accomplished

**Detail-string shift on 29 OS picks**:

| Cycle-54 detail | Count | Cycle-55 detail | Count |
|---|---:|---|---:|
| `unsupported-carrier: OrderedSet` | 29 | `unsupported-carrier: OrderedSet<Int>` | 29 |

The `bound(_:)` resolver-level canonicalization passes; the failure moves down one layer to the strategist's `resolveRecipe` step. v1.59 closes this layer by adding a curated `OrderedSet<Int>` recipe (instance generation via `OrderedSet([Int])` from a `Gen<[Int]>` value).

## What V1.58.B accomplished

**4 latent V1.47.D bindings surfaced**:

| Binding key | V1.47.D rationale | Cycle-27 fixture match |
|---|---|---|
| `Self.Index` | "protocol extensions on Collection / Sequence produce these" | None |
| `Self.Element` | same | None |
| `Base.Element` | same | None |
| `Iterator.Element` | same | None |

These were added preemptively in V1.47.D for hypothetical protocol-extension-produced TypeShapes but no cycle-27 entry surfaces them as stored-member type names. Resolution: documented in `intentionallyUnmatchedKeys` with rationale; the V1.58.B methodology guard's positive signal (matched bindings) plus negative signal (escape-hatch entries) makes future binding decisions explicit.

**`Base.Index` is NOT in the escape hatch** — cycle-27's `ChunkedByCollection` picks have `Base.Index` as a stored-member type-name in their TypeShape (per V1.47.B). The V1.47.D binding for that one IS load-bearing.

**`Complex` and `OrderedSet` are in `curatedBindings` and match cycle-27 carriers** — Complex (20 picks have typeName="Complex"), OrderedSet (29 picks). Both fire when the verify pipeline runs against real-indexer entries.

## Per-template breakdown

Unchanged from cycle-54.

## What cycle-55 establishes

1. **V1.58.A's binding fires correctly** but doesn't close picks alone. The detail-string transition `OrderedSet → OrderedSet<Int>` confirms the binding-resolver layer accepts the OC carrier; the next-layer failure is at the strategist's `resolveRecipe` (no curated generator for `OrderedSet<Int>`).

2. **V1.58.B's methodology guard works as designed.** Surfaced 4 latent V1.47.D bindings at unit-test speed; the resolution (escape-hatch entry with rationale) is explicit and reviewable. Future V1.51.B / V1.52.C-style latent-key issues are prevented pre-merge.

3. **The `.measured-error = 0` baseline holds.** V1.58 doesn't introduce any new error categories.

4. **The cycle-27 baseline of 103 picks holds.** V1.58 doesn't change the fixture or scanner behavior; the count carries forward from cycle-54.

5. **TypeShape work is multi-cycle.** v1.58 is the first scaffold step (binding only); v1.59 needs strategist-side generator support; v1.60+ needs mutating-instance-method emission. Full OC closure projected v1.59-v1.61 (~3 cycles).

## Cycle-46 predictions vs cycle-55 actuals

Unchanged from cycle-54:
- **Strict 4-category match**: 5 / 13 = 38%
- **Semantic "property holds" match**: 13 / 13 = **100%**

## v1.59+ priorities

In priority order:

1. **v1.59 — Strategist-side `OrderedSet<Int>` recipe**. Add a curated branch in `StrategistDispatchEmitter.resolveRecipe` that handles `OrderedSet<Int>`: returns a recipe with expression like `Gen<[Int]>.array(of: Gen<Int>.int(in: -100...100), count: 10).map { OrderedSet($0) }`. Builds on V1.58.A; closes the strategist-recipe-layer failure for 29 OS picks.

2. **v1.59-v1.60 — Mutating-instance-method idempotence emission for OC**. The current `IdempotenceStubEmitter` assumes `forwardCall(value)` returns a value. For OC mutating methods like `sort()`, the emit shape is: `var copy1 = value; copy1.sort(); var copy2 = value; copy2.sort(); copy2.sort(); if copy1 != copy2 { fail }`. Once instance-method emission lands, ~5-10 OS picks should reach `.bothPass` / `.defaultFails`.

3. **v1.60-v1.61 — Generalize TypeShape work to other OC carriers** — `OrderedSet.UnorderedView`, `OrderedDictionary`, `OrderedDictionary.Elements`, `_HashTable`, `ChunkedByCollection`, `EvenlyChunkedCollection`, `CombinationsSequence`. Pattern established in v1.59-v1.60 generalizes.

4. **v1.61+ — Phase 2 accept-flow integration**. Now demonstrably viable: 20-pick measurable sample, 0 .measured-error, methodology guard preventing latent-key recurrence, 103-pick coherent baseline.

5. **v1.61+ — Per-function default-pass domain refinement** (v1.55 carry-forward).

## Methodology notes

- **Wall-clock**: ~4-5 min for the 103-pick survey (matched cycle-54).
- **The methodology guard's escape-hatch grows over time** — v1.58 starts with 4 V1.47.D entries; v1.59+ may add more as new binding-shape patterns emerge. Each entry requires a code-comment rationale (enforced by reviewer eyeballs, not test machinery).
- **The cycle-55 / cycle-54 outcome equivalence is not a regression** — v1.58 was scoped explicitly as scaffolding-only. The detail-string shift is the visible forward-progress signal at this scaffolding layer.
