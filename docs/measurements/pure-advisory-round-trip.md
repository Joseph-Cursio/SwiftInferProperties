# Does taking the `pure` advice change anything?

> **Status:** `measured` · **As of:** 2026-08-17

Re-derivable at any time — `PureAdvisoryRoundTripMeasuredTests` *is* the harness,
and `make batch2` runs it.

Answers open-threads item 35. **The premise is wrong about the mechanism and
right about the consequence**, and the difference decides what a fix would have
to be. Measured: **3,250 functions annotated across three corpora, zero
suggestions moved.**

---

## The premise, and what is actually there

Item 35 says `discover --effect-annotations` recommends `/// @lint.effect pure`
lines and *"nothing reads them back — one tool talking to itself in English."*

**The channel is not outbound-only.** `FunctionScannerVisitor` calls
`EffectAnnotationParser.parseEffect(declaration:)` on every declaration and
stores the result as `FunctionSummary.declaredEffect`. Templates genuinely
consume it:

- `IdempotenceTemplate` scores `.idempotent` at **+15** and applies a **veto** to
  `.nonIdempotent` and `.externallyIdempotent`;
- `ReplayIdempotenceTemplate` dispatches on two tiers;
- `EffectResolver` uses its *presence* to decide whether to infer at all.

Write `@lint.effect non_idempotent` and the tool reads it, believes it, and
withdraws a law. The round trip exists and works.

**What is inert is `pure` specifically, and deliberately so.**
`declaredEffectSignal` carries an explicit `case .observational, .pure: return
nil`, and argues the point: *"`pure` is orthogonal (`x + 1` is pure and not
idempotent). Staying silent is the claim."*

**That reasoning is correct** — for idempotence. The trouble is that no *other*
template consumes declared purity either, so one template's deliberate silence
is indistinguishable from the whole catalog's.

So the accurate statement is not *nothing reads it back*. It is **acting on the
advice changes nothing**, which is sharper, falsifiable, and measured below.

---

## Provenance

| | |
|---|---|
| corpora | three, shared with the item 34 harness |
| tree | `58a0c3a6`, SEI pin `3ea25f2` |
| harness | `Tests/SwiftInferCoreTests/PureAdvisoryRoundTripMeasuredTests.swift` |

The advised population is exactly what `EffectAnnotationAdvice+Build` recommends
— `isInferredPure` — minus anything already carrying a tier, since re-annotating
an annotated declaration is not the round trip.

---

## The measurement

| corpus | functions the advisory would annotate | baseline | **advice taken** | control `.nonIdempotent` |
|---|---|---|---|---|
| self (`Sources/`, CLI) | 2,571 | 710 | **710 (0)** | 603 (**−107**) |
| `swift-collections/OrderedCollections` | 356 | 163 | **163 (0)** | 160 (**−3**) |
| `SwiftPropertyLaws` | 323 | 51 | **51 (0)** | 39 (**−12**) |

**3,250 annotations. Zero movement.**

### The control is what makes the zero readable

Substituting `.nonIdempotent` on the *same* population moves the count on every
corpus — −107, −3, −12 — because `IdempotenceTemplate` vetoes on that tier. So
the harness reaches the consumers, the declared-effect channel is live, and the
`pure` zero is a **measured zero rather than a broken arm**.

That distinction is not hypothetical: item 34's first run scanned an empty SwiftPM
stub and returned a zero that looked exactly like a result.

---

## The verdict

**Item 35 is re-filed, not built.** The channel it asks for already exists; what
does not exist is any consumer of the one tier the advisory emits.

**This is item 34's finding at the other end of the round trip.** Item 34
measured that no template gates on `purityVerdict` — the *inferred* signal has no
path to a law. This measures the same for the *declared* signal. Together:

> The purity vocabulary is complete in both directions and consumed in neither.

That is the root cause items 31–34 kept meeting from different sides, and it is
now stated once, with a number on each end.

### What a fix would actually have to be

Not a read-back — that exists. A **consumer**: some template that does something
different when a function is known pure. Two shapes are visible from here, and
neither is scoped:

- **A tier bump rather than a new law.** Declared purity is evidence *about the
  same laws already proposed* — a `Signal` on shape-derived suggestions, not a
  new family. That is cheap and would make the advisory matter, but item 22's
  practice applies: score it against the laws that HELD, because turning
  `Likely → Verified` on a law nobody would have refuted is the
  [Daikon trap](../design-internal/glossary.md#daikon-trap) reached through a new door.
- **A veto's mirror.** `.nonIdempotent` withdraws a law; nothing yet uses `.pure`
  to *admit* one that shape alone would decline. This is the more valuable
  direction and the more dangerous one, since admitting on an author's annotation
  trusts a claim the tool cannot check.

### What would reopen it

- **`takingTheAdviceChangesNothing` goes red.** Some template has learned to
  consume declared purity, and the item is live again.
- **The advisory starts emitting a tier something consumes.** Today it emits only
  `pure`; the tiers with consumers (`idempotent`, `non_idempotent`) are never
  recommended by this tool.

### Not measured here

Whether the advisory's *recommendations* are correct. This experiment grants
every one of them and asks only what the catalog does with them — 3,250 grants,
zero effect. If a consumer is ever built, the precision of the advice becomes
load-bearing for the first time, and items 30/33/42 are the record of how often
this oracle has been more permissive than its own doc claimed.
