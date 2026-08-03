# Open threads

Things decided, noticed, or left undone that have **no other home**. Deliberately terse — an
index, not an essay. Anything with a real home lives there instead; this file exists so a
conversation's residue does not evaporate.

> **As of 2026-08-03** · `SwiftInferProperties@67f9ecf`. Entries here are *not* dated claims
> about code — they are open questions and standing reads. Close them by deleting the row and
> putting the answer where it belongs.

<!-- doc-provenance date=2026-08-03 subject=SwiftInferProperties@67f9ecfb3724f4336198eaf5c59ff02de46ef5db observer=SwiftInferProperties@67f9ecfb3724f4336198eaf5c59ff02de46ef5db -->

---

## Open items

| # | item | where it stands |
|---|---|---|
| 1 | **[SwiftEffectInference#1](https://github.com/Joseph-Cursio/SwiftEffectInference/issues/1)** — `~2×` regression on the whole-domain purity path | filed with an A/B; blocks the pin bump. Fix: stop `inferredEffect(for:)` delegating to `verdict(for:)` |
| 2 | **Then**: bump the SEI pin, run `make perf` *before* `make test` (perf is step 3 of 9, fail-fast hides the rest), add a pin-equality guard, then adopt `verdict(for:)` | ordered; each step gated on the one before |
| 3 | **Is SwiftProjectLint silently paying item 1?** It is already on `097181aa` and calls `PurityInferrer` from two visitors over every function *and closure* in a project | unmeasured. Cheap: point the same A/B at its own suite |
| 4 | **The attribute-grammar join has no contract test.** SwiftIdempotency ships the macro names; `AttributeRecognition.default` hard-codes them; nothing asserts they still match | a rename fails as a *missing* annotation, indistinguishable from an unannotated codebase |
| 5 | **`PBTSeed.role`'s doc comment is stale** — says two rules classify roles; `ExtractablePureKernelVisitor:106` makes it three | one-line fix in SwiftProjectLint |
| 6 | **`.swiftinfer/` is not gitignored** — generated index/evidence JSON sits untracked in every `git status` | decide: ignore it, or commit the index deliberately |
| 7 | **No current end-to-end number** for the loop | see *Standing observations* → *The measurements are all withdrawn* |
| 8 | **Exit criteria for "the toolchain is in shape"** are unwritten | see *Decisions* → *Road tests were misfiled* |
| 9 | **Driver stages 3–4** (`verify`, kit conformance suites) are declared and unimplemented | `scripts/toolchain.sh`. Until they exist, **no run of the loop executes a law** — the driver says so every run rather than implying otherwise |
| 10 | **The two ends of the lint→infer hop take different inputs.** The linter takes a repo path and works out the layout; `discover` requires exactly one of `--target`/`--sources` and errors without one | a reader following the documented hop hits an argument error on their first attempt. The driver papers over it by inferring scope — open question whether the *fix* belongs in `discover` instead |
| 11 | **Driver stage 0 builds another repository** (`swift build --product CLI` in SwiftProjectLint) | convenient, and it mutates a sibling's `.build`. Arguably it should only *locate* and fail telling you to build |

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
2. **The loop's entry point cannot be invoked.** SwiftProjectLint ships no installed binary and is
   not on `PATH`; stage 0 has to compile it. That is not an inconvenience in the driver, it is the
   first thing standing between a reader and the loop.

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
