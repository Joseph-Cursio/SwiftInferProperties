# Exit criteria for "the toolchain is in shape"

> **Status:** `open` · **As of:** 2026-08-24

Open item 8 has said *"exit criteria are unwritten"* since the item list began. This
scores the criteria that **were** written — on 2026-08-03, inside a decision note, where
nobody looked at them again — and asks for a decision on the ones that are missing.

**A is RATIFIED and MET, both halves** — A-reach 2026-08-22 (`swift-system`), A-quality
2026-08-23 (`mcp-swift-sdk`). B–E are supporting measurements and do **not** gate. §5 is the
criteria and their scoring; **§6 is the current standing, and supersedes any earlier
statement of open work in this file.**

<!-- doc-provenance date=2026-08-25 subject=SwiftInferProperties@4477c25f observer=SwiftInferProperties@4477c25fe23d12e28e905e1aac6dd6e6dc120b6a -->

> **Why this trailer arrived late.** `make docs-drift` reported this file as *no doc-provenance
> trailer* — which its own header calls a **broken check, not a clean bill**: exit 1 is reserved
> for *the check could not answer*, precisely so a missing answer never reads as "no drift". This
> file scored staleness elsewhere while being the one doc the staleness checker could not see.
> The SHA means **this doc was reviewed against that tree**, not that any figure in it was
> re-measured there — the same rule `open-threads.md` states for its own trailer.

> ⚠ **This header read *"Nothing here is ratified. §5 is a proposal"* until 2026-08-24**,
> three days after ratification and one day after the bar was met — while §5's own title said
> RATIFIED. It is recorded rather than quietly replaced because it is this file's second
> instance of the same defect in one pass: §6 went on prescribing work §5.4 had already
> completed. **A document that scores staleness elsewhere is not exempt from it**, and both
> stale claims were in the two places a reader looks first.

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
— **done 2026-08-20**, `docs/measurements/catalog-health-census.md`. `partition`
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
| **A-quality** | ≥1 of those passing laws **kills a mutant** the subject's existing tests miss | the purpose, in refutation units | **ANSWERED YES 2026-08-23 on `mcp-swift-sdk`, and by a REAL defect rather than a planted one** — `codable-round-trip` on `ToolChoice` refuted on the subject as shipped, and their **551-test suite misses it**. `docs/measurements/criterion-a-quality-mcp.md`. Earlier, weaker answer on `swift-system` (planted mutant): **NO at the shipped budget, YES at N ≥ 500** — `criterion-a-quality-swift-system.md` |
| B | The runnable-tier ratio holds ≥60% across the 17 corpora, not just the home corpus | generality, in a number meant to be quoted | 65% home; cross-corpus unmeasured |
| C | ~~Zero templates unwitnessed across all 17 corpora~~ → **no template in the RECORDED zero row is still unwitnessed** | closes §2.2 with the wider list; **restated 2026-08-20 because the original is unevaluable** — a criterion over *all* templates needs a catalogue and there is none | **not met: 4 remain**, one deferred. `partition` resolved. `docs/measurements/catalog-health-census.md` |
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

> ⚠ **Both this table's first row and the second bullet below were CORRECTED 2026-08-23 by the
> route that met A-quality — see §6.2.** They hold for the **mutant route** and were mistaken
> for general claims. Do not quote either without §6.2.

| A-reach | A-quality | reading |
|---|---|---|
| fails | — | the **pipeline** is the constraint; law quality is unmeasured and no verdict about it follows ⚠ **too strong — a refutation on shipped code is a verdict, and needs no passing law; §6.2** |
| passes | fails | the **laws** are the constraint |
| passes | passes | in shape, on that subject ⚠ **never demonstrated on ONE subject — the two halves were met on different ones; §6.2** |

**Why A-reach's threshold is a *passing* law rather than an executing one.** It follows from
two measured facts rather than from taste:

- **A trapped law yields no verdict**, so nothing can be planted against it. Nine of
  swift-system's rows were traps.
- **A refuted law is, on all evidence here, a false law** — 17 of 17 across this project
  (15 in `refutation-hand-check.md`, plus `pushing(_:)` and `removingLastComponent()`).
  Planting a violating mutant against a law that is already false says nothing.
  ⚠ **FALSIFIED 2026-08-23, by the refutation that met A-quality** — the tally is now
  **18 FALSE of 19 hand-checked**, and the 1 real is `ToolChoice` on `mcp-swift-sdk`. The prior stays strong and
  the decline advice is unchanged; what is gone is the *exceptionless* form this bullet used.

**Both corrections run in the same direction: the thresholds were STRICTER than the purpose
required.** A-reach remains the right precondition for planting a mutant. It is not a
precondition for A-quality as such, and treating it as one would have sent the next attempt
down the longer of two routes.

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

~~**A itself is NOT ANSWERED**~~ — **SUPERSEDED 2026-08-23 by §5.3 and §5.4; both halves are
now MET.** The paragraph is kept struck rather than deleted because the rule inside it is
still live and cited elsewhere. As written: this document said "FAILS" until 2026-08-21, and
that was wrong — the planted mutants were real correctness bugs that **preserve idempotence**,
so the laws' passes were correct and no verdict about their refutation power follows.
**A planted defect must be chosen to violate the law**, not chosen for realism —
`fixtures/branch-reaching-generator/` §3 has the correction and the rule. That rule survives
the supersession and applies to any future mutant; what does not survive is the *NOT ANSWERED*
verdict attached to it.

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

