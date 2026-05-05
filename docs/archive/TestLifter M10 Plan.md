# TestLifter M10 — Inferred Domains (Plan)

**Supersedes:** PRD v1.0 §7.8 second example + §7.9 row M10 ("Inferred domains — cross-call data-flow tracing for 'decode only sees encode output'-style domain narrowing").

## v1.1 trajectory framing

PRD v1.0 §5.8 + §7.9 mark M10 as **Deferred** to v1.1+. v1.0 shipped with M9 as the §7.8 first example (preconditions); M10 is the §7.8 second example. **Opening this plan opens the v1.1 trajectory.** It does not pull the rest of v1.1+ scope in (SemanticIndex, IDE integration, `swift-infer apply`, `swift-infer metrics` per PRD §20 stay deferred); M10 is the single v1.1 milestone this plan covers.

The v1.1 line will tag at the close of M10 (or batched with M11 if M11 ships immediately after — open scheduling decision; this plan doesn't assume either way).

## Scope-narrowing decision: round-trip-pair domains only

PRD §7.8 second example: *"When tests for `decode` only pass strings produced by `encode`, TestLifter could infer that `decode`'s domain is 'encoder output' rather than 'all `String`'. Suggestion: 'round-trip property over `Gen<MyType>.map(encode)` rather than `Gen.string()` — `decode` was never observed against arbitrary strings, only encoder output.'"*

The PRD note continues: *"Requires cross-call data-flow tracing infrastructure the v1 surface doesn't have."* — i.e. the **fully general** form of inferred domains needs whole-corpus directed call-graph analysis with intra/inter-test let-binding resolution, classification of arbitrary argument expressions, and a corpus-level join. Call this **Option A**.

**This plan ships Option B:** narrow M10 to *round-trip-pair domain narrowing only*. The detector fires only when M5's round-trip pair detector (TemplateEngine `RoundTripTemplate` + cross-pair signal `FunctionPairing`) has independently surfaced a `(forward, reverse)` pair on the source side; M10's job is then to confirm — by examining the test corpus's reverse-side call sites — that the reverse function's argument is consistently the forward function's output, and to refine the round-trip suggestion's generator metadata accordingly.

Option B reuses the M5 pair detector's precision (§3.5 conservative-engine alignment), avoids the speculative consumer-producer-chain detection space that Option A opens, and matches the M9 cadence (3–4 sub-milestones, one new data-model file + one new inferrer + pipeline wiring + validation). The Option A surface remains in the v1.1+ trajectory as a future M10.1 / M10 expansion.

Three reasons Option B is the right v1.1-opening scope:

1. **Precision inherits from M5.** Option A would have to invent its own consumer-producer detection criteria (which (consumer, producer) chains in the corpus are real-vs-coincidental). Option B short-circuits that question by anchoring on M5's already-validated round-trip pair set.
2. **Output surface is well-defined.** A round-trip suggestion already carries a `MockGenerator`; M10 attaches a `DomainHint` that overrides the generator string to `Gen<T>.map(forward)` when the pattern fires + producer veto checks pass. No new template, no new suggestion kind.
3. **Mirrors M9's narrowing pattern.** M9 chose preconditions only over the §7.8 three-way list because each piece had wildly different complexity. M10 follows the same playbook: ship the high-confidence narrow detector first, leave the speculative wider surface for later.

## What M10 ships (PRD v1.0 §7.8 second example, narrowed)

For each round-trip pair `(forward, reverse)` surfaced by the M5 pair detector:

1. **`DomainCallSiteExtractor`** — pure-function pass. Given `(reverseFunctionName, sourceTexts: [TestSlice])`, walks each test slice's parsed body, finds every call site of `reverseFunctionName`, and classifies the first argument expression at each site:
   - `.callOutput(producerName: String)` — argument is a direct `producerName(...)` call expression.
   - `.identifier(name: String)` — argument is a bare identifier (`x`, `encoded`, etc.); the extractor records it for the inferrer to resolve via intra-test let-binding lookup.
   - `.other` — argument is a literal, closure, member access, complex expression — anything else. Treated as outlier.

2. **`DomainInferrer`** — pure-function analysis pass. Given `(roundTripPair, [DomainCallSite])`, returns an optional `DomainHint`:
   - **Threshold:** `≥ 3` sites mirrors M4.3 / M9. Under-threshold → no hint.
   - **Identifier resolution:** for each `.identifier(name:)` site, walk the same test body's setup-region `let` bindings (already extracted by `SetupRegionConstructionScanner` / `SetupRegionTypeAnnotationScanner` infrastructure) and rewrite to `.callOutput(producerName:)` when the binding's RHS is a `forwardName(...)` call.
   - **Homogeneity:** every site (post-resolution) must classify as `.callOutput(producerName: forwardName)`. One outlier (a site with `.identifier` that doesn't resolve, an `.other`, or a `.callOutput` to a different producer) kills the hint.
   - **Producer vetoes:** if `forward` is `throws`, `async`, takes `>1` argument, or its single arg type isn't generatable per the M3+ generator-strategy table → veto generator override (still emit comment-only advisory). The `swift-property-based` runner can't shrink through `try!` / `await`; `Gen<_>.map(_:)` is unary.

3. **`DomainHint` data model** — public struct in `SwiftInferCore`. Fields:
   - `roundTripPair: (forwardName: String, reverseName: String)` — names mirror the M5 detector's pair surface.
   - `producerName: String` — the function whose output the reverse-side argument was always observed to be (always equals `forwardName` in B's narrowed scope; reserved as a separate field so the future Option A expansion can populate it for non-round-trip chains without a model migration).
   - `domainTypeName: String` — the type name `T` that the override generator is `Gen<T>.map(producer)`. Surfaced explicitly so the renderer doesn't re-derive it from the round-trip pair.
   - `siteCount: Int` — `≥ 3`. For the rendered `across N sites` provenance line.
   - `producerVetoed: Bool` — true when one of the producer-veto checks fired; renderer emits advisory comment but skips generator override.
   - `suggestedGenerator: String` — `Gen<T>.map(forward)` (or producer's actual call shape) pre-computed so the renderer doesn't re-derive.

4. **Hints threaded through the suggestion pipeline.** `MockGenerator` (M4.3) gets a new field `domainHint: DomainHint?` (single — round-trip suggestions have at most one domain hint). `LiftedSuggestionPipeline.applyMockInferredFallback(...)` is extended to call `DomainCallSiteExtractor.extract(...)` + `DomainInferrer.infer(...)` per affected round-trip suggestion, populating the field.

5. **Accept-flow renderer** (`LiftedTestEmitter+Generators`) consumes `MockGenerator.domainHint`:
   - When `producerVetoed == false`: render `// Inferred domain: reverse's argument was always forward's output across N sites — narrowing to Gen<T>.map(forward)` provenance comment AND substitute the generator expression for `Gen<T>.map(forward)`.
   - When `producerVetoed == true`: render comment only (`// Inferred domain: reverse's argument was always forward's output across N sites — generator narrowing skipped: <veto reason>`); leave the original generator unchanged.

6. **Validation suite.** §13 perf re-check + §16 #1 hard-guarantee re-check + per-pattern unit tests + end-to-end integration test on a real fixture corpus.

The non-goals — explicitly out of scope for M10, reaffirmed:

- **General consumer-producer chain detection (Option A).** If `validate(s)` is always tested against `format(...)` output and the pair isn't a round-trip — no hint emits. Future v1.x M10.1.
- **Cross-test data-flow tracing.** M10 resolves identifiers within a single test body only. A `let x = encode(t)` in `testA` and `decode(x)` in `testB` does not get correlated. Future v1.x.
- **Throwing / async producer override.** Hard veto on generator substitution; comment-only fallback.
- **Multi-arg producer override.** `Gen<_>.map(_:)` is unary; `forward(t, opts)` can't be generator-narrowed via map. Veto.
- **Cross-validation against TemplateEngine round-trip score.** M9 deferred this for preconditions; M10 inherits the same posture (advisory only, no score change).
- **`--show-domains` CLI flag.** v1.1+ per the §16 #6 v1.1+ scoping pattern — same rationale as M9's deferred `--show-preconditions`.
- **Counterexample-driven domain refinement.** Convert-counterexample (M8) territory; not extended here.

### Important scope clarifications

- **Detection threshold reuses M4.3 / M9's `≥ 3 sites`.** A domain pattern observed on fewer sites is too thin to surface confidently.
- **Source-side round-trip pair must already be detected.** M10 does not surface domain hints for arbitrary call chains in the corpus — that's Option A. The `(forward, reverse)` pair input comes from M5's detector output.
- **PRD §3.5 conservative bias.** Every reverse-side call site must classify as `.callOutput(producerName: forwardName)` post-identifier-resolution. One outlier kills the hint.
- **Suggestion-side rendering is purely advisory when vetoed.** Even when the generator override is skipped, the comment line surfaces — the user reads "domain was always encode output, but we couldn't narrow because encode throws" and decides whether to refactor `encode` to a non-throwing variant or leave the round-trip generator as-is.
- **No new CLI flags.** M10 surfaces hints automatically through the existing `swift-infer discover` pipeline.

## Sub-milestone breakdown

| Sub | Scope | Why this order |
|---|---|---|
| **M10.0** | **`DomainHint` data model** in `SwiftInferCore`. New `Sources/SwiftInferCore/DomainHint.swift`. Public struct with the fields above. `MockGenerator.domainHint: DomainHint?` field threaded through with default-`nil` backwards-compat init. **Acceptance:** `DomainHintTests` covers the struct's `Equatable` conformance + the `MockGenerator` round-trip-through-Codable shape (matching the M9.0 `PreconditionHint` test pattern). | Smallest possible refactor opening the door for M10.1 / M10.2's analysis pass. |
| **M10.1** | **`DomainCallSiteExtractor.extract(consumer:in:) -> [DomainCallSite]`** — pure-function pass. New `Sources/SwiftInferTestLifter/DomainCallSiteExtractor.swift`. Walks `[SlicedTestBody]` for every call site of `consumer`, classifies the first arg into `ArgumentClassification.{ callOutput, identifier, other }`. **Acceptance:** `DomainCallSiteExtractorTests` covers each classification (direct `forward(t)` arg → `.callOutput`; bare identifier `decode(x)` → `.identifier(name: "x")`; literal `decode("hi")` → `.other`; closure / complex expr → `.other`). | Builds on existing `Slicer` / `SlicedTestBody` infrastructure. Independent of M10.2 (pure function over already-sliced input). |
| **M10.2** | **`DomainInferrer.infer(roundTripPair:sites:setupBindings:) -> DomainHint?`** — pure-function inferrer. New `Sources/SwiftInferTestLifter/DomainInferrer.swift`. Resolves `.identifier` sites against `setupBindings` (intra-test `let x = forward(t)` lookups produced by the existing `SetupRegionConstructionScanner`). Applies the threshold (`≥ 3`), homogeneity (every post-resolution site equals `.callOutput(producerName: forwardName)`), and the producer-veto checks (throws / async / multi-arg / non-generatable arg type). Returns `DomainHint?`. **Acceptance:** `DomainInferrerTests` covers each path — homogeneous direct-call corpus → emit; mixed-producer corpus → no emit; 2 direct + 1 unresolved-identifier corpus → no emit; throwing forward → `producerVetoed: true` hint emitted; multi-arg forward → `producerVetoed: true` hint emitted; under-threshold → no emit. | Sequenced after M10.1 because the inferrer consumes `[DomainCallSite]`. Independent of M10.3. |
| **M10.3** | **Pipeline wiring + accept-flow rendering + validation suite.** Extend `LiftedSuggestionPipeline.applyMockInferredFallback(...)` to walk M5's round-trip pair set, invoke `DomainCallSiteExtractor.extract(...)` + `DomainInferrer.infer(...)` once per pair, populate `MockGenerator.domainHint`. Extend `LiftedTestEmitter+Generators.mockInferredGenerator(...)` to render the `// Inferred domain:` provenance comment line and (when `producerVetoed == false`) substitute the generator expression for `Gen<T>.map(forward)`. Add §13 perf re-check (extend `TestLifterPerformanceTests` with synthetic round-trip-pair corpora), §16 #1 hard-guarantee re-check (M10 writes nothing to source), §15 fuzz (extend non-throwing fuzz with malformed call expressions to ensure the extractor doesn't crash), and end-to-end integration test under `SwiftInferIntegrationTests`. **Acceptance:** `MockInferredDomainRenderingTests` covers the end-to-end path — synthetic 5-test fixture with `decode(encode(t))` × 5 sites surfaces both the comment line AND the `Gen<T>.map(encode)` override in the rendered stub; a separate test with 5-site corpus where `encode` is `throws` surfaces comment-only with the `producerVetoed` reason. | Sequenced last; closes the M10 acceptance bar. |

## M10 acceptance bar

Mirroring PRD §7.9 + §7.8 + the v1.0 §5.8 acceptance-bar pattern + the M5/M6/M7/M8/M9 cadence, M10 is not done until:

a. **`DomainHint` is a public type in `SwiftInferCore`.** `MockGenerator` carries `domainHint: DomainHint?` with default-nil init.

b. **`DomainCallSiteExtractor.extract(consumer:in:)` recognizes the three argument classifications** (callOutput / identifier / other) over real `SlicedTestBody` input.

c. **`DomainInferrer.infer(...)` resolves intra-test `let`-bindings** via `SetupRegionConstructionScanner` output before applying homogeneity.

d. **`≥ 3` site threshold enforced.** Under-threshold inputs produce no hint.

e. **One outlier kills the hint.** PRD §3.5 conservative bias: any non-`.callOutput(forwardName)` post-resolution site → no emit.

f. **Producer veto checks fire correctly.** Throwing / async / multi-arg / non-generatable-arg producer → `producerVetoed: true` hint (comment-only render); never a generator override.

g. **Pipeline wiring populates `MockGenerator.domainHint` automatically** during the M4.3 lifted-pipeline mock-inference pass, anchored on the M5 round-trip pair set.

h. **Accept-flow renderer surfaces hints as `// Inferred domain:` provenance comments** in the generated `Gen<T>` body, with the generator expression substituted for `Gen<T>.map(forward)` when not vetoed.

i. **§13 100-test-file budget holds with M10.0–M10.3 active.** The added work (per-pair extraction + per-position homogeneity check) should be sub-millisecond per round-trip pair; corpus has ≤ a few dozen pairs in realistic packages.

j. **§16 #1 hard guarantee preserved** — M10 adds no source-tree writes (the existing M4.4 + M3.3 writeout paths surface the hints as comments inside their existing files).

k. **§15 non-throwing fuzz harness extended.** The extractor must not crash on malformed call expressions, unusual argument shapes, or empty test bodies.

l. **`Package.swift` stays at `from: "2.0.0"`** — no kit-side coordination needed for M10.

## Out of scope for M10 (re-stated for clarity)

- **Option A (full data-flow tracing).** Whole-corpus directed call-graph + non-round-trip consumer-producer chain detection. Future v1.x M10.1.
- **Cross-test data-flow tracing.** Identifier resolution stays intra-test-body only.
- **Throwing / async / multi-arg producer override.** Hard veto on generator substitution; comment-only fallback.
- **`whyMightBeWrong` widening for hints.** Hints render as advisory comments only; no tier or score change (M9 inherits-the-posture pattern).
- **Counterexample-driven hint refinement** — convert-counterexample (M8) territory.
- **Cross-validation of hints against TemplateEngine round-trip score** — out of v1.0/v1.1 scope.
- **`--show-domains` CLI flag** — v1.1+ per the §16 #6 v1.1+ scoping pattern.
- **Cross-repo coordination with SwiftPropertyLaws.** No kit-side changes for M10.

## Open decisions to make in-flight

1. **Identifier resolution scope: setup region only, or full body?** Default proposal: **(a) setup region + property region of the SAME test body**. The slicer already partitions both (`SlicedTestBody` carries both regions); the inferrer walks both for `let x = forward(t)` candidates. Cross-test correlation is Option A territory and stays out.

2. **Throwing / async producer: hard veto or soft warning?** Default proposal: **(a) HARD VETO on generator override**, comment-only fallback with the veto reason in the comment text. Rationale: `Gen<_>.map(_:)` cannot apply a throwing/async function; the runner can't shrink through `try!`/`await`; substituting silently would emit broken code.

3. **Multi-arg producer (`forward(t, opts)`): hard veto or partial-application synthesis?** Default proposal: **(a) HARD VETO**. Partial-application is fragile (which arg to fix at which value? — the corpus may show variation in `opts`); comment-only with the veto reason. Defer to Option A's full data-flow if the partial-application case shows real-corpus value.

4. **What counts as a "non-generatable arg type" for the producer veto?** Default proposal: **(a) anything the M3+ `DerivationStrategist` returns `.todo` or `.userGen` for** — both indicate the type isn't auto-generatable in the M5/M6/M7 strategy table. The user can resolve `.userGen` cases by providing `static func gen()` themselves and re-running discover; the hint will then re-fire.

5. **`DomainHint.producerName` vs hard-coding `forwardName`.** Default proposal: **(a) keep `producerName` as a distinct field** equal to `forwardName` in B's narrowed scope. Rationale: forward-compat with Option A's expansion, where a non-round-trip `(consumer, producer)` chain would fill `producerName` independently of any round-trip pair. Avoids a model migration when M10.1 lands.

6. **Multiple round-trip pairs in the same corpus involving the same reverse function.** E.g. `encodeJSON / decode` and `encodeXML / decode` both sit in the corpus. Default proposal: **(a) SKIP HINT for that reverse function** — homogeneity fails by definition (some sites have `.callOutput("encodeJSON")`, others `.callOutput("encodeXML")`). The conservative bias takes precedence; user can disambiguate by accepting the round-trip suggestions individually.

7. **`DomainHint` field placement: on `MockGenerator` or on `Suggestion`?** Default proposal: **(a) field on `MockGenerator`**, mirroring the M9 `preconditionHints` placement. Rationale: domain narrowing rewrites the generator string, so the hint travels with the generator. Suggestions without a mock generator can't carry domain hints (the round-trip suggestion path always produces one).

8. **Pre-existing `MockGenerator.preconditionHints` interaction.** If M9 emits `Inferred precondition: ...` lines AND M10 emits `Inferred domain: ...` lines on the same generator, both render. Default proposal: **(a) both render**, M10's domain comment precedes M9's precondition lines (the domain narrowing changes the generator type; preconditions then apply to the post-narrowing generator). Renderer ordering documented in `LiftedTestEmitter+Generators` comment.

## New dependencies introduced in M10

None. All work is pure SwiftInferProperties internal — `SlicedTestBody`, `SetupRegionConstructionScanner` (already in `SwiftInferTestLifter`), `MockGenerator`, `FunctionPair` (already in `SwiftInferCore` / `SwiftInferTemplates`), `LiftedSuggestionPipeline` (already in `SwiftInferCLI`), `LiftedTestEmitter+Generators` (already in `SwiftInferTemplates`). `Package.swift` stays at `from: "2.0.0"`.

## Target layout impact

Two new source files:
- `Sources/SwiftInferCore/DomainHint.swift` (M10.0) — public struct + the `MockGenerator.domainHint` field thread-through.
- `Sources/SwiftInferTestLifter/DomainCallSiteExtractor.swift` (M10.1) — pure-function pass.
- `Sources/SwiftInferTestLifter/DomainInferrer.swift` (M10.2) — pure-function inferrer.

Two existing source files modified:
- `Sources/SwiftInferCLI/LiftedSuggestionPipeline.swift` — call extractor + inferrer per round-trip pair inside `applyMockInferredFallback`; populate the mock-generator's `domainHint` field.
- `Sources/SwiftInferTemplates/LiftedTestEmitter+Generators.swift` — render `// Inferred domain:` comment line per hint, substitute generator expression when not vetoed, document the hint-ordering convention with M9's precondition lines.

Test files:
- `Tests/SwiftInferCoreTests/DomainHintTests.swift` (M10.0) — model-shape tests.
- `Tests/SwiftInferTestLifterTests/DomainCallSiteExtractorTests.swift` (M10.1) — per-classification extraction tests.
- `Tests/SwiftInferTestLifterTests/DomainInferrerTests.swift` (M10.2) — per-path inferrer tests.
- `Tests/SwiftInferIntegrationTests/MockInferredDomainRenderingTests.swift` (M10.3) — end-to-end fixture tests.

## Closes after M10 ships

After M10, TestLifter's expanded-output surface ships its second concrete pattern (round-trip-pair domain narrowing). The PRD §7.8 expanded-outputs row is further closed; equivalence-class detection (M11) remains as the third concrete piece + Option A's general data-flow tracing remains as the v1.x M10.1 expansion.

The v1.1 trajectory is now formally open. Subsequent work either pivots to M11 (equivalence-classes, the §7.8 third example) or M10.1 (Option A general data-flow), or to non-§7.8 v1.1+ items (`SemanticIndex`, IDE integration, `swift-infer apply`, `swift-infer metrics` per PRD §20). v1.1 tags either after M10 alone (single-milestone v1.1) or after M11 (paired v1.1) — open scheduling decision.
