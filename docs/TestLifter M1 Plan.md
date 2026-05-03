# TestLifter M1 Execution Plan

Working doc for the TestLifter M1 milestone defined in `SwiftInferProperties PRD v0.4.md` §7.9. Decomposes M1 into seven sub-milestones so progress is checkable session-by-session. **Ephemeral** — archive to `docs/archive/TestLifter M1 Plan.md` once M1 ships and the §7.9 acceptance bar is met (mirroring TemplateEngine M1–M8).

> **TestLifter M1 lights up the seam that's been dormant since TemplateEngine M3.5.** It ships a SwiftSyntax test-body parser + the PRD §7.2 slicing pass + an assert-after-transform round-trip detector, plus the CLI glue that feeds TestLifter-derived identities into TemplateEngine's `crossValidationFromTestLifter` parameter. After M1, a function whose round-trip pair fires on the signature side AND has matching round-trip evidence in the test target picks up the `+20` cross-validation signal that PRD §4.1 has been promising since v0.2. The four other M1 deliverables that PRD §7.9 lists (parser, slicing, assert-after-transform, round-trip suggestion) are the *substrate* for that seam — TestLifter M1 is the smallest TestLifter milestone that can measurably move the needle on TemplateEngine output.

## What M1 ships (PRD v0.4 §7.9 + §13 + §4.1)

> **M1 (TestLifter).** SwiftSyntax test body parser, slicing phase, assert-after-transform detection, round-trip suggestion. *(Verbatim from PRD §7.9.)*

Five concrete deliverables (one new vs. the bare PRD line — the cross-validation wiring that makes M1 user-visible):

1. **`SwiftInferTestLifter` library target** + `SwiftInferTestLifterTests` test target. Parallel to `SwiftInferTemplates`. New target keeps the boundary explicit — TemplateEngine never reaches into TestLifter internals and vice versa; they meet at the `crossValidationFromTestLifter: Set<SuggestionIdentity>` API contract that already exists in `SwiftInferTemplates.discover` (M3.5 dormant seam).

2. **`TestSuiteParser`** — SwiftSyntax-based scanner that emits a `TestMethodSummary` for every XCTest method (`XCTestCase` subclass methods starting with `test*`) AND every Swift Testing method (`@Test func`). Per PRD §7.9 M1: "M1 should target both. The slicing pass is the same; the SwiftSyntax shape of `@Test func` is well-defined." Body is preserved as raw `CodeBlockItemListSyntax` for the slicer to consume; the parser doesn't try to understand assertions yet.

3. **Slicer** — implements PRD §7.2's four rules verbatim: (1) anchor on terminal `XCTAssertEqual` / `#expect` / `XCTAssert*` / `#require`; (2) backward-slice contributing statements via SSA-like usage walk; (3) classify remaining statements as setup; (4) identify parameterized values (literals + variables initialized to literals). Returns a `SlicedTestBody { setup, propertyRegion, parameterizedValues }`. **Never throws** — when no terminal assertion is found, the property region is empty and the entire body classifies as setup. PRD §15: "slicing must always produce a valid (possibly empty) property region without throwing." Hard requirement — fuzz-tested in M1.6.

4. **`AssertAfterTransformDetector`** — runs against the *property region* of a sliced test (not the raw body). Recognizes the round-trip shape: `let y = transform(x); let z = inverseTransform(y); XCTAssertEqual(x, z)` and the `#expect(decode(encode(x)) == x)` shape. Per PRD §7.3: "Assert-after-Transform → round-trip." Idempotence (Assert-after-Double-Apply) and commutativity (Assert-Symmetry) are M2; ordering / count-change / reduce-equivalence are M5.

5. **CLI cross-validation wiring** — `discover` now scans both production `.swift` (existing TemplateEngine path via `FunctionScanner.scanCorpus`) AND test `.swift` (new TestLifter path via `TestSuiteParser.scanTests`). TestLifter's `LiftedSuggestion.identity` set is collected and passed to `TemplateEngine.discover(...)` via the existing `crossValidationFromTestLifter` parameter. The `+20` finally fires when `RoundTripTemplate`'s `SuggestionIdentity` matches a `LiftedSuggestion.identity` produced from the same function's tests. **CLAUDE.md repo-state line "Cross-validation `+20` from a real TestLifter is still gated on TestLifter M1 in this repo … M3.5's `crossValidationFromTestLifter` parameter remains dormant" closes after M1.5.**

