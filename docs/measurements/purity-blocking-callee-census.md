# What blocks a verdict, and who would read the answer?

> **Status:** `measured` · **As of:** 2026-08-17

Re-derivable at any time — `PurityBlockingCalleeCensusMeasuredTests` *is* the
harness, and `make batch2` runs it.

Answers open-threads item 31. **The verdict is DECLINE, on two independent
grounds, either of which alone would be enough.**

---

## The question

At the point `throwsOnlyItsOwnErrors` gives up, it knows **which** callee it gave
up on. `PurityVerdict.refuted` has no room to say so, so the fact never leaves
the inferrer — the fourth recorded instance of *the consumer keeps asking the
producer, in English*. Item 31 proposes inverting it: key by blocking callee,
list the functions whose verdict rests on it.

Item 29 sized the population — 152, then 135 after item 41. Sizing is not
leverage, and the *Decisions* stub in the additions doc names the trap
explicitly: *"If the ranking has no consumer, it is a third instance rather than
a fix."* So two questions had to come before the build.

1. **Does the index have leverage?** How many of the 135 would a within-package
   join actually free?
2. **Does the leverage have a reader?** What verdict do freed rows land on, and
   does anything consume it?

The trap was expected to arrive through item 35 — nobody reads a recommended
`@lint.effect pure` back. It arrives from a different direction, and earlier.

---

## Provenance

| | |
|---|---|
| corpus | this repo's `Sources/`, tree `7dad9f5b` |
| SEI pin | `c66fceb` (`Package.swift:122`) — **post item 41**, which is why the population is 135 |
| harness | `Tests/SwiftInferCoreTests/PurityBlockingCalleeCensusMeasuredTests.swift` |
| population | the item 29 census's own `refuted` static, filtered to ignorance-only — shared, not recomputed |

**The blocking callee is read at two strengths, and both are reported.** One
`try` covers a whole expression in Swift, so in `try foo(index(x))` either call
may be the throwing one. *Conservative* requires every callee under the `try` to
resolve; *optimistic* requires only the outermost. The truth is between them, and
picking one silently would be choosing the answer.

Name-keyed resolution throughout (no IndexStore — item 38), so a name counts as
settled only when **every** declaration carrying it is non-refuted.

---

## 1 · Ground one — the leverage is a fifth of the population

| reading | one hop | fixpoint |
|---|---|---|
| conservative | 13 of 135 | **27** of 135 (9 hops) |
| optimistic | 17 of 135 | **31** of 135 (9 hops) |

**Item 31's row says *quote the 135*. The 135 is the population; the leverage is
13–31.** That is the same arithmetic error the item's own dependant (item 32)
warns about, arriving a fifth time and now inside the *corrected* number: 152 was
an over-report of the rankable set, 135 is right, and 135 is still a 4–10×
over-report of what a join buys.

Multi-hop is worth its budget where it is worth anything at all — fixpoint roughly
doubles one-hop (13→27, 17→31) and takes 9 hops to converge, well past the one
hop `EffectResolver` can afford under §13. That is item 28's asymmetry confirmed
and priced: a linter running ahead could pay for this. It would buy 27 rows.

### Where the other 104 go, which is the finding

| | rows |
|---|---|
| freed at fixpoint (optimistic) | 31 |
| blocked by ≥1 **foreign** callee — no within-package join can ever reach them | 36 |
| blocked **only** by foreign callees | 13 |
| remainder: resolve fine, to package callees that are **themselves refuted** | ~68 |

**Most of this "ignorance" is accurate.** The join runs, names the callee, and
the answer is still `.refuted` — `write`, `encode`, `emit`, `discover`, `resolve`
are package functions that genuinely do I/O. Naming the blocker converts an
unexplained refutation into an explained one; it does not convert it into a law.

That is a real gain in *legibility* and none at all in *reach*, and item 31 is
filed as a reach item.

---

## 2 · Ground two — the leverage lands in a tier nothing reads

**Every row in this population `throws`.** Structural, not incidental:
`propagatedTry` is defined as `throwsClause != nil` *and* a `try` in the body,
and `verdict(for:)` returns `.pure` only when there is no `throwsClause`. So the
best a resolved callee can do for any of these 135 rows is `.pureButPartial`.

