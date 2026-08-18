# Would refactoring toward purity put more code within a law's reach?

> **Status:** `measured` · **As of:** 2026-08-18

**Re-taken the same day it was first written** — open item 43's one-hop join landed between
the two readings and moved arm 2's population. Every table below is the second reading.

Re-derivable at any time — `PurityRefactoringReachMeasuredTests` *is* the harness, and
`make batch2` runs it.

**Measured NO, on three corpora, at a ceiling: forcing every non-`.pure` verdict to
`.pure` moves ZERO suggestions.** Nothing in the pipeline gates law emission on purity,
so there is no mechanism for a purity refactor to free a law.

**And the same fact read from the other side is a soundness finding.** Because nothing
gates on purity, **22 suggestions across the three corpora rest on a subject this
analyzer refutes with a named construct in the body** — a `FileManager` call, a trap, an
`async` signature. Purity does not hold a law back, which is why the refactor frees
nothing *and* why an impure subject is never stopped.

---

## Why this was measured rather than argued

The claim — *annotate or refactor toward `@Pure` and the toolchain finds more property
tests* — describes a loop that genuinely exists. The tools do read purity; purity is what
makes a generated law meaningful, since SEI's own doc calls `.pure` the most dangerous
place to land wrongly *because a generated property test runs the function in-process
over random inputs*. A plausible claim about a real loop is exactly the shape
`docs/measurements/ownership-premise-declined.md` established the practice for: **probe
the premise before scoping the build.**

---

## Provenance

| | |
|---|---|
| corpora | item 34's three, reused unchanged — self, OrderedCollections, SwiftPropertyLaws |
| SEI pin | `3ea25f2` |
| harness | `Tests/SwiftInferCoreTests/PurityRefactoringReachMeasuredTests.swift` (+`Support`) |
| join key | the full `SwiftInferCore.SourceLocation` — file, line **and** column |
| classifier | `PurityRefutationCensusMeasuredTests.Attributor`, the replica guarded against `SoundPurity` |

**The corpora are item 34's on purpose.** A different set would make the `isThrows`
control incomparable to the **+2** that census measured through the same code path, and
that comparison is the only thing establishing this harness reaches the templates at all.

**The denominators reconcile with the item 29 census**, which is worth stating because
they are not equal: 2,920 summaries here against 2,740 functions there, and 2,576 `.pure`
against 2,396. Both gaps are **180** — the read-only computed properties, which
`FunctionScanner` summarises and the function census does not. Two instruments, one
population, and the difference is fully explained.

---

## 1 · Arm 1 — the claim in its own terms

Force every `.refuted` and `.pureButPartial` verdict to `.pure`, carrying
`isInferredPure` with it, and re-run `TemplateRegistry.discover`.

| corpus | summaries | baseline | **purity forced** | `isThrows` masked (**control**) |
|---|---|---|---|---|
| self (`Sources/`, CLI) | 2,927 | 712 | **712 (0)** | 714 (**+2**) |
| OrderedCollections | 435 | 160 | **160 (0)** | 160 (0) |
| SwiftPropertyLaws | 599 | 51 | **51 (0)** | 51 (0) |

**Zero, on every corpus — and still zero after the one-hop join landed**, which is the
sharper statement: the join moved 31 verdicts across the three corpora and arm 1 did not
budge, because retracting a verdict nothing reads changes nothing a template does. And the instrument is deliberately more generous than any real
refactor: a real one changes the body and may change the signature, this one changes only
the verdict — so **0 is a ceiling, not an estimate**.

**The control reproduces item 34's +2 exactly**, on the same corpus, through the same
call. That is what makes the zero readable: the harness reaches the templates, the
templates respond to a field, and the field they respond to is not purity.

### Why zero, structurally

