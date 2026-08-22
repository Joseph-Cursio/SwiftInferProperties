# Exit criteria for "the toolchain is in shape"

> **Status:** `open` · **As of:** 2026-08-22

Open item 8 has said *"exit criteria are unwritten"* since the item list began. This
scores the criteria that **were** written — on 2026-08-03, inside a decision note, where
nobody looked at them again — and asks for a decision on the ones that are missing.

**Nothing here is ratified.** §5 is a proposal; the choice of bar is the maintainer's.

---

## 1. Why an unwritten bar is not a neutral state

The 2026-08-03 note (*Road tests were misfiled, not mistimed*) named the trap precisely:

> *"not ready to measure yet"* is unfalsifiable — the confident zero of project
> planning, always defensible, forever. **Write the exit criteria while inclined to be
> strict.**

Seventeen days later the criteria are still unwritten, which is that prediction coming
true rather than an accident. **This document exists because the note anticipated its
own neglect and nothing acted on it** — the same shape as row 46's *"do not carry this
zero"*, which also sat undischarged until someone re-read it.

---

## 2. The four candidates, scored

The note proposed four. None had been checked since.

| # | Candidate criterion | Status today |
|---|---|---|
| 1 | composer reach past **38%** | ⚠️ **ill-posed** — see §2.1 |
| 2 | the **5 dead templates** diagnosed | 🟡 **partly** — 5 → 4, and reframed |
| 3 | the **instrument-error class** closed | 🟡 **unfalsifiable as stated** |
| 4 | `--sources` no longer gating app code out of measured verify | 🔴 **not met, by design** |

### 2.1 Composer reach — the number is real, the criterion is not

38% is from `kit-suite-backtest-arms-2-3.md` §5, Arm 3, whose own header reads:

> *"derivation and compile rate (diagnostic only). Per the plan: context, never a
> headline, and not to be read without Arms 1 and 2."*

**A figure explicitly labelled "never a headline" cannot be a release gate.** Promoting
it is the mistake §5 of that doc exists to prevent, and the criterion should be
rewritten against a number meant to be quoted — the runnable-tier ratio in
`fixtures/whole-corpus-survey/` (**178 of 272 = 65%**) is the closest candidate, and it
has its own trap: quote the *runnable tiers*, never the 178/538 total.

### 2.2 Dead templates — 5 became 4, and the four changed meaning

§10.5 of the swift.org findings moved the list from five to four and reframed the
remainder as **unwitnessed on a known corpus set**, not inert. `involution` was never
dead; its witness predated the census.

**The criterion is now measurable in a way it was not:** those four were unwitnessed
across **eight** corpora, and `CorpusManifest` now resolves **seventeen**. §10.5's own
process finding is the reason this matters:

> *a census is only as wide as its corpus list, and its zero row is the one cell that
> cannot be trusted without knowing that list.*

That is the third time this exact lesson has been paid for — §10.5, then the
three-corpus censuses re-taken 2026-08-19, then row 46's module-state zero. **Re-running
the catalog health census over 17 corpora is the concrete action this criterion implies**
— **done 2026-08-20**, `docs/measurements/catalog-health-17-corpora.md`. `partition`
resolved; three remain, plus `invariant-preservation`, which is deferred rather than
broken. **And it returned a finding about the criterion itself**: there is no trustworthy
runtime catalogue of templates, so a bar phrased over *all* templates cannot be
evaluated at all. C is restated in §5 to the form that can.

### 2.3 Instrument error — closed cannot be shown, only not-yet-refuted

Pass 2 was fixed, and it was the big one. But *"the instrument-error class is closed"* is
a claim of absence, and the record argues against ever asserting it: the
swiftformat/GRDB exploration found **five instrument defects on one subject**, and
**three of the five were in code shipped hours earlier the same day**.

**A bar of "no known instrument defects" is satisfiable by not looking.** If this stays a
criterion it needs a positive form — e.g. *every measurement doc published in the last N
days has been re-derived against the current binary* — which is the A/B rule generalised,
and is work nobody has scoped.

### 2.4 `--sources` — not met, and deliberately

`--sources` reaches four commands. `verify-interaction` is **excluded on purpose**: it
synthesises a verifier that does `import <module>`, so `--sources` would fail later and
say less. CLAUDE.md states the cost plainly:

