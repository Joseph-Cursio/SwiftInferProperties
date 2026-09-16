# The missing generator — the funnel's largest blocker, measured (2026-09-16)

> **Status:** `measured` · **As of:** 2026-09-16
> **Instrument:** `swift-infer` at `56926b98`, the 19 repositories of [`corpus-funnel-census-2026-09-16.md`](corpus-funnel-census-2026-09-16.md)

The corpus funnel re-run moved the binding constraint from *no writer exists* to *does not
compile*. This asks what is behind that wall.

**It is the generator, and it is bigger than everything else measured this cycle put
together: 1,160 of 2,058 emitted stubs — 56% — carry at least one `.gen()` the tool could
not derive.**

Against the other causes from the same corpus: 666 name a type not in scope, 288 could not
infer a closure parameter (since fixed, #499), 132 are access-restricted.

## Why this was not measurable until now

The `.todo` marker has always been in the emitted text. What hid its size was ordering:
**a stub blocked on a missing generator usually failed on something else first.** #499 measured
269 of 288 closure-inference failures as also carrying a `.todo`, and fixing the annotation
changed their error to `type 'DoctorCommand' has no member 'gen'` — the true one. *A refuter
that fires first hides every refuter behind it*, paid again.

This census reads the marker at **emission**, so it needs no compile step and is not subject
to that ordering at all.

## 1. The shape of it

| | |
|---|---:|
| stubs emitted | 2,058 |
| stubs with ≥1 underived generator | **1,160 (56%)** |
| distinct types with no generator | **548** |
| stub-type pairs | 1,653 |
| covered by the top 10 types | 428 (26%) |

⚠️ **This is a long tail, and that makes it unlike every other defect measured this cycle.**
The import problem was 88% one repository; the identity collapse was 17 sites; the generic-parameter
gate was 50 rows. Here the ten most-wanted types cover a quarter of the population and 548 types
share the rest. There is no single fix with most of the value behind it.

**Most wanted:** `Syntax` 99 · `FunctionCallExprSyntax` 83 · `ExprSyntax` 56 ·
`FunctionDeclSyntax` 38 · `VariableDeclSyntax` 31 · `TypeSyntax` 30 · `ClosureExprSyntax` 27 ·
`AttributeListSyntax` 24 · `NonInjectedNondeterminismVisitor` 21 · `MemberBlockSyntax` 19.

**By repository:** SwiftProjectLint 595 · SwiftAssist 94 · SwiftPropertyLaws 87 ·
SwiftLintRuleStudio 83 · SwiftUMLStudio 83 · SwiftEffectInference 52 · the rest under 40.
SwiftProjectLint is 51% of the total, and it is a syntax-analysis tool, so its carriers are
SwiftSyntax nodes.

## 2. What kind of type has no generator

Classified against the corpus's own declarations, per stub-type pair:

| declaration | pairs |
|---|---:|
| class with a superclass or conformance | **482** |
| plain struct | **318** |
| plain class | 59 |
| enum | 27 |
| actor | 21 |
| `private` / `fileprivate` struct or enum | 14 |
| **declared nowhere the scan looked** (external) | **685** |
| stdlib / Foundation | 16 |

Two of those are not defects:

- **The 482 classes with a superclass** are genuinely underivable by a memberwise strategy —
  a `SyntaxVisitor` subclass has no memberwise init.
- **The 685 external types** are the dependency problem, and importing them is not enough:
  it needs a `.package` and product edge, which
  [`dependency-carrier-imports-scope.md`](../plans/dependency-carrier-imports-scope.md)
  scoped and declined. That decline rested on a population of 2 rows and is stale, but the
  concentration objection applies here too.

**The 318 plain structs are the interesting bucket**, because a memberwise struct is exactly
what `GeneratorResolver` exists to derive.

## 3. Why the plain structs fail — NOT ANSWERED, and the attempt is instructive

Two mechanisms are visible by reading:

- **A single unknown leaf.** `SwiftAssist.RunGate` is `struct RunGate: Sendable, Equatable`
  with `let minimumInterval: Duration`. `Duration` is in neither `RawType` nor the kit's
  composed-generator set, so one member blocks the whole struct.
- **A tree of project types.** `DocCResponse`'s members are `DocCSchemaVersion`,
  `DocCIdentifier`, `DocCMetadata`, `[DocCInlineContent]?` — derivable only if all of those are.

⚠️ **An attempt to measure the split failed, and the failure is the point.** Walking each failing
struct's stored members with a regex reported `some` and `View` among the "leaf types blocking a
struct" — because `var body: some View` is a **computed** property and the pattern took it for a
stored one. It left **119 of the failing structs with no blocker it could see at all**.

That is *a measurement that pattern-matches on text measures the text*, and it is the wrong
instrument by construction: the question is what `GeneratorResolver` decided, and the only
authority on that is `GeneratorResolver`.

**One hypothesis WAS testable and is refuted.** The resolver refuses an ambiguous bare name —
*"Two or more distinct types share this bare name … Refusing keeps the referencing type at
`.todo`"* — and plausible-looking names (`TypeShape`, `Node`, `Collector`, `Kind`) are in the
failing set. Measured: **9 of 548 distinct failing types are declared more than once**; 379 are
declared exactly once and 160 not at all. Ambiguity is not the cause.

## 4. What to do next, and what not to

**The next step is a probe that asks `GeneratorResolver` directly** — build it over a corpus's
scanned `TypeShape`s and record, per failing type, which branch returned `nil`:
ambiguous name, no shape, or a failure inside `derive`. The resolver currently reports no
reason, so the probe either reads its branches or the resolver learns to say. That is the
difference between 548 unexplained types and a ranked list of causes.

⚠️ **Do not reach for the head of the list.** The ten most-wanted types are SwiftSyntax nodes, and
a hand-written generator for `ExprSyntax` would serve one repository that happens to be 51% of
this corpus. The long tail is the finding; a fix aimed at the head would move this census and
not the general case.

⚠️ **`Duration` is worth checking on its own terms** — it is a stdlib type, it is not in
`RawType`, and adding it is the kit's call rather than this repository's. Its population here
is small and was measured by hand, not counted.
