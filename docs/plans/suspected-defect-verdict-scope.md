# Suspected-defect verdict — scope, with the proposed gate measured and refuted

> **Status:** `open` · **As of:** 2026-08-07


**Status: scoped, not built. 2026-08-07.** Scopes
`docs/ideas/Refuted-high-confidence-guess as candidate bug.md`, which is unchanged and
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

1. **Settle the confound (§4).** Re-run `verify --all-from-index` over a second corpus
   with an unrelated template mix and check whether the tier/template readings come apart.
   One run, no code. If they do not come apart, this ships as a template rule and the
   framing changes.
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
  deferred (falsifier: `InteractionSuspectedDefectClassifier`) until that census is
  re-run over an MVVM/VIPER corpus.

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
