# TestLifter M14 — N-class `coversDomain` via Same-Target Enum Case Enumeration (Plan)

**Supersedes:** `docs/archive/TestLifter M13 Plan.md` axis-4 N-class deferral. M13.3 shipped:
- Two-class `coversDomain` via syntactic XCTAssertTrue/XCTAssertFalse pairing — fully working.
- N-class `coversDomain` field on `NClassEquivalenceClassHint` — wired through detector + renderer + accept-flow, but the detector always sets it `false` because `TypeDecl` doesn't yet carry enum case names. The renderer's exhaustiveness comment block is gated on `coversDomain == true`, so it currently never fires for N-class.

M14 closes that deferral. After M14 ships, an N-class corpus whose marker set covers every case of the predicate's same-target enum return type surfaces the exhaustiveness comment block automatically.

## v1.x trajectory framing

The M13 plan §"Closes after M13 ships" listed the deferred axis 4 enum-case enumeration as a "narrow follow-up; not §20". M14 IS that follow-up. Three reasons it's cleanly separable from M13:

1. **The data model + renderer are already in place.** `NClassEquivalenceClassHint.coversDomain` exists; `nClassEquivalenceClassFileContents` already emits the exhaustiveness comment when `coversDomain == true`. M14 just turns the bit on for the right candidates.
2. **The same-target constraint is well-defined.** `FunctionScanner` already enumerates every type declaration in the package; M14 extends `TypeDecl` with `enumCaseNames` and consumes them in the detector. No SemanticIndex required.
3. **No pipeline shape changes.** `LiftedSuggestionPipeline` already threads `[TypeDecl]` through to `LiftedSuggestionPipeline.promote(...)`; M14's wiring just propagates the same value to `equivalenceClassLifted` + `equivalenceClassHintMap`.

Opening this plan does NOT pull the rest of the v1.x trajectory in — PRD §20 (SemanticIndex, IDE integration, `swift-infer apply`, `swift-infer metrics`) plus M12 (general consumer-producer chain detection) plus M13.+ (multi-predicate equivalence classes, axis 3) stay deferred. M14 is the single milestone this plan covers.

## Scope-narrowing decision: same-target enums only

Following the M9 / M10 / M11 / M13 pattern of "ship the high-confidence narrow extension, leave speculative scope for later":

