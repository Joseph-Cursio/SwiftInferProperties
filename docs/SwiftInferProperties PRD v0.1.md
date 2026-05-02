# Product Requirements Document

## SwiftInfer: Type-Directed Property Inference for Swift

**Version:** 0.1 Draft  
**Status:** Proposal  
**Audience:** Open Source Contributors, Swift Ecosystem  
**Depends On:** SwiftProtocolLaws (ProtocolLawKit + ProtoLawMacro)

-----

## 1. Overview

SwiftProtocolLaws addresses the lowest-hanging fruit in automated property testing: if a type declares a protocol, verify that the implementation satisfies the protocol’s semantic laws. That project is intentionally scoped to the *explicit* — conformances the developer has already declared.

SwiftInfer addresses what comes next: the *implicit*. Properties that are meaningful and testable, but are not encoded in any protocol declaration. They live in the structure of function signatures, in the relationships between functions, and in the patterns visible in existing unit tests.

This document proposes **SwiftInfer**, a Swift package delivering two contributions:

- **Contribution 1 — TemplateEngine**: A library of named property templates matched against function signatures via SwiftSyntax, emitting candidate property tests for human review.
- **Contribution 2 — TestLifter**: A tool that analyzes existing XCTest and Swift Testing unit test suites, identifies structural patterns in the tests, and suggests generalized property tests derived from those patterns.

Both contributions produce *suggestions for human review*, not silently executed tests. The developer is always in the loop.

-----

## 2. Problem Statement

### 2.1 Properties Beyond Protocols

Protocol law testing, as provided by SwiftProtocolLaws, covers a well-defined and bounded space. But most of the interesting correctness properties of a codebase are not expressible as protocol laws. Consider:

```swift
func normalize(_ input: String) -> String
func compress(_ data: Data) -> Data
func decompress(_ data: Data) -> Data
func applyDiscount(_ price: Decimal, _ rate: Decimal) -> Decimal
```

None of these functions declare any protocol that implies testable properties. Yet:

- `normalize` is likely idempotent: `normalize(normalize(x)) == normalize(x)`
- `compress`/`decompress` form a round-trip pair: `decompress(compress(x)) == x`
- `applyDiscount` likely preserves ordering: if `a < b` then `applyDiscount(a, r) < applyDiscount(b, r)`

These properties are discoverable from *structure* — function names, type signatures, and relationships between functions — without requiring the developer to have written any tests at all.

### 2.2 The Unit Test as an Underused Signal

Most Swift codebases with meaningful test coverage have unit tests that implicitly encode structural knowledge. A test like:

```swift
func testRoundTrip() {
    let original = MyData(value: 42)
    let encoded = encoder.encode(original)
    let decoded = decoder.decode(encoded)
    XCTAssertEqual(original, decoded)
}
```

encodes the round-trip property for one specific input. The general property — `decode(encode(x)) == x` for *all* `x` — is right there, but it takes a deliberate step to lift it. Most developers don’t take that step because nothing prompts them to and the activation energy is nonzero.

### 2.3 The Gap SwiftInfer Fills

SwiftProtocolLaws handles: *“you declared a protocol, does your implementation honor its laws?”*

SwiftInfer handles: *“given what your code looks like and what your tests say, what properties are you implicitly claiming?”*

Together they cover the automated end of the property inference spectrum, from explicit protocol contracts down through structural inference to test-guided generalization.

-----

## 3. Goals and Non-Goals

### Goals

- Identify candidate properties from function signatures without requiring any developer annotation
- Surface round-trip pairs, idempotence candidates, and other algebraic patterns through structural analysis
- Analyze existing unit test suites and suggest lifted property tests
- Produce human-reviewable output with clear provenance and confidence indicators
- Integrate with SwiftProtocolLaws’ `PropertyBackend` abstraction for test execution
- Operate as a CLI discovery tool, a compiler plugin, or both

### Non-Goals

- Automatically executing inferred properties without human review
- Replacing unit tests or SwiftProtocolLaws protocol law checks
- Full runtime invariant inference (Daikon-style instrumentation)
- Stateful / model-based test generation (separate project scope)
- Correctness guarantees on inferred properties — all output is probabilistic suggestion

-----

## 4. Confidence Model

SwiftInfer assigns every suggestion a confidence tier. This is surfaced in all output and governs how aggressively suggestions are promoted.