`isInferredPure` has **one** consumer in shipped code — `EffectAnnotationAdvice+Build`,
the outbound advisory — and `purityVerdict` has **none**. `UnverifiableCause` has eight
cases and purity is not among them, so no law is declined for an impure subject either.
There is no wire for a purity refactor to travel down.

**The refactoring worklist is also the wrong bucket.** Marking the 2,396 already-pure
functions says nothing about which of the 307 impure ones to fix; the actionable list is
the **174 witness-bearing** refutations, which already name the construct. And that
advisory already ships — `discover --effect-annotations` emits it — with
`docs/measurements/pure-advisory-round-trip.md` measuring **3,250 annotations, 0
suggestions moved** at the other end of the same loop.

---

## 2 · Arm 2 — the question arm 1 exposed

If nothing gates on purity, how many of today's suggestions rest on a subject the
analyzer refuted?

| corpus | suggestions | touching a refuted subject | **witness** | ignorance-only | **joined** | computed property |
|---|---|---|---|---|---|---|
| self | 712 | 20 | **8** | 12 | 0 | 0 |
| OrderedCollections | 160 | 32 | **11** | 11 | **6** | 8 |
| SwiftPropertyLaws | 51 | 3 | **3** | 0 | 0 | 0 |
| **total** | **923** | **55** | **22** | **23** | **6** | **8** |

> **Re-taken after open item 43's one-hop join, and the coupling was predicted before it was
> built.** The join retracts `.pure` verdicts whose body calls a settled-impure package
> function, so it *grows* this population rather than shrinking it: **+5 suggestions and +6
> refuted subjects, all on OrderedCollections**. The witness and ignorance halves did not
> move — 22 and 23 both times — because none of this repo's 16 retracted functions is a law
> subject.
>
> **The `joined` column is a category this census did not have, and for one run it got them
> wrong.** A joined retraction leaves no *local* syntactic cause, so the attributor found
> none and bucketed six rows as `ignorance-only` — the analyzer reporting its own blindness,
> which is the inverse of the truth: these carry a witness **one hop away**. Before the join
> existed, a `.refuted` subject always carried at least one local cause, so an empty cause
> set is unambiguous and the fix is exact. The six are `OrderedSet.sort()`, `subtract(_:)`,
> `subtracting(_:)` ×3 and `symmetricDifference(_:)`, each reaching the `nonTotal`-refuted
> `_partition` family.
>
> **Self's summary count moves for a duller reason**: 2,920 → 2,927 because this change added
> source files to `Sources/`, which is this corpus. Self-dogfood contamination, not a finding.

**The join resolves every row** — 954/954, 208/208, 52/52 — which is asserted, because a
suggestion whose evidence matches no summary is dropped silently and a broken join
reports a small, reassuring number.

### The witness split is what makes this a finding rather than a tally

**Item 32's arithmetic in a fourth place.** 23 of the 53 refuted subjects are refuted
*only* by `propagatedTry` — the analyzer saying it could not see past a `try`, not
evidence of an impurity. Ten of those are `encode(to:)` in this repo's own sources, which
throws because the `Encoder` API throws and is not impure. Quoting 50 would over-report
the actionable count by more than half.

### What the 22 witness-bearing rows actually are

**Self — 8, all `marker`, and all genuinely impure**: `directoryExists(_:)`,
`fileExists(atPath:)`, `isDirectory(_:)` ×2, `isStale(indexPath:packageRoot:diagnostic:)`,
`packageDependsOnSwiftSyntax(at:diagnostic:)`, `parseBudget(_:)`, `baseValues(for:)`.
Seven of the eight are filesystem reads offered under the **`predicate`** template. **A
`predicate` law over `directoryExists(_:)` is a law whose truth depends on the
filesystem** — it can pass, fail, or flake depending on what is on disk, and nothing in
the output says so.

