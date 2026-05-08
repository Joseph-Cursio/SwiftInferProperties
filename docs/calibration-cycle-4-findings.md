# v1.7 Calibration Cycle 4 — Findings

Captured: 2026-05-08. swift-infer at `231ae16` (V1.7.1 — stdlib-conformance bake-in). The fourth execution of PRD §17.3's empirical-tuning loop.

This document is the cycle-4 record: what we ran, what we learned, what shipped, what's deferred. Cycle 5 reads this to decide where to perturb next.

## Headline

**Cycle 4 shipped one structural rule: curated stdlib-conformance bake-in.** A 14-key `[TypeName: Set<String>]` of stdlib types' known conformances (V1.7.1) seeds `ProtocolCoverageMap.inheritedTypesIndex(...)`, extending V1.5.2's coverage veto reach to stdlib-typed (`Int` / `Double` / `UInt64` / etc.) carriers. Closes cycle-2's headline 0-delta limitation.

| Tuning | Type | Where | Empirical effect |
|---|---|---|---|
| `ProtocolCoverageMap.stdlibConformances` (V1.7.1) | curated data extension | `inheritedTypesIndex(from:)`'s seed step | **−23 round-trip** suppressions (22 OrderedCollections via `Int: Codable` + `UInt64: Codable`; 1 Algorithms via `Double: Codable`); attribution-clean delta from V1.7.1 |
| `IdentityElementPairing.stdlibBinaryOperators += {pow, **}` (V1.6.1.1) | structural | math-library op-name gate | **−1 identity-element** suppression on ComplexModule (`(zero, pow)` × `Complex.zero` filtered) |

After v1.7: total `--include-possible` surface across the 4 corpora went **350 → 326** (−24, −6.9%). The 22-of-24 suppression concentration on OrderedCollections is the loudest signal: cycle-2's textual-only-coverage finding held up — when the bake-in extends reach to stdlib-typed carriers, the suppression candidates appear.

**Notable plan-vs-actual deviation (positive direction):** the v1.7 plan's f-bullet projected "OrderedCollections / Algorithms / PropertyLawKit show non-zero suppression on `(Int, Int) -> Int` ops." The actual outcome is more nuanced — the suppressions come through the **round-trip** template's `[codableRoundTrip]` coverage candidate, not commutativity / associativity. Cycle-2's `(Int, Int) -> Int` candidate set in OrderedCollections (10 commutativity + 10 associativity per cycle-3 data) had carriers like `Int` that **don't have explicit `+` / `*` operators in the corpus** (the user-defined functions are named `minimumCapacity`, `scale`, etc., not `+` / `*`). V1.5.2's commutativity / associativity coverage candidates are op-class-mapped (`+` → additiveCommutative, `*` → multiplicativeCommutative); user-named ops fall through to op-class fall-through and emit unsuppressed. **The bake-in's reach extends only as far as the existing veto-candidate-set design allows.** This is informative: cycle-5 priority candidate is re-examining the round-trip template's `[codableRoundTrip]` candidate (over-suppressing user-defined inverse pairs?) rather than extending bake-in coverage.

## Corpus selection

Same four cycle-1+2+3 targets — re-running on the cycle-3 baseline lets the suppression delta attribute cleanly to V1.6.1.1 + V1.7.1's combined effect:

| Corpus | Target | Cycle-3 post-filter total | Cycle-4 post-bakein total | Δ |
|---|---|---:|---:|---:|
| swift-collections | OrderedCollections | 101 | 79 | **−22** |
| swift-numerics | ComplexModule | 167 | 166 | **−1** |
| swift-algorithms | Algorithms | 75 | 74 | **−1** |
| SwiftPropertyLaws | PropertyLawKit | 7 | 7 | 0 |
| **Total** | | **350** | **326** | **−24 (−6.9%)** |

Per-corpus pre/post snapshots committed to `docs/calibration-cycle-4-data/post-bakein-*.discover.txt`. Diff target is `docs/calibration-cycle-3-data/post-filter-*.discover.txt`.

## What v1.7 ships (the mechanism)

One piece, in `Sources/SwiftInferCore/StdlibConformances.swift`:

- **A 14-key curated table.** `ProtocolCoverageMap.stdlibConformances: [String: Set<String>]` lists Swift stdlib types whose conformances are unconditional and well-known: signed integer family (`Int` / `Int8` / `Int16` / `Int32` / `Int64`) → `signedIntegerBase` (10 conformances including `AdditiveArithmetic` / `Numeric` / `SignedNumeric` / `Comparable` / `Hashable` / `Codable` / `Equatable`); unsigned integer family (`UInt` / `UInt8` / `UInt16` / `UInt32` / `UInt64`) → `unsignedIntegerBase` (no `SignedNumeric` / `SignedInteger`); floating-point family (`Float` / `Double`) → `floatingPointBase` (adds `FloatingPoint` / `BinaryFloatingPoint`); `Bool` → `[Equatable, Hashable, Codable]`; `String` → `[Equatable, Comparable, Hashable, Codable]`.
- **Seeded into `inheritedTypesIndex(from:)`.** `ProtocolCoverageMap.inheritedTypesIndex(from: typeDecls)` now seeds the result with `stdlibConformances` *before* folding corpus typeDecls. Per-key `formUnion` semantics preserved — a corpus `extension Int: SomeProto` *unions* with the curated set rather than replacing it.

The mechanism reuses V1.5.2's `coverageVetoSignal(...)` directly (already public). No new `Signal.Kind`, no new `KnownProperty`, no template-side changes — V1.5.2's scoring layer is unchanged.

## Per-corpus suppression breakdown

### swift-collections / OrderedCollections — the headline corpus

| Template | Cycle-3 | Cycle-4 | Δ | Notes |
|---|---:|---:|---:|---|
| idempotence | 27 | 27 | 0 | No round-trip-shaped candidates. |
| **round-trip** | **25** | **3** | **−22** | 21 `(Int) -> Int` + 1 `(UInt64) -> Int?` pairs all suppressed via bake-in's `Int: Codable` / `UInt64: Codable`. Survivors: 1 `(Bucket) -> Bucket` + 2 `(Self) -> Self` pairs (user types not in bake-in). |
| monotonicity | 20 | 20 | 0 | Coverage veto isn't wired to monotonicity (no kit-published monotonicity law in v1.5's table). |
| commutativity | 10 | 10 | 0 | Suggestions are user-named `(Int, Int) -> Int` ops (capacity / scale / wordCount); op-class fall-through preserves them. Bake-in correctly does *not* suppress these (kit covers `+`/`*` specifically, not arbitrary commutative functions on Numeric carriers). |
| associativity | 10 | 10 | 0 | Same as commutativity — user-named `(Int, Int) -> Int` ops fall through. |
| inverse-pair | 9 | 9 | 0 | Coverage veto candidates are `[additiveInverse, groupInverse]`; user-named `(Int, Int) -> Int` ops aren't operator-shaped subtraction. |

The 22 suppressed round-trip pairs all had stdlib-typed primary types that resolved through V1.7.1's `Int: Codable` / `UInt64: Codable` bake-in to V1.5.2's existing round-trip coverage veto on `[codableRoundTrip]`. Sample (cycle-3 → cycle-4 → suppressed):

```
[Cycle-3] (Int) -> Int round-trip pairs (all 21 suppressed in cycle-4):
  minimumCapacity(forScale:) ↔ maximumCapacity(forScale:)
  minimumCapacity(forScale:) ↔ scale(forCapacity:)
  minimumCapacity(forScale:) ↔ wordCount(forScale:)
  ...12 more HashTable+Constants / OrderedDictionary / OrderedSet pairs...
  word(after:) ↔ word(before:)
  index(after:) ↔ index(before:)  [7 distinct sites]

[Cycle-3] (UInt64) -> Int? round-trip pair (suppressed in cycle-4):
  _value(forBucketContents:) ↔ _bucketContents(for:)

[Cycle-3 → Cycle-4 surviving round-trip pairs (all on user types):
  bucket(after:) ↔ bucket(before:)  [(Bucket) -> Bucket]
  intersection(_:) ↔ subtracting(_:)  [(Self) -> Self, 2 sites]
```

### swift-numerics / ComplexModule

| Template | Cycle-3 | Cycle-4 | Δ | Notes |
|---|---:|---:|---:|---|
| **identity-element** | **2** | **1** | **−1** | V1.6.1.1's math-library op-name gate (`pow` added to `stdlibBinaryOperators`) filters `(zero, pow)` × `Complex.zero` at pair-formation. Surviving: `(zero, rescaledDivide)` × `Complex.zero` — `rescaledDivide` is user-named, outside the curated math-library set. |
| associativity | 6 | 6 | 0 | `Complex` is a user type with `: Numeric` conformance the corpus already declared; cycle-2's V1.5.2 veto already suppressed the kit-`+`/`*` pairs. The 6 survivors are non-`+`/`*` user-named ops (`-`, `/`, `pow`, `rescaledDivide`, etc.). |
| commutativity | 6 | 6 | 0 | Same as associativity — non-commutative user-named ops. |
| idempotence | 17 | 17 | 0 | No coverage match for these ops. |
| round-trip | 136 | 136 | 0 | `Complex` is in the corpus's typeDecls with `: Codable` already declared in cycle-2's textual scan; V1.7.1's bake-in has nothing to add. |

