# Mutation sweep, slice 1 — measure the noise before building the layer

> **Status:** `shipped` · **As of:** 2026-08-08

Scopes the first slice of `docs/ideas/Mutation operator layer over the corpus harness.md`.

> **RUN 2026-08-08 — `docs/measurements/mutation-sweep-slice1-findings.md`.** 26 killed,
> **1 survived**, 3 did not compile. §9 fired: one survivor is not a rate, so the question
> this slice exists to answer is **unmeasured**, and the §6 GO bar is arithmetically
> satisfiable only by treating a sample of one as evidence. The survivor was a real gap and
> is fixed. Read §7 of the findings before designing slice 2.

**Slice 1 does not build the layer. It answers the one question that decides whether the
layer is worth building**: on a mechanically-mutated real target, what fraction of
survivors are *actionable*, and what fraction are noise?

## 1. Why that question first

The idea doc's sharpest paragraph is the one that argues against itself. Reusing
SwiftIdempotency's `mutants/` runner does **not** inherit the curated corpus's two best
properties, because both live in the hand-authoring rather than the plumbing:

> Each mutant is authored to break a *specific guarantee* … Mechanical operators mutate
> wherever the grammar allows, and **most such sites are semantically inert**.

An equivalent mutant changes source without changing behaviour, so nothing can ever kill
it: it survives forever as a false alarm. Curation cannot *contain* one, because
`expected: killed` is itself the equivalence filter. A mechanical sweep has no such gate.

So the layer's cost is not the runner — that part is reusable and understood. The cost is
**triage per survivor**, and the deciding number is how many survivors there are per real
finding. If nine in ten are equivalent, the tool produces a queue nobody works.

That number is unmeasured, and it is measurable for the cost of one afternoon. Measuring it
is slice 1.

## 2. What changed today that makes this affordable

Three of the idea's stated costs moved on 2026-08-08:

- **Per-mutant build.** Its cost note budgets "one `swift build` per mutant … for a corpus
  of *dozens* it is fine". `SharedVerifierPackage` since measured **8.4× faster / 15× less
  disk** on `fixtures/cycle27-surface` (#130), so the budget is looser than when written.
- **Comparison runs.** The determinism note wants a seeded sweep then an unseeded re-run
  over survivors — repeated runs compared against a baseline. `--no-persist-evidence`
  (#129) now makes a comparison run non-destructive; before it, each run silently rewrote
  the file it was being compared against, which produced a false "0 drift" twice.
- **A worked precedent.** `fixtures/planted-defect-arm/` is this methodology at n=1: plant
  a known-wrong implementation, run the loop, read the verdict. It also carries the two
  traps found by getting it wrong — a fixture must not document its own defect in a
  docstring (`DocstringPropertyCorroborator` reads it), and the method name is load-bearing.

## 3. Frozen prediction

**Nothing below this line is edited in response to the results.** Recorded before the first
mutant is generated, per the same discipline as `roadtest-self-dogfood` §1.

1. **Equivalent mutants dominate the survivor set** — I predict **> 50%** of survivors are
   semantically inert, and that this, not build time, is what makes an unscoped sweep
   unusable.
2. **`gen-unreachable` is the second-largest bucket, not a rarity.** This session measured
   three reachability walls in this tool's own generators — collection carriers drawn at
   `0...8` elements, collision-dependent failures invisible to a realistic domain, and
   edge-only failures routed to the advisory pass. A boundary-shifting mutant landing behind
   any of those survives while being perfectly killable in principle.
3. **Real gaps are a minority of survivors but non-zero** — I predict **at least one** in a
   30-mutant sweep, or the exercise says something worse about the operators than about the
   suite.
4. **The killed rate is high** — I predict **> 60% killed**, because the subject is a
   heavily-tested module. A low kill rate would mean the sweep is mutating code the scoped
   suite does not exercise, which is a scoping error, not a finding.

## 4. Design

**Subject.** One module, not the package: `SwiftInferCore`. It is the most heavily tested
target, which makes a survivor interesting rather than expected, and it is where the
property tests live.

**Operators.** Four, grammar-level, deliberately boring:

| operator | example |
|---|---|
| relational swap | `<` → `<=`, `>` → `>=` |
| boundary shift | `n` → `n + 1` in a comparison |
| boolean negation | `if x` → `if !x` |
| arithmetic swap | `+` → `-` |

Domain operators (the idea doc's open question 3) are **out of slice 1**. A boring operator
set is the right first probe precisely because it maximises the equivalent-mutant rate — if
the noise is tolerable here it is tolerable anywhere, and if it is not, that is the finding.

**Size.** 30 mutants, sampled with a fixed seed across eligible sites so the selection is
reproducible and not cherry-picked — the same discipline `scripts/swiftorg_sample.py`
applies to its corpus.

**Procedure**, reusing the curated runner's mechanics verbatim (apply / build / run /
revert, one at a time, clean tree):

1. `git apply` the patch.
2. `swift build --build-tests`.
3. Run the **scoped** suite — `make test-fast`, ~28s — under a pinned seed.
4. Classify `killed` / `survived` / `error`.
5. `git checkout -- .`

**Determinism.** Pinned seed for the sweep, then an unseeded high-trial re-run **over the
survivor set only**, because a frozen draw lets a mutant that only a different draw would
catch survive spuriously. Survivors are few, so the second pass is cheap.

## 5. Triage, and the hazard that governs it

Every survivor is adjudicated by hand into exactly one of four buckets. **Misrouting is the
hazard the idea doc names**, and it is asymmetric:

| bucket | remedy | cost of getting it wrong |
|---|---|---|
| **real gap** | write a killer, graduate to the curated manifest | low |
| **gen-unreachable** | fix the generator's *distribution*, re-run | **high** — writing another killer is pointless; the killer was never the missing piece |
| **equivalent** | fingerprint into an ignore-list | **highest** — permanently ignores a reachable bug the generator merely masks |
| **out-of-scope** | drop | low |

**The decision rule, so the two dangerous buckets are not decided by intuition:** a survivor
may be filed `equivalent` only if a reader can state *why no input distinguishes the
mutant*. If the answer is "the tests happen not to reach it", it is `gen-unreachable`, not
equivalent. The burden of proof sits on the bucket whose error is permanent.

## 6. Go / no-go

Slice 1 reports a table and a recommendation, not a tool.

- **Go** if actionable survivors (real gap + gen-unreachable) are **≥ 25%** of survivors.
  Triage is then affordable and the layer earns its keep.
- **No-go, and say so** if equivalents exceed **75%**. That is the outcome the idea doc's
  own argument predicts, and publishing it is worth as much as a green result — it is the
  measured reason not to build a tool that would otherwise look obviously good.
- **Inconclusive** if the killed rate is below 60%: the sweep mutated code the scoped suite
  does not exercise, which is a scoping error. Re-scope and re-run rather than reporting a
  number.

## 7. What slice 1 deliberately does not do

- **No automatic attribution** of a survivor to the generator versus the law.
  `docs/plans/existing-property-test-audit-scope.md` names that as the unsolved part, and
  `fixtures/leaderboard-sort`'s mutant × law matrix exists because the two are confusable.
  Slice 1 adjudicates by hand and *records how hard each call was*, which is the input a
  future automation would need.
- **No ignore-list, no manifest schema, no site fingerprinting.** Those are the idea doc's
  open questions 1–2 and they are a producer/consumer contract worth freezing only once the
  noise rate says there is a consumer.
- **No new package.** The idea doc is explicit that the tool, if it graduates, is
  cross-cutting and would not live here. Slice 1 is a `scripts/` experiment and a findings
  doc, matching `scripts/swiftorg_sample.py`'s precedent — `scripts/` is study tooling that
  no shipped target imports.
- **No change to `run-mutants.sh`.** It stays the CI regression gate; discovery is a sibling
  runner. That separation is rows 1–2 of the idea's delta table.

## 8. Cost

~30 mutants × (incremental build + 28s scoped suite) ≈ **30–45 minutes of machine time**,
plus hand triage of the survivors, which is the part being measured and so cannot be
estimated in advance without prejudging the answer.

## 9. What would make this wrong

The prediction in §3 is falsifiable in both directions, and the failure mode to watch is a
**high kill rate with zero survivors** — that reads as "the suite is excellent" and is more
likely to mean the operator set is too timid or the sampled sites are trivial. If that
happens, the honest report is that slice 1 measured nothing, not that the suite is perfect.