**OrderedCollections — 11, all `nonTotal`**: `_partition`, `_halfStablePartition`,
`isSubset(of:)`, `removeLast()`, `_ensureUnique()`, and friends. These trap on invalid
input by design; the refutation is about **totality**, not effects. A law over them is
sound on the domain where they are defined, which is a weaker problem than the
filesystem one and a real one — `.pureButPartial` exists for exactly this and does not
reach here, because these are `.refuted` outright.

**SwiftPropertyLaws — 3**: `debouncedOutput(of:)` ×2 (`asyncSignature+reducerEffect`) and
`knownValueGenerator(forTypeName:)` (`marker`).

**So the 22 are not one finding but three**, split by refuter, and only the first is the
in-process-execution hazard SEI's doc warns about.

---

## 3 · The finding this census was not looking for

**`isReadOnlyGetter` treats `_modify` as read-only, so a MUTABLE property is offered as a
law subject.** `OrderedSet.unordered` declares `get` and `_modify`:

```swift
public var unordered: UnorderedView {
  get { UnorderedView(_base: self) }
  _modify { … self = OrderedSet(); defer { self = view._base }; yield &view }
}
```

`isReadOnlyGetter` accepts any accessor list containing `get` and not containing the
literal `"set"`. A `_modify` coroutine **is** a mutating accessor — `set.unordered.insert(x)`
writes through it — so the guard admits it, and the property carries **8 suggestions**
(`inverse-pair` ×4, `round-trip` ×4).

**A second defect masks the first.** `SoundPurity.verdict(forGetter:)` is handed the whole
`AccessorBlockSyntax`, so it reads the `_modify` body too, sees `self = OrderedSet()`, and
returns `.refuted`. The property is therefore *reported* impure — correctly, but for a
reason that has nothing to do with its getter, which is pure. Remove the `_modify` and
the same misclassification would return a clean `.pure`.

**Item 40's shape exactly: an oracle pointed at the wrong node.** Neither defect has been
A/B'd here and neither is fixed in this change — both are filed rather than folded into
this census's numbers. **Fifth census in a row whose finding is not the thing it went
looking for.**

---

## What this does NOT establish

**That the 22 laws are wrong.** A law over an impure subject may still hold. What is
missing is that nothing *says* the subject is impure, so a reader cannot tell a robust
law from one that passes because the filesystem happened to cooperate.

**That a veto would be cheap.** Its population is measured; its false-positive rate is
not. The 23 ignorance-only rows are exactly what a naive `purityVerdict == .refuted` veto
would also remove, and ten of those are `encode(to:)`.

**Anything about a corpus with different shape.** Three corpora, one of them this repo.
OrderedCollections' 17% is the outlier and it is entirely `nonTotal` — a collection
library traps by design.

---

## The verdict

**The refactoring loop is not there to be used.** Arm 1's zero is structural, not
incidental: no template gates on `purityVerdict`, purity is not a decline cause, and the
one consumer of `isInferredPure` is an advisory measured inert at 3,250 annotations. A
`@Pure` adoption programme over this corpus would annotate **2,396 declarations and move
nothing** — the Daikon trap reached through a new door.

**What the purity signal is actually for, on this evidence, is a veto.** Arm 2's 22 rows
are the population a veto would act on, and the eight `marker` rows in this repo's own
sources — seven of them filesystem predicates — are the ones worth acting on first.

**Scope any veto to witness-bearing refutations.** Vetoing on `.refuted` outright removes
23 rows whose refutation is the analyzer's own blindness, `encode(to:)` chief among them,
and `codable-round-trip` is the one template measured at 100% yield.

## What would reverse this

- **A template gates on `purityVerdict`.** Arm 1 stops being structurally zero, and
  `makingEveryRefutedFunctionPureMovesNothing` fails on the day it happens.
- **The witness count reaches zero**, meaning a veto landed. Pinned by
  `lawsRestOnWitnessRefutedSubjects`.
- **The tally and the witness half converge**, which would make quoting either safe.
  Pinned by `theTallyOverReportsTheWitnessHalf`.
