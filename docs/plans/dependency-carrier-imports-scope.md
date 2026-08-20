# Scope: importing a dependency-declared carrier into a verify stub

> **Status:** `open` · **As of:** 2026-08-09

**Status: scoped, not built.** The measurement that motivates it is done and is in
`docs/measurements/roadtest-self-dogfood-2026-08-08.md` §9; this is what closing it would take,
and what would make it not worth closing.

## 1. What is blocked, measured

`--scan-dependencies` records shapes for types declared in `.build/checkouts/*/Sources`.
One binary, one flag, in the package proper (a fresh `git worktree` has no `.build` and the
scan reports that now):

| | control | `--scan-dependencies` |
|---|---|---|
| indexed shapes | 283 | **2,315** |
| `unsupported-carrier` | 5 | **3** |
| `build-failed` | 0 | **3** |
| Proven | 84 | **84** |

Both remaining genuine generator gaps moved:

```
? EffectResolver   predicate  carriesInformationUpward(_:)  (unsupported-carrier: Effect)
· EffectResolver   predicate  carriesInformationUpward(_:)  (build-failed: cannot find type 'Effect' in scope)

? SetAlgebraShape  predicate  isSelfTypedBinaryOp(_:)       (unsupported-carrier: FunctionSummary)
· SetAlgebraShape  predicate  isSelfTypedBinaryOp(_:)       (build-failed)
```

**The constraint moved from the kit to us**, for the third time in this document's history
(§8.3.3, §9.4, and now). The strategist can derive these carriers; the stub cannot name them.

## 2. Why the current skip is not a bug

`VerifyImportSet.modules` already consults the declaration-site map and skips a type whose
site resolves to no module. Its justification named dependency checkouts explicitly and was
**true when written** — nothing put dependency types in the index, so a checkout type really
was unreachable. `--scan-dependencies` invalidated the premise for exactly the population it
introduces. The sentence is corrected in place; the behaviour is not, because changing it
alone makes things worse (§3).

## 3. Two halves, and the first alone is a regression

**(a) Resolve the module.** Map `.build/checkouts/<Checkout>/Sources/<Module>/…` → `<Module>`
in `VerifyTargetInference`. Small and well-defined.

**(b) Give the stub a product edge.** `@testable import <Subject>` does **not** re-export the
subject's dependencies, so `import SwiftEffectInference` fails at *manifest* resolution, not
at type lookup. The stub package needs its own `.package(url:…)` plus a `.product(…)` entry.

Doing (a) without (b) emits an import the manifest cannot satisfy: the entry still fails, with
a *worse* error — `no such module` instead of `cannot find type 'Effect' in scope`, which at
least names the type a reader would search for. **A change that trades a specific build error
for a vaguer one is a regression even though it looks like progress.**

## 4. What must be decided before building (b)

1. **Is the module vended by a product?** The index now names every module in every checkout,
   including internal targets nobody can depend on. A module that is not a product cannot be
   imported however the manifest is written, so the resolver must distinguish *not a product*
   from *product we failed to find* — the same absent-vs-unreadable distinction the
   2026-08-09 sweep spent its day on.
2. **Which version?** The stub must resolve the *same* version the subject compiled against or
   the generator may be derived from one shape and executed against another. The subject's
   `Package.resolved` is the source of truth and re-resolving is not equivalent.
3. **Identity collisions.** `#169` already records that collapsing a URL dependency into a
   corpus can repeat a product edge. Adding arbitrary dependency edges multiplies that surface.
4. **`DependencyTypeShapes` records shapes from checkouts that are NOT the subject's direct
   dependencies** — anything under `.build/checkouts`, including transitive ones. A stub may
   not legitimately depend on those at all.

## 5. Is it worth it

**Measured population: 2 rows.** `Effect` and `FunctionSummary`, on `SwiftInferCore`.

Against that, §9.6.1's standing result: five consecutive gap-closures on this corpus moved
fourteen rows and produced **three** executing laws, because each cleared gap revealed a
second blocker. The base rate says these two rows are more likely to reach a *third* blocker —
the generated call itself, or a member type that is `internal` in the dependency and therefore
unreachable even with the import — than to reach Proven.

