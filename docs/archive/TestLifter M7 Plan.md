# TestLifter M7 — Counter-Signal Scanning (Plan)

**Supersedes:** PRD v0.4 §7.9 row M7 ("Counter-signal scanning across test target") + the standing TestLifter M2 / M5 plan deferrals ("Counter-signal scanning — TestLifter M7"; "non-deterministic body in mock-synthesis suppression — TestLifter M7").

## What M7 ships (PRD v0.4 §7.9 row M7 + §4.1 + §4.4)

PRD §4.1 lists "Counter-signal: asymmetric assertion" with weight `-25`: "TestLifter found an explicitly asymmetric assertion contradicting a candidate symmetric property in any test." This is the v1 counter-signal scanning surface. Today TestLifter's six detectors (M1–M5) only fire on POSITIVE-form assertions (`==`, `<=`, etc.); negative-form assertions (`XCTAssertNotEqual`, `!=`, `XCTAssertGreaterThan` after a `<` precondition) are silently ignored. M7 adds the negative-form pass and threads its output into the discover pipeline alongside the existing positive cross-validation seam.

PRD §3.5 + §4.4 conservative-inference principle drives the second M7 piece: when `MockGeneratorSynthesizer` observes a constructor's test fixtures pass non-deterministic literals (`Date()`, `UUID()`, `Random.next()`, etc.), the mock-inferred generator MUST NOT fire — emitting a `Gen<T>` that produces a constant `Date()` value defeats the purpose of property testing. M7 adds the non-determinism filter to the M4.3 mock-synthesis path.

Concretely TestLifter M7 ships:

1. **Asymmetric-assertion counter-signal detector.** A new pass that scans the test target for negative-form assertions matching any of the six TestLifter patterns:
   - `XCTAssertNotEqual(f(a, b), f(b, a))` / `#expect(f(a, b) != f(b, a))` → vetoes commutativity for `f`.
   - `XCTAssertNotEqual(f(f(x)), f(x))` / `#expect(...)` → vetoes idempotence for `f`.
   - `XCTAssertNotEqual(decode(encode(x)), x)` / `#expect(...)` → vetoes round-trip for the `(encode, decode)` pair.
   - `XCTAssertGreaterThan(f(a), f(b))` with `a < b` precondition → vetoes monotonicity for `f` (anti-monotonicity).
   - `XCTAssertNotEqual(f(xs).count, xs.count)` / `#expect(...)` → vetoes count-invariance for `f`.
   - `XCTAssertNotEqual(xs.reduce(s, op), xs.reversed().reduce(s, op))` / `#expect(...)` → vetoes reduce-equivalence for `op`.
   - Each detection produces a `LiftedCounterSignal` keyed on the same `CrossValidationKey` shape the positive detectors use (so the seam can match by template + callee).

2. **Counter-signal seam in `TemplateRegistry.discover`.** Parallel to the existing `crossValidationFromTestLifter: Set<CrossValidationKey>` parameter (which adds `+20`), a new `counterSignalsFromTestLifter: Set<CrossValidationKey>` parameter that adds `-25` to TE-side suggestions whose key matches. Lifted-side suggestions whose key matches a counter-signal are also filtered (a counter-signal explicitly says "this property does NOT hold"; the lifted-side claim should be suppressed entirely, not just penalized).

