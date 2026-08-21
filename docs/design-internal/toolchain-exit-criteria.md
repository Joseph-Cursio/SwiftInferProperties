# Exit criteria for "the toolchain is in shape"

> **Status:** `open` · **As of:** 2026-08-20

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
and it has not been done.

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

## 5. Proposed criteria — for ratification, not adoption

Offered strict, per the 2026-08-03 instruction. **Reject or soften deliberately; that is
the decision this document is asking for.**

| # | Proposed | Why this bar | Measured today |
|---|---|---|---|
| A | On a subject the toolchain has never met, ≥1 emitted law **kills a mutant** the subject's existing tests miss | the purpose, in refutation units | unmeasured |
| B | The runnable-tier ratio holds ≥60% across the 17 corpora, not just the home corpus | generality, in a number meant to be quoted | 65% home; cross-corpus unmeasured |
| C | Zero templates unwitnessed across all 17 corpora | closes §2.2 with the wider list | 4 unwitnessed at 8 corpora |
| D | An app-shaped subject reaches `verified` by some route | §2.4's outcome form | not met |
| E | No measurement doc older than its binary — every published figure re-derivable | §2.3's positive form | unmeasured, unscoped |

**A is the one that matters.** B–E are capability bars that make A possible; A is the
only one that would tell you the toolchain is worth using.

---

## 6. What this document is asking for

1. **Ratify, soften or reject A–E.** Unwritten criteria are the failure mode; wrong
   criteria are recoverable.
2. **Retire candidates 1 and 3 as written** — one promotes a diagnostic-only figure, the
   other is satisfiable by not looking.
3. **Take the one concrete action that already follows**: re-run the catalog health
   census over 17 corpora (§2.2). It needs no decision, and it is the third repetition of
   a lesson this repo has already paid for twice.

## 7. What would refute this document

- **A ratified bar that A–E do not cover.** These are proposals from the inside; the
  purpose belongs to the maintainer.
- **The catalog re-run resolving all four unwitnessed templates**, which would make C
  free and suggest B is measuring the wrong scarcity.
- **An outcome measurement showing movement.** The §3 table is five results, not a law.
  One measurement that moves rows would reframe the whole section.
