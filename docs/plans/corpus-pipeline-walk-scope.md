# Corpus pipeline walk — scope

> **Status:** `open` · **As of:** 2026-09-11
> **First subject:** SwiftMarkdownWiki

The linter sweep is done — 33 runs, 26 repositories, ~5,300 files, a census of
4,686 named pure functions and 875 unnamed pure closures
([run 33](https://claude.ai/code/artifact/071317fc-a604-49ec-b825-c73400c15346)).
That was step one of the toolchain. This document scopes step two and three:
handing those candidates to `swift-infer` and the law kit, one repository and one
function at a time, and recording **where a property test we expected did not
arrive**.

## The one question

> For a function we predicted a refutable law for, did the pipeline produce that
> law — and if not, at which stage did it die?

Everything else on the ledger is instrumentation for that row.

## What this is not

It is not the MacCloud road test. That asks *can the loop find planted bugs?*
against a frozen fixture with a frozen answer key
(Appendix C, "How this toolchain was road-tested"). This asks the complement, the
question `roadtest-swiftlintrulestudio.md` opened in 2026-07:
**why did the pipeline recommend so little, and whose fault is each silence?**
Finding a bug here is a bonus, not the measure.

Two subjects are therefore excluded on principle:

- **MacCloud_client_iOS** — the frozen fixture. Pointing the finished loop at it
  spends the benchmark. Do not add it to this walk.
- **SwiftInferProperties** — largest census in the corpus (2,033) and it is the
  tool under test. A tool that grades its own homework always improves.

## Subject order

From the run-33 per-repo table, prompts / closures / census / blocked:

| # | Repository | prompts | closures | census | why |
|---|---|---|---|---|---|
| 1 | SwiftMarkdownWiki | 9 | 17 | 83 | Small enough to finish. Never through the pipeline. **No property tests at all** (grep for `propertyCheck` / `PropertyLawKit` / `forAll`: zero hits across 184 source and 61 test files). Catalog-shaped subjects in `Linking`, `Search`, `Graph`, `Vault`. |
| 2 | SwiftUMLStudio | 12 | 43 | 237 | Untouched, richer, model → PlantUML is a textbook round-trip. |
| 3 | SwiftCloneDetector | 0 | 30 | 42 | The inverse case: **zero refactor prompts**, so any silence is a pure discover-stage finding with no refactor confound. |
| — | SwiftLintRuleStudio | 32 | 232 | 5 | Deferred. Already road-tested 2026-07-22 and three fixes shipped against it; the tool has been tuned on this subject. Worth a re-measure later, worthless as a first honest run. |

## The queue, and why it is not the ETK prompts

The sweep produces two populations and they are different experiments.

**Queue A — named pure functions (this walk).** Testable *today*. No refactor
stands between the code and a law, so a silence is attributable to a tool.

**Queue B — the 19 `Extractable Total Kernel` prompts (later).** The kernel is
not extracted yet, so "no property test" is the expected answer until someone
refactors. Every row would be confounded by our own unfinished work. Worse,
SwiftProjectLint #205 records that the ETK path arm names the wrong law at seven
of the eight sites carrying it — so the prompt's own claim is not yet a reliable
prediction to measure against.

**Within Queue A, comparators and reducers first — ~~and this did not survive
first contact~~.** Run 33's shape table is blunt that a predicate's obligation is
totality and a transform's is being a function of its input, those being 806 of
887 — "nearly always true and rarely interesting" — while the comparators (57)
and reducers (5) are where a generic law exists and **can fail**.

**Corrected 2026-09-11, on the first subject.** That shape table describes the
*closure* bucket, and a closure has no name. All four comparator seeds in
SwiftMarkdownWiki are `kind: extractable-kernel`, and the manifest addresses each
one by its **enclosing function** — `buildNodes`, `sources`, `enumerateNotes`,
`sortNotes`. Focusing `swift-infer` on `buildNodes` focuses it on a function that
is not a comparator. So the comparators are Queue B (they need an extraction
first) and the walk runs over **named** pure functions, comparators included only
once they have names. The census is 4,686 named functions; the comparator count
is a property of the 875 anonymous ones.

## Four commitments

Each exists because it was tempting to break it, and three are unfixable after
the fact.

**1. The prediction is written before the run.** For each subject function, read
the code and write down, by hand: the law(s) we hope for, and for each, *is it
refutable* — does some type-correct, plausible wrong implementation fail it?
Only then invoke the tool. Without this column the question "did it fail to
produce a test we hoped for?" gets answered by reading what came back, which is
the answer-key-editing failure Appendix C caught this exercise committing, and
the sweep artifact caught itself committing twice more (Concrete Type Usage
reported zero; "laws in CI" reported zero).

**2. Refutability is the score, not suggestion count.** `f(x) == f(x)` is the
documented fallback — `swift-infer discover --seeds` help says so outright: *"a
seeded pure function that no template matched still earns the generic determinism
law"*. A row whose only yield is that law is a **miss**. So is a law that runs,
passes, and could not have failed (see S7).

**3. Every miss is attributed to a stage.** Otherwise the ledger cannot be acted
on, because the five tools have five different owners.

**4. The instrument is pinned per run.** Record the commit SHA of all five tools
in every ledger entry. Run 33 found *Circular Dependency* giving three different
answers over one unchanged repository across five runs of one binary, and two
sweeps had to have phantom movement ruled out by hand. Assume the instrument
moves unless a SHA says it did not.

## Stage taxonomy

Where a hoped-for property test can die, and who owns each.

| Stage | Where it died | Owner | Signature |
|---|---|---|---|
| **S0** | Linter never surfaced the kernel | SwiftProjectLint | absent from the census and from `--format pbt-seeds` |
| **S1** | Seed emitted, hand-off dropped it | shared vocabulary | in the manifest, absent from the focused run (the 316-of-468 shape) |
| **S2** | Purity veto | SwiftEffectInference | refused as impure; check whether the refusal is correct |
| **S3** | Catalog gap — no template names the shape | swift-infer | scanned, scored, no template matched |
| **S4** | Matched, but only tautologies survive | swift-infer | output is `f(x) == f(x)`, or the focus filter discarded the refutable law |
| **S5** | Generator derivation fails → `.todo` | SwiftPropertyLaws | emitted stub calls `Type.gen()` that does not exist |
| **S6** | Emitted but will not compile | SwiftPropertyLaws | missing import, access level, `Sendable` |
| **S7** | Compiles, runs, passes — and could not have failed | both | conditional law whose antecedent never fires; vacuous pass with no diagnostic |
| **S8** | `verify` returns Unverifiable / Inconclusive | swift-infer | candidate executed, verdict is neither Proven nor Disproven |

S7 is the stage to watch. The 2026-09-08 measurement in SwiftPropertyLaws found
two shipped laws — `Equatable.transitivity` and `Hashable.equalityConsistency` —
whose refuting configuration disappears at a realistic domain width: caught 20/20
from `0...3` and **0/20 from `0...200`** against a genuinely non-transitive `==`.
A green run here is not evidence of anything until the antecedent is shown to
have fired.

## Per-issue protocol

One function at a time. Steps 1–2 happen before any tool is invoked.

1. **Read the function.** Record file:line, signature, and what it is supposed to
   do (docstring if there is one — the docstring-advice path is on by default and
   surfaced 8 of 10 hand-keyed kernels on the SwiftProjectLint road test where
   templates surfaced 2).
2. **Predict.** Write the hoped-for law(s), and for each, name one plausible
   wrong implementation it would reject. A law with no such implementation is
   recorded as *not refutable* and the row is dropped from scoring — before we
   know what the tool says.
3. **Seeds.** `SwiftProjectLint/.build/debug/CLI <subject> --format pbt-seeds > .pbt/seeds.json`
   Confirm the function is in the manifest. If not → **S0**.
4. **Discover, unseeded then seeded.** Both, because the difference *is* the S1/S4
   measurement:
   - `swift-infer discover --sources SwiftMarkdownWiki --include-possible`
   - `swift-infer discover --sources SwiftMarkdownWiki --seeds .pbt/seeds.json`
   (`--sources`, not `--target`: the subject is an Xcode app whose SwiftPM target
   path is not `Sources/`.) A law present unseeded and absent seeded is **S1/S4**
   and is the single most valuable row on this ledger.
5. **Classify the yield** against step 2: hit / tautology-only / silence.
6. **Emit and compile.** Accept the suggestion, build the stub. Failure → **S5**
   or **S6**.
7. **Run it, then try to break it.** A passing law is not a result until a
   deliberately wrong implementation has been shown to fail it. If it passes
   against the planted violator → **S7**.
8. **Write the row.** Then move to the next function.

## Ledger

One file per subject, named `roadtest-` plus the repository, alongside the 69
existing measurement docs. Columns:

`function` · `predicted law` · `refutable?` · `in seeds?` · `unseeded yield` ·
`seeded yield` · `compiled?` · `ran?` · `killed a violator?` · `stage` · `note`

Defects found in SwiftProjectLint, SwiftEffectInference or SwiftPropertyLaws are
filed as issues **in their own repositories** and referenced from the row by
stage. This document and the ledgers stay in SwiftInferProperties because that is
where the majority of stages land, not because it owns them all.

## Stop rules

- **A subject is done** when every comparator and reducer in its census has a row,
  and when the predicates and transforms have been sampled rather than exhausted
  (they are 806 of 887 and their laws are nearly always trivially true).
- **A stage is worth a fix** when it has three rows across two subjects. One row
  is an anecdote; the sweep has already recorded four separate cases of a
  single-site reading producing a wrong general claim.
- **The walk stops being honest** the moment a predicted law is edited after
  seeing the tool's output. If that happens, mark the row `unscored` and
  adjudicate it by refutability alone — the rule the road test used for the
  locale-dependent search predicate the hand-written answer key had missed.

## Open

- Whether to run `verify` (S8) on the first subject at all, or defer it until the
  discover stage is characterised. Leaning defer: S3/S4 are expected to dominate,
  and a verify pass on a candidate that was never proposed measures nothing.
- Whether `--require-corroboration` belongs in the standard invocation. It is a
  prototype and it took Q3 recall 9/12 → 0/12; default is off and it should stay
  off for this walk.