> *the measured-verify path stays unreachable for Xcode projects, so app findings stay at
> `Possible`.*

So the criterion as written can only be met by reversing a decision that was taken for a
good reason. **It should be restated as an outcome** — *an app-shaped subject can reach a
`verified` tier by some route* — which leaves the route open.

---

## 3. What the four candidates all miss

Every one is a **capability** bar: can the tool do X. None is an **outcome** bar: does
using it change anything.

That gap matters now in a way it did not in August. The last five measurements, all
well-made, all say *no movement*:

| measurement | result |
|---|---|
| purity refactoring reach | **0** rows moved, at a ceiling |
| parameter roles | declined — 2 role-distinct of 118 |
| cross-type round-trip | no action — 1.1% elsewhere vs 96% here |
| module-state base rate | 5 of 20,526 |
| `Result` carrier reach | **−53** performable |

**That may be exactly right.** Conservative inference is the stated design (PRD §3.5),
and a tool that correctly declines is working. But with no outcome bar there is no way to
tell *"the tool is correctly declining"* from *"we are measuring the wrong things"* — and
those call for opposite responses.

---

## 4. The candidate nobody has stated

The toolchain's purpose is to get **property tests that would reject a wrong
implementation** into repositories that lack them. Every criterion above is upstream of
that. The measurable form already exists in this repo's vocabulary:

- **Refutation units, not suggestion counts.** The standing rule is *score refutability*;
  `fixtures/integer-division-generator/` reports 2/8 → 8/8 mutants killed, which is what
  a real outcome bar looks like.
- **Rows moved, not laws gained.** Also standing, and the ~5:1 ratio against is measured.

An outcome criterion in those units would be falsifiable, and none of the four is.

---

## 5. The criteria — RATIFIED 2026-08-21, A SPLIT 2026-08-22

**A is the bar. B–E are supporting measurements and do NOT gate.**

**A is now two bars, A-reach and A-quality.** Split by the maintainer on 2026-08-22. The
split itself is ratified; the specific thresholds in §5.1 are a proposal, and a later reader
should be able to tell those apart.

Ratified by the maintainer on 2026-08-21, which is what open item 8 had been waiting for
since the list began. The reasoning for taking A alone: **it is the only outcome bar**,
and this cycle demonstrated why that matters — every capability bar can pass while the
tool emits code that does not compile. Nine reach measurements were taken and none could
have found the 89%; one outcome attempt did, on its first subject.

B–E stay in this table because they are worth measuring and worth quoting. **They are not
conditions of being in shape**, and a future reading that treats them as gates is reading
this document wrong.

| # | Proposed | Why this bar | Measured today |
|---|---|---|---|
| **A-reach** | On a subject the toolchain has never met, **≥1 emitted law runs to a PASSING verdict** under a stressed trial budget | you cannot aim a mutant at a law that does not run | **MET 2026-08-22, for the first time** — `swift-system`, 2 laws (`isSeparator`, `isPrenormalSeparator`) hold at 5,000 trials. `docs/measurements/criterion-a-swift-system.md` §8 |
| **A-quality** | ≥1 of those passing laws **kills a mutant** the subject's existing tests miss | the purpose, in refutation units | **ANSWERED 2026-08-22 — NO at the shipped budget, YES at N ≥ 500.** `swift-system`, `isSeparator(_:)` totality vs a NUL-guard mutant: their 78 tests miss it, the law misses it at N=100 and kills it at N=500. `docs/measurements/criterion-a-quality-swift-system.md` |
| B | The runnable-tier ratio holds ≥60% across the 17 corpora, not just the home corpus | generality, in a number meant to be quoted | 65% home; cross-corpus unmeasured |
| C | ~~Zero templates unwitnessed across all 17 corpora~~ → **no template in the RECORDED zero row is still unwitnessed** | closes §2.2 with the wider list; **restated 2026-08-20 because the original is unevaluable** — a criterion over *all* templates needs a catalogue and there is none | **not met: 4 remain**, one deferred. `partition` resolved. `docs/measurements/catalog-health-17-corpora.md` |
| D | An app-shaped subject reaches `verified` by some route | §2.4's outcome form | not met |
| E | No measurement doc older than its binary — every published figure re-derivable | §2.3's positive form | unmeasured, unscoped |

### 5.1 Why A splits, and where the thresholds come from