ComplexModule had been the headline corpus across cycles 1–3. Cycle-4 captures only V1.6.1.1's marginal gain (−1) on identity-element. Cumulative ComplexModule identity-element: **6 → 1 (−83.3%)** over three calibration cycles.

### swift-algorithms / Algorithms

| Template | Cycle-3 | Cycle-4 | Δ | Notes |
|---|---:|---:|---:|---|
| idempotence | 44 | 44 | 0 | No coverage match for these ops. |
| **round-trip** | **20** | **19** | **−1** | One `(Double) -> Double` pair suppressed via bake-in's `Double: Codable`. The 19 survivors are mostly `(Index) -> Index` / `(Base.Index) -> Base.Index` — generic associated types that aren't in the stdlib bake-in. |
| inverse-pair | 6 | 6 | 0 | Generic carrier types not in bake-in. |
| monotonicity | 3 | 3 | 0 | No coverage match. |
| commutativity | 1 | 1 | 0 | No coverage match. |
| associativity | 1 | 1 | 0 | No coverage match. |

### SwiftPropertyLaws / PropertyLawKit

| Template | Cycle-3 | Cycle-4 | Δ | Notes |
|---|---:|---:|---:|---|
| monotonicity | 6 | 6 | 0 | Kit-internal types (`Algorithm`, `LawCheckOutcome`, etc.); not in bake-in. |
| idempotence | 1 | 1 | 0 | Same. |

PropertyLawKit's surface has no stdlib-typed carriers, so V1.7.1's bake-in has nothing to extend coverage to. PropertyLawKit's 7-suggestion floor reflects genuine kit-internal claims that don't overlap with the bake-in's mechanism.

## Cumulative trajectory across cycles 1–4

The four calibration cycles compose on different cause-of-noise classes — each closing a structurally distinct gap:

| Cycle | Mechanism | Total surface | Δ from prior | Δ cumulative |
|---|---|---:|---:|---:|
| 1 (pre-tune) | none | 1167 | — | — |
| 1 (post-tune) | FP-storage + cross-type round-trip counter-signals | 358 | **−809** | −69.3% |
| 2 (V1.5.2 coverage veto) | textual-only protocol-coverage suppression on user types | 353 | −5 | −69.7% |
| 3 (V1.6.1 pair-formation filter) | identity-element pair-formation skip-list on `(constant, op)` cross-products | 350 | −3 | −70.0% |
| 4 (V1.7.1 stdlib bake-in) | extends V1.5.2's reach to stdlib carriers via curated 14-key table | 326 | **−24** | **−72.1%** |

**Cycle-4 is the second-largest reduction after cycle-1**, but small in proportional terms — the surface is now narrow enough (326 across four corpora) that further structural rules will likely produce sub-10 reductions per cycle. This is exactly the "decreasing returns per cycle" pattern the cycle-3 findings doc predicted.

The four mechanisms are mutually exclusive (no suggestion is suppressed by two at once):
- **V1.4.3** counter-signals: cross-type round-trip noise (textual type-name mismatch).
- **V1.5.2** coverage veto: user-type coverage match (textual-conformance reach).
- **V1.6.1** pair-formation filter: identity-element cross-product structural mismatches.
- **V1.7.1** bake-in: stdlib-type coverage reach (curated-table extension of V1.5.2).

## Why the round-trip template caught most of the suppressions

V1.5.2's per-template coverage candidates:
- `IdentityElementTemplate`: op-class-mapped (`(zero, +)` → `additiveIdentityZero`, etc.)
- `CommutativityTemplate`: op-class-mapped (`+` → `additiveCommutative`, etc.)
- `AssociativityTemplate`: op-class-mapped (`+` → `additiveAssociative`, etc.)
- `IdempotenceTemplate`: `[setIntersectionIdempotent, semilatticeIdempotence]`
- `InversePairTemplate`: `[additiveInverse, groupInverse]`
- **`RoundTripTemplate`: `[codableRoundTrip]`**