**Nothing consumes `.pureButPartial`.** It occurs in `Sources/` only inside doc
comments — no `case`, no `if`, no filter — and `isInferredPure`, the field the
one live consumer reads, is `purityVerdict == .pure` by definition.

**So resolving every blocking callee in the package moves zero advisory rows.**
Not few. Zero, by construction.

This re-orders the work: **item 34 is item 31's precondition, not item 29.**
Item 34 is the unconsumed `.pureButPartial` tier, filed 2026-08-04 as waiting on
*"a consumer that can narrow a law's domain to the non-throwing inputs."* Until
that consumer exists, item 31 has nowhere to put its output. That dependency is
written down nowhere the sequencing would have caught it — items 31–33 were
chained to item 29, which is the *population* question, and nobody chained them
to the *tier* question.

`thePartialTierHasNoConsumer` scans the shipped sources and fails the day a
consumer appears, which is when this verdict should be re-taken.

---

## 3 · The index's head is unmovable, which is why this is a decline and not a defer

Item 31's actual artifact, built and measured. Blocking callee → rows blocked,
most-blocking first:

| callee | shape / status | rows |
|---|---|---|
| `String` | free / **foreign** | 14 |
| `write` | member / blocked | 14 |
| `encode` | member / blocked | 12 |
| `emit` | member / blocked | 10 |
| `discover` | member / blocked | 7 |
| `resolve` | member / blocked | 7 |
| `Data` | free / **foreign** | 6 |
| `Inputs` | member / foreign | 6 |
| `collectVisibleSuggestions` | member / blocked | 4 |
| `decode` | member / blocked | 4 |
| `makeSeedHex` | free / **settled** | 4 |

**The single most-blocking callee is `String`, and every `try String(…)` in this
corpus is `String(contentsOf:)` — a file read.** `Data` at 6 is likewise
`Data(contentsOf:)`. Those rows are *correctly* refuted; the analyzer simply
cannot say why.

A leverage report built on this index ranks **"resolve `String`"** first. Nothing
can resolve it, because it is not pure. The next four are package functions that
write files, encode to disk, and emit output — also correctly blocking. The first
entry that any annotation could legitimately move is `makeSeedHex`, at 4 rows,
eleventh.

**This is what makes the verdict a decline rather than a deferral.** If the only
problem were the unconsumed tier, item 31 would be *build it after 34*. But the
ranking it would produce is led by callees that must stay blocking, and a report
whose top recommendations are all wrong is worse than no report — it is item 20's
*vocabulary nobody reads* with an added failure mode, because this one would be
read and acted on.

---

## The verdict

**DECLINE item 31 as filed.** Not measured-not-worth-building in the item 22
sense — the fact is real, the extraction works, and the index is 126 entries of
genuine information. What fails is every path from the index to an output:

- its leverage is 13–31 rows, not 135;
- those rows land in `.pureButPartial`, which nothing reads, so 0 advisory rows
  move;
- and its top-ranked entries are file reads that no annotation can free.

**What is worth keeping** is the extraction itself, which is ~40 lines and now
exists in the harness. Naming the blocking callee turns an unexplained refutation
into an explained one, and that is a legibility gain available *without* a
ranking, a channel, or a report — `PurityVerdict.refuted` carrying a callee name
would deliver it at the point the fact is known.

### What would reopen it

- **A consumer for `.pureButPartial` appears** (item 34). That is the precondition
  this census discovered; `thePartialTierHasNoConsumer` fires when it happens.
- **The freed count reaches a third of the population.** Today 31/135.
  `theLeverageIsAFractionOfThePopulation` is the guard.
- **The index's head changes character** — if the top blockers become package
  functions that annotation could legitimately settle, the ranking starts
  recommending true things. Today the first such entry is eleventh.

### What this census does NOT claim

- That the 27–31 freeable rows carry **refutable** laws. Item 22's transferable
  practice and item 32's own caveat both apply, and neither was measured here:
  freeing a row is only a win if some plausible implementation would be *rejected*
  by the law it unlocks. Given the output tier has no reader, that measurement was
  not worth taking yet.
- That the member-shape entries in the index are correctly resolved. Name-keying
  collapses overloads, and §4 of the unrecognised-callee census measured how badly
  that misleads on member shapes specifically. The index is reported with shape
  and status per entry so a reader can discount accordingly.