|Tier  |Label       |Meaning                                         |Example                                       |
|------|------------|------------------------------------------------|----------------------------------------------|
|High  |`✓ Strong`  |Structural evidence is unambiguous              |`encode`/`decode` pair with matching types    |
|Medium|`~ Likely`  |Pattern matches but heuristic-dependent         |`normalize` as idempotence candidate by name  |
|Low   |`? Possible`|Weak signal, requires significant human judgment|ordering property inferred from numeric inputs|

Low-confidence suggestions are opt-in. The default output shows only Strong and Likely.

All suggestions include:

- The property template matched
- The evidence that triggered the match
- The specific functions or tests involved
- A reproducible seed if a trial run was performed during discovery

-----

## 5. Contribution 1: TemplateEngine

### 5.1 Description

TemplateEngine is a SwiftSyntax-based static analysis pipeline that scans Swift source files, matches function signatures and naming patterns against a registry of named property templates, and emits candidate property test stubs.

### 5.2 Property Template Registry

The registry is the intellectual core of TemplateEngine. Each entry defines:

- A named algebraic property shape
- The type signature pattern it requires
- The naming heuristics that raise confidence
- The property test body to emit
- Interaction warnings with other templates

#### Round-Trip

**Pattern:** Two functions `f: T → U` and `g: U → T` in the same module or type.

**Confidence boost:** Names match known inverse pairs (`encode`/`decode`, `serialize`/`deserialize`, `compress`/`decompress`, `encrypt`/`decrypt`, `push`/`pop`, `insert`/`remove`, `open`/`close`).

**Emitted property:**

```swift
// Template: round-trip
// Evidence: encode(_:) -> Data, decode(_:) -> MyType (MyType.swift:14, 22)
@Test func roundTripEncoding() async {
    await propertyCheck(input: Gen.derived(MyType.self)) { value in
        #expect(try decode(encode(value)) == value)
    }
}
```

#### Idempotence

**Pattern:** A function `f: T → T` (same input and output type).

**Confidence boost:** Name contains `normalize`, `canonicalize`, `trim`, `flatten`, `sort`, `deduplicate`, `sanitize`, `format`.

**Emitted property:**

```swift
// Template: idempotence
// Evidence: normalize(_:) -> String (StringUtils.swift:8)
@Test func normalizeIsIdempotent() async {
    await propertyCheck(input: Gen.string()) { value in
        #expect(normalize(normalize(value)) == normalize(value))
    }
}
```

#### Commutativity

**Pattern:** A function `f: (T, T) → T` (binary operation, same type throughout).

**Confidence boost:** Name contains `merge`, `combine`, `union`, `add`, `plus`.

**Contradiction check:** Combining with associativity and identity implies a monoid — warn if the type does not conform to `AdditiveArithmetic` or similar.

**Emitted property:**

```swift
// Template: commutativity
// Evidence: merge(_:_:) -> Config (Config.swift:31)
@Test func mergeIsCommutative() async {
    await propertyCheck(input: Gen.zip(Gen.derived(Config.self), Gen.derived(Config.self))) { a, b in
        #expect(merge(a, b) == merge(b, a))
    }
}
```

#### Associativity

**Pattern:** Same as commutativity — `f: (T, T) → T`.

**Confidence boost:** Same naming signals as commutativity; often suggested alongside it.

#### Monotonicity

**Pattern:** A function `f: T → U` where both `T` and `U` are `Comparable`.

**Confidence boost:** Name contains `scale`, `apply`, `transform`, `weight`.

**Emitted property:**

```swift
// Template: monotonicity
// Evidence: applyDiscount(_:_:) -> Decimal (Pricing.swift:19)
@Test func applyDiscountIsMonotone() async {
    await propertyCheck(input: Gen.zip(Gen.decimal(), Gen.decimal(in: 0...1))) { price, rate in
        // NOTE: direction (increasing/decreasing) requires human verification
        let result1 = applyDiscount(price, rate)
        let result2 = applyDiscount(price + 1, rate)
        #expect(result1 <= result2) // adjust direction if needed
    }
}
```

#### Identity Element

**Pattern:** A binary operation `f: (T, T) → T` combined with a static zero-like value (`zero`, `empty`, `identity`, `none`, `default`).

**Emitted property:**

```swift
// Template: identity-element
// Evidence: combine(_:_:) -> T, T.empty (Collection+Combine.swift)
@Test func emptyIsIdentity() async {
    await propertyCheck(input: Gen.derived(T.self)) { value in
        #expect(combine(value, .empty) == value)
        #expect(combine(.empty, value) == value)
    }
}
```

#### Invariant Preservation

**Pattern:** Any mutating or transforming function where a measurable property (count, isEmpty, a computable predicate) should hold before and after.

