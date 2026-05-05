# TestLifter M11 — Equivalence-Class Detection (Plan)

**Supersedes:** PRD v1.0 §7.8 third example + §7.9 row M11 ("Equivalence-class detection — test-method-name partition heuristics for valid/invalid buckets").

## v1.1 trajectory framing

PRD v1.0 §5.8 + §7.9 mark M11 as **Deferred** to v1.1+. M10 opened the v1.1 line by shipping the §7.8 second example (round-trip-pair domain narrowing); M11 ships the **third and final** §7.8 example. After M11, the §7.8 expanded-outputs row is fully closed (preconditions / domains / equivalence-classes all shipped) and the v1.1 line tags.

Opening this plan does NOT pull the rest of v1.1+ scope in — PRD §20 (SemanticIndex, IDE integration, `swift-infer apply`, `swift-infer metrics`) plus the deferred Option A general data-flow tracing from M10 stay deferred. M11 is the single milestone this plan covers.

## Scope-narrowing decision: two-class predicate partitions from a curated marker set

PRD §7.8 third example: *"Tests that group inputs into 'valid' / 'invalid' buckets via parallel construction patterns hint at equivalence classes worth parameterizing the property over."*

The PRD note continues: *"Requires test-method-name partition heuristics that go beyond the M1–M9 detector model."* — i.e. the **fully general** form would cover arbitrary partition labels, N-class partitions (>2), multi-predicate equivalence classes (different functions consistent within each class), and cross-class relation properties. Call this **Option A**.

**This plan ships Option B:** narrow M11 to **two-class predicate equivalence detection from a curated marker set only.** The detector fires only when:

1. Test method names in the parsed corpus carry one of the curated `(positive, negative)` marker pairs (`Valid`/`Invalid` for v1.1 — synonyms deferred per the open decision below).
2. Both buckets reach the `≥ 3` site threshold (mirrors M4.3 / M9 / M10).
3. Every site in the partition invokes the **same** unary predicate function.
4. Polarity is homogeneous within each bucket (positive bucket → asserted true; negative bucket → asserted false).
5. The predicate passes the same producer-veto checks M10 uses (non-throwing, non-async, single-arg, generatable arg type).

Option B mirrors the M9 / M10 narrowing pattern: pick the high-confidence narrow detector, ship it, leave the speculative wider surface for the v1.x trajectory. The general partition surface (arbitrary labels, N-class, multi-predicate, cross-class relations) remains as future v1.x M11.1+.

Three reasons Option B is the right scope:

1. **Matches the PRD example directly.** §7.8 third example specifically names `valid`/`invalid` buckets; M11 ships exactly what the PRD describes, no scope creep.
2. **Conservative-engine alignment (PRD §3.5).** Curated marker set + ≥3 sites per bucket + polarity homogeneity + predicate-shape veto = high precision. Matches the M9 / M10 precision posture exactly.
3. **Closes the §7.8 trio cleanly.** After M11, all three §7.8 examples ship and v1.1 tags with a coherent expanded-outputs story rather than a partial one.

## What M11 ships (PRD v1.0 §7.8 third example, narrowed)

For each `(positiveMarker, negativeMarker)` pair scanned across the parsed test corpus:

1. **`EquivalenceClassMarkerExtractor`** — pure-function pass. Given `[TestMethodSummary]` and a curated marker table, classifies each method's `methodName` into:
   - `.positive(marker: String, predicateCallSite: PredicateCallSite?)` — name carries the positive marker AND the sliced body's terminal assertion is a single predicate call.
   - `.negative(marker: String, predicateCallSite: PredicateCallSite?)` — same, with negative marker.
   - `.none` — name carries no marker, or carries a marker but the body shape rules it out (no terminal assertion, multi-call argument expression, etc.).

   Marker matching is **identifier-token-aware** (camelCase + snake_case): `testValid_simple` and `testIsValidWithPlus` match `Valid`; `testValidate_simple` does NOT (the token continues with `ate`). Both prefix and suffix forms scan-out as long as the token boundary is clean.

