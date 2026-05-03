# Product Requirements Document

## SwiftInfer: Type-Directed Property Inference for Swift

**Version:** 1.0
**Status:** Shipped (v1 surface complete; v1.1+ trajectory described in §20)
**Audience:** Open Source Contributors, Swift Ecosystem
**Depends On:** SwiftProtocolLaws (ProtocolLawKit + ProtoLawMacro + ProtoLawCore), v1.9.0+

> This document describes the v1 SwiftInfer surface as it exists today: TemplateEngine + RefactorBridge + TestLifter, plus the §7.8 first-example expanded output (preconditions). Where features are shipped, the prose is descriptive ("the system does"). Where features are deferred to v1.1+, the prose is forward-looking ("would" / "is planned"). The §5.8, §5.9, and §7.9 milestone tables call out the **STATUS** column for each row so readers can see at a glance what's done versus what's named-but-deferred.

-----

## 1. Overview

SwiftProtocolLaws addresses the lowest-hanging fruit in automated property testing: if a type declares a protocol, verify that the implementation satisfies the protocol's semantic laws. That project is intentionally scoped to the *explicit* — conformances the developer has already declared.

SwiftInfer addresses what comes next: the *implicit*. Properties that are meaningful and testable, but are not encoded in any protocol declaration. They live in the structure of function signatures, in the relationships between functions, in the algebraic shape of operations, and in the patterns visible in existing unit tests.

This document describes **SwiftInfer**, a Swift package delivering three v1 contributions and one planned v1.1 contribution:

- **Contribution 1 — TemplateEngine** (shipped): A library of named property templates matched against function signatures via SwiftSyntax + light type-flow analysis, emitting candidate property tests for human review. Includes algebraic-structure detectors (semigroup, monoid, group, semilattice, ring) that drive both test generation *and* protocol-conformance refactoring suggestions.
- **Contribution 2 — TestLifter** (shipped): A tool that analyzes existing XCTest and Swift Testing unit test suites, slices each test body into "setup" and "property" regions, and suggests generalized property tests derived from the property region — including generator candidates inferred from how values were constructed in the test, and inferred preconditions surfaced as advisory comments inside generated `Gen<T>` bodies.
- **Contribution 3 — RefactorBridge** (shipped): When TemplateEngine accumulates enough algebraic evidence on a type, SwiftInfer suggests the corresponding standard-library or kit-supported protocol conformance so the property can be verified by SwiftProtocolLaws on every CI run.
- **Contribution 4 (v1.1) — SemanticIndex** (deferred): A persistent, queryable graph of inferred properties and relationships across runs. Discussed in §20 Future Directions, deliberately out of v1 scope. Mentioned here so the v1 architecture leaves the door open.

All shipped contributions produce *suggestions for human review*, not silently executed tests. The developer is always in the loop.

-----

## 2. Problem Statement

### 2.1 Properties Beyond Protocols

Protocol law testing covers a well-defined and bounded space. Most of the interesting correctness properties of a codebase are not expressible as protocol laws as written. Consider:

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

Algebraic structures (semigroups, monoids, groups, semilattices, rings) are not exotic — they're the backbone of common Swift code patterns:

- **Reducers and state machines** → semigroup operation under event application
- **Undo/redo systems** → group with identity, inverse, associative composition
- **Configuration merging / feature-flag resolution** → join-semilattice (associative, commutative, idempotent)
- **Numeric pipelines (graphics, audio, finance)** → ring under `+` and `*`
- **Compiler / SwiftSyntax / lint passes** → semigroup under composition
- **Concurrency primitives (task merging, cancellation)** → semigroup or monoid
- **String/Array/Log/Dictionary accumulators** → monoid with `empty` identity

When SwiftInfer detects these patterns, it generates the corresponding properties **and** points the developer at the standard-library or kit-supported protocol they could conform to so SwiftProtocolLaws verifies the laws on every run thereafter. That bridge — discovery now, enforcement forever — is RefactorBridge.

### 2.3 The Unit Test as an Underused Signal

Real-world tests are messy. A `testRoundTrip` may include five lines of `JSONEncoder` configuration before the actual round-trip assertion. The general property is right there, but extracting it requires *slicing* the test into the encoder/decoder construction (setup) and the assertion chain (property). TestLifter does this slicing explicitly.

### 2.4 The Gap SwiftInfer Fills

SwiftProtocolLaws handles: *"you declared a protocol, does your implementation honor its laws?"*

SwiftInfer handles: *"given what your code looks like and what your tests say, what properties are you implicitly claiming, and is there a protocol you should be conforming to so SwiftProtocolLaws can keep verifying them?"*

-----

## 3. Goals and Non-Goals

### Goals

- Identify candidate properties from function signatures and types without requiring developer annotation
- Surface round-trip pairs, idempotence candidates, and **algebraic structures** through structural analysis
- Suggest protocol conformances that would let SwiftProtocolLaws verify discovered algebraic laws on every CI run (RefactorBridge)
- Analyze existing unit test suites and suggest lifted property tests, slicing test bodies into setup/property regions
- Infer generator candidates from how values were constructed in existing tests, delegating to SwiftProtocolLaws' shared `DerivationStrategist`
- Surface inferred preconditions on those generators as advisory comments when the test corpus shows a homogeneous literal pattern (e.g. `value: positive Int` across every test site)
- Produce human-reviewable output with weighted-score provenance, counter-signals, and **first-class explainability** (§4.5)
- Operate as a CLI discovery tool with an interactive triage mode, and as a non-fatal CI drift checker
- Integrate with SwiftProtocolLaws' `PropertyBackend` abstraction for test execution
- Track adoption decisions so the scoring engine can be empirically tuned (§17, v1.1+)

### Non-Goals

- Automatically executing inferred properties without human review
- Replacing unit tests or SwiftProtocolLaws protocol law checks
- Full runtime invariant inference (Daikon-style instrumentation)
- Stateful / model-based test generation (separate project scope)
- Correctness guarantees on inferred properties — all output is probabilistic suggestion
- Persistent semantic indexing across runs (deferred to v1.1 — see §20)
- IDE plugins (Xcode quick-fix integration is desirable but out of scope for v1 — see §20)

-----

## 3.5 Product Philosophy

> SwiftInfer is a **conservative inference engine**. It prioritizes high precision and low recall. The goal is not to discover every possible property, but to surface only those with strong structural or behavioral evidence.

This philosophy governs every design choice in this document. Three corollaries:

1. **False positives are more damaging than missed opportunities.** A developer who reviews ten suggestions and finds one wrong loses trust faster than one who runs the tool again next month and finds new suggestions. Every threshold, signal weight, and default visibility setting in this document is biased toward suppression.
2. **All output is opt-in and human-reviewed.** SwiftInfer never auto-applies, never auto-executes, never auto-commits. Even in CI mode (§9), it emits warnings, not failures.
3. **The Daikon trap is the failure mode to avoid.** Daikon (runtime invariant inference) famously produces hundreds of true-but-uninteresting invariants. SwiftInfer's defaults must produce a number of suggestions a developer can read in one sitting; if benchmark calibration shows we're producing more, the answer is to raise thresholds, not to add filters on top.

This philosophy is load-bearing for the scoring engine (§4) and the success criteria (§19). When in doubt about a design choice, default to whichever option produces fewer suggestions.

-----

## 3.6 Developer Workflow

The intended end-to-end workflow. Each step lists its owning milestone (§5.8 for TemplateEngine, §7.9 for TestLifter, §5.9 for the cross-reference table).

1. **Discovery.** Developer runs `swift-infer discover --target MyApp` or `swift-infer discover --interactive`. Both subcommands ship in the v1 surface.
2. **Suggestion review.** Suggestions are grouped by tier (`✓ Strong`, `~ Likely`, optionally `? Possible` with `--include-possible`). Each suggestion shows its evidence trail and explainability block (§4.5).
3. **Adoption.** Accepted suggestions write stubs to `Tests/Generated/SwiftInfer/`, opt-in via `--interactive`'s `[A]` / `[B]` / `[B']` accept (multi-proposal prompt for incomparable algebraic-structure arms — see §5.4). The user can also opt-in *per declaration* via the `@CheckProperty` macro (§5.7), which expands an `@Test` peer in the user's own source — not under `Tests/Generated/SwiftInfer/`. RefactorBridge suggestions write conformance stubs to `Tests/Generated/SwiftInferRefactors/` for the developer to inspect and move (never auto-edit existing source — see §16).
4. **Generator completion.** Developer resolves any `.todo` generators. Mock-based synthesis (§7.4) reduces this step's frequency. Inferred preconditions (§7.8) on mock-synthesized generators surface as `// Inferred precondition:` comment lines inside the generated `Gen<T>` body so the user can tighten the generator from `Gen.int()` to e.g. `Gen.int(in: 1...5)` when the test corpus shows that pattern.
5. **Execution.** `PropertyBackend` (single backend: `swift-property-based`) executes the tests via the standard `swift test` flow.
6. **Counterexample feedback.** When a property fails, the shrunk counterexample is convertible into a focused unit test via `swift-infer convert-counterexample`.
7. **Drift checking.** CI runs `swift-infer drift --baseline .swiftinfer/baseline.json` on every PR, warning (non-fatally) about new Strong-tier suggestions added since baseline that lack a recorded decision.
8. **Decision persistence.** Accept / reject / skip decisions live in `.swiftinfer/decisions.json`, keyed by stable suggestion-identity hash (§7.5). Decisions survive refactors that don't change function signatures or AST shape.