### Important scope clarifications

- **TestLifter's own `LiftedSuggestion` entries do NOT yet enter the main `discover` suggestion stream in M1.** They contribute identities to the cross-validation set only. This keeps M1 from forcing a corresponding extension to `LiftedTestEmitter` / `InteractiveTriage+Accept`'s lifted-from-test accept flow — those are M2 (when the second + third patterns make a real "lifted suggestions stream" justifiable). Open decision #3 below covers the resolution.
- **Identity-hash equality across TemplateEngine and TestLifter is M1's load-bearing invariant.** PRD §7.5 specifies the hash as `(template ID, function signature canonical form, AST shape of property region)`. TemplateEngine M1.5 already shipped this hash for the signature-side suggestions; TestLifter M1.4 must produce a hash that — for the same `(template-name, target-function-signature)` pair — collides byte-identically with TemplateEngine's hash for that pair. The "AST shape of property region" component is intrinsically test-side; cross-validation matches on the canonicalized prefix `(template-name, target-function-signature)`, not the full hash. M1.4's design must keep these two components separable. See open decision #4.
- **No accept flow for lifted suggestions in M1.** `--interactive` continues to walk only TemplateEngine suggestions. The `+20`-boosted RoundTripTemplate suggestions still go through the existing M6 `[A/B/s/n/?]` prompt + M6.4 LiftedTestEmitter accept path. TestLifter's own writeouts (`Tests/Generated/SwiftInfer/<TestType>/<lifted-property>.swift`) ship in TestLifter M2 alongside the second pattern.
- **No TestLifter-side `decisions.json` persistence in M1.** That's TestLifter M6 (mirror of TemplateEngine M6). The TemplateEngine-side decisions write doesn't change in M1 — TemplateEngine still owns the decisions schema; TestLifter M6 will consume the same file.
- **No `// swiftinfer: skip` honoring on the test-side in M1.** TemplateEngine M1.5 ships skip-marker honoring for production `.swift` files (`SkipMarkerScanner`). TestLifter M6 will scan test files for the same marker shape; for M1 the test-side scan ignores skip markers (same posture as TemplateEngine M1 → M1.5). This is acceptable because M1's only user-visible output is the `+20` boost on TemplateEngine suggestions, and those suggestions still respect production-side skip markers.
- **Test directory discovery is heuristic, not configurable, in M1.** Default: scan any directory named `Tests` or matching `*Tests` under the discover root. `--test-dir <path>` override is M2+. PRD §3.6 step 1 specifies "the project's source tree and the test target" — the heuristic matches SwiftPM's idiomatic layout. Open decision #2.
- **Cross-validation matching is by signature-canonicalized identity prefix, not by file/line.** A `RoundTripTemplate` Suggestion against `encode/decode` in `Sources/Foo/Bar.swift` matches a `LiftedSuggestion` derived from `testRoundTripFooBar()` in `Tests/FooTests/BarTests.swift` if both resolve to the same `(template ID = "round-trip", function signature canonical form = "encode(_: Foo) -> Data | decode(_: Data) -> Foo")`. No file-path coupling; the hash is line-number-insensitive per PRD §7.5.
- **TemplateEngine's `RoundTripTemplate` already produces `SuggestionIdentity` values keyed by the function pair.** TestLifter M1.4 just needs to produce the same identity from the test-body slice. The "AST shape of property region" component appears as a *separate* identity field when LiftedSuggestions enter the main stream in M2; for cross-validation in M1, only the prefix is compared.
- **No new SwiftPM dependencies.** TestLifter consumes the existing `swift-syntax` (for parsing) + `Foundation` (for I/O) + `SwiftInferCore` (for `SuggestionIdentity` + the canonicalized signature shape). Mirrors TemplateEngine's dep posture.