The op-class-mapped templates only suppress when the user-defined op is a stdlib operator (`+` / `*` / `-` / etc.). Cycle-3+4 corpora's commutativity / associativity suggestions on stdlib-typed carriers are user-named (`minimumCapacity`, `scale`, `combine`) — so op-class fall-through preserves them. The bake-in extends reach but the candidate-set design gates which suggestions actually get suppressed.

The round-trip template is the exception: its candidate set is the type-level `codableRoundTrip` (no op-class filter). Any round-trip pair whose carrier conforms to `Codable` gets suppressed — and V1.7.1's bake-in adds `Codable` to all 14 stdlib types. Hence the 22-of-24 concentration on round-trip.

**Cycle-5 question:** Is the round-trip template's `[codableRoundTrip]` candidate the *correct* coverage signal for stdlib-typed user-defined inverse pairs? OrderedCollections's `minimumCapacity(forScale:) ↔ scale(forCapacity:)` is a user-defined inverse pair *by intent* — not a Codable round-trip. The kit's `checkCodableRoundTripPropertyLaws` doesn't verify this user-defined inverse claim. V1.5.2's candidate-set choice was arguably over-broad; the bake-in extends that over-breadth to stdlib types.

This is **the most empirically interesting cycle-4 finding**: the bake-in worked exactly as designed (extending V1.5.2's reach), and that surfaced an inherited V1.5.2 design question. Cycle-5 priority candidate: tighten the round-trip template's coverage candidates to fire only when the *forward function shape* matches a Codable encode/decode shape (e.g., `(T) -> Data` / `(Data) -> T`), not arbitrary `(T) -> T` pairs.

## Plan-vs-actual deviation analysis

The v1.7 plan f-bullet predicted: "OrderedCollections / Algorithms / PropertyLawKit show non-zero suppression on `(Int, Int) -> Int` ops; ComplexModule may show small additional delta if any pairs slipped through cycle-2's textual match."

**Actual outcome:**
- **OrderedCollections −22**: ✓ but on round-trip, not commutativity / associativity.
- **Algorithms −1**: ✓ but on round-trip, not commutativity / associativity. (`(Double) -> Double` pair — stdlib type primary.)
- **PropertyLawKit 0**: ✗ — no stdlib-typed carriers in the surface.
- **ComplexModule −1**: ✓ but attributable to V1.6.1.1 (math-library op-name gate, post-cycle-3 patch), not V1.7.1.

The plan's projection over-indexed on op-class-mapped templates (commutativity / associativity) where the candidate-set design gates suppression to stdlib-operator-named ops only. The actual high-leverage path was through round-trip's broader `[codableRoundTrip]` candidate. Lesson for cycle-5 plan authoring: trace the predicted suppression path through both the bake-in's reach *and* the per-template candidate-set design — the candidate sets are the rate-limiter, not the conformance reach.

## Methodology gaps

**Bake-in introduces V1.5.2 design inheritance.** As discussed above, the bake-in extends V1.5.2's round-trip coverage candidate (`[codableRoundTrip]`) to stdlib types, which surfaces the inherited question of whether that candidate is correctly scoped. Cycle-5 priority #1 candidate.

**Cycle-3 baseline didn't include V1.6.1.1+.** The cycle-3 calibration capture (V1.6.2 commit `309c404`) preceded V1.6.1.1's math-library op-name gate. Cycle-4's −24 aggregate splits as −1 (V1.6.1.1) + −23 (V1.7.1). A clean cycle-3 re-capture between V1.6.1.4 and V1.7.1 would have isolated the V1.7.1 effect more cleanly. Methodology fix for cycle-5: re-baseline immediately before the cycle's structural change lands, not at release-tag.

**Possible-tier sampling on the post-v1.7 surface (326 across 4 corpora) still pending.** Carries forward from cycle-2+3. The 326 is now genuinely tractable for sampling — cycle-5 priority territory.

**`surfacedAt` plumbing still pending.** Carries forward from cycle-1.

**Single-runner triage carryover.** Same gap from cycles 1–3 carries forward unchanged. v1.7 ships zero new triage decisions (structural-only change).

## Cycle-5 priority list (in expected impact order)

1. **Round-trip template coverage-candidate tightening.** *(NEW from cycle 4.)* Re-examine `RoundTripTemplate.protocolCoverageVeto(...)`'s `[codableRoundTrip]` candidate. Two options: (a) tighten to fire only when the forward function shape matches `(T) -> Data` / `(Encodable) -> T` (true Codable round-trip surface); (b) split into two templates — `KitCodableRoundTripTemplate` (kit-blessed, narrow) and `UserDefinedInversePairTemplate` (no Codable veto, falls back to existing scoring). Option (b) is more invasive but more semantically precise. Option (a) is a 1-day tuning. Estimated empirical effect: most of the 23 V1.7.1 suppressions become surfaced again (the user-defined inverse pairs aren't really Codable round-trips), but with cleaner Codable-specific suppression remaining. Highest-leverage cycle-5 item if the cycle-4 over-suppression hypothesis bears out.

