# What would a purity veto cost?

> **Status:** `measured` · **As of:** 2026-08-18

Re-derivable at any time — `PurityVetoPrecisionMeasuredTests` *is* the harness, and
`make batch2` runs it.

`docs/measurements/purity-refactoring-reach.md` measured the veto's **population** and
said outright that its precision was not measured. This is that measurement, and it
follows this repo's standing rule for a candidate veto: **score it against the laws that
HELD**, not against the class it targets.

**Measured: neither scope removes a single law that found a counterexample.** The naive
veto removes **10** laws that ran and passed; scoping it to witness-bearing refutations
removes **2**. The 8 spared are all `encode(to:)` under `codable-round-trip` — the one
template measured at 100% yield.

---

## "False positive" had to be defined before it could be counted

A veto's cost is the good laws it removes. But **`measured-bothPass` does not mean the
property holds** — CLAUDE.md says so outright: it means *no counterexample in the
generated domain*. For an impure subject that is exactly the ambiguous case. A `predicate`
law over `isDirectory(_:)` can pass because the filesystem cooperated, and counting that
pass as a good law would assume the answer this census exists to test.

So a removal is priced four ways, and only the first is an unambiguous loss:

| bucket | recorded outcome | what removing it costs |
|---|---|---|
| **`refuted`** | `measured-defaultFails` | **a law that found a counterexample** — real work, clearly lost |
| `passed` | `measured-bothPass` | it ran and did not refute — **ambiguous**, and suspect exactly where the subject is impure |
| `inert` | `architectural-coverage-pending` / `measured-error` | nothing measurable — it never ran |
| `unrecorded` | *(absent)* | not in the answer key; **priced by nothing** |

---

## Provenance

| | |
|---|---|
| corpus | this repo's `Sources/` — the only corpus with a recorded survey |
| answer key | `fixtures/whole-corpus-survey/2026-08-05-whole-corpus.jsonl`, 281 rows, 139 executed |
| key's subject | `SwiftInferProperties@1ef7128`, 2026-08-05 — **13 days older than this run** |
| join | `SuggestionIdentity.display`, which *is* the survey's `identityHash` |
| scope rule | `PackagePurityJoin.refutingNames`, reused rather than restated |
| harness | `Tests/SwiftInferCoreTests/PurityVetoPrecisionMeasuredTests.swift` (+`Support`) |

**The join is exact, not name-keyed.** Name-keying has been the dominant defect at this
seam in three measurements, and `isDirectory(_:)` alone has two declarations here.

**And the join survived a signature change, which is worth recording.** `isStale` gained a
`diagnostic:` parameter since 2026-08-05 — the survey row reads
`isStale(indexPath:packageRoot:)` and the current declaration is
`isStale(indexPath:packageRoot:diagnostic:)` — and the identity still matched. That is
what a stable cross-run identity is *for*, and it is the property
`fixtures/verify-runs/README.md` exists to defend. Every match is same-template and
same-base-name; no cross-function matches occurred.

**The scope predicate is the shipped one.** `witness-bearing` here means what
`PackagePurityJoin` means by it — a `.refuted` declaration that does not throw, or one
whose body reaches a settled-impure name — because a census scoring a veto against a
*restatement* of its rule would be scoring the restatement.

---

## The measurement

**712 suggestions · 274 with a survey row · 20 resting on a refuted subject.**

| veto scope | removed | **`refuted`** | `passed` | `inert` | `unrecorded` |
|---|---|---|---|---|---|
| on `.refuted` outright | **20** | **0** | **10** | 3 | 7 |
| scoped to witness-bearing | **8** | **0** | **2** | 2 | 4 |

### The headline is the zero

**Neither scope removes a law that found a counterexample.** The unambiguous loss — a law
that did refuting work and would be suppressed — is **zero at both scopes**. Whatever else
a veto costs here, it does not cost a refutation.

### The scoping recommendation is now priced, and it holds

The refactoring-reach census recommended scoping to witness-bearing refutations rather
than vetoing on `.refuted` outright. That was an argument; it is now a number. **Scoping
spares 8 passing laws, and all 8 are `encode(to:)` under `codable-round-trip`** — refuted
only by `propagatedTry`, which is the analyzer failing to see past a `try` rather than
evidence of an impurity. `encode(to:)` throws because the `Encoder` API throws.

**Item 32's arithmetic a fifth time**: the broad tally is 20 and the actionable scope is 8,
so a veto sized from the raw population would over-report its own reach by 2.5×.

### The two passing laws the scoped veto still removes

`predicate :: isDirectory(_:)` and `predicate :: isStale(...)` — both `measured-bothPass`,
both reading the filesystem. **These are the cases the veto exists for, not the cases it
gets wrong.** A `predicate` law whose subject stats a path passes when the path happens to
be there; the pass is a fact about the machine, not about the function. Removing them is
the intended effect and should not be counted as a cost.

That leaves the scoped veto with a measured cost of **zero refutations and two passes it
should arguably be removing anyway** — which is as close to free as this apparatus can
show.

---

## The control fired, and was corrected rather than relaxed

**Its first version asserted that half of all 712 suggestions carry a survey row. 274 do,
so it failed.** The gap is not drift: the survey's own README says **"281 records, one per
**index** entry"** — a filtered population that was never a map of every suggestion. The
assertion compared a *discover* population against an *index* one and would have failed at
any corpus size and any staleness.

What the control guards is one threat — **a join that resolves nothing reports a veto that
costs nothing** — and the quantity that threat turns on is what fraction of the *removals*
are priced. That is **13 of 20**, and the control now asserts it.

**Recorded because the distinction is the whole difference between correcting an
instrument and fitting it to its result.** A threshold moved because the number came out
wrong is the second thing; a predicate replaced because it compared the wrong two
populations is the first.

---

## What this does NOT establish

**Anything about the 7 unrecorded removals**, four of them in the scoped population.
They are absent from the index the survey was taken over, so nothing here prices them.
The honest ceiling on the scoped veto's cost is therefore *2 passes plus up to 4 unknowns*.

**Anything about another corpus.** OrderedCollections and SwiftPropertyLaws have no
recorded survey, so their removals — including the 6 the one-hop join added — are unpriced.

**That the 2 passing laws are wrong.** They ran and did not refute. The argument that a
filesystem predicate's pass is untrustworthy is a *reading* of that outcome, and it is
stated as one.

**That a veto should ship.** This prices one; it does not decide it. What it removes from
the decision is the objection that the cost is unknown.

---

## The verdict

**A witness-scoped veto is affordable on this corpus**: 0 refutations, 2 passes both of
which are the intended target, 4 unpriced.

**A veto on `.refuted` outright is not the same thing and should not be shipped as though
it were**: 10 passing laws, 8 of them under the only template with 100% yield, all
suppressed for a refutation that is the analyzer reporting its own blindness.

## What would reverse this

- **A removal lands in `refuted`.** Pinned by `noVetoScopeRemovesARefutingLaw`; it is the
  only unambiguous loss and it is currently zero at both scopes.
- **Scoping stops sparing anything.** Pinned by `scopingSparesThePasses` — the
  recommendation rests entirely on that gap.
- **The removals stop being mostly priced.** Pinned by the control. At that point the
  survey is due a re-take rather than a citation.
