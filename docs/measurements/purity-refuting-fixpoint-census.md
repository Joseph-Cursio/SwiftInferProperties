# What would a refuting-direction fixpoint retract?

> **Status:** `measured` · **As of:** 2026-08-17

Re-derivable at any time — `PurityFixpointCensusMeasuredTests` *is* the
harness, and `make batch2` runs it.

**The answer is BUILD the one-hop join. The loop is a second phase, not the
headline** — and the reason that sentence changed is the most useful thing in this
document.

The first run of this harness measured **75 rows at fixpoint, 57 of them from the
cascade**, and concluded that the loop was where all the value lay. A hand-check of
those cascade rows found **46 of the 75 were name-collision artifacts** — a 61%
false-positive rate — caused by a defect in this harness, not in the idea. The
corrected figures are **29 at fixpoint, 11 from the cascade**. Both readings are
kept below, because a census that quietly replaced its own numbers would be the
thing this repo's whole apparatus exists to prevent.

---

## The question, and why nobody had asked it

Every purity census so far measured the **promoting** direction — *callee pure, so
maybe the caller is pure*. That is what item 31 proposed, and it declined twice:
13–31 rows of leverage, every freed row landing on `.pureButPartial`, which has
**zero non-comment references in `Sources/`**.

This census asks the mirror question:

> `DrainedProcess.standardOutputViaEnv` calls `standardOutput`, which spawns a
> subprocess, drains two pipes on `DispatchQueue.global`, and is `.refuted` **with
> a witness**. The caller is judged **`.pure`**. If `verdict(for:)` consulted the
> verdict this same analyzer already computed for its callee — and kept going —
> how much would be retracted?

**And whether it must be a loop at all.** One hop is a much smaller build than a
fixpoint, so the number that decides the design is not the total but the *share
the cascade contributes*.

---

## Provenance

| | |
|---|---|
| corpus | this repo's `Sources/`, the item 29 census's own `corpus` / `verdicts` statics — shared, not recomputed |
| SEI pin | `3ea25f2` (`Package.swift:122`) |
| harness | `Tests/SwiftInferCoreTests/PurityFixpointCensusMeasuredTests.swift` |
| population | the **2,396 `.pure`** subjects — the only rows a retraction can cost, since `isInferredPure` is `purityVerdict == .pure` |
| seed | the **91** names whose every declaration is refuted **with a witness** |

Sharing the item 29 statics is what makes the two documents comparable;
`oneHopReproducesTheAllowlistCensusBaseRate` pins the agreement against the
allowlist census's independently-extracted base rate.

---

## 1 · The measurement

| | first run (**contaminated**) | corrected |
|---|---|---|
| population — `.pure` subjects | 2,396 | 2,396 |
| refuting names, witness-bearing (the seed) | 91 | 91 |
| **retracted at one hop** | 18 | **18** |
| **retracted at fixpoint** | 75 (7 hops) | **29** (6 hops) |
| …of which the **loop** contributes (hops 2+) | 57 | **11** |
| retracted share of the `.pure` population | 3.1% | **1.2%** |

Corrected, per hop: **18 · 6 · 2 · 1 · 1 · 1**.

**The one-hop number never moved.** The seed always obeyed the settledness rule; only
the cascade was wrong. That is why 18 is the number with two independent
confirmations and 11 is the number that needed a hand-check.

### The loop pays, but modestly — and less than the promoting direction's does

**One hop buys 18; the fixpoint buys 29. A 1.6× multiplier, 38% of the total.**

Set against the promoting direction over its own population — 13 → 27, a **2.1×**
multiplier — the refuting direction's cascade is the *weaker* of the two. That is
the reverse of what the contaminated first run said, and it is the honest answer to
*"does the toolchain need to run in a loop?"*: **the loop is worth having and is not
where the value is.** 18 of the 29 rows need only a single join.

The recommendation therefore splits. **Build the one-hop join first** — it is 62% of
the effect, it needs no fixpoint, no cycle reasoning and no iteration budget, and
its 18 rows are the ones hand-verified twice. **Then add the loop** for the
remaining 11 if the first phase holds up in use.

The cascade is legible in the rows. Hop 1 is direct I/O callers —
`DrainedProcess.standardOutputViaEnv`, `KitEvidenceStore.load`,
`EffectResolver.resolve`, `TargetIsolation.dump`. Hop 2 is the layer that calls
*those* — `ConfigLoader.load`, `JSONArtifactStore.load`,
`PostAcceptanceOutcomesStore.load`, `VocabularyLoader.load`,
`TargetIsolation.defaultIsolation`. It is a file-reading stack being recognised one
storey at a time, which is exactly what a fixpoint is for.