**Three subjects were attempted and A was evaluable on none.** Each time the report read
*A fails*, and each time the sentence was about the pipeline, not about the laws:
`swift-http-types` died at 89% non-compiling output, `swift-system` at a module-resolution
bug, and underneath that at generator domain. A bar that reports pipeline completeness while
claiming to report law quality is the same defect §3 diagnoses in candidates 1–4, arrived at
from the other side — **A had quietly become a capability bar too.**

Split, the two failure modes read differently, which is the whole point:

| A-reach | A-quality | reading |
|---|---|---|
| fails | — | the **pipeline** is the constraint; law quality is unmeasured and no verdict about it follows |
| passes | fails | the **laws** are the constraint |
| passes | passes | in shape, on that subject |

**Why A-reach's threshold is a *passing* law rather than an executing one.** It follows from
two measured facts rather than from taste:

- **A trapped law yields no verdict**, so nothing can be planted against it. Nine of
  swift-system's rows were traps.
- **A refuted law is, on all evidence here, a false law** — 17 of 17 across this project
  (15 in `refutation-hand-check.md`, plus `pushing(_:)` and `removingLastComponent()`).
  Planting a violating mutant against a law that is already false says nothing.

So a passing law is the *only* kind a mutant test can be aimed at, and "≥1 passing law" is
the minimum condition for A-quality to mean anything. It is a precondition, not a
consolation prize.

**Why "under a stressed trial budget".** `removingLastComponent()` passed 100 trials and
**failed at 2,000**. A law that passes only because the budget was small is a false law
wearing a pass, and a mutant planted against it produces a confident answer to a question
that was never asked. **The budget used must be recorded beside any A-reach claim.**

**What A-reach deliberately does NOT require.** No ratio, no count beyond one, and no
coverage of the catalogue. Those are B's job. A-reach exists to answer one question — *is
there anything here to aim a mutant at* — and a threshold that also smuggled in generality
would be unevaluable for the reason C already had to be restated.

### 5.2 The confound A-quality now inherits

Splitting the bar makes something visible that the joined version hid: **the evidence we
already have about executing laws is not encouraging.** Every refutation this project has
hand-checked is a false law, one of swift-system's three passes was false at a higher
budget, and the two laws that survive stress are **totality predicates** — arguably the
least discriminating family in the catalogue.