2. **Approximate-equality template arm for FP types.** *(Carried forward from cycle-2+3 priority #3.)* Real `KitFloatingPointTemplate` emitting `checkFloatingPointPropertyLaws(for: T.self, using: gen)` stubs. Synergy with v1.7's bake-in: now that `Float`/`Double` are in the bake-in with full conformance set, `KitFloatingPointTemplate` can dispatch to the right kit check function via curated lookup. ~1 day.

3. **Possible-tier sampling on the post-v1.7 surface (326 across 4 corpora).** *(Carried forward from cycle-2+3 priority #4.)* With cycle-5 priority #1 likely re-surfacing some cycle-4 suppressions, the resulting ~340 is genuinely tractable for a 20-30-decision sample. Closes the loop on cycle-1+2+3+4 hypotheses with empirical accept/reject data. Highest-leverage *empirical* cycle-5 item.

4. **`surfacedAt` plumbing.** *(Carried forward from cycle-1 priority #4.)* Unblocks PRD §17.2's time-to-adoption metric. ~half a day.

5. **Curated math-library op-name extension to round-trip / inverse-pair.** *(Generalization of V1.6.1.1's identity-element-only gate.)* The cycle-3 ComplexModule survivor (`(zero, rescaledDivide)`) is still on the floor at v1.7. Adding `rescaledDivide` to a curated math-library op set (alongside `pow`, `**`) and propagating to other algebraic templates would close it. Risk: false-positive suppression. Mitigation: keep the curated set short and well-justified. ~1 hour.

6. **SemanticIndex.** *(Carried forward; multi-cycle effort. PRD §20 v1.1+.)* Resolves `Int: Numeric` etc. authoritatively, lifting both the cycle-2 textual-only-coverage limit (which V1.7.1 partially closes via curation) and the cycle-3 stdlib-operator-name limit. Cycle-5 priority #1 (round-trip candidate tightening) is the higher-empirical-leverage near-term path; SemanticIndex remains the long-term proper fix.

## Summary

Cycle 4 shipped one structural rule: a curated 14-key stdlib-conformance bake-in on `ProtocolCoverageMap.inheritedTypesIndex(...)` (V1.7.1). The empirical effect was −23 of 350 surfaced suggestions (−6.6% V1.7.1-attributable; −24/−6.9% including V1.6.1.1's −1 ComplexModule identity-element from the v1.6.1 patch series), with 22 of 23 V1.7.1 suppressions on the round-trip template via `Int: Codable` / `UInt64: Codable` / `Double: Codable` reach.

The **most informative cycle-4 finding** is empirical and design-shaped: V1.7.1 worked exactly as designed (extending V1.5.2's reach to stdlib carriers), and that surfaced an inherited V1.5.2 design question — whether `RoundTripTemplate`'s `[codableRoundTrip]` veto candidate is the correct coverage signal for stdlib-typed user-defined inverse pairs (e.g., `minimumCapacity(forScale:) ↔ scale(forCapacity:)`). This is the cycle-5 priority #1 candidate.

The cumulative trajectory across cycles 1–4 is the headline result: **1167 → 326 (−72.1%)** over three calibration cycles with four mutually-exclusive structural mechanisms. The remaining 326-suggestion surface is now narrow enough that cycle-5's Possible-tier sampling triage is genuinely tractable; cycle-5 priority #3 sizes that work as a 20-30-decision empirical pass.

Cycle 5 has a concrete priority list with one ~1-day empirical tuning item (round-trip candidate tightening, the cycle-4 design-question follow-up), one ~1-day FP-template-arm item (cycle-3 carryover), and a half-day surfacedAt plumbing item. After cycle 5, the §19 acceptance-rate target should be measurable on a meaningfully-narrowed surface with clean V1.7.1 attribution.
