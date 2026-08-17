# What is actually inside `PurityVerdict.refuted`?

> **Status:** `measured` · **As of:** 2026-08-17

Re-derivable at any time — `PurityRefutationCensusMeasuredTests` *is* the
harness, and `make batch2` runs it.

Discharges the measurement precondition on open-threads item 29, which is the
precondition on items 30–33.

**Two SEI pins are reported here, and only the later one is current.** The census
was taken on `22342ca`; item 41 landed hours later on `c66fceb` and moved the
split. Sections carrying the earlier numbers say so at the top. **Do not quote a
figure from this document without checking which pin it belongs to** — the
headline reversed.

---

## The question

`PurityVerdict.refuted` means, per its own doc, *"an impurity or nondeterminism
refuter fired, **or** the shape could not be inspected at all."* Those are
different facts. The first is a claim about the code; the second is the analyzer
reporting its own blindness in the same token. Only the first is a finding.

So: **how much of the bucket is evidence and how much is ignorance?** The answer
was framed as the falsifier for the whole purity-as-a-consumed-tier line of work.
If ignorance were a rounding error, there would be nothing to rank and items
31–33 would close as *measured-not-worth-building*.

**The 2026-08-04 figure is deliberately not reused.** 2,206 `.pure` / 35
`.pureButPartial` / 259 `.refuted` of 2,500 was taken on a different binary and a
smaller tree, and it is precisely the *undivided* number this census exists to
divide. Everything below is a fresh run.

---

## Provenance

| | |
|---|---|
| corpus | this repo's `Sources/`, tree `d6285dff` (branch point `3c41f704`) |
| SEI pin | `22342ca` (`Package.swift:122`) |
| harness | `Tests/SwiftInferCoreTests/PurityRefutationCensusMeasuredTests.swift` |
| taxonomy frozen at | `20e134c1`, **before** the run — git order is the proof |
| run | `20e134c1..b6207a45`, 2026-08-17 |

The corpus is function *declarations* collected with `FunctionScannerVisitor`'s
own traversal rules — protocol bodies skipped, nested functions skipped — so the
denominator is the population the shipped scan actually computes a
`purityVerdict` for, not every `func` token in the tree.

---

## The population

| verdict | count |
|---|---|
| `.pure` | 2,416 |
| `.pureButPartial` | 39 |
| `.refuted` | **284** |
| total | 2,739 |

The 39 `.pureButPartial` are open-threads item 34's population, unchanged in
character since 2026-08-04 and still unconsumed.

---

## The split — the answer, and it moved the same day

> **Superseded numbers below, kept because the change is the finding.** Every
> figure in this section and the two that follow was measured against SEI pin
> `22342ca`. On **2026-08-17**, hours later, open item 41 landed — `PurityInferrer`
> learned that a **default argument** is code the function runs — and the split
> changed materially. Both readings are given; the post-fix one is authoritative.
> See *After item 41* below, and
> `docs/measurements/purity-unrecognised-callee-census.md` §5 for the fix.

| | rows (pin `22342ca`) | share | rows (pin `c66fceb`) | share |
|---|---|---|---|---|
| **witness-bearing** — at least one named construct refutes | 132 | 46% | **164** | **55%** |
| **ignorance-only** — nothing in the source refutes | **152** | **54%** | 135 | 45% |
| `.refuted` total | 284 | | 299 | |

**As first measured, ignorance was the majority** — not a rounding error — and
that is what returned the answer in the direction that *permits* items 30–33
rather than closing them.

**It is no longer the majority.** What survives is the weaker claim: ignorance is
45% of the bucket, all of it actionable, and that is still not a rounding error.
What does *not* survive is *most of the bucket is unread*, which is the stronger
sentence items 31–33 were sold on. `ignoranceIsNotARoundingError` carries the
surviving claim; the assertion was re-argued in its doc comment rather than
quietly relaxed.

### By cause