3. **Non-determinism suppression in mock-inference.** Extend `MockGeneratorSynthesizer.synthesize(typeName:record:)` to inspect each construction record's `observedLiterals` for non-deterministic API calls (`Date()`, `Date.now`, `UUID()`, `Random.next()`, etc. — same curated list as `BodySignalVisitor.nonDeterministicAPIs`). If any position's observed literals contain a non-deterministic call, return `nil` (suppress mock-inference for that type). The `LiftedSuggestionPipeline.applyMockInferredFallback(...)` falls through to `.notYetComputed` for those types, which the existing M3.3 path renders as `?.gen()` — non-compiling so the user sees the gap explicitly (PRD §16 #4 invariant preserved).

The non-goals — explicitly out of scope for M7, reaffirmed:

- **`swift-infer convert-counterexample`** — TestLifter M8.
- **Expanded outputs** (inferred preconditions, inferred domains, equivalence-class detection) — TestLifter M9.
- **Marker-binding precision** for counter-signals (PRD §7.5 future-work bind-to-decl) — out of v1.
- **Counter-signal explainability lines** beyond the existing PRD §4.5 block surface — the existing block already supports per-signal detail strings (`Signal.detail`), so M7 just adds entries for the new signal kind.

### Important scope clarifications

- **Asymmetric-assertion shapes are MIRRORS of the M1+M2+M5 positive shapes.** Each of the six positive detectors (round-trip / idempotence / commutativity / monotonicity / count-invariance / reduce-equivalence) has a natural negative form. M7 doesn't invent new shape vocabulary — it adds `XCTAssertNotEqual` / `!=` / `XCTAssertGreaterThan` as an alternative top-level assertion kind for the existing six pattern bodies.

- **One detector or six?** The cleanest design is ONE `AsymmetricAssertionDetector` that dispatches by the negative-assertion kind it sees, with the same per-shape extraction logic each positive detector already implements. Reuses the existing `Slicer` output and the existing `AssertionInvocation` surface (extended with `xctAssertNotEqual` + `xctAssertGreaterThan` + `xctAssertGreaterThanOrEqual` kinds).

- **Counter-signal vs cross-validation suppression.** The existing M3.2 cross-validation suppression filters lifted suggestions whose key matches a TE-side suggestion (avoids double-emit). The new M7 counter-signal pass is DIFFERENT — it filters lifted suggestions whose key matches a NEGATIVE assertion in the test corpus (explicit veto). Both filters can fire; the order is suppression-then-counter-signal so the more specific case (cross-validation match) takes precedence.

- **Score floor.** The PRD §4.1 row says `-25`. With the existing tier mapping (Possible 20–39 / Likely 40–69 / Strong 70+), a -25 counter-signal on a Likely-tier suggestion (~50 score) drops it to ~25 → Possible (hidden by default). On a Strong-tier suggestion (~80 score) it drops to ~55 → Likely (still visible). This matches the PRD's intent: counter-signals reduce confidence, but a strong signature signal can outweigh one negative test if the user is sure.

- **Veto vs penalty for the lifted side.** PRD §4.1 lists asymmetric-assertion as `-25` (penalty). For the LIFTED side, where the only score signal is `+50` testBodyPattern, applying `-25` would drop it to `+25` → Possible tier. M7 takes the stronger posture: if the user has explicitly asserted the property does NOT hold, the lifted suggestion is suppressed entirely (not just demoted to Possible) — the test author's negative assertion is dispositive. The `-25` weight remains for the TE-side path where the suggestion has additional structural signals to outweigh the counter.

## Sub-milestone breakdown

| Sub | Scope | Why this order |
|---|---|---|
| **M7.0** | **`AsymmetricAssertionDetector` + counter-signal seam.** New `Sources/SwiftInferTestLifter/AsymmetricAssertionDetector.swift`. Public entry: `static func detect(in slice: SlicedTestBody) -> [LiftedCounterSignal]`. Recognizes the negative-form mirror of each of the six positive shapes. Slicer extension: `AssertionInvocation.Kind` adds `.xctAssertNotEqual`, `.xctAssertGreaterThan`, `.xctAssertGreaterThanOrEqual`. New `LiftedCounterSignal` struct in `LiftedSuggestion.swift` carrying `templateName: String + crossValidationKey: CrossValidationKey + detail: String + sourceLocation: SourceLocation`. New `TestLifter.discover` collection of `[LiftedCounterSignal]` alongside `[LiftedSuggestion]` — sixth-detector loop. New `Artifacts.counterSignalKeys: Set<CrossValidationKey>` derived from the counter signals. New `crossValidationFromTestLifter` companion parameter `counterSignalsFromTestLifter: Set<CrossValidationKey>` on `TemplateRegistry.discover` / `discoverArtifacts` — applies `-25` Signal of kind `.counterSignal` (new SignalKind case) to matching TE-side suggestions. `Discover+Pipeline.collectVisibleSuggestions` threads the artifacts.counterSignalKeys through; lifted-side suggestions whose key matches are filtered out (the counter-signal is dispositive on the lifted side). **Acceptance:** new `AsymmetricAssertionDetectorTests` covers the six negative-form shapes (one per pattern) + the obvious negative cases (positive assertions don't fire; tautology rejected; mismatched callees rejected). New `TestLifterCounterSignalSeamTests` integration tests verify (i) -25 lands on TE-side matching suggestions; (ii) lifted-side matching suggestions are filtered; (iii) existing +20 cross-validation seam coexists (a positive test for `f(a, b) == f(b, a)` AND a negative test for `g(a, b) != g(b, a)` produces +20 on the f-suggestion AND -25 on the g-suggestion, no cross-contamination). | First piece — establishes the negative-form vocabulary + the seam contract. M7.1 (mock suppression) is independent but uses the same non-determinism plumbing M7.0 doesn't touch. |
| **M7.1** | **Non-determinism suppression in mock-inference.** Extend `MockGeneratorSynthesizer.synthesize(typeName:record:)` to inspect each construction record's `observedLiterals` for non-deterministic API calls. New `MockGeneratorSynthesizer.containsNonDeterministicLiteral(in:)` private helper — same curated list as `BodySignalVisitor.nonDeterministicAPIs` (`Date()`, `Date.now`, `UUID()`, `Random.next()`, `URLSession`, etc.). When any position's observed literals match, return `nil` (suppress mock-inference). `LiftedSuggestionPipeline.applyMockInferredFallback(...)` falls through to `.notYetComputed`; the existing M3.3 path renders `?.gen()` so the user sees the gap explicitly. **Acceptance:** new `MockNonDeterminismSuppressionTests` covers (i) a `Doc(timestamp: Date(), id: UUID())` construction record with ≥3 sites does NOT produce a mock generator; (ii) a `Money(amount: 100, currency: "USD")` (literal-only) record DOES produce a mock generator (M4.3 baseline preserved); (iii) mixed: `Doc(timestamp: Date(), title: "fixed")` suppresses (any non-det literal in any position vetoes); (iv) under-threshold + non-det also suppresses (no spurious lift from the suppression rule itself). | Independent of M7.0 — different code path. Sequenced second so the M7.0 detector tests stay focused. |
| **M7.2** | **Validation suite.** Adds (a) **§13 perf re-check** — extend `TestLifterPerformanceTests` synthetic corpus to include a few negative-form assertions per file; assert the discover pass still completes in < 3s wall (M7.0 adds one more detector per slice; M7.1 adds the literal-scan inside synthesize); (b) **§16 #1 hard-guarantee re-check** — `TestLifterHardGuaranteeTests` extension confirms M7's counter-signal pass doesn't write to source files; (c) **§15 detection-non-throwing fuzz extension** — extend `SlicerFuzzTests` from 6 detectors to 7 (adds `AsymmetricAssertionDetector`); (d) **end-to-end counter-signal integration** — new `TestLifterCounterSignalSuppressionTests` confirms a real CLI-style fixture with both Sources/ + Tests/ surfaces a counter-signal-suppressed suggestion correctly through the full pipeline; (e) **non-determinism mock-suppression coverage** — extend `MockSynthesisCoverageTests` with the `Date()` / `UUID()` cases. | Validation, not new code. Closes the M7 acceptance bar. |

## M7 acceptance bar

Mirroring PRD §7.9 + §4.1 + the v0.4 §5.8 acceptance-bar pattern + the M1 / M2 / M3 / M4 / M5 / M6 cadence, M7 is not done until:

a. **`AsymmetricAssertionDetector` recognizes negative-form mirrors of all six positive detectors** — round-trip / idempotence / commutativity / monotonicity / count-invariance / reduce-equivalence each have a corresponding negative-form shape that `detect(in:)` surfaces.

b. **`TemplateRegistry.discover(counterSignalsFromTestLifter:)` applies `-25 .counterSignal` to TE-side matching suggestions.** The Score's running total drops by 25; `Score.signals` carries the new entry; explainability surfaces it as a "Counter-signal: asymmetric assertion" line.

c. **Lifted-side suggestions whose key matches a counter-signal are filtered out of the visible stream.** A user's explicit negative assertion is dispositive — the lifted-only path doesn't surface a freestanding suggestion the test bodies actively contradict.

d. **Existing `+20` cross-validation seam coexists.** A positive test in one method + a negative test in another method on different callees produce the matching positive and counter signals independently — no cross-contamination.

e. **`MockGeneratorSynthesizer` returns `nil` for types whose construction records contain non-deterministic literals.** `Date()` / `UUID()` / `Random.next()` etc. in any observed-literal position vetoes mock inference for that type; the lifted-side promotion falls through to `?.gen()` (PRD §16 #4 invariant preserved — non-compiling stub forces user attention).

f. **§13 100-test-file perf budget still holds** with M7.0 + M7.1 active. The added work (one more detector pass + literal-scan inside synthesize) is sub-millisecond per file.

g. **§16 #1 hard guarantee preserved** — M7's counter-signal pass + non-determinism filter add zero source-tree writes.

h. **`Package.swift` stays at `from: "1.9.0"`** — no kit-side coordination needed for M7.

## Out of scope for M7 (re-stated for clarity)

- **`swift-infer convert-counterexample`** — TestLifter M8.
- **Expanded outputs** — TestLifter M9.
- **Marker-binding precision** — out of v1.
- **Counter-signal CLI flags** (e.g. `--show-suppressed-by-counter`) — v1.1+ per PRD §16 #6 `--show-suppressed` scoping.
- **`Signal.detail` localization** — out of v1.
- **Cross-repo coordination with SwiftProtocolLaws.** No kit-side changes for TestLifter M7.

## Open decisions to make in-flight

1. **Lifted-side counter-signal handling: filter or demote?** Default proposal: filter (suppress entirely). The user's explicit negative assertion is dispositive — surfacing a demoted-but-visible Possible-tier lifted suggestion the user has explicitly contradicted would be confusing. Reversible if real users want demotion. **Default: (a) filter the lifted side; demote the TE side.**

2. **Counter-signal score weight: `-25` exact or `-25..-50`?** PRD §4.1 specifies `-25` literal. Default proposal: use `-25` everywhere; do not vary by template. Avoids fan-out in the calibration table. **Default: (a) `-25` literal.**

3. **Asymmetric monotonicity: detect `XCTAssertGreaterThan(f(a), f(b))` after `a < b` precondition only, or also detect `XCTAssertLessThanOrEqual(f(b), f(a))`?** Both are anti-monotonicity claims. Default proposal: detect only the canonical `<` precondition + `>` result form (mirror of M5.1's positive shape with `>` substituted). The reversed-arg form `XCTAssertLessThanOrEqual(f(b), f(a))` is M5.1's "reversed argument order" shape that's already rejected as out-of-scope on the positive side; mirroring that rejection here keeps symmetry. **Default: (a) `<` precondition + `>` result only.**

4. **Non-determinism literal scan: which literals?** PRD §3.5 + Appendix B.3 list `Date()`, `Date.now`, `UUID()`, `Random.next()`, `URLSession`. The existing `BodySignalVisitor.nonDeterministicAPIs` curated list IS the canonical source. M7.1 reuses it verbatim. **Default: (a) reuse the production-side list verbatim.**

5. **Ordering: counter-signal pass before or after the cross-validation pass in `TemplateRegistry.discover`?** Default proposal: AFTER. Cross-validation `+20` lands first; counter-signal `-25` lands second. A suggestion that's both cross-validated AND counter-signaled lands at base+20-25 = base-5, which preserves the relative weighting (cross-validation < counter-signal in absolute terms). The CV-then-CS ordering also matches the order detectors run today. **Default: (a) CV first, CS after.**

## New dependencies introduced in M7

None. All work is pure SwiftInferProperties internal — `Slicer`, `AssertionInvocation`, `Score`, `Signal`, `SignalKind`, `MockGeneratorSynthesizer`, `BodySignalVisitor` are all existing modules. `Package.swift` stays at `from: "1.9.0"`.

## Target layout impact

Three new source files:
- `Sources/SwiftInferTestLifter/AsymmetricAssertionDetector.swift` (M7.0)
- `Sources/SwiftInferTestLifter/LiftedCounterSignal.swift` — new struct + factories (M7.0)
- (No new file for M7.1; the change is internal to `MockGeneratorSynthesizer`.)

Three existing source files modified:
- `Sources/SwiftInferTestLifter/Slicer.swift` — `AssertionInvocation.Kind` + 3 new cases.
- `Sources/SwiftInferTestLifter/TestLifter.swift` — discover loop calls the seventh detector.
- `Sources/SwiftInferTemplates/SwiftInferTemplates.swift` — `discover` / `discoverArtifacts` accept the new `counterSignalsFromTestLifter` parameter.
- `Sources/SwiftInferTemplates/TemplateRegistry+CrossValidation.swift` (or a new `+CounterSignal.swift`) — applies the `-25` signal.
- `Sources/SwiftInferCLI/Discover+Pipeline.swift` — threads the counter-signal keys + filters lifted-side matches.
- `Sources/SwiftInferTestLifter/MockGeneratorSynthesizer.swift` — non-determinism filter.

Test files:
- `Tests/SwiftInferTestLifterTests/AsymmetricAssertionDetectorTests.swift` (M7.0)
- `Tests/SwiftInferIntegrationTests/TestLifterCounterSignalSeamTests.swift` (M7.0)
- `Tests/SwiftInferTestLifterTests/MockNonDeterminismSuppressionTests.swift` (M7.1)
- `Tests/SwiftInferIntegrationTests/TestLifterCounterSignalSuppressionTests.swift` (M7.2)

## Closes after M7 ships

After M7, TestLifter's detector surface is symmetric: every positive pattern has a corresponding negative pattern that vetoes the candidate suggestion. Users who write tests that explicitly contradict a property no longer get spurious lifted suggestions; users whose constructor fixtures use `Date()` / `UUID()` no longer get mock-inferred generators that defeat the purpose of property testing. PRD §7.9 row M7 closes; the "trust is everything" v0.3 design tenet (PRD §17 preamble) is operationalized for the test-side surface.

The remaining TestLifter milestones (M8 convert-counterexample, M9 expanded outputs) ship on top of this surface; neither requires widening the detector layer M7 closes.
