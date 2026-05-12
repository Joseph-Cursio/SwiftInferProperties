# v1.51 Calibration Cycle 48 — Findings (first non-zero end-to-end-from-indexer measurement)

Captured: 2026-05-12. swift-infer at v1.51 (post-V1.51.F). The forty-eighth execution of PRD §17.3's empirical-tuning loop and the **second full-coverage verify measurement** — measures the impact of v1.51's three mechanical fixes (A: bare→qualified `Complex` canonicalization; B: dual-style curated pair expansion; C: monotonicity-on-Double routing flip) plus the Layer-2(a) blind-spot guard (D: always-on E2E indexer→verify test).

## Headline

**Full-surface measured-execution: 22/109 = 20.2% (vs cycle-47's 0/109 = 0.0%).** All 22 lie in `measured-error` (11 build-failed + 11 parse-error); zero picks reached `.bothPass` / `.defaultFails` / `.edgeCaseAdvisory`. The 22 picks now reach `swift build` — V1.51.A canonicalization unblocks the 20 ComplexModule picks at the carrier-resolution layer; V1.51.C routing flip unblocks the 2 monotonicity-on-Double picks at the template-routing layer. The remaining 87 picks (87/109 = 79.8%) are still `architectural-coverage-pending`, dominated by OrderedCollections + swift-algorithms generic types that v1.52+ needs to handle.

**This is a real measurement-tooling gain (22-pick shift), but cycle-48 doesn't produce a per-pick agreement-rate signal** — none of the 22 measured picks landed in the outcome categories cycle-46's predictions used. Cycle-48 instead surfaces a *new* gap below the cycle-47 one: **call-expression-shape mismatches** between the resolver's `<TypeQualifier>.<funcName>` output and real Swift call syntax (operator names, free functions promoted to type namespaces, etc.).

## What v1.51's three mechanical fixes accomplished

| Fix | Picks unblocked | Picks reaching swift build | Picks reaching `.bothPass`/`.defaultFails` |
|---|---:|---:|---:|
| V1.51.A — Complex→Complex<Double> canonicalization | 20 | 20 | 0 (all measured-error) |
| V1.51.B — Dual-style curated pair expansion | 0 effective | 0 | 0 (the OC dual-style picks still fail at carrier resolution before the curated lookup fires — see §"Why V1.51.B's expansion didn't surface in cycle-48") |
| V1.51.C — Monotonicity-on-Double routing flip | 2 | 2 | 0 (1 build-failed + 1 parse-error) |
| **Total** | **22** | **22** | **0** |

V1.51.A and V1.51.C work as designed: they close the cycle-47 routing/resolution gaps for the picks where the rest of the pipeline can handle the resulting bound carrier. V1.51.B works as designed at the unit-test level (V1_51DualStyleExpansionTests pins it) but doesn't surface in cycle-48 measurements because all of cycle-27's dual-style picks have OC generic carriers (OrderedSet.UnorderedView, OrderedDictionary, etc.) that fail at the *carrier* layer before V1.51.B's pair-lookup runs.

## Why V1.51.B's expansion didn't surface in cycle-48

Cycle-27's 22 dual-style-consistency picks all live on OrderedCollections internal/generic types. The carrier resolution layer (V1.47.F) rejects these before the pair resolver runs:

- `OrderedSet` (17 picks): bare name, no canonical binding in GenericBindingResolver. V1.51.A added a Complex entry; no OrderedSet entry. → `.unsupportedCarrier`.
- `OrderedSet.UnorderedView` (8 picks): nested generic, also no binding.
- `OrderedDictionary` (variants) (~5 picks): same.

So V1.51.B's curated-pair expansion is *latent* — when the v1.52+ work closes the carrier-resolution gap for OC types, V1.51.B's expanded pair list will kick in and unblock these 22 picks. **V1.51.B is a forward-looking fix; cycle-48 cannot validate it yet.**

## Cycle-48 measured-error breakdown (the new gap)

The 22 picks that now reach swift build split:

**11 build-failed**: stub source doesn't compile.
- 4 round-trip CM picks (`/(z:w:)`, `-(z:w:)`, `*(z:w:)`, `+(z:w:)` — all operator-named functions): the resolver builds `Complex./` as the call expression but Swift requires `/(_:_:)` to be referenced as `(/)` or `(/)(z, w)`, not as a `.`-accessed method.
- 2 monotonicity picks: similar shape issue (the V1.51.C fixture monotonicity × Double picks reference `log(onePlus:)` which the resolver builds as `Double.log` but `log` is a free function on `ElementaryFunctions`, not a static on `Double`).
- 3 commutativity + 2 associativity picks: same operator/free-function shape gaps.

**11 parse-error (subprocess exit 6, SIGABRT)**: stub compiles but the runtime call traps.
- 4 round-trip CM picks (`exp/log`, `sinh/asinh`, `tanh/atanh`, `tan/atan`): the verifier subprocess crashes during the property check. Likely cause: the synthesized call `Complex.exp(value)` resolves to a different shape at runtime than the property expects, hitting a precondition or a divide-by-zero or NaN trap.
- 3 commutativity + 4 associativity picks: same parse-error class on Complex `_relaxedMul`, `-` operator, `+` operator.

**Both classes are call-expression-shape gaps in the resolver**. v1.52's call-expression resolver should close them.

## Cycle-46 predictions vs cycle-48 actuals (32-pick sample subset)

Cycles 42-46 predicted per-pick outcomes (`.bothPass` / `.defaultFails`) on the basis of synthetic-shape-class agreement. The cycle-48 actuals don't intersect with that outcome space — all 8 of the 32-pick picks that reach swift build landed in `.measured-error`. So:

- **Predicted `.bothPass` picks**: 21 in the 32-pick sample (#1, #3-#6, #10-#17, #18-#20, #24, #26, #28-#32). 4 of these reached swift build (the 4 CM round-trip picks #3-#6); all landed in `.measured-error (parse-error)`. The remaining 17 are still `architectural-coverage-pending`.
- **Predicted `.defaultFails` picks**: 8 in the 32-pick sample (#2, #7-#9, #22, #23, #25, #27). 1 reached swift build (#27, `Complex.-(z:w:)` associativity), landed in `.measured-error (build-failed)`. The remaining 7 are still `architectural-coverage-pending`.
- **Predicted `.bothPass` picks (uncertain — cycle-27 verdict was "unknown")**: 3 (#10, #11, #21). All 3 are `architectural-coverage-pending`.

**Per-pick agreement-rate signal: not computable from cycle-48 evidence.** The closest framing: of 8 cycle-46-predicted picks that reached swift build in cycle-48, 0 landed in their predicted outcome category. **The synthetic-vs-real bridge has its own gap layer below the cycle-47 one** — cycle-48 establishes that closing carrier-resolution doesn't get you to `.bothPass`-class outcomes; the call-expression-shape gap is the next load-bearing fix.

## What cycle-48 establishes

1. **The cycle-47 carrier-resolution gap is real and partially closed.** v1.51.A + v1.51.C are mechanical, verified fixes that move 22 picks past the cycle-47 wall. The 87 remaining picks are mostly OC + Algo generic types that need TypeShape-driven instantiation.

2. **A new gap surfaces: call-expression shape.** Operator-named functions (`/`, `-`, `*`, `+` on Complex) and free functions promoted to type namespaces (`exp`, `log`, `sin`, `cos` on `Complex`) don't fit the resolver's `<Type>.<funcName>` template. 11 of 22 measured-error picks build-failed because of this; the other 11 likely parse-error from a runtime version of the same shape mismatch.

3. **Cycle-46's "100% per-pick agreement" was synthetic-only.** Cycle-48's actuals don't validate or invalidate the synthetic numbers — they measure a different thing. **The capability claim (cycles 42-46) and the measurement-tooling claim (cycle-47 onward) are independent.** Until v1.52+ closes the call-expression-shape gap, real-indexer end-to-end agreement is unmeasurable.

4. **V1.51.D's blind-spot guard works.** The new V1_51EndToEndFromIndexTests catches the synthetic↔real-indexer bridge regression at unit-test speed (3 tests pass in ~0.001 seconds). If v1.52+ accidentally reverts V1.51.A's canonicalization, the guard fires immediately.

## v1.52+ roadmap

Per cycle-48 evidence, in priority order:

1. **Call-expression-shape resolver** (~v1.52). Extend the resolver to handle:
   - Operator-named functions: `+(z:w:)` → `(+)(a, b)` free-function call form.
   - Free functions promoted to type namespace: `exp(_:)` indexed under `Complex` carrier → the call should be `exp(value)` (free function) not `Complex.exp(value)`.
   - Static methods (the current shape, kept): `Int.binomial(n:k:)` → `Int.binomial(n, k)`.

   This closes most of the 11 build-failed picks. Some of the 11 parse-error picks may also resolve (if exit 6 comes from a runtime shape mismatch the static fix removes).

2. **GenericBindingResolver alignment with indexer carrier-names** (~v1.52). The cycle-44 plan posited `Base.Index → Int` bindings; the real indexer produces carriers like `ChunkedByCollection`, `_Bucket`, `OrderedSet`. Expand the resolver to handle the actual indexer-produced names. Closes the 3 chunked-Index picks + likely 10+ more.

3. **TypeShape-driven generic instantiation** (~v1.52-v1.53). For `OrderedSet`, `OrderedDictionary`, etc., use the indexed TypeShape's `Element` placeholder to choose a canonical Element type (e.g., `Int`). Closes 60+ OC picks.

4. **Subprocess error stream capture** (~v1.52). The current parse-error detail says "stdout (last 5 lines, pipe-joined): " — empty stdout suggests the verifier subprocess crashed before printing anything. Capturing stderr would surface the actual trap reason. Small infrastructure improvement; useful for diagnosing exit-6 parse-errors.

5. **Phase 2 accept-flow integration** (~v1.53+) — wait for cycle-49+ to confirm a non-trivial fraction reaches `.bothPass` / `.defaultFails`.

## Captured artifacts

- Cycle-48 survey JSON: `docs/calibration-cycle-48-data/full-surface-outcomes.json` (sorted by identityHash; surveyVersion: 1; 109 entries).
- Aggregate summary: `docs/calibration-cycle-48-data/full-surface-summary.md` (template × failure-reason cross-tab + 32-pick subset comparison + methodology).
- V1.51.A canonicalization, V1.51.B pair expansion, V1.51.C routing flip — committed in the V1.51.A-D commit.
- V1.51.D blind-spot guard — `Tests/SwiftInferCLITests/V1_51EndToEndFromIndexTests.swift`.

## Open thread carried into v1.52

**The synthetic-vs-real measurement-category mismatch.** Cycles 42-46 reported synthetic-shape-class agreement at 100%; cycle-48 establishes that the bridge between synthetic and real has at least two gap layers (carrier-resolution, now partially closed; call-expression-shape, now visible). The honest framing for v1.52+ is: real-indexer per-pick agreement-rate is **uncomputable** until at least one cycle reaches `.bothPass` / `.defaultFails` on a non-zero subset of the cycle-27 picks. v1.52's call-expression-shape resolver should produce the first measurable subset.
