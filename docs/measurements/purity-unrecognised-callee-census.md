# What does an unrecognised callee cost?

> **Status:** `measured` · **As of:** 2026-08-17

Re-derivable at any time — `PurityAllowlistCensusMeasuredTests` *is* the harness,
and `make batch2` runs it.

Answers open-threads item 30, and the answer **splits the item in two**: one half
has a measured defect and a cheap fix, the other has no measured defect and an
expensive one. Building item 30 as filed would pay the expensive half's price to
fix the cheap half's problem.

---

## The question

`PurityInferrer` documents *"any doubt refutes"*, and its marker sets *"err
toward flagging"*. That is true of the tokens they **recognise**. There is no
allowlist, so a call to a name in neither marker set refutes nothing and the
caller stays `.pure`.

The error direction is the opposite of the documented one, and the two are not
the same kind of mistake:

- `Date(timeIntervalSince1970:)` **over**-refutes deliberately. The token scan
  cannot tell it from `Date()`, and withholding `.pure` is the sound direction on
  the effect lattice. That trade stands.
- An unrecognised callee **under**-refutes accidentally. `.pure` is the lattice
  bottom, and every downstream consumer trusts it: a generated property test runs
  a `.pure` function in-process and asserts a law over random inputs.

Item 30 proposes a seed set of asserted-pure operations, with unrecognised ⇒ the
item 29 ignorance case rather than a pass. Three numbers had to come first, and
the third is the one that decides it.

1. **Exposure** — how many non-refuted verdicts rest on a callee never examined.
2. **Price** — how large a seed set must be to hold that population.
3. **Base rate** — how many `.pure` verdicts are wrong *by this analyzer's own
   lights*.

The third is the item 40 question asked of item 30. There, the unchecked claim's
measured error rate was zero and the honest finding was narrower than the filing.
Here it is not zero.

---

## Provenance

| | |
|---|---|
| corpus | this repo's `Sources/`, tree `abbc0edb` (`Sources/` clean at run time) |
| SEI pin | taken at `22342ca`; **re-taken at `3ea25f2`**, which is current. Both columns are given throughout |
| harness | `Tests/SwiftInferCoreTests/PurityAllowlistCensusMeasuredTests.swift` |
| verdict assertions | `…+Verdict.swift`, written **after** the run and stated as directions, never counts |
| run | 2026-08-17 |

Corpus and verdicts are the item 29 census's own statics, reused rather than
recomputed, so the two denominators cannot drift apart —
`populationAgreesWithTheRefutationCensus` asserts it. It reads 2,740 functions
against that census's 2,739: one function landed between the two trees.

### What this census cannot see, stated before the numbers

- **Call expressions only.** A bare `x.count` runs a getter too. Admitting
  property reads would widen the exposure by an amount not measured here, so
  every exposure figure below is a **lower bound**.
- **Names, not symbols.** No IndexStore in any of the five packages (item 38), so
  package resolution is by bare name and overloads collapse. This is fatal to one
  number and harmless to the others; §4 says exactly where.
- **One package.** A callee in a sibling repo counts as unrecognised. That is
  attrition on the price, not on the exposure.

---

## 1 · Exposure — the majority of the pure population

Re-taken at SEI `3ea25f2`; the `c66fceb` column is kept because the *ratio* is the
finding and it survived the move.

| | count (`c66fceb`) | count (`3ea25f2`, current) |
|---|---|---|
| non-refuted subjects | 2,456 (`.pure` 2,417 · `.pureButPartial` 39) | 2,433 (`.pure` 2,396 · `.pureButPartial` 37) |
| …that call anything at all | 2,151 | 2,128 |
| …reaching a **package** function | 1,641 | 1,618 |
| …reaching an **unrecognised** callee | **1,618** | **1,596** |
| …reaching a **marker** | 0 — the control | 0 — the control |
| `.pure` alone, reaching an unrecognised callee | **1,579 of 2,417 (65%)** | **1,559 of 2,396 (65%)** |

**The exposure ratio is unmoved at 65%**, which is the number this section exists to
report. 23 subjects left the non-refuted population when `3ea25f2` refuted them, and they
came off both sides of the fraction at nearly the same rate — so a bump that retracts
`.pure` from real I/O does not measurably change *how much of what remains* rests on a
callee the leaf never examined. The bill for item 30 as filed is the same bill.

**The zero is the control, not a result.** A non-refuted body cannot contain a
marker token — that is what the marker sets *do*. Measuring zero is what tells a
reader the callee classifier is wired to the same name sets the verdict was
computed from. Without it, "the unrecognised bucket is large" would be
indistinguishable from a classifier that puts everything in it.

