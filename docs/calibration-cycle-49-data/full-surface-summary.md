# Cycle-49 full-surface measurement summary

Captured: 2026-05-13 via `swift-infer verify --all-from-index --index-path fixtures/cycle27-surface/.swiftinfer/index.json --max-parallel 4`. swift-infer at v1.52 (post-V1.52.D). Wall-clock: ~4 minutes.

## Aggregate

| Classification | Cycle-47 (v1.50) | Cycle-48 (v1.51) | Cycle-49 (v1.52) | Δ vs c48 |
|---|---:|---:|---:|---:|
| measured-bothPass | 0 | 0 | 0 | 0 |
| measured-edgeCaseAdvisory | 0 | 0 | 0 | 0 |
| measured-defaultFails | 0 | 0 | 0 | 0 |
| measured-error | 0 | 22 | 22 | 0 |
| architectural-coverage-pending | 109 | 87 | 87 | 0 |
| **Total** | **109** | **109** | **109** | — |

**Zero net change at the aggregate level.** The 22/109 = 20.2% measured-execution fraction holds. But the *composition* of the 22 changed substantially, and V1.52.B's stderr capture revealed that the cycle-48 framing of the parse-error class was wrong.

## Per-template breakdown

| Template | Surface | pending | build-failed | parse-error (dyld) |
|---|---:|---:|---:|---:|
| round-trip | 12 | 4 | 8 | 0 |
| idempotence | 12 | 12 | 0 | 0 |
| monotonicity | 29 | 27 | 0 | 2 |
| commutativity | 17 | 11 | 1 | 5 |
| associativity | 17 | 11 | 1 | 5 |
| dual-style-consistency | 22 | 22 | 0 | 0 |
| **Total** | **109** | **87** | **10** | **12** |

## Cycle-48 → cycle-49 transitions (22 measured picks)

The diff is more interesting than the aggregate:

| c48 → c49 | Count | What it means |
|---|---:|---|
| build → build | 2 | unchanged build failures (Complex `_relaxedMul` × commutativity + associativity; not operator-named, not EF-surface — V1.52.A's classifier left them alone) |
| build → parse-dyld | 6 | **V1.52.A operator-paren closed the compile**. `Complex.-`, `Complex./`, `Double.log` no longer compile-fail — but the resulting binary still hits `libTesting.dylib` at startup |
| parse → build | 8 | **V1.52.A free-function form regressed compile**. All 8 are Complex round-trip trig/hyperbolic (`exp`, `log`, `sin`, `cos`, `tan`, `sinh`, `cosh`, `tanh`); the resolver now emits bare `exp(value)` but `_Numerics`-global overloads aren't in scope from `ComplexModule` alone |
| parse → parse-dyld | 6 | unchanged runtime failure, now correctly attributed to `libTesting.dylib` via V1.52.B stderr capture |

**The real cycle-48 finding (revealed by V1.52.B):** the 11 cycle-48 parse-errors were *all* `dyld[XXXX]: Library not loaded: @rpath/libTesting.dylib` — a runtime linking issue where the verifier subprocess can't resolve the swift-testing library at startup. The cycle-48 findings doc's speculation that exit 6 reflected a call-expression-shape mismatch was **wrong**. The dyld issue would have manifested the same way regardless of whether the synthesized call was `Complex.exp(value)` or `exp(value)`.

## V1.52 workstream impact, per cycle-49 evidence

| Workstream | Designed to close | Actual cycle-49 effect | Verdict |
|---|---|---|---|
| V1.52.A operator-paren | 4 operator-named round-trip CM build-failures + 7 operator + free-fn build-failures (5 commutativity/associativity, 2 monotonicity) | 6 cycle-48 build-failures now reach runtime (operator-paren form compiles) | **✓ Works as designed for operators** |
| V1.52.A free-function | 4 round-trip CM parse-errors (cycle-48 speculation) | 8 round-trip CM picks regressed compile (bare `exp` not in scope without `Real`/`_Numerics` import) | **✗ Regression** — needs revert or import-shim |
| V1.52.B stderr capture | Diagnostic visibility for the 11 parse-errors | Surfaced `libTesting.dylib` runtime-link issue immediately. Cycle-48's speculation was wrong | **✓ Works as designed** — primary purpose fulfilled |
| V1.52.C `ChunkedByCollection.Index` + OrderedSet.Index bindings | 3 chunked-Index picks (cycle-46 `.defaultFails` prediction) + 10+ Index-aliased picks | Zero picks moved. Indexer emits bare `ChunkedByCollection`, not `ChunkedByCollection.Index` — keys are wrong | **✗ Latent (wrong key format)** — like V1.51.B, but a design error this cycle should have caught earlier |

## 32-pick sample subset (cycles 41-46 stratified)

Per-pick agreement-rate **still uncomputable** — 22 measured picks, all `.measured-error`. The synthetic-vs-real gap stays at two layers (call-expression shape + libTesting.dylib runtime), with v1.52 closing half of one layer (operator-paren) and introducing one regression (free-function).

**Status by row** (showing only picks that changed since cycle-48):
- #3 (0x4949 `exp/log`): c48 parse → c49 build (V1.52.A free-fn regressed compile)
- #4 (0x51D5 `sinh/asinh`): c48 parse → c49 build (same)
- #5 (0xC6E1 `tanh/atanh`): c48 parse → c49 build (same)
- #6 (0x22C4 `tan/atan`): c48 parse → c49 build (same)
- #18 (0xA9AD `log(onePlus:)` × monotonicity): c48 build → c49 parse-dyld (V1.52.A operator/free-fn classifier fixed; runtime dyld fail surfaces)
- #24 (0x7748 commutativity Complex `+`): c48 parse → c49 parse-dyld (stderr revealed dyld)
- #26 (0x60A0 associativity Complex `+`): c48 parse → c49 parse-dyld (same)
- #27 (0xB8DE associativity Complex `-`): c48 build → c49 parse-dyld (V1.52.A operator-paren fixed; runtime dyld surfaces)

## What cycle-49 establishes

1. **The new gap below cycle-48's is now visible: runtime library linking.** All 12 cycle-49 parse-errors (and the 6 cycle-48-build-failed-now-reaching-runtime picks) hit the same `dyld: Library not loaded: @rpath/libTesting.dylib` error. This is a workdir-synthesis issue — the verifier's `Package.swift` declares a `.testTarget` (or imports `Testing`) but the resulting binary's `@rpath` doesn't include the swift-testing library's actual install location.

2. **V1.52.A's call-expression classifier is half-right.** Operator-paren form is correct and closes 6 builds. Free-function form is wrong: swift-numerics's global `exp<T: ElementaryFunctions>` overloads aren't reachable from a workdir that only imports `ComplexModule` — they live in `Real`/`_Numerics`. v1.53 must either revert the free-function classification or add the right import to the stub preamble.

3. **V1.52.B was the cycle's biggest win.** Stderr capture immediately falsified cycle-48's call-expression-shape hypothesis for the parse-error class and revealed the real runtime-linking issue. Without V1.52.B, v1.53 would have continued chasing the wrong gap.

4. **V1.52.C's bindings are dead code.** Keyed on `<Type>.Index` but the indexer outputs bare `<Type>`. Easy fix in v1.53 — but it's a methodology lesson: changes to forward-looking binding tables should be validated against a sample real-indexer entry before shipping (V1.51.B had the same latent-on-cycle issue).

5. **Cycle-48's call-expression-shape framing was structurally wrong.** The 11 parse-errors weren't a shape issue. The 11 build-failures *did* split into operator-named (V1.52.A.operator closed them) + non-shape causes. v1.52's plan was overweighted on call-expression-shape; the new evidence rebalances the v1.53+ roadmap toward the linking issue.

## v1.53+ priorities (per cycle-49 evidence)

In order of expected impact:

1. **v1.53 — `libTesting.dylib` runtime-link fix.** Investigate the verifier workdir's link strategy. Possible fixes: (a) link the verifier as a regular executable that doesn't depend on `Testing`; (b) add `DYLD_LIBRARY_PATH` to the subprocess env pointing to the toolchain's swift-testing location; (c) switch the property-check loop from Testing to XCTest or a hand-rolled trial loop. **Closes all 12 parse-dyld picks + the 6 V1.52.A-newly-compiling picks** (they'd reach the property check, producing `.bothPass`/`.defaultFails`/`.edgeCaseAdvisory`).