-----

## 4. Confidence Model — Weighted Scoring Engine

A weighted score built from independent signals, plus pluggable naming vocabularies (§4.5) so project-specific conventions can extend the curated lists without forking the tool.

### 4.1 Signals

A suggestion's score is the sum of contributing signals (positive and negative). Signals are independent — a suggestion can earn confidence from naming alone, from types alone, or from any combination.

| Signal | Weight | Description |
|---|---|---|
| **Exact name match** | +40 | Function pair matches a curated inverse list (`encode`/`decode`, `serialize`/`deserialize`, `compress`/`decompress`, `encrypt`/`decrypt`, `push`/`pop`, `insert`/`remove`, `open`/`close`, `marshal`/`unmarshal`, `pack`/`unpack`, `lock`/`unlock`) **or** a project-vocabulary entry (§4.5). |
| **Type-symmetry signature** | +30 | `T → U` paired with `U → T` in the same scope (type, file, or module). For unary templates, `T → T` for idempotence; `(T, T) → T` for binary-op templates. |
| **Algebraic-structure cluster** | +25 per element | Type exposes a binary op `(T, T) → T` *and* an identity-shaped constant. Each additional element (associativity confirmed by signature; inverse function present; idempotence detected) adds +25. |
| **Reduce/fold usage** | +20 | The type is used in `.reduce(identity, op)` or a manual `for`/accumulator builder pattern at least once in the analyzed corpus. |
| **`@Discoverable(group:)` annotation** | +35 | Two functions share an explicit `@Discoverable(group:)` from SwiftProtocolLaws — promoted to HIGH in `ProtoLawMacro`'s discovery and re-used here. |
| **Test-body pattern** | +50 | TestLifter detects the same structural pattern in 3+ distinct test methods. Configurable; default is 2. |
| **Cross-validation** | +20 | TemplateEngine (signature) and TestLifter (test) independently arrive at the same template for the same function. Capped at +20. |
| **Sampling pass under derived generator** | +10 | A trial run of 25 samples passes using a `DerivationStrategist`-supplied generator. Deliberately small — see §4.3. |
| **Side-effect penalty** | -20 | Function is `mutating`, returns `Void`, has `inout` params, or calls APIs marked unsafe/IO-bound. |
| **Generator-quality penalty** | -15 | Best generator available is `.todo` or weakly-typed for an explicitly bounded domain. |
| **Counter-signal: asymmetric assertion** | -25 | TestLifter found an explicitly asymmetric assertion contradicting a candidate symmetric property in any test. |
| **Counter-signal: anti-commutativity naming** | -30 | Function name matches a curated anti-commutativity list (`subtract`, `difference`, `divide`, `apply`, `prepend`, `append`, `concat`-family) **or** a project-vocabulary `antiCommutativityVerbs` entry (§4.5). Applies to commutativity, semilattice, and any algebraic-structure claim that requires commutativity. |
| **Counter-signal: early return / partial function** | -15 | Function body has guard/early-return paths suggesting partiality, contradicting `T → T` totality. |
| **Counter-signal: non-deterministic body** | -∞ | Type-flow analysis detects calls to `Date()`, `Date.now`, `UUID()`, `Random.next()`, `URLSession`, or other clock/IO/randomness APIs in the function body. Disqualifies idempotence and most algebraic claims (see Appendix B.3). |
| **Counter-signal: uses non-Equatable output** | -∞ | The output type is not `Equatable` — the property is structurally untestable. Suggestion is suppressed entirely. |

### 4.2 Tier Mapping

| Score | Tier | Default visibility |
|---|---|---|
| ≥ 75 | `✓ Strong` | shown |
| 40–74 | `~ Likely` | shown |
| 20–39 | `? Possible` | hidden by default; surfaced with `--include-possible` |
| < 20 | suppressed | never shown |

The thresholds are tunable. Real-world calibration against open-source corpora (per §19) is what sets them; treat the numbers above as v1 starting points, not load-bearing constants. The empirical recalibration loop is described in §17 (Adoption Tracking, v1.1+).

### 4.3 Generator Awareness

Every suggestion's evidence record includes:

- `generatorSource`: `.derived(.caseIterable | .rawRepresentable | .memberwise | .codableRoundTrip)` | `.registered` | `.todo` | `.inferredFromTests`
- `generatorConfidence`: `.high` | `.medium` | `.low`
- `samplingResult`: `.passed(trials: N)` | `.failed(seed: S, counterexample: C)` | `.notRun`

A "Strong" suggestion that passed sampling under a `.low` generator is rendered with an explicit caveat in the explainability block (§4.5).

### 4.4 Counter-Signals Are Veto-Capable

The negative-weight rows above accumulate disconfirming evidence. The `non-Equatable output` signal is special-cased to `-∞` because the property is structurally untestable.

### 4.5 Explainability as a First-Class Output

Explainability isn't just nice-to-have, it's the load-bearing substitute for trust in a probabilistic tool. Every suggestion ships a structured **two-sided block**:

```text
Score:       95 (Strong)

Why suggested:
  ✓ encode(_:) -> Data, decode(_:) -> MyType — MyType.swift:14, 22
  ✓ Curated inverse name pair: encode/decode  (+40)
  ✓ Type-symmetry: T → Data ↔ Data → T        (+30)
  ✓ Sampling: 25/25 passed under derived generator (+10)
      generator: .derived(.memberwise), confidence: .high

Why this might be wrong:
  ⚠ encode is throwing, decode is throwing — round-trip on errors is asymmetric.
    The emitted property uses `try`; if encode throws on values decode
    accepts, the property is over a smaller domain than `MyType`.
  ⚠ Sampling did not exercise edge cases (empty Data, max-length strings) —
    use `--exhaustive` to widen.
```

Every suggestion ships both blocks. The "why this might be wrong" block is constructed from:

- Active counter-signals that didn't fully veto (e.g., -15 partial-function penalty applied but score still Strong)
- Known caveats for the matched template (e.g., round-trip with throws on either side, monotonicity direction unknown, Numeric vs FloatingPoint distinction for ring claims — see §5.4)
- Generator confidence below `.high`
- Sampling coverage gaps

If the "why this might be wrong" block is empty for a Strong suggestion, that fact is itself rendered ("✓ no known caveats for this template"), so absence is explicit and not just "we didn't think to check."

#### Pluggable Naming Vocabularies

The curated inverse-name list and the per-template name-suggestion sets (§5.2) are extensible. Projects can ship a `.swiftinfer/vocabulary.json`:

```json
{
  "inversePairs": [
    ["enqueue", "dequeue"],
    ["activate", "deactivate"],
    ["acquireLock", "releaseLock"]
  ],
  "idempotenceVerbs": ["sanitizeXML", "rewritePath"],
  "commutativityVerbs": ["unionGraphs"],
  "antiCommutativityVerbs": ["concatenateOrdered"],
  "inverseElementVerbs": ["undo", "revert"]
}
```

These extend (not replace) the curated lists. Project-vocabulary matches contribute the same +40 / +25 / -30 weights as the built-in lists. v1.1 may add an opt-in mode that mines naming patterns from the analyzed repo itself — punted for now (§21 Open Question 5).

-----

## 5. Contribution 1: TemplateEngine

### 5.1 Description

TemplateEngine is a SwiftSyntax-based static analysis pipeline that scans Swift source files, matches function signatures and naming patterns against a registry of named property templates, accumulates signals per the §4 scoring engine, and emits candidate property test stubs (and, for algebraic clusters, RefactorBridge suggestions per §6).

> **Evolution path.** "Templates as patterns over signatures" risks becoming a rigid rule engine; the long-term direction is **constraints over a function graph + types + usage** (the "Constraint Engine" upgrade). v1 ships the template-pattern model — the simplest thing that produces useful output. The constraint-engine upgrade is on the v1.1+ trajectory (§20). The v1 architecture is built so the constraint engine can replace the matcher behind the scoring engine without touching downstream contracts.

### 5.2 Property Template Registry

Each entry defines:

- A named algebraic property shape
- The type-signature pattern it requires
- The naming heuristics that contribute to the score (curated + project vocabulary)
- The usage patterns that contribute to the score (type-flow)
- The property test body to emit
- Counter-signals that veto or downscore the suggestion
- The known caveats that always appear in the "why this might be wrong" explainability block (§4.5)
- Interaction warnings with other templates

The eight shipped templates are: round-trip, idempotence, commutativity, associativity, monotonicity, identity-element, invariant-preservation, inverse-pair.

The two foundational templates — round-trip and idempotence — are specified in full below. The other six follow the same pattern.

#### Round-Trip

**Type pattern:** Two functions `f: T → U` and `g: U → T` in the same module, with `T: Equatable`. *Necessary.*

**Name signals:** known inverse pairs (`encode`/`decode`, `serialize`/`deserialize`, `compress`/`decompress`, `encrypt`/`decrypt`, `parse`/`format`, `push`/`pop`, `insert`/`remove`, `open`/`close`, `marshal`/`unmarshal`, `pack`/`unpack`, `lock`/`unlock`), plus any project-vocabulary `inversePairs` entries (§4.5). Escalator only; the type pattern must hold first.