**So the flip costs 1,559 `.pure` verdicts** (1,579 at `c66fceb`), restored only by
axioms. That is the bill for item 30 as filed, and it is why the rest of this document
is about whether the bill buys anything.

---

## 2 · Price — finite, and that is the surprise

**501 distinct unrecognised callees** hold the *entire* non-refuted population:
305 free-shape (`min(a, b)`, `String(x)`) and 196 member-shape (`xs.map { … }`).
A hand-curatable list, not an open-ended one. On this corpus. (508 / 312 / 196 at
`c66fceb` — the seven that left are names only the newly-refuted subjects called.)

Greedy-with-recompute, axioms needed to free each decile of the 1,596 blocked:

| freed | 10% | 20% | 30% | 40% | 50% | 60% | 70% | 80% | 90% | 100% |
|---|---|---|---|---|---|---|---|---|---|---|
| axioms (`3ea25f2`) | 2 | 4 | 9 | 16 | **24** | 36 | 66 | **128** | 270 | 501 |
| axioms (`c66fceb`) | 3 | 4 | 9 | 16 | **24** | 37 | 68 | **131** | 275 | 508 |

**The two headline seeds are the same to the digit: 24 axioms for half, ~128 for 80%.**
The curve is a property of how callee names distribute across this corpus, not of the
oracle's strictness, and it did not care that the oracle got stricter. That is the
finding to carry — the *price* claim is robust, so item 30's decline does not need
re-arguing every time SEI moves.

### The arithmetic trap, in a second place

Item 32 warns that a decline-reason tally over-reports leverage because two
blockers can jointly block one row. The same error is available here one level
up, and it is larger:

| seed set | subjects **touched** | subjects **freed** |
|---|---|---|
| top 10 | 984 | 463 |
| top 25 | 1,262 | 783 |
| top 50 | 1,407 | 1,033 |
| top 100 | 1,480 | 1,196 |
| top 200 | 1,543 | 1,357 |
| top 400 | 1,582 | 1,523 |

A subject with three unrecognised callees is freed by **none** of them
individually. `touched` is what a frequency table over callee names reports;
`freed` is what the axioms buy. At the top 10 that is a 2.1× over-report.

**The over-report ratio is identical at `3ea25f2` and `c66fceb`** — 984/463 against
992/463, both 2.1×. The freed count at the top 10 is literally unchanged. Item 32's
arithmetic is a fact about the joint structure of blockers, and a refuter that removes
subjects from the population does not touch it.

**The rule that follows: score a seed set by subjects fully covered, never by
name frequency.** This is *rows moved, never laws gained* arriving in a third
place, and the first two both had to learn it the same way.

---

## 3 · Base rate — the under-refutation is real

**17 `.pure` verdicts call a package function this same analyzer refutes with a
witness** at SEI `3ea25f2` (18 at `c66fceb`), one hop, by an unambiguous name. Every one
hand-checked at the measured tree; every callee name resolves to exactly one
declaration.

> **The row that left is the one that was refuted for `nonTotal`.**
> `InteractionInvariantBridge.bridges -> makeBridge` is gone, because `bridges` itself is
> no longer a `.pure` subject — it defaults `now: Date = Date()`, so `markerInDefault`
> now refutes the *caller* and it drops out of the population this base rate is measured
> over. **All 17 survivors are marker-family**, which slightly sharpens the finding: the
> under-refutation is entirely about side-effect and nondeterminism callees, not about
> partiality.
>
> **The base rate did not fall because the defect was fixed.** It fell because one caller
> was independently refuted for an unrelated reason. Those are different facts and only
> the first would be progress on item 30 — worth stating because a base rate that drifts
> downward reads like a closing gap when it is not.

The remaining rows are refuted for `marker` or a marker-bearing set. The sharpest:

```
DrainedProcess.standardOutputViaEnv  ->  standardOutput  [marker+reducerEffect]
```

`standardOutput` builds a `Process`, two `Pipe`s, drains them on
`DispatchQueue.global`, and runs the child. `standardOutputViaEnv` is a one-line
call into it, and `SoundPurity.verdict` answers `.pure`.

