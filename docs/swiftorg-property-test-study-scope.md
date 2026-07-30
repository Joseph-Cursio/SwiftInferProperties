# Scope: a systematic study of swift.org's property-style tests

**Status: planned, not started.** Five questions, ordered by dependency in §7, run in **two
passes** (§6): a sampled calibration pass, then a census on whichever populations the first
pass shows are worth one. Read §2 first — a substantial amount is already measured, and the
study must not re-derive it.

The corpus is Apache-2.0. Any fixture vendored into this repo carries its attribution and
its upstream path; nothing is copied without both.

## 1. Why this corpus, and why systematically

Every road test so far has been opportunistic: point the tools somewhere, record what
happens. That found real defects — two in a single day on `swift-foundation`, and one
*upstream* (`swiftlang/swift#91083`, a sortedness check that could not fail, approved by a
stdlib maintainer). But opportunistic sampling cannot answer *coverage* questions, and the
four most valuable questions here are coverage questions.

It is also the only corpus where the **law is already written down by someone who knew the
code**. That makes it the one place we can separate two things this project otherwise has
to conflate: whether a property *holds*, and whether our tool can *find* it.

## 2. What is already measured — do not redo this

| finding | where |
|---|---|
| `roundtrip` appears 723× in `swift`, 329× in `swift-foundation`; TestLifter lifts 51 suggestions from the latter's test bodies | `parsing-catalog-gap.md` §"Road test — the swift.org suites" |
| **12-vs-1 split**: source inference fires 12 templates / 262 suggestions on FoundationEssentials; lifting the *test bodies* of the same repos fires **1** | same, §"Road test — the corpus as a measuring instrument" |
| ~59% of ~4,285 equality assertions compare against a **literal** | same |
| Generators are the weak half: `.random(in: 0 ..< T.max)` 8× (excludes `.max`); the `sort_integers` LCG reaches **256** distinct values, all odd, never negative; `.nan` 50× / `.infinity` 28× but **40** test functions name an edge value with *no* randomness against **4** that do both | same, §"The generators are the weak half" |
| `TestSuiteParser` recognises **zero** of it: `validation-test/stdlib` has 3,440 `TestSuite.test("…") { }` closures, 6,033 `expectEqual`-family calls, **0** `XCTestCase`, **0** `@Test` | measured 2026-07-29, this session |
| `StdlibUnittest` ships an axiom battery — `checkEquatable` asserts reflexivity/symmetry/transitivity, `checkComparable` antisymmetry/transitivity — at **263** call sites, 164 of them in `validation-test/stdlib` | same |
| Those batteries quantify over **hand-picked instance lists**: median 2.5 elements, 22 of 28 resolved sites ≤ 4 | same |
| `lit` + FileCheck tests have no assertion function to anchor on, and quantify *exhaustively* (`permute(7, verifier)`) — stronger than random, not weaker | `parsing-catalog-gap.md` §"A third form remains out of reach" |

**One conclusion in §2 is now suspect and Q2 should retest it.** The survey concluded the
corpus is "a ceiling on human property vocabulary — nobody hand-rolls conservation or
referential-integrity, so a catalog pruned to observed demand would be pruned to
round-trip." That was measured over `swift-foundation`'s and `swift-syntax`'s test
directories, which do not use `StdlibUnittest`. `validation-test/stdlib` is 263 sites of
hand-rolled *algebraic* law checking. The generalisation may not survive.

## 3. Pinned inputs

| repo | local path | SHA to pin |
|---|---|---|
| `swift` | `~/GitHub_projects/swift` | **must be re-pinned** — the working copy is on a local PR branch (`3db7bd6e154`), not upstream `main` |
| `swift-foundation` | `~/GitHub_projects/swift-foundation` | `96d4094` (2026-07-16) |
| `swift-syntax` | `~/GitHub_projects/swift-syntax` | `1b5cd99f` (2026-07-17) |

Record the SHA with every number. A count without one is not a measurement.

## 4. The five questions

### Q1 — How many property-style tests are there?

**The hard part is the definition, not the counting**, and the study should say so before
producing any total. Candidate populations, with rough sizes at the SHAs above:

| population | size | shape |
|---|---:|---|
| `StdlibUnittest` `check*` axiom batteries | **263** | named law suites over an instance list |
| repetition loops (`for _ in 0..<N`) | **694** | hand-rolled quantifier |
| `roundtrip`-named tests / helpers | **827** mentions | the one property shape everyone recognises |
| `lit` + FileCheck exhaustive verifiers | 9 files | print-on-failure, `CHECK-NOT` |
| differential / oracle harnesses | unknown | `fast` vs `reference` |

These overlap, and none of them *is* the answer. A `for _ in 0..<10` loop over three
literals is not a property test; `checkEquatable` over a 2-element list arguably is one with
a broken generator.

