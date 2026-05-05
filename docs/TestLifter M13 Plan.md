# TestLifter M13 — Equivalence-Class Detection (General Partition Surface) (Plan)

**Supersedes:** `docs/archive/TestLifter M11 Plan.md` "Out of scope" / "Closes after M11 ships" — M11 explicitly deferred the Option A general partition surface to a future v1.x. M13 is that future v1.x.

**Sibling-deferred:** `docs/archive/TestLifter M10 Plan.md` Option A (general consumer-producer chain detection) is the M10 sibling deferral. Tracked as M12, scheduled after PRD §20 SemanticIndex per the v1.1.0 hand-off recommendation; M13 ships independently.

## v1.x trajectory framing

M11 (v1.1) shipped the §7.8 third example **narrowed**: two-class predicate partitions from a curated `(positive, negative)` marker pair (`Valid`/`Invalid`), both buckets reaching the M4.3 ≥3-site threshold + homogeneous predicate + matched polarity. M13 generalizes that surface across four axes the M11 plan named as Option A:

1. **Arbitrary marker labels** — extend the curated pair to a marker *table* (curated default set + user-extensible via `.swiftinfer/vocabulary.json`).
2. **N-class partitions (N > 2)** — same predicate-output classification, more than two buckets.
3. **Multi-predicate equivalence classes** — different predicates consistent within each class, partition-wise.
4. **Cross-class relation properties** — emit the "buckets are exhaustive over `T`" property when the markers form a complete cover.

Opening this plan does NOT pull the rest of the v1.x trajectory in — PRD §20 (SemanticIndex, IDE integration, `swift-infer apply`, `swift-infer metrics`) plus M12 (general consumer-producer chain detection) stay deferred. M13 is the single milestone this plan covers.

## Scope-narrowing decision: ship 3 of 4 Option A axes

Following the M9 / M10 / M11 pattern of "pick the high-confidence narrow extensions, ship them, leave the speculative ones for later":

**M13 ships (Option A axes 1, 2, 4):**

