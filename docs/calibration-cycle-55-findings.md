# v1.58 Calibration Cycle 55 — Findings (TypeShape scaffold opening; methodology guard surfaces 4 latent bindings)

Captured: 2026-05-13. swift-infer at v1.58 (post-V1.58.A + V1.58.B). Fifty-fifth execution of PRD §17.3's empirical-tuning loop.

## Headline

**Aggregate counts unchanged from cycle-54 (20 measured + 83 pending + 0 error + 103 total).** V1.58.A's `OrderedSet → OrderedSet<Int>` binding fires correctly but doesn't close picks alone — the strategist still rejects the bound carrier (no curated `OrderedSet<Int>` recipe). **Forward progress visible in the detail-string shift** on 29 OS picks: `"unsupported-carrier: OrderedSet"` → `"unsupported-carrier: OrderedSet<Int>"`.

| Outcome | Cycle-54 (103) | Cycle-55 (103) | Δ |
|---|---:|---:|---:|
| measured-bothPass | 6 | 6 | 0 |
| measured-edgeCaseAdvisory | 8 | 8 | 0 |
| measured-defaultFails | 6 | 6 | 0 |
| measured-error | 0 | 0 | 0 |
| architectural-coverage-pending | 83 | 83 | 0 |

**v1.58 is scaffolding-only by design**. Full OC closure is v1.59-v1.61 scope (3 cycles).

## What V1.58.A accomplished

**Layer-by-layer progress on OS picks**:
- Pre-V1.58.A: 29 OS picks fail at `bound(_:)` → `unsupported-carrier: OrderedSet` (no binding for OrderedSet).
- Post-V1.58.A: 29 OS picks pass `bound(_:)` → `OrderedSet<Int>` → strategist rejects → `unsupported-carrier: OrderedSet<Int>` (no curated recipe for OrderedSet<Int>).

The failure moves down one layer. The new detail string surfaces the next gap — strategist-side generator generation. v1.59 closes this layer.

## What V1.58.B accomplished

The new `V1_58MethodologyGuardTests` suite enforces a load-bearing invariant: every `GenericBindingResolver.curatedBindings` key must match at least one cycle-27 carrier name (either a top-level `typeName` or a `typeShape.storedMembers[].typeName`).

**First-run findings — 4 latent V1.47.D bindings**:
- `Self.Index`, `Self.Element`, `Base.Element`, `Iterator.Element`: V1.47.D added these preemptively for "the `Self.Index` / `Self.Element` shape that protocol extensions on Collection / Sequence produce" (per the V1.47.D code comment). **No cycle-27 entry surfaces them as stored-member type names.**

**Resolution**: documented in `intentionallyUnmatchedKeys` set with rationale (V1.47.D protocol-extension anticipation). Future cycles either keep the entries documented or remove them if cycle-N evidence shows they're stale.

**`Base.Index` is load-bearing** — appears as a stored-member type-name in cycle-27's `ChunkedByCollection` TypeShapes. The V1.47.D binding for that one matches.

**`Complex` (V1.51.A) and `OrderedSet` (V1.58.A) match cycle-27 carriers** — 20 Complex picks + 29 OS picks respectively.

## Pre-existing test failures caught

V1.58.B's first run + V1.58.A's binding-test addition surfaced 2 pre-existing latent test failures from prior cycles:

1. **V1.51.D's `cycle27FixtureHasExpectedSurfaceCount` asserted `count == 109`**. V1.57's fixture rebuild changed the count to 103 but didn't update the test. **The v1.57.0 tag was made with this test silently failing in the pre-rebuild test run, then committed/tagged with the new fixture, then the failure surfaced on next run.** Methodology lesson: when changing a fixture, the test run that validates the cycle must happen *after* the rebuild. v1.58 fixes the assertion (109 → 103).

2. **V1.54.B's `unknownCarrierPassesThrough` asserted `resolve("OrderedSet") == nil`**. V1.58.A's new binding broke this. Fixed by reframing the assertion: remove the OrderedSet line; add a dedicated `orderedSetBindsToInt` test that pins the new binding.

Both are intentional consequences of correct architecture evolution; both are fixed cleanly in v1.58.

## What cycle-55 establishes

1. **V1.58.A's binding fires correctly.** Detail-string transition confirms the binding-resolver layer accepts the OC carrier; the next-layer failure is at the strategist's `resolveRecipe`. v1.59 needs a curated `OrderedSet<Int>` recipe.

2. **V1.58.B's methodology guard works as designed.** Surfaced 4 latent bindings at unit-test speed; the resolution is explicit + reviewable. V1.51.B / V1.52.C-style latent-key issues are prevented going forward.

3. **The TypeShape scaffold is multi-cycle.** v1.58 is the first step (binding only); v1.59 needs strategist recipe + (probably) instance-method emission for any OC picks to close.

4. **The methodology hygiene improved at cycle-55.** Pre-existing latent test failures from v1.57's fixture rebuild caught + fixed. Future cycles should run tests *after* fixture rebuilds, not before.

5. **The `.measured-error = 0` baseline and 103-pick coherent index hold.**

## Cycle-46 predictions vs cycle-55 actuals

Unchanged from cycle-54:
- **Strict 4-category match**: 5 / 13 = 38%
- **Semantic "property holds" match**: 13 / 13 = **100%**

## v1.59+ priorities

In priority order:

1. **v1.59 — Strategist-side `OrderedSet<Int>` recipe** (closes the v1.58 scaffold-gap-layer). Add a curated branch in `StrategistDispatchEmitter.resolveRecipe` that returns a generator recipe for `OrderedSet<Int>` via `Gen<[Int]>.array(...).map { OrderedSet($0) }`. Closes the strategist-rejection failure on 29 OS picks.

2. **v1.59-v1.60 — Mutating-instance-method idempotence emission for OC.** The existing emit shape (`forwardCall(value)`) doesn't work for `sort()`-style mutating methods. New emit shape: `var copy1 = value; copy1.sort(); var copy2 = value; copy2.sort(); copy2.sort(); if copy1 != copy2 { fail }`. Once landed, ~5-10 OS picks should reach `.bothPass` / `.defaultFails`.

3. **v1.60-v1.61 — Generalize TypeShape work to other OC carriers**: `OrderedSet.UnorderedView`, `OrderedDictionary`, `_HashTable`, `ChunkedByCollection`, `EvenlyChunkedCollection`, `CombinationsSequence`. Pattern established in v1.59-v1.60 should generalize.

4. **v1.61+ — Phase 2 accept-flow integration**.

5. **v1.61+ — Per-function default-pass domain refinement** (v1.55 carry-forward).

## Captured artifacts

- Cycle-55 survey JSON: `docs/calibration-cycle-55-data/full-surface-outcomes.json` (103 entries).
- Aggregate summary: `docs/calibration-cycle-55-data/full-surface-summary.md`.
- V1.58.A code + binding test — staged for the v1.58 commit.
- V1.58.B test suite — staged.
- Pre-existing test fixes (V1.51.D count; V1.54.B OS assertion) — staged.

## Open threads carried into v1.59

1. **Strategist-side `OrderedSet<Int>` recipe** — the v1.59 load-bearing target.
2. **Mutating-instance-method emission** — needed for ~most OC picks.
3. **Generic Element binding for non-OrderedSet carriers** — TypeShape work extends to OD, _HashTable, etc.
4. **The `.architectural-coverage-pending` category structure remains** — 83 picks, 100% OC + Algo generic-instantiation gaps.
5. **Methodology guard maintenance** — escape-hatch set requires manual rationale on each entry.
