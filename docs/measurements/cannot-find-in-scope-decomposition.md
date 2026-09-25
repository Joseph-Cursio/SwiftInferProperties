# What is behind *cannot find in scope*? — mostly `private`, again

> **Status:** `measured` · **As of:** 2026-09-24

The second-largest reason census 14 set a stub aside was the compiler's *cannot find 'X' in scope*: 84
stubs across nine repositories (51 in SwiftProjectLint, 59 `predicate`). Nobody had looked inside it.
Each stub was classified by where the missing name appears in it and where that name is declared, with
the stub's own `// Access:` header checked first.

## The answer

**53 of the 84 have a `private` subject, and the stub already says so.** The compiler's first error is
about a name it cannot see — the private subject's declaring type, or a type named in a receiver
construction beside it — rather than about access. This is the same mechanism
`held-receiver-laws.md` found behind 18 of 19 type-check timeouts, and it makes the census's `private`
bucket a floor again: **16 reported as `private`, and at least 18 + 53 more behind other first errors.**

| of 84 | cause | names |
|---:|---|---|
| **53** | `private` subject — `// Access:` header present | `Collector` (11), `SyntaxPattern`, `Parser`, `ClassRecord`, … |
| 15 | no generator — the type has a `.gen()` TODO and is not in scope either | `P256`, `LintIssue`, `State`, `Deque`, … |
| 5 | a receiver construction names a type from **another module of the package**, not imported | `PatternCategory`, `RuleDirectiveKind` |
| 4 | a receiver construction names a **test-support product** the stub's target does not depend on | `MockLSPConnection` |
| 3 | a **nested type spelled bare** in a receiver construction | `DeclarationShape.Parameter`, `TypeProperties` |
| 3 | a **test-local type** in a receiver construction (2 of them `private`) | `SkillAuthorMockBackend`, `MockInferenceBackend` |
| 1 | a generator helper **called but not declared** | `__genSyntaxStructure` |

## What this means

- **There is no large lever here.** The 31 stubs that are not `private` split five ways, and the
  largest actionable group is 5 stubs. Construction imports (5), nested spelling (3) and the dropped
  helper (1) are emitter-side and fixable, about 9 stubs, each with its next blocker unknown.
- **The test-local and test-support rows are partly a harness artifact.** The census compiles every
  stub in one consolidated test target, so a mock declared in another test target is never visible there;
  written into its own test target by the accept path, the internal ones would be.
- **`__genSyntaxStructure` has 4 stubs, 3 of them `private`**, so widening those subjects would expose the
  same missing helper — the render-not-derivation shape `kit-scaffold-conversion.md` recorded for
  `__genMesh`.

## Method, and its limit

A name was attributed to the receiver construction when it appears in the property closure before the
subject's call; its declaration was then located by a regex over the subject's tree, excluding `.build/`
and `Generated/`. **The regex found a test file first for `PatternCategory` and `Parser`, which was
wrong** — both were resolved by reading. Classification is per stub, first matching rule, header first.

## Acted on, 2026-09-24 — widened, and three fixes

**Widened, all but pbt-book** — 161 declarations across nine repositories, including the 104 private
subjects still waiting on a generator, so a later generator is the only step left for them. Widening a
method whose signature names another `private` type widened that type too (10 more). Every package
builds with its tests; no name collided.

**Three `swift-infer` fixes the widening exposed:**

- **A test's own type lent its initializer to a production type of the same name** — SwiftProjectLint's
  `private struct Collector` was handed `Collector(viewMode:)` from two test files declaring their own
  visitor. The harvester now ignores a construction whose file declares that type (11 stubs).
- **A construction's names now import their declaring module** when the test file reached them through
  an import the destination cannot make (`@testable import Core` → `SwiftProjectLintVisitors`,
  `SwiftProjectLintModels`; 10 stubs). `Parser` stays unfixed: it needs `SwiftParser`, which the nested
  package does not depend on — a manifest change in the subject, not an import.
- **`monotonicity` over a SwiftSyntax node is declined** — no node is `Comparable`, and the gate waved
  every unscanned type through (11 stubs, withdrawn rather than freed).

**Census 15 (the nine widened branches, fixed binary) against census 14:** compiles **531 → 563**, passes
**492 → 520** (behaviour 89 → 106), stubs 796 → 783. The prediction written first was +25 to +40.
⚠ SwiftProjectLint's branch is 10 upstream commits ahead of census 14's, so part of its +16 is those.
**Three newly reachable laws fail and all three are false** — idempotence of `sha256`, of a key-to-title
map, and of a URL derivation — the named mechanisms, no defect.

### Then: class receivers from an empty initializer

**32 of the 102 widened stubs still waiting on a generator were blocked by nothing but their class
receiver** — mostly SwiftProjectLint's cross-file visitors, each of which inherits
`required init(fileCache:)` from `CrossFileVisitorBase`, declared in another package where the
generator derivation never looks. `TrivialConstruction` now builds such a receiver from the first
accessible initializer up the superclass chain whose every argument has a default or an empty value
(`X(fileCache: [:])`), and a `SyntaxVisitor` subclass with none of its own gets `init(viewMode:)`.

**Census 16 against census 15, the same widened code:** compiles **563 → 600**, passes 520 → 557 —
SwiftProjectLint +35, SwiftUMLStudio +2, nothing down, failures unchanged. The prediction was +15 to
+30 against a ceiling of 32; it read +37 because a buildable receiver also let 7 more suggestions write
a stub. **All 37 new passes are "does not crash"** — behaviour stays at 106 — so this is reach, not
bug-finding. Not fixable this way: `ButtonAccessibilityChecker` (7, needs an `AccessibilityVisitor`
built from a pattern) and `YAMLConfig` (6, a parameterless initializer the kit rightly refuses as a
one-value domain).
