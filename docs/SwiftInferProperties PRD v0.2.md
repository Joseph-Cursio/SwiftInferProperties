# Product Requirements Document

## SwiftInfer: Type-Directed Property Inference for Swift

**Version:** 0.2 Draft
**Status:** Proposal
**Audience:** Open Source Contributors, Swift Ecosystem
**Depends On:** SwiftProtocolLaws (ProtocolLawKit + ProtoLawMacro), v1.5+
**Supersedes:** `_9_SwiftInferProperties PRD.md` (v0.1, preserved)

> **What changed from v0.1.** v0.2 incorporates the Gemini critique and the algebraic-structures notes (`_4a_`, `_4c_`). The five biggest shifts are: (1) the binary `Strong/Likely/Possible` tier is replaced by a **weighted scoring engine** with explicit signal weights and counter-signals; (2) the template catalog is expanded with **algebraic-structure detectors** (semigroup, monoid, group, semilattice, ring) feeding a new **Property-Driven Refactoring** output that suggests protocol conformances back to SwiftProtocolLaws; (3) TestLifter gains a **Slicing phase** that isolates the property from test boilerplate and a **Mock-based generator synthesis** path that learns construction patterns from existing tests; (4) the CLI ships an **Interactive Triage Mode** and a non-fatal **CI Drift Mode**; (5) generator inference explicitly delegates to SwiftProtocolLaws' shared `DerivationStrategist` rather than re-deriving in parallel. The full delta is in Appendix A.

-----

## 1. Overview

SwiftProtocolLaws addresses the lowest-hanging fruit in automated property testing: if a type declares a protocol, verify that the implementation satisfies the protocol's semantic laws. That project is intentionally scoped to the *explicit* — conformances the developer has already declared.

SwiftInfer addresses what comes next: the *implicit*. Properties that are meaningful and testable, but are not encoded in any protocol declaration. They live in the structure of function signatures, in the relationships between functions, in the algebraic shape of operations, and in the patterns visible in existing unit tests.

This document proposes **SwiftInfer**, a Swift package delivering three contributions:

- **Contribution 1 — TemplateEngine**: A library of named property templates matched against function signatures via SwiftSyntax + light type-flow analysis, emitting candidate property tests for human review. Includes algebraic-structure detectors (semigroup, monoid, group, semilattice, ring) that drive both test generation *and* protocol-conformance refactoring suggestions.
- **Contribution 2 — TestLifter**: A tool that analyzes existing XCTest and Swift Testing unit test suites, slices each test body into "setup" and "property" regions, and suggests generalized property tests derived from the property region — including generator candidates inferred from how values were constructed in the test.
- **Contribution 3 — RefactorBridge**: When TemplateEngine accumulates enough algebraic evidence on a type (e.g., binary op + identity + associativity), SwiftInfer suggests the corresponding standard-library or kit-supported protocol conformance so the property can be verified by SwiftProtocolLaws on every CI run, not just under SwiftInfer's discovery pass.

All three contributions produce *suggestions for human review*, not silently executed tests. The developer is always in the loop.

-----

## 2. Problem Statement

### 2.1 Properties Beyond Protocols

Protocol law testing covers a well-defined and bounded space. But most of the interesting correctness properties of a codebase are not expressible as protocol laws as written. Consider:

```swift
func normalize(_ input: String) -> String
func compress(_ data: Data) -> Data
func decompress(_ data: Data) -> Data
func applyDiscount(_ price: Decimal, _ rate: Decimal) -> Decimal
func merge(_ a: Config, _ b: Config) -> Config
```

None of these functions declare any protocol that implies testable properties. Yet:

- `normalize` is likely **idempotent**: `normalize(normalize(x)) == normalize(x)`
- `compress`/`decompress` form a **round-trip** pair: `decompress(compress(x)) == x`
- `applyDiscount` likely preserves **monotonicity**: if `a < b` then `applyDiscount(a, r) <= applyDiscount(b, r)`
- `merge`, paired with a `Config.empty` constant, is very likely a **monoid**: associative, commutative, with identity

These properties are discoverable from *structure* — function names, type signatures, the existence of identity-shaped constants, usage in `reduce`/`fold` — without requiring the developer to have written any tests at all.

### 2.2 Algebraic Structures Are Latent in Most Codebases

A key insight v0.2 elevates: algebraic structures (semigroups, monoids, groups, semilattices, rings) are not exotic — they're the backbone of common Swift code patterns:

- **Reducers and state machines** → semigroup operation under event application
- **Undo/redo systems** → group with identity, inverse, associative composition
- **Configuration merging / feature-flag resolution** → join-semilattice (associative, commutative, idempotent)
- **Numeric pipelines (graphics, audio, finance)** → ring under `+` and `*`
- **Compiler / SwiftSyntax / lint passes** → semigroup under composition
- **Concurrency primitives (task merging, cancellation)** → semigroup or monoid
- **String/Array/Log/Dictionary accumulators** → monoid with `empty` identity

When SwiftInfer detects these patterns, it should generate the corresponding properties **and** point the developer at the standard-library or kit-supported protocol they could conform to so SwiftProtocolLaws verifies the laws on every run thereafter. That bridge — discovery now, enforcement forever — is RefactorBridge.

### 2.3 The Unit Test as an Underused Signal

Most Swift codebases with meaningful test coverage have unit tests that implicitly encode structural knowledge. A test like:

```swift
func testRoundTrip() {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    encoder.dateEncodingStrategy = .iso8601
    let original = MyData(value: 42, name: "alpha")
    let encoded = try encoder.encode(original)
    let decoded = try JSONDecoder().decode(MyData.self, from: encoded)
    XCTAssertEqual(original, decoded)
}
```

encodes the round-trip property for one specific input, surrounded by encoder configuration that is *not* part of the property itself. The general property — `decode(encode(x)) == x` for all `x` of a suitably configured `MyData` — is right there, but extracting it requires *slicing* the test into the encoder/decoder construction (setup) and the assertion chain (property). v0.1 assumed clean two-step transforms; v0.2's TestLifter does this slicing explicitly.

### 2.4 The Gap SwiftInfer Fills

SwiftProtocolLaws handles: *"you declared a protocol, does your implementation honor its laws?"*

SwiftInfer handles: *"given what your code looks like and what your tests say, what properties are you implicitly claiming, and is there a protocol you should be conforming to so SwiftProtocolLaws can keep verifying them?"*

Together they cover the automated end of the property inference spectrum, from explicit protocol contracts down through structural and algebraic inference to test-guided generalization, with a feedback path back into protocol conformance.

-----

## 3. Goals and Non-Goals

### Goals

