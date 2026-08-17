# What is actually inside `PurityVerdict.refuted`?

> **Status:** `measured` · **As of:** 2026-08-17

Re-derivable at any time — `PurityRefutationCensusMeasuredTests` *is* the
harness, and `make batch2` runs it.

Discharges the measurement precondition on open-threads item 29, which is the
precondition on items 30–33.

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

## The split — the answer

| | rows | share of `.refuted` |
|---|---|---|
| **witness-bearing** — at least one named construct refutes | 132 | 46% |
| **ignorance-only** — nothing in the source refutes | **152** | **54%** |

**Ignorance is the majority.** Not a rounding error. The measurement therefore
comes back in the direction that *permits* items 30–33 rather than closing them.

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
the rankable rows from the hopeless ones. All 152 are rankable.

### 2. A decline-reason tally over-reports the leverage ceiling by 44%

`propagatedTry` holds of **219** rows. It *blocks* **152**. The other 67 carry a
witness as well and would remain `.refuted` however many callees were resolved.

This is the standing **"state a gain as ROWS MOVED, never LAWS GAINED"** rule
arriving somewhere new, and it is the specific arithmetic error a blocking-callee
report would ship if it counted causes instead of rows: a promised 219 against an
actual ceiling of 152. Note the ratio is much kinder than the ~5:1 recorded
elsewhere — but it is not 1:1, and the report is the only thing anyone would
check.

### 3. 180 entries in the bucket are a default, not a verdict

`makeSummary(fromComputedProperty:)` builds a `FunctionSummary` for every
read-only computed property and **passes no `purityVerdict`**, so all 180 under
`Sources/` take `FunctionSummary.init`'s `.refuted` default. They are
simultaneously handed `isInferredPure: true` — unconditionally, with no oracle
consulted — which contradicts the field's own documentation: *"`isInferredPure`
is `purityVerdict == .pure`."*

So **the bucket a consumer reads is 464, not 284, and 39% of it is a question
that was never asked.** Any ranking, report or leverage figure built over
`purityVerdict` without excluding computed properties is ranking an initialiser
default. That is the largest single distortion this census found, and it is not
in either half of the taxonomy — it is a third population.

**Why it survived: the invariant has a guard, and the guard cannot reach the
violating path.** `PurityVerdictAdoptionTests.boolIsTheCollapse` asserts exactly
`isInferredPure == (purityVerdict == .pure)` — over six cases, **all of them
`func` declarations**. The computed-property route is the only route that breaks
the invariant and it is the one route the parameterisation does not enter. Six
green cases and a live contradiction, which is *verify a suppression by removing
it* wearing different clothes: a guard that never fires on the shape that would
fail it reports the same green as one that holds.

**The unchecked `true` has cost nothing measured.**
`PurityInferrer.isPure(_ accessor:)` is the right oracle for a getter, it exists,
and it is simply not called; run over the same 180 it refutes **0**. So no false
`/// @lint.effect pure` advisory has been emitted on this corpus.

Reported that way on purpose. Calling the advisory *unsound* on the strength of
the code path alone would be manufacturing a defect that is not there — the
second of the two recorded ways of doing that. What is true is narrower and still
worth fixing: **the claim is unchecked and its base rate here is zero.** The
failure mode it admits is real — `var now: Date { Date() }` would be advised
`pure` — and `computedPropertyAdviceIsAccidentallyCorrect` fails the day one
appears.

---

## What this does and does not license

**Discharged.** The measurement precondition on items 30–33. Ignorance is 54% of
the bucket and 100% actionable, so a blocking-callee index has a population.

**Not discharged, and not touched by this census:**

- **Whether the ranking has a consumer.** Item 35 — the `pure` advisory is
  outbound-only, nothing reads `@lint.effect pure` back. A leverage report whose
  recommended annotations change nothing when written is a third instance of *a
  vocabulary nobody reads*, not a fix. This census says the bucket is worth
  reading; it does not say a report is the way to read it.
- **Whether the freed laws are refutable.** Item 32's own caveat, and item 22's
  transferable practice: 152 rows moved is only a win if their laws can fail.
  Score any candidate against the laws that HELD.
- **Precision of the witnesses.** 132 rows carry a witness; some of those
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
