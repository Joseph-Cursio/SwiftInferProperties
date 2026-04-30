# Product Requirements Document

## SwiftInfer: Type-Directed Property Inference for Swift

**Version:** 0.3 Draft
**Status:** Proposal
**Audience:** Open Source Contributors, Swift Ecosystem
**Depends On:** SwiftProtocolLaws (ProtocolLawKit + ProtoLawMacro), v1.5+
**Supersedes:** v0.2 and v0.1 (in git history at commits prior to this version)

> **What changed from v0.2.** v0.3 folds in the ChatGPT and Copilot critiques. Five structural shifts: (1) explicit **Product Philosophy** statement (Copilot) — "high precision, low recall, conservative" — codifies what was implicit; (2) explicit **Developer Workflow** walkthrough (Copilot); (3) **Explainability** is promoted to a first-class concern (ChatGPT) — every suggestion ships both "why suggested" and "why this might be wrong"; (4) new operational sections — **Performance Expectations**, **Security & Privacy**, **Failure Modes & Hard Guarantees**, **Adoption Tracking & Metrics**, **Test Coverage Requirements** — turn the document from vision into a buildable spec (Copilot); (5) the **Semantic Index** (ChatGPT's deferred Contribution 3 from v0.2) is explicitly scoped as a planned **Contribution 4 for v1.1**, with the Constraint Engine, Domain Template Packs, IDE integration, and Semantic Linting bridge listed as the v1.1+ trajectory in a new §20 Future Directions. Two new minor additions: **pluggable naming vocabularies** (ChatGPT) extend the scoring engine; **TestLifter expanded outputs** (preconditions, domains) are scoped as M9. A **Negative Examples appendix** (Copilot) shows what SwiftInfer must *not* suggest. The full delta is in Appendix A.

-----

## 1. Overview

SwiftProtocolLaws addresses the lowest-hanging fruit in automated property testing: if a type declares a protocol, verify that the implementation satisfies the protocol's semantic laws. That project is intentionally scoped to the *explicit* — conformances the developer has already declared.

SwiftInfer addresses what comes next: the *implicit*. Properties that are meaningful and testable, but are not encoded in any protocol declaration. They live in the structure of function signatures, in the relationships between functions, in the algebraic shape of operations, and in the patterns visible in existing unit tests.

This document proposes **SwiftInfer**, a Swift package delivering three v1 contributions and one planned v1.1 contribution:

- **Contribution 1 — TemplateEngine**: A library of named property templates matched against function signatures via SwiftSyntax + light type-flow analysis, emitting candidate property tests for human review. Includes algebraic-structure detectors (semigroup, monoid, group, semilattice, ring) that drive both test generation *and* protocol-conformance refactoring suggestions.
- **Contribution 2 — TestLifter**: A tool that analyzes existing XCTest and Swift Testing unit test suites, slices each test body into "setup" and "property" regions, and suggests generalized property tests derived from the property region — including generator candidates inferred from how values were constructed in the test.
- **Contribution 3 — RefactorBridge**: When TemplateEngine accumulates enough algebraic evidence on a type, SwiftInfer suggests the corresponding standard-library or kit-supported protocol conformance so the property can be verified by SwiftProtocolLaws on every CI run.
- **Contribution 4 (v1.1) — SemanticIndex**: A persistent, queryable graph of inferred properties and relationships across runs. Discussed in §20 Future Directions, deliberately out of v1 scope. Mentioned here so the v1 architecture leaves the door open.

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

Real-world tests are messy. A `testRoundTrip` may include five lines of `JSONEncoder` configuration before the actual round-trip assertion. The general property is right there, but extracting it requires *slicing* the test into the encoder/decoder construction (setup) and the assertion chain (property). v0.2's TestLifter does this slicing explicitly.

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
- Produce human-reviewable output with weighted-score provenance, counter-signals, and **first-class explainability** (§4.5)
- Operate as a CLI discovery tool with an interactive triage mode, and as a non-fatal CI drift checker
- Integrate with SwiftProtocolLaws' `PropertyBackend` abstraction for test execution
- Track adoption decisions over time so the scoring engine can be empirically tuned (§17)

### Non-Goals

- Automatically executing inferred properties without human review
- Replacing unit tests or SwiftProtocolLaws protocol law checks
- Full runtime invariant inference (Daikon-style instrumentation)
- Stateful / model-based test generation (separate project scope)
- Correctness guarantees on inferred properties — all output is probabilistic suggestion
- Persistent semantic indexing across runs (deferred to v1.1 — see §20)
- IDE plugins (Xcode quick-fix integration is desirable but out of scope for v1 — see §20)

-----

## 3.5 Product Philosophy (NEW in v0.3)

> SwiftInfer is a **conservative inference engine**. It prioritizes high precision and low recall. The goal is not to discover every possible property, but to surface only those with strong structural or behavioral evidence.

This philosophy governs every design choice in this document. Three corollaries:

1. **False positives are more damaging than missed opportunities.** A developer who reviews ten suggestions and finds one wrong loses trust faster than one who runs the tool again next month and finds new suggestions. Every threshold, signal weight, and default visibility setting in this document is biased toward suppression.
2. **All output is opt-in and human-reviewed.** SwiftInfer never auto-applies, never auto-executes, never auto-commits. Even in CI mode (§9), it emits warnings, not failures.
3. **The Daikon trap is the failure mode to avoid.** Daikon (runtime invariant inference) famously produces hundreds of true-but-uninteresting invariants. SwiftInfer's defaults must produce a number of suggestions a developer can read in one sitting; if benchmark calibration shows we're producing more, the answer is to raise thresholds, not to add filters on top.

This philosophy is load-bearing for the scoring engine (§4) and the success criteria (§19). When in doubt about a design choice, default to whichever option produces fewer suggestions.

-----

## 3.6 Developer Workflow (NEW in v0.3)

The intended end-to-end workflow:

1. **Discovery.** Developer runs `swift-infer discover --target MyApp` or `swift-infer discover --interactive`.
2. **Suggestion review.** Suggestions are grouped by tier (`✓ Strong`, `~ Likely`, optionally `? Possible` with `--include-possible`). Each suggestion shows its evidence trail and explainability block (§4.5).
3. **Adoption.** Accepted suggestions write stubs to `Tests/Generated/SwiftInfer/`. RefactorBridge suggestions write conformance stubs to `Tests/Generated/SwiftInferRefactors/` for the developer to inspect and move (never auto-edit existing source — see §16).
4. **Generator completion.** Developer resolves any `.todo` generators. Mock-based synthesis (§7.4) reduces this step's frequency.
5. **Execution.** `PropertyBackend` (single backend: `swift-property-based`) executes the tests via the standard `swift test` flow.
6. **Counterexample feedback.** When a property fails, the shrunk counterexample is convertible into a focused unit test via `swift-infer convert-counterexample` (M8).
7. **Drift checking.** CI runs `swift-infer drift --baseline .swiftinfer/baseline.json` on every PR, warning (non-fatally) about new Strong-tier suggestions added since baseline that lack a recorded decision.
8. **Decision persistence.** Accept / reject / skip decisions live in `.swiftinfer/decisions.json`, keyed by stable suggestion-identity hash (§7.5). Decisions survive refactors that don't change function signatures or AST shape.

-----

## 4. Confidence Model — Weighted Scoring Engine

v0.1 used three discrete tiers. v0.2 replaced this with a weighted score built from independent signals; v0.3 keeps that engine and adds **pluggable naming vocabularies** (§4.5) so project-specific conventions can extend the curated lists without forking the tool.

### 4.1 Signals

A suggestion's score is the sum of contributing signals (positive and negative). Signals are independent — a suggestion can earn confidence from naming alone, from types alone, or from any combination.

| Signal | Weight | Description |
|---|---|---|
| **Exact name match** | +40 | Function pair matches a curated inverse list (`encode`/`decode`, `serialize`/`deserialize`, `compress`/`decompress`, `encrypt`/`decrypt`, `push`/`pop`, `insert`/`remove`, `open`/`close`, `marshal`/`unmarshal`, `pack`/`unpack`, `lock`/`unlock`) **or** a project-vocabulary entry (§4.5). |
| **Type-symmetry signature** | +30 | `T → U` paired with `U → T` in the same scope (type, file, or module). For unary templates, `T → T` for idempotence; `(T, T) → T` for binary-op templates. |
| **Algebraic-structure cluster** | +25 per element | Type exposes a binary op `(T, T) → T` *and* an identity-shaped constant. Each additional element (associativity confirmed by signature; inverse function present; idempotence detected) adds +25. |
| **Reduce/fold usage** | +20 | The type is used in `.reduce(identity, op)` or a manual `for`/accumulator builder pattern at least once in the analyzed corpus. |
| **`@Discoverable(group:)` annotation** | +35 | Two functions share an explicit `@Discoverable(group:)` from SwiftProtocolLaws — already promoted to HIGH in `ProtoLawMacro`'s M5 advisory and re-used here. |
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

The thresholds are tunable. Real-world calibration against open-source corpora (per §19) is what sets them; treat the numbers above as v0.3 starting points, not load-bearing constants. The empirical recalibration loop is described in §17 (Adoption Tracking).

### 4.3 Generator Awareness

Every suggestion's evidence record includes:

- `generatorSource`: `.derived(.caseIterable | .rawRepresentable | .memberwise | .codableRoundTrip)` | `.registered` | `.todo` | `.inferredFromTests`
- `generatorConfidence`: `.high` | `.medium` | `.low`
- `samplingResult`: `.passed(trials: N)` | `.failed(seed: S, counterexample: C)` | `.notRun`

A "Strong" suggestion that passed sampling under a `.low` generator is rendered with an explicit caveat in the explainability block (§4.5).

### 4.4 Counter-Signals Are Veto-Capable

The negative-weight rows above accumulate disconfirming evidence. The `non-Equatable output` signal is special-cased to `-∞` because the property is structurally untestable.

### 4.5 Explainability as a First-Class Output (NEW in v0.3)

ChatGPT's critique correctly observed: explainability isn't just nice-to-have, it's the load-bearing substitute for trust in a probabilistic tool. v0.3 elevates explainability from "evidence list" (v0.2) to a structured **two-sided block** on every suggestion:

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

#### Pluggable Naming Vocabularies (NEW in v0.3)

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
  "antiCommutativityVerbs": ["concatenateOrdered"]
}
```

These extend (not replace) the curated lists. Project-vocabulary matches contribute the same +40 / +25 / -30 weights as the built-in lists. v1.1 may add an opt-in mode that mines naming patterns from the analyzed repo itself — punted for now (Open Question 6).

-----

## 5. Contribution 1: TemplateEngine

### 5.1 Description

TemplateEngine is a SwiftSyntax-based static analysis pipeline that scans Swift source files, matches function signatures and naming patterns against a registry of named property templates, accumulates signals per the §4 scoring engine, and emits candidate property test stubs (and, for algebraic clusters, RefactorBridge suggestions per §6).

> **Evolution path.** ChatGPT's critique observed that "templates as patterns over signatures" risks becoming a rigid rule engine, and that the long-term direction is **constraints over a function graph + types + usage** (the "Constraint Engine" upgrade). v0.3 ships the template-pattern model for v1 — it's the simplest thing that produces useful output. The constraint-engine upgrade is on the v1.1+ trajectory (§20). The v1 architecture is built so the constraint engine can replace the matcher behind the scoring engine without touching downstream contracts.

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

The two M1 templates — round-trip and idempotence — are specified in full below. The other six are lifted verbatim from v0.2 §5.2 in `Joseph-Cursio/SwiftProtocolLaws` at commit `722841b`, file `docs/Property Inference/SwiftInferProperties PRD.md`, and remain unchanged in v0.3 except for the explainability-block additions of §4.5; the v0.4 sweep will inline them here. (v0.2's separate Semilattice and Reducer/Event-Application templates were folded into §5.4's algebraic-structure composition — they are no longer standalone.)

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

Per the Gemini critique, naming heuristics are fragile. v0.2's TemplateEngine supplements naming with light type-flow analysis over the SwiftSyntax-derived call graph: composition detection (`f(f(x))` → +20 idempotence), inverse-by-usage (`g(f(x))` followed by `== x` assertion → round-trip score directly), reducer/builder usage (+20 associativity), accumulator-with-empty-seed (+20 identity-element).

Type-flow analysis is intentionally light — syntactic pattern matching over the call graph at the SwiftSyntax level, scoped to the analyzed target. Not full call-graph or alias analysis. This keeps it tractable and predictable.

### 5.4 Algebraic-Structure Composition

Multiple per-template signals on the same type → structural claim (semigroup, monoid, group, semilattice, ring) → RefactorBridge suggestion. Detail unchanged from v0.2 §5.4. The RefactorBridge caveat about Numeric vs FloatingPoint (integer-like exact-equality laws vs IEEE-754 rounding) is now part of every ring-claim suggestion's explainability "why this might be wrong" block.

### 5.5 Cross-Function Pairing Strategy

Tiered filtering unchanged from v0.2: type filter → naming filter → scope filter → optional `@Discoverable(group:)`. In practice, a module of 50 functions typically produces fewer than 10 candidate pairs after type filtering.

### 5.6 Contradiction Detection

Same table as v0.2 §5.6. Contradictions surface in the explainability block as both an active counter-signal and a "this combination has known traps" warning.

### 5.7 Annotation API

Reuses `@Discoverable(group:)` from `ProtoLawMacro` (no new API). Introduces only `@CheckProperty(.idempotent)` / `@CheckProperty(.roundTrip, pairedWith:)` for direct stub generation. Detail unchanged from v0.2 §5.7.

### 5.8 Milestones

| Milestone | Deliverable |
|-----------|-------------|
| M1 | SwiftSyntax pipeline; CLI discovery tool (`swift-infer discover`); round-trip + idempotence templates wired through the §4 scoring engine and §4.5 explainability block; basic cross-function pairing (type + naming filter); `// swiftinfer: skip` rejection markers honored; performance budget hit on the §13 reference corpora (`swift-collections`, `swift-algorithms`). |
| M2 | Commutativity, associativity, identity-element templates; project configuration (`.swiftinfer/config.toml`); pluggable naming vocabulary (§4.5) loaded from `.swiftinfer/vocabulary.json`. |
| M3 | Contradiction detection (§5.6); cross-validation with TestLifter (+20 signal per §4.1) once TestLifter M1 lands. Prerequisite: `DerivationStrategist` exposed publicly from SwiftProtocolLaws (see §11, §21 OQ #4). |
| M4 | Scoring model surfaced fully in output (per-signal weights in the explainability block); sampling-before-suggesting (§4.3) using the seeded policy of §16 #6. |
| M5 | `@CheckProperty` and `@Discoverable` annotation API (§5.7); `--dry-run` / `--stats-only` modes. |
| M6 | Monotonicity (`Possible` by default — escalation only via TestLifter corroboration or explicit annotation per §5.2 caveat); invariant-preservation (annotation-only); RefactorBridge upstream-loop conformance suggestions written to `Tests/Generated/SwiftInferRefactors/` (§6, §16 #1). |
| M7 | Algebraic-structure composition (§5.4) — semigroup / monoid / group / semilattice / ring claims accumulated from per-template signals on the same type; expanded identity-element detection (init-based + reduce-usage signals); `inverse-pair` template ships standalone for non-Equatable cases (suppressed per §16 #6 explainability). |

The §4.5 explainability block ("why suggested" + "why this might be wrong") is a **cross-cutting per-template deliverable** — every template added in any milestone must ship its block populated from the matched counter-signals plus the template's known caveats. There is no separate "explainability milestone."

**M1 acceptance bar.** Beyond the deliverables above, M1 is not done until: (a) every emitted stub for round-trip and idempotence has a golden-file test (per §18) covering the explainability block byte-for-byte; (b) the §13 performance budget for `swift-infer discover` (< 2s wall on 50-file module) is hit on `swift-collections` and `swift-algorithms`; (c) the §16 hard guarantees relevant to discovery (no source-file modification, no telemetry, byte-identical reproducibility under fixed seeds) have integration tests in CI.

-----

## 6. Contribution 3: RefactorBridge

Unchanged from v0.2 §6. The bridge: TemplateEngine accumulates strong evidence for a monoid/ring/semilattice → RefactorBridge proposes both a one-off property test (Option A) and a protocol conformance (Option B) that SwiftProtocolLaws then verifies on every CI run. Both options are presented; the developer chooses; the choice is logged to `.swiftinfer/decisions.json`. RefactorBridge writes conformance stubs only to `Tests/Generated/SwiftInferRefactors/`, never to existing source files (see §16 Hard Guarantees).

-----

## 7. Contribution 2: TestLifter

### 7.1 Description, 7.2 Slicing Phase, 7.3 Pattern Recognition

Unchanged from v0.2. The slicing pass anchors on the terminal assertion, backward-slices to collect contributing statements, classifies the remainder as setup, and identifies parameterized values (literals and vars initialized to literals).

### 7.4 Generator Inference (Mock-Based Synthesis)

Unchanged from v0.2 §7.4. Tiered fallback: CaseIterable → RawRepresentable → memberwise (delegated to shared `DerivationStrategist`) → mock-inferred from observed test construction → Codable round-trip → `.todo`. Generator confidence (`high` / `medium` / `low`) flows into the explainability block.

### 7.5 Persistence and Suggestion Identity

Unchanged from v0.2 §7.5. Stable hash on `(template ID, function signature canonical form, AST shape of property region)`. Decisions live in `.swiftinfer/decisions.json` keyed by hash. `// swiftinfer: skip [hash]` markers in source survive regeneration.

### 7.6, 7.7 Existing-Tests Relationship and Confidence

Unchanged from v0.2.

### 7.8 Expanded Outputs (NEW in v0.3, scoped to M9)

ChatGPT's critique correctly observed: tests encode *intent*, not just example values. Beyond properties, TestLifter can extract:

- **Inferred preconditions.** A test that constructs `MyData` only with `value: positive Int` across every test site implies a precondition `value > 0`. TestLifter surfaces this as a generator constraint suggestion: "consider `Gen<MyData>` with `Gen.int(in: 1...)` for the `value` field — observed only with positive values across 9 test sites."
- **Inferred domains.** When tests for `decode` only pass strings produced by `encode`, TestLifter infers that `decode`'s domain is "encoder output" rather than "all `String`". Suggestion: "round-trip property over `Gen<MyType>.map(encode)` rather than `Gen.string()` — `decode` was never observed against arbitrary strings, only encoder output."
- **Equivalence classes.** Tests that group inputs into "valid" / "invalid" buckets via parallel construction patterns hint at equivalence classes worth parameterizing the property over.

These expanded outputs are scoped to M9 (after the M1–M8 base TestLifter is shipped and benchmarked). They're called out here so the M1 architecture leaves them room — specifically, the slicing phase already separates literals from configuration; M9 just adds a cross-test correlation pass on top.

### 7.9 Milestones

| Milestone | Deliverable |
|---|---|
| M1 | SwiftSyntax test body parser, slicing phase, assert-after-transform detection, round-trip suggestion |
| M2 | Double-apply (idempotence) and symmetry (commutativity) detection |
| M3 | Generator inference: stdlib derivation strategies + `.todo` stub pattern; consume shared `DerivationStrategist` |
| M4 | Mock-based generator synthesis from observed test construction |
| M5 | Ordering, count-change, reduce-equivalence pattern detection |
| M6 | Suggestion-identity hashing, decisions.json persistence, `// swiftinfer: skip` honoring |
| M7 | Counter-signal scanning across test target |
| M8 | Counterexample-to-unit-test conversion tooling |
| M9 (NEW) | Expanded outputs: inferred preconditions, inferred domains, equivalence-class detection |

-----

## 8. Interactive Triage Mode

Unchanged from v0.2 §8. `swift-infer discover --interactive` walks suggestions one at a time with `[A/B/s/n/?]` prompts. Decisions logged to `.swiftinfer/decisions.json`.

-----

## 9. CI Drift Mode

Unchanged from v0.2 §9. `swift-infer drift --baseline .swiftinfer/baseline.json` emits a non-fatal warning per new Strong-tier suggestion lacking a recorded decision after the baseline date. GitHub Actions annotation surface in PR review UI.

-----

## 10. Architecture Overview

The component diagram is unchanged from v0.2. v0.3 adds an explicit table of architectural responsibility, addressing Copilot's "what lives where?" concern:

| Concern | Owner | Notes |
|---|---|---|
| Conformance detection | SwiftProtocolLaws (`ProtoLawMacro` discovery plugin) | SwiftInfer never re-implements |
| Protocol-law verification | SwiftProtocolLaws (`ProtocolLawKit`) | All test execution goes through `PropertyBackend` |
| Memberwise generator derivation | SwiftProtocolLaws (`DerivationStrategist`) | **Shared** between `ProtoLawMacro` and SwiftInfer; refactor required to expose publicly |
| Test execution | SwiftProtocolLaws (`PropertyBackend`) | Single backend (`swift-property-based`); abstraction stays public |
| Signature-based property inference | SwiftInfer (`TemplateEngine`) | Includes type-flow analysis |
| Algebraic-structure composition | SwiftInfer (`TemplateEngine` §5.4) | Drives RefactorBridge |
| Conformance suggestions back to SwiftProtocolLaws | SwiftInfer (`RefactorBridge`) | Writes only to `Tests/Generated/SwiftInferRefactors/` |
| Test-body inference | SwiftInfer (`TestLifter`) | Includes slicing, mock-based generator synthesis |
| CLI / triage / drift / decisions persistence | SwiftInfer (CLI surface) | `.swiftinfer/` directory is SwiftInfer-owned |
| Naming vocabulary | SwiftInfer (`.swiftinfer/vocabulary.json`) | Project-extensible per §4.5 |

A type rule of thumb for contributors: **contractual** properties live in SwiftProtocolLaws (you said you conform to X, X has laws, the kit verifies them). **Structural and behavioral** properties live in SwiftInfer (the code looks like X, the tests behave like X, both are probabilistic claims).

-----

## 11. Relationship to SwiftProtocolLaws

Unchanged from v0.2 §11. Bidirectional via RefactorBridge: SwiftInfer detects algebraic structure → suggests protocol conformance → SwiftProtocolLaws' discovery plugin emits the law-check on the next regeneration → laws are enforced on every CI run thereafter.

The shared `DerivationStrategist` enum lives in `ProtoLawCore` at `package` visibility (see `Sources/ProtoLawCore/DerivationStrategy.swift:170` in `Joseph-Cursio/SwiftProtocolLaws`); promoting it — along with `DerivationStrategy`, `TypeShape`, and the public surface of `MemberwiseEmitter` — from `package` to `public` is the prerequisite for SwiftInfer M3. See §21 OQ #4 for the concrete action item.

The overlap with SwiftProtocolLaws' own M5 round-trip advisory is intentional — different confidence regimes (HIGH-confidence syntactic in SwiftProtocolLaws, weighted full-spectrum in SwiftInfer). When both fire on the same pair, SwiftInfer adds +20 for cross-validation.

Single-backend by design: `swift-property-based` only. The `SwiftQC` reference from the original v0.1 is dropped throughout.

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

-----

## 13. Performance Expectations (NEW in v0.3)

Per Copilot's critique, contributors will accidentally build something too slow if no budget is stated. Hard targets for v1:

| Operation | Target | Failure mode |
|---|---|---|
| `swift-infer discover` on 50-file module | < 2 seconds wall | regression test fails; release blocked |
| TestLifter parse of 100 test files | < 3 seconds wall | regression test fails |
| `swift-infer drift` re-run after one-file change | < 500ms (incremental) | regression test fails |
| Memory ceiling on 500-file module | < 200 MB resident | regression test fails |
| `swift-infer discover --interactive` first-prompt latency | < 1 second after process start | release blocked |

Numbers are deliberately Swift-realistic (SwiftSyntax parsing dominates), not aspirational. Calibrate against `swift-collections` and `swift-algorithms` as the reference corpora during M1 — if the targets are already missed there, raise them in v0.4 rather than ship a tool that can't keep up with `swift package protolawcheck discover`.

A **performance regression test suite** runs in CI: the discovery and drift commands are timed against fixed input corpora, results recorded, and a 25% regression in any number fails the build.

-----

## 14. Security and Privacy (NEW in v0.3)

SwiftInfer is a local development tool. The following are hard guarantees:

- **No code leaves the developer's machine.** SwiftInfer never network-calls during analysis. `swift-infer discover`, `drift`, `convert-counterexample` are entirely local.
- **No telemetry by default.** No usage data, no error reports, no anonymized statistics — nothing — is sent anywhere unless the user explicitly opts in. There is no "opt out" because there is nothing on by default to opt out of.
- **`.swiftinfer/` directory contents are local-only.** `decisions.json`, `baseline.json`, `vocabulary.json` are repo-checked-in artifacts (the user controls whether to gitignore them). They contain no information beyond what's already in the codebase.
- **Generated stubs include no source telemetry markers.** Lifted property tests reference origin tests by file:line in comments — that's it. No tool-version stamps that would let log scraping correlate users.
- **Future opt-in aggregation, if added, will be repo-local.** v1.1's Adoption Tracking dashboard (§17) operates on `.swiftinfer/decisions.json` only and does not phone home. If a hosted aggregation service is ever proposed, it requires a separate PRD and explicit opt-in per repo.

This matters for enterprise adoption and for projects with regulated/proprietary code. Stating it in the PRD prevents future contributors from "helpfully" adding any of the above.

-----

## 15. Extensibility Model (Future Work)

v1 ships a curated, closed template registry. Third-party template registration is a frequently-suggested extension (Copilot critique §7) but raises confidence-model integrity concerns: ill-tuned third-party templates would degrade the precision-over-recall philosophy from outside the maintainers' control.

The v1.1+ direction (§20) is to add a plugin API with the following declared shape per template:

- `name: String` — unique identifier
- `signaturePattern: SignaturePattern` — required type shape
- `confidenceContributors: [SignalContribution]` — bounded weights (0–50 positive, 0–30 negative); third-party templates cannot use the `-∞` veto
- `emittedTestBody: SwiftSyntax` — golden-file-tested
- `contradictionRules: [ContradictionRule]` — interactions with built-in templates
- `knownCaveats: [String]` — populates the "why this might be wrong" block

Registry ordering would be confidence-driven, not insertion-order. Built-in templates always run first. This is sketched only — no v1 commitment.

-----

## 16. Failure Modes and Hard Guarantees (NEW in v0.3)

Per Copilot critique §9. SwiftInfer ships with the following hard guarantees, enforced by code review and integration tests:

1. **SwiftInfer never modifies existing source files.** Generated content goes only to `Tests/Generated/SwiftInfer/`, `Tests/Generated/SwiftInferRefactors/`, and `Tests/Generated/SwiftInferGenerators/`. RefactorBridge conformance suggestions write conformance stubs to the Refactors directory; the developer manually moves them.
2. **SwiftInfer never deletes tests.** TestLifter reads existing tests; it never overwrites them. Lifted properties are emitted as new files, never replacements.
3. **SwiftInfer never auto-accepts suggestions.** Even in CI mode, `drift` emits warnings, not failures. The accept/reject step is always human.
4. **SwiftInfer never emits silently-wrong code.** When generator inference fails, the stub is emitted with `.todo`, which does not compile. There is no "approximately correct" generator fallback.
5. **SwiftInfer never operates outside the configured target.** `--target` is required for `discover`; the tool refuses to scan files outside the named target's source roots.
6. **SwiftInfer's output is reproducible.** Re-running `discover` on unchanged source produces byte-identical output (modulo the timestamp recorded in decisions.json on accept). Same property as SwiftProtocolLaws' discovery plugin. **Seed policy:** all sampling that contributes to a suggestion's score (§4.1 sampling-pass row, §4.3 `samplingResult`) uses a deterministic seed derived from the suggestion-identity hash (§7.5) — concretely, the low 64 bits of `SHA256(suggestionIdentityHash || "sampling")`. The seed is rendered in the explainability block of every emitted stub so a developer can re-run sampling under the same conditions. `--seed-override` is supported for debugging only and is never persisted to `decisions.json`.

These guarantees are tested by the integration suite (§18). Violation is a release-blocking bug.

-----

## 17. Adoption Tracking and Metrics (NEW in v0.3)

ChatGPT's critique observed that "trust is everything" appears in the philosophy but is never operationalized. v0.3 makes adoption tracking concrete and uses it to close the calibration loop on the scoring engine.

### 17.1 Tracked Metrics

Every accept / reject / skip / "note as wrong" decision in `.swiftinfer/decisions.json` records:

- Suggestion-identity hash
- Tier and score at decision time
- Template ID
- Signal weights that contributed
- Decision (accept-A / accept-B / skip / wrong)
- Timestamp
- (When the suggestion is accepted) whether the resulting test passes on first commit

### 17.2 Derived Metrics

`swift-infer metrics` aggregates locally:

| Metric | Definition | Why it matters |
|---|---|---|
| Acceptance rate | accepts / (accepts + rejects + wrongs) per template | Templates with < 50% acceptance after 20 suggestions are candidates for retirement or weight tuning |
| False-positive rate | "wrong" decisions / total surfaced | Tracks the precision side of the philosophy directly |
| Suppression rate | skips / total surfaced | High suppression suggests noise; low suppression suggests the tool is missing things |
| Time-to-adoption | timestamp(accept) - timestamp(suggestion first surfaced) | Tracks UX friction; long times suggest the suggestion is unclear |
| Post-acceptance failure rate | accepted suggestions whose test fails on commit / total accepted | Catches "developer accepts, test was wrong" |

### 17.3 Calibration Loop

After v1 ships, weights and thresholds are tuned **empirically**, not by guess. The calibration loop:

1. Aggregate decisions from a corpus of opt-in projects (collected manually, not via telemetry — see §14).
2. Run weight-perturbation analysis: which signal weights, if changed by ±10, would have improved the precision/recall trade-off without the false-positive rate spiking?
3. Propose weight updates in a v0.4 PRD revision; ship in a minor SwiftInfer release.
4. Re-measure on the next release cycle.

This is the operationalization of "high precision, low recall." Without it, the philosophy is just a slogan. With it, the scoring engine improves as adoption grows.

-----

## 18. Test Coverage Requirements (NEW in v0.3)

Per Copilot critique §8. SwiftInfer is a static analysis tool — its own test coverage standards must be high enough to catch regressions in the inference itself.

| Component | Coverage standard |
|---|---|
| TemplateEngine signal scoring | Per-signal unit tests for every weight in §4.1; integration tests for every template in §5.2 |
| TemplateEngine emitted bodies | **Golden-file tests** — each template's emitted SwiftSyntax stub is checked byte-for-byte against a committed expected-output file; regenerating goldens requires explicit `--update-goldens` flag |
| TestLifter slicing phase | Property-based fuzz tests against a generator of test-method ASTs — slicing must always produce a valid (possibly empty) property region without throwing |
| Generator inference | Per-strategy unit tests for every row in §7.4's table; integration tests against `swift-collections` and `swift-algorithms` as real-world corpora |
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
- Counter-signals correctly veto at least one false-positive that the v0.2 model would have surfaced, in each benchmark.
- Contradiction detection catches idempotent+involutive and at least 2 other contradictory combinations.
- Acceptance rate (per §17.2) ≥ 70% on the benchmark corpora after 6 months of dogfooding. Below that, the philosophy hasn't held.

### TestLifter

- Running on a test suite of 50+ XCTest methods correctly identifies at least 5 liftable patterns with Strong or Likely score after slicing.
- The slicing phase correctly separates setup from property body in at least 90% of tests with non-trivial setup (≥3 setup statements before the assertion).
- At least 90% of emitted stubs compile after the developer resolves `.todo` generators.
- Mock-based generator synthesis produces a valid `Gen<T>` for at least 50% of the types where ≥3 test sites construct via the same initializer.
- No existing unit test is modified or deleted under any circumstances. (Hard guarantee per §16.)

### Performance and Privacy

- All §13 performance budgets are met against `swift-collections` and `swift-algorithms` as reference corpora at v1.0 release.
- All §14 privacy guarantees are testable: integration test verifies no network sockets opened during any subcommand.

### Confidence Model

- Threshold tuning against the benchmark corpora produces tier boundaries within 10 points of the v0.3 starting values (75 / 40 / 20). If real-world calibration pushes them further, that's a finding to document in v0.4.

-----

## 20. Future Directions (NEW in v0.3)

These are explicitly out of v1 scope. Listing them here so the v1 architecture leaves the door open and so contributors know the trajectory.

### 20.1 Contribution 4: SemanticIndex (v1.1)

ChatGPT's critique made the strongest case for elevating SwiftInfer beyond test suggestion: a **persistent, queryable graph of inferred properties and relationships across runs**. This becomes a "semantic lens over a Swift codebase that reveals latent algebraic structure" — useful for:

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

ChatGPT's critique pushed for moving from "templates as patterns over signatures" to "constraints over a function graph + types + usage." The constraint-engine model:

- Constraints are first-class objects: `Constraint(targetSignature: P, requiredCallGraphEvidence: E, requiredUsageEvidence: U) -> Score`
- Templates are syntactic sugar over constraints
- New properties are added as constraints, not as bespoke matchers
- Enables higher-order property composition (e.g., "this group has a homomorphism into that semilattice")

The v1 template registry is built so this upgrade can replace the matcher behind the scoring engine without touching the scoring engine itself or any downstream contract. v1 architecture is constraint-engine-ready.

### 20.3 Domain Template Packs (v1.1+)

Both ChatGPT and Copilot suggested splitting the registry into domain packs:

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

ChatGPT noted the natural connection: SwiftInfer discovers properties, and a separate semantic linter could enforce them as project rules ("if the team committed to monoid laws on Config, lint any new function that breaks them"). This requires either a separate SwiftLint integration or a new linting tool; both are out of SwiftInfer's scope but on the strategic trajectory.

### 20.6 In-Source `@ProposedProperty` Marker Annotations (v1.1+)

Considered for v1, **deferred to v1.1+ alongside the §20.4 IDE story.** The proposal: a passive marker attribute `@ProposedProperty(.idempotent, score: 80, evidence: "encode/decode pair, sampling 25/25")` that a `swift-infer apply --suggestion <hash>` subcommand writes to the relevant declaration, surfacing structured proposals next to the code they describe. Modeled on the marker conventions in `Joseph-Cursio/swiftidempotency` (`@Idempotent`, `@NonIdempotent`, `@Observational`) and `Joseph-Cursio/SwiftProtocolLaws`, but **passive only** — `@ProposedProperty` does not expand at compile time, so SwiftInfer never becomes a runtime dependency of the source target.

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

-----

## 21. Open Questions

Trimmed from v0.2 — Open Question 5 (Generator Gap macro), Open Question 6 (semantic indexing), Open Question 7 (domain packs) all moved into §20 Future Directions with concrete v1.1 framing. Remaining open questions:

1. ~~**Separate package or monorepo?**~~ **Resolved (separate package).** SwiftInfer ships as `Joseph-Cursio/SwiftInferProperties`, a sibling repo to `Joseph-Cursio/SwiftProtocolLaws`. During pre-1.0, `Package.swift` references SwiftProtocolLaws via a local path (`../SwiftProtocolLaws`); swap to a versioned URL dep before tagging 1.0. SwiftInfer 1.0 will require SwiftProtocolLaws ≥ 1.5.
2. **TemplateEngine as compiler plugin vs. CLI?** CLI for v1 (whole-module scanning + interactive mode). Compiler-plugin mode for incremental per-file suggestions during development is desirable but unscoped — defer to v1.1 with the IDE integration push.
3. **TestLifter and Swift Testing vs. XCTest?** M1 should target both. The slicing pass is the same; the SwiftSyntax shape of `@Test func` is well-defined.
4. ~~**The shared `DerivationStrategist` extraction.**~~ **Resolved (action item, not an open question).** As of the SwiftProtocolLaws working tree, `DerivationStrategist` lives in `ProtoLawCore` (not `ProtoLawMacro` as v0.3 originally stated) at `package` visibility — see `Sources/ProtoLawCore/DerivationStrategy.swift:170`. Same maintainer owns both repos. **Action for SwiftInfer M3:** open a PR on SwiftProtocolLaws promoting `DerivationStrategist`, `DerivationStrategy`, `TypeShape`, and `MemberwiseEmitter`'s public surface from `package` to `public`; tag a SwiftProtocolLaws minor release; bump SwiftInfer's local-path dep to that tag. No design question remains.
5. **Threshold calibration source.** §17 calibration assumes a corpus of opt-in projects contributing decisions. How is that corpus assembled — public-repo dogfooding only, or invited closed-source pilots? Affects the calibration timeline directly.

-----

## 22. References

- [_7_SwiftProtocolLaws PRD](_7_SwiftProtocolLaws%20PRD.md) — upstream dependency (v0.3+)
- [_4a_ Algebraic Structures](_4a_%20Algebraic%20Structures.md)
- [_4c_ Monoids and Property Testing](_4c_Monoids%20and%20Property%20Testing.md)
- [Gemini critique](Gemini%20critique.md) — primary input to v0.2
- [ChatGPT critique](ChatGPT%20critique.md) — primary input to v0.3 (Semantic Index, Explainability, Constraint Engine, Adoption Metrics)
- [Copilot critique](Copilot%20critique.md) — primary input to v0.3 (Product Philosophy, Developer Workflow, Performance, Privacy, Hard Guarantees, Negative Examples)
- [swift-property-based](https://github.com/x-sheep/swift-property-based) — single execution backend
- [SwiftSyntax](https://github.com/apple/swift-syntax)
- [EvoSuite](https://www.evosuite.org)
- [Daikon](https://plse.cs.washington.edu/daikon/)
- [QuickSpec](https://hackage.haskell.org/package/quickspec)
- [Hedgehog state machines](https://hedgehog.qa)

-----

## Appendix A: Changelog v0.1 → v0.2 → v0.3

### v0.2 → v0.3 (this revision)

| Area | v0.2 | v0.3 | Driving input |
|---|---|---|---|
| Product philosophy | Implicit (precision over recall in body text) | Explicit §3.5 statement; corollaries derived | Copilot §1 |
| Developer workflow | Implicit | Explicit §3.6 step-by-step | Copilot §4 |
| Explainability | Evidence list per suggestion | First-class **two-sided block** ("why suggested" + "why this might be wrong") in §4.5; required for every template; populated from counter-signals + known caveats | ChatGPT §D |
| Naming heuristics | Curated lists hard-coded | Curated **plus** project-extensible `.swiftinfer/vocabulary.json` (§4.5) | ChatGPT §6 |
| TemplateEngine evolution path | Not stated | Explicit constraint-engine target for v1.1+; v1 architecture built constraint-engine-ready (§5.1, §20.2) | ChatGPT §3 |
| TestLifter outputs | Properties only | Properties for v1 (M1–M8); preconditions / domains / equivalence-classes scoped to M9 (§7.8) | ChatGPT §4 |
| Architectural responsibility | Distributed across PRD body | Explicit table in §10 ("what lives where?") | Copilot §2 |
| Performance | Unspecified | Hard targets in §13 with regression test enforcement | Copilot §5 |
| Security & privacy | Unspecified | §14 explicit guarantees: no network, no telemetry, repo-local | Copilot §6 |
| Failure modes | Implicit | §16 enumerated hard guarantees with integration-test enforcement | Copilot §9 |
| Adoption tracking | Implicit "tunable" | §17 explicit metrics + calibration loop tying scoring engine to empirical adoption | ChatGPT §9 + §10 |
| Test coverage requirements | Unspecified | §18 per-component standards including golden-file tests for emitted stubs | Copilot §8 |
| Negative examples | None | Appendix B catalog of what SwiftInfer must not suggest, why, how the model prevents it | Copilot §10 |
| Semantic Index | Deferred Open Question | Promoted to **planned Contribution 4 for v1.1** with concrete sketch (§20.1); v1 architecture preserves the seam | ChatGPT §1 |
| Constraint Engine, Domain Packs, IDE, Semantic Linting | Mentioned briefly | Consolidated in §20 Future Directions with v1.1+ trajectory | ChatGPT §A/B/C/E + Copilot §7 |
| Open Questions | 7 | 5 (3 promoted into §20) | Cleanup |

### v0.1 → v0.2 (preserved from v0.2 doc, summarized)

| Area | Change | Driving input |
|---|---|---|
| Confidence model | 3 discrete tiers → weighted scoring with signals + counter-signals | Gemini §2.A |
| Naming heuristics | Sole driver → supplemented by type-flow analysis | Gemini §1 |
| Algebraic detection | Independent templates → composed semigroup/monoid/group/lattice/ring claims | _4a_, _4c_ |
| Output of algebraic claims | Property tests → tests **plus** RefactorBridge conformance suggestion | Gemini §3.1 |
| TestLifter input | Assumed clean → slicing phase isolates property from setup | Gemini §1 |
| Generator inference | Fixed table → mock-based synthesis from observed test construction; shared `DerivationStrategist` | Gemini §3.3 |
| CLI UX | Static dump → adds `--interactive` triage mode | Gemini §2.B |
| CI integration | Unspecified → `swift-infer drift` non-fatal warning mode | Gemini §3.2 |
| Counter-signals | Implicit → explicit -∞ vetoes and downscoring | Gemini implicit |
| Suggestion identity | Unspecified → stable AST-shape hash; `.swiftinfer/decisions.json` persistence | Mirrors SwiftProtocolLaws plugin |
| Backend | `swift-property-based` + `SwiftQC` → single backend | Mirrors SwiftProtocolLaws v1.0 |

-----

## Appendix B: Negative Examples — What SwiftInfer Must Not Suggest (NEW in v0.3)

Per Copilot critique §10. These are the canonical false positives the scoring engine must reject. Contributors adding new templates should add a corresponding negative example here.

### B.1 Stringly-typed "round-trip" without Equatable

```swift
class CacheEntry { ... } // not Equatable
func store(_ entry: CacheEntry) -> CacheKey
func load(_ key: CacheKey) -> CacheEntry
```

**Naive matcher would suggest:** round-trip property `load(store(x)) == x`.

**What v0.3 does instead:** suppresses entirely. The `non-Equatable output` counter-signal weights `-∞`. The explainability block on the *suppressed* state (visible only with `--show-suppressed`) reports: "round-trip detected by name + type symmetry, but `CacheEntry` is not Equatable; property is structurally untestable."

### B.2 "Merge" that is not commutative

```swift
extension Array {
    func merge(with other: [Element]) -> [Element] {
        self + other  // ordered concat, NOT commutative
    }
}
```

**Naive matcher would suggest:** commutativity (`merge` keyword + `(T, T) -> T`).

**What v0.3 does instead:** the `concat`-family naming counter-signal (-30) is in the curated anti-commutativity list. Combined with type-flow detection that observes `merge(a, b) != merge(b, a)` in any test, score lands well below the Strong threshold. Even a Likely surfacing is gated on the user not having `concat` semantics; the explainability block warns: "`merge` on Array+Element is most often ordered concatenation — verify before adopting."

### B.3 Idempotence on a function that calls `Date()`

```swift
func canonicalize(_ session: Session) -> Session {
    var copy = session
    copy.lastNormalized = Date()  // non-deterministic
    return copy
}
```

**Naive matcher would suggest:** idempotence (`canonicalize` keyword + `T -> T`).

**What v0.3 does instead:** type-flow analysis flags non-deterministic API calls (`Date()`, `Random.next()`, `UUID()`) as immediate disqualifiers for idempotence — `f(f(x))` cannot equal `f(x)` if `f` reads the clock. Suggestion is suppressed; explainability reports: "non-deterministic API call detected on `canonicalize` body; idempotence is structurally impossible."

### B.4 Round-trip across throwing functions with asymmetric domains

```swift
func compress(_ data: Data) throws -> Data       // throws on > 1GB
func decompress(_ data: Data) throws -> Data     // throws on malformed
```

**Naive matcher would suggest:** round-trip (`compress`/`decompress` curated pair + `T -> T`).

**What v0.3 does:** suggests it *but* the explainability "why this might be wrong" block prominently warns: "both functions throw with different conditions; the property holds only over `compress`'s success domain. The emitted stub uses `try`; if `compress` succeeds and `decompress` then fails, the property tests the disjoint domain incorrectly. Consider narrowing the generator to `Gen<Data>.bounded(maxSize: 1.gigabytes)`."

### B.5 Monoid claim on a binary operation with side effects

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

**What v0.3 does:** the `mutating`/`Void`/IO side-effect penalty (-20) applies. Class kinds disqualify memberwise generator derivation. Score drops below Strong; even if surfaced, RefactorBridge would *not* propose `AdditiveArithmetic` because the structural compatibility check rejects class types. Explainability: "binary operation has observable side effects; monoid claim assumes pure functions."

### B.6 Pattern matching on a single test

```swift
func testTrivialEquality() {
    XCTAssertEqual(reverse(reverse([1, 2, 3])), [1, 2, 3])
}
```

**Naive matcher would suggest:** involution from a single double-apply pattern.

**What v0.3 does:** the minimum-2-test threshold (configurable to 3 for stricter pipelines) suppresses single-test pattern matches. Score never accumulates the +50 test-body signal because the threshold isn't met. Suggestion never reaches Strong from test evidence alone.

-----

## Appendix C: Critique Coverage Map

Tracks which critique sections are addressed in v0.3 and where:

### Gemini critique

- §1 Naming Heuristic Fragility → §5.3 type-flow (v0.2) + §4.5 pluggable vocabularies (v0.3)
- §1 TestLifter Noise Problem → §7.2 slicing phase (v0.2)
- §1 Interaction with SwiftProtocolLaws → §6 RefactorBridge (v0.2)
- §2.A Heuristic Scoring Engine → §4 weighted scoring (v0.2)
- §2.B Refinement CLI UX → §8 Interactive Triage Mode (v0.2)
- §3.1 Property-Driven Refactoring → §6 RefactorBridge (v0.2)
- §3.2 Property Drift Detection → §9 CI Drift Mode (v0.2)
- §3.3 Smart Generator Synthesis → §7.4 mock-based synthesis (v0.2)
- §5 Generator Gap macro → §20.4 IDE + Future Directions (v0.3, deferred)

### ChatGPT critique

- §1 Semantic Index → §20.1 Contribution 4 v1.1 (v0.3, scoped)
- §2 Generator Awareness → §4.3 (v0.2)
- §3 Constraint Engine → §20.2 v1.1+ (v0.3, with v1 architecture preserving seam)
- §4 TestLifter Expanded Outputs → §7.8 M9 (v0.3)
- §5 Weighted Evidence → §4 (v0.2)
- §6 Pluggable Naming → §4.5 vocabulary.json (v0.3)
- §7 Counter-Signals → §4.4 (v0.2)
- §8 Persistence Identity → §7.5 (v0.2)
- §9 Adoption Tracking → §17 (v0.3)
- §10 Operationalized Metrics → §17.2 + §17.3 (v0.3)
- §A Property Composition → §5.4 algebraic composition (v0.2) + §20 future composition over structures (v0.3)
- §B Domain Packs → §20.3 v1.1+ (v0.3)
- §C IDE Integration → §20.4 v1.1+ (v0.3)
- §D Explainability First-Class → §4.5 (v0.3)
- §E Semantic Linting Bridge → §20.5 v1.2+ (v0.3)

### Copilot critique

- §1 Product Philosophy → §3.5 (v0.3)
- §2 Architectural Clarity → §10 responsibility table (v0.3)
- §3 Noise Mitigation → distributed across §4, §5.6, §7.7 (v0.2/v0.3); calibrated by §17 (v0.3)
- §4 Developer Workflow → §3.6 (v0.3)
- §5 Performance Expectations → §13 (v0.3)
- §6 Security & Privacy → §14 (v0.3)
- §7 Extensibility Model → §15 sketch + §20.3 domain packs (v0.3)
- §8 Test Coverage Requirements → §18 (v0.3)
- §9 Failure Modes & Guarantees → §16 (v0.3)
- §10 Negative Examples → Appendix B (v0.3)
