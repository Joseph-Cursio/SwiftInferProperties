# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository state

**Current: v1.63.0** — sixtieth calibration cycle and **thirteenth Phase 2 gap-closing cycle; diminishing-returns pivot point**. V1.63.A scaffolds `OrderedDictionary.Elements` via the V1.62.A 3-edit pattern (binding + recipe + gate) — closes 1 `.bothPass` (`OD.Elements.sort()` idempotence). Plus reclassification pattern extension for `"generic parameter ... could not be inferred"` (Swift compiler diagnostic for static-call-shape on nested generics) — preserves `.measured-error = 0` baseline across the OD.Elements scaffold transition. Diminishing returns are now visible: v1.62 closed 8 picks; v1.63 closed 1. Remaining nested-OC carriers (OS.SubSequence, OD.Values, OD.Elements.SubSequence) are dominated by Comparable-blocked monotonicity + discover-layer false-positives — v1.64+ should pivot to Comparable-aware monotonicity composer (broader unblock) or non-OC generics. **Test count 2414 → 2415 (+1)**.

**Cycle-60 measurement headline**: **42/103 = 40.8% measured-execution**. **+1 vs cycle-59** (OD.Elements.sort()). Distribution: **28** `.bothPass` + 6 `.defaultFails` + 8 `.edgeCaseAdvisory` + 0 `.measured-error` + 61 `.architectural-coverage-pending`. **OC-family coverage**: 22/44 = 50% (13 OS<Int> + 8 OS<Int>.UnorderedView + 1 OD<Int,Int>.Elements). **Diminishing-returns pivot**: v1.62 closed 8 OC picks; v1.63 closed 1. Remaining nested-OC carriers dominated by Comparable-blocked monotonicity + discover-layer false-positives.

**Cycle-58 headline (carried forward)**: 33/103 = 32.0% — +12 OS SetAlgebra dual-style picks closed via V1.61.A curated-pair fix + V1.61.B mutating-instance emission.

**The measurable subset now spans 13 OS picks** (1 idempotence + 12 dual-style) — architecture's OC coverage meaningfully demonstrated.

**Detail-string distribution shift (cycle-57 → cycle-58)**:
- `instance-method-shape-not-supported` 16 → **4** (-12; the 12 OS dual-style picks closed to .bothPass)
- Other categories unchanged.

**V1.51.B latent bug fixed**: the mismatched curated pairs (treating `formUnion` as both halves) had blocked 12 picks from reaching `.bothPass` since v1.48 — ~13 release cycles of latent measurement-tooling gap. V1.61.A's correction restores the Swift SetAlgebra pairing (union ↔ formUnion etc.). Methodology lesson: curated-name tables for foreign APIs need cross-checking against the target API's conventions.