**Sampling test:** generate 25 `T` values, check `g(f(t)) == t` for all of them. Seed is derived from suggestion identity (§16 #6).

**Counter-signals:** non-Equatable `T` (-∞ veto, see Appendix B.1); both functions throw with potentially asymmetric domains (warning surfaced in explainability, see Appendix B.4); type-flow detection of non-deterministic API calls in either body (-∞ veto).

**Known caveats** (always rendered in the "why this might be wrong" block): *throws on either side narrows the property's domain to the success set of the inner function; a generator that produces values outside that set will surface false-positive failures.*

**Emitted property:**

```swift
// Template: round-trip
// Confidence: Strong (score 95)
// Signals: type symmetry T↔U (+30), curated name pair encode/decode (+40),
//          sampling 25/25 passed under derived generator (+10),
//          .high generator confidence (.derived(.memberwise))
// Evidence: encode(_:) -> Data (MyType.swift:14), decode(_:) -> MyType (MyType.swift:22)
// Seed: 0x9F2C8B14 (derived from suggestion identity hash)
@Test func roundTripEncoding() async throws {
    await propertyCheck(input: Gen.derived(MyType.self)) { value in
        #expect(try decode(encode(value)) == value)
    }
}
```

#### Idempotence

**Type pattern:** A function `f: T → T` with `T: Equatable`. *Necessary.*

**Name signals:** `normalize`, `canonicalize`, `trim`, `flatten`, `sort`, `deduplicate`, `sanitize`, `format`, plus any project-vocabulary `idempotenceVerbs` entries (§4.5). Escalator only.

**Sampling test:** generate 25 `T` values, check `f(f(t)) == f(t)` for all of them. Seed is derived from suggestion identity (§16 #6).

**Counter-signals:** non-Equatable output (-∞); type-flow detection of non-deterministic API calls in body — `Date()`, `Date.now`, `UUID()`, `Random.next()`, `URLSession`, etc. — is a **structural disqualifier** (-∞ veto, see Appendix B.3) since `f(f(x))` cannot equal `f(x)` if `f` reads the clock; partial functions (early-return / guard paths suggesting `T → T` is incomplete) apply -15.

**Known caveats:** *idempotence over an Equatable-by-value type may still differ under reference equality if `T` is a class with custom `==`; the property is over value equality as `T.==` defines it.*

**Emitted property:**

```swift
// Template: idempotence
// Confidence: Strong (score 80)
// Signals: type T→T (+30), name signal "normalize" (+40),
//          sampling 25/25 passed (+10)
// Evidence: normalize(_:) -> String (Sanitizer.swift:7)
// Seed: 0x4A1E55D2 (derived from suggestion identity hash)
@Test func normalizeIsIdempotent() async {
    await propertyCheck(input: Gen.string()) { value in
        let once = normalize(value)
        #expect(normalize(once) == once)
    }
}
```

### 5.3 Type-Flow Analysis

Naming heuristics alone are fragile. TemplateEngine supplements naming with light type-flow analysis over the SwiftSyntax-derived call graph: composition detection (`f(f(x))` → +20 idempotence), inverse-by-usage (`g(f(x))` followed by `== x` assertion → round-trip score directly), reducer/builder usage (+20 associativity), accumulator-with-empty-seed (+20 identity-element).

Type-flow analysis is intentionally light — syntactic pattern matching over the call graph at the SwiftSyntax level, scoped to the analyzed target. Not full call-graph or alias analysis. This keeps it tractable and predictable.

### 5.4 Algebraic-Structure Composition

Multiple per-template signals on the same type → structural claim (semigroup, monoid, group, semilattice, ring) → RefactorBridge suggestion. The RefactorBridge caveat about Numeric vs FloatingPoint (integer-like exact-equality laws vs IEEE-754 rounding) is part of every ring-claim suggestion's explainability "why this might be wrong" block.

| Detected combination | Implies | RefactorBridge target |
|---|---|---|
| binary op `(T, T) → T` + associativity | **Semigroup** | **kit-defined `Semigroup`** (SwiftProtocolLaws v1.8.0+) |
| Semigroup + identity element | **Monoid** | **kit-defined `Monoid`** (v1.8.0+); `AdditiveArithmetic` still suggested as a *secondary* Option B when the `+` / `zero` shape fits |
| Monoid + commutativity | **CommutativeMonoid** | **kit-defined `CommutativeMonoid`** (v1.9.0+) — adds `combineCommutativity` Strict law on top of Monoid |
| Monoid + inverse function | **Group** | **kit-defined `Group`** (v1.9.0+) — adds `static func inverse(_:)` requirement + `combineLeftInverse` / `combineRightInverse` Strict laws |
| CommutativeMonoid + idempotence | **Semilattice** | **kit-defined `Semilattice`** (v1.9.0+) — adds `combineIdempotence` Strict law; stdlib `SetAlgebra` suggested as a *secondary* Option B when curated set-named ops (`union` / `intersect` / `subtract`) fire |
| Two monoids on same type, distributive | **Ring** | suggest stdlib `Numeric` (with caveats — see below) |
| `T → T` + `T → T` inverse + identity | **Group acting on T** | (no kit protocol — informational; function-space carrier doesn't fit the kit's per-type protocol shape) |

The writeout path (`Tests/Generated/SwiftInferRefactors/<TypeName>/<ProtocolName>.swift`) emits aliasing extensions that bridge the user's existing op / identity names into the kit's required `static func combine(_:_:)` / `static var identity` / `static func inverse(_:)`. The user's source compiles end-to-end against `import ProtocolLawKit`; SwiftProtocolLaws' discovery plugin then verifies the laws on every CI run thereafter.

The orchestrator → emitter → InteractiveTriage chain handles each row above end-to-end. The `[A/B/B'/s/n/?]` extended prompt surfaces the Semilattice + SetAlgebra dual when curated set-named ops fire, plus the incomparable-arm split for types that satisfy both CommutativeMonoid AND Group simultaneously (mathematically a CommutativeGroup; v1.9.0 doesn't ship a kit `CommutativeGroup`, so the orchestrator emits both as peer proposals). Ring detection consumes a per-(type, op-set) signal accumulator + curated additive (`+` / `add` / `plus` / `sum`) and multiplicative (`*` / `multiply` / `times` / `mul` / `product`) naming lists; the writeout targets stdlib `Numeric` with a strong §4.5 caveat covering the FloatingPoint / IEEE-754 trap.

### 5.5 Cross-Function Pairing Strategy

Tiered filtering: type filter → naming filter → scope filter → optional `@Discoverable(group:)`. In practice, a module of 50 functions typically produces fewer than 10 candidate pairs after type filtering.

### 5.6 Contradiction Detection

When a function accumulates signals for multiple templates whose properties are mutually exclusive (e.g. idempotence + involution; commutativity + anti-commutativity naming), contradictions surface in the explainability block as both an active counter-signal and a "this combination has known traps" warning. The current contradiction table covers idempotence+involution, commutativity+anti-commutativity, monotonicity+strict-monotonicity, and identity-element with conflicting witnesses.

### 5.7 Annotation API

Reuses the **`@Discoverable(group:)` attribute syntax** from `ProtoLawMacro`. SwiftInferProperties' scanner recognizes the attribute by name match during the SwiftSyntax walk — *no runtime dependency* on `ProtoLawMacro` is required at scan time, so users opting into `@Discoverable` solely for SwiftInfer scoping don't pay a forced second `import`. Users wanting compile-time validation of the attribute (the kit's macro-expansion guarantee) import `ProtoLawMacro` themselves.

Introduces `@CheckProperty(.idempotent)` / `@CheckProperty(.roundTrip, pairedWith:)` / `@CheckProperty(.preservesInvariant(\.keyPath))` for direct stub generation. Implemented as a SwiftSyntax peer macro that expands the tagged function decl into an `@Test func` peer in the user's source — not into `Tests/Generated/SwiftInfer/`. The latter is the `--interactive` writeout path (§3.6 step 3); `@CheckProperty` is the per-declaration opt-in path. Both paths consume the sampling seed (§16 #6) and the `GeneratorSelection` strategy.

### 5.8 Milestones

| Milestone | Deliverable | Status |
|-----------|-------------|--------|
| **M1** | SwiftSyntax pipeline; CLI discovery tool (`swift-infer discover`); round-trip + idempotence templates wired through the §4 scoring engine and §4.5 explainability block; basic cross-function pairing (type + naming filter); `// swiftinfer: skip` rejection markers honored; performance budget hit on the §13 reference corpora (`swift-collections`, `swift-algorithms`). | **Shipped** |
| **M2** | Commutativity, associativity, identity-element templates; project configuration (`.swiftinfer/config.toml`); pluggable naming vocabulary (§4.5) loaded from `.swiftinfer/vocabulary.json`. | **Shipped** |
| **M3** | Contradiction detection (§5.6); cross-validation with TestLifter (+20 signal per §4.1) once TestLifter M1 lands. Prerequisite: `DerivationStrategist` exposed publicly from SwiftProtocolLaws. | **Shipped** |
| **M4** | Scoring model surfaced fully in output (per-signal weights in the explainability block); sampling-before-suggesting (§4.3) using the seeded policy of §16 #6. | **Shipped** |
| **M5** | `@CheckProperty` and `@Discoverable` annotation API (§5.7); `--dry-run` / `--stats-only` modes. | **Shipped** |
| **M6** | Workflow operationalization. `swift-infer discover --interactive` triage mode (§8) walking suggestions with `[A/B/s/n/?]` prompts; the §3.6 step 3 writeout — accepted suggestions emit property-test stubs to `Tests/Generated/SwiftInfer/`; `swift-infer drift` mode (§9) with `.swiftinfer/baseline.json` baseline + non-fatal drift warnings; `.swiftinfer/decisions.json` infrastructure (read + write + schema). | **Shipped** |
| **M7** | Monotonicity (`Possible` by default — escalation only via TestLifter corroboration or explicit annotation per §5.2 caveat); invariant-preservation (annotation-only); RefactorBridge upstream-loop conformance suggestions written to `Tests/Generated/SwiftInferRefactors/` (§6, §16 #1). | **Shipped** |
| **M8** | Algebraic-structure composition (§5.4) — semigroup / monoid / group / semilattice / ring claims accumulated from per-template signals on the same type; expanded identity-element detection (init-based + reduce-usage signals); `inverse-pair` template ships standalone for non-Equatable cases (suppressed per §16 #6 explainability). | **Shipped** |

The §4.5 explainability block ("why suggested" + "why this might be wrong") is a **cross-cutting per-template deliverable** — every template added in any milestone ships its block populated from the matched counter-signals plus the template's known caveats. There is no separate "explainability milestone."

### 5.9 Capability ↔ Milestone Cross-Reference

Single-source ownership for every CLI subcommand, generated-files path, `.swiftinfer/` artifact, and annotation.

**CLI subcommands.**

| Subcommand | Owner | Status |
|---|---|---|
| `swift-infer discover --target <name>` | TemplateEngine M1 | Shipped |
| `swift-infer discover --include-possible` | TemplateEngine M1 | Shipped |
| `swift-infer discover --vocabulary <path>` | TemplateEngine M2.1 | Shipped |
| `swift-infer discover --config <path>` | TemplateEngine M2.2 | Shipped |
| `swift-infer discover --stats-only` | TemplateEngine M5 | Shipped |
| `swift-infer discover --dry-run` | TemplateEngine M5 | Shipped |
| `swift-infer discover --interactive` | TemplateEngine M6 | Shipped |
| `swift-infer discover --test-dir <path>` | TestLifter M6.0 | Shipped |
| `swift-infer drift --baseline <path>` | TemplateEngine M6 | Shipped |
| `swift-infer convert-counterexample` | TestLifter M8 | Shipped |
| `swift-infer discover --show-suppressed` | v1.1+ | Deferred |
| `swift-infer discover --seed-override <hex>` | v1.1+ | Deferred |
| `swift-infer metrics` | v1.1+ (§17) | Deferred |
| `swift-infer apply --suggestion <hash>` | v1.1+ (§20.6) | Deferred |

**Generated-files paths (PRD §16 #1 hard guarantee).**

| Path | Owner | Status |
|---|---|---|
| `Tests/Generated/SwiftInfer/` | TemplateEngine M6 (`--interactive` accept) + TestLifter M3+ | **Shipped** |
| `Tests/Generated/SwiftInferRefactors/` | TemplateEngine M7 | **Shipped** |
| `Tests/Generated/SwiftInferGenerators/` | v1.1+ | Reserved path, no v1 owner |

**`.swiftinfer/` artifacts.**

| File | Owner (read) | Owner (write) |
|---|---|---|
| `.swiftinfer/vocabulary.json` | TemplateEngine M2.1 | User-authored |
| `.swiftinfer/config.toml` | TemplateEngine M2.2 | User-authored |
| `.swiftinfer/decisions.json` | TemplateEngine M6 | TemplateEngine M6 (`--interactive` writes; `drift` reads); TestLifter M6 honors lifted-suggestion identities |
| `.swiftinfer/baseline.json` | TemplateEngine M6 | TemplateEngine M6 (`drift --baseline-update`) |
| `// swiftinfer: skip <hash>` source markers | TemplateEngine M1.5 | User-authored; TestLifter M6.1 honors them on the test side |

**Annotation API (§5.7).**

| Attribute | Owner (definition) | Owner (consumption) |
|---|---|---|
| `@Discoverable(group:)` | SwiftProtocolLaws (`ProtoLawMacro`) | TemplateEngine M5 — recognizes by name match, no runtime dep |
| `@CheckProperty(.idempotent)` | TemplateEngine M5 | M5 peer-macro expansion at user compile time |
| `@CheckProperty(.roundTrip, pairedWith:)` | TemplateEngine M5 | M5 peer-macro expansion |
| `@CheckProperty(.preservesInvariant(\.keyPath))` | TemplateEngine M7.2 | M7.2 peer-macro expansion |

-----

## 6. Contribution 3: RefactorBridge

The bridge: TemplateEngine accumulates strong evidence for a monoid/ring/semilattice → RefactorBridge proposes both a one-off property test (Option A) and a protocol conformance (Option B) that SwiftProtocolLaws then verifies on every CI run. Both options are presented; the developer chooses; the choice is logged to `.swiftinfer/decisions.json`. RefactorBridge writes conformance stubs only to `Tests/Generated/SwiftInferRefactors/`, never to existing source files (see §16 Hard Guarantees).

When two structures fire on the same type and one strictly subsumes the other (Monoid + Semilattice → Semilattice wins; Semigroup + Monoid → Monoid wins), the orchestrator emits the strongest-only Option B. When two structures are incomparable (CommutativeMonoid + Group on the same type — mathematically a CommutativeGroup but no kit `CommutativeGroup` ships in v1.9.0), both proposals emit as peer Option B's via the `[A/B/B'/s/n/?]` extended prompt. When a curated secondary fires alongside a kit primary (Semilattice + curated set-named `union`/`intersect`/`subtract` ops → SetAlgebra; Monoid + `+`/`zero` shape → AdditiveArithmetic), both are surfaced.

-----

## 7. Contribution 2: TestLifter

### 7.1 Description

TestLifter analyzes existing XCTest and Swift Testing test bodies, slices each test method into setup + property regions, runs a fan-out of seven detectors over the property region, and surfaces matching shapes as **lifted suggestions** that flow through the same scoring engine + accept-flow as TemplateEngine-side suggestions. When a TestLifter-side detection matches a TemplateEngine-side production function, the matching TE suggestion gets the +20 cross-validation signal (§4.1); when no production match exists, the lifted suggestion enters the visible stream as a freestanding Likely-tier candidate.

### 7.2 Slicing Phase

The slicing pass anchors on the terminal assertion (`XCTAssert*` / `#expect` / `#require`), backward-slices to collect contributing statements (binding chains + intermediate let/var), classifies the remainder as setup, and identifies parameterized values (literals and vars initialized to literals). The pass is contract-bound to never throw — fuzzed against a 100-AST corpus of randomly-generated test bodies as a §15 invariant.

### 7.3 Pattern Recognition

Seven detectors run over the sliced property region:

- **Round-trip** (`AssertAfterTransformDetector`): `decode(encode(x)) == x` collapsed and explicit two-binding shapes.
- **Idempotence** (`AssertAfterDoubleApplyDetector`): `f(f(x)) == f(x)` collapsed and explicit two-binding shapes; single-callee invariant rejects different-callee compositions.
- **Commutativity** (`AssertSymmetryDetector`): `f(a, b) == f(b, a)` for free / static + instance-method shapes; tautology / no-reversal / three-arg shapes rejected.
- **Monotonicity** (`AssertOrderingPreservedDetector`): `XCTAssertLessThan(a, b); XCTAssertLessThanOrEqual(f(a), f(b))` two-assert + Swift Testing two-`#expect` form; strict-result `<` variant detected.
- **Count-invariance** (`AssertCountChangeDetector`): `XCTAssertEqual(f(xs).count, xs.count)` collapsed + explicit two-binding; keyPath hard-coded to `\.count`; tautology / different-keyPath / both-sides-functions shapes rejected.
- **Reduce-equivalence** (`AssertReduceEquivalenceDetector`): `XCTAssertEqual(xs.reduce(0, +), xs.reversed().reduce(0, +))` collapsed + explicit two-binding; method-chain only; same-collection + same-seed + same-op invariants enforced.
- **Asymmetric assertion** (`AsymmetricAssertionDetector`, counter-signal): negative-form mirrors of the six positive patterns above (`XCTAssertNotEqual(...)`, `XCTAssertGreaterThan(...)`, etc.). Each match contributes the -25 counter-signal to the matching TE-side suggestion (§4.1) and filters the matching lifted suggestion entirely from the visible stream — the user's explicit negative assertion is dispositive on the lifted side.

### 7.4 Generator Inference (Mock-Based Synthesis)

Tiered fallback for generator inference, ordered most-trusted first:

1. **`DerivationStrategist`** (memberwise / `CaseIterable` / `RawRepresentable`) — delegated to SwiftProtocolLaws' shared strategist. Highest confidence.
2. **Codable round-trip** (`Gen<T> { JSONEncoder/JSONDecoder ... }`) — fires when the type conforms to `Codable` or `Encodable + Decodable`. Medium confidence; emits a fixture-placeholder TODO that the user replaces.
3. **Mock-inferred from observed test construction** — the §13 calibrated rule: when ≥3 test sites construct the type with the same dominant argument shape, synthesize a `Gen<T> { _ in T(label: <Gen<...>>.run(), ...) }` stub from the kit's `RawType.generatorExpression` factories. Low confidence; surfaced with a "Mock-inferred from N construction sites in test bodies — low confidence (verify the generator covers your domain)" provenance line. Multi-shape ambiguity → no synthesis. Constructor sites with non-literal arguments are skipped at the scanner level; a curated non-determinism patterns list (`Date()`, `UUID()`, `arc4random()`, etc.) belt-and-suspenders the rejection at synthesis time.
4. **`.todo` placeholder** — when no other strategy applies, the stub emits `?.gen()` which doesn't compile. The user supplies the generator. Forces conscious adoption rather than silently-wrong code (PRD §16 #4).

Generator confidence (`high` / `medium` / `low`) flows into the explainability block.

### 7.5 Persistence and Suggestion Identity

Stable hash on `(template ID, function signature canonical form, AST shape of property region)`. Decisions live in `.swiftinfer/decisions.json` keyed by hash. `// swiftinfer: skip [hash]` markers in source survive regeneration.

TestLifter's lifted suggestions use a separate identity namespace `lifted|<template>|<sortedCalleeNames>` so they don't collide with TE-side identities. The persistence layer uniformly handles both via `existingDecisions.record(for: identity.normalized)`.

### 7.6 Existing-Tests Relationship and Confidence

When a lifted suggestion's `CrossValidationKey` matches a TemplateEngine-side suggestion, the TE-side suggestion receives the +20 cross-validation signal (§4.1) and the lifted suggestion is suppressed from the visible stream. This avoids double-counting while preserving the TE-side suggestion's existing evidence trail. Un-suppressed lifted suggestions enter the visible stream as Likely-tier freestanding candidates, with the lifted-from-test provenance line above the M3.3 "Lifted from `<file>:<line>` `<testMethodName>()`" line.

### 7.7 Confidence and Explainability for Lifted Suggestions

Lifted suggestions ship the same §4.5 two-sided explainability block as TE-side suggestions. The "why suggested" block always includes the lifted-from-test provenance + the +50 `.testBodyPattern` signal; the "why this might be wrong" block includes the template's known caveats + any caveat surfaced by the §3.5 conservative-bias suppression rules (mock-inferred low confidence, `.todo` generator, non-deterministic body proximity).

### 7.8 Expanded Outputs

Tests encode *intent*, not just example values. v1 ships **inferred preconditions**, the first of three §7.8 expanded-output examples; the other two (inferred domains, equivalence-class detection) are deferred to v1.1+ M10/M11 per the M9 plan's scope-narrowing decision.

**Inferred preconditions (shipped as TestLifter M9).** When the M4 mock-inferred synthesizer fires on a type, the M9 `PreconditionInferrer` examines each argument position's observed-literal column and surfaces curated patterns as advisory `// Inferred precondition:` comment lines inside the generated `Gen<T>` body:

- **Numerical bounds** (Int only — `Float`/`Double` deferred for precision-class concerns): `positiveInt` / `nonNegativeInt` / `negativeInt` / `intRange(low, high)`.
- **String shape**: `nonEmptyString` / `stringLength(low, high)`.
- **Boolean monomorphism**: `constantBool(value)` — observed only `true` (or only `false`) across N sites.

The pattern set is curated and conservative: most-specific wins (`intRange` ≥ 2 distinct values preempts the sign-bound patterns; `stringLength` ≥ 2 distinct lengths preempts `nonEmptyString`); one outlier kills the column; the same ≥ 3 site threshold as mock-synthesis applies; multi-line / raw / backslash-escape strings kill the column to avoid mis-counting on escaped content.

The hint surface is **advisory only** — no score or tier change. A user accepting a mock-inferred generator with hints sees, e.g.:

```swift
zip(
    // Inferred precondition: count — all observed values are in [1, 5] across 5 sites — consider Gen.int(in: 1...5)
    Gen<Int>.int(),
    // Inferred precondition: title — all observed strings have length in [5, 7] across 5 sites — consider Gen.string(of: 5...7)
    Gen<String>.string()
).map { Doc(count: $0.0, title: $0.1) }
```

**Inferred domains (deferred to v1.1+ M10).** When tests for `decode` only pass strings produced by `encode`, TestLifter could infer that `decode`'s domain is "encoder output" rather than "all `String`". Suggestion: "round-trip property over `Gen<MyType>.map(encode)` rather than `Gen.string()` — `decode` was never observed against arbitrary strings, only encoder output." Requires cross-call data-flow tracing infrastructure the v1 surface doesn't have.

**Equivalence-class detection (deferred to v1.1+ M11).** Tests that group inputs into "valid" / "invalid" buckets via parallel construction patterns hint at equivalence classes worth parameterizing the property over. Requires test-method-name partition heuristics that go beyond the M1–M9 detector model.

### 7.9 Milestones

| Milestone | Deliverable | Status |
|---|---|---|
| **M1** | SwiftSyntax test body parser, slicing phase, assert-after-transform detection, round-trip suggestion. | **Shipped** |
| **M2** | Double-apply (idempotence) and symmetry (commutativity) detection. | **Shipped** |
| **M3** | Generator inference: stdlib derivation strategies + `.todo` stub pattern; consume shared `DerivationStrategist`. Lifted suggestions enter the visible stream + write to `Tests/Generated/SwiftInfer/` on accept. | **Shipped** |
| **M4** | Mock-based generator synthesis from observed test construction. | **Shipped** |
| **M5** | Ordering, count-change, reduce-equivalence pattern detection (six-detector fan-out); Codable round-trip generator rung. | **Shipped** |
| **M6** | `--test-dir` CLI override + walk-up default; `// swiftinfer: skip` honoring on the test side; decisions.json regression coverage for lifted suggestions. | **Shipped** |
| **M7** | Counter-signal scanning (asymmetric assertion detector, seventh detector); non-determinism suppression in mock-inference. | **Shipped** |
| **M8** | `swift-infer convert-counterexample` subcommand: deterministic single-trial regression test stubs for all 10 templates from a counterexample literal. | **Shipped** |
| **M9** | Expanded outputs — inferred preconditions only (the §7.8 first example). Inferred domains + equivalence-classes deferred to v1.1+ M10/M11. | **Shipped** |
| M10 (v1.1+) | Inferred domains — cross-call data-flow tracing for "decode only sees encode output"-style domain narrowing. | **Deferred** |
| M11 (v1.1+) | Equivalence-class detection — test-method-name partition heuristics for valid/invalid buckets. | **Deferred** |

-----

## 8. Interactive Triage Mode

`swift-infer discover --interactive` walks suggestions one at a time with `[A/B/B'/s/n/?]` prompts:

- **A** — accept Option A (one-off property test); writes a stub to `Tests/Generated/SwiftInfer/`.
- **B** — accept Option B (protocol conformance, when surfaced by RefactorBridge); writes a conformance stub to `Tests/Generated/SwiftInferRefactors/`.
- **B'** — accept the secondary Option B (e.g. SetAlgebra alongside Semilattice; AdditiveArithmetic alongside Monoid; the second incomparable arm when CommutativeMonoid + Group both apply).
- **s** — skip (record as deferred; surfaces again on the next discover run).
- **n** — reject (record permanently; suppressed on subsequent runs unless the source AST shape changes).
- **?** — show full evidence + explainability block.

Decisions logged to `.swiftinfer/decisions.json`.

-----

## 9. CI Drift Mode

`swift-infer drift --baseline .swiftinfer/baseline.json` emits a non-fatal warning per new Strong-tier suggestion lacking a recorded decision after the baseline date. GitHub Actions annotation surface in PR review UI. Drift never fails the build (PRD §16 #3) — it surfaces signal for the developer to act on.

-----

## 10. Architecture Overview

| Concern | Owner | Notes |
|---|---|---|
| Conformance detection | SwiftProtocolLaws (`ProtoLawMacro` discovery plugin) | SwiftInfer never re-implements |
| Protocol-law verification | SwiftProtocolLaws (`ProtocolLawKit`) | All test execution goes through `PropertyBackend` |
| Memberwise generator derivation | SwiftProtocolLaws (`DerivationStrategist`) | **Shared** between `ProtoLawMacro` and SwiftInfer; exposed publicly from `ProtoLawCore` |
| Test execution | SwiftProtocolLaws (`PropertyBackend`) | Single backend (`swift-property-based`); abstraction stays public |
| Signature-based property inference | SwiftInfer (`TemplateEngine`) | Includes type-flow analysis |
| Algebraic-structure composition | SwiftInfer (`TemplateEngine` §5.4) | Drives RefactorBridge |
| Conformance suggestions back to SwiftProtocolLaws | SwiftInfer (`RefactorBridge`) | Writes only to `Tests/Generated/SwiftInferRefactors/` |
| Test-body inference | SwiftInfer (`TestLifter`) | Includes slicing, mock-based generator synthesis, inferred preconditions |
| CLI / triage / drift / decisions persistence | SwiftInfer (CLI surface) | `.swiftinfer/` directory is SwiftInfer-owned |
| Naming vocabulary | SwiftInfer (`.swiftinfer/vocabulary.json`) | Project-extensible per §4.5 |

A type rule of thumb for contributors: **contractual** properties live in SwiftProtocolLaws (you said you conform to X, X has laws, the kit verifies them). **Structural and behavioral** properties live in SwiftInfer (the code looks like X, the tests behave like X, both are probabilistic claims).

-----

## 11. Relationship to SwiftProtocolLaws

Bidirectional via RefactorBridge: SwiftInfer detects algebraic structure → suggests protocol conformance → SwiftProtocolLaws' discovery plugin emits the law-check on the next regeneration → laws are enforced on every CI run thereafter.

The shared `DerivationStrategist` enum lives in `ProtoLawCore` at `public` visibility — the prerequisite promotion shipped on the SwiftProtocolLaws side and SwiftInfer M3 consumes it.

The overlap with SwiftProtocolLaws' own round-trip advisory is intentional — different confidence regimes (HIGH-confidence syntactic in SwiftProtocolLaws, weighted full-spectrum in SwiftInfer). When both fire on the same pair, SwiftInfer adds +20 for cross-validation.

Single-backend by design: `swift-property-based` only.

`Package.swift` references SwiftProtocolLaws via a versioned URL dep (`from: "1.9.0"`). The dep tracked v1.8.0 from the M7.4 ship (when the kit's Semigroup + Monoid landed) until M8.0 shipped v1.9.0's second kit-defined cluster (CommutativeMonoid + Group + Semilattice). Out of v1.9.0 scope and deferred to a future kit minor: kit-side `Ring` (two-op shape — Numeric stays the canonical Ring writeout target per §5.4); kit-side `CommutativeGroup` (rare in idiomatic Swift; M8's incomparable-arm split emits separate CommutativeMonoid + Group proposals when both apply); kit-side `Group acting on T` (function-space carrier doesn't fit the per-type protocol shape).

-----

## 12. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Template matching produces too many false positives | High | Weighted scoring engine with counter-signals; `Possible` tier hidden by default; pluggable naming vocabularies (§4.5) reduce naming-driven false positives |
| Naming heuristics fail in legacy / non-English codebases | High | Type-flow analysis (§5.3) + project vocabulary (§4.5) supply signal independent of curated naming; mining naming patterns from the repo is v1.1 |
| Lifted unit test patterns don't generalize | Medium | Slicing phase (§7.2); minimum-2-test threshold; counter-signal scanning across whole test target |
| Generator inference fails for complex types | Medium | Tiered fallback per §7.4; `.todo` stub forces conscious adoption; mock-based synthesis adds a new path |
| Cross-function pairing is noisy | Medium | Type filter + `@Discoverable(group:)` |
| Property contradictions cause user confusion | Low | Contradiction detection table; explainability block surfaces traps |
| Developers ignore generated stubs | Medium | Compile-time enforcement via `.todo`; interactive triage; CI drift mode |
| RefactorBridge pushes user into wrong protocol | Medium | Both Option A (one-off) and Option B (conformance) presented with caveats; Numeric vs FloatingPoint warning explicit on ring claims |
| `.swiftinfer/decisions.json` gets stale | Medium | Stable AST-shape hashing; refactors that don't change signature don't invalidate |
| Suggestion-identity hash collides | Low | Hash includes canonical signature + AST shape + template ID |
| Performance regression as templates grow | Medium | Hard performance budgets in §13 with regression test enforcement |
| Adoption metrics introduce telemetry / privacy concerns | Medium | All metrics local-only; explicit opt-in for any aggregation; see §14 |
| Mock-inferred generator captures non-deterministic API output | Low | Curated non-determinism pattern list (`Date()`, `UUID()`, `arc4random()`, etc.) suppresses synthesis; scanner-level rejection of non-literal arguments belt-and-suspenders the synthesis-time check |
| Inferred precondition hint misleads user into over-narrowing the generator | Low | Hints are advisory comments only — no score/tier change, no generator substitution; the user inspects + decides |

-----

## 13. Performance Expectations

Hard targets for v1, enforced by regression tests in CI:

| Operation | Target | Failure mode |
|---|---|---|
| `swift-infer discover` on 50-file module | < 2 seconds wall | regression test fails; release blocked |
| TestLifter parse of 100 test files | < 3 seconds wall | regression test fails |
| `swift-infer drift` re-run after one-file change | < 500ms (incremental) | regression test fails |
| Memory ceiling on 500-file module | < 600 MB resident (calibrated at the v0.1.0 cut) | regression test fails |
| `swift-infer discover --interactive` first-prompt latency | < 1 second after process start | release blocked |

Numbers are deliberately Swift-realistic (SwiftSyntax parsing dominates), not aspirational. Calibrated against `swift-collections` and `swift-algorithms` as reference corpora.

**v0.1.0 calibration note (row 4).** The original spec set the memory ceiling at "< 200 MB resident" without measurement. The R1.1.b release-prep measurement on the 500-file synthetic corpus that exercises every shipped template found delta ~492 MB; the row was revised to **600 MB** (current measurement + ~25% headroom matching the regression rule below). Post-v0.1.0 perf-tuning candidates are recorded in `docs/perf-baseline-v0.1.md`. The other §13 rows hit their original targets at the v0.1.0 cut.

A **performance regression test suite** runs in CI: the discovery and drift commands are timed against fixed input corpora, results recorded, and a 25% regression in any number fails the build.

-----

## 14. Security and Privacy

SwiftInfer is a local development tool. The following are hard guarantees:

- **No code leaves the developer's machine.** SwiftInfer never network-calls during analysis. `swift-infer discover`, `drift`, `convert-counterexample` are entirely local.
- **No telemetry by default.** No usage data, no error reports, no anonymized statistics — nothing — is sent anywhere unless the user explicitly opts in. There is no "opt out" because there is nothing on by default to opt out of.
- **`.swiftinfer/` directory contents are local-only.** `decisions.json`, `baseline.json`, `vocabulary.json` are repo-checked-in artifacts (the user controls whether to gitignore them). They contain no information beyond what's already in the codebase.
- **Generated stubs include no source telemetry markers.** Lifted property tests reference origin tests by file:line in comments — that's it. No tool-version stamps that would let log scraping correlate users.
- **Future opt-in aggregation, if added, will be repo-local.** The v1.1 Adoption Tracking dashboard (§17) operates on `.swiftinfer/decisions.json` only and does not phone home. If a hosted aggregation service is ever proposed, it requires a separate PRD and explicit opt-in per repo.

This matters for enterprise adoption and for projects with regulated/proprietary code. Stating it in the PRD prevents future contributors from "helpfully" adding any of the above.

-----

## 15. Extensibility Model (Future Work)

v1 ships a curated, closed template registry. Third-party template registration is a frequently-suggested extension but raises confidence-model integrity concerns: ill-tuned third-party templates would degrade the precision-over-recall philosophy from outside the maintainers' control.

The v1.1+ direction (§20) is to add a plugin API with the following declared shape per template:

- `name: String` — unique identifier
- `signaturePattern: SignaturePattern` — required type shape
- `confidenceContributors: [SignalContribution]` — bounded weights (0–50 positive, 0–30 negative); third-party templates cannot use the `-∞` veto
- `emittedTestBody: SwiftSyntax` — golden-file-tested
- `contradictionRules: [ContradictionRule]` — interactions with built-in templates
- `knownCaveats: [String]` — populates the "why this might be wrong" block

Registry ordering would be confidence-driven, not insertion-order. Built-in templates always run first. This is sketched only — no v1 commitment.

-----

## 16. Failure Modes and Hard Guarantees

SwiftInfer ships with the following hard guarantees, enforced by code review and integration tests:

1. **SwiftInfer never modifies existing source files.** Generated content goes only to:
   - `Tests/Generated/SwiftInfer/` — TemplateEngine M6 (`--interactive` accept) writes property-test stubs here; TestLifter M3+ writes lifted-from-existing-tests properties here.
   - `Tests/Generated/SwiftInferRefactors/` — RefactorBridge (TemplateEngine M7) writes conformance stubs the developer manually moves.
   - `Tests/Generated/SwiftInferGenerators/` — **v1.1+** reserved path. Currently unowned; intended for the v1.1 generator-emitter writeout when `swift-infer apply` (§20.6) lands and emits standalone `Gen<T>` files separately from their consuming test files.

   Never auto-edits existing source; the M5 `@CheckProperty` macro emits peer declarations at the user's compile time (the user wrote the attribute), which is *not* a SwiftInfer-side write.
2. **SwiftInfer never deletes tests.** TestLifter reads existing tests; it never overwrites them. Lifted properties are emitted as new files, never replacements.
3. **SwiftInfer never auto-accepts suggestions.** Even in CI mode, `drift` emits warnings, not failures. The accept/reject step is always human.
4. **SwiftInfer never emits silently-wrong code.** When generator inference fails, the stub is emitted with `.todo`, which does not compile. There is no "approximately correct" generator fallback. Inferred-precondition hints (§7.8) surface as advisory comments only — they never substitute the generator under the user's feet.
5. **SwiftInfer never operates outside the configured target.** `--target` is required for `discover`; the tool refuses to scan files outside the named target's source roots. The walk-up resolver for `--test-dir` (TestLifter M6.0) walks parent dirs from the production target looking for `Package.swift` then returns `<root>/Tests/` if present — a missing test directory warn-and-degrades, never silently widens scope.
6. **SwiftInfer's output is reproducible.** Re-running `discover` on unchanged source produces byte-identical output (modulo the timestamp recorded in decisions.json on accept). Same property as SwiftProtocolLaws' discovery plugin. **Seed policy:** all sampling that contributes to a suggestion's score (§4.1 sampling-pass row, §4.3 `samplingResult`) uses a deterministic seed derived from the suggestion-identity hash (§7.5) — concretely, **all 256 bits of `SHA256(suggestionIdentityHash || "sampling")` packed as four big-endian `UInt64`s for the Xoshiro256\*\* state**. The seed is rendered in the explainability block of every emitted stub so a developer can re-run sampling under the same conditions. **`--seed-override` is v1.1+** (not in any v1 milestone); when shipped, it'll be supported for debugging only and never persisted to `decisions.json`. **`--show-suppressed` is also v1.1+**.

These guarantees are tested by the integration suite (§18). Violation is a release-blocking bug.

-----

## 17. Adoption Tracking and Metrics (v1.1+)

This section is **scoped to v1.1+** — the §14 sentence about "the v1.1 Adoption Tracking dashboard" pins the timing. The v1 surface ships `.swiftinfer/decisions.json` (TemplateEngine M6) so the data underlying §17 metrics accumulates from v1; the metrics command + dashboard read that data in v1.1+.

### 17.1 Tracked Metrics

Every accept / reject / skip / "note as wrong" decision in `.swiftinfer/decisions.json` records:

- Suggestion-identity hash
- Tier and score at decision time
- Template ID
- Signal weights that contributed
- Decision (accept-A / accept-B / accept-B' / skip / wrong)
- Timestamp
- (When the suggestion is accepted) whether the resulting test passes on first commit

### 17.2 Derived Metrics

`swift-infer metrics` (v1.1+) aggregates locally:

| Metric | Definition | Why it matters |
|---|---|---|
| Acceptance rate | accepts / (accepts + rejects + wrongs) per template | Templates with < 50% acceptance after 20 suggestions are candidates for retirement or weight tuning |
| False-positive rate | "wrong" decisions / total surfaced | Tracks the precision side of the philosophy directly |
| Suppression rate | skips / total surfaced | High suppression suggests noise; low suppression suggests the tool is missing things |
| Time-to-adoption | timestamp(accept) - timestamp(suggestion first surfaced) | Tracks UX friction; long times suggest the suggestion is unclear |
| Post-acceptance failure rate | accepted suggestions whose test fails on commit / total accepted | Catches "developer accepts, test was wrong" |

### 17.3 Calibration Loop

Once v1.1 ships, weights and thresholds are tuned **empirically**, not by guess. The calibration loop:

1. Aggregate decisions from a corpus of opt-in projects (collected manually, not via telemetry — see §14).
2. Run weight-perturbation analysis: which signal weights, if changed by ±10, would have improved the precision/recall trade-off without the false-positive rate spiking?
3. Propose weight updates in a follow-up PRD revision; ship in a minor SwiftInfer release.
4. Re-measure on the next release cycle.

This is the operationalization of "high precision, low recall." Without it, the philosophy is just a slogan. With it, the scoring engine improves as adoption grows.

-----

## 18. Test Coverage Requirements

SwiftInfer is a static analysis tool — its own test coverage standards must be high enough to catch regressions in the inference itself.

| Component | Coverage standard |
|---|---|
| TemplateEngine signal scoring | Per-signal unit tests for every weight in §4.1; integration tests for every template in §5.2 |
| TemplateEngine emitted bodies | **Golden-file tests** — each template's emitted SwiftSyntax stub is checked byte-for-byte against a committed expected-output file; regenerating goldens requires explicit `--update-goldens` flag |
| TestLifter slicing phase | Property-based fuzz tests against a generator of test-method ASTs — slicing must always produce a valid (possibly empty) property region without throwing |
| TestLifter detector fan-out | All seven detectors (six positive + asymmetric-assertion counter-signal) drive against the same 100-AST seeded fuzz corpus; non-throwing contract enforced per detector |
| Generator inference | Per-strategy unit tests for every row in §7.4's table; integration tests against `swift-collections` as a real-world corpus |
| Mock-synthesis coverage | The §13 ≥3-site dominant-shape rule covers ≥ 50% of test-corpus types in the calibrated 6-above-threshold + 4-under-threshold synthetic fixture |
| Inferred preconditions | Per-pattern unit tests for every case in `PreconditionPattern`; end-to-end integration tests for the `// Inferred precondition:` provenance comment lines in real fixture writeouts |
| RefactorBridge | Per-structure unit tests verifying the suggested conformance compiles when the type is structurally compatible, and is correctly suppressed when it isn't |
| CLI surface | Integration tests for every `swift-infer` subcommand against a fixture project; output-format tests that verify the explainability block renders correctly |
| Performance regression | The §13 timing tests run on every CI build |

Golden-file tests are particularly important for the explainability block (§4.5) because any change to the rendered "why suggested / why might be wrong" formatting needs to be a deliberate, reviewed change rather than an accidental side effect of refactoring.

-----

## 19. Success Criteria

### TemplateEngine + RefactorBridge

- Running discovery on a real-world Swift module of 50+ functions produces fewer than 10 Strong-tier suggestions, of which at least 80% are judged useful by a Swift developer unfamiliar with the tool.
- Round-trip, idempotence, and commutativity templates correctly identify known patterns in at least 3 open-source Swift packages used as benchmarks (one of which should be a sufficiently algebraic library).
- Algebraic-structure composition (§5.4) correctly identifies at least 2 monoid candidates and 1 semilattice candidate in the chosen benchmarks.
- For at least one benchmark, the RefactorBridge suggestion (option B) results in a successful protocol conformance addition that SwiftProtocolLaws then verifies on subsequent runs, end-to-end. **This is the loop-closure check.**
- Counter-signals correctly veto at least one false-positive that a naïve matcher would have surfaced, in each benchmark.
- Contradiction detection catches idempotent+involutive and at least 2 other contradictory combinations.
- Acceptance rate (per §17.2) ≥ 70% on the benchmark corpora after 6 months of dogfooding. Below that, the philosophy hasn't held.

### TestLifter

- Running on a test suite of 50+ XCTest methods correctly identifies at least 5 liftable patterns with Strong or Likely score after slicing.
- The slicing phase correctly separates setup from property body in at least 90% of tests with non-trivial setup (≥3 setup statements before the assertion).
- At least 90% of emitted stubs compile after the developer resolves `.todo` generators.
- Mock-based generator synthesis produces a valid `Gen<T>` for at least 50% of the types where ≥3 test sites construct via the same initializer.
- Inferred preconditions (§7.8) surface advisory hints on the `Gen<T>` body whenever the observed-literal column matches a curated pattern across ≥ 3 sites, with one outlier killing the column.
- No existing unit test is modified or deleted under any circumstances. (Hard guarantee per §16.)

### Performance and Privacy

- All §13 performance budgets are met against `swift-collections` and `swift-algorithms` as reference corpora at v1 release.
- All §14 privacy guarantees are testable: integration test verifies no network sockets opened during any subcommand.

### Confidence Model

- Threshold tuning against the benchmark corpora produces tier boundaries within 10 points of the v1 starting values (75 / 40 / 20). If real-world calibration pushes them further, that's a finding to document in a follow-up PRD revision.

-----

## 20. Future Directions (v1.1+)

These are explicitly out of v1 scope. Listed here so the v1 architecture leaves the door open and so contributors know the trajectory.

### 20.1 Contribution 4: SemanticIndex (v1.1)

A **persistent, queryable graph of inferred properties and relationships across runs**. This becomes a "semantic lens over a Swift codebase that reveals latent algebraic structure" — useful for:

- API design feedback ("you have three monoids; consider unifying them under a custom Monoid protocol")
- Refactoring suggestions ("this function would slot into the existing semigroup chain")
- Documentation generation ("inferred properties of this type, exported as DocC")
- Integration with project linting

The v1.1 sketch:

- `swift-infer index --target X` writes `.swiftinfer/index.sqlite` with one row per inferred-and-accepted property
- Schema: `(typeId, templateId, score, evidenceJson, decisionAt, lastSeenAt)`
- `swift-infer query 'monoids in MyApp'` runs human-readable queries
- Index is incremental: only re-analyzes files changed since last index update

The v1 architecture preserves the seam: every accepted suggestion already carries enough metadata to populate an index row, even though v1 doesn't do so persistently.

### 20.2 Constraint Engine Upgrade (v1.1+)

Move from "templates as patterns over signatures" to "constraints over a function graph + types + usage." The constraint-engine model:

- Constraints are first-class objects: `Constraint(targetSignature: P, requiredCallGraphEvidence: E, requiredUsageEvidence: U) -> Score`
- Templates are syntactic sugar over constraints
- New properties are added as constraints, not as bespoke matchers
- Enables higher-order property composition (e.g., "this group has a homomorphism into that semilattice")

The v1 template registry is built so this upgrade can replace the matcher behind the scoring engine without touching the scoring engine itself or any downstream contract. v1 architecture is constraint-engine-ready.

### 20.3 Domain Template Packs (v1.1+)

Split the registry into domain packs:

- `numeric` — distributivity, additive/multiplicative identities, ring laws
- `serialization` — round-trip, encoder-config invariance, version-compatibility
- `collections` — fold/unfold equivalence, permutation invariance, monotonicity over indexing
- `algebraic` — semigroup/monoid/group/lattice/ring (most of v1's algebraic templates)
- `concurrency` — task composition, cancellation idempotence, merge associativity

Users would enable a subset via `--packs numeric,serialization`. This dramatically improves precision on focused codebases.

The v1 registry is monolithic by design — splitting requires benchmark data to know which signals fire too often outside their natural domain. v1.1 design is informed by §17 metrics from the field.

### 20.4 IDE Integration (v1.1+)

Xcode source-editor extension for inline suggestions and quick-fix ("Generate property test") would be a substantial UX improvement. Out of v1 scope because the Xcode extension API is its own engineering project. CLI + interactive mode is v1.

### 20.5 Bridge to Semantic Linting (v1.2+)

SwiftInfer discovers properties; a separate semantic linter could enforce them as project rules ("if the team committed to monoid laws on Config, lint any new function that breaks them"). This requires either a separate SwiftLint integration or a new linting tool; both are out of SwiftInfer's scope but on the strategic trajectory.

### 20.6 In-Source `@ProposedProperty` Marker Annotations (v1.1+)

A passive marker attribute `@ProposedProperty(.idempotent, score: 80, evidence: "encode/decode pair, sampling 25/25")` that a `swift-infer apply --suggestion <hash>` subcommand writes to the relevant declaration, surfacing structured proposals next to the code they describe. **Passive only** — `@ProposedProperty` does not expand at compile time, so SwiftInfer never becomes a runtime dependency of the source target.

**Design decision baked in (not to be re-litigated): truth lives in `.swiftinfer/decisions.json`, not in source markers.** Re-running discovery recomputes proposals from AST + decisions; markers, when added, are decorative UX. Three reasons:

1. **Refactor robustness.** The AST-shape suggestion-identity hash (§7.5) survives renames and signature-preserving refactors. Source markers do not — a renamed function loses its marker even though the proposal still applies.
2. **Disambiguation.** "Marker not yet applied" and "marker explicitly deleted" are distinct states a developer needs to express. Source-of-truth markers cannot express the second without a sidecar — at which point you have a sidecar anyway.
3. **No emission without a consumer.** Emitting markers ahead of an IDE that surfaces them just adds PR noise. The marker and the IDE quick-fix story (§20.4) ship together or not at all.

**Consequence for v1:** §16 #1 stands unchanged — no source modification by any v1 subcommand. The in-source path in v1 is the developer-applied `@CheckProperty(...)` of §5.7, which contributes the +35 `@Discoverable` signal on subsequent discovery runs. The `swift-infer apply` subcommand is v1.1+ ergonomics layered on top of the same decisions.json that already drives v1.

**Three annotation states** (vocabulary for v1.1+ design conversations):

| State | What it is | v1 source? | v1.1 source? |
|-------|-----------|------------|--------------|
| Detected | SwiftInfer's score + evidence record | `.swiftinfer/` only | `.swiftinfer/` only |
| Proposed | `@ProposedProperty(.idempotent, ...)` marker | not emitted | emitted by `swift-infer apply` |
| Adopted | `@CheckProperty(.idempotent)` / `@Idempotent` / `@Discoverable(group:)` | developer-applied | developer-applied (or upgrade subcommand) |

### 20.7 TestLifter M10 — Inferred Domains (v1.1+)

When tests for `decode` only pass strings produced by `encode`, TestLifter could infer that `decode`'s domain is "encoder output" rather than "all `String`". Suggestion: "round-trip property over `Gen<MyType>.map(encode)` rather than `Gen.string()` — `decode` was never observed against arbitrary strings, only encoder output." Requires cross-call data-flow tracing infrastructure the v1 surface doesn't have.

### 20.8 TestLifter M11 — Equivalence-Class Detection (v1.1+)

Tests that group inputs into "valid" / "invalid" buckets via parallel construction patterns hint at equivalence classes worth parameterizing the property over. Requires test-method-name partition heuristics that go beyond the M1–M9 detector model and a concrete detection algorithm that the v1 surface doesn't yet have.

-----

## 21. Open Questions

1. **TemplateEngine as compiler plugin vs. CLI?** CLI for v1 (whole-module scanning + interactive mode). Compiler-plugin mode for incremental per-file suggestions during development is desirable but unscoped — defer to v1.1 with the IDE integration push.
2. **Threshold calibration source.** §17 calibration assumes a corpus of opt-in projects contributing decisions. How is that corpus assembled — public-repo dogfooding only, or invited closed-source pilots? Affects the calibration timeline directly.
3. **Inferred-precondition pattern coverage for floats.** v1 §7.8 ships Int-only numerical bounds; `Float`/`Double` add precision-class concerns (NaN, infinity, IEEE-754 rounding) that complicate detection. v1.1+ extension if real corpora show value.
4. **Cross-validation of inferred preconditions against TemplateEngine annotations.** Currently advisory-only; could in principle become a +signal or counter-signal source on the matching TE-side suggestion. Requires corpus calibration before committing.

-----

## 22. References

- [SwiftProtocolLaws PRD](https://github.com/Joseph-Cursio/SwiftProtocolLaws/blob/main/docs/SwiftProtocolLaws%20PRD.md) — upstream dependency
- [swift-property-based](https://github.com/x-sheep/swift-property-based) — single execution backend
- [SwiftSyntax](https://github.com/apple/swift-syntax)
- [EvoSuite](https://www.evosuite.org)
- [Daikon](https://plse.cs.washington.edu/daikon/)
- [QuickSpec](https://hackage.haskell.org/package/quickspec)
- [Hedgehog state machines](https://hedgehog.qa)

-----

## Appendix A: Negative Examples — What SwiftInfer Must Not Suggest

These are the canonical false positives the scoring engine must reject. Contributors adding new templates should add a corresponding negative example here.

### A.1 Stringly-typed "round-trip" without Equatable

```swift
class CacheEntry { ... } // not Equatable
func store(_ entry: CacheEntry) -> CacheKey
func load(_ key: CacheKey) -> CacheEntry
```

**Naive matcher would suggest:** round-trip property `load(store(x)) == x`.

**What v1 does instead:** suppresses entirely. The `non-Equatable output` counter-signal weights `-∞`. The explainability block on the *suppressed* state (visible only with `--show-suppressed`, v1.1+) reports: "round-trip detected by name + type symmetry, but `CacheEntry` is not Equatable; property is structurally untestable."

### A.2 "Merge" that is not commutative

```swift
extension Array {
    func merge(with other: [Element]) -> [Element] {
        self + other  // ordered concat, NOT commutative
    }
}
```

**Naive matcher would suggest:** commutativity (`merge` keyword + `(T, T) -> T`).

**What v1 does instead:** the `concat`-family naming counter-signal (-30) is in the curated anti-commutativity list. Combined with type-flow detection that observes `merge(a, b) != merge(b, a)` in any test, score lands well below the Strong threshold. Even a Likely surfacing is gated on the user not having `concat` semantics; the explainability block warns: "`merge` on Array+Element is most often ordered concatenation — verify before adopting."

### A.3 Idempotence on a function that calls `Date()`

```swift
func canonicalize(_ session: Session) -> Session {
    var copy = session
    copy.lastNormalized = Date()  // non-deterministic
    return copy
}
```

**Naive matcher would suggest:** idempotence (`canonicalize` keyword + `T -> T`).

**What v1 does instead:** type-flow analysis flags non-deterministic API calls (`Date()`, `Random.next()`, `UUID()`) as immediate disqualifiers for idempotence — `f(f(x))` cannot equal `f(x)` if `f` reads the clock. Suggestion is suppressed; explainability reports: "non-deterministic API call detected on `canonicalize` body; idempotence is structurally impossible." TestLifter M7.1 belt-and-suspenders the same rejection on the mock-synthesis side.

### A.4 Round-trip across throwing functions with asymmetric domains

```swift
func compress(_ data: Data) throws -> Data       // throws on > 1GB
func decompress(_ data: Data) throws -> Data     // throws on malformed
```

**Naive matcher would suggest:** round-trip (`compress`/`decompress` curated pair + `T -> T`).

**What v1 does:** suggests it *but* the explainability "why this might be wrong" block prominently warns: "both functions throw with different conditions; the property holds only over `compress`'s success domain. The emitted stub uses `try`; if `compress` succeeds and `decompress` then fails, the property tests the disjoint domain incorrectly. Consider narrowing the generator to `Gen<Data>.bounded(maxSize: 1.gigabytes)`."

### A.5 Monoid claim on a binary operation with side effects

```swift
class EventBus {
    static let empty = EventBus()
    func merge(_ other: EventBus) -> EventBus {
        // dispatches events as a side effect of merging
        ...
    }
}
```

**Naive matcher would suggest:** Monoid (binary op + identity + class with shared state).

**What v1 does:** the `mutating`/`Void`/IO side-effect penalty (-20) applies. Class kinds disqualify memberwise generator derivation. Score drops below Strong; even if surfaced, RefactorBridge would *not* propose `AdditiveArithmetic` because the structural compatibility check rejects class types. Explainability: "binary operation has observable side effects; monoid claim assumes pure functions."

### A.6 Pattern matching on a single test

```swift
func testTrivialEquality() {
    XCTAssertEqual(reverse(reverse([1, 2, 3])), [1, 2, 3])
}
```

**Naive matcher would suggest:** involution from a single double-apply pattern.

**What v1 does:** the minimum-2-test threshold (configurable to 3 for stricter pipelines) suppresses single-test pattern matches. Score never accumulates the +50 test-body signal because the threshold isn't met. Suggestion never reaches Strong from test evidence alone.

### A.7 Mock-inferred generator captures non-deterministic output

```swift
// In test corpus across ≥ 3 sites:
let event = Event(timestamp: Date(), id: UUID())
```

**Naive matcher would suggest:** synthesize `Gen<Event> { _ in Event(timestamp: Date(), id: UUID()) }` from the observed construction sites.

**What v1 does:** TestLifter M7.1 scans `entry.observedLiterals` for the curated non-determinism patterns (`Date()`, `Date.now`, `UUID()`, `URLSession.shared`, `arc4random()`, `arc4random_uniform(`, `drand48()`, `rand()`, `random()`, `.random()`, `.random(in:`) and rejects synthesis on any match. Without M7.1 the synthesized generator would produce the SAME `Date`/`UUID` value every trial, defeating the purpose of property testing. Belt-and-suspenders against future scanner widening — today's M4.1 scanner already implicitly suppresses function-call args at scan time, M7.1 adds explicit literal-text matching at synthesis time.