A function may satisfy several causes; these do not sum to 284.

| cause | kind | rows |
|---|---|---|
| `propagatedTry` — `throws` + a `try` into a callee this leaf cannot see | ignorance, **actionable** | 219 |
| `marker` — a side-effect / nondeterminism token in the body | witness | 111 |
| `asyncSignature` | witness | 31 |
| `reducerEffect` — `ReducerPurityAnalyzer` refuted | witness | 26 |
| `nonTotal` — force-unwrap, `try!`, `as!`, trap call | witness | 8 |
| `noBody` — nothing to inspect | ignorance, **inert** | **0** |

### By cause set

| causes | rows |
|---|---|
| `propagatedTry` | 152 |
| `marker` | 49 |
| `marker+propagatedTry` | 35 |
| `asyncSignature+marker+propagatedTry` | 9 |
| `asyncSignature+marker+propagatedTry+reducerEffect` | 9 |
| `nonTotal` | 7 |
| `asyncSignature+propagatedTry+reducerEffect` | 6 |
| `asyncSignature+marker` | 4 |
| `propagatedTry+reducerEffect` | 4 |
| `marker+propagatedTry+reducerEffect` | 3 |
| `asyncSignature+reducerEffect` | 2 |
| `marker+reducerEffect` | 2 |
| `asyncSignature` | 1 |
| `nonTotal+propagatedTry` | 1 |

### After item 41 — the authoritative split

Re-run on SEI pin `c66fceb`, same corpus, `markerInDefault` added to the frozen
taxonomy as a **witness** (it names a construct; it is simply not inside the
braces):

| cause | kind | rows |
|---|---|---|
| `propagatedTry` | ignorance, **actionable** | 219 |
| `marker` | witness | 111 |
| **`markerInDefault`** | **witness** | **32** |
| `asyncSignature` | witness | 31 |
| `reducerEffect` | witness | 26 |
| `nonTotal` | witness | 8 |
| `noBody` | ignorance, **inert** | **0** |

The 32 divide into two populations that must not be added together:

- **15 newly refuted** — previously `.pure` while defaulting a parameter to
  `Date()` or a `FileManager` read. These are the rows the fix moved.
- **17 already refuted, and already counted here as rankable ignorance.** Their
  cause set was `propagatedTry` alone; it is now
  `markerInDefault+propagatedTry`. They carry an independent witness, so **no
  annotation on any blocked callee could ever have freed them.**

The four largest cause sets afterwards: `propagatedTry` 135, `marker` 49,
`marker+propagatedTry` 35, `markerInDefault+propagatedTry` 17,
`markerInDefault` 15.

**So the leverage ceiling is 135, not 152** — and finding #2 below, which says a
decline-reason tally over-reports by 44%, now under-states its own point: on the
post-fix numbers `propagatedTry` holds of 219 rows and *blocks* 135, an
over-report of **62%**.

**This is item 32's warning a fourth time, and the sharpest instance yet: the
correction came from closing an unrelated hole, not from re-reading the
ranking.** A leverage report built on the 152 would have promised 17 rows that
nothing could move, and nothing inside the ranking would have revealed it. Every
refuter added *anywhere* shrinks this bucket again, so any build over it must
re-take the number rather than cite this document.

---

## Three findings the split makes visible

### 1. The inert ignorance case is unreachable, so the actionable half is all of it

`noBody` is **0**, and structurally so: `FunctionScannerVisitor` returns
`.skipChildren` on `ProtocolDeclSyntax`, so body-less requirements are never
summarised, and a body-less function declaration outside a protocol does not
exist in Swift.

Two consequences. First, `PurityVerdict.refuted`'s doc names a case *this
consumer cannot produce* — the sentence is true of the type and false of every
use of it here. Second, and the useful half: **every ignorance row has a named
callee behind it**, so a blocking-callee index needs no triage step to separate
the rankable rows from the hopeless ones. All 152 are rankable — **135 after item
41**, which took 17 of them into the witness-bearing half.

