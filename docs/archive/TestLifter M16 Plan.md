# TestLifter M16 — General Consumer-Producer Chain Detection (Plan)

**Supersedes:** `docs/archive/TestLifter M10 Plan.md` "Out of scope" §, item: *"General consumer-producer chain detection (Option A). If `validate(s)` is always tested against `format(...)` output and the pair isn't a round-trip — no hint emits. Future v1.x M10.1."* M16 is that v1.x M10.1 expansion.

## v1.x trajectory framing

The CLAUDE.md "open trajectory" lists "general consumer-producer chain detection" as a SemanticIndex-independent narrow follow-up. The other open items are SemanticIndex-blocked (multi-predicate equivalence classes from M13 axis 3, cross-target enum coverage from M14, cross-test data-flow correlation). M16 is the last narrow follow-up that's SemanticIndex-independent — after M16, the §7.8 trio is **fully closed** for the v1.x scanner shape, and the natural next pivot is either a v1.3 release cut or the multi-month PRD §20 SemanticIndex platform work.

Three reasons M16 is cleanly separable:

1. **Corpus-wide aggregation already in place.** M10.3 already built `DomainCorpusScanner.mergeCallSites(...)` which produces a corpus-wide `[String: [DomainCallSite]]` keyed by consumer-function name. M10's pipeline only consumes this map filtered to M5 round-trip pairs; M16 just lifts that filter (with a different precision anchor).

2. **Data model already forward-compatible.** Per M10 plan OD #5, `DomainHint.producerName` is a distinct field "reserved for the future v1.1+ Option A expansion (general consumer-producer chain detection) so it can populate it for non-round-trip pairs without a model migration." M16 is that expansion. The data-model lift is a single additive `HintOrigin` field.

3. **Veto checks transfer verbatim.** M10's `ProducerVetoReason` cases (throws / async / multi-arg / non-generatable arg) all apply to non-round-trip producers identically. The `DomainInferrer.computeVeto(...)` helper is reused as-is.