2. **`PredicateEquivalenceClassDetector`** — pure-function detector. Given the per-marker partition output of M11.1 + the `[SlicedTestBody]` for those methods, returns an optional `EquivalenceClassHint`:
   - **Threshold:** `≥ 3` sites in the positive bucket AND `≥ 3` sites in the negative bucket. Either-bucket-under-threshold → no hint.
   - **Predicate homogeneity:** every site (across both buckets, post-resolution) calls the **same** unary predicate function name. One outlier (a positive-bucket site that calls a different predicate, or any site whose argument shape doesn't reduce to `predicate(x)`) kills the hint.
   - **Polarity homogeneity:** every positive-bucket site asserts the predicate is `true` (`xctAssertTrue` / `xctAssert(predicate(x))` / `expectMacro(predicate(x))` / `requireMacro(predicate(x))`); every negative-bucket site asserts the predicate is `false` (`xctAssertFalse` — see §"Open decisions" #2 — or `xctAssert(!predicate(x))` / `expectMacro(!predicate(x))` etc.). Mixed polarity within a bucket kills the hint.
   - **Predicate veto:** if the predicate is `throws`, `async`, takes `>1` argument, or its single arg type isn't generatable per the M3+ generator-strategy table → veto generator suggestion (still emit comment-only advisory). Mirrors M10.2's veto rule exactly.

3. **`EquivalenceClassHint` data model** — public struct in `SwiftInferCore`. Fields:
   - `predicateName: String` — the function name common to both buckets.
   - `argTypeName: String` — the type `T` the equivalence-class generators are over.
   - `positiveMarker: String` — the marker text (e.g. `"Valid"`).
   - `negativeMarker: String` — the marker text (e.g. `"Invalid"`).
   - `positiveSiteCount: Int` — `≥ 3`.
   - `negativeSiteCount: Int` — `≥ 3`.
   - `predicateVetoed: Bool` — true when one of the predicate-veto checks fired.
   - `vetoReason: String?` — populated when `predicateVetoed` is true (`"throws"`, `"async"`, `"multi-arg"`, `"non-generatable arg type"`).
   - `suggestedPositiveGenerator: String` — `Gen<T>.filter(predicate)`, pre-computed.
   - `suggestedNegativeGenerator: String` — `Gen<T>.filter { !predicate($0) }`, pre-computed.

4. **`EquivalenceClassSuggestion` — new advisory lifted-suggestion kind.** Distinct from M9 / M10, which decorate `MockGenerator`s on existing constructors / round-trip suggestions. M11's finding isn't tied to any pre-existing template suggestion — it's a corpus-level observation about a predicate. The cleanest fit is therefore a **stand-alone advisory suggestion** that surfaces in the discover stream like any other lifted suggestion:
   - Tier: `Advisory` (a new tier, or reuse `Possible` with a hidden-by-default flag — see §"Open decisions" #3).
   - Score contribution: zero (advisory only, like M9 / M10 hints; no cross-validation against TemplateEngine output).
   - Accept-flow writeout: `Tests/Generated/SwiftInfer/EquivalenceClasses_<predicate>.swift`. The rendered file is **comment-only** — no runnable property body. Rationale: the equivalence-class output is documentation; emitting `forAll(Gen<T>.filter(predicate)) { x in #expect(predicate(x)) }` would be a tautology. The user reads the comment block + authors per-class properties manually.

5. **Pipeline wiring.** `LiftedSuggestionPipeline` invokes `EquivalenceClassMarkerExtractor.extract(...)` once per parsed test target, then `PredicateEquivalenceClassDetector.detect(...)` per `(positive, negative)` partition the extractor surfaces. Each emitted `EquivalenceClassHint` becomes a `LiftedSuggestion` of the new `equivalenceClass` kind in the discover stream.

6. **Validation suite.** §13 perf re-check + §16 #1 hard-guarantee re-check + per-marker / per-veto unit tests + end-to-end integration test on a synthetic Valid/Invalid fixture corpus.

The non-goals — explicitly out of scope for M11, reaffirmed:

- **Arbitrary marker partitions (Option A).** Only the curated `Valid`/`Invalid` pair v1.1 ships. User-extensible vocabulary deferred.
- **N-class partitions (`>2`).** v1.x M11.1+.
- **Multi-predicate equivalence classes.** Different functions consistent within each class — v1.x.
- **Cross-class relation properties.** E.g. "valid + invalid covers `T`'s domain". v1.x.
- **Filter-impractical generator narrowing.** When `Gen<String>.filter(isValid)` would reject 99% of samples, a different generator is needed; out of scope. The user reads the hint and authors a custom Gen.
- **Cross-test-target marker discovery.** Marker scan stays within the configured test target, like M10's intra-test-body scope.
- **Counterexample-driven class refinement.** Convert-counterexample (M8) territory; not extended here.
- **Cross-validation against TemplateEngine score.** M9 + M10 deferred this for hints; M11 inherits the same posture (advisory only, no score change).
- **`--show-equivalence-classes` CLI flag.** v1.1+ per the §16 #6 v1.1+ scoping pattern — same rationale as M9's deferred `--show-preconditions` and M10's deferred `--show-domains`.
- **Runnable property emission on accept.** Comment-only writeout; user authors per-class properties manually.

### Important scope clarifications

- **Detection threshold reuses M4.3 / M9 / M10's `≥ 3 sites`** — but applied per-bucket. A 5-positive + 2-negative partition does NOT emit; both buckets must independently reach threshold.
- **Marker tokens are identifier-aware.** `testValid_simple` / `testIsValidWithPlus` / `testEmail_valid` all match `Valid`; `testValidate_*` does NOT (the marker substring continues into another token). Implementation: tokenize `methodName` on case boundaries + underscores, then exact-match the marker string against any token.
- **PRD §3.5 conservative bias.** Predicate homogeneity + polarity homogeneity + predicate-shape veto: any single failure kills the hint. One mixed-polarity site, one different-predicate site, or a non-unary predicate is enough to suppress.
- **Suggestion-side rendering is purely advisory when vetoed.** Even when the predicate-shape veto fires, the comment line surfaces — the user reads "predicate `isValid` partitions Valid/Invalid across N+M sites, but `isValid` throws so we can't suggest `Gen<T>.filter(isValid)` directly" and decides whether to refactor `isValid` to a non-throwing variant or leave the partition as documentation.
- **No new CLI flags.** M11 surfaces hints automatically through the existing `swift-infer discover` pipeline.

## Sub-milestone breakdown

| Sub | Scope | Why this order |
|---|---|---|
| **M11.0** | **Data model + assertion-kind extension** in `SwiftInferCore` and `SwiftInferTestLifter`. New `Sources/SwiftInferCore/EquivalenceClassHint.swift` (public struct with the fields above). New `LiftedSuggestion` case `equivalenceClass(EquivalenceClassHint)` (or a new `EquivalenceClassSuggestion` peer type — see §"Open decisions" #4). Add `.xctAssertFalse` to `SlicedTestBody.AssertionInvocation.Kind` and teach `Slicer` to recognize it. **Acceptance:** `EquivalenceClassHintTests` covers Equatable + Codable round-trip; `SlicerXCTAssertFalseTests` covers the new assertion kind round-trips through slicing. | Foundation. The new assertion kind is a small refactor that lifts a near-term blocker for M11.1; landing it as part of M11.0 keeps the M11.1 detector pure-function over already-recognized assertion data. |
| **M11.1** | **`EquivalenceClassMarkerExtractor.extract(testMethods:slicedBodies:markerTable:) -> [PartitionCandidate]`** + **`PredicateEquivalenceClassDetector.detect(partition:) -> EquivalenceClassHint?`** — both pure-function passes. New `Sources/SwiftInferTestLifter/EquivalenceClassMarkerExtractor.swift` + `Sources/SwiftInferTestLifter/PredicateEquivalenceClassDetector.swift`. Marker extractor walks `[TestMethodSummary]`, applies identifier-token matching, returns per-predicate partition candidates. Detector consumes a single candidate, applies threshold + predicate homogeneity + polarity homogeneity + predicate-shape veto. Returns `EquivalenceClassHint?`. **Acceptance:** `EquivalenceClassMarkerExtractorTests` covers each marker variant (camelCase prefix, snake_case suffix, embedded marker, `Validate`-style false-positive rejection); `PredicateEquivalenceClassDetectorTests` covers each path — homogeneous valid/invalid corpus → emit; mixed-predicate corpus → no emit; mixed-polarity corpus → no emit; under-threshold (positive or negative) → no emit; throwing predicate → `predicateVetoed: true` hint emitted; multi-arg predicate → `predicateVetoed: true` hint emitted. | Sequenced after M11.0 because both passes consume the new `EquivalenceClassHint` model + the new `xctAssertFalse` assertion kind. The two passes are bundled into one sub-milestone because they share fixtures (the same corpus tests both passes end-to-end). |
| **M11.2** | **Pipeline wiring + accept-flow writeout + validation suite.** Extend `LiftedSuggestionPipeline` to invoke the M11.1 extractor + detector once per parsed test target, emit `EquivalenceClassSuggestion`s into the discover stream. Extend the accept-flow renderer (or add a peer renderer in `SwiftInferTemplates`) to write `Tests/Generated/SwiftInfer/EquivalenceClasses_<predicate>.swift` with the comment-only documentation block on accept. The block lists both buckets, both site counts, the suggested generator expressions, and the veto reason when applicable. Add §13 perf re-check (extend `TestLifterPerformanceTests` with synthetic equivalence-class corpora — N-positive + N-negative test methods sharing a single predicate name); §16 #1 hard-guarantee re-check (M11 writes only to `Tests/Generated/SwiftInfer/`, never to source); §15 fuzz extension (malformed method names, empty bodies, partial-marker substrings); end-to-end integration test under `SwiftInferIntegrationTests`. **Acceptance:** `EquivalenceClassRenderingTests` covers the end-to-end path — synthetic 8-test fixture (4 `testValid_*` + 4 `testInvalid_*` against `isValid`) surfaces the suggestion + accept writes the expected file; throwing-predicate fixture surfaces vetoed variant (comment-only, no generator suggestion in the rendered block). | Sequenced last; closes the M11 acceptance bar. |

## M11 acceptance bar

Mirroring PRD §7.9 + §7.8 + the v1.0 §5.8 acceptance-bar pattern + the M5–M10 cadence, M11 is not done until:

a. **`EquivalenceClassHint` is a public type in `SwiftInferCore`.** A new `LiftedSuggestion` kind (case or peer type per §"Open decisions" #4) carries the hint through the discover stream.

b. **`SlicedTestBody.AssertionInvocation.Kind` includes `.xctAssertFalse`** and `Slicer` recognizes it.

c. **`EquivalenceClassMarkerExtractor.extract(...)` recognizes the curated marker set** (`Valid` / `Invalid` for v1.1) over real `TestMethodSummary` input with identifier-token boundary awareness.

d. **`PredicateEquivalenceClassDetector.detect(...)` enforces both-bucket threshold + predicate homogeneity + polarity homogeneity** before emitting a hint.

e. **`≥ 3` site threshold enforced per-bucket.** Either-bucket-under-threshold inputs produce no hint.

f. **One outlier kills the hint.** PRD §3.5 conservative bias: any non-homogeneous predicate, polarity, or argument-shape site → no emit.

g. **Predicate veto checks fire correctly.** Throwing / async / multi-arg / non-generatable-arg predicate → `predicateVetoed: true` hint (comment-only render); never a generator suggestion.

h. **Pipeline wiring emits `EquivalenceClassSuggestion`s automatically** during the lifted pipeline, once per parsed test target.

i. **Accept-flow renderer writes `Tests/Generated/SwiftInfer/EquivalenceClasses_<predicate>.swift`** with the comment-only documentation block — both bucket counts, both suggested generators (or veto reason), and provenance text matching the M9 / M10 wording style.

j. **§13 100-test-file budget holds with M11.0–M11.2 active.** The added work (per-method marker classification + per-partition homogeneity check) is sub-millisecond per test method; corpus has at most a few partitions in realistic packages.

k. **§16 #1 hard guarantee preserved** — M11 writes only to `Tests/Generated/SwiftInfer/`, never to source; the writeout is gated on user accept.

l. **§15 non-throwing fuzz harness extended.** The marker extractor must not crash on malformed method names, the detector must not crash on empty / single-statement bodies or partial-marker substrings.

m. **`Package.swift` stays at `from: "2.0.0"`** — no kit-side coordination needed for M11.

## Out of scope for M11 (re-stated for clarity)

- **Option A (general partition surface).** Arbitrary marker labels, N-class partitions, multi-predicate equivalence classes, cross-class relation properties. Future v1.x M11.1+.
- **User-extensible marker vocabulary.** Curated `Valid`/`Invalid` only for v1.1; project-extensible synonyms via `.swiftinfer/vocabulary.json` (PRD §4.5) deferred.
- **Filter-impractical generator narrowing.** When the suggested `Gen<T>.filter(predicate)` is rejection-rate-impractical, M11 doesn't synthesize a custom generator.
- **Cross-test-target marker discovery.** Stays within the configured test target.
- **Throwing / async / multi-arg predicate generator suggestion.** Hard veto on the generator string; comment-only fallback with the veto reason.
- **Counterexample-driven class refinement.** Convert-counterexample (M8) territory.
- **Cross-validation against TemplateEngine score.** Inherits the M9 / M10 advisory-only posture.
- **`--show-equivalence-classes` CLI flag.** v1.1+ per the §16 #6 v1.1+ scoping pattern.
- **Runnable property emission on accept.** Comment-only writeout.
- **Cross-repo coordination with SwiftPropertyLaws.** No kit-side changes for M11.

## Open decisions to make in-flight

1. **Marker set: `Valid`/`Invalid` only, or include curated synonyms?** Default proposal: **(a) `Valid`/`Invalid` only for v1.1**. The PRD example specifically names this pair; widening to `Success`/`Failure` / `Accept`/`Reject` / `Pass`/`Fail` doubles the false-positive surface and warrants a separate v1.x marker-table-expansion plan. Reversible if real corpora show value in synonyms.

2. **`xctAssertFalse` as a first-class `AssertionInvocation.Kind` case.** Default proposal: **(a) ADD `.xctAssertFalse` to the enum** in M11.0. The negated form `XCTAssert(!predicate(x))` is fragile to detect via expression-shape inspection alone (`!` could be inside an arbitrary boolean expression), and `XCTAssertFalse` is a standard XCTest API the slicer already misses. Small refactor; no other detector consumes it today but it's a natural pair to `xctAssertTrue`. Alternative: leave the enum alone, parse `XCTAssertFalse` as `xctAssertTrue` with negated polarity — strictly less informative.

3. **`Advisory` tier or hidden-by-default `Possible`?** Default proposal: **(a) introduce a new `Advisory` tier value** in `SwiftInferCore.Tier`. Rationale: M9 + M10 hints are decorative on existing suggestions (no new tier needed); M11 emits a stand-alone suggestion that should be visually distinct in the discover stream — a new tier value (rendered as e.g. `[ADVISORY]` instead of `[STRONG]` / `[POSSIBLE]`) communicates "this is documentation, not a runnable property" clearly. Alternative: reuse `Possible` with a flag — muddies the tier semantics.

4. **`EquivalenceClassSuggestion` as a `LiftedSuggestion` enum case or as a peer type in the suggestion stream?** Default proposal: **(a) new enum case `equivalenceClass(EquivalenceClassHint)` on `LiftedSuggestion`** — keeps the suggestion-stream surface uniform with the existing M1–M7 detector outputs. Peer-type alternative would force every consumer of `[LiftedSuggestion]` to fan out a second collection.

5. **Suggestion writeout filename convention.** Default proposal: **(a) `Tests/Generated/SwiftInfer/EquivalenceClasses_<predicate>.swift`** — predicate name kept verbatim (camelCase). One file per detected equivalence class; if the same predicate fires under multiple marker pairs in the future (Option A territory), the filename gets a marker-pair suffix. Alternative: snake_case filename — inconsistent with the rest of the writeout corpus.

6. **Comment-only or runnable on accept?** Default proposal: **(a) comment-only**. Rationale: emitting `forAll(Gen<T>.filter(predicate)) { x in #expect(predicate(x)) }` is a tautology; the user expects the equivalence-class output to be documentation that informs their hand-written per-class properties. M9 + M10 set the precedent that hints are advisory, not load-bearing. Reversible if real-corpus accept rates show users want a runnable scaffold.

7. **Token-boundary matching algorithm.** Default proposal: **(a) tokenize on case boundaries + underscores, exact-match against the marker string per token**. Implementation: `testIsValidWithPlus` → `["test", "Is", "Valid", "With", "Plus"]` — `Valid` matches; `testValidate_simple` → `["test", "Validate", "simple"]` — `Validate` ≠ `Valid`. Handles the edge case the PRD example implicitly demands.

8. **Multiple partitions for the same predicate (e.g. `Valid`/`Invalid` AND `Success`/`Failure` both fire for `isValid`).** Default proposal: **(a) emit ONE suggestion per predicate**, picking the marker pair with the highest combined site count. Rationale: emitting two suggestions for the same predicate would be noise. Resolved deterministically by total-site-count ranking. (Becomes moot once §"Open decisions" #1 ships only `Valid`/`Invalid` — but keep the rule documented for the v1.x marker-expansion plan.)

9. **Polarity-detection ordering in the renderer when the M9/M10 hints also fire.** A predicate-equivalence-class corpus is independent of M9 (preconditions on a constructor) and M10 (round-trip-pair domains) — the three hint surfaces don't overlap because M11's stand-alone suggestion isn't decorating a `MockGenerator`. No ordering decision needed in the renderer. Default proposal: **(a) document the non-overlap explicitly** in `LiftedTestEmitter+Generators` comment so future readers don't conflate the surfaces.

## New dependencies introduced in M11

None. All work is pure SwiftInferProperties internal — `TestMethodSummary` (already in `SwiftInferTestLifter`), `SlicedTestBody` / `AssertionInvocation` (already in `SwiftInferTestLifter`), `LiftedSuggestion` / `Tier` (already in `SwiftInferCore`), `LiftedSuggestionPipeline` (already in `SwiftInferCLI`), `LiftedTestEmitter` (already in `SwiftInferTemplates`). `Package.swift` stays at `from: "2.0.0"`.

## Target layout impact

Three new source files:
- `Sources/SwiftInferCore/EquivalenceClassHint.swift` (M11.0) — public struct + the `LiftedSuggestion` enum case thread-through.
- `Sources/SwiftInferTestLifter/EquivalenceClassMarkerExtractor.swift` (M11.1) — pure-function pass.
- `Sources/SwiftInferTestLifter/PredicateEquivalenceClassDetector.swift` (M11.1) — pure-function detector.

Source files modified:
- `Sources/SwiftInferTestLifter/SlicedTestBody.swift` — add `.xctAssertFalse` to `AssertionInvocation.Kind` (M11.0).
- `Sources/SwiftInferTestLifter/Slicer.swift` — recognize `XCTAssertFalse` invocation (M11.0).
- `Sources/SwiftInferCore/Tier.swift` — add `.advisory` tier value (per §"Open decisions" #3) (M11.0).
- `Sources/SwiftInferCore/Suggestion.swift` (or `LiftedSuggestion.swift` in `SwiftInferTestLifter`) — add the `equivalenceClass` enum case (M11.0).
- `Sources/SwiftInferCLI/LiftedSuggestionPipeline.swift` — invoke extractor + detector per parsed test target; emit `EquivalenceClassSuggestion`s into the stream (M11.2).
- `Sources/SwiftInferTemplates/LiftedTestEmitter.swift` (or a new `LiftedTestEmitter+EquivalenceClass.swift` peer) — render the comment-only documentation block on accept (M11.2).

Test files:
- `Tests/SwiftInferCoreTests/EquivalenceClassHintTests.swift` (M11.0) — model-shape tests.
- `Tests/SwiftInferTestLifterTests/SlicerXCTAssertFalseTests.swift` (M11.0) — assertion-kind round-trip.
- `Tests/SwiftInferTestLifterTests/EquivalenceClassMarkerExtractorTests.swift` (M11.1) — per-token-boundary marker tests.
- `Tests/SwiftInferTestLifterTests/PredicateEquivalenceClassDetectorTests.swift` (M11.1) — per-path detector tests.
- `Tests/SwiftInferIntegrationTests/EquivalenceClassRenderingTests.swift` (M11.2) — end-to-end fixture tests.

## Closes after M11 ships

After M11, TestLifter's expanded-output surface ships its third (and final) §7.8 concrete pattern. The PRD §7.8 expanded-outputs row is fully closed: preconditions (M9) + inferred domains (M10) + equivalence-class detection (M11) all shipped.

The v1.1 line tags at the close of M11. Subsequent work pivots to:
- The deferred Option A general data-flow tracing from M10 (consumer-producer chain detection beyond round-trip pairs) — future v1.x.
- The deferred Option A general partition surface from M11 (arbitrary marker labels, N-class, multi-predicate, cross-class relations) — future v1.x.
- PRD §20 v1.1+ trajectory items: SemanticIndex, IDE integration, `swift-infer apply`, `swift-infer metrics`.

The §7.8 row is done; the v1.x trajectory continues with the PRD §20 surface.