**32-pick sample-subset agreement with cycle-46** (unchanged; OS picks aren't in the stratified subset):
- **Strict 4-category match**: 5/13 = 38%
- **Semantic "property holds" match**: 13/13 = **100%**

The 13 OS `.bothPass` outcomes extend the measurable set beyond the cycle-46 sample. 100% per-pick mathematical correctness on the SetAlgebra-equivalence contract.

v1.63+ priorities (per cycle-59 evidence, in priority order):

1. **v1.63 — Strategist recipes for the remaining nested-OC carriers** (25 picks: 7 OD.Elements, 6 OS.SubSequence, 6 OD.Values, 6 OD.Elements.SubSequence). Each follows the V1.62.A 3-edit pattern (binding + recipe + gate).
2. **v1.63 — Strategist recipes for non-OC generics** (17 picks: `_HashTable`, `ChunkedByCollection`, etc.).
3. **v1.64 — Comparable-aware monotonicity composer** (2 picks).
4. **v1.64 — `_minimumCapacity/_maximumCapacity` curated round-trip pair** (3 picks at the resolver layer; likely reclassify to internal-api).
5. **v1.65+ — Phase 2 accept-flow integration** — demonstrably viable (40% measured rate, 0 measured-error).
6. **v1.65+ — Methodology-guard parallel for curated-pair tables** — V1.58.B-style fixture-level check would have surfaced V1.51.B's mismatch pre-merge.
7. **Discover-layer false-positive cleanup** — 4 commutativity/associativity picks on `distance(from:Int,to:Int)` and `index(_:offsetBy:)` are signature mismatches (args aren't OS type); current architecture can't easily verify them. Deferred indefinitely; investigate discover-side template-match precision.
8. **V1.42.C.5 deferred** — implicit reindex on demand (carried from v1.42).

Full list in `docs/archive/v1.62 Calibration Plan.md`, `docs/calibration-cycle-59-findings.md` (+8 .bothPass via UnorderedView scaffold; OS-family 57% measured), `docs/calibration-cycle-59-data/full-surface-summary.md`.

---

[previous: v1.61.0] — fifty-eighth calibration cycle and **eleventh Phase 2 gap-closing cycle; biggest single-cycle measured-execution gain in the project's history (+12 .bothPass)**. V1.61.A fixed `DualStyleConsistencyPairResolver`'s mismatched V1.51.B curated pairs; V1.61.B `composeMutatingDualStylePass` for 2-value-per-trial OC dual-style. Cycle-58 closed all 12 OS SetAlgebra dual-style picks.

---

[previous: v1.60.0] — fifty-seventh calibration cycle and **tenth Phase 2 gap-closing cycle; first OC closure**. V1.60.A mutating-instance-method idempotence emission for OC carriers + V1.60.B regression tests. **`OrderedSet.sort()` × idempotence reaches `.bothPass` at 100 trials** — first non-Complex/Double measured-execution in the project's calibration history.

---

[previous: v1.59.0] — fifty-sixth calibration cycle and **ninth Phase 2 gap-closing cycle; second TypeShape scaffold step**. Three coupled fixes in V1.59.A (curated OC recipe + workdir Package.swift dep + double-qualifier strip in `CallExpressionShape.render`) plus reclassification pattern extensions (3 new architectural-pending categories: `instance-method-shape-not-supported`, `carrier-missing-required-conformance`). V1.59.B 6 unit tests. Cycle-56 aggregate unchanged but detail-string distribution shifted — 26 OS picks moved past resolver layer into compile-fail at instance-method-shape (preserved `.measured-error = 0` baseline).

---

[previous: v1.58.0] — fifty-fifth calibration cycle and **eighth Phase 2 gap-closing cycle; TypeShape scaffold opening**. V1.58.A `OrderedSet → OrderedSet<Int>` binding + V1.58.B methodology guard for `GenericBindingResolver.curatedBindings` (surfaced 4 latent V1.47.D bindings). v1.58 was scaffolding-only by design; cycle-55 outcome aggregate-unchanged with detail-string shift on 29 OS picks.

---

[previous: v1.57.0] — fifty-fourth calibration cycle and **seventh Phase 2 gap-closing cycle**. **Methodologically-significant baseline correction** — V1.57.A `private`/`fileprivate` filter in `FunctionScannerVisitor` drops file-private declarations at scan time. Applied retroactively to the cycle-27 fixture: 6 file-private picks from SwiftPropertyLaws dropped (3 file-private helpers + 3 `private static` ViolationFormatter members). **Cycle-27 baseline shifts 109 → 103 picks.** Total measured-execution count unchanged at 20; rate improves 18.3% → 19.4% (denominator-driven).

---

[previous: v1.56.0] — fifty-third calibration cycle and **sixth Phase 2 gap-closing cycle**. **Single-workstream release** — V1.56.A internal-API build-failure reclassification (new helper `architecturalPendingDetail(buildStdout:buildStderr:)` checks both streams for `"is inaccessible due to '<access-level>'"`; on match, surveyRecord returns `.architecturalCoveragePending` with detail `"internal-api-not-accessible"`). V1.56.B 6 unit tests pin the matcher. **Cycle-53 headline**: 20/109 = 18.3% measured-execution with `.measured-error = 0` for the first time since cycle-47.

---

[previous: v1.55.0] — fifty-second calibration cycle and **fifth Phase 2 gap-closing cycle**. **Single-workstream release** — V1.55.A per-function default-pass domain for Complex round-trip (2-entry curated table: cos/cosh use `Re ∈ [0, 1.5]`; everything else uses symmetric `±1.5`). Closes the cycle-51 generator-tuning finding. **Cycle-52 headline**: 20/109 = 18.3% measured-execution unchanged from cycle-51 but category quality improved — 8 picks shift from misleading `.defaultFails` to correct `.edgeCaseAdvisory` (first non-zero advisory measurement). Cycle-46 semantic agreement reaches 100% on the measurable subset.

---

[previous: v1.54.0] — fifty-first calibration cycle and **fourth Phase 2 gap-closing cycle**. Three workstreams targeting cycle-50 follow-ups: V1.54.A V1.52.A free-function revert (`CallExpressionShape.freeFunctionMap` emptied; the 8 round-trip Complex EF picks return to `.staticMethod` shape and reach the property check via V1.53.A's DYLD fix); V1.54.B V1.52.C dead-binding cleanup (4 `<Type>.Index` keys removed); V1.54.C `RealModule` import for FP strategist recipes (caught at cycle-51 smoke-test stage; prevented a 2-pick regression V1.54.A alone would have caused). **Cycle-51 headline**: 20/109 = 18.3% measured-execution (+8 vs cycle-50); 6 .bothPass + 14 .defaultFails; first generator-tuning gap surfaced — 8 round-trip Complex EF picks overflow due to the v1.42 generator exceeding the function's stable domain.

---

[previous: v1.53.0] — fiftieth calibration cycle and **third Phase 2 gap-closing cycle**. **Single-workstream release** (like v1.41 was) — V1.53.A `DYLD_LIBRARY_PATH` injection on the verifier subprocess (~80 LoC in `Sources/SwiftInferCLI/VerifierSubprocess.swift`; detects the active Swift toolchain's testing-library directory via `swift -print-target-info` → `paths.runtimeResourcePath` + `macosx/testing` suffix; cached via `static let`; graceful nil-fallback when detection fails). Closes the cycle-49 `libTesting.dylib` runtime-link gap that V1.52.B's stderr capture surfaced. **Cycle-50 headline**: 12/109 = 11.0% measured-execution — first non-zero measurement in the project's calibration history. 6 `.bothPass` + 6 `.defaultFails`, all 12 mathematically valid.

---

[previous: v1.52.0] — forty-ninth calibration cycle and **second Phase 2 gap-closing cycle**. v1.52 ships three workstreams targeting the cycle-48 findings: V1.52.A `CallExpressionShape` classifier (new type at `Sources/SwiftInferCLI/CallExpressionShape.swift`; three cases — `.staticMethod` / `.operatorFunction` / `.freeFunction`; 14-entry ElementaryFunctions free-function set for Complex/Double/Float; wired into 4 pair resolvers + 4 dispatch sites); V1.52.B subprocess stderr surfaced in parse-error detail (new `pipeJoinedTail` + `parseErrorReason` helpers in `VerifyResult.swift`; conditional append when stderr non-empty; 200-char per-line truncation); V1.52.C `GenericBindingResolver.curatedBindings` +4 chunked-Index / OrderedSet.Index entries (latent — wrong key format, see cycle-49 finding below); V1.52.D ~21 unit tests; V1.52.E cycle-49 measurement; V1.52.F findings doc. **Test count 2378 → 2399 (+21)**; **non-subprocess fast path 2399/2399 in ~4s** via `swift test --skip VerifyPipelineIntegrationTests`.

**Cycle-49 measurement headline**: **22/109 = 20.2% measured-execution — unchanged from cycle-48 at the aggregate**. But the *composition* of the 22 changed substantially, and V1.52.B's stderr capture **falsified the cycle-48 framing** of the parse-error class. Real cycle-49 findings:

- **V1.52.A operator-paren form works** (6 cycle-48 build-failures closed): Complex `+`/`-`/`*`/`/` + Double `log(onePlus:)` now compile and reach runtime via the `(/)`-style paren form.
- **V1.52.A free-function form regressed** (8 cycle-48 parse-errors regressed compile): all 8 are round-trip Complex EF-surface picks (`exp`, `log`, `sin`, `cos`, `tan`, `sinh`, `cosh`, `tanh`). Bare `exp(value)` doesn't resolve from a workdir that imports only `ComplexModule` — swift-numerics's global EF overloads live in `Real`/`_Numerics`.
- **V1.52.B revealed the real cause of the 11 cycle-48 parse-errors**: `dyld[XXXX]: Library not loaded: @rpath/libTesting.dylib`. The verifier subprocess can't resolve swift-testing's runtime library at startup. **Not a call-expression-shape issue at all**; the cycle-48 findings doc's speculation was wrong. This is a workdir-synthesis gap independent of which pick the stub exercises.
- **V1.52.C bindings are latent** (zero picks moved): keyed on `<Type>.Index` but the indexer outputs bare `<Type>`. Same latent-on-cycle pattern as V1.51.B.

**Net v1.52 effect**: V1.52.A produced ~zero net movement (closed 6 builds, regressed 8 builds). V1.52.B was the cycle's biggest win — without stderr capture, v1.53 would have continued chasing the wrong gap. V1.52.C needs a mechanical key-format fix in v1.53.

**Per-pick agreement-rate signal still uncomputable** — all 22 measured picks remain `.measured-error`. The libTesting.dylib gap is the next load-bearing fix; closing it should unlock the first non-zero `.bothPass` / `.defaultFails` subset.

v1.53+ priorities (per cycle-49 evidence, in priority order):

1. **v1.53 — `libTesting.dylib` runtime-link fix** — the highest-impact single fix. Three approaches under consideration: (a) link the verifier as a non-Testing executable (drop `import Testing`, hand-roll the property-check loop); (b) inject `DYLD_FALLBACK_LIBRARY_PATH` into the subprocess env; (c) emit explicit `@rpath` entries during workdir synthesis. Closes all 12 parse-dyld picks + the 6 V1.52.A-newly-compiling picks (~16-18 picks reach property check; likely first non-zero `.bothPass`/`.defaultFails`).
2. **v1.53 — V1.52.A free-function revert** (or import-shim fix) — restore `.staticMethod` for the EF surface on Complex/Double/Float (or add `import Real` to the V1.49.A preamble). Closes the 8 cycle-49 regressed round-trip Complex builds.
3. **v1.53 — V1.52.C carrier-name key fix** — change `ChunkedByCollection.Index` keys to bare `ChunkedByCollection`. Closes the 3 chunked-Index `.defaultFails` predictions (cycle-46) once V1.52.C's bindings actually fire.
4. **v1.53 — Methodology guard** — fixture-level check that every `GenericBindingResolver.curatedBindings` entry matches at least one indexer-produced carrier-name format. Prevents the V1.51.B + V1.52.C latent-key-format pattern from recurring.
5. **v1.53-v1.54 — TypeShape-driven generic instantiation** for `OrderedSet`, `OrderedDictionary`, etc. — closes 60+ OC picks (dominant share of the residual 87 architectural-coverage-pending bucket).
6. **v1.54+ — Phase 2 accept-flow integration** once cycle-50 produces a non-trivial `.bothPass` / `.defaultFails` subset.
7. **V1.42.C.5 deferred** — implicit reindex on demand (carried from v1.42).

Full list in `docs/archive/v1.52 Calibration Plan.md` (v1.52 specifics), `docs/calibration-cycle-49-findings.md` (cycle-49 findings + v1.53+ roadmap), `docs/calibration-cycle-49-data/full-surface-summary.md` (template × failure-reason cross-tab + transition table + workstream-impact summary).

---

[previous: v1.51.0] — forty-eighth calibration cycle and **first Phase 2 gap-closing cycle**. v1.51 ships three mechanical fixes addressing the cycle-47 measurement-tooling gap + a blind-spot guard against recurrence: V1.51.A bare→qualified `Complex` carrier normalization (extends `GenericBindingResolver.curatedBindings` with `"Complex" → "Complex<Double>"`; ~5 LoC); V1.51.B `DualStyleConsistencyPairResolver.curated` expansion (6 cycle-27-evidenced pairs: formIntersection / formUnion / formSymmetricDifference / subtract / merge / merging; ~10 LoC); V1.51.C v1.48-template routing flip (idempotence-lifted / dual-style-consistency / monotonicity always route through the strategist regardless of carrier — closes the 2 monotonicity-on-Double picks that hit `v1_46HardcodedBundle`'s default branch; ~10 LoC); V1.51.D always-on E2E indexer→verify resolution guard at `Tests/SwiftInferCLITests/V1_51EndToEndFromIndexTests.swift` (loads the committed cycle27-surface fixture, runs `buildStubBundle` on a real-indexer entry, asserts no `VerifyError` thrown — the cycle-47 blind spot can't recur silently); V1.51.E ~15 unit tests; V1.51.F cycle-48 measurement; V1.51.G doc-level reframing (cycle-47 caveat appended to cycles 41-46 findings). **Test count 2400 → 2415 (+15)**; **non-subprocess fast path 2378/2378 in ~4s** via `swift test --skip VerifyPipelineIntegrationTests`.

**Cycle-48 measurement headline**: **22/109 = 20.2% measured-execution** (up from cycle-47's 0/109). V1.51.A + V1.51.C unblock 22 picks at the carrier/template-resolution layer; all 22 land in `.measured-error` (11 build-failed + 11 parse-error). Cycle-48 framed the parse-error class as a "call-expression shape" gap; **cycle-49's stderr capture (V1.52.B) falsified this — all 11 parse-errors were `libTesting.dylib` dyld failures.** V1.51.B's dual-style pair expansion stays latent.

---

[previous: v1.50.0] v1.50 ships the measurement-instrumentation infrastructure to extend verify coverage from the cycle-27 stratified 32-pick sample (cycles 41–46) to the **full 109-pick surface** that v1.29 froze. **No new architecture** — the cycle pivots from architecture-building (v1.42–v1.49) to measurement-tooling. **Eight workstreams shipped**: V1.50.A creates a `fixtures/cycle27-surface/` SwiftPM workspace depending on swift-algorithms + swift-collections + swift-numerics + SwiftPropertyLaws; `build-index.sh` resolves the deps, runs `swift-infer index` against each of the 4 checkout source targets (8 + 74 + 20 + 7 = 109 picks), merges into a single fixture-level index sorted by identityHash. V1.50.B extends `SwiftInferCommand.Verify` with `--all-from-index` flag (+ `--max-parallel` default 4 + `--template` filter) — mutually exclusive with `--suggestion`; loads the SemanticIndex, iterates every entry via a bounded `TaskGroup`, emits per-line JSON `SurveyRecord` to stdout. V1.50.C defines a 5-category classification scheme (`measured-bothPass` / `measured-edgeCaseAdvisory` / `measured-defaultFails` / `measured-error` / `architectural-coverage-pending`) implemented in `surveyRecord(for:)` — catches `VerifyError` sub-types into `architectural-coverage-pending` with a short outcomeDetail; non-VerifyError exceptions land in `measured-error`. V1.50.D aggregate-metrics computation lives downstream (jq + cycle-47 findings doc). **V1.50.B routing fix**: the first survey run revealed 49 picks misclassified as `unsupported-template`; the V1.47.F strategist→v1.46 fallback fired for v1.48-template entries when the strategist's first attempt failed, then v1_46HardcodedBundle's 4-case switch defaulted to `.unsupportedTemplate`. Fix: gate the fallback on `v1_46HardcodedTemplates = {round-trip, idempotence, commutativity, associativity}` so v1.48-template entries surface their real strategist error. V1.50.E ships 7 unit tests (argument parsing + SurveyOutcome raw values + SurveyRecord JSON round-trip) + a v1.42 test rework (`--suggestion` is now optional at parse time; the run-time validator rejects empty). V1.50.F-G ships cycle-47 findings + the canonical 109-entry survey JSON + summary md. **Test count 2393 → 2400 (+7); full `swift test` wall-clock ~210s (21 parallel subprocess builds, unchanged from v1.49); `swift test --skip VerifyPipelineIntegrationTests` ~4s for the non-subprocess fast path.** All v1.42–v1.49 §13 budgets unchanged. Per-cycle narratives in `docs/archive/*.md` + `docs/calibration-cycle-*-findings.md` + git log; this file is a pointer-only index.

**Cycle-47 first-measurement headline**: **0/109 = 0.0% measured-execution; 100% architectural-coverage-pending**. The first full-surface verify run lands every cycle-27 pick in `architectural-coverage-pending` because each pick errors at carrier/pair/template resolution before reaching `swift build`. Failure distribution: 85 `unsupported-carrier` (indexer stores bare `Complex` / `OrderedSet` etc.; v1.49 emitter expects qualified `Complex<Double>`) + 22 `unsupported-pair` (dual-style curated list has 3 entries vs cycle-27's 22 OC dual-style picks using `formIntersection`/`formUnion`/etc.) + 2 `unsupported-template` (monotonicity-on-Double residual v1.46-path coverage gap). **Methodological reframing, not regression**: cycles 42–46's "100% per-pick agreement" was synthetic-shape-class agreement on hand-crafted SemanticIndexEntry instances — load-bearing at the *capability* level. Cycle-47 is the first *real-source-indexed* verify run and reveals measurement-tooling gaps the cycle-46 framing didn't capture.

v1.51+ priorities (per cycle-47 findings, in order of expected impact):

1. **v1.51 — bare→qualified carrier normalization** at V1.47.F router (~30 LoC). Closes the 85 `unsupported-carrier` picks to the point where they hit `unsupported-pair` or `measured-error` rather than carrier-name mismatch.
2. **v1.51 — `DualStyleConsistencyPairResolver.curated` expansion** (~10 LoC; 6+ cycle-27-evidenced pairs). Closes the 22 `unsupported-pair` picks.
3. **v1.51 — `v1_46HardcodedTemplates` widening for monotonicity-on-Double** — small. Closes the 2 `unsupported-template` picks.
4. **v1.51 cycle-48 measurement** — re-run the full survey post-fix; anchor the v1.51 trajectory.
5. **v1.52+ — internal-typed carrier handling** (`@testable` workdir vs preamble-synthesized stubs for `_HashTable`, `_Bucket`, etc.).
6. **v1.52+ — accept-flow integration** (verify outcomes → `decisions.json`) once a meaningful subset of the surface is `measured-*`.
7. **v1.52+ — verification cache**, "Verified" first-class tier.
8. **V1.42.C.5 deferred** — implicit reindex on demand (`IndexCommand`-side refactor; carried from v1.42).

Full list in `docs/archive/v1.50 Calibration Plan.md` (v1.50 specifics), `docs/calibration-cycle-47-findings.md` (first full-surface measurement + v1.51+ roadmap), `docs/calibration-cycle-47-data/full-surface-summary.md` (template × failure-reason cross-tab), and the test-execution evidence proposal at `docs/ideas/Edge-Case-Biased Generators Kit Proposal.md` (cross-cycle Phase 1 roadmap).

---

[previous: v1.49.0] — forty-sixth calibration cycle and **Phase 1.5 close-out**. v1.49 ships four bundled workstreams reaching 8/8 = 100% verifier-mode REJECT lift on the cycle-27 stratified 32-pick sample + 93.8% measured / 100% architectural verifiable-fraction: V1.49.A stub-preamble channel on all 5 emitters; V1.49.B `.memberwiseArbitrary` strategy emit (1-10 arity); V1.49.C non-curated round-trip pair derivation via `secondaryFunctionName` (closes the 8th cycle-27 REJECT #2 `_minimumCapacity/_scale`); V1.49.D `.subprocess` Swift Testing tag for §13 perf-flake mitigation. Test count 2360 → 2393 (+33); full `swift test` wall-clock ~210s.

---

[previous: v1.48.0] — forty-fifth calibration cycle and **fourth cycle of the Phase 1.5 verifiable-fraction expansion arc**. v1.48 closed the cycle-27 template-coverage matrix by adding three new templates in a single bundled cycle: idempotence-lifted + dual-style-consistency + monotonicity. Verifiable-fraction 40.6% → 87.5%. Eight workstreams (no new architecture — all three templates route through v1.47's `StrategistDispatchEmitter`). Test count 2332 → 2360 (+28); full `swift test` wall-clock ~200s.

---

[previous: v1.47.0] — forty-fourth calibration cycle and **third cycle of the Phase 1.5 verifiable-fraction expansion arc**. v1.47 ships **DerivationStrategist verify-time integration** — the first *carrier-arm* expansion after v1.45 + v1.46 closed the four-template arc. Verifiable-fraction climbs 31.3% → 40.6% with **3 new verify-confirmed REJECTs** (#7–#9 chunked-Index picks via `GenericBindingResolver`), bringing cumulative verifier-mode REJECT lift to **7/8 = 87.5%**. Nine workstreams: V1.47.A `IndexedTypeShape` mirror; V1.47.B `SemanticIndexEntry.typeShape` field + schema migration; V1.47.C discover-side population; V1.47.D `GenericBindingResolver` (5-entry curated); V1.47.E `StrategistDispatchEmitter` (5 strategies × 4 templates); V1.47.F two-arm carrier router; V1.47.G 47 unit + 4 integration tests; V1.47.H cycle-44 findings (13/13 = 100% per-pick agreement). Test count 2288 → 2332 (+44); full `swift test` wall-clock ~170s.

---

[previous: v1.46.0] — forty-third calibration cycle and **second cycle of the Phase 1.5 verifiable-fraction expansion arc**. v1.46 ships **associativity verify support** (fourth template after round-trip + idempotence + commutativity), lifting the verifiable-fraction 21.9% → 31.3% and bringing the verifier-mode REJECT lift to **4/8 = 50%**. Six workstreams: V1.46.A `AssociativityStubEmitter` (per-slot rotation edge bias + `VERIFY_EDGE_SLOT` marker); V1.46.B `AssociativityPairResolver`; V1.46.C dispatch + `RenderShape.associativity`; V1.46.D 31 unit + 3 subprocess integration tests; V1.46.E cycle-43 findings (10/10 in-scope picks 100% agreement). Test count 2254 → 2288 (+34); full `swift test` wall-clock ~160s.

---

[previous: v1.45.0] — forty-second calibration cycle and **first cycle of the Phase 1.5 verifiable-fraction expansion arc** (post-completion of the v1.42–v1.44 Phase 1 architectural shift). v1.45 ships **commutativity verify support** (third template after round-trip + idempotence) and a **curated round-trip pair-list expansion** (6 hyperbolic entries), lifting the cycle-27-corpus verifiable-fraction from 6.25% to 21.9% and surfacing the **first measured verify-mode REJECT confirmation**. Six workstreams: V1.45.A `CommutativityStubEmitter` (3-carrier dispatch + lhs-only edge bias); V1.45.B `CommutativityPairResolver`; V1.45.C dispatch + renderer extension; V1.45.D 6 hyperbolic curated pairs (`sinh/asinh`, `cosh/acosh`, `tanh/atanh`); V1.45.E 3 subprocess integration tests (surfaced a real Pass 2 `defaultGenerator` redeclaration bug); V1.45.F cycle-42 findings doc (verifiable-fraction 21.9%; first verify-mode REJECT confirmation on `binomial` + `distance`; 7/7 in-scope picks 100% agreement). Test count 2220 → 2254 (+34); full `swift test` wall-clock ~131s.

---

[previous: v1.44.0] — forty-first calibration cycle and **third of 3 cycles delivering the test-execution-evidence architectural shift** (v1.42 step 1; v1.43 step 2; v1.44 step 3). v1.44 extended the verify pipeline to a second template (idempotence non-lifted) and two new carriers (Double, Int beyond v1.42/v1.43's Complex<Double>), then took the first verify-mode calibration measurement on the cycle-27 corpus. Six workstreams: V1.44.A `IdempotenceStubEmitter`; V1.44.B `RoundTripStubEmitter` carrier dispatch via private `CarrierKind` enum (3 carriers + zero-edge sentinel for Int); V1.44.C mirror B for idempotence; V1.44.D `IdempotencePairResolver` + `Verify.runPipeline` template dispatch + template-aware renderer; V1.44.E 3 always-on subprocess integration tests for idempotence × each carrier; V1.44.F cycle-41 findings doc (verifiable-fraction 2/32 = 6.25%; all 8 cycle-27 REJECTs out of scope; planned aggregate-rate-shift didn't materialize). Test count 2178 → 2220 (+42); full `swift test` wall-clock ~65s.

---

[previous: v1.43.0] — fortieth calibration cycle and **second of 3 cycles delivering the test-execution-evidence architectural shift** (v1.42 shipped step 1; v1.44 is step 3). v1.43 layered the **edge-case-biased second pass** on top of v1.42's single-pass round-trip verifier and expanded the user-facing result to the four-outcome two-pass table. Five workstreams: V1.43.A wires `PropertyLawComplex` (the kit's v2.1.0 opt-in product) into the synthesized verifier workdir's `Package.swift`; V1.43.B rewrites `RoundTripStubEmitter` to emit two passes (default finite-domain + `Gen<Complex<Double>>.edgeCaseBiased()`), short-circuiting the edge pass on default fail; V1.43.C/D rewrite `VerifyOutcome` to a 4-case shape (`bothPass` / `edgeCaseAdvisory` / `defaultFails` / `error`) + parser + renderer with the 12-entry curated-label table; V1.43.E.3.b adds the `edgeCaseAdvisory` integration test and fixes a latent V1.43.B bug (`matchEdgeCaseIndex` now uses `Complex.rawStorage`). Test count 2171 → 2178 (+7); full `swift test` wall-clock ~41s.

---

[previous: v1.42.0] — thirty-ninth calibration cycle and **first of 3 cycles delivering the test-execution-evidence architectural shift** (originally raised at v1.25; design + kit-side prerequisite landed earlier this cycle). v1.42 shipped the **minimum-viable verify pipeline**: an opt-in `swift-infer verify --suggestion <id>` subcommand that compiles + runs a synthesized round-trip property test in a throwaway SwiftPM workdir and reports pass / fail / error. Eight workstreams: V1.42.A kit pin bump 2.0.0 → 2.1.0 (`PropertyLawComplex` product at SwiftPropertyLaws commit ba19ab7 / tag v2.1.0); V1.42.B `Verify` subcommand argument surface; V1.42.C.1 `VerifyHarness` for hash-prefix suggestion lookup; V1.42.C.2 `RoundTripStubEmitter` (pure-function source emission, `Complex<Double>` only); V1.42.C.3 `VerifierWorkdir` + `VerifierSubprocess` for SwiftPM workdir synthesis at `<packageRoot>/.swiftinfer/verify-workdir/<hashPrefix>/` (PRD §14 hard-guarantee exemption for `VerifierSubprocess.swift`); V1.42.C.4 `VerifyOutcome` + `VerifyResultParser` + `VerifyResultRenderer` for stdout-marker parsing and ✓/✗/! rendering; V1.42.D two always-on end-to-end integration tests; V1.42.C.6 `Verify.run()` end-to-end with a curated 8-entry round-trip pair list (exp/log, cos/acos, sin/asin, tan/atan; bidirectional). `VerifyError` ships 11 cases; the kit's main `PropertyLawKit` line keeps a zero `swift-numerics` footprint. Test count 2103 → 2171 (+68) across 6 new test files; full `swift test` wall-clock 4s → 37s (dominated by the V1.42.D subprocess tests).

---

[previous: v1.41.0] — thirty-eighth calibration cycle. Closes the v1.35 cycle-32 finding: **`RefactorClusterAnalyzer.classify` now uses a two-layer dominant-pattern rule.** OrderedSet's 29-suggestion cluster reclassifies from the misleading `algebraicStructure` (only 14% algebraic — fired under the pre-v1.41 "any 2 distinct templates wins" rule) to `dual-style-consistency cluster` (dual-style 12 entries is the dominant single template). The curated suggestion text now correctly points at SetAlgebra conformance. Layer 1: algebraic-collective dominance (2+ distinct algebraic templates AND their sum ≥50% of total → algebraicStructure). Layer 2: single-template most-numerous wins among per-template shapes meeting ≥3 threshold (with the pre-v1.41 priority order retained as tie-breaker). Layer 3: ≥4 total → generalCluster catch-all. **End-to-end verified**: only OrderedSet changes classification on OrderedCollections; ComplexModule stays algebraicStructure (12/20 = 60%); the other 6 OC clusters had genuine algebraic dominance (57–67%) and are unchanged. Constraint Engine refactor (v1.36–v1.40) untouched — v1.41 modifies only the cluster-classification layer. No acceptance-rate re-measurement (cycle-27's 72.4% holds). Test count 2097 → 2103 (+6). Per-cycle narratives in `docs/archive/*.md` + `docs/calibration-cycle-*-findings.md` + git log; this file is a pointer-only index.

---

[previous: v1.38.0] — thirty-fifth calibration cycle; first batch-migration cycle. Associativity + InvariantPreservation + DualStyleConsistency migrated (5/10 templates after this cycle). Test count 2080 → 2088 (+8).

---

[previous: v1.37.0] — thirty-fourth calibration cycle; second Constraint Engine migration. MonotonicityTemplate migrated. Templates migrated: 2/10. Test count 2077 → 2080.

---

[previous: v1.36.0] — thirty-third calibration cycle; Constraint Engine foundation. Introduced `Constraint<Subject>` + `ConstraintRunner` + migrated `CommutativityTemplate` as proof-of-concept. Templates migrated: 1/10. Test count 2059 → 2077 (+18).

---

[previous: v1.35.0] — thirty-second calibration cycle; ships carrier-aware refactor suggestions via `swift-infer suggest-refactors`. 5-shape ClusterShape taxonomy. End-to-end verified on ComplexModule (1 cluster) and OrderedCollections (8 clusters across 6 distinct carrier types). Test count 2027 → 2059 (+32).

---

[previous: v1.34.0] — thirty-first calibration cycle; **focused follow-up release** closing the v1.33-deferred SemanticIndex `typeName` field. Three workstreams: V1.34.A `carrier: String?` on `Suggestion`, V1.34.B threaded through 16 construction sites, V1.34.C consumed in `IndexCommand.buildEntry`. End-to-end `query --type Foo` works. Backward-compatible; per-template inference precision unchanged.

---

[previous: v1.33.0] — thirtieth calibration cycle; **third design-completion release**. PRD §20.1 SemanticIndex: JSON-backed persistent index at `.swiftinfer/index.json` + two CLI subcommands (`swift-infer index`, `swift-infer query`). 11-column schema. Storage-format decision: JSON-first; SQLite is a non-breaking later swap. Test count 1994 → 2027 (+33).

---

[previous: v1.32.0] — twenty-ninth calibration cycle; **second design-completion release**. PRD §20.3 Domain Template Packs: monolithic 10-template registry split into 5 named packs (numeric, serialization, collections, algebraic, concurrency) with non-exclusive membership. `--packs` CLI flag + config TOML. Backward-compatible (nil filter = monolithic default). Test count 1959 → 1994 (+35).

---

[previous: v1.31.0] — twenty-eighth calibration cycle; **first design-completion release**. Closed the 13-cycle longest-running carry-forward FP approximate-equality template arm. Three workstreams: V1.31.A `FloatingPointEquatableTypes` curated set + detector, V1.31.B `LiftedTestEmitter.EqualityKind` enum, V1.31.C dispatch wiring. Mechanism-class taxonomy 15 → 16 (class 16 = emit-time equality-form dispatch; first emit-side mechanism class).

---

[previous: v1.30.0] — twenty-seventh calibration cycle; seventh empirical-only release. Headline: 21/29 = 72.4% — **§19 ≥70% TARGET REACHED** after 27 calibration cycles. Seven-point trajectory: 26.7% → 34.8% → 52.3% → 48.8% → 67.6% → 63.6% → 72.4%. Cycle-26's mechanism-precision projection (72.4%) matched cycle-27's measurement exactly. Dual-style-consistency 5-cycle 100% rate-stability.

---

[previous: v1.29.0] — twenty-sixth calibration cycle; **fifth consecutive measurement-driven mechanism release** closing cycle-25 findings (V1.29.A inverse-pair asymmetric full-veto, V1.29.B identity-element algebraic-family-mismatch veto, V1.29.C composition-lifted monotone-bounded full-veto). Surface 113 → 109 (-4; exact plan-vs-actual match). Cumulative reduction -90.66%. Mechanism-class taxonomy 14 → 15.

---

[previous: v1.28.0] — twenty-fifth calibration cycle and **sixth empirical-only release**; binary-equivalent to v1.27.0. Headline: 21/33 = 63.6% Possible-tier acceptance rate — Outcome B (60-69% plateau range); -4.0pp from cycle-23's 67.6%. §19 ≥70% target NOT reached within 25 cycles. Six-point trajectory: 26.7% → 34.8% → 52.3% → 48.8% → 67.6% → 63.6% — first plateau confirmation in the loop's history, bracketing the true rate at 63-68%. Two cycle-25 mechanism findings closed by v1.29: (1) V1.27.B closure gap on asymmetric inverse-pair (now V1.29.A); (2) IdentityElementTemplate curated-constant match (now V1.29.B).

---

[previous: v1.27.0] — twenty-fourth calibration cycle; measurement-driven mechanism release closing 2 cycle-23 findings. Two workstreams: V1.27.A Sequence-conformance fallback on V1.21.A IteratorProtocol veto (class 7 extension; infrastructure for future Sequence-conforming carriers); V1.27.B name-prefix-gated full-veto on V1.11.1 inverse-pair direction-counter (class 6 extension; mirrors V1.22.B + V1.25.A patterns). Surface 114 → 113 (-1; plan-vs-actual -1 vs -4). Cumulative reduction -90.32% vs cycle-1's 1167-baseline. Test count 1893 → 1905 (+12).

---

[previous: v1.26.0] — twenty-third calibration cycle and **fifth empirical-only release** (after cycles 6 = 26.7%, 14 = 34.8%, 17 = 52.3%, 20 = 48.8%). v1.26 binary-equivalent to v1.25.0. **Headline: 25/37 = 67.6% Possible-tier acceptance rate — Outcome A**; +18.8pp from cycle-20's 48.8% (**largest single-cycle aggregate jump in the loop's history**). **§19 ≥70% target now within +2.4pp** — sample-noise band on n=40. Five-point trajectory: **26.7% → 34.8% → 52.3% → 48.8% → 67.6%**. Cycle-20's non-monotonic step (-3.5pp) validated as calibration-trade-off + sample-shift; cycle-23 measurement shows the v1.25 surface composition has materially higher per-template accept rates (round-trip 85.7%, dual-style-consistency 100% over 3 measurement points, idempotence-lifted 66.7%). Drivers: cycles 21+22 mechanism work closed -38 cross-product/direction-op/asymmetric/non-deterministic/capacity-formatter/index-advance rejects with high precision-positive density. V1.18.C dual-style 100% rate-stability across 3 consecutive measurement points = largest mechanism-class precision contribution in loop history. Per-cycle narratives in `docs/archive/*.md` + `docs/calibration-cycle-*-findings.md` + git log; this file is a pointer-only index.

No active milestone plan. Cycle-24 priorities (rotated post-v1.26): (1) FP approximate-equality template arm (**10-cycle carry-forward**; cycle-14 priority #4; correctness-emission work). (2) **NEW (cycle-23 finding):** Algo idempotence-lifted Iterator-like survivors veto — extend V1.21.A's Iterator detection to catch 2 Algo carriers without explicit IteratorProtocol conformance. (3) **NEW (cycle-23 finding):** OC bucket/word direction-pair veto on inverse-pair template — extend V1.25.A's name-prefix gate to inverse-pair; closes 2 OC. (4) Math-library `_relaxed*` (defer indefinitely; ACCEPT-class). (5-7) v1.19 carry-forwards (defer). §19 ≥70% within sample-noise band — one more mechanism cycle reaches the target. Full list in `docs/calibration-cycle-23-findings.md`. PRD §20 v1.1+ work deferred. Kit-side `ValueSemantic` proposal M-VS-2/M-VS-3/M-VS-4 deferred to v1.28+.

---

[previous: v1.25.0] — twenty-second calibration cycle and **fourth consecutive measurement-driven mechanism cycle** (cycles 18 + 19 + 21 + 22 = v1.21 + v1.22 + v1.24 + v1.25). Single-workstream cycle closing the cycle-21 finding: V1.25.A extends V1.10.1's idempotence direction-counter from -15 to -25 (full veto) when function name starts with `index`/`bucket`/`word` AND parameter is direction-labeled. Closes 14 OC + 2 Algo direction-op idempotence rejects = -16 total. Mirrors V1.22.B's both-sides direction full-veto pattern on round-trip with name-prefix gate. Surface 130 → **114** (-12.3%). **First cycle to cross -90% cumulative reduction** (-90.23% vs cycle-1's 1167-baseline; prior: -88.86% at cycle 21). Idempotence non-lifted drops 19 → 3 (**-84%, single largest per-template percentage reduction in the loop's history**). Mechanism-class taxonomy 14 → 14 (no new classes; one extension of class 6). Test count 1884 → 1893 (+9). Per-cycle narratives in `docs/archive/*.md` + `docs/calibration-cycle-*-findings.md` + git log; this file is a pointer-only index.

No active milestone plan. Cycle-23 priorities (rotated post-v1.25, in expected impact order): (1) **v1.26 = cycle 23 empirical-only re-measurement** — fifth measurement point in the loop's history (after cycles 6 + 14 + 17 + 20). Provisional aggregate projection: 55-65% from cycle-20's 48.8% baseline + cycles 21+22's -38 reject closures. (2) FP approximate-equality template arm (9-cycle carry-forward; correctness-emission work). (3) Math-library `_relaxed*` extension (7-cycle carry-forward; cycle-20 ACCEPT; extension unclear). (4-6) v1.19 carry-forwards (CompositionTemplate non-numeric monoid; lift admission relaxation; `liftedFromMutation` magnitude). Full list in `docs/calibration-cycle-22-findings.md` and the v1.25 plan at `docs/archive/v1.25 Calibration Plan.md`. §19 ≥70% target reachability on-track. PRD §20 v1.1+ work deferred until SemanticIndex lands. Kit-side `ValueSemantic` proposal M-VS-2/M-VS-3/M-VS-4 deferred to v1.27+.

---

[previous: v1.24.0] — twenty-first calibration cycle and the **third consecutive measurement-driven mechanism cycle** (cycle 18 = v1.21 closed cycle-17 findings; cycle 19 = v1.22 closed cycle-18 findings; cycle 21 = v1.24 closes cycle-19 + cycle-20 findings). Four independently-mergeable workstreams: V1.24.A asymmetric label class mismatch counter on round-trip (closes 6 OC cycle-19/20 cross-pair rejects); V1.24.B explicit non-idempotent mutator-name veto on idempotence-lifted (closes 9 OC reverse/removeFirst/removeLast/pop*/drop* variants; generalizes V1.21.A's class 7 sub-class to any value-semantic carrier); V1.24.C non-deterministic shuffle veto extension (closes 3 OC shuffle variants via name-fallback); V1.24.D capacity/formatter shape-disambiguation veto on idempotence non-lifted (closes 4 OC `_description`/`_minimumCapacity(forScale:)`-shape picks). Surface 152 → **130** (-22 = -14.5%; plan-vs-actual within projection -21 to -32). New cumulative-reduction low at **-88.86%** vs cycle-1's 1167-baseline (prior: -86.97% at cycle 19). First cycle to cross the -88% threshold. Mechanism-class taxonomy **14 → 14** (no new classes; 4 extensions of existing classes 6 + 7). Test count 1845 → 1884 (+39). Per-cycle narratives in `docs/archive/*.md` + `docs/calibration-cycle-*-findings.md` + git log; this file is a pointer-only index.

No active milestone plan. Cycle-22 priorities (rotated post-v1.24, in expected impact order): (1) v1.25 = cycle 22 — empirical-only re-measurement OR mechanism cycle (loop choice). Provisional aggregate projection: 53-60% from cycle-20's 48.8% baseline + cycle-21's removal of 22 reject picks. (2) **NEW (cycle-21 finding):** `index(after:)` / `index(before:)` direction-op idempotence non-lifted veto — the residual 19-pick idempotence non-lifted pool is dominated by 13+ OC direction-op rejects. Mechanism: extend V1.10.1's direction-label counter from -15 to -25 (full veto) on `index*`/`bucket*`/`word*` names + direction-labeled. Magnitude: closes ~13 OC candidates. (3) FP approximate-equality template arm (8-cycle carry-forward; correctness-emission work). (4) Math-library `_relaxed*` extension (6-cycle carry-forward; cycle-20 measured ACCEPT — extension target unclear; defer indefinitely). (5-7) v1.19 carry-forwards (CompositionTemplate non-numeric monoid; lift admission relaxation; `liftedFromMutation` magnitude re-baselining — none motivated by cycle-20/21 measurements). §19 ≥70% target reachability remains on-track: cycle-22 projection 53-58%; two more mechanism cycles at v1.24 magnitude reach the target. Full list in `docs/calibration-cycle-21-findings.md` and the v1.24 plan at `docs/archive/v1.24 Calibration Plan.md`. PRD §20 v1.1+ work (SemanticIndex, IDE integration, `swift-infer apply`) deferred until SemanticIndex lands. Kit-side `ValueSemantic` proposal at `docs/ideas/ValueSemantic Kit Proposal.md` M-VS-2/M-VS-3/M-VS-4 deferred to v1.26+ once kit-side `ValueSemantic` protocol ships.

## Shipped

- **TemplateEngine M1–M8**, **TestLifter M1–M16** — full v1 surface; per-milestone plans in `docs/archive/`.
- **Releases v0.1.0, v1.1.0, v1.2.0, v1.3.0** — initial release through TestLifter M16; plans in `docs/archive/v*.md`.
- **Releases v1.4.0–v1.24.0** — calibration cycles 1–21 (cycle 10 was the v1.13 hoist refactor, zero behavior change; cycles 6 + 14 + 17 + 20 are empirical-only measurement releases — v1.9 + v1.17 + v1.20 + v1.23; cycle 15 = v1.18 two workstreams; cycle 16 = v1.19 lift admission; cycle 17 = v1.20 third empirical-only; cycle 18 = v1.21 closes cycle-17 findings; cycle 19 = v1.22 closes cycle-18 findings + introduces class 14 = first recall-positive signal post-V1.4.3; cycle 20 = v1.23 fourth empirical re-measurement (first non-monotonic move at 48.8%); cycle 21 = v1.24 closes cycle-19 + cycle-20 findings with 4 workstreams; new cumulative-reduction low at -88.86%). Each cycle has a plan in `docs/archive/v1.N Calibration Plan.md`, findings in `docs/calibration-cycle-N-findings.md`, raw data in `docs/calibration-cycle-N-data/`, and a perf baseline in `docs/perf-baseline-v1.N.md` (v1.17 is a v1.16 carry-forward; v1.20 is a v1.19 carry-forward; v1.23 is a v1.22 carry-forward; v1.18 + v1.19 + v1.21 + v1.22 + v1.24 re-measured).

## Kit-side coordination

`Package.swift` pins **SwiftPropertyLaws** at `from: "2.0.0"`. The kit was renamed from SwiftProtocolLaws at v2.0.0 (refactor-only — `ProtocolLawKit`/`ProtoLawCore`/`ProtoLawMacro` → `PropertyLawKit`/`PropertyLawCore`/`PropertyLawMacro`). Pre-rename v1.9.0 added `CommutativeMonoid` + `Group` + `Semilattice` for M8.5 writeouts. Still deferred kit-side: `Ring` (Numeric stays the canonical writeout target per PRD §5.4 row 5), `CommutativeGroup` (M8.4.b.1 emits separate proposals), `Group acting on T` (function-space carrier doesn't fit per-type protocol shape).

## What this repo is

**SwiftInferProperties** — type-directed property inference for Swift. Surfaces idempotence, round-trip pairs, and algebraic-structure (semigroup / monoid / group / semilattice / ring) candidates from function signatures, cross-function pairs, and existing unit tests. All output is human-reviewed; nothing auto-executes.

One-way downstream of [SwiftPropertyLaws](https://github.com/Joseph-Cursio/SwiftPropertyLaws):

```
SwiftInferProperties → SwiftPropertyLaws (PropertyBackend, DerivationStrategist) → swift-property-based
```

## Where to look

| Question | File |
|---|---|
| Product scope, milestones, success criteria | `docs/SwiftInferProperties PRD v1.0.md` (canonical; v0.1–v0.4 retained as historical) |
| Current milestone plan | None open — see "Repository state" above |
| Current perf baseline | `docs/perf-baseline-v1.24.md` (re-measured; prior baselines retained for forensic comparison) |
| Calibration cycle N findings + data | `docs/calibration-cycle-N-findings.md` + `docs/calibration-cycle-N-data/` (cycles 1–21; cycle 10 = v1.13 hoist, no findings doc) |
| Triage rubrics (cycles 6 + 14) | `docs/cycle-6-triage-rubric.md` (canonical per-template criteria) + `docs/cycle-14-triage-rubric.md` (verbatim carry-forward + post-cycle-6 mechanism context supplement) |
| Closed milestone plans | `docs/archive/*.md` |
| PropertyLawKit / PropertyLawMacro source of truth | The SwiftPropertyLaws repo, not this one |

## Design decisions baked into v0.3

These live in the PRD; this is a quick map. Follow them rather than re-litigating.

- **Conservative inference — high precision, low recall.** PRD §3.5. When in doubt, default to fewer suggestions.
- **Opt-in, human-reviewed output.** Never auto-applies/executes/commits. Even CI mode (PRD §9) emits warnings, not failures.
- **Avoid the Daikon trap.** If calibration shows too many suggestions, raise thresholds — don't add filters on top.
- **Three v1 contributions, one v1.1.** TemplateEngine + RefactorBridge + TestLifter ship in v1; SemanticIndex + Constraint Engine + Domain Template Packs + IDE integration + Semantic Linting bridge are PRD §20 v1.1+.
- **Explainability is a first-class output.** Every suggestion ships both "why suggested" and "why this might be wrong." PRD §4.5.
- **Generator inference delegates to SwiftPropertyLaws.** Call `DerivationStrategist`; don't reimplement. PRD §11.

## Build & test

- `swift package clean && swift test` (per global `~/CLAUDE.md`) on session start.
- Skeleton expects `../SwiftPropertyLaws` as a sibling checkout. CI checks both repos out side-by-side.
- SwiftLint config at `.swiftlint.yml`; `swiftlint lint --quiet` should be silent.
