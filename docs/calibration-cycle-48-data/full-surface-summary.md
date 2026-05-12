# Cycle-48 full-surface measurement summary

Captured: 2026-05-12 via `swift-infer verify --all-from-index --index-path fixtures/cycle27-surface/.swiftinfer/index.json --max-parallel 4`. swift-infer at v1.51 (post-V1.51.D).

## Aggregate

| Classification | Cycle-47 (v1.50) | Cycle-48 (v1.51) | Δ |
|---|---:|---:|---:|
| measured-bothPass | 0 | 0 | 0 |
| measured-edgeCaseAdvisory | 0 | 0 | 0 |
| measured-defaultFails | 0 | 0 | 0 |
| measured-error | 0 | 22 | **+22** |
| architectural-coverage-pending | 109 | 87 | **−22** |
| **Total** | **109** | **109** | — |

**V1.51 mechanical fixes (A+B+C) closed 22 picks from `architectural-coverage-pending` to `measured-error`**. The picks now reach `swift build` (carrier-name resolution succeeds) but the stub source has runtime/compile issues — a *new* gap surface, smaller than the cycle-47 gap but still load-bearing.

## Per-template breakdown

| Template | Surface count | architectural-coverage-pending | measured-error |
|---|---:|---:|---:|
| round-trip | 12 | 4 | 8 |
| idempotence | 12 | 12 | 0 |
| monotonicity | 29 | 27 | 2 |
| commutativity | 17 | 11 | 6 |
| associativity | 17 | 11 | 6 |
| dual-style-consistency | 22 | 22 | 0 |
| **Total** | **109** | **87** | **22** |

**Picks that reach swift build (the 22)**: dominated by ComplexModule (Complex<Double> after V1.51.A canonicalization — 20 picks) + the 2 monotonicity-on-Double picks unblocked by V1.51.C routing flip.

**Picks still architectural-coverage-pending (the 87)**: dominated by OrderedCollections types (OrderedSet, OrderedDictionary, _HashTable, _UnsafeHashTable, OrderedDictionary.Elements + SubSequence variants) and swift-algorithms types (ChunkedByCollection, EvenlyChunkedCollection, CombinationsSequence). These all need TypeShape-driven generic instantiation — v1.52+ work.

## measured-error breakdown (the 22 picks reaching swift build)

| Reason | Count | Per-template distribution |
|---|---:|---|
| build-failed (exit=1) | 11 | round-trip 4, monotonicity 2, commutativity 3, associativity 2 |
| parse-error (subprocess exit 6, empty stdout) | 11 | round-trip 4, commutativity 3, associativity 4 |