**Method.** Hand-adjudicate a stratified sample (30 per population), define
"property-style" from what the sample shows, *then* automate the count against that
definition and report the automated total **with its sample-measured error rate**.

**Prior art against doing it the other way round:** a structural classifier written for the
earlier survey "proved unreliable — it read `result == Decimal(12340)` as a round-trip", and
only its literal/non-literal split was quotable. Automate second.

**A rough estimate is fine, deliberately.** Nothing downstream needs a precise total — it
sizes pass 2 and weights Q5's idiom table, and both tolerate ±20% comfortably. What must be
precise is the **definition** and the classifier's **error rate**, because those propagate:
a reconciliation rate computed over a population you cannot define is not a number.

So: order-of-magnitude on "how many", tight on "of what".

**Deliverable.** A definition, a rough count with a sample-measured error rate, and a
per-population breakdown.

### Q2 — Does each reconcile to a template we have?

The valuable question, and it runs in **both** directions.

- *Our recall.* For each adjudicated property-style test, which template would state its
  law? Ones with no template are catalog gaps with a **witness** — which the survey's own
  rule prefers over reasoned holes ("prefer a hole with an observed witness over one with a
  compelling argument").
- *Their precision.* A test whose law we would refuse is either our gap or **their bug**.
  That is not hypothetical: `sort_integers.swift`'s sortedness check could not fail, and the
  fix is an approved upstream PR. Expect more, and record them separately — an upstream
  defect is a finding about the corpus, not about the catalog.

**And it is an independent precision check on us.** The `check*` batteries map onto
`equivalence-relation` and `comparator` — and `comparator` was just measured **11 of 22
false** on this repo, with 3 of those already shipping at `Likely`. A corpus where the
intended law is written down is the only place we can measure that honestly.

**Guardrail — a tool may not grade its own homework.** Extract the answer key mechanically
from the `check*` call sites and *freeze it with a SHA before running `discover`*. Anything
the tools find that the key missed is recorded **unscored**.

**Deliverable.** A reconciliation table; a gaps-with-witness list; an upstream-defects list.

### Q3 — Can we tell from the source alone, without the test?

Scientifically the most valuable question, because it is the project's thesis stated as an
experiment. It needs a **blinding protocol** or it is worthless.

**Method.** For each key entry `(type, law)` from Q2:

1. Run `discover` over the **sources only**, with `--test-dir` pointed at an empty
   directory. (This session used exactly that setup; it works.)
2. Freeze the output.
3. *Then* compare against the frozen key.

**Leakage to control for, and each is a real channel:**

- **Docstrings.** `DocstringPropertyCorroborator` reads prose. If a source docstring says
  "idempotent", the source did tell us — that is legitimate inference, but it must be
  *attributed* separately from shape/name inference, or Q3's answer is inflated by the very
  thing Q3 is asking about. Report three buckets: shape-only, name-only, docstring-assisted.
- **Curated vocabulary.** A law found because `encode`/`decode` is in `curatedInversePairs`
  is found by *our* prior knowledge, not by the source. Also its own bucket.
- **Protocol conformance.** `checkEquatable` fires on `Equatable` types, and conformance is
  in the source. A law that is *role-entailed by conformance* is a trivially available
  answer and must not be counted as inference. (Measured separately already: conformance
  does not predict refutability — see `fixtures/equatable-signal/README.md`.)

**Deliverable.** A recall figure with those buckets separated, and the residual — the laws a
human wrote down that no channel of ours reaches. That residual is the real gap list.

#### Q3a — "low recall" has two causes, and conflating them wastes the study

The expectation going in is that recall is **low, because the catalog is deliberately
conservative** (PRD §3.5, high precision / low recall). That is probably right, and it is
also the least useful form the answer could take, because two very different things produce
it:

| cause | what it means | remedy |
|---|---|---|
| **(a) suppressed** — a template matched and a threshold, counter-signal, or veto held it back | we *can* state the law and chose not to | calibration: a weight, a tier, a carve-out |
| **(b) unreached** — no template names that shape at all | we cannot state the law | catalog: a new template, or new discovery |

**Count them separately or the number means nothing.** "Recall is 20%" is actionable only
once split — if the missing 80% is mostly (a), the catalog is fine and the thresholds are
mistuned; if mostly (b), no amount of tuning helps.

**And (a) is currently hard to measure, which is itself a finding.** A suppressed candidate
does not appear in `discover` output at all — measured this session on `comparator`, where
suppressing 11 shape-only claims left those functions with *no* row rather than a low-scored
one. So counting (a) needs laws to stay in the record, which is exactly what
`access-level-analysis-gate-scope.md` §2 argues for on independent grounds
(*"`metrics` can answer 'how many laws is access level hiding?' — that question is
unanswerable today"*). Two studies wanting the same capability is an argument for building
it before either.

#### Q3b — pre-register the prediction, and split it by population

Write the expected number down *before* running, with a SHA, the way Q2 freezes its key.
An unfalsifiable "I expect it to be low" cannot be wrong; a band per population can.

The prediction worth registering is **not uniform**, and the non-uniformity is the point:

- **`check*` batteries → recall should be HIGH, and trivially so.** Those laws are
  role-entailed by protocol conformance — `Equatable` obliges reflexivity, symmetry,
  transitivity — and we ship `equivalence-relation` plus `ProtocolCoverageMap`. A high number
  here is *not* evidence for the thesis, which is precisely why Q3 buckets conformance
  separately. Already measured adjacent to this: conformance does not predict refutability
  (`fixtures/equatable-signal/README.md`).
- **hand-rolled repetition loops → recall should be LOW, and meaningfully so.** No
  conformance to lean on, no curated name necessarily present. This is where the interesting
  residual lives, and where a low number is a real result.

A single blended figure would average these two into something uninterpretable.

#### Q3c — before concluding "too conservative", check for a wrong discriminator

"Too conservative" implies the fix is to relax — lower a threshold, widen a gate. The
catalog forbids that as a reflex: *"Avoid the Daikon trap. Too many suggestions → raise
thresholds, don't pile on filters"*, and its converse deserves the same suspicion.

This session produced the counter-example, on this same corpus. `comparator` was missing true
laws **and** emitting false ones — 11 of 22 false, three already shipping at `Likely`. The
problem was not threshold height; it was gating on **shape** where the discriminating
evidence was the **name**. Relaxing the threshold would have made both numbers worse.

So the test to apply to Q3's misses, before any tuning:

> Do the misses share a *discriminator* — some evidence channel present in the true cases and
> absent in the false ones — or are they scattered across the score range?

Scattered means conservatism. Clustered means we are reading the wrong signal, and the fix
raises precision and recall together. Check clustering first; it is the cheaper answer and
the better one.

### Q4 — Transform each property-style test into an actual property test

The product half. **Blocked today**, and the blocker is the most concrete deliverable in the
whole study.

`TestSuiteParser` recognises `XCTestCase` `test*` methods and `@Test` functions. The corpus
has neither — 3,440 `TestSuite.test("…") { }` *closures*, and the assertion table holds 10
XCTest names plus `#expect`, so `expectEqual` (6,033 calls) and every `check*` battery are
invisible. Zero lifted, measured.

**So Q4 has a prerequisite**: teach `TestSuiteParser` the `TestSuite.test("…") { }` closure
form and `AssertionAnchor` the `expect*` family. Both are additive. Do that before
attempting any transformation, or the work is manual and unrepeatable.

**Then the transformation is close to pure gain, and §2 says why**: the human supplied the
law — the judgment part — and the generator is the mechanical part that is measured weak.
Keep the law verbatim, replace the generator, and pick up shrinking and seed reproducibility
for free. Today a `UUIDTests` failure at iteration 7,432 hands you nothing.

**One correction to that optimism.** For the `check*` batteries there is no generator to
replace: 22 of 28 sites pass 2–4 hand-picked instances. Conversion there means *inventing* a
generator, which is strictly more work and strictly more valuable — those axioms are
currently checked over a domain small enough to be exhaustive and too small to be
interesting.

**Deliverable.** The two parser extensions; then N converted suites, each with a
before/after on what the generator now covers.

### Q5 — Do the property-style tests use weak generators?

Partly answered (§2) and worth completing, because it is where the toolchain's division of
labour is clearest.

**Method.** Enumerate every generator idiom in the adjudicated set and classify:

- `.random(in:)` ranges — **half-open excluding the maximum** is already measured at 8
  occurrences, and it is a *lintable* idiom, not carelessness: someone reaching for "the
  whole range" writes `0 ..< UInt16.max` and gets everything except the value most likely to
  break the code.
- hand-rolled PRNGs — the `sort_integers` LCG's blindness profile (256 reachable values, all
  odd, 19% unique at size 1900) is the template for this analysis.
- **instance lists** — the `check*` battery case: exhaustive over a domain of 2–4.
- collision rate, which cuts both ways. 19% unique is *accidentally correct* tuning for
  tie-break and stability laws and wrong for range coverage. The repo's own lesson:
  `Decisions.merge` commutativity is false and verify reported `bothPass` at 100 trials
  until the alphabet was narrowed.

**Deliverable.** A frequency-ranked table of edge values the corpus *names by hand but never
draws* — that ranking is the empirical priority list for what our derived generators must
weight in, which is a spec we currently do not have.

## 5. Method guardrails

- **Pin every SHA.** See §3, including re-pinning `swift` off the local PR branch.
- **Hand-adjudicate before automating** (Q1's prior art).
- **Freeze the key before running the tool** (Q2).
- **Blind Q3, and attribute the channel** — docstring / vocabulary / conformance / shape.
- **`SIGBUS` on deep third-party source.** A swift-syntax parse over `SwiftParserTest` dies
  with a stack-guard hit *inside swift-testing* (cooperative-pool threads, ~512 KB) and
  succeeds through the CLI (main thread, 8 MB). It kills the whole test process, so it reads
  as unrelated infrastructure failure. Drive corpus scans **out-of-process through the CLI**,
  or on a `Thread` with an explicit `stackSize`.
- **Run the shipping binary before reporting a crash.** The above was first reported as the
  tool crashing on the most important corpus available. One command settled it.
- **Do not run corpus scans alongside `make test` or `make perf`** — that is how the §13
  budget flakes happen.
- **Score refutability, not count.** A law no plausible implementation would fail is not a
  finding, on either side of the reconciliation.

## 6. Two passes, with different stopping rules

**A sample gives you a rate, not a population — and the output that changes what we build is
a gap list, where the tail is the valuable part.** The rare shape nobody thought of is
exactly what sampling truncates. So sampling is a *calibration* pass, not the study.

This mirrors a rule the repo already applies to unknown-size discovery: *"keep going until K
consecutive rounds return nothing new — simple counters miss the tail."*

### Pass 1 — calibrate (sampled)

30 per population, stratified, sampled not cherry-picked. Purpose is not the answer; it is
the four things that make pass 2 possible and affordable:

1. a **definition** of property-style, from what the sample actually shows (Q1)
2. an **error rate** for the automated classifier, measured against hand adjudication
3. a **reconciliation rate** per population, which sizes pass 2 and says which populations
   are worth an exhaustive pass at all
4. a **first residual list**, which is what tells you whether the study is worth continuing

**Stops** on sample completion. Cheap, and its result may legitimately be "population N is
uniform, exhaustive adds nothing" — that is a finding, and it is the only honest way to
*earn* skipping a census.

### Pass 2 — census (exhaustive on the populations pass 1 says matter)

Every site in the chosen populations adjudicated. Feasible precisely because pass 1 produced
the classifier and measured its error rate; without that, a census is 1,700+ hand
adjudications and will not happen.

**Stops** on two conditions, both required:

- **census complete** — every site in the chosen populations has a verdict; and
- **residual dry** — two consecutive population-slices add no new *kind* of gap. A slice
  that adds the twentieth instance of a known gap is not new; one that adds the first
  instance of an unseen shape is.

Q1's total may stay a rough estimate throughout (§Q1). Nothing downstream needs it precise —
it sizes the work and nothing else.

### Bounds that survive both passes

- **Q4 stays bounded to one population** — the `check*` batteries, most uniform and least
  served by anything we ship. Q4 is a product deliverable, not a measurement; a census of
  conversions is not a coherent goal.
- **Q5 exhaustive on generator *idioms*** (a small closed set) from the start, sample-based
  on sites. The idiom set is what feeds the generator spec; site counts only weight it.

## 7. Ordering — what actually depends on what

```
Q1 (define + count)
 └─▶ Q2 (reconcile; freeze key)      ─┬─▶ Q3 (blinded source-only recall)   ← highest value
                                      └─▶ Q5 (generator classification)     ← independent, cheap
Q4 prerequisite: TestSuiteParser + AssertionAnchor extensions
 └─▶ Q4 (transform)                                                         ← needs Q2's key

Shared prerequisite for Q3a: suppressed laws must stay countable
 (also wanted by access-level-analysis-gate-scope.md §2 — build once, two studies use it)
```

Q5 does not depend on Q2 and can run in parallel. Q4's *prerequisite* is independent of
everything and is the cheapest thing here with a shipped artefact at the end — a reasonable
first move if the study needs to show value early.

## 8. Risks

- **This corpus keeps correcting us, in both directions.** Two defects in a day; a wrong
  read of a `SIGBUS`; a private-function share off by 10×; a comparator template 50% false;
  a "reciprocal labels" signal that re-derived the opposite of a decision cycle-11 had
  already measured. Budget for being wrong and for recording it, and prefer measurements
  that the shipped code produces over scripts written to describe it.
- **`validation-test/stdlib` may overturn §2's headline.** If the algebraic families are
  hand-rolled 263 times, "the corpus is a ceiling on human property vocabulary" needs
  rewriting rather than citing.
- **Q4 could become a fork.** Converting upstream tests is only useful if it is upstreamable
  or reproducible; a pile of local rewrites is a maintenance liability. Decide the target
  (upstream PR / local fixture corpus / neither) *before* converting the second suite.
