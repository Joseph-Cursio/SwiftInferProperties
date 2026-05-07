# TestLifter M15 — `Float` / `Double` Numerical-Bound Preconditions (Plan)

**Supersedes:** `docs/archive/TestLifter M9 Plan.md` open-decision #1, "Pattern coverage for floats. Default proposal: M9 only handles `Int` for the numerical-bounds patterns. `Float`/`Double` add precision-class concerns (e.g. NaN, infinity) that complicate detection. Default: (a) `Int` only for v1.0 M9. Reversible if real corpora show value." M15 is the post-v1.0 reversal.

After M9 + M15, the M9 inferrer covers all four numerical-literal kinds the M4.1 `SetupRegionConstructionScanner` produces (`Int`, `Float`/`Double`, `String`, `Bool`). The renderer + accept-flow surfaces remain unchanged — M15 is a pure additive extension to `PreconditionPattern` + `PreconditionInferrer`.

## v1.x trajectory framing

The CLAUDE.md "open trajectory" lists M9.+ as the last named §7.8-trio narrow follow-up that is **not** SemanticIndex-dependent. PRD §20 (SemanticIndex), M12 (general consumer-producer chains), M13.+ (multi-predicate equivalence classes), and the M14 cross-target enum follow-up all need SemanticIndex first. M15 is independent — it operates on textual literals from the construction record, no semantic queries needed.

Three reasons it's cleanly separable:

1. **Inferrer surface area is small.** `PreconditionInferrer.detectPattern(kind: .float, column:)` currently returns `nil` (M9 plan OD #1 deferral). The constructive change is one new branch + one parser + four new pattern cases. Existing Int / String / Bool paths stay unchanged.

2. **Construction-record kind is already in place.** `ParameterizedValue.Kind.float` already exists (`SlicedTestBody.swift:76`); `SetupRegionConstructionScanner` already recognizes `FloatLiteralExprSyntax` and writes the literal source text to `observedLiterals` rows. M15 just consumes columns the scanner is already producing.

3. **Renderer is already pattern-agnostic.** `LiftedTestEmitter+Generators.swift` and `InteractiveTriage+AcceptM5.swift` render hints via the `suggestedGenerator` string + the pattern's surface description. New patterns flow through unchanged.

Opening this plan does NOT pull the rest of the v1.x trajectory in. M15 is the single milestone this plan covers.

## Scope-narrowing decision: precision-class hard-veto + finite-bound patterns

Following the M9 / M11 / M13 / M14 pattern of "ship the high-confidence narrow extension":

**M15 ships:**

- **`positiveDouble`** — every observed literal `> 0`. Suggested generator: `Gen.double(in: 0.0.nextUp...)` (advisory text; doesn't have to compile).
- **`nonNegativeDouble`** — every observed literal `>= 0`.
- **`negativeDouble`** — every observed literal `< 0`. Defensive (today's `SetupRegionConstructionScanner` doesn't admit negative `FloatLiteralExpr`s — they parse as `PrefixOperatorExpr` and become `.other` kind — but a future scanner widening might).
- **`doubleRange(low: Double, high: Double)`** — at least two distinct observed values, all finite, bounded between `low` and `high`. Most-specific pattern (preempts the sign-bound cases when both apply, mirroring M9's `intRange` priority per the M9 plan OD #4 most-specific rule).

**M15 explicitly defers:**

- **NaN / infinity literal recognition.** `Double.nan` / `Double.infinity` / `1.0 / 0.0` aren't `FloatLiteralExprSyntax` instances — they're member-access expressions or computed binary expressions, so they're already filtered out by the M4.1 scanner's kind classifier and never reach the inferrer's float column. Defensive: M15 still bails out (returns `nil`) on any column where literal-text parsing fails as a Swift `Double`. Treating the corpus's observed `.nan` literals (if any sneak through future scanner widening) as a hard kill is the conservative posture per PRD §3.5.
- **Subnormal awareness.** `1e-300` is finite but extremely small; the v1.x posture treats it as a normal observed value. `Double.leastNonzeroMagnitude` boundary detection would be statistical (M9 plan OD #7 territory).
- **Negative-zero distinction.** `-0.0` and `0.0` compare equal under `==`, and source-text parsing gives `0.0` for both after `Double` round-trip. v1.x conflates them.
- **IEEE 754 special-value generators.** `Gen.double` suggestions don't cover NaN or infinity even when the user might want them; that's a `swift-property-based` API concern, not an inferrer concern.
- **`Float` vs `Double` distinction.** The construction record's `ParameterizedValue.Kind.float` doesn't distinguish 32-bit `Float` from 64-bit `Double`. M15 reads literals as `Double` (which losslessly accepts both `Float` and `Double` literal source texts) and emits patterns parameterized by `Double`. The renderer's `Gen.double(...)` suggestion text is correct for both — `Float` callers would substitute `Gen.float(...)` manually if needed. Sub-millimeter narrowing per the conservative posture.
- **Hex / underscore-separated float literals.** `0x1.0p2` and `1_000_000.5` are valid Swift literal forms. M15's parser accepts underscore-separated forms (mirrors M9's `parseIntLiteral`); hex floats return `nil` and kill the column (conservative — same posture as M9's hex / octal / binary radix kill).

Three reasons this scope is right:

1. **PRD §3.5 conservative-engine alignment.** The narrow scope produces high-confidence hints (sign + range over fully-finite literals) and bails on any literal we can't parse. False positives on a `Float`/`Double` precondition are particularly bad — the user might author a property test asserting positivity when the corpus also contains `0.0` cases the scanner missed.

2. **No new infrastructure.** No new files in production; one new file in tests. `PreconditionPattern` enum gains four cases; `PreconditionInferrer` gains one parser + one detector arm. `MockGeneratorSynthesizer.swiftTypeName(for: .float)` already returns `"Double"`; the renderer's `// Inferred precondition:` comment-line shape is unchanged.

3. **Deferred Open Decision #1 is the explicit reversal.** The M9 plan named this as reversible "if real corpora show value". v1.1's adoption surface uncovered the value (any test corpus exercising numerical computation hits the deferral), so M15 closes the gap.

## What M15 ships

Building on M9.0's data model and M9.1's per-kind dispatch:

1. **`PreconditionPattern` extension** (`SwiftInferCore`):
   - `case positiveDouble` — every observed `Double` literal `> 0`, all finite.
   - `case nonNegativeDouble` — every observed `Double` literal `>= 0`, all finite.
   - `case negativeDouble` — every observed `Double` literal `< 0`, all finite. Defensive (current scanner doesn't produce; future-proof per the M9 `negativeInt` posture).
   - `case doubleRange(low: Double, high: Double)` — at least two distinct finite values; bounded; preempts the sign-bound patterns when both apply.

2. **`PreconditionInferrer.detectFloatPattern(_:)`** (`SwiftInferTestLifter`):
   - Replaces the `case .float: return nil` dispatch arm with a real implementation.
   - Parses each column entry via `parseDoubleLiteral` (mirrors `parseIntLiteral`'s shape: handles underscore separators; rejects hex / radix prefixes; rejects unparseable forms by returning `nil`, which kills the column per PRD §3.5).
   - Filters out non-finite parsed values (`!value.isFinite`) defensively — kills the column.
   - Applies the M9 OD #4 most-specific rule: 2+ distinct → `doubleRange`; else sign-bound (positive / non-negative / negative).

3. **Suggested generator strings** (`PreconditionInferrer.suggestedGenerator(for:)`):
   - `.positiveDouble` → `"Gen.double(in: 0.0.nextUp...)"`
   - `.nonNegativeDouble` → `"Gen.double(in: 0.0...)"`
   - `.negativeDouble` → `"Gen.double(in: ...0.0.nextDown)"`
   - `.doubleRange(low, high)` → `"Gen.double(in: \(low)...\(high))"`

4. **Validation suite extension** (`Tests/SwiftInferTestLifterTests/PreconditionInferrerFloatTests.swift`, new file): per-pattern positive + negative cases mirroring `PreconditionInferrerTests`'s shape. Existing M9.1 / M9.2 / M9.3 test suites stay green — the new `.float` arm doesn't disturb the other kinds' detection.

5. **Public-API back-compat.** `PreconditionPattern` is `Sendable, Equatable`. Adding cases is additive; consumers that exhaustively switch on the enum need to add the new cases (or default arms). Survey the call sites before sub-commits land.

6. **Renderer integration.** `LiftedTestEmitter+Generators.swift` and `InteractiveTriage+AcceptM5.swift` render hints via `hint.suggestedGenerator` (string) — they don't dispatch on the pattern enum cases. So new pattern cases flow through unchanged. Verify by inspection during M15.0.

## Sub-milestone breakdown

| Sub | Scope | Why this order |
|---|---|---|
| **M15.0** | **`PreconditionPattern` extension + renderer survey.** Add the four float pattern cases. Audit consumers (`LiftedTestEmitter+Generators`, `InteractiveTriage+AcceptM5`, any switch on `PreconditionPattern` cases) — confirm all are pattern-text-driven and need no dispatch update. **Acceptance:** `swift build` passes after the additive enum change; existing `PreconditionHintTests` stays green. | Foundation. Pure data-model addition + audit; no behavior change. |
| **M15.1** | **`PreconditionInferrer` float pattern detection.** Replace the `case .float: return nil` dispatch arm with a `detectFloatPattern` implementation. Add `parseDoubleLiteral` (underscore-tolerant; rejects hex / radix). Wire `suggestedGenerator` for the four new cases. **Acceptance:** new `PreconditionInferrerFloatTests` covers each pattern's positive + negative cases (all-positive doubles → `.positiveDouble`; mixed signs → no hint when single-distinct; multi-distinct → `.doubleRange`; unparseable → no hint; hex literal → no hint; under-threshold → no hint; non-finite parse result → no hint). Existing `PreconditionInferrerTests` stays green. | Sequenced after M15.0 because the detector emits the new pattern cases. |
| **M15.2** | **End-to-end integration verification.** Audit `MockInferredPreconditionRenderingTests` — does any existing fixture exercise float literals? If yes, add an assertion that the new hint surfaces. If no, add a small fixture covering the float-literal happy path through the M9.2 renderer + accept-flow stub. **Acceptance:** integration test corpus with three sites observing `1.5`, `2.5`, `3.5` for a Double parameter surfaces a `.doubleRange(low: 1.5, high: 3.5)` hint with the rendered comment block including the `Gen.double(in: 1.5...3.5)` suggestion text. | Closes the M15 acceptance bar end-to-end. |

## M15 acceptance bar

Mirroring PRD §7.8 + §7.9 + the M9 / M14 cadence, M15 is not done until:

a. **`PreconditionPattern` carries four float cases** (`positiveDouble`, `nonNegativeDouble`, `negativeDouble`, `doubleRange`) with the M9 most-specific-priority rule (range preempts sign-bound when both apply).

b. **`PreconditionInferrer.detectFloatPattern(_:)` enforces:**
   - Every column entry parses as a finite `Double` via `parseDoubleLiteral`.
   - Hex / radix-prefix / unparseable entries → kill the column (return `nil`).
   - Non-finite parse result → kill the column.
   - 2+ distinct finite values → `.doubleRange(low: min, high: max)`.
   - Single-distinct or all-equal values → sign-bound dispatch (positive / non-negative / negative).
   - All-zero column → `.nonNegativeInt` analog: emits `.nonNegativeDouble` since `0.0 >= 0`.

c. **`suggestedGenerator(for:)` returns plausible Swift expressions** for each new case (advisory comment text; doesn't have to compile, but must read as plausible `Gen.double(...)` invocations).

d. **`PreconditionInferrerFloatTests` covers** each pattern's positive case + negative cases (mixed signs, unparseable literals, hex literals, under-threshold, non-finite parse).

e. **End-to-end integration test surfaces a `.doubleRange` hint** through the M9.2 renderer + M9.3 accept-flow path on a fixture corpus exercising `Double` literals.

f. **Existing M9.1 / M9.2 / M9.3 / M9.4 test suites stay green.** The new `.float` dispatch arm is additive; no Int / String / Bool path changes.

g. **§13 100-test-file budget holds.** `parseDoubleLiteral` is sub-microsecond; per-position float-column scan is O(siteCount). Same big-O as the existing Int path.

h. **§13 row 4 memory ceiling holds** — no new persistent allocations.

i. **§16 #1 hard guarantee preserved** — M15 changes inferrer behavior; doesn't touch the writeout-target invariant.

j. **`Package.swift` stays at `from: "2.0.0"`** — no kit-side coordination.

## Out of scope for M15 (reaffirmed)

- **NaN / infinity literal recognition.** Filtered by the M4.1 scanner; defensive bail-out covers any future scanner widening.
- **Subnormal-aware bound detection.** Statistical (M9 plan OD #7).
- **Negative-zero distinction.** Conflated under `==`; source-text round-trip loses the sign anyway.
- **IEEE 754 special-value generator suggestions.** `swift-property-based` API surface concern.
- **`Float` vs `Double` source-type distinction.** Construction record kind is unified.
- **Hex / `0x1.0p2` literal parsing.** Conservative kill mirrors M9's int hex / radix posture.
- **Cross-repo coordination with SwiftPropertyLaws.** No kit-side changes.

## Open decisions to make in-flight

1. **Generator-suggestion text precision.** Default proposal: **(a) `Gen.double(in: 0.0.nextUp...)` for `positiveDouble`** — mirrors the `Gen.int(in: 1...)` form (smallest valid value as the lower bound). The advisory comment doesn't have to compile against a real `Gen.double` API; the user reads + adapts. Alternative: just say `Gen.double(positive: true)` if a future `Gen.double` API supports it. **Default: (a)** — explicit numeric bound is unambiguous.

2. **`doubleRange` lower-bound rendering when min == 0.0.** Default proposal: **(a) emit `Gen.double(in: 0.0...high)`** — preserve the observed minimum verbatim. Alternative: rewrite to `nonNegativeDouble` form. **Default: (a)** — most-specific rule (M9 OD #4) wins; range emission is the documented contract.

3. **Trailing-zero / scientific-notation rendering for the suggested generator.** Default proposal: **(a) `String(describing: value)` for the bound emission** — Swift's default `Double` formatting (`1.5`, `1e10`, etc.). Alternative: format-string controls. **Default: (a)** — keeps the comment text faithful to observed source.

4. **Generic-placeholder return type matching the M9 inferrer's posture.** Default proposal: **(a) inherit M9's `column.compactMap { row in row[position] }` shape** — no kind-specific changes to the per-position scan. **Default: (a)** — inferrer dispatch happens inside `detectPattern`.

5. **Whether to lift `parseDoubleLiteral` into `SwiftInferCore` for reuse.** Default proposal: **(a) keep it `private` in `PreconditionInferrer`** — no other callers need it. **Default: (a)** — no premature abstraction.

6. **Whether to extend `MockGenerator.preconditionHints` rendering for the new patterns.** Default proposal: **(a) no change required** — `hint.suggestedGenerator` text drives the renderer; new pattern cases produce new comment lines via the existing path. **Default: (a)** — verify in M15.0 audit.

## New dependencies introduced in M15

None. All work is pure SwiftInferProperties internal — `PreconditionPattern` (already in `SwiftInferCore`), `PreconditionInferrer` (already in `SwiftInferTestLifter`). `Package.swift` stays at `from: "2.0.0"`.

## Target layout impact

Source files modified:

- `Sources/SwiftInferCore/PreconditionHint.swift` — add four `Float`/`Double` cases to `PreconditionPattern` (M15.0).
- `Sources/SwiftInferTestLifter/PreconditionInferrer.swift` — replace the `case .float` dispatch arm with `detectFloatPattern`; add `parseDoubleLiteral`; wire `suggestedGenerator` for the four new cases (M15.1).

Test files:

- `Tests/SwiftInferTestLifterTests/PreconditionInferrerFloatTests.swift` (new, M15.1) — per-pattern positive + negative coverage.
- `Tests/SwiftInferIntegrationTests/MockInferredPreconditionRenderingTests.swift` (M15.2 extension) — float-literal end-to-end fixture.

Existing `PreconditionInferrerTests` + `PreconditionHintTests` stay green via the additive enum extension.

## Closes after M15 ships

After M15, the M9 inferrer covers all four `ParameterizedValue.Kind` cases the construction-record scanner produces. The §7.8 first-example surface (preconditions) is functionally complete for the v1.x scanner shape. Subsequent v1.x work pivots to the §20 surface (SemanticIndex + IDE integration + `swift-infer apply` + `swift-infer metrics`) or the deferred narrow follow-ups that need SemanticIndex sequencing (M12 general consumer-producer chains, M13.+ multi-predicate equivalence classes, M14 cross-target enum coverage).

After M15, the only remaining narrow follow-up that's independent of SemanticIndex is **release versioning** — a v1.2 cut covering M13 + M14 + M15 with a perf re-baseline pinned at `docs/perf-baseline-v1.2.md`. That's a release plan, not a milestone.