**Build failures**: dominated by operator-named functions where the resolver builds invalid Swift call expressions. Examples:
- `Complex./` for `/(z:w:)` (the resolver concatenates `<TypeQualifier>.<funcName>` but `/` isn't a valid `.` accessor — Swift requires `Complex./` to be written as `(/)` or as a free function `(/)(a, b)`).
- `Complex.-` for `-(z:w:)` — same issue.

**Parse-errors (exit 6)**: SIGABRT from the verifier subprocess. The stub source compiles but the property check traps at runtime. Likely causes:
- Calling `Complex.exp(value)` — `exp` is a free function on `ElementaryFunctions`, not a static method on `Complex`. The synthesized call `Complex.exp(value)` may resolve to a different shape than expected, causing a runtime mismatch.
- Calling `Complex._relaxedMul(a, b)` — relaxed multiplication on Complex involves NaN handling that may trip Swift Testing's preconditions or trap on invalid Complex states.

Both classes are **call-expression-shape gaps in the resolver** — the resolver builds `<Type>.<func>` for all picks but real Swift call expressions for these functions need different shapes (free-function calls, operator references, etc.). **v1.52+ scope**.

## Cycle-27 sample subset (the 32-pick stratified sample)

For comparison against cycles 42-46's synthetic-shape predictions, here's the v1.51 outcome for each of the 32 stratified picks:

| # | Identity prefix | Template | Cycle-27 verdict | Cycle-46 predicted | Cycle-48 measured | Status |
|---:|---|---|---|---|---|---|
| 1 | 0xBC43 | round-trip | accept | .bothPass | architectural (carrier `_HashTable.UnsafeHandle`) | unmeasured |
| 2 | 0xBAD0 | round-trip | reject | .defaultFails (V1.49.C secondaryFunctionName) | architectural (carrier `OrderedSet`) | unmeasured |
| 3 | 0x4949 | round-trip | accept | .bothPass | **measured-error (parse-error)** | shape gap |
| 4 | 0x51D5 | round-trip | accept | .bothPass | **measured-error (parse-error)** | shape gap |
| 5 | 0xC6E1 | round-trip | accept | .bothPass | **measured-error (parse-error)** | shape gap |
| 6 | 0x22C4 | round-trip | accept | .bothPass | **measured-error (parse-error)** | shape gap |
| 7-9 | 0x3543, 0x40C8, 0xED77 | idempotence | reject | .defaultFails (GenericBindingResolver Base.Index → Int) | architectural (carrier `ChunkedByCollection` not bound) | unmeasured — V1.51 GenericBindingResolver keys don't match indexer-produced carriers |
| 10 | 0xE54F | idempotence | unknown | .bothPass (V1.49.B memberwise) | architectural (carrier `_UnsafeHashTable`) | unmeasured |
| 11 | 0x840A | idempotence | unknown | .bothPass | architectural (carrier `ViolationFormatter`) | unmeasured |
| 12-17 | various | idempotence-lifted | accept | .bothPass | architectural (OC carriers) | unmeasured |
| 18 | 0xA9AD | monotonicity | accept | .bothPass | **measured-error (build-failed)** | shape gap |
| 19-21 | various | monotonicity | mixed | various | architectural | unmeasured |
| 22-23 | 0xB56C, 0xFCB1 | commutativity | reject | .defaultFails | architectural | unmeasured |
| 24 | 0x7748 | commutativity | accept | .bothPass | **measured-error (parse-error)** | shape gap |
| 25 | 0x518A | associativity | reject | .defaultFails | architectural | unmeasured |
| 26 | 0x60A0 | associativity | accept | .bothPass | **measured-error (parse-error)** | shape gap |
| 27 | 0xB8DE | associativity | reject | .defaultFails | **measured-error (build-failed)** | shape gap |
| 28-32 | various | dual-style-consistency | accept | .bothPass | architectural (OC carriers) | unmeasured |

**32-pick sample outcome distribution**: 8 measured-error + 24 architectural-coverage-pending. **Per-pick agreement-rate cannot be computed** — no picks reached `.bothPass` / `.defaultFails` / `.edgeCaseAdvisory`, the categories cycle-46's predictions used.

## What cycle-48 establishes

1. **The cycle-47 measurement-tooling gap is real and partially closed.** v1.51.A's `Complex` canonicalization moved 20 picks past carrier resolution. v1.51.C's routing flip closed 2 monotonicity-on-Double picks. Both are mechanical fixes, both verified.

2. **A new gap surface emerges**: call-expression shape. The resolver builds `<TypeQualifier>.<funcName>` for all picks but real Swift requires different shapes for operator-named functions (`-`, `/`, `*`), free functions promoted to the carrier's namespace (`exp`, `log`, `sin`, `cos`), and other special cases. This was *hidden* behind the cycle-47 carrier-resolution gap; v1.51 surfaces it.

3. **Cycle-46's synthetic-shape predictions don't translate to real-indexer measurements**, even after v1.51's fixes. The cycle-46 prediction for #3 (exp/log) was `.bothPass`; the real measurement is `.measured-error` (parse-error exit 6). This isn't a *disagreement* (both are valid outcomes of their respective measurement methodologies) — it's a *category mismatch* (synthetic measurement says ".bothPass on hand-crafted Complex<Double> input"; real measurement says "the verifier subprocess crashed on real Complex.exp call"). They measure different things.

4. **The 32-pick sample is now under-determined**: cycle-46's predictions were for outcomes (`.bothPass` / `.defaultFails`); cycle-48's actual outcomes are all `.measured-error` / `.architectural-coverage-pending`. There's no overlap in the outcome space, so the per-pick agreement-rate signal that cycles 42-46 reported (100% across 30 picks) becomes a synthetic-only number going forward — until v1.52+ closes the call-expression-shape gap.

## v1.52+ priorities (per cycle-48 evidence)

In order of expected impact:

1. **v1.52 — Call-expression shape resolver**: extend `RoundTripPairResolver` (and the inlined v1.47.F mirror) with operator-named-function handling (`/(z:w:)` → `(/)(a, b)` as a free function, etc.) and free-function handling (`exp(_:)` → bare `exp(value)` not `Complex.exp(value)`). Closes most of the 11 build-failed picks.

2. **v1.52 — Resolver→subprocess shape contract**: figure out what's causing exit 6 on real-package calls (likely Swift Testing precondition or signal-trap inside the verifier binary). The 11 parse-error picks share this gap. May require capturing more stderr in the survey runner.

3. **v1.52 — Indexer carrier-name format alignment**: the GenericBindingResolver expects `Base.Index` but the indexer outputs `ChunkedByCollection`. Either expand the resolver keys to the actual indexer-produced types, or change the indexer to emit the associated-type-path form. Closes most of the 87 architectural-coverage-pending picks.

4. **v1.52+ — TypeShape-driven generic instantiation**: for `OrderedSet`, `OrderedDictionary`, etc., the strategist needs to pick a canonical Element type. This is the big architectural step.

5. **v1.53+ — Phase 2 accept-flow integration** once a meaningful subset of the surface is in `measured-bothPass` / `measured-defaultFails`.

## Methodology note

Survey wall-clock: ~109 verifications × variable cost / 4-parallel = **~6 minutes total** for cycle-48 (vs cycle-47's ~3 min — the doubled time reflects the 22 picks now actually running `swift build`).

Per-pick cost when reaching swift build: ~10-15s cold (SwiftPM resolve + dependency compile of the verifier workdir's deps). Parallel runs at `--max-parallel 4` saturate disk + network.