- Identify candidate properties from function signatures and types without requiring developer annotation
- Surface round-trip pairs, idempotence candidates, and **algebraic structures** (semigroup / monoid / group / semilattice / ring) through structural analysis
- Suggest protocol conformances that would let SwiftProtocolLaws verify discovered algebraic laws on every CI run (RefactorBridge)
- Analyze existing unit test suites and suggest lifted property tests, slicing test bodies into setup/property regions
- Infer generator candidates from how values were constructed in existing tests (Mock-based synthesis), delegating to SwiftProtocolLaws' `DerivationStrategist` for shared logic
- Produce human-reviewable output with weighted-score provenance, counter-signals, and clear evidence trails
- Operate as a CLI discovery tool with an interactive triage mode, and as a non-fatal CI drift checker
- Integrate with SwiftProtocolLaws' `PropertyBackend` abstraction for test execution

### Non-Goals

- Automatically executing inferred properties without human review
- Replacing unit tests or SwiftProtocolLaws protocol law checks
- Full runtime invariant inference (Daikon-style instrumentation)
- Stateful / model-based test generation (separate project scope)
- Correctness guarantees on inferred properties — all output is probabilistic suggestion
- Persistent semantic indexing across runs (v0.2 deliberately defers ChatGPT critique's "Contribution 3 — Semantic Index" — see Open Questions)
- IDE plugins (Xcode quick-fix integration is desirable but out of scope for v1)

-----

## 4. Confidence Model — Weighted Scoring Engine

v0.1 used three discrete tiers (`Strong / Likely / Possible`). v0.2 keeps the tier *labels* as user-facing buckets but computes them from a **weighted score** built from independent signals. This makes the model tunable without rewriting tiers and forces every suggestion to carry an auditable evidence trail.

### 4.1 Signals

A suggestion's score is the sum of contributing signals (positive and negative). Signals are independent — a suggestion can earn confidence from naming alone, from types alone, or from any combination.

| Signal | Weight | Description |
|---|---|---|
| **Exact name match** | +40 | Function pair matches a curated inverse list (`encode`/`decode`, `serialize`/`deserialize`, `compress`/`decompress`, `encrypt`/`decrypt`, `push`/`pop`, `insert`/`remove`, `open`/`close`, `marshal`/`unmarshal`, `pack`/`unpack`, `lock`/`unlock`). |
| **Type-symmetry signature** | +30 | `T → U` paired with `U → T` in the same scope (type, file, or module). For unary templates, `T → T` for idempotence; `(T, T) → T` for binary-op templates. |
| **Algebraic-structure cluster** | +25 per element | Type exposes a binary op `(T, T) → T` *and* an identity-shaped constant (`.empty`, `.zero`, `.identity`, `.none`, `init()` returning a "neutral" value). Each additional element (associativity confirmed by signature; inverse function present; idempotence detected) adds +25. |
| **Reduce/fold usage** | +20 | The type is used in `.reduce(identity, op)` or a manual `for`/accumulator builder pattern at least once in the analyzed corpus — a strong signal it is *already* being treated as a monoid. |
| **`@Discoverable(group:)` annotation** | +35 | Two functions share an explicit `@Discoverable(group:)` from SwiftProtocolLaws — already promoted to HIGH in `ProtoLawMacro`'s M5 advisory (PRD §5.5) and re-used here. |
| **Test-body pattern** | +50 | TestLifter detects the same structural pattern in 3+ distinct test methods. Configurable; default is 2. |
| **Cross-validation** | +20 | TemplateEngine (signature) and TestLifter (test) independently arrive at the same template for the same function. Capped at +20 — agreement on structure ≠ agreement on semantics, so this is meaningful but not overwhelming. |
| **Sampling pass under derived generator** | +10 | A trial run of 25 samples passes using a `DerivationStrategist`-supplied generator. Deliberately small contribution: see §4.3. |
| **Side-effect penalty** | -20 | Function is `mutating`, returns `Void`, has `inout` params, or calls APIs marked unsafe/IO-bound. Algebraic templates assume pure functions. |
| **Generator-quality penalty** | -15 | Best generator available is `.todo` or weakly-typed (e.g., uniform `Int` for an explicitly bounded domain). Logs "passes sampling under weak generator" as a known caveat. |
| **Counter-signal: asymmetric assertion** | -25 | TestLifter found an explicitly asymmetric assertion (`f(a, b) != f(b, a)` for a candidate commutative op) in any test. Veto-class evidence. |
| **Counter-signal: early return / partial function** | -15 | Function body has guard / early-return paths suggesting partiality, contradicting `T → T` totality assumptions. |
| **Counter-signal: uses non-Equatable output** | -∞ | The output type is not `Equatable` — the property is structurally untestable. Suggestion is suppressed entirely, not just downscored. |

### 4.2 Tier Mapping

The score buckets into the user-facing tier:

| Score | Tier | Default visibility |
|---|---|---|
| ≥ 75 | `✓ Strong` | shown |
| 40–74 | `~ Likely` | shown |
| 20–39 | `? Possible` | hidden by default; surfaced with `--include-possible` |
| < 20 | suppressed | never shown |

The thresholds are tunable. Real-world calibration against open-source corpora (per §10) is what sets them; treat the numbers above as v0.2 starting points, not load-bearing constants.

### 4.3 Generator Awareness

A weakness of v0.1 (and a Gemini critique point shared by ChatGPT): "passes 25 samples" is a thin signal when the generator is weak. v0.2 makes generator quality first-class. Every suggestion's evidence record includes:

- `generatorSource`: `.derived(.caseIterable | .rawRepresentable | .memberwise | .codableRoundTrip)` | `.registered` | `.todo` | `.inferredFromTests`
- `generatorConfidence`: `.high` (CaseIterable/RawRepresentable enums, all-stdlib-raw memberwise structs), `.medium` (Codable round-trip; mock-inferred from 3+ tests), `.low` (Codable round-trip with no observed instances; mock-inferred from 1 test)
- `samplingResult`: `.passed(trials: N)` | `.failed(seed: S, counterexample: C)` | `.notRun`

This information surfaces in the suggestion output verbatim. A "Strong" suggestion that passed sampling under a `.low` generator is rendered with an explicit caveat ("⚠ sampling evidence is weak — no `Gen<Foo>` registered or derivable"), so the developer can choose whether to act before strengthening the generator.

### 4.4 Counter-Signals Are Veto-Capable

v0.1 only accumulated supporting evidence. v0.2 explicitly tracks disconfirming evidence (the negative-weight rows above). This prevents overconfidence from shallow naming matches: a `merge` function that passes the type-signature test but has an `XCTAssertNotEqual(merge(a, b), merge(b, a))` test in the suite is *not* commutative and SwiftInfer should not suggest it is.

The `non-Equatable output` signal is special-cased to `-∞` because the property is structurally untestable — no amount of other evidence can rescue it. The same applies to round-trip without `Equatable` on `T`.

-----

## 5. Contribution 1: TemplateEngine

### 5.1 Description

TemplateEngine is a SwiftSyntax-based static analysis pipeline that scans Swift source files, matches function signatures and naming patterns against a registry of named property templates, accumulates signals per the §4 scoring engine, and emits candidate property test stubs (and, for algebraic clusters, RefactorBridge suggestions per §6).

v0.1's "templates are patterns over signatures" framing is preserved. v0.2 extends two dimensions:

1. **Algebraic-structure templates** — semigroup, monoid, group, semilattice, ring — that compose individual property templates into higher-order structural claims.
2. **Light type-flow analysis** — per the Gemini critique, the engine looks at *how* a function is used, not just what it looks like, to supplement naming heuristics.

### 5.2 Property Template Registry

Each entry defines:

- A named algebraic property shape
- The type-signature pattern it requires
- The naming heuristics that contribute to the score
- The usage patterns that contribute to the score (type-flow)
- The property test body to emit
- Counter-signals that veto or downscore the suggestion
- Interaction warnings with other templates

#### Round-Trip

**Pattern:** Two functions `f: T → U` and `g: U → T` in the same module or type.

**Scoring contributors:** type symmetry (+30), exact name match (+40 if curated pair), `@Discoverable(group:)` (+35).

**Counter-signals:** non-Equatable `T` (suppress), `g` throws and `f` does not (downscore — recoverability asymmetric).

**Emitted property:**

```swift
// SwiftInfer template: round-trip
// Score: 95 (Strong)
// Evidence:
//   • encode(_:) -> Data, decode(_:) -> MyType — MyType.swift:14, 22
//   • Curated inverse name pair: encode/decode (+40)
//   • Type-symmetry: T → Data ↔ Data → T (+30)
//   • Sampling: 25/25 passed under derived generator (+10)
//     generator: .derived(.memberwise), confidence: .high
@Test func roundTripEncoding() async throws {
    try await propertyCheck(input: Gen.derived(MyType.self)) { value in
        #expect(try decode(encode(value)) == value)
    }
}
```

#### Idempotence

**Pattern:** A function `f: T → T`.

**Scoring contributors:** `T → T` signature (+30), name in idempotence-suggestive set (+40 — `normalize`, `canonicalize`, `trim`, `flatten`, `sort`, `deduplicate`, `sanitize`, `format`), use in test as `f(f(x))` pattern (+50 if 3+ tests).

**Counter-signals:** function is `mutating` (-20), result depends on external state (e.g., calls `Date()`, `Random.next()`) — detected syntactically as an immediate disqualifier.

#### Commutativity

**Pattern:** A function `f: (T, T) → T`.

**Scoring contributors:** `(T, T) → T` signature (+30), name in commutative-suggestive set (`merge`, `combine`, `union`, `intersect`, `add`, `plus`) (+40).

**Counter-signals:** name in *non*-commutative-suggestive set (`subtract`, `divide`, `prepend`, `concat` for ordered output) (-30); explicit `XCTAssertNotEqual` asymmetry test in suite (-25).

#### Associativity

**Pattern:** Same as commutativity — `f: (T, T) → T`.

**Scoring contributors:** same as commutativity for naming; additionally, observed use in `.reduce(...)` (+20) is a strong associativity signal — if the codebase already reduces over the operation, associativity is assumed in practice.

#### Monotonicity

**Pattern:** A function `f: T → U` where both `T` and `U` are `Comparable`.

**Scoring contributors:** Comparable-on-both-sides signature (+30), name in monotonicity-suggestive set (`scale`, `apply`, `transform`, `weight`, `discount`) (+40).

**Caveat surfaced in output:** direction (increasing vs. decreasing) cannot be inferred — the emitted stub asserts `<=` and includes a comment instructing the developer to flip if needed.

#### Identity Element

**Pattern:** A binary operation `f: (T, T) → T` plus a static identity-shaped value (`zero`, `empty`, `identity`, `none`, `default`, or `init()` documented as neutral).

**This template is the bridge to monoid detection (§5.4).**

#### Invariant Preservation

**Pattern:** A mutating or transforming function where a measurable property (count, isEmpty, a computable predicate) should hold before and after by a known arithmetic relationship.

**Scoring contributors:** observed `let before = x.count; ... XCTAssertEqual(x.count, before + N)` in a test (+50 from test-body pattern signal).

**Confidence:** Low to Medium by default — the relationship between op and invariant is heuristic.

#### Inverse Pair (NEW in v0.2)

**Pattern:** Two functions `f: T → T` and `g: T → T` such that `g(f(x)) == x` (left inverse) or `f(g(x)) == x` (right inverse), discovered by name (`apply`/`undo`, `do`/`revert`, `redo`/`undo`).

**Used by:** the group detector (§5.4).

### 5.3 Type-Flow Analysis (NEW in v0.2)

Per the Gemini critique, naming heuristics are fragile — legacy codebases and non-English naming weaken the signal. v0.2's TemplateEngine supplements naming with light type-flow analysis over the SwiftSyntax-derived call graph:

- **Composition detection.** `f(f(x))` invocations anywhere in the corpus (production *or* test) supply +20 to the idempotence score for `f`.
- **Inverse-by-usage detection.** `g(f(x))` followed by an assertion `== x` supplies the round-trip score directly, even without curated naming.
- **Reducer/builder usage.** `for x in xs { acc = op(acc, x) }` or `.reduce(seed, op)` invocations supply +20 to associativity for `op`.
- **Accumulator-with-empty-seed.** `.reduce(.empty, op)` where `.empty` is a static on the same type supplies +20 to the identity-element score, because the codebase is already treating `.empty` as the monoidal identity.

Type-flow analysis is intentionally light. It is *not* a full call-graph or alias analysis — it's syntactic pattern matching over the call graph at the SwiftSyntax level, scoped to the analyzed target. This keeps it tractable and predictable.

### 5.4 Algebraic-Structure Composition (NEW in v0.2)

When multiple per-template signals concentrate on the same type, TemplateEngine emits a **structural claim** beyond the individual properties. These claims drive RefactorBridge (§6).

| Detected combination | Implies | RefactorBridge target |
|---|---|---|
| binary op `(T, T) → T` + associativity | **Semigroup** | (no stdlib protocol — claim only) |
| Semigroup + identity element | **Monoid** | suggest `AdditiveArithmetic` if `+`/`zero`-shaped, otherwise informational |
| Monoid + inverse function | **Group** | (no stdlib protocol — claim only) |
| Monoid + commutativity + idempotence | **Bounded join-semilattice** | suggest `SetAlgebra` if applicable |
| Two monoids on same type, distributive | **Ring** | suggest `Numeric` (with caveats — see below) |
| `T → T` + `T → T` inverse + identity | **Group acting on T** | (no stdlib protocol — informational) |

Each composed claim emits a single bundled set of property tests covering all the laws of the structure (e.g., a Monoid suggestion emits associativity + identity-left + identity-right as three `#expect`s in one `propertyCheck`). This is more useful than three separate suggestions the developer has to mentally assemble.

**Why `Numeric` carries caveats.** SwiftProtocolLaws v1.4 added laws for `AdditiveArithmetic`, `Numeric`, `SignedNumeric` — but these are *exact-equality* laws that hold for integer-like types and not for IEEE-754 floats. RefactorBridge must surface this when suggesting `Numeric` conformance: "this looks like a ring; if your type is integer-like, conform to `Numeric` and let SwiftProtocolLaws verify the algebraic chain. If it's float-like (lossy multiplication, rounding), the same laws will report spurious violations and you should conform to `FloatingPoint` and gate NaN-domain laws via `LawCheckOptions.allowNaN` instead." The kit already enforces this at the macro side; SwiftInfer's suggestion text mirrors that guidance so the user doesn't get pushed into a known footgun.

### 5.5 Cross-Function Pairing Strategy

Naive cross-function pairing is O(n²). TemplateEngine avoids this through tiered filtering, unchanged from v0.1:

1. **Type filter (primary):** Only pair `f: T → U` with `g: U → T`. Applied first, eliminates most candidates.
2. **Naming filter (secondary):** Score pairs by curated inverse name patterns.
3. **Scope filter (tertiary):** Prefer pairs within the same type or file before considering module-wide pairs.
4. **`@Discoverable(group:)` (optional):** Already shipped in `ProtoLawMacro` v1.x. Re-used here verbatim — same annotation, same semantics, same +35 weight.

In practice, a module of 50 functions typically produces fewer than 10 candidate pairs after type filtering.

### 5.6 Contradiction Detection

When multiple templates fire on the same function, TemplateEngine checks for logical contradictions before emitting:

| Combination | Implication | Action |
|---|---|---|
| Idempotent + Involutive | `f` must be identity | ⚠ warn; emit only the strongest single suggestion |
| Commutative + non-Equatable output | Commutativity is untestable | suppress (counter-signal `-∞`) |
| Round-trip without Equatable on T | Round-trip is untestable | suppress |
| Strong commutativity + asymmetric test in suite | Tests contradict the inferred property | suppress (counter-signal -25 plus warning) |
| Monoid claim + observed non-pure side effect on op | Algebraic claim violates purity assumption | downscore monoid claim by 20; keep individual templates if they still clear thresholds |

### 5.7 Annotation API

Developers can guide TemplateEngine with lightweight annotations rather than waiting for automatic discovery. v0.2 reuses the existing `@Discoverable(group:)` from `ProtoLawMacro` rather than introducing a parallel API:

```swift
@CheckProperty(.idempotent)
func normalize(_ input: String) -> String { ... }

@CheckProperty(.roundTrip, pairedWith: "decode")
func encode(_ value: MyType) -> Data { ... }

// Already shipped in ProtoLawMacro M5; SwiftInfer reuses verbatim.
@Discoverable(group: "serialization")
func decode(_ data: Data) -> MyType { ... }
```

`@CheckProperty` triggers immediate stub generation for that function (only annotation introduced by SwiftInfer). `@Discoverable` continues to mean what it does in `ProtoLawMacro`: cross-function pairing within a named group, promoted to high score by the +35 signal.

### 5.8 Milestones

| Milestone | Deliverable |
|---|---|
| M1 | Round-trip and idempotence templates, SwiftSyntax pipeline, weighted scoring engine, CLI discovery tool with text output |
| M2 | Commutativity, associativity, identity-element templates; type-flow analysis (composition + reducer/builder usage) |
| M3 | Algebraic-structure composition (semigroup, monoid); contradiction detection table |
| M4 | Group, semilattice, ring composition; RefactorBridge wiring (Contribution 3) |
| M5 | Monotonicity and invariant-preservation templates; counter-signal accumulation |
| M6 | `@CheckProperty` annotation; full `@Discoverable(group:)` reuse from ProtoLawMacro |
| M7 | Interactive Triage Mode (§8) and CI Drift Mode (§9) |

-----

## 6. Contribution 3: RefactorBridge

### 6.1 Why a Third Contribution

v0.1 framed SwiftInfer as a property-test suggester. The Gemini critique correctly observed this leaves leverage on the table: when TemplateEngine accumulates strong evidence for a monoid (binary op + identity + associativity), the most valuable output is *not* a one-shot property test — it's a suggestion to **conform to a protocol that SwiftProtocolLaws can then verify forever**.

This closes the loop:

- SwiftInfer discovers latent algebraic structure
- The user adds a protocol conformance (`AdditiveArithmetic`, `SetAlgebra`, etc.)
- SwiftProtocolLaws' discovery plugin detects the new conformance and emits the corresponding `checkXxxProtocolLaws(...)` test on the next regeneration
- The property is now part of the standing test suite, not a one-off SwiftInfer artifact

This is what RefactorBridge implements.

### 6.2 RefactorBridge Output Shape

RefactorBridge is *not* a separate analysis pass — it's an output mode of TemplateEngine. Whenever an algebraic-structure composition (§5.4) reaches Strong tier, the suggestion is rendered with two parallel options:

```text
─── SwiftInfer Suggestion ──────────────────────────────────────────
File:        Config.swift
Type:        Config
Score:       110 (Strong)
Structure:   Monoid

Evidence:
  • merge(_:_:) -> Config    [signature (T,T)→T] (+30)
  • Config.empty: Config     [identity-shaped static] (+25)
  • merge present in 3 .reduce(.empty, merge) call sites (+25 + 20)
  • 0 counter-signals

Option A — One-off property test (faster):
  Generate Tests/Generated/ConfigMonoidProperties.swift with three
  property checks: associativity, left-identity, right-identity.

Option B — Refactor to AdditiveArithmetic (recommended):
  Add `extension Config: AdditiveArithmetic { ... }` (stub provided).
  SwiftProtocolLaws will then emit
  `checkAdditiveArithmeticProtocolLaws(Config.self)` on the next
  `swift package protolawcheck discover` run, which verifies these
  laws plus the wider AdditiveArithmetic chain on every CI run.

  ⚠ AdditiveArithmetic exact-equality laws assume integer-like
  semantics. If Config.merge is lossy (e.g., float averaging),
  prefer Option A.

Choose [A/B/skip]:
─────────────────────────────────────────────────────────────────────
```

The choice is logged to a per-project `.swiftinfer/decisions.json` file (see §7.5 Persistence), so reruns don't re-prompt.

### 6.3 What RefactorBridge Will Not Do

- **It will not modify source code.** Even when "Refactor to AdditiveArithmetic" is chosen, RefactorBridge only writes the conformance to a *staged* `.swift` file under `Tests/Generated/SwiftInferRefactors/` and asks the developer to inspect/move it. No automatic edits to existing files.
- **It will not propose a conformance the type structurally cannot satisfy.** Memberwise inspection rules out classes, types missing required members, or types whose stored properties don't themselves conform to the required protocol.
- **It will not propose conformances outside SwiftProtocolLaws' coverage scope.** The bridge can only suggest protocols whose laws SwiftProtocolLaws actually verifies; everything else is informational ("this looks like a Group, but no stdlib protocol corresponds; consider a custom protocol if your codebase needs it").

-----

## 7. Contribution 2: TestLifter

### 7.1 Description

TestLifter analyzes existing XCTest and Swift Testing test suites, **slices each test method into setup and property regions**, identifies structural patterns in the property region, and suggests generalized property tests. v0.2's slicing phase is the major change from v0.1, which assumed already-clean test bodies.

### 7.2 The Slicing Phase (NEW in v0.2)

Real-world tests are messy. A `testRoundTrip` may include five lines of `JSONEncoder` configuration before the actual round-trip assertion. v0.1's pattern matchers required clean two-step transforms; v0.2 introduces a slicing pass that runs before any pattern matching.

**Slicing rules (in priority order):**

1. **Anchor on the assertion.** Locate the terminal `XCTAssertEqual` / `#expect` / `XCTAssert*` call. This is the property's claim.
2. **Backward-slice from the assertion's arguments.** Walk SSA-style up the test body, collecting only the statements that contribute to the assertion's argument values.
3. **Classify the remaining statements as setup.** Encoder configuration, mock instantiation, fixture loading — none of which are part of the property.
4. **Identify the *parameterized* values.** Within the slice, literals (`MyData(value: 42)`) and variables initialized to literals are the candidate inputs the property generalizes over. Configuration constants (`.iso8601`, `.prettyPrinted`) are *not* parameterized — they're part of the property's fixed setup, lifted alongside the assertion into the generated stub.

**Worked example:**

```swift
// Original test
func testRoundTrip() throws {
    let encoder = JSONEncoder()              // setup (carried into stub)
    encoder.outputFormatting = .prettyPrinted // setup (carried into stub)
    encoder.dateEncodingStrategy = .iso8601  // setup (carried into stub)
    let original = MyData(value: 42, name: "alpha") // parameterized (becomes Gen)
    let encoded = try encoder.encode(original)      // property body
    let decoded = try JSONDecoder().decode(MyData.self, from: encoded) // property body
    XCTAssertEqual(original, decoded)               // property assertion
}
```

```swift
// LIFTED by SwiftInfer
// LIFTED from: testRoundTrip() (MyDataTests.swift:14)
// Pattern: round-trip
// Score: 100 (Strong)
// Slicing: 3 setup statements carried; 1 input parameterized
// Generator: inferred from test construction — see Mock-based synthesis below

@Test func roundTripProperty() async throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    await propertyCheck(input: Gen.todo(MyData.self) /* see synthesis suggestion below */) { value in
        let encoded = try encoder.encode(value)
        let decoded = try decoder.decode(MyData.self, from: encoded)
        #expect(decoded == value)
    }
}

// SUGGESTED Gen<MyData> — based on 7 test sites constructing MyData(value:name:):
//   static var arbitrary: Gen<MyData> {
//       Gen.zip(Gen.int, Gen.string).map(MyData.init(value:name:))
//   }
// Apply this generator? [y/n/edit]
```

### 7.3 Pattern Recognition (post-slicing)

Pattern recognition runs against the *property region* of each sliced test, not the raw body. The patterns themselves are essentially as in v0.1, but they now match against cleaner inputs:

- **Assert-after-Transform** → round-trip
- **Assert-after-Double-Apply** → idempotence
- **Assert-Symmetry** → commutativity
- **Assert-Ordering-Preserved** → monotonicity
- **Assert-Count-Change** → invariant preservation
- **Assert-Reduce-Equivalence (NEW)** → associativity, when the test asserts `xs.reduce(seed, op) == xs.reversed().reduce(seed, op)` or similar reordering equalities

### 7.4 Generator Inference (Expanded — Mock-Based Synthesis)

v0.1 had a fixed table of generator strategies. v0.2 expands this with the Gemini critique's "mock-based generation": **learn the generator from how the type is constructed in tests**.

| Condition | Strategy | Confidence |
|---|---|---|
| Type conforms to `CaseIterable` | `Gen.allCases` | high |
| Type conforms to `RawRepresentable` with stdlib raw | `Gen<RawValue>.derived().compactMap(Type.init(rawValue:))` | high |
| Type has visible memberwise init with all-stdlib-raw parameters | Compose primitive generators (delegated to SwiftProtocolLaws' `DerivationStrategist`) | high |
| Type appears in 3+ tests constructed via the same initializer (NEW) | Synthesize `Gen.zip(...)` over the observed argument types and `.map` through that initializer | medium |
| Type appears in 1–2 tests with the same construction | Same synthesis, marked low confidence; surface caveat | low |
| `Codable` and observed only as decoded test fixture | `Gen.derived` via JSON round-trip | medium |
| SwiftProtocolLaws generator already registered for this type | Reuse it | high |
| None of the above | Emit `.todo` stub | n/a |

**Why "delegated to `DerivationStrategist`"**: SwiftProtocolLaws' `ProtoLawMacro` already implements the memberwise-Arbitrary derivation (Strategy 3 — `zip(...).map { Type(prop: $0.N, ...) }` lifted through the synthesized memberwise initializer, arity 1–10, falling through to `.todo` for non-raw members / class kinds / arity > 10). v0.2 explicitly extracts that logic into a shared `DerivationStrategist` actor that both `ProtoLawMacro` and SwiftInfer call. Re-implementing it in parallel would guarantee divergence; sharing it keeps the macro and SwiftInfer in lock-step. This is a small SwiftProtocolLaws change (refactor `DerivationStrategist` from internal to public) but enables a much cleaner SwiftInfer.

### 7.5 Persistence and Suggestion Identity

v0.1 said "developers can suppress lifting via `// swiftinfer: skip`" but didn't specify how decisions persist across runs. v0.2 borrows the deterministic-output + suppression-marker pattern from SwiftProtocolLaws' discovery plugin:

- Every suggestion has a **stable hash** computed from `(template ID, function signature canonical form, AST shape of property region)`. The hash is *not* line-number-sensitive — moving a function up or down a file does not invalidate prior decisions. Renaming the function or changing its signature does invalidate, by design.
- The CLI writes accept/reject/skip decisions to `.swiftinfer/decisions.json`, keyed by hash.
- `// swiftinfer: skip [hash]` markers in source are honored and survive regeneration.
- A per-decision `recorded` timestamp lets a future `--show-stale` flag surface decisions older than N days for re-review, but decisions never auto-expire — staleness is informational, never destructive.

### 7.6 Relationship to Existing Unit Tests

TestLifter does not modify or replace existing unit tests. The relationship is unchanged from v0.1:

- **Unit tests** remain as regression anchors for specific known cases
- **Lifted properties** generalize those cases across the input space
- When a lifted property finds a new counterexample, it becomes a new unit test (regression oracle)

### 7.7 Confidence and Noise

Test-guided inference is inherently lower confidence than structural inference, because unit tests may encode accidental structure — patterns that happen to appear in the test values chosen, but don't represent real invariants.

TestLifter mitigates this through:

- **Minimum test-pattern count:** A pattern must appear in at least 2 distinct test methods before a suggestion is emitted (configurable, default 2).
- **Counter-signal scanning:** TestLifter explicitly looks for asymmetric assertions (`XCTAssertNotEqual` patterns that contradict a candidate property) across the *whole* test target, not just the candidate test. Finding one is a hard veto.
- **Human review gate:** All output is clearly marked as suggested, never auto-committed.
- **Persistent suppression:** The `// swiftinfer: skip` marker (with optional hash) survives regeneration, per §7.5.

### 7.8 Milestones

| Milestone | Deliverable |
|---|---|
| M1 | SwiftSyntax test body parser, slicing phase, assert-after-transform detection, round-trip suggestion |
| M2 | Double-apply (idempotence) and symmetry (commutativity) detection |
| M3 | Generator inference: stdlib derivation strategies + `.todo` stub pattern; consume shared `DerivationStrategist` from SwiftProtocolLaws |
| M4 | Mock-based generator synthesis from observed test construction |
| M5 | Ordering, count-change, reduce-equivalence pattern detection |
| M6 | Suggestion-identity hashing, decisions.json persistence, `// swiftinfer: skip` honoring |
| M7 | Counter-signal scanning across test target |
| M8 | Counterexample-to-unit-test conversion tooling |

-----

## 8. Interactive Triage Mode (NEW in v0.2)

The default CLI output remains a static text dump, suitable for batch use and CI piping. v0.2 adds an opt-in `--interactive` flag that walks suggestions one at a time:

```text
$ swift-infer discover --target MyApp --interactive

Found 14 Strong, 6 Likely suggestions across MyApp.

[1/14 Strong] Config.swift:31 — Monoid pattern (score 110)
  → merge(_:_:) is associative + Config.empty is identity
  Options:
    [A] Generate property tests only
    [B] Generate AdditiveArithmetic conformance + property tests
    [s] Skip (record decision)
    [n] Note as wrong (record decision + suppress for 30 days)
    [?] Show full evidence
  Choose: B

  ✓ Wrote Tests/Generated/SwiftInferRefactors/Config+AdditiveArithmetic.swift
  ✓ Recorded decision in .swiftinfer/decisions.json

  Detected: Gen<Config> not registered. Synthesize from observed
  test construction (Config(name:priority:) seen in 4 tests)?
  Choose: y

  ✓ Wrote Tests/Generated/SwiftInferGenerators/Config+Arbitrary.swift

[2/14 Strong] StringUtils.swift:8 — Idempotence (score 90)
  ...
```

This is the Gemini critique's "Triage Mode" verbatim. The non-interactive mode prints the same content as a flat report; interactive mode just paces it.

-----

## 9. CI Drift Mode (NEW in v0.2)

A non-fatal CI integration mode for catching property-coverage regression as a codebase grows.

```yaml
# .github/workflows/ci.yml
- name: SwiftInfer drift check
  run: swift-infer drift --baseline .swiftinfer/baseline.json
```

`drift` mode:

1. Re-runs discovery with the same scoring config.
2. Compares the current set of Strong-tier suggestions against the baseline.
3. **Emits a warning (not a failure)** for each new Strong-tier suggestion that lacks an accept/reject decision in `.swiftinfer/decisions.json` after the baseline date.
4. Outputs a GitHub Actions annotation per warning, surfaced in the PR review UI.

The Gemini critique's framing applies: "If a developer adds `decompressV2` matching a known template but doesn't add a corresponding property test, CI emits a warning." This prevents property coverage from silently diluting as the codebase grows, without blocking merges.

The baseline is updated by running `swift-infer drift --update-baseline` locally and committing the resulting `.swiftinfer/baseline.json`.

-----

## 10. Architecture Overview

```
┌────────────────────────────────────────────────────────────────┐
│                          SwiftInfer                            │
│                                                                │
│  ┌─────────────────┐     ┌─────────────────────┐              │
│  │  TemplateEngine │     │     TestLifter      │              │
│  │                 │     │                     │              │
│  │ SwiftSyntax     │     │ SwiftSyntax         │              │
│  │ signature scan  │     │ test parser         │              │
│  │ + type-flow     │     │ + slicing phase     │              │
│  │                 │     │                     │              │
│  │ Template        │     │ Pattern registry    │              │
│  │ registry        │     │ (post-slice)        │              │
│  │                 │     │                     │              │
│  │ Algebraic       │     │ Mock-based          │              │
│  │ composition     │     │ generator synthesis │              │
│  └────────┬────────┘     └──────────┬──────────┘              │
│           │                         │                          │
│           ▼                         ▼                          │
│  ┌─────────────────────────────────────────────┐              │
│  │           Weighted Scoring Engine           │              │
│  │  signals + counter-signals → tier mapping   │              │
│  └─────────────────┬───────────────────────────┘              │
│                    │                                           │
│         ┌──────────┴──────────┐                               │
│         ▼                     ▼                               │
│  ┌──────────────┐    ┌───────────────────┐                   │
│  │  Property    │    │   RefactorBridge  │                   │
│  │  Test Stubs  │    │ (algebraic claims │                   │
│  │              │    │  → conformance    │                   │
│  │              │    │  suggestions)     │                   │
│  └──────┬───────┘    └─────────┬─────────┘                   │
│         │                      │                              │
│         └──────────┬───────────┘                              │
│                    ▼                                           │
│         ┌─────────────────────┐                               │
│         │  CLI / Triage / CI  │                               │
│         │ (.swiftinfer/       │                               │
│         │  decisions.json)    │                               │
│         └──────────┬──────────┘                               │
└────────────────────┼──────────────────────────────────────────┘
                     │
       ┌─────────────┴────────────────┐
       ▼                              ▼
┌──────────────────┐       ┌──────────────────────┐
│ SwiftProtocolLaws│       │ SwiftProtocolLaws    │
│ PropertyBackend  │       │ ProtoLawMacro +      │
│ (test execution) │       │ Discovery plugin     │
│                  │       │ (re-emits law tests  │
│                  │       │  on next regen if    │
│                  │       │  conformance accepted)│
└──────────────────┘       └──────────────────────┘
                                   │
                                   ▼
                       ┌──────────────────────────┐
                       │ DerivationStrategist     │
                       │ (shared by ProtoLawMacro │
                       │  and TestLifter for      │
                       │  generator derivation)   │
                       └──────────────────────────┘
```

-----

## 11. Relationship to SwiftProtocolLaws

SwiftInfer is downstream of SwiftProtocolLaws but the relationship is now **bidirectional via RefactorBridge**, not strictly one-way:

| Concern | Handled By |
|---|---|
| Protocol semantic law verification | SwiftProtocolLaws (ProtocolLawKit) |
| Protocol conformance detection | SwiftProtocolLaws (ProtoLawMacro discovery plugin) |
| Missing-conformance suggestion (HIGH-confidence syntactic) | SwiftProtocolLaws (ProtoLawMacro M4 advisory) |
| Cross-function round-trip discovery | SwiftProtocolLaws (ProtoLawMacro M5 advisory) — overlaps with SwiftInfer; see below |
| Structural property inference from signatures | SwiftInfer (TemplateEngine) |
| Algebraic-structure detection (semigroup / monoid / etc.) | SwiftInfer (TemplateEngine §5.4) |
| Conformance suggestion derived from algebraic detection | SwiftInfer (RefactorBridge §6) — feeds back into SwiftProtocolLaws |
| Property inference from unit tests | SwiftInfer (TestLifter) |
| Test-body slicing | SwiftInfer (TestLifter §7.2) |
| Memberwise-Arbitrary generator derivation | SwiftProtocolLaws (`DerivationStrategist`) — shared, called by both |
| Test execution backend | SwiftProtocolLaws (`PropertyBackend`) — shared, single backend (`swift-property-based`) |

**On the overlap with ProtoLawMacro M5 advisory.** SwiftProtocolLaws v1.x's advisory layer already does cross-function round-trip discovery via curated naming pairs and `@Discoverable(group:)` groups. SwiftInfer's TemplateEngine round-trip detection is strictly broader (type-symmetry signal, type-flow analysis, test-body cross-validation). The intended split:

- SwiftProtocolLaws stays in its lane: HIGH-confidence syntactic detection, output to stderr only, regeneration-as-diff guarantee preserved.
- SwiftInfer takes the long tail: lower-confidence signals, weighted scoring, test integration, interactive triage.

If the user runs both and they fire on the same pair, that's a +20 cross-validation signal in SwiftInfer's score — a deliberate strengthening, not a duplication.

**Single-backend by design.** SwiftProtocolLaws v1.0 deliberately ships `swift-property-based` as the only `PropertyBackend` implementation (the `SwiftQC` reference in v0.1 is dropped). SwiftInfer follows suit — same single backend, same `PropertyBackend` abstraction. If a future second backend is needed, the abstraction is already there.

-----

## 12. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Template matching produces too many false positives | High | Weighted scoring engine (§4) with counter-signals; default tier shows only Strong + Likely; opt-in for Possible |
| Naming heuristics fail in legacy / non-English codebases | High | Type-flow analysis (§5.3) supplies signal independent of naming; project-specific vocabulary extension is a v1.1 follow-up |
| Lifted unit test patterns don't generalize | Medium | Slicing phase (§7.2) isolates property from boilerplate; minimum-2-test threshold; counter-signal scanning across whole test target |
| Generator inference fails for complex types | Medium | Tiered fallback per §7.4; `.todo` stub forces conscious adoption; mock-based synthesis adds a new path that didn't exist in v0.1 |
| Cross-function pairing is noisy without grouping | Medium | Type filter eliminates most pairs; `@Discoverable(group:)` provides explicit grouping with +35 signal |
| Property contradictions cause user confusion | Low | Contradiction detection table (§5.6); clear warnings in output |
| Developers ignore generated stubs | Medium | Compile-time enforcement via `.todo`; interactive triage mode reduces friction; CI drift mode prevents silent regression |
| Algebraic-structure suggestion pushes user into wrong protocol (e.g., `Numeric` for a float-like type) | Medium | RefactorBridge surfaces explicit caveats (§5.4); both option A and option B presented so the user picks |
| `.swiftinfer/decisions.json` gets stale after refactors | Medium | Stable hashing keyed on AST shape (§7.5) — line moves don't invalidate; signature changes do |
| Suggestion-identity hash collides across functions | Low | Hash includes canonical signature + AST shape + template ID; collision probability negligible at typical project size |

-----

## 13. Success Criteria

### TemplateEngine + RefactorBridge

- Running discovery on a real-world Swift module of 50+ functions produces fewer than 10 Strong-tier suggestions, of which at least 80% are judged useful by a Swift developer unfamiliar with the tool.
- Round-trip, idempotence, and commutativity templates correctly identify known patterns in at least 3 open-source Swift packages used as benchmarks (one of which should be a sufficiently algebraic library — `swift-collections`, `swift-algorithms`, or similar).
- Algebraic-structure composition (§5.4) correctly identifies at least 2 monoid candidates and 1 semilattice candidate in the chosen benchmarks.
- For at least one benchmark, the RefactorBridge suggestion (option B) results in a successful protocol conformance addition that SwiftProtocolLaws then verifies on subsequent runs, end-to-end. This is the loop-closure check.
- Counter-signals correctly veto at least one false-positive that the v0.1 model would have surfaced, in each benchmark.
- Contradiction detection catches idempotent+involutive and at least 2 other contradictory combinations.

### TestLifter

- Running on a test suite of 50+ XCTest methods correctly identifies at least 5 liftable patterns with Strong or Likely score after slicing.
- The slicing phase correctly separates setup from property body in at least 90% of tests with non-trivial setup (≥3 setup statements before the assertion).
- At least 90% of emitted stubs compile after the developer resolves `.todo` generators.
- Mock-based generator synthesis produces a valid `Gen<T>` for at least 50% of the types where ≥3 test sites construct via the same initializer.
- No existing unit test is modified or deleted under any circumstances. (Hard guarantee, not a target.)

### Confidence Model

- Threshold tuning against the benchmark corpora produces tier boundaries within 10 points of the v0.2 starting values (75 / 40 / 20). If real-world calibration pushes them further, that's a finding worth documenting in a future PRD revision.

-----

## 14. Open Questions

1. **Separate package or monorepo?** Should SwiftInfer be a separate package from SwiftProtocolLaws, or a set of additional targets in the same repository? The shared `DerivationStrategist` requirement (§7.4) makes monorepo more attractive than v0.1 framing suggested — there's now a real shared component, not just a shared abstraction.
2. **TemplateEngine as compiler plugin vs. CLI?** The discovery CLI is the right model for whole-module scanning; M7's interactive mode is CLI-only. A compiler-plugin mode for incremental per-file suggestions during development is desirable but unscoped — defer to v1.1.
3. **TestLifter and Swift Testing vs. XCTest?** Swift Testing's `@Test` macro makes test body parsing harder than XCTest's method-based structure but not qualitatively different (the slicing pass is the same). M1 should target both; the SwiftSyntax shape of `@Test func` is well-defined.
4. **Community template contributions:** The template registry is the most valuable long-term artifact. A pluggable third-party registration API is desirable but raises confidence-model integrity concerns (third-party templates could ship aggressive weights). Defer to a v1.1 design with explicit signal-weight bounds and quality-control review.
5. **The Generator Gap and macro-based generators.** The biggest friction point in property testing is writing generators. Even with `.todo` stubs and the new mock-based synthesis, complex generic / nested types will still need hand-written generators. Should SwiftInfer expose a `@GenerateProperties(for: MyType.self)` macro that auto-synthesizes `Gen<T>` for memberwise-eligible types? **v0.2 position:** the synthesis logic already lives in `DerivationStrategist`; exposing it as an explicit macro is cheap and worth doing in M3 — but only as an opt-in annotation (no automatic application), so the developer-in-the-loop guarantee holds. Confirm with the maintainer before M3.
6. **Persistent semantic indexing (ChatGPT critique's "Contribution 3" — deferred).** The case for a persistent, queryable graph of inferred properties across runs is real (API design feedback, refactoring suggestions, doc generation). v0.2 deliberately defers this — RefactorBridge is the highest-value chunk of that vision and is enough to ship in v1. Revisit after benchmark data informs whether the index would be load-bearing for any of those follow-on use cases.
7. **Domain-specific template packs.** Splitting the registry into `numeric`, `serialization`, `collections`, `algebraic` packs and letting the user enable a subset would dramatically improve precision on focused codebases. Defer to v1.1 — needs benchmark data first.

-----

## 15. References

- [_7_SwiftProtocolLaws PRD](_7_SwiftProtocolLaws%20PRD.md) — upstream dependency (v0.3)
- [_4a_ Algebraic Structures](_4a_%20Algebraic%20Structures.md) — algebraic-structure motivation for §5.4
- [_4c_ Monoids and Property Testing](_4c_Monoids%20and%20Property%20Testing.md) — monoid detection rules feeding §5.4
- [Gemini critique](Gemini%20critique.md) — primary input to v0.2
- [swift-property-based](https://github.com/x-sheep/swift-property-based) — single execution backend
- [SwiftSyntax](https://github.com/apple/swift-syntax) — static analysis foundation
- [EvoSuite](https://www.evosuite.org) — Java property inference inspiration
- [Daikon](https://plse.cs.washington.edu/daikon/) — runtime invariant inference reference
- [QuickSpec](https://hackage.haskell.org/package/quickspec) — Haskell equational property discovery
- [Hedgehog state machines](https://hedgehog.qa) — stateful testing reference (out of scope, noted for future)

-----

## Appendix A: Changelog v0.1 → v0.2

| Area | v0.1 | v0.2 | Driving input |
|---|---|---|---|
| Confidence model | Three discrete tiers (`Strong / Likely / Possible`) | Weighted scoring engine with explicit signals + counter-signals; tiers derived from score | Gemini critique §2.A; ChatGPT critique §5 |
| Naming heuristics | Sole confidence driver besides type-symmetry | Supplemented by type-flow analysis (composition, reducer/builder usage) | Gemini critique §1 |
| Algebraic detection | Idempotence, commutativity, associativity, identity element as independent templates | Composed into semigroup / monoid / group / semilattice / ring claims (§5.4) | `_4a_`, `_4c_` |
| Output of algebraic claims | Property tests only | Property tests *plus* RefactorBridge protocol-conformance suggestion (§6) | Gemini critique §3.1 |
| TestLifter input shape | Assumed clean two-step transforms | Slicing phase isolates property from setup (§7.2) | Gemini critique §1 |
| Generator inference | Fixed strategy table | Same table + mock-based synthesis from observed test construction (§7.4); explicitly delegates shared logic to SwiftProtocolLaws' `DerivationStrategist` | Gemini critique §3.3 |
| CLI UX | Static text dump | Static dump remains; adds `--interactive` triage mode (§8) | Gemini critique §2.B |
| CI integration | Unspecified | `swift-infer drift` non-fatal warning mode (§9) | Gemini critique §3.2 |
| Counter-signals | Implicit / absent | Explicit -∞ vetoes (non-Equatable output); -25/-20/-15 downscoring for asymmetric tests, side effects, weak generators | Gemini critique implicit; addresses ChatGPT critique §7 |
| Suggestion identity | Unspecified | Stable hash on AST shape; `.swiftinfer/decisions.json` persistence; `// swiftinfer: skip [hash]` survives regeneration (§7.5) | Mirrors SwiftProtocolLaws discovery plugin pattern |
| Backend coverage | Mentioned `swift-property-based` and `SwiftQC` | Single backend (`swift-property-based`) by design — mirrors SwiftProtocolLaws v1.0 decision | CLAUDE.md / SwiftProtocolLaws PRD §4.8 |
| Cross-function pairing annotation | Introduced `@Discoverable(group:)` as new API | Reuses existing `@Discoverable(group:)` from SwiftProtocolLaws ProtoLawMacro M5 | Avoids API duplication |
| Milestones (TemplateEngine) | 6 milestones | 7 milestones — added M7 for triage + drift modes | New scope from §8, §9 |
| Milestones (TestLifter) | 6 milestones | 8 milestones — added slicing (M1), mock synthesis (M4), counter-signal scanning (M7) | New scope from §7.2, §7.4, §7.7 |

-----

## Appendix B: Critiques in This Folder Not Yet Folded In

The `Property Inference/` folder contains two additional critiques that v0.2 does *not* incorporate beyond surface alignment, because the user explicitly handed in only Gemini's critique for this revision:

- **`ChatGPT critique.md`** — The strongest unincorporated idea is **Contribution 3 — Semantic Index** (a persistent queryable graph of inferred properties across runs). v0.2's RefactorBridge captures the highest-value chunk of that vision; the rest is deferred (Open Question 6). ChatGPT's other major themes — generator-confidence layering, weighted evidence model, counter-signals, suggestion-identity hashing — *are* in v0.2, arrived at independently via Gemini.
- **`Copilot critique.md`** — The strongest unincorporated suggestions are an **explicit "Product Philosophy" section** ("conservative inference engine; high precision over recall") and an **explicit Developer Workflow section**. Both would tighten the document; neither changes architecture. Easy to fold into v0.3.

A v0.3 pass folding both critiques in would be additive, not redirectional. Worth doing once benchmark data starts informing the scoring weights.