**Confidence:** Low by default — requires user annotation or strong naming evidence.

```swift
// Template: invariant-preservation
// Evidence: append(_:) on Stack — count increases by 1
@Test func appendIncreasesCount() async {
    await propertyCheck(input: Gen.zip(Gen.derived(Stack<Int>.self), Gen.int())) { stack, value in
        let before = stack.count
        var modified = stack
        modified.append(value)
        #expect(modified.count == before + 1)
    }
}
```

### 5.3 Cross-Function Pairing Strategy

Naive cross-function pairing is O(n²). TemplateEngine avoids this through tiered filtering:

1. **Type filter (primary):** Only pair `f: T → U` with `g: U → T`. Applied first, eliminates most candidates.
2. **Naming filter (secondary):** Score pairs by known inverse name patterns.
3. **Scope filter (tertiary):** Prefer pairs within the same type or file before considering module-wide pairs.
4. **User grouping (optional):** `@Discoverable(group: "serialization")` explicitly groups functions for pairing.

In practice, a module of 50 functions typically produces fewer than 10 candidate pairs after type filtering.

### 5.4 Contradiction Detection

When multiple templates are suggested for the same function, TemplateEngine checks for logical contradictions before emitting:

|Combination                       |Implication                |Warning                                          |
|----------------------------------|---------------------------|-------------------------------------------------|
|Idempotent + Involutive           |`f` must be identity       |⚠️ These together imply `f(x) == x`; verify intent|
|Commutative + non-Equatable output|Commutativity is untestable|⚠️ Output type must be Equatable                  |
|Round-trip without Equatable on T |Round-trip is untestable   |⚠️ T must conform to Equatable                    |

### 5.5 Annotation API

Developers can guide TemplateEngine with lightweight annotations rather than waiting for automatic discovery:

```swift
@CheckProperty(.idempotent)
func normalize(_ input: String) -> String { ... }

@CheckProperty(.roundTrip, pairedWith: "decode")
func encode(_ value: MyType) -> Data { ... }

@Discoverable(group: "serialization")
func decode(_ data: Data) -> MyType { ... }
```

`@CheckProperty` triggers immediate stub generation for that function. `@Discoverable` groups functions for cross-function pairing without asserting a specific template.

### 5.6 Milestones

|Milestone|Deliverable                                                                   |
|---------|------------------------------------------------------------------------------|
|M1       |Round-trip and idempotence templates, SwiftSyntax pipeline, CLI discovery tool|
|M2       |Commutativity, associativity, identity element templates                      |
|M3       |Contradiction detection                                                       |
|M4       |Monotonicity and invariant preservation templates                             |
|M5       |`@CheckProperty` and `@Discoverable` annotation API                           |
|M6       |Cross-function pairing with full filtering pipeline                           |

-----

## 6. Contribution 2: TestLifter

### 6.1 Description

TestLifter analyzes existing XCTest and Swift Testing test suites, identifies structural patterns in test method bodies, and suggests generalized property tests derived from those patterns. The premise is that unit tests contain implicit structural knowledge that can be lifted into general properties with the developer’s guidance.

### 6.2 Pattern Recognition

TestLifter parses test method bodies using SwiftSyntax and matches against a set of structural patterns:

#### Assert-after-Transform

```swift
// Detected pattern: value → transform → assert equality with original
func testRoundTrip() {
    let original = MyData(value: 42)
    let transformed = encode(original)
    let recovered = decode(transformed)
    XCTAssertEqual(original, recovered)
}
```

**Suggestion:** Round-trip property. The specific value `42` is incidental; the structure is general.

#### Assert-after-Double-Apply

```swift
// Detected pattern: value → f → f → assert equality with f(value)
func testNormalization() {
    let input = "  Hello  "
    let once = normalize(input)
    let twice = normalize(once)
    XCTAssertEqual(once, twice)
}
```

**Suggestion:** Idempotence property.

#### Assert-Symmetry

```swift
// Detected pattern: f(a, b) == f(b, a) for specific values
func testMergeOrder() {
    let a = Config(priority: 1)
    let b = Config(priority: 2)
    XCTAssertEqual(merge(a, b), merge(b, a))
}
```

**Suggestion:** Commutativity property.

#### Assert-Ordering-Preserved

```swift
// Detected pattern: a < b, then f(a) <= f(b)
func testDiscountPreservesOrder() {
    let low = Decimal(10)
    let high = Decimal(20)
    XCTAssertLessThanOrEqual(applyDiscount(low, 0.1), applyDiscount(high, 0.1))
}
```

**Suggestion:** Monotonicity property.