## Sub-milestone breakdown

| Sub | Scope | Why this order |
|---|---|---|
| **M1.0** | **`SwiftInferTestLifter` target scaffolding.** New `Sources/SwiftInferTestLifter/` with a single shell file `SwiftInferTestLifter.swift` declaring `public enum TestLifter` (placeholder for the `discover(in:)` entry point landing in M1.5). New `Tests/SwiftInferTestLifterTests/` with one smoke test proving the dep graph resolves and `import SwiftInferTestLifter` works from the test target. `Package.swift` adds the `.target(name: "SwiftInferTestLifter", dependencies: ["SwiftInferCore"])` declaration + matching `.testTarget`. CLI target deliberately does NOT yet depend on `SwiftInferTestLifter` — that wire happens in M1.5. **Acceptance:** `swift package clean && swift test` green; new `SwiftInferTestLifterTests` suite contains 1 smoke test that passes. | Cleanest possible boundary first. M1.1+ build into the new target without touching the existing `SwiftInferTemplates` / `SwiftInferCLI` shape. |
| **M1.1** | **`TestSuiteParser` — XCTest + Swift Testing scanner.** New `Sources/SwiftInferTestLifter/TestSuiteParser.swift`. SwiftSyntax visitor emitting `TestMethodSummary { className, methodName, body: CodeBlockItemListSyntax, location: SourceLocation, harness: .xctest \| .swiftTesting }`. Recognizes (a) any function `func test...()` declared inside a class inheriting from `XCTestCase`; (b) any function annotated `@Test` (Swift Testing). Recurses into `Suite`-grouped test classes. Does NOT try to parse assertions — body stays raw for the slicer. Mirror of `FunctionScanner`'s shape: file-walking helper `TestSuiteParser.scanTests(directory:)` returns `[TestMethodSummary]`. **Acceptance:** unit tests cover (i) XCTestCase subclass with `test*` methods → one summary per method; (ii) `@Test func` at file scope → summary; (iii) `@Test func` inside a Swift Testing `@Suite` class → summary; (iv) non-test methods (helpers, `setUp`, `tearDown`) → not in output; (v) nested suites → flattened. | Independent of slicer / detector. M1.2 consumes the bodies it produces; M1.3 / M1.4 / M1.5 don't reach upstream of M1.2. |
| **M1.2** | **`Slicer` — PRD §7.2 four-rule pass.** New `Sources/SwiftInferTestLifter/Slicer.swift`. Public entry: `Slicer.slice(_ body: CodeBlockItemListSyntax) -> SlicedTestBody`. Implements (1) **terminal-assertion anchor** — last call expression in the body matching one of `XCTAssertEqual`, `XCTAssertTrue`, `XCTAssert`, `XCTAssertNotNil`, `#expect`, `#require` (full whitelist in `Slicer.AssertionWhitelist`); (2) **backward-slice** — collect every statement that contributes a value transitively used in the assertion's argument list (via `IdentifierExprSyntax` resolution against locally-bound `let`/`var` declarations); (3) **setup classification** — every statement not in the slice goes into `setup`; (4) **parameterized values** — within the slice, expressions matching `IntegerLiteralExprSyntax` / `StringLiteralExprSyntax` / `BooleanLiteralExprSyntax` / `FloatLiteralExprSyntax` and `let x = <literal>` patterns are tagged. Returns `SlicedTestBody { setup: [CodeBlockItemSyntax], propertyRegion: [CodeBlockItemSyntax], parameterizedValues: [ParameterizedValue] }`. **Empty property region** when no terminal assertion → entire body in `setup`, empty slice, empty params. **PRD §15 contract: never throws.** Add fuzz test in M1.6 that runs the slicer on 100 randomly-generated test-body ASTs and asserts non-throwing. | Standalone pass over already-parsed bodies. M1.3 consumes its output. Independent of M1.1's parser shape — slicer takes a `CodeBlockItemListSyntax`, doesn't care how it was loaded. |
| **M1.3** | **`AssertAfterTransformDetector` — round-trip pattern.** New `Sources/SwiftInferTestLifter/AssertAfterTransformDetector.swift`. Public entry: `AssertAfterTransformDetector.detect(in: SlicedTestBody) -> [DetectedRoundTrip]`. Walks the property region looking for two distinct call expressions that compose: `let intermediate = forward(input); let recovered = backward(intermediate); XCTAssertEqual(input, recovered)` (or the `#expect(backward(forward(x)) == x)` collapsed form). Returns `DetectedRoundTrip { forwardCallee: String, backwardCallee: String, inputBindingName: String, recoveredBindingName: String?, assertionLocation: SourceLocation }`. Names extracted from the call expression's `calledExpression` (function references; method calls flatten via `.member`). **Per-shape acceptance:** (i) explicit two-binding shape → detected; (ii) collapsed `#expect(decode(encode(x)) == x)` shape → detected (one DetectedRoundTrip with `recoveredBindingName == nil`); (iii) shape where forward and backward are method calls on different receivers → not detected (round-trip requires the value to flow forward → backward, not switch receivers); (iv) shape where the assertion compares two unrelated values → not detected. | Reads slicer output. Doesn't yet emit a Suggestion — that's M1.4. Decoupling lets M1.4 own the identity-hash construction without M1.3 needing to know about hashes. |
| **M1.4** | **`LiftedSuggestion` + identity hashing.** New `Sources/SwiftInferTestLifter/LiftedSuggestion.swift` declaring `public struct LiftedSuggestion { templateName: String; identity: SuggestionIdentity; testMethodSummary: TestMethodSummary; detectedRoundTrip: DetectedRoundTrip }`. `SuggestionIdentity` is reused from `SwiftInferCore` (already shipped in TemplateEngine M1.5). New `LiftedSuggestion.identity(for:)` static factory: takes a `DetectedRoundTrip` + the surrounding `TestMethodSummary` + the heuristically-resolved target function signature (the `forwardCallee` / `backwardCallee` names + their inferred type signature derived from the property region's binding declarations) and produces an identity whose canonicalized prefix `(template-name = "round-trip", function signature canonical form = "<forward> | <backward>")` matches `RoundTripTemplate`'s identity for the same pair. **Open decision #4** covers identity-prefix construction in detail. M1.4's tests assert hash equality between a hand-constructed RoundTripTemplate Suggestion identity and a parallel LiftedSuggestion identity for the same function pair. | Sets up the M1.5 cross-validation contract. The hash equality test in M1.4 is the load-bearing invariant for the whole milestone. |
| **M1.5** | **CLI cross-validation wiring.** Extends `Sources/SwiftInferCLI/SwiftInferCommand.swift`'s `discover` subcommand: after the existing `FunctionScanner.scanCorpus(directory:)` call, add `let liftedIdentities = try TestLifter.discover(in: directory).liftedSuggestions.map(\.identity)`. Pass `liftedIdentities` as a `Set<SuggestionIdentity>` to the existing `TemplateRegistry.discover(in:..., crossValidationFromTestLifter: liftedIdentities)` call (the parameter has been there since M3.5). New file `Sources/SwiftInferTestLifter/TestLifter.swift` declares `public enum TestLifter { public static func discover(in directory: URL) throws -> Artifacts }` where `Artifacts { liftedSuggestions: [LiftedSuggestion] }`. CLI target's `Package.swift` deps gain `"SwiftInferTestLifter"` (the M1.0 deferred wire). **Acceptance:** integration test under `Tests/SwiftInferIntegrationTests/` that constructs a synthetic temp project with `Sources/Foo/Codec.swift` defining `encode`/`decode` AND `Tests/FooTests/CodecTests.swift` containing a `testRoundTrip()` round-trip → runs `discover` → asserts the resulting RoundTripTemplate Suggestion has a `Signal(kind: .crossValidation, weight: 20, detail: "Cross-validated by TestLifter")` in its score. | First user-visible M1 piece. Depends on M1.1–M1.4. Doesn't touch `--interactive` / `LiftedTestEmitter` / decisions persistence. |
| **M1.6** | **Validation suite.** Adds (a) **slicer fuzz test** — generates 100 random test-body ASTs (via a `TestBodyGenerator` helper that combines random `let`/`var` decls + random call expressions + optional terminal assertions) and asserts `Slicer.slice(_:)` never throws and always returns a `SlicedTestBody` with `setup ∪ propertyRegion = body`; (b) **per-shape goldens** — 5 hand-curated test bodies (clean roundtrip; roundtrip with 3 setup stmts; roundtrip in `#expect` collapsed form; roundtrip inside `@Test` Swift Testing method; non-roundtrip body that should NOT detect) with byte-stable goldens for slicer output + detector output; (c) **§13 perf re-check** — synthetic 100-test-file corpus generated by a test helper, asserts `TestLifter.discover(in:)` completes in `< 3s` wall (PRD §13 row "TestLifter parse of 100 test files"); (d) **§16 #1 hard-guarantee extension** — runs `TestLifter.discover(in:)` against a fixture and snapshots the source-file tree before/after, asserts byte-identical (TestLifter never writes to source); (e) **end-to-end cross-validation integration test** (already written in M1.5; M1.6 just adds the perf + hard-guarantee tests). | Validation, not new code. Closes the M1 acceptance bar. |

## M1 acceptance bar

Mirroring PRD §7.9 + the v0.4 §5.8 acceptance-bar pattern, M1 is not done until:

a. **`SwiftInferTestLifter` library target ships and is consumed by `SwiftInferCLI`.** `Package.swift` declares the new target + test target; CLI target depends on it; `swift package clean && swift test` is green.

b. **`TestSuiteParser` recognizes both XCTest and Swift Testing methods.** XCTestCase subclasses with `test*` methods, `@Test func` declarations at file scope, and `@Test func` inside `@Suite` classes all surface as `TestMethodSummary` records with the correct `harness` enum value. Helper methods, `setUp`, `tearDown`, and non-test functions do not surface.

c. **`Slicer` implements PRD §7.2's four rules and never throws.** Terminal-assertion anchor walks the assertion whitelist (`XCTAssertEqual`, `XCTAssertTrue`, `XCTAssert`, `XCTAssertNotNil`, `#expect`, `#require`); backward-slice via SSA-like usage walk; setup classification covers the complement; parameterized values flag literals + `let x = <literal>` patterns. Empty property region for tests with no terminal assertion. Fuzz test (100 random test-body ASTs) confirms non-throwing.

d. **`AssertAfterTransformDetector` recognizes the round-trip shape in property regions.** Both the explicit two-binding form (`let y = forward(x); let z = backward(y); XCTAssertEqual(x, z)`) and the collapsed `#expect(backward(forward(x)) == x)` form. Receiver-mismatch and unrelated-comparison shapes are correctly rejected.

e. **`LiftedSuggestion.identity` matches `RoundTripTemplate.identity` for the same function pair.** Hash equality test in `SwiftInferTestLifterTests` constructs a RoundTripTemplate Suggestion and a LiftedSuggestion for the same `encode`/`decode` pair and asserts byte-identical canonicalized prefixes. This is the load-bearing invariant for cross-validation.

f. **`discover` produces RoundTripTemplate suggestions with a `+20` cross-validation signal** when the test target contains a matching round-trip pattern. Integration test under `SwiftInferIntegrationTests` constructs a synthetic project with `Sources/Foo/Codec.swift` (encode/decode) and `Tests/FooTests/CodecTests.swift` (testRoundTrip); the resulting Suggestion's `score.signals` includes one `Signal(kind: .crossValidation, weight: 20, detail: "Cross-validated by TestLifter")`.

g. **§13 performance budget for `TestLifter parse of 100 test files` (`< 3s` wall) holds** on the synthetic 100-test-file corpus. Regression test fails if exceeded.

h. **§16 #1 hard guarantee preserved** — TestLifter never writes to source files. Verified by `HardGuaranteeTests` extension that runs `TestLifter.discover(in:)` against a fixture and snapshots the source-file tree before/after.

## Out of scope for M1 (re-stated for clarity)

- **Idempotence / commutativity / monotonicity / count-change / reduce-equivalence pattern detection** — TestLifter M2 + M5.
- **Generator inference** (CaseIterable / RawRepresentable / memberwise-from-DerivationStrategist / Codable round-trip / `.todo`) — TestLifter M3.
- **Mock-based generator synthesis** from observed test construction — TestLifter M4.
- **TestLifter-side `decisions.json` persistence** — TestLifter M6 (mirror of TemplateEngine M6).
- **`// swiftinfer: skip` honoring on the test side** — TestLifter M6.
- **Counter-signal scanning** across test target (asymmetric assertions vetoing candidate symmetric properties) — TestLifter M7.
- **`swift-infer convert-counterexample`** — TestLifter M8.
- **Expanded outputs**: inferred preconditions, inferred domains, equivalence-class detection — TestLifter M9.
- **TestLifter's own `LiftedSuggestion` entries in the main `discover` suggestion stream + accept flow** — TestLifter M2 (when the second + third patterns make a real "lifted suggestions stream" justifiable; open decision #3 below).
- **Test directory `--test-dir` override** — TestLifter M2; M1 uses heuristic `Tests/` discovery.
- **Lifted property writeouts to `Tests/Generated/SwiftInfer/<TestType>/<lifted-property>.swift`** — TestLifter M2 (paired with the second pattern).
- **Cross-repo coordination with SwiftProtocolLaws.** No kit-side changes for TestLifter M1; the kit already exposes everything M1 needs (`SuggestionIdentity` lives in `SwiftInferCore`, not in the kit).

## Open decisions to make in-flight

1. **`TestLifter.discover(in:)` directory contract: same `directory: URL` as `TemplateRegistry.discover(in:)` (and let TestLifter walk the `Tests/` subtree heuristically), or a separate `testsDirectory: URL` argument?**
   - **(a) Same `directory: URL`; TestLifter heuristically scans `Tests/`-named subdirectories.** Zero-config UX; matches SwiftPM's idiomatic layout. CLI doesn't grow a new flag.
   - **(b) Separate `testsDirectory: URL` argument; CLI defaults to `<discover-root>/Tests` and surfaces `--tests-dir` for overrides.** Explicit. Adds CLI surface.
   - **Default unless reason emerges:** **(a) heuristic scan**. Matches the zero-config posture of `discover` (which already walks `Sources/` heuristically without a `--sources-dir` flag). Override flag deferred to M2 (when there's more reason to vary the scan root, e.g. monorepos with non-standard test layouts).

2. **Test directory heuristic: scan any directory named exactly `Tests`, or any directory matching `*Tests` (so e.g. `IntegrationTests/` is included)?**
   - **(a) Exactly `Tests`.** SwiftPM's convention. Simplest.
   - **(b) `Tests` OR `*Tests`.** Includes `IntegrationTests/`, `UITests/`, etc. — broader coverage but risks scanning generated/output directories named `*Tests`.
   - **(c) Any directory containing `XCTestCase` subclasses or `@Test func` declarations.** Behaviorally precise; scans every `.swift` file under `discover-root` looking for the AST shape, then keeps the directories that produce hits. Slowest.
   - **Default unless reason emerges:** **(b) `Tests` OR `*Tests`**. SwiftPM convention covers `Tests/`; the wider glob picks up `IntegrationTests/`, `UITests/`, and other idiomatic SwiftPM patterns without scanning every file. SwiftPM-generated `.build/` and `.swiftpm/` are explicitly excluded by name (mirror of `FunctionScanner`'s existing exclusion list).

3. **Should TestLifter's own `LiftedSuggestion` entries enter the main `discover` suggestion stream in M1, or stay internal-to-TestLifter for cross-validation only?**
   - **(a) Stay internal in M1; main stream entry in M2.** Cross-validation `+20` is the only user-visible payoff for M1. M2 brings the second pattern (idempotence) and at that point the stream-entry + LiftedTestEmitter-extension + accept-flow extension all justify their own milestone-shaped scope.
   - **(b) Enter main stream in M1.** Stream-entry forces extending `LiftedTestEmitter` to handle lifted-from-test stubs, extending `InteractiveTriage+Accept`'s dispatch, and extending `--include-possible` / tier filtering. Roughly doubles M1's surface area for one pattern.
   - **Default unless reason emerges:** **(a) stay internal in M1**. Keeps M1 tightly scoped to its load-bearing invariant (cross-validation hash equality). M2 amortizes the stream-entry work across two patterns.

4. **Identity-hash construction for cross-validation: full hash match including AST-shape-of-property-region, or canonicalized-prefix match excluding the AST shape?**
   - **(a) Canonicalized-prefix match** — `(template-name, function signature canonical form)` only. The "AST shape of property region" component (PRD §7.5) is intrinsically test-side; TemplateEngine's signature-side suggestions don't have a property region to hash. Cross-validation matches on the prefix; the AST-shape component appears only when LiftedSuggestions enter the main stream in M2.
   - **(b) Full-hash match** — both sides compute the same shape including a synthetic "AST shape" component that TemplateEngine derives from the function's *body* AST (not from a test). Adds a new derivation path on the TemplateEngine side.
   - **Default unless reason emerges:** **(a) canonicalized-prefix match**. PRD §7.5's "AST shape of property region" is explicitly test-region; deriving an equivalent from a production function's body to make the full hash match would be inventing new spec. The prefix match is well-defined and load-bearing — `RoundTripTemplate` already produces identities keyed by the canonicalized function signature (M1.5 of TemplateEngine). M1.4's tests assert prefix equality; the AST-shape component is set on LiftedSuggestion side but compared only when entering the main stream (M2).

5. **`TestLifter.Artifacts` shape: dedicated struct with `liftedSuggestions: [LiftedSuggestion]` only, or richer (e.g. include `slicedBodies: [SlicedTestBody]` for diagnostics)?**
   - **(a) Minimal `Artifacts { liftedSuggestions: [LiftedSuggestion] }`.** Cross-validation only needs the identities; CLI doesn't yet have anywhere to surface sliced-body diagnostics.
   - **(b) Richer `Artifacts { liftedSuggestions, slicedBodies, parsedTests }` for `--debug` / future tooling.** Forward-compatibility for TestLifter M2+.
   - **Default unless reason emerges:** **(a) minimal**. M1 doesn't need the richer shape; adding fields later is non-breaking (callers consume `liftedSuggestions` only). M2 / M6 can extend the struct as needed.

6. **`TestSuiteParser`'s file walker: separate from `FunctionScanner`'s file walker, or share?**
   - **(a) Separate walker.** TestLifter walks a (potentially) different subtree (`Tests/`), so its walker has different roots; sharing the implementation requires parameterizing the directory exclusion list (currently hard-coded to skip `.build/`, `.swiftpm/`, etc.). Two walkers with mostly-overlapping exclusion lists is a small duplication cost.
   - **(b) Shared `SwiftSourceFileWalker` extracted into `SwiftInferCore`.** One canonical walker; both TemplateEngine and TestLifter consume it. Refactoring change to `FunctionScanner` (small).
   - **Default unless reason emerges:** **(b) shared walker**. The walker logic is already centralized in `FunctionScanner.scanCorpus`'s helper — extracting a `SwiftSourceFileWalker` enum into `SwiftInferCore` is a small refactor that makes the M1 wiring cleaner. Defer to M1.5 (when the second walker actually appears) so the refactor is justified by the second consumer.

## New dependencies introduced in M1

`Package.swift` adds:
- New library target `SwiftInferTestLifter` depending on `SwiftInferCore` + `swift-syntax` (`SwiftSyntax` + `SwiftParser` products). Mirror of the `SwiftInferTemplates` dep shape.
- New test target `SwiftInferTestLifterTests` depending on `SwiftInferTestLifter`.
- M1.5: `SwiftInferCLI` target dep gains `"SwiftInferTestLifter"`.

No new external SwiftPM dependencies. SwiftProtocolLaws stays at `from: "1.9.0"` (M8.0). No kit-side changes.

## Target layout impact

```
SwiftInferProperties (this repo, M1.0–M1.6):
  Package.swift                     # + SwiftInferTestLifter target + test target  (M1.0)
                                    # CLI target dep gains SwiftInferTestLifter    (M1.5)
  Sources/
    + SwiftInferTestLifter/         # NEW MODULE                                   (M1.0)
        SwiftInferTestLifter.swift  # public enum TestLifter shell (M1.0; M1.5 fills `discover`)
        TestSuiteParser.swift       #                                              (M1.1)
        Slicer.swift                #                                              (M1.2)
        SlicedTestBody.swift        #                                              (M1.2)
        AssertAfterTransformDetector.swift  #                                      (M1.3)
        LiftedSuggestion.swift      #                                              (M1.4)
        TestLifter.swift            # discover(in:) entry point                    (M1.5)
    SwiftInferCLI/
        SwiftInferCommand.swift     # discover threads liftedIdentities into       (M1.5)
                                    #   TemplateRegistry.discover via the
                                    #   existing crossValidationFromTestLifter
                                    #   parameter (M3.5 dormant seam closes)
    SwiftInferCore/
        SwiftSourceFileWalker.swift # OPTIONAL (open decision #6 default `(b)`)    (M1.5)
                                    #   extracted from FunctionScanner.scanCorpus
                                    #   when TestLifter becomes the second consumer
  Tests/
    + SwiftInferTestLifterTests/    # NEW TEST TARGET                              (M1.0)
        SmokeTests.swift            # M1.0 — import + dep-graph smoke
        TestSuiteParserTests.swift  #                                              (M1.1)
        SlicerTests.swift           #                                              (M1.2)
        SlicerFuzzTests.swift       # 100-AST non-throwing fuzz                    (M1.6)
        AssertAfterTransformDetectorTests.swift  #                                 (M1.3)
        LiftedSuggestionTests.swift # identity-prefix-equality test (load-bearing) (M1.4)
        SlicerGoldenTests.swift     # 5 hand-curated body goldens                  (M1.6)
    SwiftInferIntegrationTests/
        TestLifterCrossValidationTests.swift     # M1.5 end-to-end +20 fires
        TestLifterPerformanceTests.swift         # §13 100-test-file < 3s          (M1.6)
        TestLifterHardGuaranteeTests.swift       # §16 #1 source-tree snapshot     (M1.6)
  docs/
    TestLifter M1 Plan.md           # THIS DOC (M1.0)
    archive/
      TestLifter M1 Plan.md         # AFTER M1 ships
```

## Closes after M1 ships

- **`CLAUDE.md` repo-state line** "Cross-validation `+20` from a real TestLifter is still gated on TestLifter M1 in this repo (no TestLifter target started); M3.5's `crossValidationFromTestLifter` parameter remains dormant" updates to reflect the seam closing.
- **`Sources/SwiftInferTemplates/TemplateRegistry+CrossValidation.swift`** docstring "Kept generic for the dormant seam — once TestLifter M1 ships…" updates with the actual TestLifter caller pattern.
- **`Sources/SwiftInferTemplates/InversePairTemplate.swift:205`** comment "TestLifter corroboration not yet wired (gated on TestLifter M1)" updates — InversePairTemplate's escalation path is *still* gated on TestLifter (the `inverse-pair` template doesn't get a round-trip test signal because non-Equatable types can't be sample-verified), so this comment is unchanged in M1; M2 might pick it up if idempotence corroboration helps; otherwise stays for v1.1+'s SemanticIndex.
- **`Sources/SwiftInferTemplates/MonotonicityTemplate.swift:244`** "TestLifter corroboration not yet wired (gated on TestLifter M1)" updates — MonotonicityTemplate's `Possible` → `Likely` escalation via test corroboration is gated on TestLifter detecting the monotonicity pattern in tests. M5 adds Assert-Ordering-Preserved → monotonicity to TestLifter; this comment updates then, not in M1.