**That is the exact disaster `throwsOnlyItsOwnErrors`' own doc was written
about** — *"a subprocess-spawning `runSwiftLint(executable:workingDirectory:
lintFile:)` was judged pure, which is the lattice-bottom mistake the type's
soundness note forbids."* The `try` route into a subprocess was closed by that
gate. The plain-call route was never closed, and this is it, in the same package,
reachable in one hop.

The remaining 16, all one hop, all name-unique:

| caller | callee | callee refuted for |
|---|---|---|
| `ActionSequenceStubEmitter+PayloadConstructibility.compositionGenerator` | `defaultValueLiteral` | marker |
| `DependencyTypeShapes.scan` | `checkoutSourceRoots` | marker |
| `Discover+PipelineSetup.resolvePipelineSetup` | `effectiveTestDirectories` | marker |
| `MetricsCommand.loadAggregate` | `loadExplicitPaths` | marker |
| `MetricsCommand.loadImplicit` | `nowTimestamp`, `startingDirectory` | markerInDefault, marker |
| `MetricsInteractionCommand.loadDecisions` | `loadDefault` | marker |
| `MetricsRenderer+TimeToAdoption.timeToAdoptionSection` | `timeToAdoptionRows` | marker |
| `SpeculativeRefactorRunner+Machinery.scanRestricted` | `swiftFiles` | marker |
| `SpeculativeRefactorRunner+Machinery.snapshotOrReport` | `snapshotTree` | marker+propagatedTry |
| `TargetIsolation.dump` | `uncachedDump` | marker |
| `VerifierWorkdir+Environment.macOSPlatformLine` | `declaredMacOSVersion` | marker |
| `VerifierWorkdir+Products.renderTargetDependenciesBlock` | `packageDependsOnSwiftSyntax` | marker |
| `VerifierWorkdir.renderDependenciesBlock` | `packageDependsOnSwiftSyntax` | marker |
| `ViewModelArgumentGenerator.candidateValuesExpression` | `baseValues` | marker |
| `EffectResolver.resolve` | `parseSources` | marker |
| `KitEvidenceStore.load` | `packageRoot` | marker |

`MetricsCommand.loadImplicit` reaches **two** refuted callees, which is the same
non-additivity §2 measures one level up: fixing either one alone leaves the caller
blocked. Sixteen rows here plus `DrainedProcess.standardOutputViaEnv` is the 17.

### 4 · Why the number is 17 and not 147

Admitting **member-shape** callees (`base.name(…)`) raises it to 147 (150 at `c66fceb`),
and that number is unusable. Name-keyed resolution cannot survive the member shape:
`xs.sorted()` is the stdlib method, and this package happens to declare a
`sorted(in:)` that reads `FileManager` and is duly refuted — so every `.sorted()`
in the corpus reads as a call into an impure package function. Same for
`.fileExists`, `.standardOutput`. 1,238 subjects have a `package` classification
resting on a member-shape name, and that is the size of the contamination.

A bare `foo(…)` resolves to something visible in the file's own scope, which is a
claim name-keying can nearly support — and the survivors were then read by
hand rather than counted. The list is a set of positive claims and cannot afford
the approximation the exposure numbers can, which is also why a name counts only
when **every** declaration carrying it is refuted with a witness.

The exclusion runs the other way too: a `package`-classified name that is really
a stdlib method makes the exposure figures a **lower** bound, which is the
direction that does not flatter the finding.

---

## 5 · The finding this census was not looking for — FIXED 2026-08-17

**15 non-refuted subjects defaulted a parameter to a marker expression, and the
body scan could not see it.** `bodyHasRefutingMarker` is handed `function.body`;
a default value lives in the signature.

```swift
public static func bridges(…, now: Date = Date()) -> [BridgeSuggestion]      // .pure
static func resolve(_ target: String,
                    relativeTo root: URL =
                        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) throws -> URL
```

`bridges` reads the clock on every call that omits the argument. `resolve` reads
the process's current working directory — global mutable state. Fourteen are
`Date()`, one pair is `FileManager`; all hand-checked.

**Scanned over default-value expressions only, never the whole signature.**
`func f(_ d: Date) -> Int` mentions the `Date` marker in a parameter *type* and
is perfectly pure — taking a value is not reading a clock. A whole-signature scan
would report that as a defect and it is not one, which is why the census scopes
to `parameters.defaultValue` and says so.

This is a different defect from item 30's: no allowlist, no axioms, no population
cost beyond those 15. It is a scan that stops one node too early.

### The fix, and its A/B

`PurityInferrer.hasRefutingDefaultArgument` (SwiftEffectInference `c66fceb`,
[PR #13](https://github.com/Joseph-Cursio/SwiftEffectInference/pull/13)), pinned
here at `Package.swift:122`. Default **values** only — the `func f(_ d: Date)`
control is what separates the fix from the naive whole-signature scan that would
refute the very shape dependency injection produces, and both directions were
watched failing rather than asserted.

On a tree otherwise byte-identical:

| | before | after |
|---|---|---|
| `.pure` | 2,417 | 2,404 |
| `.pureButPartial` | 39 | 37 |
| `.refuted` | 284 | **299** |
| advisory rows (`summaries.filter(\.isInferredPure)`) | 2,597 | **2,584** |

**13 false `/// @lint.effect pure` recommendations were retracted.** Thirteen and
not fifteen because two of the fifteen were `.pureButPartial`, which never
entered the advisory. **This is the opposite of item 40's result and worth saying
plainly**: there the unchecked claim was accidentally correct and 0 rows moved,
so it was reported as a latent unsoundness with a zero base rate. Here the tool
was telling thirteen functions something false, on every defaulted call.