#### Assert-Count-Change

```swift
// Detected pattern: count before, mutate, assert count after with arithmetic relationship
func testAppendIncreasesCount() {
    var stack = Stack<Int>()
    let before = stack.count
    stack.append(42)
    XCTAssertEqual(stack.count, before + 1)
}
```

**Suggestion:** Invariant preservation property.

### 6.3 Lifted Output Format

For each detected pattern, TestLifter emits a property test stub alongside provenance linking back to the originating unit test:

```swift
// LIFTED from: testRoundTrip() (MyDataTests.swift:14)
// Pattern: round-trip
// Confidence: Strong
// Original test used specific input: MyData(value: 42)
// This property generalizes to all MyData values.
//
// ⚠️  Requires a generator for MyData. Replace .todo below.

@Test func roundTripProperty() async {
    await propertyCheck(input: Gen.todo(MyData.self)) { value in
        #expect(decode(encode(value)) == value)
    }
}
```

The `.todo` generator is a deliberate forcing function — the stub does not compile until the developer provides a real generator, ensuring the lifted test is consciously adopted rather than blindly accepted.

### 6.4 Generator Inference

Where possible, TestLifter infers a generator from the types observed in the unit test:

|Condition                                                       |Strategy                    |
|----------------------------------------------------------------|----------------------------|
|Type conforms to `CaseIterable`                                 |`Gen.allCases`              |
|Type conforms to `Codable` and values appear in test as literals|`Gen.derived` using JSON    |
|Type has a visible memberwise init with all-primitive parameters|Compose primitive generators|
|SwiftProtocolLaws generator already registered for this type            |Reuse it                    |
|None of the above                                               |Emit `.todo` stub           |

### 6.5 Relationship to Existing Unit Tests

TestLifter does not modify or replace existing unit tests. The relationship is:

- **Unit tests** remain as regression anchors for specific known cases
- **Lifted properties** generalize those cases across the input space
- When a lifted property finds a new counterexample, it becomes a new unit test (a regression oracle)

This creates a feedback loop: unit tests seed property discovery; property tests generate new unit tests when they fail.

### 6.6 Confidence and Noise

Test-guided inference is inherently lower confidence than structural inference, because unit tests may encode accidental structure — patterns that happen to appear in the test values chosen, but don’t represent real invariants.

TestLifter mitigates this through:

- **Minimum test count:** A pattern must appear in at least 2 distinct test methods before a suggestion is emitted (configurable)
- **Human review gate:** All output is clearly marked as suggested, never auto-committed
- **Explicit rejection:** Developers can annotate a test to suppress lifting: `// swiftinfer: skip`

### 6.7 Milestones

|Milestone|Deliverable                                                                          |
|---------|-------------------------------------------------------------------------------------|
|M1       |SwiftSyntax test body parser, assert-after-transform detection, round-trip suggestion|
|M2       |Double-apply (idempotence) and symmetry (commutativity) detection                    |
|M3       |Generator inference strategies, `.todo` stub pattern                                 |
|M4       |Ordering and count-change pattern detection                                          |
|M5       |Minimum test count threshold, `// swiftinfer: skip` suppression                      |
|M6       |Feedback loop tooling — convert failing property counterexamples to unit test stubs  |

-----

## 7. Architecture Overview

```
┌──────────────────────────────────────────────────────┐
│                    SwiftInfer                        │
│                                                      │
│  ┌─────────────────┐      ┌───────────────────────┐  │
│  │  TemplateEngine │      │      TestLifter        │  │
│  │                 │      │                        │  │
│  │ SwiftSyntax     │      │ SwiftSyntax            │  │
│  │ signature scan  │      │ test body analysis     │  │
│  │                 │      │                        │  │
│  │ Template        │      │ Pattern registry       │  │
│  │ registry        │      │ (structural lifting)   │  │
│  │                 │      │                        │  │
│  │ @CheckProperty  │      │ Generator inference    │  │
│  │ @Discoverable   │      │ Provenance tracking    │  │
│  └────────┬────────┘      └───────────┬───────────┘  │
│           │                           │               │
│           └──────────┬────────────────┘               │
│                      │ emits stubs using              │
└──────────────────────┼──────────────────────────────--┘
                       │
┌──────────────────────▼──────────────────────────────┐
│                 SwiftProtocolLaws                    │
│            PropertyBackend abstraction               │
│         swift-property-based / SwiftQC               │
└─────────────────────────────────────────────────────┘
```

-----

## 8. Relationship to SwiftProtocolLaws