### 2. A decline-reason tally over-reports the leverage ceiling by 44%

**Pre-item-41 numbers; the post-fix over-report is 62%, not 44%.** `propagatedTry`
holds of **219** rows. It *blocks* **152**. The other 67 carry a
witness as well and would remain `.refuted` however many callees were resolved.

This is the standing **"state a gain as ROWS MOVED, never LAWS GAINED"** rule
arriving somewhere new, and it is the specific arithmetic error a blocking-callee
report would ship if it counted causes instead of rows: a promised 219 against an
actual ceiling of 152. Note the ratio is much kinder than the ~5:1 recorded
elsewhere — but it is not 1:1, and the report is the only thing anyone would
check.

### 3. 180 entries in the bucket were a default, not a verdict — FIXED 2026-08-17

`makeSummary(fromComputedProperty:)` built a `FunctionSummary` for every
read-only computed property and **passed no `purityVerdict`**, so all 180 under
`Sources/` took `FunctionSummary.init`'s `.refuted` default. They were
simultaneously handed `isInferredPure: true` — unconditionally, with no oracle
consulted — which contradicts the field's own documentation: *"`isInferredPure`
is `purityVerdict == .pure`."*

So **the bucket a consumer read was 464, not 284, and 39% of it was a question
that was never asked.** Any ranking, report or leverage figure built over
`purityVerdict` would have been ranking an initialiser default. That was the
largest single distortion this census found, and it is not in either half of the
taxonomy — it is a third population.

**The fix is `SoundPurity.verdict(forGetter:)`**, and `isInferredPure` is now
*derived* from it rather than asserted beside it. The meet is taken exactly as
the function path takes it — `ReducerPurityAnalyzer` for the TCA/concurrency
surface and static writes, `PurityInferrer.isPure(_ accessor:)` for markers and
totality — because a getter can return a `Task` or write `Self.cache` as readily
as a function can, and claiming `.pure` on one refuter is the lattice-bottom
mistake whatever shape it is claimed about.

| | before | after |
|---|---|---|
| advisory rows (`summaries.filter(\.isInferredPure)`) | 2,597 | **2,597** |
| computed properties among them | 180 | **180** |
| `.refuted` bucket a consumer reads | 464 | **284** |

**0 rows moved, and that is the point.** Both refuters return zero over all 180,
so the unchecked `true` had been accidentally correct on this corpus the whole
time. The A/B was taken with the tree otherwise byte-identical — only the two
assignment lines differed — so the 2,597 is a comparison, not two separate
measurements.

**Never `.pureButPartial`, and that is a filter rather than a property.**
`isReadOnlyGetter` rejects `async` and `throws` accessors before the oracle is
reached, and SEI's accessor entry point is a `Bool` with no third state. If that
filter is ever widened to admit a throwing getter, `verdict(forGetter:)` — not
the filter — is what must learn the distinction, or a partial getter will read as
fully pure.

**Why it survived, and what was done about that.** The invariant *has* a guard —
`PurityVerdictAdoptionTests.boolIsTheCollapse` asserts exactly
`isInferredPure == (purityVerdict == .pure)` — over six cases, **all six of them
`func` declarations**. The computed-property route was the only route that broke
the invariant and the only route the parameterisation never entered. It now
carries two more cases, one per polarity, so an oracle wired to a constant fails
whichever constant it is wired to. `clockReadingGetterIsRefuted` pins the shape
the defect admitted — `var now: Date { Date() }`, which would have been advised
`/// @lint.effect pure` — and was watched failing against the pre-fix code.

That witness is **synthetic on purpose**: the failing shape is one this corpus
does not contain, and the alternative was waiting for a real one to appear.