Both other consumers were run against the branch before it merged:
SwiftProjectLint 3,327 tests green, this repo 5,508 green. The pin moved in both
on the same SHA, which also closed the standing `SEICrossRepoPinTests` red.

### What it cost item 29, which is the part worth reading

The fix **moved the answer to a different open item**, and not by a little.
`markerInDefault` holds of **32** rows:

- **15 are newly refuted** — the ones above.
- **17 were already refuted and already counted as *rankable ignorance*.** They
  carry `propagatedTry` **and** an impure default, so no annotation on any
  blocked callee could ever have freed them.

So the item 29 bucket goes 284 → 299 while its *rankable* population goes
**152 → 135**, and the split flips from 152-ignorance / 132-witness to
135-ignorance / **164-witness**. Item 29's headline — *ignorance is the majority*
— was true when measured and is not true now. `ignoranceIsNotARoundingError`
carries the weaker claim that survives, and the reasoning for the change is in
its doc comment rather than in a silently relaxed bound.

**The transferable lesson is item 32's, a fourth time**: a bucket's size is not
its leverage, and every refuter added *anywhere* shrinks it again. A leverage
report built on the 152 would have promised 17 rows that no annotation could
ever have moved — and nothing in the ranking itself would have revealed that.
The correction arrived from closing an unrelated hole.

---

## The verdict

**Item 30's premise is confirmed and its build is declined as filed.** The
under-refutation is real — 17 hand-checked rows, one of them a subprocess spawn —
but the fix it proposes costs 1,559 `.pure` verdicts to buy a defect that lives
entirely in the half the fix does not need axioms for.

**Re-taken at SEI `3ea25f2` and the verdict is unchanged, including its shape.** Both
halves moved by single digits and neither crossed anything: the base rate went 18 → 17
(one caller independently refuted, not one defect fixed), the bill went 1,579 → 1,559,
the exposure ratio held at 65%, and the two seed-set headlines — 24 axioms for half,
~128 for 80% — are identical to the digit. A decline is only worth re-taking if a number
could cross a threshold, and none of these is near one.

The item splits:

- **The package-internal half is measured-defective and cheap.** All 17 rows are
  one hop into a function whose verdict this package already computed. Closing
  them needs a within-package callee join, not an allowlist, and costs **zero**
  `.pure` verdicts that rest on stdlib. `EffectSymbolTable.applyBodyInference`
  already does upward inference over un-annotated callees; what does not happen is
  `PurityInferrer.verdict` consulting it. That is item 31's *"wiring, not
  analysis"* about the same seam, and it is the build worth scoping next.
- **The stdlib half is unmeasured and expensive.** This census can exhibit no
  defect in it — and **cannot**, because it has no oracle for those callees. That
  is absence of evidence, not evidence of absence, and it is the reason this half
  stays open rather than closing. What is now known is its price: 501 axioms for
  the whole corpus, 24 for half of it, scored by subjects freed and not by name
  frequency.
- **`3ea25f2` closed part of the stdlib half without an allowlist, and that is a
  data point for this decline rather than against it.** `FileHandle` / `Process` /
  `Pipe` were exactly stdlib-side under-refutations, and SEI closed them by adding
  **three marker names**, not by inverting the default. Three names cost zero `.pure`
  verdicts that rest on genuinely pure stdlib calls. **Targeted marker additions are
  the cheap instrument for this half; the allowlist flip is still the expensive one.**
- **The default-argument hole is separable from both** and smaller than either.

### What would reopen the decline

- A `.pure` verdict shown wrong through a **stdlib** callee. One witness moves
  the expensive half from unmeasured to measured, and the costing above is
  already done.
- `flippingTheDefaultMovesMostOfThePurePopulation` going green-to-red — if fewer
  than half of `.pure` verdicts rest on an unrecognised callee, the flip is
  affordable without axioms and the build is back on.
- The distinct-callee count growing faster than the population it serves, which
  voids the "hand-curatable" costing. `theSeedSetIsFinite` is where that shows up.

### Standing caution for whoever builds the seed set

**The axioms are asserted, not proven.** They belong in their own file, counted
separately, and every downstream claim reads *pure given these axioms* — the same
posture the tier table in the additions doc gives the static tier. A seed set
folded into the marker file becomes indistinguishable from measurement within one
cycle.