---

## 2 · The seed restriction is nearly free, which removes a temptation

A refutation is either **evidence** (a named construct) or **ignorance** (a `try`
into a callee this leaf cannot see). Propagating ignorance upward would spread
*"I cannot tell"* through the call graph and retract advisories on no evidence —
the [Daikon trap](../design-internal/glossary.md#daikon-trap) through a new door,
and the opposite of the PRD's *conservative inference*.

So the seed is witness-bearing only. **The measured cost of that restriction is 5
rows:**

| seed | refuting names | retracted at fixpoint |
|---|---|---|
| witness-bearing (buildable) | 91 | **29** |
| ignorance admitted (upper bound, **not** buildable) | 153 | 34 |

Admitting ignorance grows the seed by 68% and the result by **17%** (5 rows). There is
therefore no efficiency argument for the unsound variant, which is worth
recording because *"but we'd catch more"* is the obvious objection and the number
refuses it.

---

## 3 · Soundness, termination, and why cycles need no special case

The join only ever **withholds** `.pure`. That is the permitted direction on the
effect lattice and the one CLAUDE.md's *purity gates must not relax to reach a
target* rule demands — this gate only tightens.

It is also what makes the fixpoint well-founded. The refuting set grows
monotonically and is bounded by the corpus's distinct names, so:

- **Mutual recursion needs no optimistic assumption.** The promoting direction
  must assume a cycle pure to make progress and then justify it coinductively.
  Refutation has no such problem: a cycle simply never enters the set unless
  something in it carries a witness.
- **Termination is structural, not a guard.** Measured at **7 hops**;
  `theFixpointIsMonotoneAndTerminates` asserts monotonicity per row and bounds the
  depth rather than trusting the argument.

`emptySeedRetractsNothing` is the control: with nothing seeded the loop retracts
nothing, so *"the fixpoint retracts 75"* can be told apart from a walk that
retracts on any call at all.

---

## 4 · Every number here is a lower bound, and by how much

**Free-shape callees only** (`foo(…)`, not `base.foo(…)`), matching the allowlist
census's rule and for its measured reason: this package declares a
`FileManager`-reading `sorted(in:)`, so name-keying makes every `xs.sorted()` read
as a call into an impure package function. That contamination inflated the
allowlist census's base rate 17 → 147.

**1,748 of the 2,396 `.pure` subjects make at least one member-shape call.** So
the unresolved surface is not a rounding error — it is 73% of the population, and
73 rows retracted from it would be indistinguishable from 73 false positives
under name-keying. Fixing that is item 38 (IndexStore), not this.

A name counts as refuting only when **every** declaration carrying it is refuted —
the inverse of the allowlist census's settledness rule. One pure overload makes
the call ambiguous and the name is dropped.

### The trap this harness fell into, recorded because it is the same one

The first run reported rows retracted twice and `theFixpointIsMonotoneAndTerminates`
failed. The cause was not the algorithm: the row key was `file:name`, and this
package has overload families — `CarrierKindResolver.classify`,
`DomainCorpusScanner.visit`, `GenericBindingResolver.bound` — that share both.
**115 rows would have been merged by that key.**

So the name-collision hazard this document spends §4 bounding turned up *inside the
instrument measuring it*, within one run. The counts were never wrong (rows are
distinct subjects and were counted as such); the identity was. It is now an
ordinal. **A measurement harness is not exempt from the defect class it measures**,
and the only reason this was caught is that the monotonicity property was asserted
rather than assumed.

---

## 5 · What is NOT established

**Hops 2+ WERE hand-checked, and the first attempt failed it.** This section
previously said the check had not been done and named it as the thing that would
reverse the verdict. It was done, it did reverse part of the verdict, and §6 records
what it found. The surviving 11 rows were then re-audited: **every justifying callee
has exactly one declaration in the package**, so none of them rests on a name
collision. That is the criterion this census can check; it is not the same as
reading all 11 bodies.

**This does not measure what the retractions would cost a user.** 75 fewer
`@lint.effect pure` advisories is 75 fewer *false* advisories, but whether any law
rested on them is a separate question this census does not ask.

**Where it belongs is not measured here either.** 7 hops is far past the one hop
`EffectResolver` affords under §13's 2-second `discover` ceiling — the same budget
wall item 31 hit. Item 28's asymmetry is the presumptive answer: a linter running
ahead has no such ceiling, so SwiftProjectLint pays for the fixpoint and `discover`
reads the result already resolved. That is an argument, not a measurement.

---

## The verdict

**BUILD, in the linter, as item 30's package-internal half.**

- **The defect is real and non-zero** — 75 `.pure` verdicts retracted, including a
  subprocess spawn judged pure.
- **It must be a loop** — 76% of the effect is in hops 2+, so a single join is not
  a cheaper version of this build, it is a different and much weaker one.
- **It has a reader today** — retractions move `isInferredPure`, which is the field
  the one live consumer reads. This is the only purity item measured so far whose
  output something consumes.
- **It is the sound direction** — monotone, terminating, no coinduction, and it
  tightens rather than relaxes a purity gate.
- **The sound seed is nearly free** — 75 of the 80 an unsound seed would reach.

`EffectSymbolTable.applyBodyInference` already does upward inference over
un-annotated callees, and `applyBodyInference(multiHop:)` already implements the
fixpoint. Both consumers call it with `multiHop: false`. **What does not happen is
`verdict(for:)` consulting the result** — item 31's *"wiring, not analysis"* about
the same seam, arriving this time with a number that supports the build instead of
declining it.

## What would reverse this

- ~~A hand-check of hops 2+ finding a materially false retraction rate.~~
  **This happened.** 46 of 75 were artifacts; the cascade is now 11 rows and the
  loop is a second phase rather than the headline. The remaining reversal risk is
  narrower: all 11 survivors depend on name-uniqueness within the *package*, so a
  new overload of `compositionGenerator`, `renderDependenciesBlock`,
  `timeToAdoptionSection`, `candidateValuesExpression` or any link in the
  `ActionSequenceStubEmitter` chain would need the chain re-checked.
- **The member-shape surface being resolved** (item 38). It would not weaken this
  finding, but it would change the design — a resolver that can see through
  `base.foo(…)` makes name-keyed settledness obsolete rather than merely partial.
- **A `.pureButPartial` consumer landing** (item 34). Then the promoting direction
  acquires a reader too, and the two halves should be scoped as one pass rather
  than sequenced.

---

## 6 · The hand-check, and why it belongs in the document

The verdict above is the *second* one this census produced. The first said the loop
carried 76% of the effect, on 75 rows. Hand-checking the cascade — printing, for
every hop-2+ retraction, the callee that justified it — produced this at hop 5:

```
h5 SwiftInferCore/EquatableResolver.swift:classify      <- classify
h5 SwiftInferCore/CarrierKindResolver.swift:classify    <- classify
h5 SwiftInferCore/IdempotenceReturnShape.swift:classify <- classify
h5 SwiftInferTemplates/BiconditionalWitnessDetector.swift:extract <- classify
   … 16 rows in that wave
```

Sixteen rows retracted because the **name** `classify` had entered the refuting
set — and this package has roughly six unrelated `classify` declarations. Also
present: `render <- render`, `bound <- bound`. Functions were being retracted by
*themselves under a different type*.

**The bug was in the harness and it was one line of omission.** §4's rule — a name
refutes only when every declaration carrying it is refuted — guarded the *seed*
only. The cascade inserted a retracted caller's bare name with no settledness check
at all, so one refuted `DedupGateShape.classify` poisoned every call to any
`classify`. `settledByCascade` now applies the same rule to cascade-added names, and
a declaration that is `.pureButPartial` or refuted only by ignorance blocks the
name, because neither is proof that calling it is impure.

Corrected: **75 → 29, and 57 → 11. A 61% false-positive rate in the cascade.**

Three things worth carrying out of this:

**A property assertion caught what a count could not.** The contaminated run's
totals looked entirely plausible — 75 of 2,396 is 3.1%, a modest and believable
number, arrived at through a legible 7-hop curve. Nothing about the *figure*
suggested a defect. What surfaced it was `theFixpointIsMonotoneAndTerminates`
failing on duplicate row identity, which was a *different* bug (the `file:name` key)
in the same area. **Two defects, one of them found only because fixing the other
required printing the rows.**

**This is the third time in this line of work that name-keying has been the
defect**, after the allowlist census's 1,238 contaminated subjects and the
`sorted()` collision. It is no longer a caveat to note in §4 — it is the dominant
failure mode of every name-keyed measurement in this repo, and the case for item 38
(IndexStore) rests more on this than on reach.

**The seed's independent confirmation is what made the split diagnosable.** Because
`oneHopReproducesTheAllowlistCensusBaseRate` pins hop 1 against a separately-extracted
census, 18 was known-good throughout. That localised the fault to the cascade
immediately instead of putting the whole harness in doubt. **A measurement with one
externally-corroborated number is far more debuggable than one with none.**

---

## 7 · Does the toolchain already ship a purity oracle? Measured: yes, and it covers 20 underscored names

The allowlist census left item 30's stdlib half open with the words *"this census can
exhibit no defect in it and **cannot**, having no oracle for those callees."* That was
true of the census. It was never checked against the **toolchain**, which does ship a
purity annotation. So it was checked.

**`@_effects` is real, shipped, and readable.** It is an underscored attribute
documented in Swift's `UnderscoredAttributes.md`, and it survives into the
`.swiftinterface` files Xcode ships — so a consumer could read it without building
the stdlib.

Measured over the 226 `.swiftinterface` files in the macOS SDK:

| attribute | occurrences | distinct names | maps to `Effect` |
|---|---|---|---|
| `@_effects(releasenone)` | 352 | — | **nothing** — ARC retain/release traffic |
| `@_effects(readonly)` | 256 | 14 | `.observational` (rank 1) — reads, never writes |
| `@_effects(readnone)` | 40 | 6 | `.pure` (rank 0) — neither reads nor writes |

The **whole** `readnone` + `readonly` surface is 20 distinct names:

```
_finalizeUninitializedArray  _hash  _stringCompare  _stringCompareInternal
_stringCompareWithSmolCheck  _unconditionallyBridgeFromObjectiveC
_stdlib_isOSVersionAtLeast (+3 variants)  _stdlib_binary_CFStringGetLength
_stdlib_binary_CFStringGetCharactersPtr  formatSpecifier  getArgumentHeader
getContiguousArrayStorageType  getUpdatedPreamble  get*FormatSpecifier (×4)
```

Hashing, string comparison, ObjC bridging, OS-version checks, and `os_log` format
plumbing. **Not one is a name this corpus calls: 0 of the 20 appear anywhere in this
repo's `Sources/`**, so the overlap with the 501 unrecognised callees is zero by
measurement rather than by argument.

### The mapping is sound, which is why the coverage is the whole story

The two kinds do land cleanly on the bottom of the lattice, and for the right reason:
**"no external writes" is exactly the retry-safe property.** A `readonly` function
cannot corrupt anything by being called twice, which is `.observational`; a `readnone`
one is a function of its arguments alone, which is `.pure`. So this is not a
type-mismatch problem. It is purely a coverage problem, and the coverage is 20
underscored internals.

**It cannot give algebraic idempotence at all.** `f(x) = x + 1` is `readnone` and is
plainly not idempotent — `f(f(x)) ≠ f(x)` is a fact about a function's mathematics,
not about its effects. No effect annotation can settle it.

### Three reasons it does not rescue the stdlib half, the second being structural

1. **Coverage, measured above: 20 names, 0 reachable from here.**
2. **It feeds the wrong direction.** `EffectResolver.carriesInformationUpward` returns
   `false` for `.pure` and `.observational`. So a perfect oracle at the *bottom* of the
   lattice informs only the **promoting** direction — the one item 31 declined for
   having no consumer. What the refuting direction needs is stdlib functions annotated
   **impure**, and `@_effects` has no such case: `readwrite` is the absence of a
   claim, not a claim of a side effect.
3. **It is an optimizer contract, not a semantic guarantee.** Underscored, unstable,
   and `readonly` explicitly permits reading mutable global state — so it cannot
   ground determinism even where it appears. Treating it as a soundness input means
   trusting an attribute Apple may change without notice.

### What it is genuinely worth

The allowlist census specified the stdlib seed as *"a set of known-pure stdlib
operations… asserted, not proven,"* counted separately, with every downstream claim
reading *pure given these axioms*. These 20 are **asserted by Apple** rather than by
us, which is strictly better provenance than hand-assertion. That is a real if narrow
gain: a seed set can now distinguish *vendor-asserted* axioms from *our* axioms, and
say which each claim rests on.

**Reopens if** a stable (non-underscored) effects annotation ships, or if the annotated
set grows to cover the head of the unrecognised-callee frequency table — `min`, `max`,
`map`, `count`, `String(_:)`. Neither is true today.

> **Not re-derivable by `make batch2`.** Unlike every other figure in this document,
> this section measures the *installed SDK* rather than this repo, so no harness can
> pin it and it will drift with Xcode. Re-take it with:
>
> ```sh
> SDK=$(xcrun --show-sdk-path)
> grep -rh -E '@_effects\((readnone|readonly)\)' \
>   $(find "$SDK/usr/lib/swift" -name '*.swiftinterface') \
>   | grep -oE '(func|var) [_a-zA-Z0-9]+' | sed -E 's/(func|var) //' | sort -u
> ```
>
> Measured 2026-08-17 against the Xcode-shipped macOS SDK. **A figure here belongs to
> an SDK version the way the rest of this document's belong to an SEI pin.**