**Six green cases and a live contradiction** is *verify a suppression by removing
it* wearing different clothes: a guard that never fires on the shape that would
fail it reports the same green as one that holds. The general lesson is about
parameterised guards specifically — the six cases read as thorough coverage of
the invariant, and the count is exactly what made the gap invisible.

**On how this was reported before it was fixed.** The zero base rate came first,
and the wording followed it. Calling the advisory *unsound* on the strength of
the code path alone would have been manufacturing a defect that is not there —
the second of the two recorded ways of doing that. What was true was narrower and
still worth fixing: the claim was unchecked and its base rate here was zero.
`noAccessorInThisRepoIsRefuted` keeps that number under measurement.

---

## What this does and does not license

**Discharged.** The measurement precondition on items 30–33. Ignorance is **45%**
of the bucket (54% before item 41) and 100% actionable, so a blocking-callee
index has a population — 135 rows, not the 152 this document reported for a few
hours. The precondition is discharged on *not a rounding error*, which survives;
it was never discharged on *most of the bucket*, which does not.

**Also discharged, and it was a precondition nobody had filed:** the 180
computed-property defaults are gone, so a ranking can now be built over
`purityVerdict` directly. Doing it in the other order would have computed the
first leverage report over an input 39% of which was noise.

**Not discharged, and not touched by this census:**

- **Whether the ranking has a consumer.** Item 35 — the `pure` advisory is
  outbound-only, nothing reads `@lint.effect pure` back. A leverage report whose
  recommended annotations change nothing when written is a third instance of *a
  vocabulary nobody reads*, not a fix. This census says the bucket is worth
  reading; it does not say a report is the way to read it.
- **Whether the freed laws are refutable.** Item 32's own caveat, and item 22's
  transferable practice: 135 rows moved is only a win if their laws can fail.
  Score any candidate against the laws that HELD.
- **Precision of the witnesses.** 164 rows carry a witness; some of those
  witnesses are deliberate over-refutations (`Date(timeIntervalSince1970:)` is
  deterministic and is refuted anyway). This census counts whether a refutation
  *names* something, never whether the naming is right.

---

## How the replication is trustworthy

`PurityInferrer`'s refuters are `private`, so attributing a cause meant
re-deriving them in the harness. That is normally a drift trap. It is not one
here: the harness re-assembles a **whole verdict** from the replicated pieces and
asserts it equals `SoundPurity.verdict(for:)` on **every function in the
corpus**. A marker missing, a marker spuriously added, a totality rule moved —
each surfaces as a named mismatch on a real function and voids the census loudly
rather than misattributing a cause quietly.

`truncatedMarkerSetIsDetected` is the control: it drops `print` from the marker
set and watches the agreement check fail. Without it, zero mismatches would be
indistinguishable from a comparison that cannot fire.

## Re-running it

```
make batch2          # or: swift test --filter PurityRefutationCensusMeasuredTests
```

The suite prints the full census; the assertions pin the *direction* of each
finding rather than its integer, because the corpus is this repo and grows every
commit. The integers above belong to tree `d6285dff` and should be re-taken, not
extrapolated.

Two things moved after the run, and they are different in kind.

**The corpus size, harmlessly.** Fixing finding 3 added
`SoundPurity.verdict(forGetter:)`, so the function census reads 2,740 / 2,417
`.pure` rather than 2,739 / 2,416. The 284 `.refuted` and its 132 / 152 split
were unchanged — the new function is pure, and the fix touched no refuter.

**The split itself, materially.** Item 41 added a refuter (SEI `c66fceb`), and
the census reads **2,404 `.pure` / 37 `.pureButPartial` / 299 `.refuted`**, split
164 witness / 135 ignorance. That is the reversal recorded above. **The lesson is
about this document, not about the fix:** a census over a corpus is only valid
against the *oracle* it was taken with, and the oracle is a pinned dependency
that can move without any of this repo's own code changing. The provenance table
names the SEI pin for exactly this reason, and it earned its place within a day.