**M14 ships:**
- Same-target enum case enumeration via `TypeDecl.enumCaseNames`. The enum must be declared in the same package the discover loop is scanning.
- Case-coverage check uses identifier-token comparison, case-insensitive (matches the M13 plan OD #4 marker matching).
- Both bare cases (`case small`) and multi-binding cases (`case small, medium, large`) are recognized.
- Cases declared in `extension` blocks are merged into the same `TypeDecl.enumCaseNames` (the existing `TypeDecl` resolver already merges by name across files).

**M14 explicitly defers:**
- **Cross-target / cross-package enum coverage.** The M13 plan §"Out of scope" already names this as SemanticIndex territory. An imported `Size` enum from a sibling package won't fire `coversDomain`; the comment block surfaces without exhaustiveness.
- **Associated-value variants.** `case small(Int)` reports the case identifier `small` for marker matching; the ASSOCIATED value isn't part of the partition. The marker set still has to cover the case identifiers, not the associated tuples.
- **`@frozen` / `@unknown default` interaction.** `@frozen` enums could in principle prove exhaustiveness more confidently, but the v1.x check is structural (case-identifier coverage) — `@frozen` doesn't change the answer.
- **Statistical exhaustiveness.** The M13 plan OD #7 already deferred "100 sites tested across 4 buckets, no other case ever observed" heuristics; M14 inherits that posture.

Two reasons this scope is right:

1. **PRD §3.5 conservative-engine alignment.** Same-target case enumeration is verifiable from `FunctionScanner` output without inference; cross-target needs SemanticIndex. False positives on the `coversDomain` bit are particularly harmful — they encourage the user to author a "covers every case" property that's wrong.
2. **No new infrastructure.** `TypeDecl` extension is additive (new `[String]` field, `[]` default); `MemberBlockInspector` extension is a single static method; `NClassEquivalenceClassDetector` gets one new parameter. The pipeline already threads `[TypeDecl]`.

## What M14 ships

Building on M13.3's data model + renderer + accept-flow:

1. **`TypeDecl.enumCaseNames: [String]`** (`SwiftInferCore`). New stored field, `[]` default, populated only when `kind == .enum` (otherwise `[]`). Source order preserved. Codable additive (`decodeIfPresent ?? []` for back-compat with any persisted `TypeDecl` records — currently none, but the field becomes part of the public surface).

2. **`MemberBlockInspector.enumCaseNames(in:)`** (`SwiftInferCore`). New static method. Walks `EnumCaseDeclSyntax` nodes in the member block and extracts every case identifier from each `EnumCaseElementListSyntax`. Handles:
   - `case small` → `["small"]`
   - `case small, medium, large` → `["small", "medium", "large"]`
   - `case small(Int)` → `["small"]` (associated values stripped)
   - `case small = "S"` → `["small"]` (raw values stripped)
   - Empty body / no `EnumCaseDeclSyntax` → `[]`

3. **`FunctionScannerVisitor.makeTypeDecl(...)` populates `enumCaseNames`** when `kind == .enum`. For non-enum kinds, the field stays `[]`. The same merging behavior the existing `TypeDecl` resolver applies for `storedMembers` (enum cases declared in `extension`s land in a separate `TypeDecl(kind: .extension)` record; the consumer queries by `name` and unions across kinds when needed).

4. **`NClassEquivalenceClassDetector.detect(...)` accepts `typeDecls: [TypeDecl] = []`** as a new parameter. When the predicate's `returnTypeText` matches a `TypeDecl.name` AND `kind == .enum` (or an extension on the enum) AND `enumCaseNames` (unioned across same-name records) is non-empty, compute case coverage:
   - For each enum case `caseName`, check `markerSet.markers.contains { $0.lowercased() == caseName.lowercased() }`.
   - If every enum case is covered, set `hint.coversDomain = true`.
   - If any enum case is NOT covered, set `hint.coversDomain = false` (the partition isn't exhaustive).
   - If the return type isn't a same-target enum (no matching `TypeDecl`), set `hint.coversDomain = false` (no claim either way without SemanticIndex).
   - Empty enum (case-less) is a degenerate case — treat as `coversDomain = false` (no markers can cover an empty case set meaningfully).

5. **Pipeline wiring.** `LiftedSuggestionPipeline.equivalenceClassLifted(...)` and `equivalenceClassHintMap(...)` accept a new `typeDecls: [TypeDecl]` parameter. `Discover+Pipeline.collectVisibleSuggestions` passes `artifacts.typeDecls` (already in scope from `TemplateRegistry.discoverArtifacts`). The promote-side already takes `typeDecls`; the equivalence-class branch plumbs through.

6. **Renderer.** No changes — `nClassEquivalenceClassFileContents` already emits the exhaustiveness comment block when `hint.coversDomain == true`. M14's wiring just turns the bit on; the comment surfaces automatically.

7. **Validation suite.** New `TypeDeclEnumCaseTests` covers the `MemberBlockInspector` extension. New `NClassEquivalenceClassDetectorCoversDomainTests` covers the detector's coverage logic. Existing `EquivalenceClassRenderingNClassTests` extends the three-class enum corpus to assert the exhaustiveness comment now surfaces.

## Sub-milestone breakdown

| Sub | Scope | Why this order |
|---|---|---|
| **M14.0** | **`TypeDecl.enumCaseNames` + `MemberBlockInspector.enumCaseNames(in:)` + `FunctionScannerVisitor.makeTypeDecl` populate.** Extend `TypeDecl` with the new field; extend the inspector with the case-extraction pass; populate when `kind == .enum`. **Acceptance:** `TypeDeclEnumCaseTests` covers the bare / multi-binding / associated-value / raw-value extraction shapes; existing `FunctionScannerTests` stay green; existing `TypeDeclTests` stay green (the new field is additive with `[]` default). | Foundation. Pure data-model + scanning extension; no behavioral change downstream until M14.1 consumes it. |
| **M14.1** | **`NClassEquivalenceClassDetector.detect(candidate:predicateSummary:predicateArgGeneratable:typeDecls:)` consumes `[TypeDecl]` + computes `coversDomain`.** Add the parameter (default `[]` for back-compat with M13.2 callers + tests). Walk same-name `TypeDecl`s, union enum cases across primary + extension records, run case-coverage. **Acceptance:** `NClassEquivalenceClassDetectorCoversDomainTests` covers full-coverage → `coversDomain == true`; partial-coverage → `false`; non-same-target → `false`; empty-enum → `false`; case-insensitive marker matching honored; existing `NClassEquivalenceClassDetectorTests` + `NClassEquivalenceClassDetectorVetoTests` stay green (the new param defaults to `[]`, so existing test fixtures continue to compile + produce `coversDomain == false`). | Sequenced after M14.0 because the detector reads the new `TypeDecl` field. Pure-function pass; no pipeline changes yet. |
| **M14.2** | **Pipeline wiring + integration test.** `LiftedSuggestionPipeline.equivalenceClassLifted(...)` / `equivalenceClassHintMap(...)` accept a `typeDecls: [TypeDecl]` parameter (both default `[]`); `Discover+Pipeline.collectVisibleSuggestions` passes `artifacts.typeDecls`. **Acceptance:** `EquivalenceClassRenderingNClassTests` extension — three-class enum corpus (existing fixture's `enum Size { case small, medium, large }` + `MarkerSet(markers: ["Small", "Medium", "Large"])`) now surfaces `hint.coversDomain == true` AND the writeout includes the `Exhaustiveness:` line. Existing tests stay green. | Sequenced last; closes the M14 acceptance bar end-to-end. |

## M14 acceptance bar

Mirroring PRD §7.8 + §7.9 + the M9–M13 cadence, M14 is not done until:

a. **`TypeDecl.enumCaseNames` is a public field** with `[]` default + Codable additive round-trip. The same-name resolver unions cases across primary + extension records.

b. **`MemberBlockInspector.enumCaseNames(in:)` extracts case identifiers** from bare / multi-binding / associated-value / raw-value forms, in source order, with no duplicates.

c. **`FunctionScannerVisitor.makeTypeDecl` populates `enumCaseNames`** for `kind == .enum`. Other kinds get `[]` (the field is enum-specific).

d. **`NClassEquivalenceClassDetector.detect(...)` enforces:**
   - Same-target enum lookup via `typeDecls.first { $0.name == returnTypeText && ($0.kind == .enum || $0.kind == .extension) }` + extension union.
   - Case-coverage check via case-insensitive identifier match against `markerSet.markers`.
   - `hint.coversDomain == true` iff EVERY same-target enum case is covered by the marker set.
   - Cross-target / unresolved return type → `false` (conservative, no claim).
   - Empty enum case set → `false`.

e. **Pipeline wiring threads `[TypeDecl]`** from `Discover+Pipeline.collectVisibleSuggestions` through `LiftedSuggestionPipeline.equivalenceClassLifted` + `equivalenceClassHintMap` into the detector.

f. **End-to-end integration test** — `EquivalenceClassRenderingNClassTests`'s three-class enum fixture surfaces the exhaustiveness comment block automatically. The `acceptNClassThreeBucketCorpus` test extends to assert the new comment line.

g. **§13 100-test-file budget holds** — `TypeDecl.enumCaseNames` adds one `[String]` per enum decl; `O(decls)` cost. The detector's coverage check is `O(cases × markers)`; both cardinalities are small (real corpora rarely have >10 cases). Sub-millisecond per discover run.

h. **§13 row 4 memory ceiling holds** — adding `[String]` per enum `TypeDecl` is a few hundred bytes total on a typical corpus; well below the ceiling. The `[§13 row 4]` diagnostic log line surfaces the actual delta on every CI run.

i. **§16 #1 hard guarantee preserved** — M14 changes detector behavior; doesn't touch the writeout-target invariant.

j. **`Package.swift` stays at `from: "2.0.0"`** — no kit-side coordination needed.

## Out of scope for M14 (reaffirmed)

- **Cross-target / cross-package enum case enumeration.** SemanticIndex territory.
- **Associated-value-aware partition matching.** Case identifiers only; associated values aren't part of the marker semantics.
- **Statistical exhaustiveness heuristics.** Inherited M13 OD #7 deferral.
- **`@frozen` / `@unknown default` exhaustiveness reasoning.** Structural identifier coverage is enough for the v1.x posture.
- **Multi-predicate equivalence classes (M13's deferred axis 3).** Same SemanticIndex-sequencing constraint as M12.
- **Cross-repo coordination with SwiftPropertyLaws.** No kit-side changes.

## Open decisions to make in-flight

1. **Same-name `TypeDecl` extension union.** Default proposal: **(a) walk `typeDecls.filter { $0.name == returnTypeText && ($0.kind == .enum || $0.kind == .extension) }` and union `enumCaseNames`**. Rationale: enum cases declared in extensions are valid Swift; the existing `TypeDecl` resolver already merges by name for `inheritedTypes`. Reversible if extension-case discovery proves noisy.

2. **Marker matching case sensitivity.** Default proposal: **(a) case-insensitive identifier match** — same as the M13 plan OD #4 / `EquivalenceClassMarkerExtractor.classifyNClass` posture. Rationale: marker text in vocabulary is conventionally Title-cased (`"Small"`); enum cases are lowercase-first (`small`). Case-insensitive match handles both spellings.

3. **`TypeDecl.enumCaseNames` Codable round-trip on persisted records.** Default proposal: **(a) `decodeIfPresent ?? []`** — additive schema change consistent with `Vocabulary` / `MarkerTable` posture. Rationale: future-proofs against any case where `TypeDecl` Codable surfaces (currently none in production paths but `Equatable` test suites round-trip).

4. **Empty-enum (no cases) handling.** Default proposal: **(a) `coversDomain = false`** — degenerate case. Rationale: no marker set can meaningfully "cover" an enum with zero cases; emitting `true` would be a vacuous claim that confuses the reader.

5. **Generic enums (e.g., `enum Box<T> { case wrapped(T) }`).** Default proposal: **(a) treat the same as concrete enums** — extract case identifiers, attempt coverage check. The predicate's return type would be `Box<Foo>` etc.; the simple `returnTypeText == TypeDecl.name` check fails for generics. Acceptable false negative — `coversDomain` stays `false` on generic enums until SemanticIndex lands.

6. **Optional enum return types (`Size?`).** Default proposal: **(a) strip the trailing `?` for the type-name lookup**. Rationale: `Size?` predicates are common (`size(_:) -> Size?`); the extractor treats `Size?` as Equatable already (per `returnTypeIsLikelyEquatable`). For coverage, look up `Size` and compute coverage on the un-optional name; the `nil` value isn't in the marker set so `coversDomain` would be `false` — which is correct (the partition doesn't cover `nil`).

7. **Whether to include the M14 deferral (cross-target enums) in the rendered comment.** Default proposal: **(a) no — silence is the right posture for cross-target.** Adding "exhaustiveness check skipped: cross-target enum" as a comment line would clutter the output; users who expect the comment will notice its absence.

## New dependencies introduced in M14

None. All work is pure SwiftInferProperties internal — `TypeDecl` (already in `SwiftInferCore`), `MemberBlockInspector` (already in `SwiftInferCore`), `FunctionScannerVisitor` (already in `SwiftInferCore`), `NClassEquivalenceClassDetector` (already in `SwiftInferTestLifter`), `LiftedSuggestionPipeline` + `Discover+Pipeline` (already in `SwiftInferCLI`). `Package.swift` stays at `from: "2.0.0"`.

## Target layout impact

Source files modified:

- `Sources/SwiftInferCore/TypeDecl.swift` — add `enumCaseNames: [String]` field with `[]` default (M14.0).
- `Sources/SwiftInferCore/MemberBlockInspector.swift` (or split file if the existing one approaches the SwiftLint cap) — add `enumCaseNames(in:)` static method (M14.0).
- `Sources/SwiftInferCore/FunctionScannerVisitor+TypeDecls.swift` — populate `enumCaseNames` when `kind == .enum` (M14.0).
- `Sources/SwiftInferTestLifter/NClassEquivalenceClassDetector.swift` — add `typeDecls: [TypeDecl] = []` param + coverage check (M14.1).
- `Sources/SwiftInferCLI/LiftedSuggestionPipeline+EquivalenceClass.swift` — thread `typeDecls` parameter through (M14.2).
- `Sources/SwiftInferCLI/Discover+Pipeline.swift` — pass `artifacts.typeDecls` (M14.2).

Test files:

- `Tests/SwiftInferCoreTests/TypeDeclEnumCaseTests.swift` (M14.0) — case-extraction shape tests.
- `Tests/SwiftInferTestLifterTests/NClassEquivalenceClassDetectorCoversDomainTests.swift` (M14.1) — coverage-logic tests.
- `Tests/SwiftInferIntegrationTests/EquivalenceClassRenderingNClassTests.swift` (M14.2) — extend the three-class enum corpus assertion to cover the exhaustiveness comment.

## Closes after M14 ships

After M14, the §7.8 third example surface ships its full M13 plan acceptance bar — both two-class and N-class `coversDomain` annotations work end-to-end. The two named-deferred items from M13 (cross-target enum coverage, multi-predicate equivalence classes) stay tied to SemanticIndex and remain in the v1.x trajectory.

Subsequent work picks one of:

- **PRD §20 v1.1+ trajectory** — SemanticIndex (the largest single lift), IDE integration, `swift-infer apply`, `swift-infer metrics`.
- **M12** — General consumer-producer chain detection (M10 deferred Option A). Recommended sequencing: after PRD §20 SemanticIndex.
- **M13.+** — Multi-predicate equivalence classes (M13's deferred axis 3). Same sequencing constraint as M12.
- **M9.+** — `Float` / `Double` numerical-bound preconditions (M9 deferred). Independent of SemanticIndex.

The §7.8 row's expanded-output surface is now both shipped (M9 + M10 + M11) and generalized (M13 + M14). Subsequent v1.x work pivots to the §20 surface.
