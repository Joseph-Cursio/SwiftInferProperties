# Suspected-defect verdict — scope, with the proposed gate measured and refuted

> **Status:** `shipped` · **As of:** 2026-08-08


> **§6 step 1 was RUN on 2026-08-08 and is misspecified. See §9 for the result.**
> Three corpora, 0 refutations, so the confound is **unsettled** — and not for want
> of trying: a HEAD corpus is correct code, and correct code does not refute. The
> step asks for "a second corpus with an unrelated template mix"; what it needs is
> **pre-fix commits**. Two blocking defects were found and fixed on the way (#170,
> #169), and one clause of §2 is now measurably weaker than when it was written.

**Status: scoped, not built. 2026-08-07.** Scopes
`docs/archive/Refuted-high-confidence-guess as candidate bug.md`, which is unchanged and
still the statement of the idea. **The idea survives contact with the data; its gate does
not.** All three of the gate's clauses, applied literally to this repo, select **zero
rows** — including the four refutations that turned out to be real defects and were fixed.

The idea in one line: a `measured-defaultFails` has two causes — *the guess was wrong* or
*the guess was right and the code is wrong* — and the tool currently resolves that fork
silently to the first. Surface the second as a distinct verdict.

## 1. The calibration data already exists, and nobody has pointed it at this

The idea doc is dated 2026-07-21 and reasons about the precision risk from first
principles: *"most disproofs really are bad guesses… without a high-confidence gate,
every refuted heuristic becomes a suspected bug and the mode is pure noise."* Two weeks
later the whole-corpus survey measured exactly that population and the streams are
committed — `fixtures/whole-corpus-survey/2026-08-05-whole-corpus.jsonl`, 281 records,
release binary at `1ef7128`, written up in `docs/design-internal/open-threads.md` →
*The whole-corpus number*.

**139 entries executed a law. 130 held. 9 refuted.** Those 9 are the entire population
this feature would ever classify, and here they are:

| template | carrier | function | failing trial |
|---|---|---|---:|
| `commutativity` | `Decisions` | `merge(_:)` | 1 |
| `commutativity` | `VerifyEvidenceLog` | `merge(_:)` | 1 |
| `commutativity` | `PostAcceptanceOutcomeLog` | `merge(_:)` | 10 |
| `commutativity` | `InteractionDecisions` | `merge(_:)` | 44 |
| `idempotence` | `MinedTraceSelector` | `markovSynthesized(from:)` | 0 |
| `idempotence` | `LiftedTestEmitter` | `regressionFileHash(for:)` | 0 |
| `idempotence` | `LiftedTestEmitter` | `codableRoundTripGenerator(for:)` | 0 |
| `idempotence` | `SwiftInferCommand.Verify` | `seedString(for:)` | 0 |
| `idempotence` | `ViewModelActionSequenceStubEmitter` | `seedTuple(from:)` | 0 |

The stream carries no tier field, so the tier join comes from that thread's own table
(**Strong** 3 entries / 0 ran · **Likely** 27 / 23 ran / **4 refuted** · **Possible** 249
/ 116 ran / **5 refuted**) plus its statement that *"every executed `commutativity` law on
this repo is one of the four merges, and every one is false."* The four `commutativity`
rows are the Likely four; the five `idempotence` rows are the Possible five.

**And the two halves were adjudicated independently, by hand, before this scope existed:**

- The four Likely refutations became **#92 (merge fold non-commutative ×4)**, confirmed
  real and **fixed in PR #98**, with `MergeAlgebraPropertyTests` pinning all four logs
  over an injected clock.
- The five Possible refutations are the **domain-transfer class**, **#93**, still open and
  deliberately so: `IdempotenceReturnShapeClassifier`'s own doc names the class and
  declines to veto it. `fixtures/domain-transfer-signal/` then scored a candidate veto for
  it at **recall 4/5, precision 4/12** — two true laws suppressed per false one removed.
  These are false laws about correct code. `seedString` hashing its input is not a bug.

So the discriminator this feature needs is not hypothetical and does not need a new
corpus. **4/4 of the high-tier refutations were defects; 0/5 of the low-tier ones were.**
That is a better starting separation than the idea doc dared assume — and it is why the
gate is worth getting right rather than guessing.

## 2. Three defects in the proposed gate, all pointing the same way

### 2.1 `.strong` fires on nothing

The idea gates on `staticTier >= .strong`. In the survey, **`Strong` is the one tier where
nothing runs at all**: 3 entries, all declining `unsupported-template`
(`differential-equivalence` ×2, `invariant-preservation`). Verify cannot execute the
suggestions discovery is most confident in, so a `.strong` gate cannot see a refutation to
classify.

Shipped as written, the feature would be a guard green because it cannot fire — the
arm-4 trap `docs/measurements/stale-summary-guard-declined.md` names, and the same
failure `DeferralFalsifierTests.resolverActuallyResolves` exists to prevent.

> **Weakened 2026-08-08 — the conclusion holds, the reason given for it does not.**
> `Strong` is **not** structurally unable to execute; it had never been pointed at a
> corpus where it could. Five `Strong` rows executed on swift-collections (§9) —
> `idempotence` ×3, `dual-style-consistency` ×2 — the first anywhere. So "verify
> cannot execute the suggestions discovery is most confident in" was a statement
> about this repo's template mix and about two tooling defects, not about the tier.
> The `.likely` gate in §3 still stands, but on the §9 evidence rather than on
> `.strong` being unreachable: **5 Strong rows ran and 0 refuted**, so a `.strong`
> gate remains a gate with no measured population to classify.

### 2.2 `>=` is backwards against this repo's `Tier`

`Tier` is `Comparable` with **`verified` as the minimum** (`Tier.severityRank`, and the
ordering is a deliberate `switch` so `case` layout cannot move it). So `tier >= .strong`
literally selects `likely`, `possible`, `suppressed`, `advisory` — the *opposite* of the
intent, and the noisiest possible reading. The spelling the codebase already provides is
`Tier.atLeastAsProminentAs(_:)`, which exists precisely because two call sites had
hand-kept `["Verified", "Strong", "Likely"]` string lists with no compiler check.

Use `Tier.atLeastAsProminentAs(.likely).contains(tier)`. Never open-code the comparison.

### 2.3 The coverage gate rejects every algebraic refutation

The idea says to gate on full action-space coverage, *"the same soundness bar the
gate-overrule uses"* — i.e. `excludedActionCount == 0`. That field is **interaction-side
only**. It is written by `VerifyInteractionPipeline+Evidence.foldPartialExplorationDisclosure`
and by the two view-model/output-determinism recorders; the algebraic path
(`VerifyEvidenceRecorder.evidence(for:)` and the `--all-from-index` survey) never sets it,
so it is `nil` — and `VerifyEvidence`'s own doc says `nil` is *"treated conservatively as
**not** full coverage."*

All 9 refutations above are algebraic. The coverage clause alone rejects all of them,
including the four confirmed defects.

**The clause is not wrong, it is mis-sited.** Relaxed partial exploration is a TCA
reducer concern; there is no action space to under-explore in `Decisions.merge`. The
algebraic surface already partitions the artifact risk the clause exists to manage —
a trap or parse failure is `measured-error`, not `measured-defaultFails`, so an algebraic
default-fail already means *the stub compiled, ran, and the law failed at a numbered
trial*. The interaction surface needs the clause; the algebraic surface must not inherit it.

## 3. The corrected gate

A `measured-defaultFails` is reclassified **Suspected defect** when all of:

1. **Pre-verify tier is at least `.likely`** — `Tier.atLeastAsProminentAs(.likely)`, read
   from the score-derived tier, *not* the post-verify effective tier. `.verified` is
   unreachable here by construction (`Tier.promoted(byVerifyOutcome:)` only promotes on
   `measuredBothPass`), so in practice the set is `{.strong, .likely}`.
2. **Surface-appropriate coverage.** Interaction: `excludedActionCount == 0`, `nil`
   remaining conservative for legacy records. Algebraic: no coverage clause — the
   outcome partition already carries it.
3. **The counterexample is present.** `VerifyEvidence.counterexample != nil`. A
   default-fail with no rendered failing input cannot be shown to a user as a defect
   claim, and it is the cheapest possible check that the record is well-formed.

Everything else stays Disproven.

Against the survey: **4 Suspected defect, 5 Disproven** — the exact split three weeks of
hand-adjudication produced.

## 4. What the measurement does **not** establish

Three limits, and the first is the one that could overturn the design.

**Tier is perfectly confounded with template.** All four high-tier refutations are
`commutativity`; all five low-tier ones are `idempotence`. On n=9 from one corpus,
*"the tier predicts whether a refutation is a defect"* and *"`commutativity` refutations
are defects and `idempotence` refutations are false laws"* fit the data identically.
`open-threads` states the tier reading; nothing has separated the two. A template-keyed
rule would be a much weaker feature (a fixed list of templates rather than a confidence
signal), so this is worth one measurement before building, not after.

**One corpus, and it is this repo.** These are swift-infer's own sources. The four
defects are four instances of *one* diagnosis (a last-write-wins fold that ties on a
whole-second `Date()` stamp) in four near-identical log types, which is closer to n=1 than
to n=4 for the purpose of calibrating a threshold.

**The Possible tier's 5 are not a random sample of bad guesses.** They are one named,
already-diagnosed class. A second corpus could easily contain a low-tier refutation that
*is* a defect, which would cost recall rather than precision — the safer direction, and
the reason the threshold should be tunable rather than baked.

## 5. Siting: two folds, not one function

There is no single place to put this. `VerifyEvidenceScoring` and
`InteractionVerifyEvidenceScoring` are separate folds on separate pipelines, and they must
stay separate here, because **`VerifyEvidence` cannot tell you which surface wrote it.**
`makeEvidence` stores `template: invariant.family.rawValue`, and
`InteractionInvariantFamily.idempotence` and `TemplateName`'s `idempotence` are the same
string. A `nil` `excludedActionCount` on a record labelled `idempotence` is ambiguous
between *algebraic* and *legacy interaction*.

At runtime the ambiguity never arises, because each fold only ever sees its own records.
So: **classify inside each fold, keyed on the surface that owns it** — do not write one
`suspectedDefect(for: VerifyEvidence)` helper over the shared type, which would have to
guess. If a future consumer needs to classify a record it did not produce, add an explicit
surface discriminator to `VerifyEvidence` rather than parsing `template`.

## 6. Build order

1. ~~**Settle the confound (§4).** Re-run `verify --all-from-index` over a second corpus
   with an unrelated template mix and check whether the tier/template readings come apart.
   One run, no code. If they do not come apart, this ships as a template rule and the
   framing changes.~~
   **Run 2026-08-08 and MISSPECIFIED — see §9.** Three corpora produced 0 refutations,
   because a corpus at HEAD is correct code and correct code does not refute. Replace
   with: **re-run at `<fix>^` commits**, per `docs/plans/kit-suite-backtest-plan.md`'s
   own argument. It also was not "one run, no code": two defects had to be fixed first.
2. **The classifier**, per §3 and §5. A pure function per fold plus its tests; no new
   execution machinery — the disproof, the counterexample, the shrunk counterexample, the
   seed and the coverage stamp are all already persisted on `VerifyEvidence`.
3. **A fifth `prove-then-show` bucket.** `docs/reference/prove-then-show.md` renders four
   (Proven · Disproven · Unverifiable · Inconclusive) through a shared row-based renderer
   serving both surfaces; Suspected defect sits between Disproven and Proven. The summary
   line and the `--family` restriction come along for free.
4. **A true-positive fixture** (the idea doc's open question 4). `fixtures/` carries
   deliberate false positives for the verify corpora but nothing that is a *high-confidence
   guess against genuinely broken code*. The pre-#98 merge fold is the obvious donor: it is
   a real defect, at a known SHA, with a pinned test — the same `<fix>^` construction
   `docs/plans/kit-suite-backtest-plan.md` is built on, and for the same reason. A fixture
   frozen at HEAD would be all-green and could not distinguish a working classifier from a
   blind one.

Deliberately **not** in this list: a `discover`-default surface. See §7.

## 7. Open questions that survive the correction

- **Threshold tunability.** `.likely` is measured on n=9 from one corpus. Expose it, or
  pin it and revisit after the second corpus?
- **Where it renders.** The idea offers `--suspect-bugs` or `prove-then-show`-only.
  `prove-then-show` is already the everything-gets-executed surface with buckets and a
  posture of showing disproofs, so it needs no new flag and no posture change. A
  `discover`-default surface would change what the tool *is* — that is the product call
  the idea doc flags, and it should stay unmade until the classifier has run on a corpus
  that is not our own.
- **Blame wording.** Unresolved and load-bearing. The tool cannot know which fork it is
  on; the verdict must present the fork. Note that the *measured* base rate at `.likely`
  is 4/4, which is a strong argument for confident wording and exactly the reason to
  distrust it — 4/4 on one diagnosis in one repo.
- **Interaction-side base rate is unmeasured.** `docs/measurements/interaction-trap-attribution-census.md`
  measured 10 refutations, 10 attributed to the invariant check and 0 to subject code —
  which, read as this feature's question, is a **0/10 defect rate on the interaction
  surface**, the opposite of the algebraic one. That census is reducer-only and says so.
  Suspected defect should therefore ship algebraic-first, with the interaction fold
  deferred until that census is re-run over an MVVM/VIPER corpus.

  > **CORRECTED 2026-08-08 — this paragraph misreads the census, and the deferral it
  > justified is withdrawn (§13).** The census defines `.invariantCheck` as *"the property
  > is genuinely refuted"* and `.subjectCode` as the subject's own trap, so **10 of 10
  > `.invariantCheck`** means **zero harness artifacts**, not zero defects. Its own §4 says
  > *"the `.measuredDefaultFails` verdicts these corpora produce are all genuine."* That is
  > a reason to surface interaction refutations, not to defer them. The deferral's falsifier
  > is removed because the fold is built.

## 8. Recommendation

**Build it, at `.likely`, on `prove-then-show`, algebraic surface only — after step 1.**

The idea's value proposition holds up better than it claimed: it is not a speculative
posture extension but a mechanisation of an adjudication this project has already
performed by hand, correctly, on the only population that exists. The cost really is
small — a classifier, a bucket, a fixture — and nothing about it changes the default
suggestion feed.

What must not carry forward is the gate. Three clauses, three ways of selecting zero rows,
and the reason each is wrong is a fact about this codebase that was not available when the
idea was written. **Write the corrected gate down before writing the classifier** — that
is the whole point of this note.

## 9. Step 1, run — three corpora, zero refutations (2026-08-08)

swift-infer `1.148.0`, release binary, `verify --all-from-index --max-parallel 4`.
Streams and the focused index in the session scratchpad; the two fixes below carry
their own regression tests, which is the durable half.

| corpus | SHA | entries | executed | refuted |
|---|---|---:|---:|---:|
| SwiftEffectInference | `50c5d3a` | 38 | 8 | **0** |
| SwiftPropertyLaws | `91e09a2` | 39 | 0 | — |
| swift-collections (focused, 3 arms) | `899809d3` | 98 | 12 | **0** |

**No refutation, anywhere. The confound is untouched**: tier and template remain
perfectly aligned across the only nine refutations that exist, exactly as in §4.

### 9.1 Why zero, and why the step cannot work as written

Not bad luck, and not carrier reach. **A corpus at HEAD is correct code.**
`BitSet.union`, `OrderedSet.formUnion` and `SortedSet.intersection` are associative
and commutative; the laws hold because they are true. The base rate of refutation in
the original survey was 9 of 281, and 4 of those 9 were one defect (#92) in four
near-identical log types — so the expected yield from ~150 correct entries was
approximately zero before the run started.

This project already made this argument, in a doc this scope cites for a different
purpose. `docs/plans/kit-suite-backtest-plan.md` is built on it:

> These libraries are correct at HEAD, so an all-green run is indistinguishable from
> the tool being blind; only the pre-fix commit separates those readings.

That is the same problem in a different feature. **Step 1 needs `<fix>^` commits**,
which is a materially more expensive experiment than "one run, no code": each arm
needs a known defect, its fixing commit, and a corpus that builds at the parent.
`876177db^` on swift-collections is the one already scouted (§Arm 1 of that plan) and
would give a `symmetricDifference` refutation at `Likely` — a `commutativity` row, so
it *replicates* the observed cell rather than breaking it. **An arm that separates the
readings has to be a refutation at `Likely`/`Strong` in a template that is not
`commutativity`, or at `Possible` in one that is.** Nothing yet scouted supplies one.

### 9.2 What the run did establish

- **`Strong` executes.** Five rows, the first anywhere: `idempotence` ×3,
  `dual-style-consistency` ×2. §2.1's conclusion survives; its stated reason does not.
- **Arm A ran on both sides of the tier split within one template.** `idempotence` at
  `Strong` (3 ran) and `Likely` (3 ran), 0 refuted on each; `Possible` reached 0. So the
  arm designed to separate tier from template *ran* and returned no signal, rather than
  being blocked.
- **The confound is confirmed non-structural in a third corpus.** `idempotence` spans
  `Possible`/`Likely`/`Strong` in swift-collections as it does here and in
  SwiftPropertyLaws. Tier is not template in disguise; it is the refutations that align.
- **Two defects, both fixed, both invisible to this repo's own corpus.**
  **#170** — `PackageProductResolver` waited for the child to exit before draining its
  pipe, so `verify` hung indefinitely at 0% CPU on any package whose `dump-package`
  output exceeds ~64 KB (swift-collections: 133,341 bytes). **#169** — the synthesized
  manifest declared the corpus both by URL and by path whenever the corpus was one of
  the verifier's own dependencies, which is every canonical algebraic corpus; and
  removing that uncovered a third, where one unresolvable product edge failed *manifest
  loading* for all 54 buildable entries.

### 9.3 The methodological residue, which outlasts the question

- **A completion check must not be satisfiable by the previous run's artifact.** A
  monitor keyed on `wc -l >= 98` reported COMPLETE against the *prior* run's file while
  the new one was still building, and its numbers were read as fresh. Delete the output
  first, or key on process exit. Same family as §10.3's "never compare against a stored
  count", met from a new direction.
- **Green unit tests are not evidence that a fix works.** #169's first fix passed seven
  tests and moved the corpus **not at all** — 54 of 98 failing before and after — because
  every test exercised the renderer in isolation while the defect lived in how its output
  was combined. The corpus is the oracle; the suite is a regression net afterwards.
- **A blocked measurement is worth more than it looks.** The question this run was
  supposed to answer is still open. It nonetheless found two defects that made
  `swift-collections` and `swift-numerics` unverifiable, which is most of the population
  the algebraic surface exists for.

## 10. The confound is settled by a planted arm — and the gate takes a hit (2026-08-08)

§9 could not settle §4 because correct code does not refute and no historical `<fix>^`
candidate was reachable. `fixtures/planted-defect-arm/` takes the other route: rather than
hunting history for a bug that lands in the empty cell, it plants one there.

Three types, one method name (`combine(_:)`), all scored **`Likely` 70** by both
`associativity` and `commutativity`, so template and implementation vary while every
scoring signal is held constant. One run, one generator.

| template | carrier | verdict | the refutation was |
|---|---|---|---|
| `associativity` | `BlendSummary` (averages the averages) | **REFUTED** | **a real defect** |
| `commutativity` | `PathSegment` (joins with `/`) | **REFUTED** | **a false law about correct code** |
| both | the remaining four rows | held | controls |

**The template reading is dead.** It needed both *"a non-`commutativity` refutation is a
false law"* and *"a `commutativity` refutation is a defect"*, and each now has a
counterexample at the same tier, in the same run. §4's confound is broken: template does
not determine whether a refutation is worth reading.

**And the corrected gate has its first measured false positive.** Every row in the arm is
`Likely` 70, so it says nothing about whether *tier* discriminates — but it does show that
at one high tier a refutation can be either kind. `PathSegment`'s commutativity refutation
would render as *Suspected defect* under §3, and it is not one. The tool's own
explainability already names this exact case (*"a `(T, T) -> T` need not commute —
subtraction, division, concatenation"*), which suggests the gate should consult the
conjecture warning it already emits rather than tier alone.

> **That suggestion was measured the same day and is REFUTED — see §11.** The conjecture
> caveat fires on **14 of 14** refutations on record, defects and false laws alike, because
> `commutativity`, `associativity` and `idempotence` are all absent from
> `Refutability.roleEntailedTemplates`. It has no discriminating power at all. The
> body-shape alternative fails for a sharper reason, and §11 argues the false positive is
> not fixable by a static gate.

**What the arm cannot do**, and §3 should not be re-tuned as though it could: planted
evidence has no base rate. These three types were chosen to occupy particular cells, so the
arm falsifies a categorical claim and cannot estimate precision. The nine natural
refutations remain the only base-rate evidence, and they are still 4/4 and 0/5.

Revised standing of the build order:

- **Step 1 (settle the confound) — DONE**, by the planted arm rather than by a corpus.
- **New step: re-examine §3's gate.** `.likely` alone admits a known false positive. The
  candidate refinement is to consult the conjecture signal, not to move the tier cut.
- The `<fix>^` backtest is no longer needed to settle the confound. It is still the only
  way to get a *rate*, and §9.1's reachability findings bound what it could ever measure.

## 11. The false positive is not fixable by a static signal (2026-08-08)

§10 closed by proposing that the gate consult the conjecture warning rather than tier
alone. Scored against every refutation on record, that fails outright, and the two obvious
alternatives fail with it. The negative result is the finding.

### 11.1 The conjecture signal has no discriminating power

`SuggestionRenderer.conjectureCaveat` fires when a law is refutable and **not**
role-entailed, and `Refutability.roleEntailedTemplates` is a ten-name set —
`predicate`, `comparator`, `partition`, `state-machine`, `filter-subset`,
`selection-subset`, `diff-disjointness`, `caseiterable-key-injectivity`,
`input-totality`, `normal-form`. `commutativity`, `associativity` and `idempotence` are
all absent, by design: a correct implementation genuinely can fail them.

| refutations on record | conjecture caveat fires |
|---|---|
| 5 real defects (4 merge folds + `BlendSummary`) | **5 of 5** |
| 9 false laws (5 domain-transfer + `PathSegment` + 3 fixture `idempotence`) | **9 of 9** |

**14 of 14.** As a gate it suppresses everything; as a signal it says nothing. It is a
correct warning aimed at a different question — *can a correct implementation fail this?* —
and every law this feature will ever classify answers yes. That is what makes them
classifiable in the first place.

### 11.2 The body-shape alternative fails for a sharper reason

The natural next idea is to read the body, as `EqualityBodyClassifier` does for `==`:
a binary operation that composes its two operands *positionally* is order-dependent by
construction, so do not call a commutativity failure a bug.

It does not separate them, and the pre-fix source says why. `Decisions.merge` at
`1355f69^`:

```swift
for record in records + other.records {
    if let existing = byHash[record.identityHash],
       existing.timestamp >= record.timestamp { continue }
```

`records + other.records` — a fixed positional composition of the two operands, and the
`>=` makes the first-visited win a tie. Structurally that is the same shape as
`PathSegment`'s `text + "/" + other.text`. **One is a real defect and the other is correct
code, and a body-shape reader cannot tell them apart** — worse, it would suppress the
defects, which is the recall failure `fixtures/domain-transfer-signal` already measured for
a different veto (recall 4/5, precision 4/12).

### 11.3 What actually separates them is intent, which is not in the shape

The one signal with any evidence is the **docstring**, and the evidence is thin. The
pre-fix `Decisions.merge` doc states a rule that is symmetric in its operands —
*"Identity-keyed; on collision the record with the later `timestamp` wins"* — which claims
an outcome depending only on timestamps, never on argument position. The body violated its
own stated contract; that is what made it a defect. `PathSegment.combine`'s doc describes a
positional operation and claims nothing.

That is **one real pair**, and it would miss `BlendSummary`, whose docstring is silent — and
whose docstring is silent because this scope's author wrote it that way, so it is an
artifact of the fixture rather than evidence about real code. `DocstringPropertyCorroborator`
already exists and is the natural home if anyone wants to measure it properly, over a
population rather than an anecdote.

**The general claim, and the reason to stop looking for a gate:** *"is commutativity a
property this function owes?"* is a question about intent. Two functions with the same
signature, the same tier, the same generated counterexample and the same body shape can
answer it differently. No static signal reads intent.

### 11.4 So the fix is the wording, not the gate

This is the idea doc's own open question 3 — *"the tool can't know which; the verdict should
present the fork, not assert the bug"* — promoted from a stylistic preference to a measured
constraint. §3's gate stays as the *visibility* rule (which refutations are worth a second
look) and stops being read as a *classification* (which refutations are bugs).

Concretely, for the build in §6:

- **Rename the verdict.** Not *Suspected defect*. Something that states the fork —
  *"expected to hold; it does not"* — so a reader meets `PathSegment` and `Decisions.merge`
  in the same bucket and is not told the wrong thing about either.
- **Render both readings, always**, with the counterexample: either the law does not apply
  here, or this is a bug. The tool has no basis for choosing and should not appear to.
- **Keep `.likely` as the cut**, since §10 gives no reason to move it and no measured
  alternative beats it.
- **Docstring corroboration is an escalation, not a gate**, and unmeasured. If it is built,
  score it over a population first — the standing practice from
  `fixtures/domain-transfer-signal`: score a candidate signal against the laws that HELD,
  not against the class it targets.


## 12. Built (2026-08-08)

§11.4's first two prescriptions shipped; §6 steps 2 and 3 are done.

`RefutedExpectation` (Core) decides **visibility** and never blame — `.likely` or better
via `Tier.atLeastAsProminentAs`, a counterexample present, coverage not partial.
`ProveThenShowRenderer` gained a fifth bucket, **EXPECTED TO HOLD, AND DOES NOT**, which
renders both readings and the sentence saying the tool cannot choose. Tiers are read
pre-verify from the index; with no tier, a refutation stays in DISPROVEN, because a missing
tier must never promote a row into a section headed *read these first*.

Measured on `fixtures/planted-defect-arm`, which is why the fixture exists:

```
  Proven 4 · Expected-to-hold 2 · Disproven 3 · Unverifiable 0 · Inconclusive 0

EXPECTED TO HOLD, AND DOES NOT — read these first
  ! BlendSummary  associativity  combine(_:)    ← a real defect
  ! PathSegment   commutativity  combine(_:)    ← a false law about correct code
```

Both at `Likely` 70, in one bucket, described identically. That is the design, not a
limitation of it.

**Still open**, and deliberately: the interaction fold (§7's deferral, now keyed to
`InteractionRefutedExpectation`), and docstring corroboration as an unmeasured escalation
— score it over a population first, per §11.3.

**The wording guard caught its own first draft.** It banned the substring `is a bug`, and
failed on the tool's correctly-hedged reading 2, which has to say the function may be
wrong or the fork has one prong. It now asserts the property instead: neither reading is
ever rendered without the other. Guarding a claim is not the same as guarding a
vocabulary.


## 13. The interaction fold, and the misreading that had deferred it (2026-08-08)

§7 deferred the interaction fold on the grounds that the trap-attribution census showed
*"a 0/10 defect rate on the interaction surface, the opposite of the algebraic one."*
**That is a misreading of the census and the deferral is withdrawn.**

`docs/measurements/interaction-trap-attribution-census.md` defines its two outcomes:

| stderr | attribution |
|---|---|
| carries the marker | `.invariantCheck` — **the property is genuinely refuted** |
| no marker, but a sequence was reached | `.subjectCode` — the subject's own trap |

So **10 of 10 `.invariantCheck`, 0 `.subjectCode`** means *no harness artifacts*, and its §4
says so directly: *"the `.measuredDefaultFails` verdicts these corpora produce are all
genuine."* Read correctly, the census **supports** surfacing interaction refutations. The
error was reading "subject-code" as "defect" when it means "artifact", and it propagated
from §7 into §12, into two source comments and into a test comment before anyone re-read
the source.

### What the census does leave open, and how the fold answers it

Its §4 *"does not"* is narrower than the deferral claimed: the corpora are reducer-only, and
whether an **MVVM/VIPER** carrier could produce a subject-code trap that the parser
conflates into a refutation is unmeasured. That risk needs no corpus to manage, because the
census's own machinery already answers it per run — `TrapOrigin` is on every
`measuredDefaultFails` result.

So the fold gains a fourth clause rather than waiting: **`attribution`**. An interaction
refutation reaches EXPECTED TO HOLD only when the trap is attributed to the invariant check.
A `.subjectTrap` is the subject falling over, not the property failing; `.unknown` stays out
too, following the census's rule that absence of the marker never convicts the subject —
which means it is not evidence of a property violation either. The algebraic surface passes
`.notApplicable`, because its outcome partition already does this work: a trap there is
`measuredError`, never `measuredDefaultFails`.

`RefutedExpectation.statesAFork` is now tier + counterexample + coverage + attribution, with
`Coverage` and `Attribution` as the two surface-specific soundness clauses and
`.notApplicable` the honest answer on the surface that does not need them.
