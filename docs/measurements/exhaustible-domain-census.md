# Should the catalogue EXHAUST a small domain instead of sampling it?

> **Status:** `measured` · **As of:** 2026-09-19

Prompted by reading how two Apple repositories test without random generators, and by noticing
this repository had already met the same fact from the other side.

> **Answer: mostly NO — the population is 30 refutable rows — but the reason to want it is not
> the population.** Exhausting a domain changes what a pass MEANS: `measured-bothPass` becomes a
> statement about the whole domain rather than about 1,000 draws from it. Two narrow exceptions
> are worth taking; the general machinery is not.

## The population

Measured over the `seed-index.json` files of the 2026-09-19 corpus run. A domain counts as
*enumerable* when every parameter is `Bool` or a payload-free enum recorded in `typeShapes`.

| | count |
|---|---:|
| index entries with parameters | 5,127 |
| every parameter enumerable | **115 (2%)** |
| — of which `determinism`, the tautology | 85 |
| — `monotonicity` | 24 |
| — `predicate` | 6 |
| **refutable AND exhaustible** | **30** |

**The 85 determinism rows are worth nothing exhausted.** `f(x) == f(x)` is true of every
implementation that type-checks, so proving it over a whole domain proves nothing that sampling
did not already fail to prove. Quoting 115 would be quoting the tautology.

Domain sizes are tiny — most are between 1 and 8 total combinations:

| combinations | entries |
|---:|---:|
| 1 | **10** |
| 2 | 15 |
| 3 | 36 |
| 4 | 14 |
| 5–8 | 22 |

## Why the small population is not the point

CLAUDE.md is explicit that **`measured-bothPass` means *no counterexample in the generated
domain*, not *the property holds***. For a domain of three cases, that caveat is removable: a law
checked against all three IS a statement about the property, not a sample of it.

So the gain is a **change in the kind of verdict**, not a larger number of them. This repository
has no other lever that does that.

## ⚠ The same fact is already treated as a nuisance elsewhere

`KitSuiteEmitter+GeneratorShaping` **suppresses** `Hashable.distribution` for `CaseIterable`
carriers, because *"1000 samples produced only 25 unique hashValues"* — the domain is smaller than
the trial budget, so the law is *"degenerate here by construction, not failing"*.

That is this census's finding, met from the opposite direction and handled by silencing the law.
One template — `caseiterable-key-injectivity` — already emits an exhaustive loop instead. **The
instinct exists in the codebase twice and is generalised neither time.**

## ⚠ A law over one value is a unit test

**10 entries have a domain of exactly one combination.** Drawing 1,000 samples from a single-case
enum produces 1,000 identical values and reports them as 1,000 trials, which reads as evidence it
is not. That is a reporting defect independent of whether anything is ever exhausted.

## What the two Apple repositories do, and why it fits

Neither reaches for a random generator, and they diverge exactly where the domain does:

| repository | method | count | when it applies |
|---|---|---:|---|
| swift-collections | `withEvery…` exhaustive enumeration | **1,055** uses | the domain is small and structured |
| swift-syntax | `assertParse` over literal and on-disk source | **3,422** call sites | the domain is huge and structurally constrained |

swift-syntax's round-trip property — `Parser.parse(source:).syntaxTextBytes == fileContents`,
asserted over files — is a real property with a **corpus** for a domain rather than a generator.
Only 8 of its test files mention randomness at all, and the one that generates edits is disabled
by default, enabled by hand.

**This independently confirms `generator-blocker-reasons.md`'s largest bucket.** The 393 markers
asking for a generated `Syntax` / `ExprSyntax` / `FunctionCallExprSyntax` want something the
authors of SwiftSyntax deliberately do not do — a randomly assembled tree is mostly not a tree any
parser would produce.

Our catalogue has only the middle strategy: sample a generated domain.

## Recommendation

**DECLINE the general `withEvery` machinery.** 30 refutable rows does not justify it, and this
project's measured ~5:1 decline-to-rows ratio makes 30 an optimistic ceiling rather than a
forecast.

**Two narrow things are worth doing**, both cheap:

1. **Emit an exhaustive loop when every parameter is enumerable and the product is small.** The
   emitter already does this for `caseiterable-key-injectivity`, so it is a render, not a
   derivation — the same shape as the four render-not-derivation fixes in
   `kit-scaffold-conversion.md` and `generator-blocker-reasons.md`.
2. **Decline, or mark degenerate, a law whose domain has one member**, the way
   `StubApplicationArity` already declines other unbuildable shapes. 10 rows, and it removes a
   misleading trial count rather than adding a law.

## What would reverse this

A corpus whose enumerable domains are refutable rather than tautological — the ratio here is 30
refutable against 85 tautologies, and it is the tautologies that dominate. A catalogue with more
templates over small enum domains would change that split.

Re-run: read `typeShapes` and `entries[].parameterTypeNames` from any `seed-index.json` set; a
domain is enumerable when every parameter is `Bool` or an enum whose cases carry no associated
values.