### 5.4 A-quality met on a short-chain subject, without a mutant

**Answered YES on `mcp-swift-sdk` @ `a0ae212`, 2026-08-23.** The law refuted on the subject as
shipped: `CreateSamplingMessage.ToolChoice` encodes `mode: nil` and `mode: .auto` to
byte-identical JSON while `Equatable`/`Hashable` distinguish them, so a codable round trip does
not preserve the value. Their 551 tests pass and mention `ToolChoice` **zero** times.

**No mutant was planted, and that is worth being precise about.** The bar is phrased around a
planted defect because planted evidence is *guaranteed* to be a defect — the adjudication is
free. A found defect moves that cost to the reader: someone must decide whether the refutation
is real. Here it was hand-checked and independently reproduced against the package before the
claim was made. **A found defect is stronger evidence than a planted one when the adjudication
holds, and worthless when it does not** — so the standard for reporting one must be a repro,
not a reading.

**§6.1's short-chain rule predicted this before the run.** MCP executes **10 of 67 rows on the
first attempt with zero fixes**, against swift-system's **0 of 41**, and the structural criteria
(173 public value types to 2 classes, no C interop, target name matching its directory) were
read off the package beforehand. The one-run pre-check works.

**The catalogue reading changes shape, though not much.** The refuting template is
`codable-round-trip` — a law the code *owes*, since the type declares `Codable` and `Equatable`
and those two conformances make the claim between them. All 18 previously hand-checked
refutations were `idempotence` or its operand form, which the tool's own caveat calls a
conjecture. **Tally: 1 real of 19.** One data point, and the first suggesting *which template
refutes* carries information.

## 6. A is MET, both halves — and the route taken was not the one this document planned

**A-reach MET 2026-08-22 (`swift-system`). A-quality MET 2026-08-23 (`mcp-swift-sdk`).**
The bar ratified on 2026-08-21 is cleared. §5.3 and §5.4 are the results; this section
records what the open work *was*, what survived it, and the one thing the route falsified.

**This section prescribed three steps until 2026-08-23 and they were never taken.** They are
kept here because two of the three survive as standing rules, and because a plan overtaken by
a different route is worth distinguishing from a plan that was followed:

1. ~~**Plant a mutant against one of the two passing laws**~~ — `isSeparator(_:)` /
   `isPrenormalSeparator(_:)` on `swift-system`, both holding at 5,000 trials. **Not done, and
   no longer needed for the bar.** It remains the only route that would answer A-quality *on
   swift-system*, which §6.2 argues is still worth having.
2. **A planted defect must be chosen to VIOLATE the law**, not for realism. **Survives** —
   `fixtures/branch-reaching-generator/` §3: *a mutant is evidence about a law only if it
   violates that law.* Applies to any future mutant.
3. **Record the trial budget beside the result.** **Survives**, and is now §5.1's second
   threshold: `removingLastComponent()` passed at 100 and failed at 2,000.

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

⚠ **AMENDED 2026-08-24, after the rule was USED and came up short.** Two subjects were selected
by every clause above — `swift-aws-lambda-events` and `MacPaw/OpenAI`, both public value types,
both zero C interop, both target-directory-matching — and they executed **1 of 15** and **0 of
55**. The clauses are about the *subject*; they say nothing about whether the **template** has a
population there. Two further clauses, each measured:

- **A template's population is an INTERSECTION, not a conformance count.** `codable-round-trip`
  needs `Codable` ∩ `Equatable` on the *same type*, because `Codable` supplies the round trip and
  `Equatable` supplies the `==`. `lottie-ios` declares **32** Codable types and **48**
  Equatable ones and emits **1** row: five types are in the intersection. Counting the
  conformances separately predicts a rich subject; the intersection predicted a poor one and was
  right.
- **The fields must be generator-derivable, and conformance does not imply it.** `AWSRegion`
  declares both conformances and derives nothing, because its only initializer is *failable*.
  `MacPaw/OpenAI` clears that clause too and still executed nothing until an unrelated
  leaf-spelling defect was fixed.

**The pre-check itself is unchanged and was never wrong** — it read 1 of 15 and 0 of 55 exactly
as it should have. What was wrong was continuing past it. Both subjects were carried forward
*after* the pre-check had already said stop, which is a discipline failure rather than a rule
failure, and is recorded here because the rule will read as insufficient otherwise.
`docs/measurements/refutation-rate-second-subject.md`,
`docs/measurements/module-qualified-leaf-spelling.md`.

⚠ **AMENDED AGAIN 2026-08-28, with three clauses paid for rather than reasoned to.** A
screening pass over **63 subjects** ran the amended rule end to end and found three things it
does not say. `docs/measurements/candidate-screening-pass.md`.