2. **v1.53 — V1.52.A free-function regression revert (or fix the import).** Either: (a) remove the `.freeFunction` case from `CallExpressionShape.classify` and revert to `.staticMethod` for the EF surface; (b) add `import Real` / `import _Numerics` to the V1.49.A preamble for Complex carriers. (a) is simpler; (b) preserves the cycle-48 hypothesis that the free-function form is canonical. **Closes the 8 cycle-49 regressed round-trip Complex builds.**

3. **v1.53 — V1.52.C carrier-name key fix.** Change V1.52.C entries from `ChunkedByCollection.Index` to `ChunkedByCollection` (binding to a TypeShape-driven Index, or to `Int` as a placeholder). Closes the 3 chunked-Index `.defaultFails` predictions.

4. **v1.53 — TypeShape-driven generic instantiation** for OC types (defer-target carried from v1.52 plan). 60+ OC picks. Largest remaining single category.

5. **v1.54+ — Phase 2 accept-flow integration** — gated on v1.53 producing the first non-zero `.bothPass`/`.defaultFails` subset (which the `libTesting.dylib` fix should unlock for ~16+ picks).

## Methodology notes

- Wall-clock: 3:50 (4 min). Lower than cycle-48's reported ~6 min — possibly cache warmer on the second run, or `--max-parallel 4` more efficient given the 22 picks reaching `swift build` is unchanged from cycle-48.
- The libTesting.dylib error is consistent across all dyld-fail picks — same trap reason, same dyld search path. This is workdir-synthesis-side, not pick-side.
- V1.52.B's stderr capture (last 5 lines, 200-char per-line truncation) was sufficient to identify the cause on first read. The truncation cap left the dyld error fully visible.
- V1.52.A's `_relaxedMul` regression check (unit-test V1.52.D.1's `complexCarrierWithNonEFNameStaysStatic`) **held in cycle-49 measurement** — `Complex._relaxedMul` builds are still build-failed at runtime/compile for a non-shape reason (likely the same shape gap the test handles correctly).
