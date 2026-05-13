# v1.52 Calibration Cycle 49 — Findings (zero net headline, but stderr capture falsified the cycle-48 framing)

Captured: 2026-05-13. swift-infer at v1.52 (post-V1.52.F). The forty-ninth execution of PRD §17.3's empirical-tuning loop. Cycle-49 measures the impact of v1.52's three workstreams (A: call-expression-shape resolver; B: subprocess stderr capture; C: `GenericBindingResolver` chunked-Index expansion) against the cycle-27 fixture.

## Headline

**Full-surface measured-execution: 22/109 = 20.2% — unchanged from cycle-48's 22/109.** Zero net movement at the aggregate level.

**But the cycle-49 composition is materially different**, and V1.52.B's stderr capture revealed the cycle-48 framing of the parse-error class was wrong. Cycle-49's substantive findings:

1. **V1.52.A's operator-paren form works** — 6 cycle-48 build-failures (operator-named Complex picks: `+`, `-`, `*`, `/`, plus 2 monotonicity-on-Double picks) now compile and reach runtime.
2. **V1.52.A's free-function form regressed** — 8 cycle-48 parse-error picks (round-trip Complex `exp/log`, `sin/asin`, `cos/acos`, `tan/atan`, `sinh/asinh`, `cosh/acosh`, `tanh/atanh`) now compile-fail because the bare `exp(value)` form isn't in scope from `ComplexModule` alone (swift-numerics's global EF overloads live in `Real`/`_Numerics`).
3. **V1.52.B revealed the real cause of the 11 cycle-48 parse-errors**: `dyld[XXXX]: Library not loaded: @rpath/libTesting.dylib`. The verifier subprocess can't resolve swift-testing's runtime library at startup. Not a call-expression-shape issue at all.
4. **V1.52.C's chunked-Index bindings are latent** — keyed on `<Type>.Index` but the indexer outputs bare `<Type>`. Zero picks moved.

**Net effect**: V1.52.A produced ~zero net pick movement (closed 6, regressed 8). V1.52.B was the cycle's biggest win — it falsified the cycle-48 hypothesis and surfaced the new load-bearing gap (`libTesting.dylib` runtime linking). V1.52.C is latent and needs a v1.53 fix.

## Cycle-48 → cycle-49 transitions

Of the 22 measured picks:

| Transition | Count | Interpretation |
|---|---:|---|
| build → build | 2 | `Complex._relaxedMul` (commutativity + associativity) — V1.52.A correctly left these as `.staticMethod`; they still build-fail for a non-shape reason (likely the `_relaxedMul` member-vs-free disambiguation) |
| build → parse-dyld | 6 | V1.52.A operator-paren closed the compile; binary now hits libTesting.dylib at runtime |
| parse → build | 8 | V1.52.A free-function regressed compile (all 8 are round-trip Complex EF-surface picks) |
| parse → parse-dyld | 6 | Unchanged runtime failure; V1.52.B revealed the cause |

## What V1.52.B's stderr capture surfaced

Every cycle-49 parse-error pick (12 of them) shows the same shape on stderr:

```
dyld[<PID>]: Library not loaded: @rpath/libTesting.dylib
  Referenced from: <UUID> <workdir>/.build/arm64-apple-macosx/debug/SwiftInferVerifier
  Reason: tried: '/usr/lib/swift/libTesting.dylib' (no such file, not in dyld cache),
          '/System/Volumes/Preboot/Cryptexes/OS/usr/lib/swift/libTesting.dylib' (no such file),
          '/Users/.../...' (no such file)…
```

The verifier binary's `@rpath` doesn't include the swift-testing toolchain location. swift-testing is bundled with the Swift toolchain but isn't installed in `/usr/lib/swift/` on this macOS host — it lives in the Xcode-managed toolchain bundle. The verifier workdir's `Package.swift` declares the swift-testing dependency, so `swift build` resolves and links against it; but at runtime the dynamic linker can't find the library because the rpath baked into the binary points to a path that doesn't resolve in the current environment.

**This is a workdir-synthesis issue, not a per-pick issue.** All 12 dyld-fail picks share the same trap; the cause is independent of which template / carrier / function the synthesized stub exercises.

## Cycle-46 predictions vs cycle-49 actuals

Per-pick agreement-rate **still uncomputable** — all 22 measured picks remain `.measured-error`. Of the 8 cycle-46-predicted picks that reach swift build in cycle-49, all land in `.measured-error`. Synthetic-vs-real per-pick agreement is unmeasurable until v1.53 closes the libTesting.dylib gap.

## What cycle-49 establishes

1. **The cycle-48 call-expression-shape framing was structurally wrong for parse-error.** Parse-errors weren't a shape issue — they're a runtime linking issue. V1.52.A's free-function form attempted to fix something that wasn't the cause.

2. **V1.52.A's operator-paren classification is correct.** 6 build-failures closed. The 4-case (`/`, `-`, `*`, `+`) operator-named functions on Complex now compile via the `(/)`, `(-)`, etc. paren-form. This is the cycle's single most-real architectural win.

3. **V1.52.A's free-function classification needs to be reverted (or fixed at the import layer).** swift-numerics's global EF overloads live in `Real`/`_Numerics`, not `ComplexModule`. The bare `exp(value)` shape doesn't resolve from a workdir that imports only `ComplexModule`. Two v1.53 options:
   - **Revert**: drop the `.freeFunction` case for Complex/Double/Float carriers; restore the v1.51 `.staticMethod` shape. 8 picks return to "compile + runtime dyld fail" — which is forward progress once v1.53 closes the dyld issue.
   - **Fix import**: add `import Real` to the V1.49.A preamble for Complex/Double/Float carriers. Preserves v1.52's hypothesis but introduces a kit-side dependency.

   Revert is the lower-risk choice — cleaner, no preamble-shape change, the static `Complex.exp` form is canonical Swift call shape for the `static func exp` declared on `ElementaryFunctions`.

4. **V1.52.B is the cycle's most valuable workstream.** Without stderr capture, v1.53 would have continued chasing the wrong gap (call-expression shape) based on the cycle-48 misdiagnosis. The 20 LoC of stderr capture has higher diagnostic ROI than the 100+ LoC of V1.52.A's classifier.

5. **V1.52.C's bindings are latent.** Keyed on `ChunkedByCollection.Index` but indexer emits bare `ChunkedByCollection`. Pure-mechanical fix in v1.53 — change keys + add element-type binding. Closes the 3 chunked-Index picks cycle-46 predicted `.defaultFails`.

6. **Methodology lesson**: forward-looking binding-table changes (V1.51.B dual-style pairs; V1.52.C chunked-Index keys) should be validated against a real-indexer entry sample *before* shipping. Both V1.51.B and V1.52.C shipped latent and required a subsequent cycle to surface the key-format mismatch. v1.53 should adopt a "validate-binding-table-against-fixture-index" check pattern.

## v1.53+ roadmap (per cycle-49 evidence)

In priority order:

1. **v1.53 — `libTesting.dylib` runtime-link fix**. Highest-impact single fix. Investigate three approaches: (a) link the verifier as a non-Testing executable (drop `import Testing`, hand-roll the property-check loop with `XCTAssert`-style asserts or pure-Swift `precondition`); (b) inject `DYLD_FALLBACK_LIBRARY_PATH` into the subprocess env at run-time to point at the toolchain's swift-testing location; (c) emit explicit `@rpath` entries during workdir synthesis. (a) is the most robust. **Closes all 12 parse-dyld picks + the 6 V1.52.A-newly-compiling picks** (likely producing the first non-zero `.bothPass`/`.defaultFails` subset).

2. **v1.53 — V1.52.A free-function revert** (or import-shim fix). 8 cycle-49 build regressions on round-trip Complex EF-surface picks. The revert path is cleaner — restore `.staticMethod` for the EF surface. Per-pick: 8 picks return to "compile success + runtime dyld" — which becomes "compile success + property check" once (1) lands.

3. **v1.53 — V1.52.C carrier-name key fix**. Change keys from `ChunkedByCollection.Index` to `ChunkedByCollection` (with TypeShape-driven Element binding, or `Array<Int>` placeholder). Closes 3+ chunked-Index picks.

4. **v1.53 — TypeShape-driven generic instantiation** (deferred from v1.52 plan). For OC types — 60+ picks. The largest residual category. Substantial scope; may split across v1.53-v1.54.

5. **v1.53 — Methodology guard**: add a unit-test or fixture-level check that every entry in `GenericBindingResolver.curatedBindings` matches at least one carrier-name format the indexer actually produces (or is explicitly flagged as "future-format placeholder"). Prevents the V1.51.B + V1.52.C latent-key-format pattern from recurring.

6. **v1.54+ — Phase 2 accept-flow integration** — gated on v1.53 producing the first non-zero `.bothPass`/`.defaultFails` subset.

## Captured artifacts

- Cycle-49 survey JSON: `docs/calibration-cycle-49-data/full-surface-outcomes.json` (sorted by identityHash; surveyVersion: 1; 109 entries).
- Aggregate summary: `docs/calibration-cycle-49-data/full-surface-summary.md` (template × failure-reason cross-tab + transition table + workstream-impact summary + methodology).
- V1.52.A classifier, V1.52.B stderr capture, V1.52.C binding expansion — committed in the V1.52.A-D commits.
- V1.52.D unit tests — `Tests/SwiftInferCLITests/V1_52CallExpressionShapeTests.swift`.

## Open threads carried into v1.53

1. **The libTesting.dylib runtime-link issue.** Not yet diagnosed beyond the dyld error message. v1.53 must investigate whether the toolchain's swift-testing install location is detectable at workdir-synthesis time, or whether the verifier should drop the Testing dependency entirely.
2. **Whether v1.51's prior cycle-48 measurements were artifacts of the dyld issue.** Cycle-48 reported 11 parse-errors; cycle-49 reveals all were dyld. Were any of v1.50's cycle-47 picks also masked by the same issue? Re-running v1.50's binary against the cycle-49 fixture with stderr capture would tell us — but the answer is also "probably yes; cycle-47's 0/109 measurement was dominated by carrier-resolution, which is upstream of the dyld issue anyway."
3. **The V1.52.A free-function vs static-method decision.** Cycle-49 favors revert. v1.53's first commit should be the revert, with the rationale tied to this findings doc.