- Axis 1 — **Arbitrary marker labels via `.swiftinfer/vocabulary.json`** plus a small curated default set (`Success`/`Failure`, `Accept`/`Reject`, `Pass`/`Fail`, `Allowed`/`Forbidden`) on top of M11's `Valid`/`Invalid`. User-extensible vocabulary fits the existing `Vocabulary` surface (PRD §4.5) cleanly.
- Axis 2 — **N-class partitions (N > 2) over a single predicate**, when the predicate's output type is an enum/Comparable and the markers correspond to specific cases or ordered ranges. E.g. `testSmall_*` / `testMedium_*` / `testLarge_*` against `size(_:) -> Size` where `Size` is `enum Size { case small, medium, large }`.
- Axis 4 — **Cross-class exhaustiveness suggestion**, emitted when the partition over an enum-output predicate covers every case (or when a 2-class partition's two predicates are negations of each other). The advisory comment block names the additional generated property: `forAll x: T. p₁(x) ∨ p₂(x) ∨ … ∨ pₙ(x)`.

**M13 explicitly defers (Option A axis 3) to a future v1.x M13.+:**

- Axis 3 — **Multi-predicate equivalence classes with different predicates per bucket** (e.g. `Valid` bucket calls `isValid(x)`, `Invalid` bucket calls `isInvalid(x)`, where `isValid` and `isInvalid` are sibling functions, not negations of each other). Reason: the homogeneity-veto logic that protects M11's precision relies on a single predicate per partition. Multi-predicate detection requires either a name-resemblance heuristic (fragile) or a semantic-equivalence check (out of scope at v1.x; needs SemanticIndex). Two-bucket negation (a special case where `p₂ = ¬p₁`) IS handled — that's structurally identical to M11's polarity-homogeneity check applied across buckets.

Three reasons this scope is right:

1. **PRD §3.5 conservative-engine alignment.** Curated + user-extensible markers, predicate-output-type homogeneity, ≥3 sites per bucket, all M11's veto checks reused. False-positive surface grows linearly with the marker table, not combinatorially.
2. **Most user value, least new infrastructure.** Axes 1, 2, 4 reuse M11's `EquivalenceClassMarkerExtractor`, `PredicateEquivalenceClassDetector`, and the side-map carrier with mostly additive changes. Axis 3 (multi-predicate) needs a substantial new homogeneity model.
3. **Closes the "M11 ships narrow → M13 ships general" arc cleanly.** After M13, the §7.8 third example surface is functionally complete for the patterns that show up in real test corpora; the deferred axis 3 is a refinement, not a new surface.

## What M13 ships (PRD §7.8 third example, generalized)

Building on M11's surface — `EquivalenceClassMarkerExtractor`, `PredicateEquivalenceClassDetector`, `EquivalenceClassHint`, `Tier.advisory`, side-map carrier — M13 adds:

1. **Marker table generalization (axis 1).** `EquivalenceClassMarkerExtractor` consumes a `MarkerTable` value rather than the M11 hard-coded `Valid`/`Invalid` pair. Default table includes:
   - `(Valid, Invalid)` — M11 inheritance.
   - `(Success, Failure)`, `(Accept, Reject)`, `(Pass, Fail)`, `(Allowed, Forbidden)` — added curated defaults.
   - User-extensible via `Vocabulary.markerPairs: [MarkerPair]` (M11's two-class table) and `Vocabulary.markerSets: [MarkerSet]` (M13's N-class table — see axis 2).

   Each `MarkerPair` is `(positive: String, negative: String)` with optional `synonyms: [String]` per polarity. Each `MarkerSet` is `(name: String, markers: [String])` for N-class.

2. **N-class detection (axis 2).** New `NClassEquivalenceClassDetector` peer to M11's `PredicateEquivalenceClassDetector`. Fires when:
   - A `MarkerSet` of cardinality ≥ 3 partitions test methods into ≥ 3 buckets, all reaching the ≥3-site threshold.
   - Every site invokes the **same** unary predicate function (homogeneity).
   - The predicate's return type is `Equatable` and the partition's per-bucket assertion shape is `XCTAssertEqual(predicate(x), <bucketCase>)` or the Swift Testing `#expect(predicate(x) == <bucketCase>)` equivalent. The `<bucketCase>` literal in each bucket must match the marker name (case-insensitive identifier match).
   - Predicate veto checks from M11 still apply (no throws, no async, single arg, generatable arg type).

   Emits a new `NClassEquivalenceClassHint` (peer to M11's two-class `EquivalenceClassHint`) carrying:
   - `predicateName: String`, `argTypeName: String`, `returnTypeName: String`.
   - `markers: [String]` (ordered).
   - `siteCountsByMarker: [String: Int]` (each ≥ 3).
   - `predicateVetoed: Bool`, `vetoReason: String?`.
   - `suggestedGeneratorsByMarker: [String: String]` — `Gen<T>.gen().filter { predicate($0) == .<marker> }` per bucket.

3. **Exhaustiveness emission (axis 4).** The detector annotates hints with `coversDomain: Bool` when one of the following holds:
   - Two-class M11 hint and the negative-bucket assertion form is structurally `XCTAssertFalse(predicate(x))` while the positive bucket asserts `XCTAssertTrue(predicate(x))` — `negative = ¬positive` syntactically, so the partition covers `T`.
   - N-class M13 hint where the predicate's return type is an enum that the SwiftSyntax pass can resolve (i.e. the type is declared in the same target / module and visible to `FunctionScanner`) AND the marker set covers every enum case. Same-target enum case enumeration is a constraint we accept — full cross-target case coverage is SemanticIndex territory.

   When `coversDomain` is true, the rendered comment block includes the additional property suggestion: `// Exhaustiveness: forAll x: T. <p₁(x) ∨ p₂(x) ∨ … ∨ pₙ(x)>`.

4. **Suggestion stream + accept-flow.** M13 hints flow through the same `InteractiveTriage.Context.equivalenceClassHintsByIdentity` side-map M11 introduced — the carrier shape generalizes naturally to a sum type (`enum EquivalenceClassHintKind { case twoClass(EquivalenceClassHint), nClass(NClassEquivalenceClassHint) }`) so the §13 row 4 memory budget posture is unchanged.

   Accept-flow writeout filename:
   - Two-class: `Tests/Generated/SwiftInfer/equivalence-class/EquivalenceClasses_<predicate>.swift` (M11 inheritance — unchanged).
   - N-class: `Tests/Generated/SwiftInfer/equivalence-class/EquivalenceClasses_<predicate>_<markerSetName>.swift` — marker-set name suffix disambiguates when the same predicate fires under multiple marker sets.

5. **Validation suite.** §13 perf re-check (extend `TestLifterPerformanceTests` with N-class corpora — N-bucket × M-site test methods over a single predicate). §16 #1 hard-guarantee re-check. §15 fuzz extension on the new `MarkerTable` parsing path. End-to-end integration tests under `EquivalenceClassRenderingTests` for each shipped axis.

## Sub-milestone breakdown

| Sub | Scope | Why this order |
|---|---|---|
| **M13.0** | **MarkerTable + Vocabulary surface extension.** New `Sources/SwiftInferCore/MarkerTable.swift` (public structs `MarkerPair`, `MarkerSet`, `MarkerTable`). Extend `Vocabulary` with `markerPairs: [MarkerPair]` and `markerSets: [MarkerSet]` fields (defaults populated with the curated pairs above). Extend `VocabularyLoader` to round-trip both new fields through `.swiftinfer/vocabulary.json`. **Acceptance:** `MarkerTableTests` covers Equatable + Codable round-trip; `VocabularyLoaderMarkerTableTests` covers JSON round-trip including the empty-pairs / empty-sets fallbacks; existing `VocabularyLoaderTests` remain green (no migration needed — the new fields are additive with curated defaults). | Foundation. M13.1 + M13.2 + M13.3 all consume `MarkerTable`; landing it standalone keeps the dependent subs pure-function over a stable input shape. |
| **M13.1** | **Refactor `EquivalenceClassMarkerExtractor` to consume `MarkerTable` + multi-pair scan.** Replace the M11 hard-coded `("Valid", "Invalid")` constant with the loaded `MarkerTable.pairs`. Per-pair partition output unchanged; the extractor returns `[PartitionCandidate]` keyed by `(predicate, markerPair)` so the detector can rank when multiple markers fire on the same predicate (M11 open-decision #8). New `PartitionCandidate.markerSet: MarkerSet?` field carries the N-class marker set when applicable; `markerPair: MarkerPair?` carries the two-class pair. Mutually exclusive — one or the other is non-nil. **Acceptance:** `EquivalenceClassMarkerExtractorMultiMarkerTests` covers extraction across the curated default pairs (`Success`/`Failure` corpus produces an `EquivalenceClassHint` matching M11's shape); per-predicate ranking when multiple pairs fire (highest-combined-site-count wins). M11's existing `EquivalenceClassMarkerExtractorTests` remain green — the API is source-compatible. | Sequenced after M13.0 because the extractor consumes `MarkerTable`. Pure refactor + small extension; no detector changes yet. |
| **M13.2** | **N-class detection (axis 2).** New `Sources/SwiftInferCore/NClassEquivalenceClassHint.swift` (data model). New `Sources/SwiftInferTestLifter/NClassEquivalenceClassDetector.swift` — pure-function pass consuming an N-class `PartitionCandidate` (≥ 3 buckets) + `[SlicedTestBody]`, returning `NClassEquivalenceClassHint?`. Predicate-return-type inspection uses the existing `FunctionSummary.returnType` field; bucket-case literal matching uses identifier-token comparison. Reuses M11's predicate veto rules verbatim. **Acceptance:** `NClassEquivalenceClassDetectorTests` covers the three-class enum corpus (Small/Medium/Large fixtures); under-threshold-in-any-bucket → no emit; mixed-predicate → no emit; non-Equatable predicate return → no emit; throwing predicate → vetoed hint with the same comment-only fallback shape as M11. | Sequenced after M13.1 because the N-class detector consumes the same `PartitionCandidate` shape M13.1 widens. M13.2 is parallel-able with M13.3 in principle but the validation suites overlap — easier to land in series. |
| **M13.3** | **Exhaustiveness annotation (axis 4) + pipeline wiring + accept-flow + validation suite.** Extend M11's `PredicateEquivalenceClassDetector` to set `coversDomain: true` on two-class hints when the negative bucket asserts via `XCTAssertFalse`; extend M13.2's `NClassEquivalenceClassDetector` with same-target enum case enumeration via the existing `FunctionScanner` symbol table. Pipeline wiring: `LiftedSuggestionPipeline+EquivalenceClass` invokes both detectors; sum-type carrier `EquivalenceClassHintKind` lands in the side-map. Accept-flow renderer: extend `InteractiveTriage+AcceptEquivalenceClass` to handle the N-class file naming + the exhaustiveness comment block. §13 perf re-check (extend the integration suite with a 50-method N-class corpus). §16 #1 hard-guarantee re-check. §15 fuzz extension on `MarkerTable` parsing. End-to-end integration tests cover each axis. **Acceptance:** `EquivalenceClassRenderingTests` extended — three-class enum corpus surfaces `NClassEquivalenceClassHint` + accept writes the expected file with the exhaustiveness comment; two-class XCTAssertFalse corpus surfaces the M11-shape hint with `coversDomain: true` + accept writes with the negation property comment; multi-marker corpus picks the right pair per the M11 open-decision #8 ranking. | Sequenced last; closes the M13 acceptance bar. |

## M13 acceptance bar

Mirroring PRD §7.8 + §7.9 + the M9–M11 cadence, M13 is not done until:

a. **`MarkerTable` is a public type in `SwiftInferCore`** with `MarkerPair` + `MarkerSet` value types and curated default pairs landed.

b. **`Vocabulary` carries `markerPairs` + `markerSets` fields** with JSON round-trip via `VocabularyLoader`. Empty-pairs / empty-sets fallback to defaults — no project-level config required to inherit M13's curated surface.

c. **`EquivalenceClassMarkerExtractor.extract(...)` consumes `MarkerTable`** and emits `PartitionCandidate`s for both two-class and N-class shapes.

d. **`NClassEquivalenceClassDetector.detect(...)` enforces:**
   - ≥ 3 buckets active.
   - ≥ 3 sites per bucket (each).
   - Same predicate across all buckets (homogeneity).
   - Predicate's return type is `Equatable` (compile-time check via `FunctionSummary` introspection — same posture as M4's generator strategy table).
   - Bucket-case literal matches the marker name (identifier-token).
   - All predicate veto checks from M11 (no throws / async / multi-arg / non-generatable).

e. **`coversDomain: Bool` annotation fires correctly:**
   - Two-class: `coversDomain == true` iff negative bucket uses `XCTAssertFalse(predicate(x))` against positive bucket's `XCTAssertTrue(predicate(x))`.
   - N-class: `coversDomain == true` iff the partition's marker set covers every case of the predicate's enum return type, when that enum is declared in the same target.

f. **One outlier kills the hint** — same PRD §3.5 conservative bias as M11. Any non-homogeneous predicate / non-matching bucket-case literal / non-Equatable return type / non-enumerable enum cases → no emit (or vetoed-comment-only emit per the M11 fallback).

g. **Pipeline wiring emits `EquivalenceClassHintKind` into the side-map** automatically, once per parsed test target. Side-map shape (`InteractiveTriage.Context.equivalenceClassHintsByIdentity`) is unchanged; only the carrier value type widens.

h. **Accept-flow writeout follows the M13 filename convention** — two-class inherits M11's filename verbatim; N-class adds `_<markerSetName>` suffix. The rendered file is comment-only (M11 inheritance) and includes the exhaustiveness suggestion when `coversDomain == true`.

i. **§13 100-test-file budget holds with M13.0–M13.3 active.** The marker-table iteration is O(table-size × method-count); the detector work is O(partition-size). Tabular cost is dominated by marker-pair iteration; with the v1.1 default of 5 pairs + N marker sets, perf impact stays sub-millisecond per test method.

j. **§13 row 4 memory ceiling holds** — the side-map carrier widening (sum type) does not regress the v1.1 recalibrated 800 MB CI ceiling. The `[§13 row 4]` diagnostic log line surfaces the actual delta on every CI run.

k. **§16 #1 hard guarantee preserved** — M13 writes only to `Tests/Generated/SwiftInfer/equivalence-class/`, never to source.

l. **§15 non-throwing fuzz harness extended** — `MarkerTable` parsing must not crash on malformed JSON; the marker extractor must not crash on N-class corpora with adversarial method names.

m. **`Package.swift` stays at `from: "2.0.0"`** — no kit-side coordination needed for M13.

## Out of scope for M13 (reaffirmed)

- **Multi-predicate equivalence classes (Option A axis 3).** Different predicates per bucket where they're not negations of each other. Future v1.x — needs SemanticIndex for semantic-equivalence reasoning.
- **Cross-target enum case enumeration.** N-class exhaustiveness annotation only fires when the predicate's enum return type is declared in the same target. Full cross-target / cross-package coverage is SemanticIndex territory.
- **Filter-impractical generator narrowing.** Same M11 posture — when `Gen<T>.filter(predicate)` is rejection-rate-impractical, M13 doesn't synthesize a custom generator.
- **Cross-test-target marker discovery.** Stays within the configured test target.
- **Throwing / async / multi-arg predicate generator suggestion.** Hard veto on the generator string; comment-only fallback with the veto reason.
- **Counterexample-driven class refinement.** Convert-counterexample (M8) territory; not extended here.
- **Cross-validation against TemplateEngine score.** Inherits the M9 / M10 / M11 advisory-only posture.
- **`--show-equivalence-classes` CLI flag.** v1.1+ scoping pattern still applies — the discover stream surface is sufficient.
- **Runnable property emission on accept.** Comment-only writeout (M11 inheritance).
- **Marker label localization.** English curated defaults only; project-extensible vocabulary handles non-English projects via user-supplied marker pairs.
- **Cross-repo coordination with SwiftPropertyLaws.** No kit-side changes for M13.

## Open decisions to make in-flight

1. **Curated default `MarkerPair` set.** Default proposal: **(a) `Valid`/`Invalid` (M11) + `Success`/`Failure` + `Accept`/`Reject` + `Pass`/`Fail` + `Allowed`/`Forbidden`** — five pairs total. Rationale: covers the `success-or-failure` / `permission-style` / `boolean-validity` axes that real corpora exercise. Synonyms (e.g. `Reject`/`Refused`) deferred to user-supplied vocabulary. Reversible — if a default pair turns up too noisy in real-corpus calibration, drop it from defaults; user vocabulary still admits it.

2. **Curated default `MarkerSet` set.** Default proposal: **(a) ship NO default N-class sets**. Rationale: N-class partitions are domain-specific (`Small`/`Medium`/`Large`, `Red`/`Green`/`Blue`, `Spring`/`Summer`/`Fall`/`Winter`, etc.) with no universal patterns; opinionated curated defaults would be either too narrow (don't cover the user's domain) or too broad (false positives). User-supplied via `.swiftinfer/vocabulary.json` exclusively. M13's curated test fixtures still exercise N-class detection via in-test marker sets.

3. **Predicate-return-type Equatable check methodology.** Default proposal: **(a) syntactic check via `FunctionSummary.returnType` declaring `Equatable` conformance OR being a stdlib type with known `Equatable` conformance** (`Int`, `String`, `Bool`, enum-with-no-associated-values). Full conformance check requires SemanticIndex; v1.x proxy is good enough for the high-confidence paths.

4. **Bucket-case literal matching for N-class.** Default proposal: **(a) identifier-token match against the marker name, case-insensitive** — e.g. `XCTAssertEqual(size(x), .small)` matches the `Small` marker. Rejected alternative: AST-level resolution of the enum case → too brittle, too dependent on type inference.

5. **Sum-type carrier shape (`EquivalenceClassHintKind`) vs separate side-maps.** Default proposal: **(a) sum type** — single side-map carries both M11 and M13 hint kinds. Rationale: matches M11's existing carrier shape minimally; renderer dispatches on the sum tag once. Two side-maps would force every consumer to query both.

6. **N-class accept-flow filename suffix.** Default proposal: **(a) `_<markerSetName>` lowercased verbatim** (`EquivalenceClasses_size_sizes.swift` for predicate `size` + marker set `Sizes`). Snake-case alternative: rejected for inconsistency with M11's camelCase predicate filename.

7. **`coversDomain` annotation threshold.** Default proposal: **(a) emit the exhaustiveness comment ONLY when the markers structurally cover the domain** (the two cases above). Statistical heuristics (e.g. "100 sites tested across 4 buckets, no other case ever observed") are deferred — too easy to be wrong (the corpus might just be incomplete).

8. **Multi-pair fire ranking.** Default proposal: **(a) inherit M11 open-decision #8** — emit ONE suggestion per `(predicate, markerPair)` combination, picking the highest-combined-site-count when multiple pairs fire on the same predicate. For N-class, emit ONE per `(predicate, markerSet)`. A predicate that fires under both a two-class pair AND an N-class set emits two suggestions (different artifacts).

9. **Whether to bump the `≥ 3` per-bucket threshold for N-class.** Default proposal: **(a) keep `≥ 3` per bucket**. Higher thresholds (e.g. `≥ 5`) trade recall for precision; the per-bucket strictness already protects against noise. Reversible based on real-corpus calibration.

10. **Whether the marker table participates in `// swiftinfer: skip` honoring.** Default proposal: **(a) yes** — a test method tagged with `// swiftinfer: skip` is excluded from marker classification (consistent with M6's skip-marker honoring across all detectors).

## New dependencies introduced in M13

None. All work is pure SwiftInferProperties internal — `Vocabulary` (already in `SwiftInferCore`), `VocabularyLoader` (already in `SwiftInferCLI`), `FunctionSummary` (already in `SwiftInferCore`), `TestMethodSummary` / `SlicedTestBody` (already in `SwiftInferTestLifter`), `LiftedSuggestion` (already in `SwiftInferTestLifter`), `LiftedSuggestionPipeline` + `InteractiveTriage` (already in `SwiftInferCLI`). `Package.swift` stays at `from: "2.0.0"`.

## Target layout impact

Three new source files:

- `Sources/SwiftInferCore/MarkerTable.swift` (M13.0) — `MarkerPair`, `MarkerSet`, `MarkerTable`, default-pair / default-set constants.
- `Sources/SwiftInferCore/NClassEquivalenceClassHint.swift` (M13.2) — N-class hint data model.
- `Sources/SwiftInferTestLifter/NClassEquivalenceClassDetector.swift` (M13.2) — N-class pure-function pass.

Source files modified:

- `Sources/SwiftInferCore/Vocabulary.swift` — add `markerPairs` + `markerSets` fields with curated defaults (M13.0).
- `Sources/SwiftInferCLI/VocabularyLoader.swift` — JSON round-trip the new fields (M13.0).
- `Sources/SwiftInferTestLifter/EquivalenceClassMarkerExtractor.swift` — consume `MarkerTable` + emit `PartitionCandidate` for both two-class and N-class shapes (M13.1).
- `Sources/SwiftInferTestLifter/PredicateEquivalenceClassDetector.swift` — annotate with `coversDomain: Bool` (M13.3).
- `Sources/SwiftInferCore/EquivalenceClassHint.swift` — add `coversDomain: Bool` field; either rename type to `EquivalenceClassHintKind` (sum) or add a parallel `NClassEquivalenceClassHint` and an enum wrapper. See §"Open decisions" #5.
- `Sources/SwiftInferCLI/LiftedSuggestionPipeline+EquivalenceClass.swift` — invoke both detectors; carrier widening (M13.3).
- `Sources/SwiftInferCLI/InteractiveTriage+AcceptEquivalenceClass.swift` — N-class file naming + exhaustiveness comment block (M13.3).

Test files:

- `Tests/SwiftInferCoreTests/MarkerTableTests.swift` (M13.0) — model-shape tests + default-pair sanity.
- `Tests/SwiftInferCLITests/VocabularyLoaderMarkerTableTests.swift` (M13.0) — JSON round-trip including empty / partial / nil paths.
- `Tests/SwiftInferTestLifterTests/EquivalenceClassMarkerExtractorMultiMarkerTests.swift` (M13.1) — multi-pair scanning + ranking.
- `Tests/SwiftInferTestLifterTests/NClassEquivalenceClassDetectorTests.swift` (M13.2) — per-path detector tests for N-class corpora.
- `Tests/SwiftInferIntegrationTests/EquivalenceClassRenderingNClassTests.swift` (M13.3) — end-to-end fixture tests covering each shipped axis.
- `Tests/SwiftInferIntegrationTests/EquivalenceClassRenderingTests.swift` extended (M13.3) — `coversDomain` two-class case + multi-marker corpus.

## Closes after M13 ships

After M13, TestLifter's expanded-output equivalence-class surface ships its general (Option A) form for the three highest-confidence axes. The §7.8 third example surface is functionally complete for the patterns that show up in real test corpora. Combined with the M11 narrow surface (which M13 strict-extends), users get:

- M11 — `Valid`/`Invalid` two-class detection (default).
- M13 — Five curated marker pairs + user-extensible vocabulary; N-class detection over enum / Comparable predicate outputs; exhaustiveness annotation when the partition covers the domain.

Subsequent work picks one of:

- **M12** — General consumer-producer chain detection (M10 deferred Option A). Recommended sequencing: after PRD §20 SemanticIndex (much of M12 falls out of having a directed call-graph available).
- **M13.+** — Multi-predicate equivalence classes (M13's deferred axis 3). Same sequencing constraint as M12 — needs SemanticIndex for the semantic-equivalence reasoning.
- **PRD §20 v1.1+ trajectory** — SemanticIndex (the largest single lift), IDE integration, `swift-infer apply`, `swift-infer metrics`.
- **M9.+** — `Float` / `Double` numerical-bound preconditions (M9 deferred). Independent of SemanticIndex.

The §7.8 row's expanded-output surface is now both shipped (M9 + M10 + M11) and generalized (M13). Subsequent v1.x work pivots to the §20 surface.
