# Is there anything for a `.pureButPartial` consumer to consume?

> **Status:** `measured` · **As of:** 2026-08-17

Re-derivable at any time — `PartialPurityConsumerMeasuredTests` *is* the
harness, and `make batch2` runs it.

Answers open-threads item 34. **Measured NO — the ceiling is 2 suggestions across
three corpora and 363 throwing functions, and item 34's own population accounts
for one of them.** Since item 31's census made this the precondition for items
31–33, declining it closes that cluster too.

---

## The question, re-shaped by what the code actually does

Item 34 asks for *"a consumer that can narrow a law's domain to the non-throwing
inputs."* Two facts had to be established before building one, and the first
changed the item.

### Purity gates no law. `throws` gates several.

`isInferredPure` is read in exactly **one** place in the shipped sources —
`EffectAnnotationAdvice+Build`, the outbound `/// @lint.effect pure` advisory —
and `purityVerdict` is read in **none**. No template consults either. The
templates that care about effects gate on `declaredEffect`, which is the
*linter's annotation*, not this inference.

**`isThrows` is a hard gate in at least eight places**: `InvolutionTemplate`,
`HomomorphismTemplate`, `EquivalenceRelationTemplate`,
`CaseIterableMappingTemplate`, `SetRelationModelPairing`,
`OverridePrecedenceTemplate`, and two TestLifter detectors that name the decline
outright (`.producerThrows`, `.predicateThrows`).

So item 34 is not *"give the advisory something to say"*. It is **"`.pureButPartial`
is the licence to relax a `throws` gate that eight templates apply
unconditionally."** That is a better item than the one filed — and the first in
this sequence whose leverage would land in law emission rather than in an
advisory nobody reads. It is worth stating plainly because it made the item look
promising right up until it was measured.

---

## Provenance

| | |
|---|---|
| corpora | three, below |
| tree | `bcfeb45b`, SEI pin `3ea25f2` |
| harness | `Tests/SwiftInferCoreTests/PartialPurityConsumerMeasuredTests.swift` |

**The instrument is deliberately generous, and that is what makes a zero
meaningful.** Masking `isThrows` is *not* the build: a real domain-narrowed law
would emit `try?` and compare optionals, whereas masking makes the templates emit
a law calling `f(x)` bare, which would not compile. The arms therefore measure
**how many candidates the gate is holding back** — a ceiling, in the same sense
that a decline-reason tally is a ceiling on what a fix frees. The standing ratio
on that is ~5:1 against.

Three arms: **baseline** (shipped), **partial** (`isThrows` masked on
`.pureButPartial` only — item 34's own ceiling), and **allThrowing** (`isThrows`
masked on every throwing summary — the gate's total ceiling, whatever the purity
verdict).

### A corpus note that cost a measurement

**`fixtures/cycle27-surface/Sources` is not the v1 corpus.** That target is an
empty stub whose only job is to give SwiftPM something to resolve dependencies
into — its own `Stub.swift` says so — and the corpus is the *resolved checkouts*.
Pointing an arm at the stub returned 0 summaries and 0 suggestions, which reads
exactly like a measured zero and is not one. The harness now fails on any arm
that scans zero summaries, because that is a broken arm, not a result.

---

## The measurement

| corpus | summaries | throwing | `.pureButPartial` | baseline | partial-masked | all-throwing-masked |
|---|---|---|---|---|---|---|
| self (`Sources/`, CLI) | 2,920 | 260 | 37 | 710 | 711 **(+1)** | 712 **(+2)** |
| `swift-collections/OrderedCollections` (v1, third-party) | 457 | 36 | **0** | 163 | 163 (+0) | 163 (+0) |
| `SwiftPropertyLaws` (sibling library) | 599 | 67 | 9 | 51 | 51 (+0) | 51 (+0) |

**363 throwing functions. 46 `.pureButPartial`. Relaxing the gate entirely buys
+2 suggestions; item 34's population accounts for +1.**

### What the +2 actually are

```
filter-subset    :: CorpusCommand.select(CorpusManifest) -> [CorpusManifest.Entry]
selection-subset :: (the same function)
```

Both land on one **`private`** helper in a CLI command. They are refutable laws —
a `select` that added elements would fail them — so this is not the
`f(x) == f(x)` trap. It is simply one private function's worth of reach, dressed
up by a 37-row population.

### The zero that is most informative

**`OrderedCollections` has 36 throwing functions and 0 `.pureButPartial`.** Every
throwing function in that corpus is `.refuted`, because each `try`s into a callee
this leaf cannot resolve. That is item 30's under-reach arriving in a new place:
on a third-party corpus, the `.pureButPartial` tier is not merely unconsumed, it
is **empty**. A consumer built for it would have had nothing to read there even
if the templates had wanted it.

---

## The verdict

**DECLINE, measured.** Not *not-yet-built*: the ceiling is measured, generously,
over three corpora, and it is 2.

**This closes items 31–33 as well.** Item 31's census established that its whole
population `throws`, so every row it could free lands in `.pureButPartial`, and
made item 34 the precondition for the cluster. Item 34 measures at ~0, so:

- **31** (blocking-callee index) — declined on its own numbers, and its output
  tier is now measured worthless as well.
- **32** (leverage ranking) — nothing left to rank.
- **33** (parameterised purity) — declined on its own numbers; its population is
  an over-claim, not an under-reach.

**The line of work is not a loss, and it is worth being precise about what it
bought.** Items 29 and 30 were measurements that found real defects, and three
fixes shipped from them: **item 40** (computed-property verdicts, 0 rows moved
but a latent unsoundness closed), **item 41** (default arguments, 13 false
advisories retracted), **item 42** (masked I/O plus the unconsulted shared
classifier, 8 rows). Items 31–34 are the *reach* half, and the reach half is
where the measurements came back empty.

### What would reopen it

- **A template starts gating on `purityVerdict`.** Today none does, and that is
  the root of the whole result — the signal has no path to a law.
- **Relaxing the `throws` gate reaches even a tenth of the throwing population**
  on any corpus. `theGateHoldsBackAlmostNothing` is the guard; today the ratio is
  2 in 363.
- **A corpus appears with a large `.pureButPartial` population.** Two of the
  three here are in single digits and one is zero. A parser-heavy or
  codec-heavy subject is the obvious place to look, and this harness takes a
  corpus list.

### The second consumer, still unbuilt and now unmotivated

The row also names a shrink-and-replay consumer: a `.pureButPartial` function is
safe to shrink and replay, which is weaker than what the advisory refuses to say.
That remains true and remains unbuilt. It is not measured here because it is not
a *law-emission* question — it would gate how a generated test behaves, not
whether one is proposed. If it is ever built, it needs its own measurement, and
the population figures above are the place to start: **9 rows on a sibling
library, 0 on a third-party one.**