So the honest expected value is **low**, and the reason to do it anyway would be that
`unsupported-carrier` and `build-failed` are both wrong labels for *"the stub is not allowed to
import this"*, which is a third thing. That is a reporting argument, and reporting is cheaper
than plumbing: a decline that said *"carrier declared in dependency module `X`, which the
verify stub does not import"* would close the explainability gap without any manifest work.

**Recommendation: build the report, not the import.** Revisit (b) if a corpus appears where the
population is large — a package whose laws are mostly about its dependencies' types would
invert this arithmetic. (falsifier: `VerifierWorkdir.dependencyProductEdge`)

## 6. What would falsify the recommendation

A corpus where dependency-declared carriers are a **double-digit** share of declines, measured
the same way (one binary, one flag, in the package proper, index deleted between arms).
`swift-collections` and `swift-async-algorithms` are poor candidates — they are leaf-ish. An
app target depending on several first-party frameworks is the shape that would show it, and
`MacCloud_client_iOS` is the fixture already on hand.


## 7. `FunctionSummary` — a second route, investigated and also declined (2026-08-10)

§5 recommends against the product edge at a population of 2 rows. One of those two,
`FunctionSummary`, has a **cheaper-looking route that does not need the edge at all**, and it
is worth recording why that is also declined rather than leaving it to be rediscovered.

### The observation

`FunctionSummary` is blocked by `declaredEffect: Effect?` and `inferredEffect: Effect?`, both
of which are **stored properties whose initializer parameters carry `= nil` defaults**. A
generator does not have to supply them. `FunctionSummary(name:parameters:…)` compiles without
either, so the carrier is derivable **without `Effect` ever being generated** — no product
edge, no import, no manifest work.

### Why it is not cheap

Neither `IndexedTypeShape.InitializerParameter` **nor the kit's `PropertyLawCore.InitializerParameter`**
records whether a parameter has a default. Both are `(label, typeName)`. So closing it needs:

1. the scanner to capture `defaultValue` from SwiftSyntax;
2. our mirror to carry it (additive schema change, `decodeIfPresent`);
3. **the kit's `initializerBasedStrategy` to skip a defaulted parameter it cannot derive** —
   which is work in SwiftPropertyLaws, not here.

That is a cross-repo feature, strictly more expensive than §3's product edge, which is
single-repo.

### The population, stated in both forms because they differ by two orders of magnitude

| | count |
|---|---|
| `public init`s in `Sources/` with at least one defaulted parameter | **91 of 310 (29%)** |
| …where a defaulted parameter's type is **underivable**, i.e. the rule would change anything | **1** |

**The 29% is not the reachable population and must not be quoted as one.** Most defaults are
`Int`, `[String]`, `Bool` — types that derive fine, so skipping them changes nothing. The rule
only bites when the defaulted parameter's type is one the strategist cannot generate, and on
this corpus that is `FunctionSummary` alone.

### The route that must NOT be taken

Generating `Effect?` as **`nil` only** would derive `FunctionSummary` today, single-repo, with
no schema change. It is rejected: a nil-only optional is a **degenerate domain**, and the
standing rule is that *`measured-bothPass` means no counterexample in the generated domain, not
that the property holds*. Any law keyed on a function's effect would pass without ever being
tested, and pass *silently* — the exact shape §8.6 records for `booleanStem`, where a `String`
generator that never drew an English boolean prefix made the failing branch unreachable.

A generator that cannot fail is worse than a decline, because a decline is legible.

### Recommendation

**Do not build.** Same arithmetic as §5, worse cost: cross-repo instead of single-repo, for one
row, and that row's law is `isSelfTypedBinaryOp` — a two-comparison `predicate` totality claim
on a function whose body is `paramType == "Self" && returnTypeText == "Self"`.

**Revisit if a corpus shows a double-digit count in the second row of that table**, not the
first. The kit-side half would be worth proposing on its own if SwiftPropertyLaws sees the same
shape from other consumers — it is a reasonable capability, just not one this repo's evidence
justifies asking for. (falsifier: `SwiftPropertyLaws/InitializerParameter.hasDefault`)
