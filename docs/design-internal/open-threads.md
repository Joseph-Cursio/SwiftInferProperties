# Open threads

Things decided, noticed, or left undone that have **no other home**. Deliberately terse — an
index, not an essay. Anything with a real home lives there instead; this file exists so a
conversation's residue does not evaporate.

> **As of 2026-08-04** · `SwiftInferProperties@1e0218e`. Entries here are *not* dated claims
> about code — they are open questions and standing reads. Close them by deleting the row and
> putting the answer where it belongs. Measurements *inside* an entry carry their own date and
> SHA; the suite run in item 0 is the only thing re-taken at `1e0218e`.

<!-- doc-provenance date=2026-08-04 subject=SwiftInferProperties@1e0218ed538b8d0c62c91b80cc1b1a5009d129b1 observer=SwiftInferProperties@1e0218ed538b8d0c62c91b80cc1b1a5009d129b1 -->

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

**Do the 1-point version anyway, because it is cheap and it is a mystery:** diagnose the single
`build-failed` on `isStale(indexPath:packageRoot:)`. One entry, one workdir, and an undiagnosed
build failure in a bucket where every other cause is now named is exactly the shape that turns out
to be a fourth defect.

**2. Generators for syntax-node carriers — scope it before building it.** 14 of the 22 is the
largest single bucket left anywhere in this survey, and it is *one* question: can a `TokenSyntax` /
`SyntaxCollection` be derived at all, and by whom — here, or `DerivationStrategist` in
SwiftPropertyLaws? The design decision *"generator inference delegates to SwiftPropertyLaws"* says
the answer is probably not here, which makes this a scope-and-file item rather than a build item.

**3. Re-measure item 13's access-widening probe, with a pre-check.** The recorded read is that
access is not the binding constraint — widening moves a function from *invisible* to
*proposed-but-unrunnable*. That was written before today. It is now cheaply falsifiable: take the
20 widened functions, check their parameter types against the carrier-decline list above, and see
whether they land in the same bucket. If they do, the read stands and item 13 stays deferred; if
they do not, the ordering against item 14 changes.

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
| 1 | **[SwiftEffectInference#1](https://github.com/Joseph-Cursio/SwiftEffectInference/issues/1)** — `~2×` regression on the whole-domain purity path | filed with an A/B; blocks the pin bump. Fix: stop `inferredEffect(for:)` delegating to `verdict(for:)` |
| 2 | **Then**: bump the SEI pin, run `make perf` *before* `make test` (perf is step 3 of 9, fail-fast hides the rest), add a pin-equality guard, then adopt `verdict(for:)` | ordered; each step gated on the one before |
| 3 | **Is SwiftProjectLint silently paying item 1?** It is already on `097181aa` and calls `PurityInferrer` from two visitors over every function *and closure* in a project | unmeasured. Cheap: point the same A/B at its own suite |
| 4 | **The attribute-grammar join has no contract test.** SwiftIdempotency ships the macro names; `AttributeRecognition.default` hard-codes them; nothing asserts they still match | a rename fails as a *missing* annotation, indistinguishable from an unannotated codebase |
| 5 | **`PBTSeed.role`'s doc comment is stale** — says two rules classify roles; `ExtractablePureKernelVisitor:106` makes it three | one-line fix in SwiftProjectLint |
| 6 | ~~`.swiftinfer/` is not gitignored~~ | **Closed 2026-08-03.** Ignored at the **root only** (`/.swiftinfer/`, not `**/`) — `fixtures/cycle27-surface/.swiftinfer/index.json` is a tracked frozen corpus and a recursive pattern would have hidden it. A deliberate commit is still available via `git add -f` |
| 7 | **No current end-to-end number** for the loop | see *Standing observations* → *The measurements are all withdrawn* |
| 8 | **Exit criteria for "the toolchain is in shape"** are unwritten | see *Decisions* → *Road tests were misfiled* |
| 9 | **Driver stages 3–4** (`verify`, kit conformance suites) are declared and unimplemented | `scripts/toolchain.sh`. Until they exist, **no run of the loop executes a law** — the driver says so every run rather than implying otherwise |
| 10 | **The two ends of the lint→infer hop take different inputs.** The linter takes a repo path and works out the layout; `discover` requires exactly one of `--target`/`--sources` and errors without one | a reader following the documented hop hits an argument error on their first attempt. The driver papers over it by inferring scope — open question whether the *fix* belongs in `discover` instead |
| 11 | ~~Driver stage 0 builds another repository~~ | **Closed 2026-08-03, the other way.** The rebuild is now *load-bearing*: a repo SHA describes the binary only if we just built the binary from it, so building unconditionally is what earns the attribution. A `stale` binary fails the stage — accepted deliberately, since an unattributable run is worse than no run |
| 12 | **Neither binary can state its own build identity.** `swift-infer --version` reports `1.148.0` — identical whether built this morning or months ago from another commit | the real fix for item 11's workaround: embed a build SHA at compile time, in *those* packages, and have the driver read it from the binary rather than the tree. Prerequisite for ever shipping installed release binaries |
| 13 | **Speculative refactoring** — mutate a copy, verify, propose a patch only when the law ran | designed 2026-08-03, **unbuilt**. A 20-function probe measured 20 → 8 proposed → 2 composer-supported, i.e. **≤+60 against a base of 100 — a 60% gain at the ceiling**. Ordering against 14 is **not settled**; see *Decisions* |
| 14 | ~~Write a `predicate` composer~~ | **Closed 2026-08-03, and MEASURED.** Shipped, then found unreachable (gate 2), then found never-composing (a compose-time value escaped as a runtime one) — three defects between "written" and "runs", each invisible to the unit tests that call the composer directly. Survey of all 126: **54 run and hold**, against a measured base of **0**. The `≤+126` ceiling resolved to **+54**; 56 of the remaining 72 are item 16, 11 are SwiftSyntax carriers with no generator. **Superseded by item 16: the figure is now 104.** Zero refutations — these are regression guards on correct code, not bugs found |
| 15 | ~~Are `predicate`/totality laws refutable here, or a wall of green?~~ | **Closed 2026-08-03: not a wall of green.** 35 of the 126 (27%) already carry a hand-written totality guard, and ~half of a 20-sample would trap under a plausible implementation. Item 14 unblocked; see *Decisions* |
| 16 | ~~The index records a CARRIER; a law needs a SIGNATURE~~ | **Closed 2026-08-03, and MEASURED.** Built as scoped; `≤+56` realised as **+50** (54 → **104 of 126**). Both compile buckets are ZERO: cross-module 37 → 0, arity 19 → 0. The shortfall accounts for itself — carrier declines 11 → 17, entries that used to fail at compile and now fail earlier at generator resolution. Two defects found only by running it: the receiver is an implicit parameter (7 rows, all previously hidden behind the import failure), and the n-ary path dropped the `GeneratorResolver` `emit` builds (5 rows, mine, same day). See *Decisions* → *Signature, not carrier* |

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