Opening this plan does NOT pull cross-test data-flow correlation into scope. M16 stays intra-test (matching M10's narrowed scope). Cross-test correlation is a separate future v1.x deferred follow-up.

## Scope-narrowing decision: comment-only standalone advisory + corpus-wide homogeneity

PRD §7.8 second example, generalized: *"When tests for `validate(s)` only pass strings produced by `format(...)`, TestLifter could infer that `validate`'s domain is 'format output' rather than 'all `String`'."* Where M10 narrowed this to the round-trip-pair case (every reverse-side site is forward's output), M16 widens to **any** (consumer, producer) chain meeting a precision anchor.

The key scope-narrowing question for M16 — the same question M10's plan flagged: *"which (consumer, producer) chains in the corpus are real-vs-coincidental?"* — gets the following narrow answer:

**A (consumer, producer) chain qualifies for M16 if and only if:**

1. **Threshold:** consumer is observed on `≥ 3` test sites (mirrors M4.3 / M9 / M10).
2. **Homogeneity:** every site, post-identifier-resolution, classifies as `.callOutput(producerName: P)` for the **same** P. One outlier kills the chain (PRD §3.5 conservative bias).
3. **Producer-existence:** P resolves to a `FunctionSummary` from the source target's scanned function set. Stdlib initializers (`String("hello")`, `Int(s)`) and unknown identifiers fail this check.
4. **Type-alignment:** `producerSummary.returnTypeName == consumer's first-arg-type-name`. The corpus showing `validate(format(t))` only qualifies if `format(t)` returns `validate`'s argument type. Avoids false-positives where the trailing-identifier classification matches but the types don't.
5. **Anti-double-fire with M10:** no M5 round-trip pair `(forwardName: P, reverseName: consumer)` exists. M10 owns the round-trip case; M16 stays out of its lane.

**M16 ships:**

- **Comment-only standalone advisory.** No generator override (M10's territory; M16 inherits the M10 plan's "generator override is round-trip-pair-only" invariant). Writeout to `Tests/Generated/SwiftInfer/consumer-producer/<consumer>_<producer>.swift` on accept (mirrors M11's equivalence-class writeout).
- **`Tier.advisory` routing.** New advisory suggestions enter the discover stream with the M11-introduced advisory tier; the renderer dispatches on `templateName == "consumer-producer-chain"` (mirrors M11's "equivalence-class" dispatch).
- **All four producer-veto checks reused verbatim.** Throws / async / multi-arg / non-generatable surface as advisory comments with the veto reason in the writeout (no behavior difference from M10's veto rendering).

**M16 explicitly defers:**

- **Cross-test data-flow correlation.** A `let x = format(t)` in `testA` and `validate(x)` in `testB` doesn't correlate. Resolution stays intra-test-body. Same posture as M10's "Out of scope" section. Future v1.x narrow follow-up.
- **Multi-producer disambiguation suggestions.** When the corpus has `validate(formatJSON(t))` AND `validate(formatXML(t))` sites, homogeneity fails by definition (different P at different sites) and no hint fires. Future Option-A-deeper expansion could surface "validate's domain is `formatJSON ∪ formatXML` output" — out of M16 scope, conservative posture.
- **Producer-side property derivation.** "Tests of `format` always feed `validate`; consider testing `validate(format(t))` directly" — a derived property test. M16 surfaces the chain observation; deriving runnable properties from it is a future template extension.
- **Generator override for non-round-trip chains.** Even when veto checks pass, M16 stays comment-only. Generator override remains M10's exclusive surface (preserves the §16 #1 "all output is opt-in and human-reviewed" posture without doubling override surface area).
- **Counter-signal / suppression integration.** M7's counter-signal scanner doesn't know about consumer-producer chains; no `-25` suppression for asymmetric assertions on a chain's consumer. Future expansion if real corpora show value.
- **Cross-validation against TemplateEngine score.** Same posture as M9 / M10 — chains are advisory only, no score change to other suggestions.

Three reasons this scope is right:

1. **PRD §3.5 conservative-engine alignment.** The five-fold criterion (threshold + homogeneity + producer-existence + type-alignment + anti-double-fire) produces high-confidence chains. False positives on a domain advisory mislead users into writing property tests that misrepresent their corpus.

2. **No new infrastructure needed.** Corpus aggregation (M10.3), identifier resolution (M10.3), `DomainHint` data model (M10.0), `ProducerVetoReason` (M10.0), `Tier.advisory` (M11.0), advisory dispatch in the renderer (M11.2) — all already in place. M16 adds one new detector + one new pipeline arm + one new renderer arm.

3. **Closes the §7.8 trio.** After M16, the trio's three examples have shipped narrow scopes. The remaining narrow follow-ups are either SemanticIndex-blocked (M12 / multi-predicate axis 3 / M14 cross-target / cross-test data-flow) or release-cut work (v1.3). The v1.x trajectory pivots cleanly to v2.x SemanticIndex platform work.

## What M16 ships

Building on the M10 + M11 substrate:

1. **`HintOrigin` extension** (`SwiftInferCore/DomainHint.swift`):
   - `case roundTripPair` — M10's existing surface. Default for the existing `DomainHint(...)` initializer (additive, back-compat).
   - `case consumerProducerChain` — M16's new surface. Set by the M16.1 detector.
   - `DomainHint.origin: HintOrigin` field with default `.roundTripPair` — every M10 call site stays correct without modification.

2. **`ConsumerProducerChainDetector`** (`SwiftInferTestLifter/ConsumerProducerChainDetector.swift`, new):
   - Pure-function pass. Inputs: corpus-wide `[String: [DomainCallSite]]` (from `DomainCorpusScanner.mergeCallSites`), per-slice `[String: ArgumentClassification]` setup-binding maps, `[String: FunctionSummary]` producer-summary lookup, `[RoundTripPair]` known M5 pairs (for anti-double-fire), `(typeName) -> Bool` producer-arg-generatable predicate (decoupled per M10's pattern).
   - For each consumer in the corpus map, applies the five-criterion narrow scope (threshold + homogeneity + producer-existence + type-alignment + anti-double-fire) + the four veto checks. Returns `[DomainHint]` (one per qualifying chain; empty when none).

3. **`LiftedSuggestionPipeline` arm** (`SwiftInferCLI/LiftedSuggestionPipeline.swift`, extended):
   - After the M10 round-trip-pair pass, invokes `ConsumerProducerChainDetector.detect(...)` once per corpus-discovery run. Each returned `DomainHint` becomes a `Tier.advisory` `LiftedSuggestion` with `templateName == "consumer-producer-chain"` and a synthetic `Score` whose `advisorySignals` slot carries the chain's site count + homogeneity provenance.
   - Suggestions enter the existing M11 advisory routing path verbatim (no new triage / accept logic needed).

4. **Accept-flow renderer arm** (`SwiftInferTemplates/LiftedTestEmitter+Generators.swift`, extended):
   - Dispatches on `templateName == "consumer-producer-chain"` ahead of the runnable-stub switch (mirrors M11's "equivalence-class" dispatch).
   - Writes a comment-only documentation block to `Tests/Generated/SwiftInfer/consumer-producer/<consumer>_<producer>.swift`. The block names: the chain (`<consumer> ← <producer>`), the site count, the producer-veto reason if any, and a `// Inferred domain (consumer-producer chain):` provenance line. No runnable property test; the user reads + decides whether to write one.

5. **Validation suite** (`Tests/SwiftInferTestLifterTests/ConsumerProducerChainDetectorTests.swift` + `Tests/SwiftInferIntegrationTests/ConsumerProducerChainRenderingTests.swift`, both new):
   - Per-criterion unit coverage (threshold / homogeneity / producer-existence / type-alignment / anti-double-fire / each veto reason) + end-to-end fixture exercising the full pipeline.

6. **Public-API back-compat.** The `HintOrigin` field on `DomainHint` is additive with a default value; existing M10 call sites continue to compile without modification. `ConsumerProducerChainDetector` is a new public type; introducing it doesn't break any existing surface.

## Sub-milestone breakdown

| Sub | Scope | Why this order |
|---|---|---|
| **M16.0** | **`HintOrigin` data-model extension.** Add `HintOrigin` enum to `SwiftInferCore`. Add `DomainHint.origin: HintOrigin` field with default `.roundTripPair`. Audit existing M10 call sites — confirm all are default-init or named-init compatible. **Acceptance:** existing `DomainHintTests` stays green after the additive field; new `DomainHintOriginTests` covers Codable round-trip + Equatable conformance for both origin cases. | Foundation. Pure data-model addition; no behavior change. Mirrors M9.0 / M10.0 / M13.0 / M15.0 cadence. |
| **M16.1** | **`ConsumerProducerChainDetector` analysis pass.** New `Sources/SwiftInferTestLifter/ConsumerProducerChainDetector.swift`. Pure function over the corpus-aggregated maps + producer summaries + known M5 pairs. Applies the five-criterion narrow scope and returns `[DomainHint]` with `origin: .consumerProducerChain`. **Acceptance:** new `ConsumerProducerChainDetectorTests` covers each criterion in isolation — homogeneous chain → emit; mixed-producer chain → no emit; under-threshold → no emit; producer-not-in-source-target → no emit; producer-return-type-mismatch → no emit; M5-round-trip-pair-exists → no emit; per-veto-reason cases match M10's posture. | Sequenced after M16.0 because the detector emits hints with the new origin. Independent of M16.2 (pure function over already-aggregated input). |
| **M16.2** | **Pipeline wiring + Tier.advisory routing.** Extend `LiftedSuggestionPipeline.applyMockInferredFallback(...)` (or a sibling pass) to invoke `ConsumerProducerChainDetector.detect(...)` once per discover run. Each returned hint becomes a `Tier.advisory` `LiftedSuggestion` with `templateName == "consumer-producer-chain"`. Suggestions enter the existing M11 advisory routing path verbatim. **Acceptance:** new `LiftedSuggestionPipeline+ConsumerProducerChainTests` covers the pipeline-arm contract — end-to-end fixture corpus where `validate(format(t))` × 3 sites surfaces a `Tier.advisory` suggestion with the correct templateName + synthetic score. | Sequenced after M16.1 because the pipeline arm consumes the detector's output. Reuses M11's advisory tier + score infrastructure verbatim. |
| **M16.3** | **Accept-flow renderer + end-to-end integration.** Extend `LiftedTestEmitter+Generators` with a "consumer-producer-chain" dispatch arm ahead of the runnable-stub switch (mirrors M11's "equivalence-class" arm). Writes a comment-only documentation block to `Tests/Generated/SwiftInfer/consumer-producer/<consumer>_<producer>.swift` on accept. Validation: §13 perf re-check (extends `TestLifterPerformanceTests` to confirm the new corpus-wide pass adds ≤ a few ms per discover run); §16 #1 hard-guarantee re-check (writes only to allowlisted path); end-to-end integration test under `SwiftInferIntegrationTests`. **Acceptance:** new `ConsumerProducerChainRenderingTests` covers the end-to-end accept path — synthetic 3-test fixture with `validate(format(t))` × 3 sites surfaces an advisory writeout with the chain naming + site count + (when applicable) veto reason. | Closes the M16 acceptance bar end-to-end. |

## M16 acceptance bar

Mirroring PRD §7.8 + §7.9 + the M9 / M10 / M11 / M13 / M14 / M15 cadence, M16 is not done until:

a. **`HintOrigin` carries two cases** (`.roundTripPair`, `.consumerProducerChain`) and `DomainHint.origin: HintOrigin` is additively populated with default `.roundTripPair` for back-compat.

b. **`ConsumerProducerChainDetector.detect(...)` enforces all five criteria:**
   - `≥ 3` site threshold (mirrors M4.3 / M9 / M10).
   - Homogeneity post-identifier-resolution (one outlier kills, per PRD §3.5).
   - Producer P resolves to a `FunctionSummary` from the source target.
   - `producerSummary.returnTypeName == consumerFirstArgTypeName` (type alignment).
   - No M5 round-trip pair `(forwardName: P, reverseName: consumer)` exists (anti-double-fire with M10).

c. **All four producer-veto checks fire correctly** and surface in the rendered comment (throws / async / multi-arg / non-generatable). Same priority order as M10 (`computeVeto` reused).

d. **`Tier.advisory` routing reuses the M11 advisory pipeline.** No new triage UX; suggestions appear in the discover stream with `[Advisory]` tier rendering.

e. **Renderer dispatches on `templateName == "consumer-producer-chain"`** ahead of the runnable-stub switch and writes a comment-only documentation block to `Tests/Generated/SwiftInfer/consumer-producer/<consumer>_<producer>.swift`.

f. **End-to-end integration test surfaces the advisory writeout** through the M11.2 routing + M11.2-shaped accept flow on a fixture corpus exercising `validate(format(t))` × 3 sites.

g. **Existing M9 / M10 / M11 / M13 / M14 / M15 test suites stay green.** The new `HintOrigin` field is additive; no existing M10 path changes. Anti-double-fire ensures M16 never re-fires on M10's round-trip-pair surface.

h. **§13 100-test-file budget holds.** `ConsumerProducerChainDetector` is one corpus-wide pass over the already-aggregated `[String: [DomainCallSite]]` map; per-consumer work is O(siteCount + producerSummaryLookup). Same big-O as M10's per-pair pass; budget already absorbs M10's overhead.

i. **§13 row 4 memory ceiling holds** — no new persistent allocations beyond the `[DomainHint]` advisory list (small, bounded by qualifying chain count).

j. **§16 #1 hard guarantee preserved** — M16 writes only to `Tests/Generated/SwiftInfer/consumer-producer/` (allowlisted under the M11 "consumer-producer" sibling slot).

k. **§14 + §19 privacy / no-network guarantee preserved** — M16 is a pure-function analysis pass; no networking-API touches.

l. **§15 non-throwing fuzz harness extended.** The detector must not crash on malformed corpus inputs, empty corpus maps, or producer-summary maps with missing entries.

m. **`Package.swift` stays at `from: "2.0.0"`** — no kit-side coordination needed for M16.

## Out of scope for M16 (re-stated for clarity)

- **Cross-test data-flow correlation.** Identifier resolution stays intra-slice-body only (matches M10's posture). Future v1.x narrow follow-up.
- **Multi-producer disambiguation.** When `validate` is observed against `formatJSON(t)` AND `formatXML(t)`, homogeneity fails and no hint fires. Future Option-A-deeper expansion.
- **Generator override on non-round-trip chains.** M10 owns the override surface; M16 stays comment-only.
- **Producer-side property derivation.** M16 surfaces the chain observation; deriving runnable properties is template-extension territory.
- **Counter-signal / suppression integration.** M7's surface doesn't know about chains; no `-25` suppression for asymmetric assertions on a chain's consumer.
- **Cross-validation against TemplateEngine score.** Chains stay advisory; no score change to other suggestions.
- **Counterexample-driven chain refinement.** Convert-counterexample (M8) territory.
- **`--show-chains` CLI flag.** v1.1+ per the §16 #6 v1.1+ scoping pattern (same posture as M9's deferred `--show-preconditions` and M10's deferred `--show-domains`).
- **Cross-repo coordination with SwiftPropertyLaws.** No kit-side changes.

## Open decisions to make in-flight

1. **Writeout file naming when `<consumer>_<producer>` collides with an existing `EquivalenceClasses_*` file.** Default proposal: **(a) different directory** (`Tests/Generated/SwiftInfer/consumer-producer/` vs `Tests/Generated/SwiftInfer/equivalence-class/`) — collision is a non-issue at the path level. **Default: (a)** — avoid path-collision concern at the source.

2. **Hint surfacing when both M10 and M16 would fire on the same `(consumer, producer)` pair.** The anti-double-fire criterion (#5) makes M16 skip when M5 has the round-trip pair. But what if M5 surfaced the pair late or M10's domain hint vetoed for a producer reason? Default proposal: **(a) M5-round-trip-pair existence is the binary anti-double-fire signal**, regardless of whether M10's hint fired or vetoed. Rationale: M10 owns the round-trip surface end-to-end; the user accepting/rejecting the round-trip suggestion is the user's call to make about the same chain.

3. **Naming convention for the hint label in the rendered comment.** M10's comment says "reverse's argument was always forward's output across N sites." M16's comment needs a non-round-trip phrasing. Default proposal: **(a) "consumer's argument was always producer's output across N sites — domain narrowing observed"** — explicit + non-template-specific. Alternative: borrow from PRD §7.8 example: "validate was never observed against arbitrary arguments, only producer output." **Default: (a)** — consistent with M10's structural phrasing; differentiation from M10's "reverse"/"forward" makes the renderer diff legible.

4. **Whether to surface advisory-tier signal score for the chain.** M11 surfaces equivalence-class hints with a synthetic `Score(advisorySignals:)` that includes the site count. Default proposal: **(a) mirror M11's pattern** — synthetic score with `advisorySignals: [siteCount]`. Renderer surfaces the count in the documentation block. **Default: (a)** — consistent with M11.

5. **Whether the corpus-wide pass reads from an already-existing pipeline artifact or re-runs.** `LiftedSuggestionPipeline.applyMockInferredFallback(...)` is the natural attach point; the per-slice `DomainCorpusScanner.SliceArtifacts` is already collected per slice. Default proposal: **(a) reuse the existing per-slice artifacts collection** — call `DomainCorpusScanner.mergeCallSites(...)` once on the already-collected artifacts list, pass the merged map into M16.1. No second pass over slices. **Default: (a)** — perf-neutral, single source of truth.

6. **Producer-summary lookup source.** The detector needs `[String: FunctionSummary]` keyed by function name to check producer existence + return-type alignment. The existing pipeline carries `FunctionSummary` per source-side function. Default proposal: **(a) derive the lookup from the existing scanner output** — one pass over the source-side function summaries to build the by-name map. **Default: (a)** — re-uses existing data; no new scanner.

7. **Pre-existing `MockGenerator.preconditionHints` interaction.** M16's writeout is a separate file from any MockGenerator-embedded surface; no interaction. The user reading the consumer's suggestions might see M9 precondition hints AND a sibling consumer-producer-chain advisory file. Default proposal: **(a) both surface independently** — different files, different signals, both live. **Default: (a)** — no interaction concern.

8. **Whether to short-circuit the detector when the corpus has no candidate consumers.** Default proposal: **(a) early return on empty merged map** — perf nicety. **Default: (a)** — single-line guard at function entry.

## New dependencies introduced in M16

None. All work is pure SwiftInferProperties internal — `DomainHint` (already in `SwiftInferCore`), `DomainCorpusScanner` / `ArgumentClassification` / `RoundTripPair` (already in `SwiftInferTestLifter`), `Tier.advisory` (already in `SwiftInferCore`), `LiftedTestEmitter+Generators` advisory-dispatch (already in `SwiftInferTemplates`). `Package.swift` stays at `from: "2.0.0"`.

## Target layout impact

Source files modified:
- `Sources/SwiftInferCore/DomainHint.swift` — add `HintOrigin` + `DomainHint.origin` field with default `.roundTripPair` (M16.0).
- `Sources/SwiftInferCLI/LiftedSuggestionPipeline.swift` — add the M16 detector pass after the M10 pair pass (M16.2).
- `Sources/SwiftInferTemplates/LiftedTestEmitter+Generators.swift` — add the "consumer-producer-chain" dispatch arm (M16.3).

New source files:
- `Sources/SwiftInferTestLifter/ConsumerProducerChainDetector.swift` (M16.1) — pure-function analysis pass.

Test files (new):
- `Tests/SwiftInferCoreTests/DomainHintOriginTests.swift` (M16.0) — model-shape tests.
- `Tests/SwiftInferTestLifterTests/ConsumerProducerChainDetectorTests.swift` (M16.1) — per-criterion + per-veto coverage.
- `Tests/SwiftInferIntegrationTests/ConsumerProducerChainRenderingTests.swift` (M16.3) — end-to-end fixture tests.

Existing `DomainHintTests` + `DomainInferrerTests` + `MockInferredDomainRenderingTests` stay green via the additive `HintOrigin` extension.

## Closes after M16 ships

After M16, the §7.8 trio is **fully closed** for the v1.x scanner shape:

- First example (preconditions) — closed at M9 + M15. Covers all four `ParameterizedValue.Kind` cases (Int / String / Bool / Double) the M4.1 scanner produces.
- Second example (inferred domains) — closed at M10 + M16. M10 covers round-trip-pair narrowing with generator override; M16 covers general consumer-producer chains as comment-only standalone advisories.
- Third example (equivalence classes) — closed at M11 + M13 + M14. Covers three of four Option A axes (multi-marker partitions, N-class detection, same-target enum exhaustiveness annotation).

The remaining open trajectory items are:
- **PRD §20 v1.1+ trajectory** — SemanticIndex (the multi-month platform lift), IDE integration, `swift-infer apply`, `swift-infer metrics`. SemanticIndex unlocks the rest.
- **Multi-predicate equivalence classes** (M13 axis 3) — SemanticIndex-blocked.
- **Cross-target enum coverage** (M14 deferred bit) — SemanticIndex-blocked.
- **Cross-test data-flow correlation** (M10 + M16 deferred) — narrow but complex; was originally deferred independently of SemanticIndex but the natural sequencing is post-SemanticIndex (SemanticIndex's whole-corpus call-graph view subsumes this).
- **v1.3 release** — covers M16 + recalibration patch (`3e2f961`) + any M16.x follow-ups. Release plan, not a milestone.

After M16, the v1.x narrow-follow-up surface is fully exhausted; the next non-release milestone pivots to v2.x (PRD §20 SemanticIndex + downstream platform work).
