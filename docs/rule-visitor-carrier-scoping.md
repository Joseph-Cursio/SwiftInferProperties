# Rule-visitor carrier — scoping (investigation + decision record)

**Status:** SCOPED. **Slice 1 (recognition) SHIPPED 2026-06-18** — see §7. Verify
(slices 3–4) stays shelved per the recommendation below.

**Slice 1 result (recognition only, no invariant emitted):** `RuleVisitorDiscoverer`
+ `RuleVisitorCandidate` (Core) recognise a `class` declaring ≥1
`visit(_:) -> SyntaxVisitorContinueKind` override (the structural visitor signal —
no base name hard-coded), capturing inherited base, visited node types, and
`ruleName:` emissions; surfaced as a new section in `discover-reducers`. Dogfood
proof on `swiftprojectlint`: **147** carriers in `SwiftProjectLintRules` (+12
Visitors, +7 IdempotencyRules), e.g. `ForceUnwrapVisitor [BasePatternVisitor] →
visits ForceUnwrapExprSyntax, emits forceUnwrap`. Cross-file/extension-aware;
abstract bases + non-visitor classes correctly excluded. Tests:
`RuleVisitorDiscovererTests` (6). `make test-fast` green (3287); swiftlint
`--strict` clean. **No determinism invariant is emitted, by design** (§6) — the
carrier is listed for a human, nothing scored.

---

**Original status:** SCOPED — not built. Recommendation below.
**Captured:** 2026-06-18. **Motivation:** the `swiftprojectlint` dogfood (2026-06-18)
surfaced 0 default-tier picks on a 282-file lint engine because its core is
SwiftSyntax *visitor classes*, a carrier shape the engine doesn't model —
exactly analogous to the MVVM gap that motivated `ViewModelDiscoverer`.

---

## 1. The carrier shape (architecture facts)

SwiftProjectLint detects lint patterns with one uniform carrier:

```swift
public protocol PatternVisitorProtocol: SyntaxVisitor {
    var detectedIssues: [LintIssue] { get }     // ← accumulated output (State analog)
    func reset()                                 // ← clears detectedIssues
    var pattern: SyntaxPattern { get }
    init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode)   // ← uniform ctor
}

open class BasePatternVisitor: SyntaxVisitor, PatternVisitorProtocol { … }
```

A concrete rule is a `final class FooVisitor: BasePatternVisitor` overriding
`visit(_ node:) -> SyntaxVisitorContinueKind` and calling `addIssue(…)`.

The engine runs one like this (`SourcePatternDetector`, the public driver):

```swift
let visitor = type.init(pattern: …)   // construct
visitor.set…(context)                 // inject pre-scan type metadata
visitor.walk(sourceFile)              // walk a parsed SourceFileSyntax
let issues = visitor.detectedIssues   // read output
```

The **value-semantic kernel** is therefore `(String) -> [LintIssue]`:
parse source → walk → collect. Pure over an immutable AST + injected context.

## 2. Reachability (hard counts, `Packages/SwiftProjectLintRules`)

| Metric | Count |
|---|---|
| `*Visitor.swift` files | 149 |
| extend `BasePatternVisitor` w/ `init(pattern:viewMode:)` | **124** |
| override `visit(…)` + `addIssue(…)` | 142 |
| **`public` visitor subclasses** | **0** |
| `internal` (default) visitor subclasses | 123 |
| public driver `SourcePatternDetector.detectPatterns(in:…) -> [LintIssue]` | 1 |

**Recognition is trivial and high-coverage** — 124/149 share one base + one ctor.
This is a *cleaner* carrier than MVVM (no `@Observable`/extension-merge ambiguity).

## 3. Invariant mapping — the first hard finding

Unlike the MVVM carrier (a view model genuinely **is** a reducer, so it reused
all five interaction families verbatim), a lint visitor does **not** map onto the
existing algebraic/interaction families. Its natural, universally-quantified
properties are a **different class**:

| Candidate property | Form | Verdict |
|---|---|---|
| **Determinism / purity** | `detect(s) == detect(s)` | Universal, but **near-trivially true** — a pure AST walk is nondeterministic only via Set/Dict iteration order or shared `static` mutable state. Low signal. |
| **Reset soundness** | `reset()` ⟹ `detectedIssues == []`; `walk; reset; walk == walk` | Universal, also near-trivially true (it's a one-line `= []`). Low signal. |
| **Clean-input emptiness** | pattern-free source ⟹ `detect(s) == []` (no false positives) | **High value** — this is the real bug class — but **per-rule semantic**: "pattern-free" is rule-specific, so it needs a per-rule generator/corpus, not a generic law. |
| Idempotence of a fix | `fix(fix(x)) == fix(x)` | **N/A** — these visitors detect, they don't autocorrect. |

**Conclusion:** the generically-checkable invariants (determinism, reset) are
the *least* interesting; the interesting one (no-false-positive on clean input)
is *not* generic. This is the inverse of the MVVM carrier's economics.

## 4. Verify feasibility — the second hard finding (access levels)

The project has **two** measured-verify models. Which one applies is settled by
access level:

- **External-package path-dependency** (the algebraic + MVVM model): a *generated
  verifier package* path-depends on the target and `import`s it. **Blocked here** —
  all 123 rule visitors are `internal`; an external package cannot see them.
  Only the public `SourcePatternDetector` is reachable this way, giving the coarse
  whole-engine `detect(s)==detect(s)` (no per-rule resolution).

- **In-repo generated `@testable` tests** (the **TestLifter** model — the engine
  already writes to `<package-root>/Tests/Generated/SwiftInfer/`): a generated
  test *inside the target's own test target* CAN `@testable import
  SwiftProjectLintRules` and construct an internal `FooVisitor`. **This is the
  only path that reaches the 123 internal carriers.**

So a per-visitor verify story is a **TestLifter** story, not a measured-execution
(external-package) story. That also means it leans on the target already having a
test target wired for `@testable` — which `swiftprojectlint` does
(`Tests/CoreTests/**/*VisitorTests.swift`, uniform `makeVisitor()` +
`Parser.parse` + `walk` + `#expect(detectedIssues.count == N)`), and it already
depends on `swift-property-based` (`Tests/CoreTests/Idempotency/LatticeLawsTests`).

## 5. The fork

- **A. Discovery-only.** `RuleVisitorDiscoverer` (Core) recognizes
  `BasePatternVisitor` subclasses → `RuleVisitorCandidate` (type, emitted
  `ruleName`s, ctor shape), surfaced in `discover-reducers`/`discover-interaction`
  at `.possible` with a **determinism** candidate. Cheap (~1 slice, mirrors
  `ViewModelDiscoverer`). But surfacing "this visitor is probably deterministic"
  on 124 visitors is a **low-signal flood** — the Daikon trap the PRD warns against.

- **B. TestLifter over the rule tests.** Lift the uniform `*VisitorTests`
  example pairs (`source ⟹ count == N`) into per-rule regression properties +
  the generic determinism law, written into `Tests/Generated/SwiftInfer/`. Reaches
  the internal carriers, produces the *high-value* clean-input/positive-input
  checks — but these are **example-based**, not universally-quantified laws, so
  they sit at the edge of the engine's "infer a law" thesis (closer to regression
  capture than property inference).

- **C. Detector-level determinism.** Verify the one public
  `detect(s) == detect(s)` over a source corpus via the external-package model.
  Verify-clean and reuses existing machinery, but coarse (whole engine, not
  per-rule) and again low-signal (determinism rarely fails).

## 6. Recommendation

**Build A's discovery half only as dogfood-completeness; SHELVE B and C.**
This mirrors the **cycle-119 value-generator outcome**: the carrier is cheap to
*recognize* (124/149, one base class) but the genuinely-checkable invariant is
**low-yield**, so investing in verify risks flooding `.possible` with
determinism candidates that nearly always pass — net-negative under the
high-precision / anti-Daikon posture.

Concretely:
- **Worth doing** (small, high-confidence, completes the dogfood story): a
  `RuleVisitorDiscoverer` that *recognizes* the carrier and reports it in
  `discover-reducers` (location, base, emitted rule, ctor) **without** auto-emitting
  a determinism invariant — recognition is the reusable asset; the determinism
  law is the part that floods.
- **Shelve until a higher-value property exists than determinism/reset.** The only
  property worth verifying (no-false-positive on clean input) is per-rule and
  already encoded in the target's tests — so if this is ever revisited, the lever
  is **TestLifter over `*VisitorTests` (fork B)**, not a from-scratch visitor
  measured-verify carrier. Determinism/detector-level verify (C) is not worth a
  cold TCA-class build per visitor for a property that is almost never false.

## 7. Slice plan (if/when greenlit — fork A first)

1. **Recognize.** `RuleVisitorDiscoverer` + `RuleVisitorCandidate` (Core): scan for
   `class X: BasePatternVisitor` (and `: PatternVisitorProtocol`), capture
   `init(pattern:viewMode:)`, the overridden `visit(_:)` node types, and the
   `ruleName:` argument(s) passed to `addIssue`. Test against `ForceUnwrapVisitor`.
2. **Surface.** A `discover-reducers`/`discover-interaction` section listing
   recognized rule visitors. No invariant emission yet (avoid the flood).
3. **(Deferred) Determinism candidate.** Only behind a future calibration decision
   that a determinism law clears the precision bar — likely it does not.
4. **(Deferred, fork B) TestLifter lift** of `*VisitorTests` example pairs into
   `Tests/Generated/SwiftInfer/RuleVisitor/`, reaching internal carriers via
   `@testable`. This, not measured-execution, is the real verify lever.

## 8. Decision

The rule-visitor carrier is **recognizable and high-coverage (124/149) but its
generic invariants are low-signal**, and its high-value invariant is per-rule
(TestLifter territory), not a generic law. **Default: build recognition only;
do not emit determinism invariants; revisit verify only via TestLifter (fork B)
if the dogfood owner wants per-rule regression capture.** Recognition is a clean
reusable asset; determinism verification is not worth the Daikon risk.
