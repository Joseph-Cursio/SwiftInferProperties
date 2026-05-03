# TestLifter M2 Execution Plan

Working doc for the TestLifter M2 milestone defined in `SwiftInferProperties PRD v0.4.md` §7.9. Decomposes M2 into five sub-milestones so progress is checkable session-by-session. **Ephemeral** — archive to `docs/archive/TestLifter M2 Plan.md` once M2 ships and the §7.9 acceptance bar is met (mirroring TestLifter M1 + TemplateEngine M1–M8).

> **TestLifter M2 lights up cross-validation `+20` for two more templates.** TestLifter M1 closed the round-trip half of the cross-validation seam; M2 extends the same machinery to the **idempotence** and **commutativity** templates. After M2, a function whose `IdempotenceTemplate` suggestion fires on the signature side AND has matching `f(f(x)) == f(x)` evidence in the test target picks up the `+20` cross-validation signal — same for `CommutativityTemplate` and `f(a, b) == f(b, a)`. The M1.4 `CrossValidationKey` shape (`templateName + sortedCalleeNames`) already covers single-callee templates (idempotence, commutativity both have one Evidence → one callee name); M2 just produces the matching key from the test side.

## What M2 ships (PRD v0.4 §7.9)

> **M2 (TestLifter).** Double-apply (idempotence) and symmetry (commutativity) detection. *(Verbatim from PRD §7.9.)*

Three concrete deliverables, all additive on top of M1's library:

1. **`AssertAfterDoubleApplyDetector`** — runs against the *property region* of a sliced test (not the raw body), mirroring M1.3's `AssertAfterTransformDetector`. Recognizes the idempotence shape per PRD §7.3 ("Assert-after-Double-Apply → idempotence"): `let y = f(x); let z = f(y); XCTAssertEqual(y, z)` (explicit) and `XCTAssertEqual(f(f(x)), f(x))` / `#expect(f(f(x)) == f(x))` (collapsed). Returns a `DetectedIdempotence { calleeName, inputBindingName, assertionLocation }`.

2. **`AssertSymmetryDetector`** — recognizes the commutativity shape per PRD §7.3 ("Assert-Symmetry → commutativity"): `XCTAssertEqual(f(a, b), f(b, a))` and `#expect(f(a, b) == f(b, a))` (collapsed); `let lhs = f(a, b); let rhs = f(b, a); XCTAssertEqual(lhs, rhs)` (explicit). Returns a `DetectedCommutativity { calleeName, leftArgName, rightArgName, assertionLocation }`. Requires the two argument identifiers to be distinct (`a != b` by name) — `f(a, a) == f(a, a)` is a tautology and must not detect.

3. **`TestLifter.discover(in:)` fan-out** — extends the per-summary detection loop to call all three detectors (round-trip, double-apply, symmetry) and append a `LiftedSuggestion` per detection. Each new detection produces a `LiftedSuggestion` whose `crossValidationKey` matches the corresponding production-side template's key for the same function — `("idempotence", [calleeName])` and `("commutativity", [calleeName])` respectively.

### Important scope clarifications

- **TestLifter's own `LiftedSuggestion` entries STILL do NOT enter the main `discover` suggestion stream in M2.** The M1 plan's open decision #3 default `(a)` ("stay internal in M1; main stream entry in M2") was based on the assumption that M2's two new patterns would justify the stream-entry + LiftedTestEmitter-extension + accept-flow extension work. **M2 revisits that assumption and defaults to keeping LiftedSuggestion stream-internal through M2.** Reasoning: (i) the cross-validation `+20` payoff is already user-visible for three templates after M2 — three distinct templates lighting up the same seam is enough to call the seam "real" and validated; (ii) stream-entry forces extending `LiftedTestEmitter`, `InteractiveTriage+Accept`, the `--include-possible` filter, and the tier-rendering path simultaneously, which is a milestone-shaped lift on its own; (iii) deferring stream-entry to M3 (alongside generator inference) lets the stream-entry work land with a real generator inference layer behind it, which is what the lifted-from-test stubs would actually need to be useful in `Tests/Generated/SwiftInfer/`. Open decision #1 below covers the resolution.

- **No accept flow / `Tests/Generated/SwiftInfer/` writeouts for lifted suggestions in M2.** Same reasoning as M1.3 stream-entry. M3 (generator inference) is the natural moment.

- **No TestLifter-side `decisions.json` persistence in M2.** That's TestLifter M6 (mirror of TemplateEngine M6).

