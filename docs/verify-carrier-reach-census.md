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

**So the concrete next measurement is a one-line split**: of the 22
`inverse-pair` entries, how many were demoted by `.unknown` rather than
`.notEquatable`? That number is the size of the lever, and it is cheap to get.
`EquatableResolver.curatedEquatableStdlib` already carries a road-test scar
showing the failure mode is real — `Data` classified `.unknown` and demoted a
flagship encrypt/decrypt round-trip until it was added to the curated set by
hand.

`predicate`, by contrast, is 117 entries of docstring-derived contracts with no
generic law shape behind them. Bigger bucket, much weaker claim to being
mechanically verifiable.

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
