# Verify carrier-reach census

**Date:** 2026-07-30 · **Corpus:** this repo's own SemanticIndex · **Status:** measured, two fixes shipped

The question this answers: *`verify` produced a verdict for only 14% of proposed
laws in `fixtures/verify-refutability`. Which layer is actually stopping it?*

The going assumption was **carrier support** — every seeded stub emitter declares

```swift
public static let supportedCarriers: [String] = ["Complex<Double>", "Double", "Int"]
```

and the plan built on it read: *"`String` and `[T]` are the obvious first
additions; they'd cover most of what the catalog actually proposes."*

**That was wrong on both counts.** `String` was already the single most common
carrier *and* already fully supported. Carrier accounted for 7% of declines, not
most of them. The measurement is below.

## Method

`buildStubBundle` is pure — it resolves the carrier, calls the strategist, and
composes stub source without touching the filesystem. So the whole index can be
swept in milliseconds instead of paying for one `swift build` per entry (the
survey that motivated this left **3.4 GB** of verify workdirs behind).

For each entry: call `buildStubBundle`, bucket the outcome by `VerifyError` case.

**The census measures an upper bound, not reach.** A synthesized stub still has
to compile. Both numbers matter and they are not the same number — see
[The trap in this method](#the-trap-in-this-method).

`supportedCarriers` turned out not to be the gate at all. It governs **Route 1**
only (`VerifyCommand+TemplateDispatch.swift`), the v1.46 hardcoded path for
`Complex<Double>` / `Double`. Everything else routes to `StrategistDispatchEmitter`,
which derives from `RawType` (15 stdlib types including `String`) or from an
indexed `TypeShape`. Reading the constant and believing it is what produced the
wrong plan.

## Result — `SwiftInferCore`, 104 entries

| | OK | unsupported-**template** | unsupported-**carrier** | other |
|---|---|---|---|---|
| as measured first, `allShapes` **not** threaded | 18 | 66 | 20 | 0 |
| with `allShapes` threaded (what the real command does) | 30 | 66 | **7** | 1 |
| after the `Self` rebinding fix | **36** | 66 | **1** | 1 |

Confirmed on the full 250-entry index (all of `Sources/`): 78 OK, **162**
unsupported-template (65%), 9 unsupported-carrier (3.6%).

### The first row is a harness bug, and it is the useful one

The first census called `buildStubBundle` without `allShapes`, whose default is
`[:]`. The real command passes `index.typeShapes` — 241 shapes. Threading it
moved 12 entries from "declined" to "fine" and cut the carrier bucket from 20 to
7. Had I stopped at the first row I would have "discovered" a carrier problem
two-thirds of which was my own harness, and then built generators for types that
already derive.

### What the remaining declines are

Of the 7 carrier declines before the fix, **6 were the single carrier `Self`**.

`Self.Index` and `Self.Element` were in `GenericBindingResolver.curatedBindings`;
bare `Self` was not — necessarily, because its binding is the *entry's owning
type* and so has no fixed right-hand side. A method like
`func merge(_ other: Self) -> Self` records `carrierTypeName: "Self"`, which
matches no `RawType` and no indexed shape and is declined — while its owner
(`Decisions`, `SemanticIndexEntry`, `VerifyEvidenceLog`, …) derives a generator
perfectly well under its own name for every other template.

The 7th is `SamplingSeed`, correctly declined with the `gen()` escape hatch named.

## The trap in this method

Rebinding `Self` took the carrier bucket to 1 and produced **zero new verdicts**.

All six entries then failed to *compile*. `resolveFunctionCalls` renders
`idempotence` with `receiverShape: false`, giving the static reference
`Decisions.merge` — which for an instance method is a curried
`(Decisions) -> (Decisions) -> Decisions` and does not coerce to the
`(Decisions) -> Decisions` the composer annotates. The existing self-returning
composer sidesteps this by chaining on the receiver, but it is gated on
`isNullary`, and `merge(_:)` takes an operand.

So the census's OK bucket is an **upper bound on reach**. It says the carrier
resolved and a stub was written; it does not say the stub compiles. Reporting
"36 reachable" off the census alone would have been wrong by six.

The second fix — an operand-idempotence emit shape, `a.f(b).f(b) == a.f(b)` —
closes it. All six now return a verdict.

## Is the new law refutable?

Six for six came back `bothPass`, which is exactly the pattern CLAUDE.md warns
about: these are *merge* functions, the collision-dependent family, and the
self-dogfood road test already measured `Decisions.merge` **commutativity** as
false-with-a-`bothPass`.

So the pass was checked rather than trusted. Mutating `Decisions.merge` to
accumulate instead of absorb:

```swift
// records + other.records, dropping the identity-keying
```

is **refuted at trial 0**, with a counterexample and an auto-derived regression
test. The law fails when it should. Reverted immediately; it is recorded here
because a passing property whose falsifiability was never checked is worth
nothing, per *"score refutability, not suggestion count."*

This does **not** upgrade the six passes to "the property holds" — the standing
`measured-bothPass` caveat applies unchanged.

## What this reprioritises

**Carrier support is finished as a lever on this corpus** — 1 of 104 entries,
correctly declined with the fix named in the error.

The constraint is **template reach: 65%**, and it is concentrated:

| template | entries (250-index) | verifiable? |
|---|---|---|
| `predicate` | 117 | no |
| `inverse-pair` | 22 | no |
| `differential-equivalence` | 2 | no |
| `input-totality` | 2 | no |
| `filter-subset`, `invariant-preservation` | 2 | no |

`predicate` alone is 47% of the index. Whether these *should* be verifiable is a
separate question from whether they *can* be — and the two biggest buckets
answer it differently.

### `inverse-pair` is a round-trip that lost a coin toss

`InversePairTemplate` fires on exactly the `f: T -> U` / `g: U -> T` shape
`RoundTripTemplate` wants, but only when `EquatableResolver` returns
`.notEquatable` **or `.unknown`** for `T` — round-trip's emitted property needs
`==`, so an unproven `T` is demoted to a Possible-tier informational claim.

Those two resolver verdicts are not the same situation:

- `.notEquatable` — genuinely cannot be checked with `==`. Correctly declined.
- `.unknown` — the resolver *could not tell*. The carrier may be perfectly
  `Equatable`; nothing was proven either way.

The verifier does not have to guess where the resolver couldn't: it compiles the
stub. An `.unknown` carrier that really is `Equatable` yields a verdict, and one
that isn't yields a build failure naming the missing conformance — which is a
better answer than the silent demotion, and the same "forward progress to the
next gap layer" this census got from rebinding `Self`.

**Measured 2026-07-30 — and the answer inverted the recommendation. The lever
was never built; what the measurement found instead was a bug, now fixed.**

The split is **22 `.unknown`, 0 `.notEquatable`**. Every owning type classifies
`.equatable` on its own name. So the lever looked real: 22 round-trips demoted
by a resolver that merely couldn't tell.

It is not real, and the reason is worth more than the lever would have been.

### 14 of the 22 are cross-type false pairings

The forward parameter type for 14 of them is the literal text `Self`.
`FunctionPairing.hasInverseTypeShape` compares type *text*:

```swift
if lhsReturn == rhsDomain, lhsDomain == rhsReturn { return true }
```

`Decisions.merge` is `(Self) -> Self`. So is `InteractionDecisions.merge`. So is
`VerifyEvidenceLog.merge`, `SemanticIndexEntry.updated(from:)`, and three more.
Every one of them string-matches every other one, so the pairing engine builds
the **complete graph** over six unrelated types — C(6,2) = 15 pairs, 14 of which
surfaced:

```
CROSS  Decisions.merge(_:)            <->  InteractionDecisions.merge(_:)
CROSS  Decisions.merge(_:)            <->  InteractionIndexEntry.updated(from:)
CROSS  Decisions.merge(_:)            <->  VerifyEvidence.merge(_:)
…14 total, 0 same-type
```

`Decisions.merge` is not the inverse of `InteractionDecisions.merge`. Nothing
here is an inverse of anything; a merge has no inverse at all.

**The `.unknown` verdict is the only thing holding these at Possible tier.**
"Fixing" `EquatableResolver` to resolve `Self` — in isolation — would promote 14
false round-trip claims to a stronger tier. That is the opposite of the intended
effect, and it is precisely the Daikon trap the PRD warns about.

### This exact pathology already has a precedent in the same file

`FunctionPairing.isPairable` vetoes result-builder methods, with this comment:

> *one builder becomes a clique under type symmetry — 16 of SwiftSyntaxBuilder's
> 23 suggestions came from one file this way, including `buildEither(first:)`
> proposed as the inverse of `buildEither(second:)`*

Same failure mode, different trigger: a textually-symmetric type spelling
generating a clique. It was closed there with a name-based veto.

### The actual fix is upstream, and it is the third face of one bug

Resolve `Self` to `summary.containingTypeName` in `transformationDomain` and in
the return type **before** the comparison. `Decisions.merge` becomes
`Decisions -> Decisions`, `InteractionDecisions.merge` becomes
`InteractionDecisions -> InteractionDecisions`, and they stop matching. All 14
disappear as suggestions rather than getting promoted.

Unresolved `Self` has now produced three distinct defects:

1. **carrier declines** — `unsupported-carrier: Self` (fixed above).
2. **cross-type false pairings** — 14 suggestions on this corpus (**fixed**, see
   below).
3. **`.unknown` Equatable verdicts** — which *masked* defect 2.

Fixing 3 without 2 would have made the tool worse. The order was 2, then 3.

### Defect 2 is fixed

`FunctionPairing.resolvingSelf(_:declaredIn:)` rewrites whole-word `Self` to the
declaring type's name before the type filter compares. `Decisions.merge` becomes
`Decisions -> Decisions`, `InteractionDecisions.merge` becomes
`InteractionDecisions -> InteractionDecisions`, and they stop matching.

Measured on `SwiftInferCore`, per template, before vs after:

| | before | after |
|---|---|---|
| `inverse-pair` | 14 | **0** |
| every other template | — | **unchanged** |
| total suggestions | 107 | 93 |

Exactly the 14, and `round-trip` stayed at 1 — nothing was promoted, which is
correct: these were never pairs. A fresh index drops 104 → 90 entries.

The nested spellings resolve too (`[Self]`, `Self?`, `Set<Self>`), and a genuine
same-type `Self`-spelled pair still pairs — both sides resolve to the same owner.
Inside a *protocol* extension `Self` denotes the conforming type rather than the
protocol, so rewriting to the protocol's own name is an approximation; it is the
conservative one, since same-protocol functions still match each other and
different protocols stop matching.

**Nothing in the 4,515-test suite failed on this change** — the cross-type clique
was entirely untested, which is why it survived. The new suite
(`FunctionPairingSelfResolutionTests`) pins the clique case at N=6 specifically,
so a fix that only separates two types would fail.

This also moves the census's own headline: with the 14 gone, `SwiftInferCore`'s
template-decline rate falls from 63% (66/104) to **58% (52/90)**. The
constraint is still template reach, and it is still mostly `predicate`.

### The other 8 — also fixed, and smaller than they looked

`[String]`, `[Suggestion]`, `URL?` — all `.unknown` by explicit design
("conditional-conformance reasoning is intentionally out of scope"), while every
element/wrapped type classifies `.equatable`.

**The count was inflated by the index being cumulative.** Once defect 2 was
fixed and `discover` re-run, the live population was **3**, not 8 — the index
retains entries from earlier runs, so reading a population off it overstates.
Read populations off `discover`, not off `.swiftinfer/index.json`.

`EquatableResolver` now gives `Array` and `Optional` their payload's verdict.
This is a rewrite rather than a judgement: both conform to `Equatable` under
exactly one condition — their single payload does. `Set` and `Dictionary` stay
`.unknown` because their conformances rest on *different* constraints (`Set`
needs `Element: Hashable`, `Dictionary` needs `Value: Equatable`), and tuples
are not nominal types and cannot conform at all. `.notEquatable` forwards too,
so `[Any]` and `((Int) -> Int)?` refute rather than merely going unknown.

Measured: `inverse-pair` on `SwiftInferCLI` **3 → 0**, `SwiftInferCore`
**unchanged**, and — the part that had to be checked — **nothing promoted at any
tier**. The three were type-legitimate but semantically empty
(`importsForComplexDouble([String]) -> String` paired against
`argumentLabels(String) -> [String]`), and `RoundTripTemplate`'s naming gates
decline them. So the rule removed three false suggestions and added none.

**The risk this had to clear was the opposite of defect 2's.** There, a resolver
fix in isolation would have *promoted* false claims. Here the danger was a
silent recall loss: if the gate defers a pair and `RoundTripTemplate` does not
claim it, the suggestion vanishes instead of strengthening.
`InversePairContainerHandoffTests` pins the handoff — a genuine `[String]`
encode/decode pair must return `nil` from `InversePairTemplate` *and* non-`nil`
from `RoundTripTemplate`.

`EquatableResolver.curatedEquatableStdlib` carries a road-test scar showing the
`.unknown` demotion is a real failure mode in general — `Data` classified
`.unknown` and demoted a flagship encrypt/decrypt round-trip until it was added
to the curated set by hand. The rewrite closes the container-shaped half of that
class of miss; a bare stdlib name still has to be curated by hand.

`predicate`, by contrast, is the **wrong example to hang this on**, and
`docs/predicate-display-order.md` corrects it. It is shape-derived — any
`Bool`-returning function — not "docstring-derived contracts" as this doc
originally said, and the law it proposes is *totality*. Verify declining that is
not a reach gap: there is no further law to measure, and `PredicateTemplate`
says so itself ("the one role in this catalogue that carries **no free law**").
The 65% headline stands; `predicate`'s share of it is not a deficit.

## Reproducing

The harness was a throwaway (it hardcoded an absolute index path) and is not
committed. To rebuild it: load an index via `IndexStore.load`, call
`SwiftInferCommand.Verify.buildStubBundle(entry:budget:allShapes:)` per entry —
**passing `loaded.index.typeShapes`, or the numbers are wrong** — and bucket the
thrown `VerifyError`.

## Shipped from this

- `GenericBindingResolver.bound(_:selfType:)` — contextual `Self` → owner rebinding.
- `StrategistDispatchEmitter.composeOperandIdempotencePass` — the
  `a.f(b).f(b) == a.f(b)` shape, gated on `parameterCount == 1`.

## Still open

- **The renderer describes the operand shape in unary terms.** A refuted
  operand-idempotence pick prints `Decisions.merge(Decisions.merge(input))` and
  `expected ≈ f(input)`; the operand appears only in the input line. Not wrong
  enough to mislead about the verdict, wrong enough to confuse a reader.
- **`Decisions` is reported as an "integer carrier — edge pass not applicable".**
  The edge-pass no-op message is picked by something other than the actual
  carrier. Related to the open edge-pass defect (`edgeTrials=0` on a binary law
  in `fixtures/verify-refutability`).
- **Two-operand methods** keep the old static rendering and its `build-failed`.