- **No `// swiftinfer: skip` honoring on the test-side in M2.** TestLifter M6.

- **No `--test-dir` override in M2.** Heuristic `Tests/` + `*Tests/` discovery from M1 stays; `--test-dir` deferred to M6 (alongside the rest of TestLifter's CLI surface widening). The M1 plan's "out of scope" line listed `--test-dir` as M2; M2 demotes it because (i) zero-config UX has held up across the M1 perf + integration tests, (ii) the `--test-dir` flag is consumed by the same call site that consumes `--decisions`, `--baseline`, etc., and bundling all of those into M6 keeps the CLI churn coherent.

- **No counter-signal scanning in M2.** PRD §4.1's "asymmetric assertion" `-25` row (a test that explicitly asserts `f(a, b) != f(b, a)` vetoing a candidate commutativity property) is **TestLifter M7**. M2's `AssertSymmetryDetector` recognizes the *positive* shape only.

- **Cross-validation matching stays by `CrossValidationKey` (templateName + sorted callee names).** No identity-shape changes in M2 — `IdempotenceTemplate` and `CommutativityTemplate` already produce a `Suggestion` whose derived `crossValidationKey` (one Evidence → one callee name) is what M2's LiftedSuggestion matches against.

- **No new SwiftPM dependencies.** TestLifter stays on `swift-syntax` + `Foundation` + `SwiftInferCore`. SwiftProtocolLaws stays at `from: "1.9.0"`.

## Sub-milestone breakdown

| Sub | Scope | Why this order |
|---|---|---|
| **M2.0** | **Refactor `LiftedSuggestion` to carry a `DetectedPattern` enum.** Replace `LiftedSuggestion.detectedRoundTrip: DetectedRoundTrip` with `LiftedSuggestion.pattern: DetectedPattern` where `enum DetectedPattern { case roundTrip(DetectedRoundTrip), idempotence(DetectedIdempotence), commutativity(DetectedCommutativity) }`. M2.1 + M2.2 add the new associated structs; M2.0 introduces the enum with one case (`.roundTrip`) so the M1 surface keeps compiling. Update `LiftedSuggestion.roundTrip(from:)` to wrap the M1 `DetectedRoundTrip` in `.roundTrip(...)`. Update existing M1 tests that read `lifted.detectedRoundTrip` to switch on `lifted.pattern`. **Acceptance:** all 764 existing tests still pass; `LiftedSuggestion.pattern` is the new public property; `DetectedRoundTrip` is unchanged. | Smallest possible refactor that opens the door for two new pattern shapes. Doing it before M2.1 / M2.2 means the new detectors land into a stable enum shape rather than each one bolting on a new optional field. |
| **M2.1** | **`AssertAfterDoubleApplyDetector` — idempotence pattern.** New `Sources/SwiftInferTestLifter/AssertAfterDoubleApplyDetector.swift`. Public entry: `AssertAfterDoubleApplyDetector.detect(in: SlicedTestBody) -> [DetectedIdempotence]`. Recognizes (a) **collapsed** — `XCTAssertEqual(f(f(x)), f(x))` / `#expect(f(f(x)) == f(x))` (and the swapped argument order), reusing M1.3's `SequenceExprSyntax` / `InfixOperatorExprSyntax` walk for the `==` shape; (b) **explicit** — `let y = f(x); let z = f(y); XCTAssertEqual(y, z)`, reusing M1.3's `collectBindings(in:)` helper to resolve `y` → `f(x)` and `z` → `f(y)` before asserting both call the same `f`. Single-callee invariant: the outer `f`, inner `f`, and (in the explicit form) the `let z = f(y)` binding must all reference the same callee name; otherwise `nil`. Returns `DetectedIdempotence { calleeName: String, inputBindingName: String, assertionLocation: SourceLocation }`. **Per-shape acceptance:** (i) collapsed `XCTAssertEqual(normalize(normalize(s)), normalize(s))` → detected; (ii) collapsed `#expect(normalize(normalize(s)) == normalize(s))` → detected; (iii) explicit two-binding shape → detected; (iv) two distinct callees `XCTAssertEqual(normalize(canonicalize(s)), canonicalize(s))` → not detected (different callees); (v) tautology `XCTAssertEqual(normalize(s), normalize(s))` → not detected (no double-apply). | Independent of M2.2. Reuses M1.3's collapsed/explicit shape vocabulary so the test goldens stay byte-comparable. |
| **M2.2** | **`AssertSymmetryDetector` — commutativity pattern.** New `Sources/SwiftInferTestLifter/AssertSymmetryDetector.swift`. Public entry: `AssertSymmetryDetector.detect(in: SlicedTestBody) -> [DetectedCommutativity]`. Recognizes (a) **collapsed** — `XCTAssertEqual(f(a, b), f(b, a))` / `#expect(f(a, b) == f(b, a))`; (b) **explicit** — `let lhs = f(a, b); let rhs = f(b, a); XCTAssertEqual(lhs, rhs)`. Single-callee invariant: both call sites must reference the same `f`. Distinct-argument invariant: the two argument identifier names must differ (`f(a, b)` vs `f(b, a)` → detected; `f(a, a)` vs `f(a, a)` → not detected, tautology). Argument-order invariant: the second call's arguments must be the reverse of the first's (`f(a, b)` paired with `f(b, a)` → detected; `f(a, b)` paired with `f(a, b)` → not detected). Returns `DetectedCommutativity { calleeName: String, leftArgName: String, rightArgName: String, assertionLocation: SourceLocation }`. **Per-shape acceptance:** (i) collapsed `XCTAssertEqual(merge(a, b), merge(b, a))` → detected; (ii) collapsed `#expect(union(s1, s2) == union(s2, s1))` → detected; (iii) explicit two-binding shape → detected; (iv) tautology `f(a, a) == f(a, a)` → not detected; (v) different callees `f(a, b) == g(b, a)` → not detected. | Independent of M2.1. Same per-shape vocabulary as M1.3 / M2.1 so the test goldens stay coherent. |
| **M2.3** | **LiftedSuggestion factories + `TestLifter.discover(in:)` fan-out.** Extend `LiftedSuggestion` with `static func idempotence(from: DetectedIdempotence) -> LiftedSuggestion` and `static func commutativity(from: DetectedCommutativity) -> LiftedSuggestion`. Each builds a `CrossValidationKey(templateName: "idempotence" \| "commutativity", calleeNames: [<calleeName>])`. Extend `TestLifter.discover(in:)`'s per-summary loop to call all three detectors (round-trip, double-apply, symmetry) and fan their detections into LiftedSuggestions via the matching factory. **Acceptance:** unit tests cover (i) `LiftedSuggestion.idempotence(from:)` produces `crossValidationKey == CrossValidationKey(templateName: "idempotence", calleeNames: ["normalize"])` from a `DetectedIdempotence(calleeName: "normalize", ...)`; (ii) parallel test for commutativity; (iii) `TestLifter.discover(in:)` against a fixture with mixed test methods (one round-trip, one idempotence, one commutativity) returns three LiftedSuggestions with the matching pattern enum cases and matching cross-validation keys. | Sets up the M2.4 cross-validation contract. The fan-out is the load-bearing wiring for M2's user-visible payoff. |
| **M2.4** | **Validation suite.** Adds (a) **per-shape goldens** — 5 hand-curated test bodies for idempotence (collapsed `#expect`, collapsed XCTAssertEqual, explicit two-binding, tautology negative, different-callee negative) and 5 for commutativity (collapsed `#expect`, collapsed XCTAssertEqual, explicit two-binding, tautology negative, different-callee negative) with byte-stable goldens for slicer + detector output; (b) **end-to-end cross-validation integration tests** — two parallels of M1.5's `TestLifterCrossValidationTests`: one constructs `Sources/Foo/Normalizer.swift` (with `func normalize(_:) -> ...`) + `Tests/FooTests/NormalizerTests.swift` (`testIdempotent` body) and asserts the resulting `IdempotenceTemplate` Suggestion's score includes a `Signal(kind: .crossValidation, weight: 20, detail: "Cross-validated by TestLifter")`; the other does the same for `merge` + commutativity; (c) **§13 perf re-check** — extend `TestLifterPerformanceTests` to assert the §13 100-test-file budget (`< 3s` wall) still holds with all three detectors active; (d) **§16 #1 hard-guarantee re-check** — extend `TestLifterHardGuaranteeTests` to confirm M2's new detectors don't introduce any source-tree writes; (e) **slicer fuzz extension** — the M1.6 `SlicerFuzzTests` 100-AST fuzz is unchanged but a new test asserts none of the three detectors throw on the same fuzz corpus (PRD §15 contract: detection passes never throw, mirror of slicer's contract). | Validation, not new code. Closes the M2 acceptance bar. |

## M2 acceptance bar

Mirroring PRD §7.9 + the v0.4 §5.8 acceptance-bar pattern, M2 is not done until:

a. **`LiftedSuggestion.pattern: DetectedPattern` is the public detection-carrier surface.** The M1 `detectedRoundTrip: DetectedRoundTrip` field is replaced by a `pattern: DetectedPattern` enum with three cases (`.roundTrip`, `.idempotence`, `.commutativity`). All existing M1 tests that read the M1 field are migrated to switch on `pattern`.

b. **`AssertAfterDoubleApplyDetector` recognizes the idempotence shape in property regions.** Both collapsed (`XCTAssertEqual(f(f(x)), f(x))`, `#expect(f(f(x)) == f(x))`) and explicit (`let y = f(x); let z = f(y); XCTAssertEqual(y, z)`) forms detect. Tautology (`f(s) == f(s)`) and different-callee (`f(g(x)) == g(x)`) shapes are correctly rejected.

c. **`AssertSymmetryDetector` recognizes the commutativity shape in property regions.** Both collapsed (`XCTAssertEqual(f(a, b), f(b, a))`, `#expect(f(a, b) == f(b, a))`) and explicit (`let lhs = f(a, b); let rhs = f(b, a); XCTAssertEqual(lhs, rhs)`) forms detect. Tautology (`f(a, a) == f(a, a)`) and different-callee (`f(a, b) == g(b, a)`) shapes are correctly rejected.

d. **`LiftedSuggestion.crossValidationKey` for new detections matches the production-side `IdempotenceTemplate` / `CommutativityTemplate` keys.** Hash equality test in `SwiftInferTestLifterTests` constructs an IdempotenceTemplate Suggestion + a parallel LiftedSuggestion from a `DetectedIdempotence` for the same `normalize` callee and asserts byte-identical `CrossValidationKey`. Parallel test for commutativity.

e. **`discover` produces `IdempotenceTemplate` + `CommutativityTemplate` suggestions with a `+20` cross-validation signal** when the test target contains the matching pattern. Two integration tests under `SwiftInferIntegrationTests` (parallels of M1.5's `TestLifterCrossValidationTests`) construct synthetic projects and assert the resulting Suggestion's `score.signals` includes one `Signal(kind: .crossValidation, weight: 20, detail: "Cross-validated by TestLifter")`.

f. **§13 performance budget for `TestLifter parse of 100 test files` (`< 3s` wall) holds** with all three detectors active. Regression test fails if exceeded.

g. **§16 #1 hard guarantee preserved** — M2's new detectors do not write to source files. Verified by extending `TestLifterHardGuaranteeTests`.

h. **Detection passes never throw on the M1.6 fuzz corpus** — extending the existing 100-AST fuzz to also run idempotence + symmetry detection asserts non-throwing for both.

## Out of scope for M2 (re-stated for clarity)

- **Generator inference** (CaseIterable / RawRepresentable / memberwise-from-DerivationStrategist / Codable round-trip / `.todo`) — TestLifter M3.
- **Mock-based generator synthesis** from observed test construction — TestLifter M4.
- **Ordering, count-change, reduce-equivalence pattern detection** — TestLifter M5.
- **TestLifter-side `decisions.json` persistence** — TestLifter M6.
- **`// swiftinfer: skip` honoring on the test side** — TestLifter M6.
- **`--test-dir` override** — TestLifter M6 (demoted from the M1 plan's "M2" listing — see open decision #2).
- **Counter-signal scanning** across test target (asymmetric assertions vetoing candidate symmetric properties) — TestLifter M7.
- **`swift-infer convert-counterexample`** — TestLifter M8.
- **Expanded outputs**: inferred preconditions, inferred domains, equivalence-class detection — TestLifter M9.
- **TestLifter's own `LiftedSuggestion` entries in the main `discover` suggestion stream + `Tests/Generated/SwiftInfer/` writeouts + accept flow** — TestLifter M3 (open decision #1 default; M1 plan defaulted this to M2 but M2 re-evaluates and defers).
- **Cross-repo coordination with SwiftProtocolLaws.** No kit-side changes for TestLifter M2.

## Open decisions to make in-flight

1. **Should TestLifter's `LiftedSuggestion` entries enter the main `discover` suggestion stream in M2, or stay internal-to-TestLifter for cross-validation only through M2?**
   - **(a) Stay internal through M2; main stream entry in M3.** Cross-validation `+20` is the user-visible payoff for M1 + M2 (three templates: round-trip, idempotence, commutativity). M3 brings generator inference and at that point the stream-entry + LiftedTestEmitter-extension + `Tests/Generated/SwiftInfer/` writeouts + `InteractiveTriage+Accept` extension all justify their own milestone-shaped scope, AND the lifted stubs would actually carry inferred generators (rather than `.todo` placeholders) by the time they surface to the user.
   - **(b) Enter main stream in M2.** Honors the M1 plan's open decision #3 framing ("M2 amortizes the stream-entry work across two patterns"). Roughly doubles M2's surface area, especially the `LiftedTestEmitter` arm work + the `InteractiveTriage+Accept` dispatch widening.
   - **Default unless reason emerges:** **(a) stay internal through M2**. Reasoning above. The M1 plan's open decision #3 framing assumed two patterns would be enough justification; in practice M3's generator inference is the better pairing for stream-entry because lifted stubs without inferred generators are less useful than the cross-validation seam they corroborate.

2. **Should M2 ship the `--test-dir` CLI override the M1 plan listed as M2 work?**
   - **(a) Defer to M6.** Bundles `--test-dir` with TestLifter M6's other CLI surface widenings (`--decisions`, `--baseline`-on-test-side, etc.). Heuristic discovery has held up across M1's perf + integration tests; no real user pressure for the override yet.
   - **(b) Ship in M2 per the M1 plan.** Adds a small CLI surface; non-controversial.
   - **Default unless reason emerges:** **(a) defer to M6**. Keeps M2 tightly scoped to PRD §7.9's M2 line. The M1 → M2 mapping for `--test-dir` was a coordination call in the M1 plan; now that we're at M2 and there's no SwiftInferProperties consumer asking for it, M6's bundled CLI widening is the better home.

3. **`DetectedPattern` enum vs. parallel sibling structs.**
   - **(a) Single `DetectedPattern` enum with one case per pattern.** Cleaner switch sites; one `LiftedSuggestion.pattern` field; M5's ordering / count-change / reduce-equivalence patterns each add an enum case without growing the suggestion's storage shape.
   - **(b) Parallel sibling structs (`DetectedRoundTrip`, `DetectedIdempotence`, `DetectedCommutativity`) each with their own `LiftedSuggestion.detected*: ...?` optional field.** Keeps the M1 surface unchanged (no `lifted.detectedRoundTrip → lifted.pattern` migration). Optional fields multiply with patterns; readers must check each `nil`.
   - **Default unless reason emerges:** **(a) `DetectedPattern` enum**. The M1 → M2 migration is a small one-time cost (M1's `lifted.detectedRoundTrip` reads in `LiftedSuggestionTests` are the only consumers); the enum scales to M5's three additional patterns without surface-area growth.

4. **Detector entry-point shape: free function `detect(in:)` per detector (M1.3 pattern), or shared `LiftedDetector` protocol the discover loop dispatches over?**
   - **(a) Free `static func detect(in:) -> [Detected*]` per detector.** Mirrors M1.3's `AssertAfterTransformDetector.detect(in:) -> [DetectedRoundTrip]`. Easiest read; no dispatch indirection.
   - **(b) Shared `protocol LiftedDetector { static func detect(in: SlicedTestBody) -> [DetectedPattern] }` the discover loop iterates over.** Lets M5's three additional detectors plug in without touching the discover loop.
   - **Default unless reason emerges:** **(a) free `static func detect(in:)`**. Three detectors is small enough to fan out by hand; the protocol abstraction would be premature. M5 can introduce the protocol when there are six detectors.

5. **Should the explicit-shape detection for idempotence / commutativity require the let-bound intermediate to be unused outside the assertion, or is "any binding referenced in the assertion" sufficient?**
   - **(a) Strict: intermediate bindings must be referenced ONLY in the assertion (and the next binding in the chain).** Reduces false positives where a `let y = f(x)` is incidentally used elsewhere.
   - **(b) Loose: any binding referenced in the assertion that points to the right call shape qualifies.** Simpler; matches M1.3's explicit-roundtrip detection which doesn't impose this constraint.
   - **Default unless reason emerges:** **(b) loose**. Matches M1.3's posture — the slicer already classifies anything not contributing to the assertion as setup, so by the time we're walking the property region a binding *is* contributing to the assertion. Adding a "used only here" check would diverge from M1.3 without a known false-positive case to motivate it.

6. **Should `AssertSymmetryDetector` recognize argument orders beyond literal reversal — e.g. `f(a, b, c) == f(b, a, c)` (partial reversal of two args, third unchanged)?**
   - **(a) Literal reversal of all arguments only — `f(a, b) == f(b, a)`.** The §5.2 commutativity template only fires on two-parameter functions, so the matching M2 detector mirrors that constraint. Cross-validation only matches single-callee keys; multi-arg partial-reversal would correspond to a different template.
   - **(b) Recognize argument-set permutations more generally.** Out-of-scope for the commutativity template; would need a new "partial-permutation" template to consume.
   - **Default unless reason emerges:** **(a) literal reversal of two arguments only**. Matches the production-side `CommutativityTemplate`'s two-parameter shape. If M5 grows a partial-permutation template, M5 can ship the matching detector then.

## New dependencies introduced in M2

None. SwiftPM dependencies stay at:
- `swift-syntax` (existing)
- `Foundation` (existing)
- `SwiftInferCore` (existing, intra-package)

`Package.swift` is unchanged. SwiftProtocolLaws stays at `from: "1.9.0"` (M8.0 / TestLifter M1).

## Target layout impact

```
SwiftInferProperties (this repo, M2.0–M2.4):
  Sources/
    SwiftInferTestLifter/
        LiftedSuggestion.swift              # DetectedPattern enum migration  (M2.0)
                                            # + idempotence(from:), commutativity(from:) factories (M2.3)
        + AssertAfterDoubleApplyDetector.swift  # NEW                          (M2.1)
        + AssertSymmetryDetector.swift          # NEW                          (M2.2)
        TestLifter.swift                    # discover loop fans out to all 3 detectors  (M2.3)
  Tests/
    SwiftInferTestLifterTests/
        LiftedSuggestionTests.swift         # migrate to switch on pattern    (M2.0)
        + AssertAfterDoubleApplyDetectorTests.swift  # NEW                    (M2.1)
        + AssertSymmetryDetectorTests.swift          # NEW                    (M2.2)
        + IdempotenceCrossValidationKeyTests.swift   # NEW key-equality test  (M2.3)
        + CommutativityCrossValidationKeyTests.swift # NEW key-equality test  (M2.3)
        SlicerFuzzTests.swift               # extend to run all 3 detectors   (M2.4)
        + IdempotenceGoldenTests.swift      # 5 hand-curated bodies           (M2.4)
        + CommutativityGoldenTests.swift    # 5 hand-curated bodies           (M2.4)
    SwiftInferIntegrationTests/
        + TestLifterIdempotenceCrossValidationTests.swift   # NEW             (M2.4)
        + TestLifterCommutativityCrossValidationTests.swift # NEW             (M2.4)
        TestLifterPerformanceTests.swift    # extend to cover all 3 detectors (M2.4)
        TestLifterHardGuaranteeTests.swift  # extend hard-guarantee re-check  (M2.4)
  docs/
    TestLifter M2 Plan.md                   # THIS DOC (M2.0)
    archive/
      TestLifter M2 Plan.md                 # AFTER M2 ships
```

## Closes after M2 ships

- **`CLAUDE.md` repo-state line** updates to reflect TestLifter M2 lighting up `+20` for idempotence + commutativity. The M1 line "TestLifter M1 shipped — cross-validation `+20` lights up end-to-end" extends to "TestLifter M1 + M2 shipped — cross-validation `+20` lights up for round-trip, idempotence, and commutativity" (or equivalent phrasing).
- **`docs/archive/TestLifter M1 Plan.md`** is unchanged (already archived); this `TestLifter M2 Plan.md` joins it after M2 ships.
- **`Sources/SwiftInferTemplates/MonotonicityTemplate.swift:244`** comment "TestLifter corroboration not yet wired (gated on TestLifter M1)" stays — M5 (Assert-Ordering-Preserved → monotonicity) is the unblocker, not M2.
- **`Sources/SwiftInferTemplates/InversePairTemplate.swift:205`** comment "TestLifter corroboration not yet wired (gated on TestLifter M1)" stays — neither idempotence nor commutativity helps the inverse-pair Possible→Likely escalation; the comment continues pointing at the M1 framing for as long as InversePair stays in v1's Possible tier.
- **`Sources/SwiftInferTestLifter/LiftedSuggestion.swift`** docstring "M1 only ships `\"round-trip\"`; M2+ adds `\"idempotence\"`, `\"commutativity\"`, etc." updates to reflect the closure of that "M2+" promise.
- **`Sources/SwiftInferTestLifter/TestLifter.swift`** docstring "M1 carries lifted round-trip suggestions only — M2+ extends with idempotence / commutativity / etc." updates similarly.
