# TestLifter M9 — Inferred Preconditions (Plan)

**Supersedes:** PRD v0.4 §7.9 row M9 ("Expanded outputs: inferred preconditions, inferred domains, equivalence-class detection") + §7.8.

## Scope-narrowing decision: preconditions only

PRD §7.9 row M9 lists three pieces: **inferred preconditions**, **inferred domains**, **equivalence-class detection**. These are wildly different complexity:

- **Preconditions** — detect literal patterns in `ConstructionRecord.observedLiterals` (already collected by M4.1). Local analysis. Small.
- **Inferred domains** — cross-call data-flow tracing (e.g. "every `decode(x)` call site uses an `x` produced by `encode(...)`"). Hard — requires whole-test-corpus slice correlation, not just per-test slicing.
- **Equivalence classes** — cross-test method name pattern matching (e.g. `testValid_*` vs `testInvalid_*` partitions). Speculative; the PRD example is hand-wavy.

Per the M5–M8 cadence (each milestone is scoped to ship in a few sub-milestones), shipping all three in one M9 would balloon to a 6–8 sub-milestone effort with two of the three pieces requiring genuinely new analysis infrastructure.

**This M9 plan ships PRECONDITIONS ONLY.** Inferred domains and equivalence-class detection are explicitly listed as out-of-scope for v1.0 M9 + deferred to future v1.x milestones. Three reasons:

1. **PRD §7.8 is forward-looking, not prescriptive.** The section is "ChatGPT's critique correctly observed" + three example patterns. The PRD doesn't bind M9 to all three; it scopes the section as "expanded outputs" with examples.
2. **Domains + equivalence-classes are speculative.** The §7.8 examples are illustrative ("a test that constructs MyData only with positive Int", "decode's domain is encoder output", "valid/invalid buckets") but neither has a concrete detection algorithm. M9 would have to invent detection criteria from scratch. Preconditions, by contrast, has a clear detection rule — observe literals, classify pattern.
3. **Preconditions alone is shippable + tested.** The §13 / §16 / §15 invariants extend cleanly to a literal-classifier pass on `ConstructionRecord`. The other two pieces would need new test infrastructure too.

The M5–M8 milestones each shipped 3 sub-milestones in a few hours of focused work. This narrowed M9 maintains that cadence. If the v1.x trajectory wants domains and equivalence-classes later, the corresponding M10 / M11 plans can ship them as standalone milestones.

## What M9 ships (PRD v0.4 §7.8 first example)

PRD §7.8 example: "A test that constructs `MyData` only with `value: positive Int` across every test site implies a precondition `value > 0`. TestLifter surfaces this as a generator constraint suggestion: 'consider `Gen<MyData>` with `Gen.int(in: 1...)` for the `value` field — observed only with positive values across 9 test sites.'"

M9 ships:

1. **`PreconditionInferrer`** — pure-function analysis pass. Given a `ConstructionRecordEntry` (M4.1's per-type construction record), examines each argument position's `observedLiterals` row and emits a `PreconditionHint` when the entire row matches one of the curated patterns:
   - **Numerical bounds**: all observed values for an `Int`/`Float`/`Double` position are `> 0`, `>= 0`, `< 0`, or within a closed range `[low, high]` that's narrower than the type's natural range.
   - **String non-emptiness**: all observed string literals have non-zero length.
   - **String length range**: all observed strings have length in `[low, high]`.
   - **Boolean monomorphism**: all observed values for a `Bool` position are `true` (or all `false`) — the position is effectively a constant; suggest dropping it from the generator or treating it as a config flag.

2. **`PreconditionHint` data model** — public struct in `SwiftInferCore`. Fields:
   - `position: Int` — argument-shape index the hint applies to.
   - `argumentLabel: String?` — the label at that position (for user-facing rendering).
   - `pattern: PreconditionPattern` (enum case) — `.positiveInt` / `.nonNegativeInt` / `.intRange(low: Int, high: Int)` / `.nonEmptyString` / `.stringLength(low: Int, high: Int)` / `.constantBool(value: Bool)`.
   - `siteCount: Int` — how many sites the pattern was observed on (for "across N test sites" rendering).
   - `suggestedGenerator: String` — recommended Swift expression (e.g. `Gen.int(in: 1...)`).

3. **Hints threaded through the suggestion pipeline.** `MockGenerator` (already shipped at M4.3) gets a new field `preconditionHints: [PreconditionHint]`. The lifted-pipeline mock-inference path populates it via `PreconditionInferrer.infer(from:)`. The accept-flow renderer surfaces hints as a `// Inferred precondition:` provenance comment line above each affected argument in the generated `Gen<T>` body — same pattern as M4.4's mock-inferred provenance line.

4. **Validation suite.** §13 perf re-check + §16 #1 hard-guarantee re-check + per-pattern detection unit tests + an end-to-end integration test confirming the provenance comment lands in a real fixture.

The non-goals — explicitly out of scope for M9, reaffirmed:

- **Inferred domains** (cross-call data-flow, e.g. "decode only ever sees encode output"). Future v1.x M10.
- **Equivalence-class detection** (test method name partitioning). Future v1.x M11.
- **Per-suggestion `whyMightBeWrong` widening** beyond the existing `// Inferred precondition:` provenance line. The hints surface but don't change tier or score.
- **Counterexample-driven precondition refinement** (M8 territory).
- **Cross-validation of preconditions against TemplateEngine annotations** (could be future work; the M9 hints are advisory only, not load-bearing).

### Important scope clarifications

- **Detection threshold reuses M4.3's `≥ 3 sites`.** A precondition observed on fewer sites is too thin to surface confidently. Same conservative threshold.
- **Per-position detection.** Each argument position is analyzed independently — `Doc(title: "x", count: 5)` with all titles non-empty + all counts > 0 produces TWO hints, one per position.
- **Pattern priority.** When multiple patterns match (e.g. all observed ints are `0`, `1`, `2` — both "non-negative" AND "range [0, 2]" apply), the most-specific pattern wins. Range > nonNegative > positive.
- **PRD §3.5 conservative bias.** A pattern is emitted ONLY if EVERY observed literal in the row matches; one outlier kills the hint. The PRD example "across 9 test sites" demands homogeneity.
- **Suggestion-side rendering is purely advisory.** The hint surfaces as a comment line in the generated stub; the generator the user sees still uses `Gen.int()` or `Gen<Int>.int()` — the hint says "consider `Gen.int(in: 1...)`". The user decides whether to apply it.
- **No new CLI flags.** M9 surfaces hints automatically through the existing `swift-infer discover` pipeline. No `--show-preconditions` flag (would be v1.1+ per the PRD §16 #6 v1.1+ scoping pattern).

## Sub-milestone breakdown

| Sub | Scope | Why this order |
|---|---|---|
| **M9.0** | **`PreconditionHint` + `PreconditionPattern` data model** in `SwiftInferCore`. New `Sources/SwiftInferCore/PreconditionHint.swift`. Public struct + enum + the `MockGenerator.preconditionHints: [PreconditionHint]` field threaded through with default-empty backwards-compat init. **Acceptance:** `PreconditionHintTests` covers the struct's Equatable conformance + the enum's case-iteration through the curated patterns. | Smallest possible refactor opening the door for M9.1's analysis pass. |
| **M9.1** | **`PreconditionInferrer.infer(from: ConstructionRecordEntry) -> [PreconditionHint]`** — pure-function analysis. Per-position detection across the curated patterns: numerical bounds, string non-empty, string length range, boolean constant. Curated `≥ 3` site threshold mirrors M4.3. New `Sources/SwiftInferTestLifter/PreconditionInferrer.swift`. **Acceptance:** `PreconditionInferrerTests` covers each pattern's positive + negative cases (e.g. all-positive ints → `.positiveInt`; mixed signs → no hint; empty record → no hints; under-threshold → no hints). | Builds on M9.0's data model. Independent of M9.2. |
| **M9.2** | **Pipeline wiring + accept-flow rendering.** Extend `LiftedSuggestionPipeline.applyMockInferredFallback(...)` to call `PreconditionInferrer.infer(from:)` for each construction-record entry that produces a mock generator; populate `MockGenerator.preconditionHints`. Extend `LiftedTestEmitter+Generators.mockInferredGenerator(_:)` to render a `// Inferred precondition:` provenance comment line above each affected argument's generator expression. The user sees the hint inline in their generated stub without needing to read separate documentation. **Acceptance:** new `MockInferredPreconditionRenderingTests` covers the end-to-end path — synthetic corpus with `Doc(timestamp: 1, count: 5)` × 5 sites surfaces both `Inferred precondition: positive Int (across 5 sites)` lines in the rendered stub. | Sequenced after M9.1 because the pipeline call site needs the inferrer. |
| **M9.3** | **Validation suite.** Adds (a) §13 perf re-check — extend `TestLifterPerformanceTests` synthetic corpus with construction sites that trigger the inferrer; assert the `< 3s` budget holds with M9 active; (b) §16 #1 hard-guarantee re-check — implicit since M9 doesn't write to source files; (c) per-pattern unit tests for the inferrer (already covered by M9.1's tests but extended with edge cases — exactly-at-threshold, single-outlier-kills, multi-shape records); (d) end-to-end integration test under `SwiftInferIntegrationTests` confirming a real Sources/ + Tests/ fixture surfaces the precondition hint in the writeout. | Validation, not new code. Closes the M9 acceptance bar. |

## M9 acceptance bar

Mirroring PRD §7.9 + §7.8 + the v0.4 §5.8 acceptance-bar pattern + the M5/M6/M7/M8 cadence, M9 is not done until:

a. **`PreconditionHint` + `PreconditionPattern` are public types in `SwiftInferCore`.** `MockGenerator` carries `preconditionHints: [PreconditionHint]` with default-empty init.

b. **`PreconditionInferrer.infer(from:)` recognizes all four curated pattern families** (numerical bounds, string non-empty, string length range, boolean constant) when the construction record's observedLiterals row matches.

c. **`≥ 3` site threshold enforced.** Under-threshold records produce no hints.

d. **Pattern priority resolved.** When multiple patterns match the same observation, the most-specific wins (range > nonNegative > positive).

e. **One outlier kills the hint.** PRD §3.5 conservative bias: if any observed literal in a row deviates from the pattern, no hint emits.

f. **Pipeline wiring populates `MockGenerator.preconditionHints` automatically** during the M4.3 lifted-pipeline mock-inference pass.

g. **Accept-flow renderer surfaces hints as `// Inferred precondition:` provenance comments** in the generated `Gen<T>` body, one per affected argument.

h. **§13 100-test-file budget holds with M9.0–M9.2 active.** The added work (per-position pattern matching) is sub-millisecond per construction record.

i. **§16 #1 hard guarantee preserved** — M9 adds no source-tree writes (the existing M4.4 + M3.3 writeout paths surface the hints as comments inside their existing files).

j. **`Package.swift` stays at `from: "1.9.0"`** — no kit-side coordination needed for M9.

## Out of scope for M9 (re-stated for clarity)

- **Inferred domains** — future v1.x M10. The PRD §7.8 example "decode's domain is encoder output" requires cross-call data-flow tracing the v1.0 surface doesn't have infrastructure for.
- **Equivalence-class detection** — future v1.x M11. The PRD §7.8 example "valid/invalid buckets via parallel construction patterns" requires test-method-name partition heuristics that go beyond the M1–M8 detector model.
- **`whyMightBeWrong` widening for hints.** Hints render as advisory comments only.
- **Counterexample-driven hint refinement** — M8 territory.
- **Cross-validation of hints against TemplateEngine annotations** — out of v1.0 scope.
- **`--show-preconditions` CLI flag** — v1.1+ per the §16 #6 v1.1+ scoping pattern.
- **Cross-repo coordination with SwiftProtocolLaws.** No kit-side changes for M9.

## Open decisions to make in-flight

1. **Pattern coverage for floats.** Default proposal: M9 only handles `Int` for the numerical-bounds patterns. `Float`/`Double` add precision-class concerns (e.g. NaN, infinity) that complicate detection. **Default: (a) `Int` only for v1.0 M9.** Reversible if real corpora show value.

2. **Boolean-constant pattern: emit hint or veto generator?** A constructor where every site passes `true` for a `Bool` field could mean (a) the field is effectively a constant the user should drop, OR (b) the test corpus didn't cover the `false` case. Default proposal: emit hint as a caveat ("observed only `true` across 5 sites — false case may be untested") rather than vetoing. **Default: (a) emit advisory hint, no generator change.**

3. **String-length range: what bounds count as "narrow"?** `["", "a", "ab", "abc"]` has range `[0, 3]` which is narrower than `Int.max` but might be coincidental. Default proposal: emit hint when range is bounded AND ≥ 3 sites observed AND at least 2 distinct lengths (filter trivial single-length cases since those are caught by `.constantBool` analog for strings). **Default: (a) emit hint when range ≥ 2 distinct lengths + bounded.**

4. **Hint accumulation: merge overlapping hints or emit each pattern independently?** When `[1, 2, 5]` matches both `.positiveInt` AND `.intRange(low: 1, high: 5)`, default proposal: emit ONE hint at the most-specific pattern (range), drop the broader (positive). **Default: (a) most-specific only.**

5. **`MockGenerator.preconditionHints` field placement: on `MockGenerator` or on `Suggestion`?** Default proposal: on `MockGenerator` since the hints are tied to the constructor's argument shape (which `MockGenerator` already encodes). Suggestions without a mock generator don't carry hints. **Default: (a) field on `MockGenerator`.**

## New dependencies introduced in M9

None. All work is pure SwiftInferProperties internal — `ConstructionRecord` (already in `SwiftInferTestLifter`), `MockGenerator` (already in `SwiftInferCore`), `LiftedSuggestionPipeline` (already in `SwiftInferCLI`), `LiftedTestEmitter+Generators` (already in `SwiftInferTemplates`). `Package.swift` stays at `from: "1.9.0"`.

## Target layout impact

Two new source files:
- `Sources/SwiftInferCore/PreconditionHint.swift` (M9.0) — public struct + enum + `MockGenerator` field thread-through.
- `Sources/SwiftInferTestLifter/PreconditionInferrer.swift` (M9.1) — pure-function analysis pass.

Two existing source files modified:
- `Sources/SwiftInferCLI/LiftedSuggestionPipeline.swift` — call `PreconditionInferrer.infer(from:)` inside `applyMockInferredFallback`; populate the mock-generator's hints field.
- `Sources/SwiftInferTemplates/LiftedTestEmitter+Generators.swift` — render `// Inferred precondition:` comment lines per hint.

Test files:
- `Tests/SwiftInferCoreTests/PreconditionHintTests.swift` (M9.0) — model-shape tests.
- `Tests/SwiftInferTestLifterTests/PreconditionInferrerTests.swift` (M9.1) — per-pattern detection tests.
- `Tests/SwiftInferIntegrationTests/MockInferredPreconditionRenderingTests.swift` (M9.2 + M9.3) — end-to-end fixture test.

## Closes after M9 ships

After M9, TestLifter's expanded-output surface ships its first concrete pattern (preconditions). The PRD §7.8 expanded-outputs row is partially closed; inferred domains + equivalence-classes remain as future v1.x work. The v1.0 TestLifter surface is now complete with preconditions as a bonus shippable; the PRD §20 v1.1+ trajectory (SemanticIndex / IDE integration / `swift-infer apply` / `swift-infer metrics`) consumes the hint surface unchanged.