- **The subject must build for the HOST.** Every clause above is about the subject's *types*;
  none asks whether `swift build` succeeds on macOS, because every prior subject was a
  cross-platform library. `IceCubesApp/Packages/Models` had the best on-disk hand-written count
  (**9**) and declares no macOS platform, so it defaults to 10.13 against `SwiftSoup`'s 10.15
  and fails outright — **every row would have read `build-failed`**, which CLAUDE.md warns reads
  as an architectural limitation rather than a broken manifest. App-local packages are where
  hand-written wire types are richest, so this class is both attractive and unreachable. **The
  cheap check is reading `platforms:`; only an actual build settles it**, since a dependency can
  out-require a declared floor — which is precisely how this one failed.
- **Point the index at a VENDED LIBRARY PRODUCT, not an internal target.** Indexing
  `--target OpenAPIKitCore` gave **33 rows, 0 verdicts, and 13 declines reading
  `unsupported-carrier: OpenAPIKitCore is not a library product`**. The vended product gave 97
  rows and 5 verdicts. Fifth instance of *a decline bucket's NAME is not its cause*, and the
  same shape as swift-system's 21-of-36.
- **The spent-subject check must key on MEASURED, not on MENTIONED**, for two independent
  reasons. It greps the directory basename, so `~/GitHub_projects/swift-sdk` — which **is**
  `mcp-swift-sdk`, already spent, and scored the highest hand-written count in the sweep — was
  caught only because one name is a substring of the other; a directory named `mcp` would have
  passed and the contaminated result would have looked like the pass's best find. And
  **publishing a screen spends every candidate it names**, so the letter of the rule now
  disqualifies subjects for having been *screened*. Read a screening doc's candidate list as
  available.

⚠ **The pre-check's own reading is ambiguous and this is not resolved.** *Rows reaching a
verdict* and *rows reaching the build stage* are different numbers — a `build-failed` row
reaches the build stage and yields no verdict — and they differ by 3× on `OpenAPIKit` (15
against 5). Which of the two the published `jwt-kit` figure of **17 of 35** counted is not
recoverable from its table. **A threshold is only as meaningful as the reading it names.**

### 6.2 The route falsifies §5.1's precondition argument, and one of its premises

**A-quality was met by a REFUTING law on unmutated code, not by a passing law killing a
planted mutant.** `codable-round-trip` refuted `ToolChoice` on `mcp-swift-sdk` as shipped.
Two consequences for the criteria as written, both worth stating plainly rather than quietly
absorbing:

- **A-reach is not, in general, a precondition for A-quality.** §5.1 argues it is, on the
  ground that *a passing law is the only kind a mutant can be aimed at*. That is true of the
  **mutant route** and says nothing about the **found-defect route**, which needs no mutant
  and therefore needs no passing law. The argument was sound for the case it considered and
  was mistaken for a general one. §5.1's table row *A-reach fails → no verdict about law
  quality follows* is correspondingly too strong: a refutation on shipped code is a verdict.
- **The premise *a refuted law is a false law* has now been falsified once — by the result
  that met the bar.** §5.1 rested on **17 of 17**; the tally is **18 FALSE of 19 hand-checked**, and the 1 real
  is `ToolChoice`. The decline advice does not change (18 of 19 is still a strong prior, and
  all 18 are `idempotence`), but a premise quoted as exceptionless now has its exception, and
  that exception is load-bearing rather than incidental.

**Neither of these lowers the bar or reopens it.** A is met on the reading that was ratified.
What they change is the *reasoning* around it, and the correction runs in the direction that
matters here: the criteria were stricter than they needed to be, in a way that would have
sent the next attempt down the longer route.

**A-reach and A-quality were met on DIFFERENT subjects**, so §5.1's *passes / passes → in
shape, on that subject* has not been demonstrated on any single subject.

### 6.3 ASKED AND ANSWERED 2026-08-27 — the composite is NOT required

**The maintainer's answer is NO: A is met on the reading ratified 2026-08-21, and the
composite is not what the bar meant.** The question sat unasked from 2026-08-23 to
2026-08-27, was filed as `open-threads.md` row 64 on the second of those dates, and is
recorded here — the row is deleted rather than struck, per that file's own convention that a
closed row's answer moves to where it belongs.

**Why this is the right direction and not a convenience.** §6.2 had already found the criteria
**stricter than their purpose needed**, twice in one section: A-reach is not in general a
precondition for A-quality, and *a refuted law is a false law* had its exception. Requiring the
composite would move the bar in the opposite direction — **upward, after it had been cleared,
on a reading nobody committed to in advance.** That is the failure §1 names from the other side:
an unwritten bar is not a neutral state, and a bar re-tightened once its result is known is
worse than one written down wrong.

**What this does NOT claim.** It does not claim any single subject has been shown *in shape*.
Nothing here has demonstrated that, and the sentence above stands as written. What is settled
is only that **the bar never asked for it.**

⚠ **The swift-system mutant (§6 step 1) remains worth having and is now OPTIONAL rather than
gating.** It is still the only route to A-quality *on that subject*, and §6.2 argues
independently that having both halves on one subject is worth having. It is no longer a
precondition for anything.

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

## 8. What would refute this document

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