That does not make A-quality unanswerable; a totality law is a perfectly good mutant target
(make the predicate non-total and see whether the subject's tests notice). It does mean
**A-quality should not be expected to pass merely because A-reach did**, and a failure there
would be a finding about the catalogue rather than about the pipeline. Which is exactly the
distinction the split was made to expose.

**A is the bar, and B–E are context.** They are capability bars that make A possible; A
is the only one that says the toolchain is worth using.

**A was attempted, and the attempt is the argument for an outcome bar in one line.** It did
not need ratification to be informative — and it found what **nine reach measurements could
not**: 89% of emitted laws did not compile on an unmet subject. Three emitter defects,
since fixed.

**A itself is NOT ANSWERED**, and this document said "FAILS" until 2026-08-21. That was
wrong: the planted mutants were real correctness bugs that **preserve idempotence**, so the
laws' passes were correct and no verdict about their refutation power follows.
**Answering A needs a defect chosen to violate the law**, not one chosen for realism —
`fixtures/branch-reaching-generator/` §3 has the correction and the rule.

---

### 5.3 A-quality answered — and the budget, not the law, is what fails

**Answered 2026-08-22 on `swift-system`: NO at the shipped budget, YES at N ≥ 500.**
`criterion-a-quality-swift-system.md` has the arms; the part that belongs in the criteria is
what it says about the bar itself.

**The bar is budget-dependent, and nothing said so.** A-reach already carries *"under a
stressed trial budget"* because `removingLastComponent()` passed at 100 and failed at 2,000.
A-quality now needs the same clause for the mirror-image reason: the NUL mutant passes at 100
and is killed at 500. **Both failure modes a budget has — a false law passing, a real defect
surviving — were measured on one subject within a day, at the same N.**

So **A-quality inherits A-reach's budget clause**, and a claim on either bar that does not
quote its N is not a claim.

**The default was then raised, 2026-08-22: N=100 → N=1000.** This section previously declined
to propose one because the cost was unmeasured; it was measured, and the premise behind
`small` is false. A stub costs **3.56 s to build** and **0.022 s to run 100 trials** — verify
is compile-bound, so the 10× budget costs **~5 ms, 0.14% of the per-row cost**. N=1000 clears
both measured failures (the false law fails at 250, the planted defect dies at 500), checked
rather than assumed. `small` still means N=100 and remains available.

**A control was required and should be required again.** One mutant would have shown only
*the law missed it*, leaving blind-law and unlucky-draw indistinguishable. A second mutant
whose violating input is common was killed at trial 9 — establishing the law is under-budgeted
rather than blind — **and was also caught by the subject's own tests**, which is the finding
that gives the bar its edge: where the violating input is common the law adds nothing, and its
whole value is on the rare input the subject's suite cannot reach. **A-quality run without a
common-input control cannot tell those apart, and should not be reported.**

## 6. The standing question, now that A is two bars

**A-reach is MET. A-quality is answerable for the first time, and answering it is the open
work.** What that needs, specifically:

1. **Plant a mutant against one of the two passing laws.** `isSeparator(_:)` and
   `isPrenormalSeparator(_:)` on `swift-system` hold at 5,000 trials. Both are totality
   predicates, so the violating mutant is one that makes the predicate non-total — and the
   bar requires that **swift-system's own test suite miss it**, which must be checked rather
   than assumed.
2. **A defect chosen to VIOLATE the law**, not chosen for realism. The first attempt planted
   three real correctness bugs that all preserved idempotence, so the laws' passes were
   correct and no verdict followed. `fixtures/branch-reaching-generator/` §3 has the rule:
   *a mutant is evidence about a law only if it violates that law.*
3. **Record the trial budget beside the result.** §5.1's second threshold exists because
   `removingLastComponent()` passed at 100 and failed at 2,000.

### 6.1 Choosing the next subject — a lesson from three of them

`swift-http-types` and GRDB are spent, and `swift-algorithms` was disqualified before use
because the manifest records it in the v1 algebraic corpus. **Check the manifest before
choosing; it recorded both facts and one grep saved a contaminated result.**

But *unmet* is not the only thing to select for, and treating it as such is what cost three
attempts. **A-reach's length is a property of the subject.** swift-system is close to
worst-case for it: a relocated target directory, C interop throughout, internal types whose
invariants live in `#if DEBUG` preconditions, and byte-oriented storage. Every one of those
became a blocker, and each was invisible until the previous was fixed.

So select for **unmet AND short-chain**: public value types, memberwise or clearly-public
initializers, no C interop. There is a cheap pre-check that costs one run — point
`verify --all-from-index` at the candidate and read **how many rows reach the build stage**
before committing to it. swift-system's first honest reading was **0 of 41**, and that
number was itself the signal that the chain was long.

## 7. What this document used to ask for

1. **Ratify, soften or reject A–E.** Unwritten criteria are the failure mode; wrong
   criteria are recoverable.
2. **Retire candidates 1 and 3 as written** — one promotes a diagnostic-only figure, the
   other is satisfiable by not looking.
3. ~~**Take the one concrete action that already follows**: re-run the catalog health
   census over 17 corpora (§2.2).~~ **DONE 2026-08-20.** It resolved `partition`, left
   three, and produced a finding that outranks its own result: **a criterion phrased over
   "all templates" is unevaluable**, because naming a zero needs a catalogue this project
   does not have. C is restated accordingly. The first run of that census got its own
   denominator wrong in exactly that way and was caught by a control — which is the
   argument for A–E being written as things that can *fail*, not as things that sound
   strict.

## 7. What would refute this document

- **A ratified bar that A–E do not cover.** These are proposals from the inside; the
  purpose belongs to the maintainer.
- **A-quality passing while the toolchain is plainly not worth using**, or failing while it
  plainly is. The split in §5 is a claim that these two questions come apart cleanly; one
  subject where the answer is obvious and the bar disagrees would refute it.
- **A refutation that turns out to be a REAL bug.** §5.1 rests A-reach's threshold on 17 of
  17 hand-checked refutations being false laws. A single true one would not overturn the
  threshold, but it would remove the reason for it, and the reasoning would have to be
  rebuilt on something else.
- **The catalog re-run resolving all four unwitnessed templates**, which would make C
  free and suggest B is measuring the wrong scarcity.
- **An outcome measurement showing movement.** The §3 table is five results, not a law.
  One measurement that moves rows would reframe the whole section.
