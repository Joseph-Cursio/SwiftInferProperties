# Open threads

Things decided, noticed, or left undone that have **no other home**. Deliberately terse — an
index, not an essay. Anything with a real home lives there instead; this file exists so a
conversation's residue does not evaporate.

> **As of 2026-08-04** · `SwiftInferProperties@0b49651`. Entries here are *not* dated claims
> about code — they are open questions and standing reads. Close them by deleting the row and
> putting the answer where it belongs. Measurements *inside* an entry carry their own date and
> SHA; the suite run in item 0 was taken at `1e0218e` and has not been re-taken since.

<!-- doc-provenance date=2026-08-04 subject=SwiftInferProperties@0b4965140e41f9c32315f2552887a95b75170c95 observer=SwiftInferProperties@0b4965140e41f9c32315f2552887a95b75170c95 -->

---

## Next session starts here

Written at the close of 2026-08-03, after PRs #71/#72/#73 took running `predicate` laws from
**0 → 104 of 126**. Ordered; item 0 is a chore and everything after it is a choice.

**0. ~~Run the batches this work never saw.~~ Closed 2026-08-04 — the whole tree is green.** Every
target run at `1e0218e` (three commits past the `052515b` this was written against, so it covers
PR #74 as well), each invoked *separately* rather than through `make test`: that target is
fail-fast, and a failure in batch 1 would have hidden the six behind it — the same
refuter-fires-first shape this repo already names as a design decision.

| target | verdict | tests / suites | wall |
|---|---|---:|---:|
| `lint` | green | — | 0s |
| `test-fast` | green | 4,823 / 653 | 31s |
| `perf` | green | 8 / 5 | 17s |
| `batch1` | green | 4 / 3 | 171s |
| `batch2` | green | 3 / 3 | 136s |
| `batch3` | green | 31 / 6 | 319s |
| `batch4` | green | 7 / 7 | 370s |
| `batch5` | green | 7 / 7 | 20s |
| `batch6` | green | 4 / 4 | 171s |
| `batch7` | green | 9 / 9 | 350s |

Zero failures, zero flakes — no rerun was needed, which is worth recording given the standing note
that the long measured suites occasionally drop one issue under load. **One test skipped**, in
`perf`: the swift-collections `DequeModule` discover budget, which needs a corpus not checked out
on this machine. That is a skip, not a pass; the §13 budget it guards is unmeasured here.

`batch3` reproduces at **319s against the 417s** recorded at `052515b` — same 31 tests, and the
gap is contention, not code: this run had the box to itself. Peak temp-disk never moved the free
figure off 573–574 GB, and `make clean-temp` was run before and after.

**1. Should the `predicate` composer be pushed past 83%? — No, and the number is the argument.**

The question was asked as *"retry the predicate composer update even though it is still only at
83%"*, and the honest answer is that **83% is where that composer's work ends**. The remaining 22
are not composer failures. Both compile buckets are **zero**; what is left is 17 carrier declines
(14 SwiftSyntax nodes and optionals, `[String: TypeShape]` ×2, `[TypeDecl]`), 4 traps the carrier
gate refuses to call refutations, and 1 undiagnosed `build-failed`. Nothing in that list gets
better by changing the composer — 14 of them are *"no generator derives a `TokenSyntax`"*, which is
a different package's problem, and 4 are the tool being right.

So the next honest gain is **breadth, not depth**: a second composer, reaching a template that has
none, is worth more than the last 17% of this one. `item 13`'s probe already said the same thing
from the other side — *"the binding constraint is the composer set"* — and this survey is the first
measurement that agrees with it from inside a composer that works.

**~~Do the 1-point version anyway~~ — done 2026-08-04, and it was NOT a fourth defect.** The
undiagnosed `build-failed` on `isStale(indexPath:packageRoot:)` is
`type 'Gen<URL>' has no member 'url'` — **item 19**, reached here from the `predicate` survey and
independently from item 18's `idempotence` survey, where it blocks the nine `defaultPath(for:)`
rows. Two surveys, different templates, one defect — **now fixed**. See *Decisions* → *The
`Gen<URL>` defect — fixed, after a wrong diagnosis worth keeping*.

**2. Generators for syntax-node carriers — scope it before building it.** 14 of the 22 is the
largest single bucket left anywhere in this survey, and it is *one* question: can a `TokenSyntax` /
`SyntaxCollection` be derived at all, and by whom — here, or `DerivationStrategist` in
SwiftPropertyLaws? The design decision *"generator inference delegates to SwiftPropertyLaws"* says
the answer is probably not here, which makes this a scope-and-file item rather than a build item.

**3. ~~Re-measure item 13's access-widening probe, with a pre-check.~~ Closed 2026-08-04, and the
read is REFUTED.** Widening no longer moves a function from *invisible* to
*proposed-but-unrunnable*: **3 of 6 gained laws now execute, against 0 before.** See *Decisions* →
*Access widening, re-measured*.

**4. The whole-corpus number is still missing.** Everything above is `--template predicate` over
126 entries. There is no measurement of how many laws run across *all* templates, which is the
number open item 7 actually wants. Cost is the blocker, not method: 126 entries ran in roughly an
afternoon and left 3.4 GB of workdirs behind.

**5. Two review findings from `/swiftui-pro`, both fixed at close** — `VerifyTargetInference` was
re-implementing `TargetDirectory.isDirectory` (now shared), and `VerifyImportSet`'s doc said
breadth-first over a depth-first `popLast`. Recorded because the second one is the house failure
mode in miniature: a comment that describes something the code stopped doing. Neither was a bug.

---

## Open items

| # | item | where it stands |
|---|---|---|
| 1 | ~~**[SwiftEffectInference#1](https://github.com/Joseph-Cursio/SwiftEffectInference/issues/1)** — `~2×` regression on the whole-domain purity path~~ | **Closed 2026-08-04, and the issue's own diagnosis was right.** `inferredEffect(for:)` no longer delegates to `verdict(for:)`: `verdict` cannot check `throws` until *after* the body walk (that walk is the only way to separate `.pureButPartial` from `.refuted`), but the whole-domain question treats `throws` as disqualifying and rejects on the signature. Fixed in [SEI#2](https://github.com/Joseph-Cursio/SwiftEffectInference/pull/2). **Also settles the issue's open question — mechanism 1 was the ENTIRE cost**; the erased-`Syntax` generalisation contributes nothing measurable, so there is no second fix to chase |
| 2 | **Then**: ~~bump the SEI pin~~, ~~run `make perf` before `make test`~~, add a pin-equality guard, then adopt `verdict(for:)` | **Pin bumped 2026-08-04** to `bfcf0e3` — *past* the regression rather than around it. All five §13 budgets back at control-arm cost (Discover-pipeline **3.677s** against its 6.0s budget, versus **6.777s** on `097181aa`); all ten `make` targets green. **Still open: the pin-equality guard and adopting `verdict(for:)`.** SwiftProjectLint remains on `097181aa`, which sharpens item 3 into *is SPL paying a cost this repo has stopped paying?* |
| 3 | **Is SwiftProjectLint silently paying item 1?** It is already on `097181aa` and calls `PurityInferrer` from two visitors over every function *and closure* in a project | unmeasured. Cheap: point the same A/B at its own suite |
| 4 | **The attribute-grammar join has no contract test.** SwiftIdempotency ships the macro names; `AttributeRecognition.default` hard-codes them; nothing asserts they still match | a rename fails as a *missing* annotation, indistinguishable from an unannotated codebase |
| 5 | ~~**`PBTSeed.role`'s doc comment is stale**~~ | **Closed 2026-08-04** ([SPL#65](https://github.com/Joseph-Cursio/SwiftProjectLint/pull/65)), and it was wrong **twice over** — which is why it was not a one-line fix. The count was stale, *and* the wording (*"every rule but the two **candidate** rules"*) ruled the third out **by name**: `extractablePureKernel` is a kernel rule, so a reader checking the sentence against the code would have read the classification they found there as a bug. **A doc that characterises a set by a property its newest member lacks does not go out of date — it argues against the code.** The three are now named individually rather than counted. Also closed the gap the count rested on: `SeedRoleEmissionTests` had arms for the closure and kernel rules and **none** for `pureFunctionCandidate`, so the third classifier had no executable claim anywhere — which is how a doc about it could be wrong unnoticed |
| 6 | ~~`.swiftinfer/` is not gitignored~~ | **Closed 2026-08-03.** Ignored at the **root only** (`/.swiftinfer/`, not `**/`) — `fixtures/cycle27-surface/.swiftinfer/index.json` is a tracked frozen corpus and a recursive pattern would have hidden it. A deliberate commit is still available via `git add -f` |
| 7 | **No current end-to-end number** for the loop | see *Standing observations* → *The measurements are all withdrawn* |
| 8 | **Exit criteria for "the toolchain is in shape"** are unwritten | see *Decisions* → *Road tests were misfiled* |
| 9 | **Driver stages 3–4** (`verify`, kit conformance suites) are declared and unimplemented | `scripts/toolchain.sh`. Until they exist, **no run of the loop executes a law** — the driver says so every run rather than implying otherwise |
| 10 | **The two ends of the lint→infer hop take different inputs.** The linter takes a repo path and works out the layout; `discover` requires exactly one of `--target`/`--sources` and errors without one | a reader following the documented hop hits an argument error on their first attempt. The driver papers over it by inferring scope — open question whether the *fix* belongs in `discover` instead |
| 11 | ~~Driver stage 0 builds another repository~~ | **Closed 2026-08-03, the other way.** The rebuild is now *load-bearing*: a repo SHA describes the binary only if we just built the binary from it, so building unconditionally is what earns the attribution. A `stale` binary fails the stage — accepted deliberately, since an unattributable run is worse than no run |
| 12 | **Neither binary can state its own build identity.** `swift-infer --version` reports `1.148.0` — identical whether built this morning or months ago from another commit | the real fix for item 11's workaround: embed a build SHA at compile time, in *those* packages, and have the driver read it from the binary rather than the tree. Prerequisite for ever shipping installed release binaries |
| 13 | **Speculative refactoring** — mutate a copy, verify, propose a patch only when the law ran | designed 2026-08-03, **unbuilt**, and **re-measured 2026-08-04 with laws that RUN**. The 2026-08-03 funnel (20 → 8 proposed → 2 composer-supported) was a ceiling nobody had executed. Executed: **0 of 6 ran on the pre-composer binary, 3 of 6 on HEAD** — 1 holds, **2 refute**, and both refutations are false laws rather than bugs. The blocker was never the composer; it was the cross-module import (item 16). See *Decisions* → *Access widening, re-measured* |
| 14 | ~~Write a `predicate` composer~~ | **Closed 2026-08-03, and MEASURED.** Shipped, then found unreachable (gate 2), then found never-composing (a compose-time value escaped as a runtime one) — three defects between "written" and "runs", each invisible to the unit tests that call the composer directly. Survey of all 126: **54 run and hold**, against a measured base of **0**. The `≤+126` ceiling resolved to **+54**; 56 of the remaining 72 are item 16, 11 are SwiftSyntax carriers with no generator. **Superseded by item 16: the figure is now 104.** Zero refutations — these are regression guards on correct code, not bugs found |
| 15 | ~~Are `predicate`/totality laws refutable here, or a wall of green?~~ | **Closed 2026-08-03: not a wall of green.** 35 of the 126 (27%) already carry a hand-written totality guard, and ~half of a 20-sample would trap under a plausible implementation. Item 14 unblocked; see *Decisions* |
| 16 | ~~The index records a CARRIER; a law needs a SIGNATURE~~ | **Closed 2026-08-03, and MEASURED.** Built as scoped; `≤+56` realised as **+50** (54 → **104 of 126**). Both compile buckets are ZERO: cross-module 37 → 0, arity 19 → 0. The shortfall accounts for itself — carrier declines 11 → 17, entries that used to fail at compile and now fail earlier at generator resolution. Two defects found only by running it: the receiver is an implicit parameter (7 rows, all previously hidden behind the import failure), and the n-ary path dropped the `GeneratorResolver` `emit` builds (5 rows, mine, same day). See *Decisions* → *Signature, not carrier* |
| 17 | **The idempotency vocabulary is split across two packages, and this one reads neither half it owns** | surveyed 2026-08-04, **undecided by choice** — see *Decisions* → *Idempotency vocabulary*. Not a naming clash: two packages independently **generate idempotency tests from an annotation**, and swift-infer uses `EffectAnnotationParser` at exactly **three call sites, all `isClockDeterministic`**. Ordering matters — retiring `.idempotent` before swift-infer *reads* `@Idempotent` reproduces item 4's failure mode by hand. **Folded in**: whether `@ClockDeterministic` belongs in SwiftIdempotency — it does **not** belong to the effect lattice (four pre-existing fences say so) but probably does belong to the package; the actionable part is that it is the one annotation neither configurable nor contract-tested, which is item 4 |
| 18 | **`idempotence` has a 24% false-law rate on its executed surface** — 13 of 55, all at the score-35 shape-only floor | measured 2026-08-04, **no fix shipped**. A return-expression shape classifier, frozen before the verdicts, scores **83% precision / 38% recall**; the misses are a second class (**domain transfer**: `T -> T` where the output is a different *kind of thing*) that the `_description` and capacity vetoes have been chasing by NAME. Blocked behind a decision, not a build: a tenth veto vs PRD §3.5's *raise thresholds, don't add filters*. See *Decisions* → *The `idempotence` template's false-positive rate* |
| 19 | ~~**`Gen<URL>` has no member `url`**~~ | **FIXED 2026-08-04** — two lines, no kit change. Same defect as the `predicate` survey's one undiagnosed `build-failed` — two templates, reached independently, one cause. `Gen` is from `PropertyBased`; `url()` is an extension in `PropertyLawKit`, which the stub does not import and the workdir does not depend on. The `.algebraic` workdir was the outlier — `.interaction` already declared the product. **URL rows now 0 → 11 of 13 executing (2 hold, 9 refute)**, and the 9 refutations confirm item 18's frozen classifier on rows it could not previously run. **An earlier same-day diagnosis of this was WRONG** (a `libTesting` launch failure that was an artefact of running the binary outside its harness) and is kept as a correction. See *Decisions* → *The `Gen<URL>` defect — fixed, after a wrong diagnosis worth keeping* |
| 20 | **Nothing reads `@EffectUnknown`.** SwiftIdempotency ships the marker as of [#3](https://github.com/Joseph-Cursio/SwiftIdempotency/pull/3) (2026-08-04); no tool distinguishes it from an unannotated declaration | **Unblocked 2026-08-04.** Item 1 is fixed and the pin now sits at `bfcf0e3`, so links 2 and 3 of the chain are clear. What remains is **link 1: SEI must learn to read the marker** — and it belongs there, not here, because swift-infer re-implementing the `@lint.effect` grammar is exactly what SEI exists to prevent. See *Decisions* → *The `@EffectUnknown` dependency chain* |

---

## Decisions taken in conversation

Recorded because the reasoning is the useful part and it exists nowhere else.

### Road tests were misfiled, not mistimed (2026-08-03)

They were premature **as scorecards** and exactly on time **as development instruments**. The
distinction matters because the conclusion "stop road-testing" does not follow.

- The 0-of-3 run is what *found* five confident zeros. You cannot find a confident zero by reading
  code — by definition it looks like success.
- `roadtest-self-dogfood.md` has every measurement withdrawn and **19 live source sites still cite
  its diagnoses**. That is a high yield for a "premature" exercise.
- **What went wrong was publishing scores from a tool that was still changing.** The repo already
  has *"a tool may not grade its own homework"* (about answer-key contamination). The missing
  sibling: **a tool may not grade itself while it is still changing** — every score taken during
  active development is a score of a binary that no longer exists. That is §10.3's A/B rule
  (two binaries, same day, same corpora) generalised past templates.

**Backtests are not the same instrument and should not be deferred with road tests.** Their oracle
is a public fix commit that predates the tools and cannot be contaminated; they are cheap to re-run
and survive tool churn. In-repo record agrees: road-test scorecards withdrawn twice, backtests
standing (`backtest-apple-libraries.md`, and `kit-suite-backtest-plan.md` Arm 1 a clean hit).

**The trap in the position:** *"not ready to measure yet"* is unfalsifiable — the confident zero of
project planning, always defensible, forever. Write the exit criteria while inclined to be strict.
Candidates: composer reach past 38%, the 5 dead templates diagnosed, the instrument-error class
closed (Pass 2 was the big one, fixed), `--sources` no longer gating app code out of measured
verify.

### Speculative refactoring — shape and build order (2026-08-03, designed not built)

**The idea.** `swift-infer` copies the target, applies a refactor the linter suggested, derives a
law from the *refactored* shape, verifies it, and surfaces the refactor **only if the law ran**.
Output stops being advice and becomes a **patch + a law + a verdict**.

This is `prove-then-show`'s inversion — *"the test-then-surface inversion of the hide-Possible
default"* — applied to `suggest-refactors`' domain. Both commands already exist; what is missing is
the copy, the mutation, and the join between them.

**Why it is worth doing at all.** Today the linter says *"extract this kernel"* and the reader takes
it on faith; `extractable-kernel` seeds explicitly do not focus discovery, and `swift-infer` reports
"work a human must do before any tool can help" and stops. This lets it say instead: *extract this,
and here are the laws you get.* The value is **refactors that actually get done**, not more
suggestions.

**Emit a diff, not advice.** If the output is prose, the verdict does not transfer — you verified
*your* extraction and they will write a different one, and choosing the parameters is where the
design work lives. If the output is the exact code that was compiled, the claim is precise and
checkable: *paste this, and this law held over 100 trials.*

**"A patch we know would work" means two different things.** Conflating them is how the kernel tier
would over-claim:

| tier | what makes the **patch** safe | what the property test proves |
|---|---|---|
| access widening | the compiler — a visibility change cannot alter behaviour | that the **law** holds |
| kernel extraction | **nothing yet** — the extraction may not preserve behaviour | that the law holds **of that extraction** |

A passing law on an extracted function says nothing about whether the extraction preserved the
original. You can extract wrongly, get a clean law, and propose a patch that changes the program.

**Build order, by how much the PATCH needs proving** — not by how valuable the law is:

1. **Access widening.** Patch free, law proven, and **extraction ambiguity is zero**: same symbol,
   same body, one keyword. A verdict on the copy is a verdict on their code. `restricted-function`
   is 316 of 468 analysable seeds on SwiftProjectLint's own repo. **Start here** — it also builds the
   copy-mutate-verify machinery the later tiers reuse.
2. **Extract closure to a named function.** Nearly mechanical; the risk is captures and the signature.
3. **Kernel extraction.** Needs a *second* property — that the original method and the refactored one
   **agree**. That is differential/oracle testing, already in this repo's vocabulary
   (`parsing-catalog-gap.md`, holes 8/9/12). Without it, "we know it would work" is not earned.
4. **Primitive → domain type.** A redesign. No property makes that patch safe. Out.

**The linter side needs one thing, and it is not a new seed kind.** `PBTSeedsFormatter.effectiveKind`
already demotes to `restricted-function` on `TestReachability.unreachable`, so the seed ships today.
What it collapses is *why*: that case covers `private`/`fileprivate` **and** "nested inside a type
that is", and the remedies differ — for a nested member, widening the member is a **no-op**, and a
generator that got it wrong would emit a patch that unblocks nothing and then fail verification for
a reason unrelated to the law. Add a `reason`, not a kind.

**Three costs to price first.** Build cost multiplies (every candidate is its own SwiftPM workdir;
an 85-entry survey already leaves 3.4 GB) so it must be hard-gated and opt-in. A **disproven**
speculative law is ambiguous in a way a real one is not — it indicts either the code or the
extraction, and reusing `measured-defaultFails` would be dishonest, since that name means *the
property is false of your program*. And the copy is a [border claim](glossary.md#border-claim):
verify against a snapshot and report on the original, and a moved source silently invalidates the
verdict — record the source hash the way `run.json` records tool SHAs.

**The safety line survives, and reads better.** `swift-infer` still never modifies your tree; it
mutates a copy and proposes a patch, which is what every refactoring tool does.

#### Measured before building — and it changed the plan (2026-08-03)

The prerequisite shipped first (SwiftProjectLint#64: `TestRestriction`, so a patch generator can
tell "widen this declaration" from "widening it is a no-op"). Then a probe, because the population
figure answers the wrong question.

**Sampling.** 20 of the 641 `declaration`-restricted seeds on this repo — every 32nd, sorted by
`file:line`, **frozen before any was read**. Widened by line number in a throwaway worktree, then
the same `swift-infer` binary run over four targets, before and after.

| stage | count |
|---|---:|
| widened | **20** |
| gained a proposed law | **8** (256 → 264 suggestions) |
| law is **composer-supported**, i.e. `verify` can attempt it | **2** |

The two runnable are both `idempotence`. The other six are `predicate` ×3, `filter-subset`,
`comparator` — none of which has a composer, so they would be proposed, scored, rendered, and then
decline `unsupported-template`. Six of the seven distinct laws are `Possible`, hidden by default.

**Access is not the binding constraint.** Widening it moves a function from *invisible* to
*proposed-but-unrunnable*; the binding constraint is the composer set. The probe's contribution is
showing the access population lands in **the same bucket** the decline census already described.

**The first reading of this was wrong, and the error is the instructive part.** Extrapolating 10%
over 641 seeds gives ~60 runnable laws, which was written up as a disappointment — by comparing 60
against **641 seeds**, the denominator this repo explicitly warns against (*"a seed is not a
suggestion"*, glossary). Nobody had measured what 60 would be added *to*. Measured, over the same
four targets:

| | suggestions | **runnable** |
|---|---:|---:|
| default tier | 180 | 28 |
| with `--include-possible` | 256 | **100** |

So +60 is a **60% increase in the executable population**, not a rounding error. Anchoring on the
seed count made a substantial gain read as a small one.

**What each lever might be worth — CEILINGS, not predictions.** Same corpus, same binary. 156 laws
are non-runnable today and **126 of them are `predicate`**:

| lever | attemptable after | change | needs |
|---|---:|---|---|
| today | 100 | — | — |
| `predicate` composer (item 14) | ≤226 | **≤+126** | no new machinery |
| access widening (item 13) | ≤160 | **≤+60** | copy-mutate-verify |

Both are **composer-supported counts**, obtained by grouping declines by template name. That makes
them comparable *to each other* and to nothing else. Composer support is **necessary, not
sufficient** — the glossary says so — so every row still has to resolve a generator for its carrier,
compile, and not trap. That attrition is unmeasured. Neither number is a count of laws that would
run, still less of laws that would *hold*.

**The ordering claim is NOT established, and the reason is worth more than the claim.** These levers
were ranked by **count**, in a repo whose standing rule is *score refutability, not suggestion
count*. A totality law over a function that never traps passes every time, and 126 new green results
that cannot fail is the [Daikon trap](glossary.md#daikon-trap) wearing a composer — *"a wall of
green unrefutable passes is the Daikon trap in a new costume."*

The counter-argument is real and also unmeasured: `predicate`/totality is **role-entailed**, a law a
*correct* implementation cannot fail, which is the combination a law wants. A green pass there is a
guard against future change rather than noise. Both readings are available and nothing here decides
between them.

**What is actually known:** `predicate` is the largest blocked population, and `predicate` +
access widening compose — after a composer the probe's own 8 proposals go from 2 attemptable to 5,
so item 14 makes item 13 better rather than redundant. **What is not known:** whether unblocking
`predicate` yields refutable laws or a wall of green. That is cheap to settle — take a handful of
the 126, hand-write the totality law, and ask whether any plausible wrong implementation traps.
Do that before committing to the order.

The probe cost about twenty minutes. Recorded because the habit is worth more than the result, and
the record now has **two** corrections stacked on one measurement: the extrapolation was first read
against the wrong denominator, and then the corrected reading was used to rank two options by a unit
this project explicitly rejects. Neither error was in the measuring.

#### Are `predicate` laws refutable, or a wall of green? — answered (2026-08-03)

**Not a wall of green.** Two independent readings of the same 126:

- **Measured, all 126:** **35 (27%)** already contain an explicit totality-shaped guard — 17 count
  bounds, 12 `isEmpty` checks, 8 optional-`first` guards, 2 index-domain aware. An author had to
  think about emptiness or bounds in a quarter of these functions.
- **Judged, a 20-sample** (every 6th, sorted by `file:line`, frozen before reading): roughly **half**
  operate on domains where a plausible implementation traps — string index walking, positional
  collection access, force-unwrapped `first`. `looksLikeMobiusNext` is the clean case: total as
  written, and `returnType.firstIndex(of: ",")!` is an entirely natural way to write it.

**The concrete framing.** For those 35, the totality law is a **regression test on a guard that has
none**. `isOptional`'s `type.count > 1` does no classifying work — it is there so the function is
total — and deleting it turns nothing red today.

**Limits, because both numbers are soft in different directions.** 27% is a *lower-bound proxy*: a
guard proves the author hit the issue, its absence does not prove safety, since totality is often
implicit in the operations chosen. The ~50% is judgement over 20 functions, not a measurement.
Neither says the law would *fail* on shipped code — it will not; refutability asks whether a **wrong**
implementation would be caught.

**A method note worth more than the result.** The first pass classified by regex — force unwraps,
subscripts, division — and returned **1 of 20**, with that one a false positive (`/` inside a
comment). The regex asked *"does this implementation trap?"* when refutability asks *"would a
plausible implementation be rejected?"* Different questions; the cheap proxy answered the wrong one,
which is the fourth instance today of measuring through a proxy that does not cover the claim.

**What it settles:** the wall-of-green objection to item 14 is gone. **What it does not:** the
precise ranking of 14 against 13 — refutability was measured for `predicate` and not for access
widening's output, though that output's 2 runnable rows were both `idempotence`, a conjecture
template a wrong implementation can fail by construction.

### Signature, not carrier — the largest measured blocker to running laws (2026-08-03, scoped not built)

**The finding.** `verify --all-from-index --template predicate` over this repo, after the
`--target` derivation fix, resolves 126 entries into:

| outcome | count |
|---|---:|
| ran and held | **54** |
| compile: type not in scope (cross-module) | 37 |
| compile: n-ary predicate | 19 |
| no generator for carrier (SwiftSyntax nodes) | 11 |
| trapped — declined as domain evidence, correctly | 4 |
| other | 1 |

Two error buckets dominate, and they are **not two defects**. `SemanticIndexEntry` records
`carrierTypeName` — **singular** — and `primaryFunctionName` carries argument *labels* only
(`matches(typeName:inheritedTypeNames:)`). So:

- a predicate taking `(A, B)` cannot be composed, because nothing says what `B` is — **19 rows**;
- a predicate over a type declared in another module cannot be imported, because nothing records
  which module any type lives in — **37 rows**, of which **31 are `FunctionSummary` alone**.

One missing fact, two symptoms, **56 of the 72 non-running rows (78%)**.

**The data already exists and is dropped.** `FunctionSummary.parameters[].typeText` carries every
parameter type at scan time, and `FunctionSummary.location.file` carries the file;
`TypeShapeBuilder` reads `decl.location.file` too. Neither survives projection into the index.

**Where it must NOT go.** `Discover.PipelineResult.typeShapesByName` is
`[String: PropertyLawCore.TypeShape]` — the **kit's** type, owned by SwiftPropertyLaws. Putting a
module or source path on it is a cross-repo change plus a pin bump, for a fact the kit has no use
for. The established alternative is a **sidecar map keyed by type name**, and this would be the
third: `inheritedTypesByName` exists because the shape merges same-file extensions only, and
`genericParametersByName` exists because — in its own words — *"`TypeShape` does not carry them …
which is why `scaffold-kit-suites` wrote `Deque.self`"*. Same shape of gap, same remedy.

**The change, in five pieces.**

| # | what | where |
|---|---|---|
| 1 | `sourceFileByTypeName: [String: String]` | `Discover.PipelineResult` — third sidecar map, no kit change |
| 2 | `parameterTypeNames: [String]?` on the entry | `SemanticIndexEntry` + the projection; straight pass-through from the summary |
| 3 | persist the sidecar beside `typeShapes` | `IndexStore` / `IndexCommand` |
| 4 | import set = union of modules over every type the recipe touches | the stub emitter, via **`VerifyTargetInference.module(forLocation:)` — already shipped**, so no new concept |
| 5 | draw one value per parameter, not one per law | `composePredicatePass` |

**Rollout is graceful and needs no schema bump.** `SemanticIndexEntry` has a hand-written
`init(from decoder:)` using `decodeIfPresent`, so an added optional decodes as `nil` from an
existing index and verify falls back to today's behaviour. `reindexIfNeeded` then repopulates it on
the next stale read, which shipping the code itself triggers.

**≤+56 is a CEILING, not a prediction** — the same discipline items 13/14 are held to. Composer
support is necessary, not sufficient: an n-ary predicate still needs a resolvable generator for
*each* parameter carrier, and the 11 SwiftSyntax declines are evidence that some will land exactly
there. The honest claim is *up to* 110 of 126 (87%), with the attrition inside that unmeasured.

**Two known limitations, stated rather than discovered later.** The sidecar is keyed by **bare type
name**, so two modules declaring the same type name collide — an existing limitation of
`typeShapesByName` that this inherits rather than introduces. And a stub importing N modules builds
more than one importing one; this survey already costs ~35 min and ~72 GB for 126 entries.

**How to measure it.** Re-run the identical command — `verify --all-from-index --template predicate
--max-parallel 4` — per §10.3: two binaries, same day, same corpus, never against a remembered
count. **The run above IS the before-binary measurement**, taken 2026-08-03 at `1d39745` plus the
`--target` derivation. Do not substitute a recollection of it.

### Signature, not carrier — the measured close (2026-08-03)

Three binaries, same 126 entries, same afternoon — the §10.3 shape, and the reason the numbers are
comparable at all.

| bucket | A: `--target` | B: `+signature` | C: `+fixes` |
|---|---:|---:|---:|
| **ran and held** | 54 | 94 | **104** |
| compile: type not in scope | 37 | 0 | **0** |
| compile: arity | 19 | 7 | **0** |
| no generator for carrier | 11 | 20 | 17 |
| trapped — domain evidence | 4 | 4 | 4 |
| other | 1 | 1 | 1 |

**Both compile buckets closed. `≤+56` realised as +50**, and the 6 it fell short by are visible
rather than unexplained: carrier declines rose 11 → 17. Those entries did not get worse — they
stopped failing at compile and started failing earlier, at generator resolution, which is where
they were always going to fail. `DefaultFileSystemReader` was never generatable; saying so beats
reporting a missing argument count.

**Two defects that only running it could find**, both invisible to the unit tests:

1. **The receiver is an implicit parameter.** `receiverCallExpression` renders `{ $0.method($1) }`,
   so an instance method's closure takes `parameters + 1` values. Exactly 7 entries, and all 7 had
   been failing on a missing type first — *a refuter that fires first hides every refuter behind
   it*, which is a design decision in this repo and turned out to describe its own measurement.
2. **The n-ary path dropped the resolver.** `emit` builds a `GeneratorResolver` from `allShapes`;
   the totality composer re-resolved per parameter without it, so nested custom types could not
   derive. Five `FunctionSummary` laws declined for a type that derives fine on the unary path —
   which never noticed, because it is handed an already-resolved recipe. **Anything that
   re-resolves must re-resolve with the same resolver.**

**What remains is a different kind of problem.** Of 22 non-passing, **17 are carrier declines** and
14 of those are SwiftSyntax nodes or optionals — nothing derives generators for those, and it is
not more plumbing. Plus `[String: TypeShape]` ×2 and `[TypeDecl]` (containers of custom types),
4 traps the carrier gate correctly refuses to call refutations, and 1 undiagnosed build failure.

**And 104 laws holding is not 104 findings.** Zero refutations across all three runs. These are
executable regression guards on code that is currently correct — item 15's prediction, and what
*score refutability, not suggestion count* requires be said out loud.

### Access widening, re-measured — the read was right about the cause and wrong about the lever (2026-08-04)

Item 3 asked for a **pre-check**: do the widened functions' parameter types land in the same
carrier-decline bucket the residual 17 do? Then it asked for the re-measurement. Both were run,
in that order, and the pre-check turned out to answer a *narrower* question than it was asked.

**Apparatus, stated first because one detail invalidated the first attempt.** 641
`declaration`-restricted seeds (the identical figure to 2026-08-03), sorted by `file:line`, every
32nd — indices 31, 63, … 639, exactly 20 — **frozen to a file before any body was read**. Two
worktrees at `1e0218e`, pristine and widened. Two binaries, **same day, same trees**, per §10.3:
**A** = `7e7a633` (the last commit before the `predicate` composer) and **B** = `1e0218e`. The
index — not `discover`'s prose — is the instrument, because it is JSON, it defaults to
`--include-possible`, and it is the artifact `verify --all-from-index` actually consumes.

> ⚠ **These are not the same 20 functions as 2026-08-03.** That list was never recorded — only
> the aggregate was. The sampling *rule* is reproduced exactly and the seed population is
> identical (641), but function-level comparison to the old run is not available. Read the old
> `20 → 8 → 2` as context, never as this table's before-column; the before-column is binary A.

**The funnel, executed.**

| stage | A (`7e7a633`) | B (`1e0218e`) |
|---|---:|---:|
| widened | 20 | 20 |
| index entries, pristine → widened | 249 → 255 | 249 → 255 |
| **gained a proposed law** | 6 | 6 |
| composer-supported | 4 | 6 |
| **ran a law** | **0** | **3** |
| held | 0 | 1 |
| refuted | 0 | 2 |

**The recorded read is refuted, and not by the lever it was filed under.** *"Widening moves a
function from invisible to proposed-but-unrunnable"* was true of binary A and is false of HEAD.
But the `predicate` composer is **not** what changed it — the composer moved 2 rows from
`unsupported-template: predicate` to `unsupported-carrier: FunctionDeclSyntax` /
`InheritanceClauseSyntax?`, which is a **more honest decline and still zero laws run**. What made
laws run was item 16's cross-module import fix: all three `idempotence` rows failed under A with
`build-failed: cannot find 'LiftedTestEmitter' in scope` (and `IdempotenceStubEmitter`,
`Suggestion`) and execute under B. **The two levers were ranked against each other; the one that
mattered here was neither.**

**The pre-check was right, and it was answering a smaller question than it was asked.** It
predicted 3 of 20 SwiftSyntax carriers against 14 of 17 in the residual list, i.e. *not the same
bucket*. Measured: the two rows that reach a carrier decline are **exactly** rows 10 and 20 of
the pre-check, declining on `FunctionDeclSyntax` and `InheritanceClauseSyntax?` — the residual
bucket named verbatim. So the bucket prediction held **per row**. What it could not predict is
**which functions gain a law at all**: 6 of 20 did, and two of the five all-primitive rows
(`source`, `manifest`) gained nothing, because the template gate — not the carrier — decides
whether a law is proposed. Parameter types predict whether a proposed law can *run*; they say
nothing about whether one is *proposed*. The pre-check conflated the two, cheaply and recoverably.

**3 ran is not 3 wins, and this is the first time that was visible.** One is a real regression
guard (`sanitizeKeyPathForIdentifier` — strips a leading `\.`, then `.`→`_`; genuinely
idempotent, `measured-bothPass` at 100 + 100 trials). **Two are false laws refuted at trial 0**:
`complexDoubleEdgePass` is a source-*template* emitter, so applying it twice embeds the block
twice, and `rebuildWithCounterSignal` **appends** a signal and a caveat per call, so `f(f(s))`
carries the counter-signal twice and scores −50 instead of −25. Neither is a bug; both are
`idempotence` firing on a `T -> T` shape that is not idempotent. Both sit at `Possible` (score
35), hidden without `--include-possible`. **The 2026-08-03 funnel could not see this at all** —
nothing ran, so precision was unmeasurable, and *"2 composer-supported"* silently read as
2 prospective wins. Against *score refutability, not suggestion count*: the honest yield of
this sample is **1 guard, 2 false proposals, 3 declines**.

**A trap that cost a full run, and it is the one item 13's design already warned about from a
different direction.** The first widening rewrote `private ` → `internal `, which is the obvious
spelling of "widen access". It gained **exactly nothing**: 249 → 249, *identical* identityHash
set. `FunctionScanner` skips explicit `internal` too (cycle 148, Lever A) — it reads the token as
deliberate SPI, and Swift's default access carries **no token**, which is the shape the scanner
accepts. So a patch generator that emits `internal` produces a patch that compiles, changes
nothing, and then fails verification for a reason unrelated to the law — the exact failure item
13 anticipated for members nested inside a `private` type, arriving from a second, unrelated
cause. **The patch must delete the modifier, not replace it.** Measured, not argued.

**What this does to the ordering.** Item 13 no longer produces unrunnable output, so the reason
to defer it is gone. But the case *for* it is now smaller and better-founded than the ceiling
suggested: 20 widenings → 6 laws → 3 executions → **1 correct law**. Extrapolated over 641 seeds
that is roughly 32 correct laws and 64 false proposals — a real gain and a real precision cost,
where before there was only a count. The widened tree **compiles clean**, so the access tier's
"the compiler makes the patch safe" claim is confirmed rather than assumed.

### Idempotency vocabulary — surveyed, not yet decided (2026-08-04)

Raised while scoping speculative *annotation* (item 13's cousin: add an annotation to a copy,
verify, propose it only when the law ran). Recorded as a survey because the decision is the
user's and the facts were not written down anywhere.

**The first read of this was WRONG and the correction is the useful part.** I claimed the
SwiftIdempotency and swift-infer vocabularies "don't meet, with nothing asserting they match."
The second half is item 4 and is true. The first half is false: **`EffectAnnotationParser` in
SwiftEffectInference already parses the entire SwiftIdempotency family**, bilingually — attribute
form (`@Idempotent`, `@NonIdempotent`, `@Observational`, `@ExternallyIdempotent(by:)`, `@Pure`)
*and* doc-comment form (`/// @lint.effect …`, `@lint.determinism clock_deterministic`) — with the
names configurable through `AttributeRecognition`. swift-infer already depends on it. The join
exists; it is simply almost unused.

**Three vocabularies, three genuinely different jobs. That part is healthy.**

| package | ships | job |
|---|---|---|
| SwiftIdempotency | `@Idempotent` `@NonIdempotent` `@Observational` `@ExternallyIdempotent(by:)` `@Pure` `@ClockDeterministic` | *what this function does* |
| SwiftPropertyLaws | `@Discoverable(group:)` `@PropertyLawSuite` `@ValueSemanticTests` … | *what to discover / generate suites for* |
| **this repo** | `@CheckProperty(.idempotent / .roundTrip(pairedWith:) / .preservesInvariant(_:))` | *which law to check* |

**The real inconsistency is one row of overlap, and it is duplicated FUNCTION, not spelling.**
`@CheckProperty(.idempotent)` expands into a peer `@Test func` (`CheckPropertyMacro`, M5.2);
SwiftIdempotency's `@Idempotent` + `@IdempotencyTests` does the same job. Two packages generating
idempotency tests from an annotation.

**And this repo reads neither half it owns.** `AttributeScanner` reads only the
`.preservesInvariant` arm — its own comment says `.idempotent` and `.roundTrip` "are ignored
here." `EffectAnnotationParser` is called at exactly **three sites, all `isClockDeterministic`**
(`FunctionScannerVisitor+Summary`, `ViewModelDiscoveryVisitor`, `ReducerDiscoverer`). Everything
else in the effect vocabulary is parsed by a linked dependency and consumed by nothing.

**Two defects found while checking, both small and both real:**

- `AttributeScanner`'s doc comment says it recognises `@CheckProperty` and that "SwiftInferProperties
  does not take a runtime dependency on **`PropertyLawMacro`**'s definitions". But `@CheckProperty`
  is **this repo's own macro** (`Sources/SwiftInferMacro/CheckProperty.swift`) — the comment
  attributes a local macro to another package. House failure mode, again.
- **`@ClockDeterministic` is deliberately OUTSIDE `AttributeRecognition`** and hardcoded — SEI's own
  comment says so in as many words. So the one annotation swift-infer depends on for admitting
  `async` is the single name that is neither configurable nor contract-tested. That is item 4's
  precise bite, now with a named target instead of a general worry.

**The order that was proposed, and the trap in reversing it.**

1. **Make swift-infer READ the effect vocabulary.** No cross-repo change — the parser is already a
   dependency. `@Idempotent` as corroboration; **`@NonIdempotent` / `@Observational` as vetoes**.
   This lands on the same afternoon's false-positive work: an author-declared `@NonIdempotent` is
   exactly the signal that kills a shape-only score-35 candidate, and SwiftIdempotency has
   spellings for the negative and conditional cases (`@ExternallyIdempotent(by:)`) that this repo
   cannot express at all. It also gives SwiftIdempotency its first stage in the toolchain.
2. **Then** converge authoring — retire `.idempotent` from `CheckPropertyKind`, keep `.roundTrip`
   and `.preservesInvariant` (no SwiftIdempotency equivalent).
3. **Then** the item-4 contract test, against the hardcoded `@ClockDeterministic` name.

**Doing 2 before 1 is the worst order**: it removes a working test generator and replaces it with
an annotation the tool cannot see — a rename that fails as a *missing* annotation, which is item
4's failure mode reproduced by hand. Same shape as the `private` → explicit `internal` no-op
measured the same day.

**Step 1 is next** (decided 2026-08-04), with one caveat against the framing that sold it. This
repo carries **zero** effect annotations in its own sources — the `@lint.effect` hits are all code
*about* the annotation — and SwiftIdempotency is not a dependency here. So a `@NonIdempotent` veto
would affect **0 of the 13 false positives measured the same day** (item 18). It is a
**capability, not a fix**: it gives an author a way to kill a false law, it does not kill one.
The shape-based work and the annotation-reading work attack the same class from opposite ends,
and only one of them helps a codebase that has annotated nothing — they should not be scored
against each other. What does hold up is the dependency-free part: the doc-comment spelling
`/// @lint.effect idempotent` needs no package dependency, so the veto is usable without adopting
SwiftIdempotency. And the tool **already speaks this vocabulary outbound** —
`discover --effect-annotations` recommends `/// @lint.effect pure` lines
(`EffectAnnotationAdvice` / `EffectAnnotationRenderer`) — and reads none back. One tool talking to
itself in English, which is the *consumer keeps asking the producer* observation with both ends in
the same repo.

#### Does `@ClockDeterministic` belong in SwiftIdempotency? (folded in 2026-08-04)

Raised as *"I think it was bolted on later for the infer-properties work"*. **The timing claim is
exactly right** — `@Idempotent` dates from 2026-05-19; `@ClockDeterministic` and `@Pure` both
landed 2026-07-10, the latter committed as *"closing the recognizer-first gap"*: the recognizer
existed first and the macro was shipped afterwards so the attribute spelling would compile.

**Two questions, and merging them is the trap.**

**Does it belong to the idempotency LATTICE? No — and four fences already say so**, none of them
added by this conversation:

1. Its own doc header: *"Not an effect tier … attaching it grants no lattice trust — it makes a
   **determinism** claim."*
2. A different doc-comment namespace — `@lint.determinism`, where every other marker is
   `@lint.effect <tier>`.
3. SEI **excludes it from `AttributeRecognition`**; the configurable set is
   pure / idempotent / nonIdempotent / observational / externallyIdempotent, and this one gets a
   bespoke `isClockDeterministic(declaration:)`.
4. `Effect` has five ordered tiers. `@lint.determinism` has **exactly one legal value**
   (`clock_deterministic`) — a singleton namespace beside an ordered lattice.

**Does it belong in the PACKAGE? Probably yes, and the two arguments that look decisive both
fail.** *"SwiftIdempotency does not consume it"* is true — and true of **all five markers**, which
are `EmptyPeerMacro {}` and expand to nothing; the whole family is vocabulary, so this does not
separate it. *"It landed late"* fails too: `@Pure` shipped the **same day** for the **same**
recognizer-first reason and is uncontroversially the lattice bottom. And every alternative home is
worse — moving it to swift-infer would have **SEI (upstream, shared with SwiftProjectLint)
recognising a name owned by a downstream package**; SwiftPropertyLaws is a real candidate since it
ships the law that falsifies the claim (`TimedAsyncSequence.debounceIsDeterministicUnderTestClock`),
but its macro vocabulary is suite generation, not claims; a package for one marker is overkill.

**So the problem is not location — it is that the package silently plays two roles** (the
retry-safety lattice, and the toolchain's marker-macro home) and only the first is named.
`@ClockDeterministic` is a tenant of the second, defended by four fences and stated as a structure
nowhere.

**The concrete cost, which is the part worth acting on.** Because it sits outside
`AttributeRecognition`, it is the one annotation in the toolchain that is **neither configurable
nor contract-tested** — and it is the one swift-infer depends on to admit `async` at all. That is
open item 4's target. Either give it a `determinism` field in `AttributeRecognition` (a **separate**
field, not an effect tier — the orthogonality is real and worth keeping) or write the contract
test. Doing neither leaves a rename failing as a *missing* annotation, indistinguishable from
unannotated code.

### The `idempotence` template's false-positive rate, executed (2026-08-04)

Follow-on from *Access widening, re-measured*, where 2 of the 3 laws that ran were false. That was
3 rows. This is the whole template's surface on this repo, **run rather than judged**.

**Apparatus.** All 72 `idempotence` entries from the four source targets' index (default
`--include-possible`), verified via `--all-from-index --index-path` against a worktree at
`1e0218e`. **55 executed. 13 refuted — a 24% false-law rate.**

| score | ran | refuted | held | error | declined |
|---:|---:|---:|---:|---:|---:|
| 30 | 2 | 0 | 2 | 1 | 0 |
| **35** | 49 | **13** | 36 | 13 | 2 |
| 55 | 4 | 0 | 4 | 0 | 0 |
| 80 | 0 | — | 0 | 0 | 1 |

**64 of 72 sit at score 35** — the shape-only floor (+30 type symmetry, +5 value semantics, no
name signal) — and **every refutation is there**. Read this beside `leaderboard-sort`'s finding
that the score is *inverted* inside the 30–45 band: on this larger sample it discriminates
cleanly, 0 of 4 at 55 against 13 of 49 at 35. Different corpora, different bands; both
measurements stand and neither supersedes the other.

**A classifier, frozen before any verdict existed.** Hypothesis: an idempotent function
*projects* onto a normal form, so its result is a **sub-part** of its input; a function whose
result **extends** its input cannot be idempotent. Keyed on the **return expression**, not on
calls anywhere in the body — `quoted` calls `replacingOccurrences` (a normalizer marker) and
*then* wraps in delimiters, so a body-wide scan reads it as a normalizer. Recorded to
`classification-FROZEN.json` while the survey stood at **0 verdicts**.

| predicted | held | refuted | false-law rate |
|---|---:|---:|---:|
| `extension` | 1 | 5 | **83%** |
| `reduction` | 32 | 3 | 9% |
| `unknown` | 9 | 5 | 36% |

**Precision 5/6, recall 5/13.** The single false alarm is `dedupedByStateAndAction`, flagged
because `.append` appears in its body — but it is a *dedup*, and dedup is idempotent. That is the
exact trap the return-expression-first rule was built to dodge, **re-introduced by my own
body-wide fallback**; return-expression-only scores 5/5 at identical recall, so the fallback is
pure cost. Same lesson twice in one measurement: *where* you look beats *what* you look for.

**The 8 misses split into two causes, and only one is a limitation of the idea.**

- **2 are the regex, not the concept.** `quoted` and `escapedLiteral` return `"\"\(escaped)\""`;
  the pattern could not cross the escaped quote. They *are* extensions.
- **6 are a genuinely different class** — `seedTuple`, `typeName(for:)`, `seedString`,
  `codableRoundTripGenerator`, `rationale(for:)`, `regressionFileHash`. Not growth but **domain
  transfer**: `T -> T` where the output is a different *kind of thing* (a hash, a rendered name, a
  seed string), so `f(f(x))` is meaningless though it type-checks. **This is what the existing
  `_description` and capacity-from-scale vetoes have been groping at by NAME for several cycles**
   — the same name-versus-body-shape gap `EqualityBodyShape` was built to close for `==`.

**One tool defect, incidental to all of the above.** `type 'Gen<URL>' has no member 'url'` blocks
**9 rows**, all the `defaultPath(for:)` family — false laws by inspection
(`appendingPathComponent`). So 24% is a **floor**: nine known-false rows cannot run. Plus 4
verifier traps (signal 5) and 1 opaque-result-type failure.

**An apparatus bug caught before it became a finding.** Six rows first failed
`cannot find type … in scope`, which reads exactly like a residual of item 16's cross-module
import fix. It was mine: the filtered index's `sourceFileByTypeName` still pointed into a
worktree I had deleted, so the module lookup resolved against nothing and no import was emitted.
Re-run with corrected paths, three of them compiled and ran. **Third instance in one day of the
same shape** — after `private` → explicit `internal`, and item 13's own warning about widening a
member of a private type. The harness fails in ways that look precisely like the tool failing.

**What this does NOT settle.** Whether a shape veto should ship. It would be the tenth veto on
this template, and PRD §3.5's corollary says the remedy for too much output is to raise
thresholds rather than pile on filters — but this is a **precision** problem, not a volume one,
and `EqualityBodyShape` is the standing precedent for exactly this move. What the numbers add is
that the target is now sized (24% of an executed surface, 13 rows) and the discriminator scored
(83% precision blind) rather than argued.

### The `@EffectUnknown` dependency chain (2026-08-04)

Recorded because the chain is four links long, crosses three repositories, and
its **first** link is an open performance issue — which is not a connection
anyone would guess from either end.

**Where it started.** Item 17's step 1 made swift-infer read the effect
vocabulary, and dogfooding it surfaced a gap: an author who means *"I cannot
guarantee idempotency here"* had no way to say so. `@NonIdempotent` claims
something strictly stronger — SwiftIdempotency defines it as **unconditionally**
non-idempotent, *"re-invocation produces additional observable effects (sending
email, inserting rows, publishing events)"*. The tier that does mean "cannot
determine" is `unknown`, which had been in the reference lattice from the start
and was **inference-only**: no spelling, so no way to write it down.

**Link 0 — shipped.** `@EffectUnknown`
([SwiftIdempotency#3](https://github.com/Joseph-Cursio/SwiftIdempotency/pull/3)),
marker-only, plus `/// @lint.effect unknown`. Also corrected two stale
`REFERENCE.md` claims found while checking — the table gave `pure` no macro and
the prose called `pure`/`unknown` "tiers that need no marker", but `@Pure`
shipped 2026-07-10.

| # | link | state |
|---|---|---|
| 0 | SwiftIdempotency ships the marker | **done** |
| 1 | SEI learns to *read* it | **now the only blocker** |
| 2 | swift-infer bumps the SEI pin | **done 2026-08-04** — `bfcf0e3` |
| 3 | swift-infer suppresses on it | waiting on link 1 |

**Links 2 and 3 came unblocked the same day**, by fixing open item 1 rather than
working around it — the `~2×` regression that made the pin unbumpable is gone, and
the bump landed past it. What is left is the one link that was never about
performance.

**Why the reader must live in SEI.** swift-infer could parse `@lint.effect`
itself, and that is precisely what `EffectAnnotationParser` exists to prevent —
one grammar, shared by SwiftProjectLint and swift-infer, is the reason the
vocabulary has not already drifted. Re-implementing it downstream would buy
speed now and a second dialect later.

**Why that blocks on a performance issue.** swift-infer pins SEI at
`1f2265a0`; SEI's HEAD is `097181a`, the commit **open item 1** records as a
`~2×` regression on the whole-domain purity path and names as blocking the pin
bump. So the reader cannot ship without either moving past that commit or
branching SEI from the old pin — and a divergent branch is worse than waiting.

**Deliberately NOT in the chain: an `Effect` case.** `unknown` is *incomparable*
to `non_idempotent`, so admitting it to SEI's `Effect` enum would force its
linear five-tier chain into a genuine partial order and replace the rank-only
`lub(_:)` with a Hasse-diagram join — a change SEI declined for exactly this
tier. Link 1 should therefore read it the way `@ClockDeterministic` is read: its
own predicate, outside `AttributeRecognition`, answering its own question. That
keeps the chain to a reader rather than a re-derivation of the core algebra.

**The honest state until then: the marker documents intent and nothing acts on
it.** Which is the very condition it was built to end — a declaration that is
indistinguishable from an unannotated one. Worth saying plainly rather than
letting "shipped" imply "working".

### The `Gen<URL>` defect — fixed, after a wrong diagnosis worth keeping (2026-08-04)

Item 19, closed. Two lines in this repo, no kit change, no version bump. **The first
diagnosis of it, published earlier the same day, was wrong**, and the way it was wrong
is the more useful half.

**What it actually was.** `Gen<T>` comes from `PropertyBased`; the Foundation
generators — `Gen<URL>.url()`, `.uuid()`, `.data()`, `.decimal()` — are **extensions in
`PropertyLawKit`**. The algebraic verify workdir declared `PropertyLawComplex` and not
`PropertyLawKit`, and the strategist stub imported `PropertyBased` alone, so the
expression the kit handed us referenced an extension the file could not see.

**Why the kit is not at fault.** `CompositeMemberParser` omits `PropertyLawKit` from
`requiredImports` **deliberately**, saying these are *"the generators every derivation
consumer already imports"* and naming `GeneratedFileEmitter` / `ScaffoldFileEmitter`.
True of the kit's own emitters. False of a verify stub — which is a
[border claim](glossary.md#border-claim) about a consumer in another repository, and we
were the consumer violating it. `.interaction` and `.valueSemantics` already declared
the product; `.algebraic` was the outlier.

**The wrong turn, recorded because it cost a cross-repo refactor.** The first pass added
the product and the import by hand, ran the binary **directly**, and hit
`dyld: Library not loaded: @rpath/libTesting.dylib`. That was written up as *"the obvious
fix builds and then does not run"*, and a `PropertyLawFoundation` carve-out was built in
SwiftPropertyLaws to move the generators out of a Testing-bound module.

Three things falsified it, in order:

1. A probe importing **only** the new Testing-free target still failed to launch — so
   `PropertyLawKit` was never the source.
2. **`swift-property-based` itself imports `Testing`** (four files). Every verify stub
   ever emitted links it.
3. `VerifierSubprocess` **already injects `DYLD_LIBRARY_PATH` / `DYLD_FRAMEWORK_PATH`**
   for exactly this, and says so — V1.53.A, tracing cycle-49's 12 parse-error picks to
   this same `dyld` message.

So the launch failure was an artefact of running the binary outside the harness that
exists to run it. **The lesson is not "check the harness" but something narrower: a
reproduction that skips the caller is not a reproduction.** The carve-out was reverted
unpushed.

**Measured after the fix**, every `URL`-carrier row on this repo:

| | before | after |
|---|---:|---:|
| execute | 0 | **11 of 13** |
| held | 0 | 2 |
| **refuted** | 0 | **9** |

The 9 refutations are the `defaultPath(for:)` family, and they are **not new bugs** —
they are `appendingPathComponent`, which item 18's frozen classifier flagged as
`extension` (the output extends its input, so it cannot be idempotent). Nine blind
predictions, nine confirmations, on rows that could not run when the prediction was made.
That is the strongest evidence the classifier has, and it arrived from a defect fixed for
an unrelated reason. The 2 remaining non-executing rows are a different class
(`cannot find 'Scaffold' in scope` — item 16's residual, not this).

### Doc staleness: automate the trigger, not the habit (2026-08-03)

The rejected alternative was *"check the design-internal docs whenever we merge."* Two problems:
the **trigger is wrong** (a merge here does not correlate with a sibling moving — the gap between
sessions does), and **"check the docs" has no pass/fail**, so a skipped check looks exactly like a
passed one. Shipped instead: provenance trailers + `make docs-drift` + a `SessionStart` hook, with
claims split by perishability — counts and measurements rot, diagnoses do not. See PRs #55/#56 and
`scripts/docs_drift.sh`'s header.

---

## Standing observations

Toolchain-level reads with no single owning package. Not tasks; not measurements.

### The consumer keeps asking the producer for things, in English

Three times the downstream tool discovered it needed something upstream already knew, and each was
bolted on differently:

- `role` on a seed — added **because `discover` was already printing** *"the manifest SHOULD have
  named it: this is a LINTER gap."*
- `KitEvidence` — the kit's verdicts were the only *executed* evidence anywhere and fed nothing back.
- The rescue warnings — `swift-infer` prints prose **addressed at the linter**, to a human, hoping
  they act.

Not three coincidences. The pipeline is one-way by design and has needed backflow three times.
Worth deciding deliberately: is one-way load-bearing, or just how it started? **When a tool's best
diagnostic output is a sentence addressed to another tool, that is a missing channel.**

### The middle is thin where it should be thick

Volume and value point opposite directions at the lint → infer boundary: ~664 candidate findings →
1,657 seeds → **21 default-tier picks**. Meanwhile the *refactoring* half — extract this kernel,
make this domain type — **does not seed at all** (`PBTSeedsFormatter.seedKinds` maps four rules,
all testability/idempotency). The highest-value handoff is human-only; the highest-volume one is
nearly all noise. `CandidateInventory` fixed the reader-facing symptom by collapsing the census;
the manifest still carries the flood and not the insight.

### "Toolchain" claims more than the code backs — *now half-addressed*

**Was:** two of five packages had no automated relationship to anything, and no command ran the
loop, so every claim about "the loop" described a sequence nobody had automated.

**Now:** `scripts/toolchain.sh` runs **stages 0–2** (locate → lint → `discover --seeds`) and
declares 3–5 as not-implemented on every run. What that changes and what it does not:

- **Closed:** the sequence is executable and attributable. `run.json` records tool SHAs, so two
  runs are comparable — the precondition for any end-to-end number.
- **Still open:** stages 3–4 do not exist, so **no run executes a law** (item 9). Stage 5 never
  will — hardening is a human's job, and the driver says `not-a-command` rather than pretend.
- **SwiftIdempotency is still attached by one word** (`@ClockDeterministic`, via SEI) and appears
  in no stage. That half of the observation is untouched.

**Two facts that only surfaced by writing it**, and they say more than the observation did:

1. **`.pbt/seeds.json` had never existed anywhere on this machine.** Both repos document that
   path — the formatter writes it, `discover --seeds` reads it — and the hop had no instance until
   2026-08-03. A documented handoff with zero instances is not a handoff.
2. **The loop's entry point could not be invoked** — SwiftProjectLint ships no installed binary
   and is not on `PATH`, so "run the linter" meant knowing to type `swift run CLI` from the right
   directory. **Fixed 2026-08-03** by `scripts/bin/swiftprojectlint` (add `scripts/bin` to `PATH`).

   The reason it stayed broken is worth keeping, because it was a *good* instinct producing a bad
   outcome: binaries were never installed because the code was always changing, and recompiling
   was the safe choice. That is correct — **an installed binary is a remembered build**, the same
   hazard the A/B rule exists to prevent. The wrappers keep that property (they build through
   SwiftPM every invocation, so the binary is always the working tree) while removing the friction,
   which was never the compile — it was the missing command.

### The measurements are all withdrawn; the diagnoses survive

`roadtest-self-dogfood.md` voided, `leaderboard-sort`'s scorecards voided,
`PBT_TOOLCHAIN_FIX_PLAN.md` scored against a frozen fixture. **There is no current number for
"does a reader following the loop reach the bugs?"** — the one row the road test says should be
the only row that matters. That is open item 7, and it is downstream of *"toolchain claims more
than the code backs"*: you cannot cheaply re-measure a loop you cannot cheaply run.

**Partly unblocked as of 2026-08-03.** `scripts/toolchain.sh` makes stages 0–2 re-runnable and
writes a comparable `run.json`, so a *seed-and-suggestion* number is now cheap. A **refutation**
number still is not, because that needs stage 3, which does not exist (item 9). Worth being exact
about which number is back: the loop's own headline row — *would a reader reach the bugs?* —
remains unmeasured.

### Every guard here was a retrofit

`VerifierWorkdirKitPinTests`, `SeedRoleContractTests`, `KitCoverageLawLevelTests` — all added
*after* the incident. Not one [border claim](glossary.md#border-claim) was guarded when written.
The question is not "which guard is missing" but **what makes writing one feel like it needs no
test** — and the answer looks like: it is expressed where prose is normally decorative, its failure
is an absence, and the author is the only person who ever held both repos at once.