SwiftInfer is explicitly downstream of SwiftProtocolLaws and does not duplicate its concerns:

|Concern                                      |Handled By                          |
|---------------------------------------------|------------------------------------|
|Protocol semantic law verification           |SwiftProtocolLaws (ProtocolLawKit)                  |
|Protocol conformance detection               |SwiftProtocolLaws (ProtoLawMacro)                |
|Missing protocol suggestions                 |SwiftProtocolLaws (ProtoLawMacro)                |
|Structural property inference from signatures|SwiftInfer (TemplateEngine)         |
|Property inference from unit tests           |SwiftInfer (TestLifter)             |
|Test execution backend                       |SwiftProtocolLaws (PropertyBackend) — shared|

SwiftInfer reuses SwiftProtocolLaws’ `PropertyBackend` abstraction directly. Generator registrations made in SwiftProtocolLaws (e.g., a `Gen<MyType>` registered for law checking) are visible to SwiftInfer’s generator inference, avoiding duplication.

-----

## 9. Risks and Mitigations

|Risk                                               |Likelihood|Mitigation                                                                  |
|---------------------------------------------------|----------|----------------------------------------------------------------------------|
|Template matching produces too many false positives|High      |Conservative confidence tiers; default to Strong/Likely only; opt-in for Low|
|Lifted unit test patterns don’t generalize         |Medium    |Minimum test count threshold; `.todo` generator forces conscious adoption   |
|Generator inference fails for complex types        |Medium    |Graceful fallback to `.todo` stub; never silently skip                      |
|Cross-function pairing is noisy without grouping   |Medium    |Type filter eliminates most pairs; `@Discoverable` groups available         |
|Property contradictions cause user confusion       |Low       |Contradiction detection table in TemplateEngine; clear warnings             |
|Developers ignore generated stubs                  |Medium    |Compile-time enforcement via `.todo` — stubs don’t compile until adopted    |

-----

## 10. Success Criteria

### TemplateEngine

- Running the discovery CLI on a real-world Swift module of 50+ functions produces fewer than 10 Strong-confidence suggestions, of which at least 80% are judged useful by a Swift developer unfamiliar with the tool
- Round-trip, idempotence, and commutativity templates correctly identify known patterns in at least 3 open source Swift packages used as benchmarks
- Contradiction detection catches idempotent+involutive and at least 2 other known contradictory combinations

### TestLifter

- Running on a test suite of 50+ XCTest methods correctly identifies at least 5 liftable patterns with Strong or Likely confidence
- At least 90% of emitted stubs compile after the developer resolves `.todo` generators
- No existing unit test is modified or deleted by the tool under any circumstances

-----

## 11. Open Questions

1. **Separate package or monorepo?** Should SwiftInfer be a separate package from SwiftProtocolLaws, or a set of additional targets in the same repository? Separate packages preserve independent versioning; a monorepo simplifies shared abstractions.
2. **TemplateEngine as compiler plugin vs. CLI?** The discovery CLI is the right model for whole-module scanning, but should TemplateEngine also expose a compiler plugin mode for incremental per-file suggestions during development?
3. **TestLifter and Swift Testing vs. XCTest?** Swift Testing’s `@Test` macro makes test body parsing harder than XCTest’s method-based structure. Should M1 target XCTest only, with Swift Testing support deferred?
4. **Community template contributions:** The template registry is the most valuable long-term artifact. Should it be designed as an extensible registry that third parties can contribute to, or kept curated and closed for quality control?
5. **Integration with SwiftProtocolLaws ProtoLawMacro:** ProtoLawMacro already detects missing protocol conformances. Should TemplateEngine’s structural analysis feed into ProtoLawMacro’s suggestions (e.g., “this type pattern matches Monoid — consider conforming to AdditiveArithmetic”), or remain strictly separate?

-----

## 12. References

- [_7_SwiftProtocolLaws PRD](_7_SwiftProtocolLaws%20PRD.md) — upstream dependency
- [swift-property-based](https://github.com/x-sheep/swift-property-based) — execution backend
- [SwiftQC](https://github.com/Aristide021/SwiftQC) — alternative backend
- [SwiftSyntax](https://github.com/apple/swift-syntax) — static analysis foundation
- [EvoSuite](https://www.evosuite.org) — Java property inference inspiration
- [Daikon](https://plse.cs.washington.edu/daikon/) — runtime invariant inference reference
- [QuickSpec](https://hackage.haskell.org/package/quickspec) — Haskell equational property discovery
- [Hedgehog state machines](https://hedgehog.qa) — stateful testing reference (out of scope, noted for future)