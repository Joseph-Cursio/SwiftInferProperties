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

**These three are the study's scope, and that is a starting point rather than a boundary.**
§3a is the expansion, deliberately sequenced after pass 1 rather than folded in now.

## 3a. Expansion — ranked, and not before pass 1

Fourteen further swift.org / Apple repos are checked out locally (eight cloned 2026-07-30
for this survey). Measured at the SHAs below — `check*` call sites, `for _ in 0..<N` loops,
`XCTestCase` + `@Test` (what `TestSuiteParser` can currently see), and adjudicated
round-trip mentions:

| repo | SHA | `check*` | loops | recognisable | round-trip |
|---|---|---:|---:|---:|---:|
| **swift-collections** | `899809d3` | **196** | 4 | 19 | 0 |
| **swift-nio** | `590dd7b4` | 118 | **119** | 431 | 20 |
| **swift-protobuf** | `309bd28f` | 3 | 3 | 95 | **118** |
| **swift-atomics** | `0442cb5` | **76** | 0 | 33 | 0 |
| **swift-certificates** | `449dbbe` | 0 | 3 | 30 | **71** |
| **swift-markdown** | `27b7fc1` | **60** | 0 | 48 | **35** |
| swift-asn1 | `a9a5efd` | 0 | 0 | 4 | 27 |
| swift-numerics | `899af71` | 11 | 3 | 16 | 2 |
| swift-format | `d2bd4b3` | 18 | 2 | 114 | 0 |
| swift-algorithms | `ff223da` | 8 | 0 | 29 | 0 |
| swift-system | `6a63f08` | 2 | 3 | 26 | 0 |
| swift-testing | `e57b6fb0` | 15 | 4 | 1107 | 8 |
| swift-async-algorithms | `3da39bb` | 1 | 1 | 125 | 6 |
| swift-http-types | `5b99e00` | 0 | 0 | 3 | 0 |

**Two columns were dropped after adjudication, and the reason is Q1's hazard arriving inside
this table's own construction.** A first pass also counted `associat*` and `idempot*` as
property vocabulary and produced numbers that looked decisive:

| apparent signal | what it actually was |
|---|---|
| swift-collections "associativity" ×92 | 54 `associated`, 25 `associatedtype` — **zero** are the law |
| swift-protobuf "idempotence" ×315 | 214 `idempotencyLevel`, 68 `_p` variants — protobuf's `idempotency_level` **method option**, domain vocabulary from the `.proto` spec |

Both would have ranked repos wrongly and confidently. This is the same failure the earlier
survey's classifier had (*"it read `result == Decimal(12340)` as a round-trip"*), reproduced
here in the space of one command — which is the argument for Q1's "hand-adjudicate first"
rule, now with a second witness. The round-trip column above survived the same check
(swift-markdown's 35 are bare `roundtrip` plus `RoundTripTests` / `roundTripBlockquote`).

**The ranking criterion is not size — it is whether a repo adds a new POPULATION or more
sites of an existing one.** More sites tightens an error bar. A new population can falsify a
conclusion. They are not comparable, and counting sites would rank these wrongly.

### Tier 1 — `swift-collections`, and it is not close

196 `check*` sites in `_CollectionsTestSupport` is a **second axiom battery, independent of
`StdlibUnittest`**. That makes it the only repo here that can answer a question the pinned
three cannot: *is the battery idiom a property of Swift library testing, or one team's
habit?* Two independent teams converging on `checkEquatable`-shaped law suites is a much
stronger claim than 263 sites of one team's, and it directly tests §2's suspect conclusion
about human property vocabulary.

It is also **recognisable to TestLifter today** (6 `XCTestCase`, 13 `@Test`), which the
pinned corpus is not — see the re-ordering note below.

### Tier 2 — a round-trip corpus we do not have: `swift-markdown`, `swift-certificates`, `swift-protobuf`

Three repos whose *whole domain* is the round-trip law, at 118 / 71 / 35 adjudicated
mentions and all recognisable to TestLifter today (95 / 30 / 48).

This matters more than the counts suggest, because round-trip is the template we just
measured as **~100% false on this repo and precise on Foundation** — the difference being
that Foundation's are genuine `A -> B` / `B -> A` pairs and ours were endomorphisms. A
serializer, a DER encoder, and a markdown printer are three independent corpora of *real*
opposite-typed round-trips, which is exactly the population that would either confirm the
`endomorphismRoundTripPair` counter-signal or expose it as over-broad. We have one
confirming corpus; three more would settle it.

`swift-markdown` doubles as a **parser** subject, which puts it directly against
`parsing-catalog-gap.md`'s findings — its `parse`/`format` pair is the shape §3c of that
survey said we could not reach until `CustomStringConvertible.description` pairing shipped.

### Tier 2 — `swift-nio`

Large (118 `check*`, 119 loops) and the most recognisable non-framework repo (431). Its
value is **domain breadth**, not depth: networking laws are not stdlib algebra, so it tests
whether the catalog generalises past value types. Expect a different failure mode from Tier
1 — gaps rather than declines.

### Needs adjudication before tiering — `swift-atomics`

76 `check*` sites, no loops, no round-trip vocabulary. That combination does not match any
population defined so far, and the name suggests a generated conformance matrix rather than
an axiom battery. **Adjudicate 10 sites before deciding**, and if it is a new idiom, it is a
new population and outranks Tier 2.

### Tier 3 — `swift-numerics`, `swift-algorithms`

Small populations (11 and 8), but these are the classic algebraic corpora and **this
project's own findings already cite them 27 and 34 times** — the cycle-8 ComplexModule
survey, the `_ensureFreeCapacity` delegation case, the access-default calibration. Their
value is **consistency checking against claims we already made**, not new discovery. Cheap,
and the place a contradiction with our own record would surface.

### Excluded — and one of the exclusions is itself a finding

`swift-testing` (1,107 recognisable) is a testing *framework* testing itself; its properties
are about assertion machinery, not a domain the catalog models. High volume, low relevance —
the kind of population that inflates a denominator. `swift-async-algorithms`,
`swift-http-types`, `swift-system` and `swift-asn1` have no meaningful population.

**`swift-format` is excluded, and that is the interesting one.** A formatter's law *is*
idempotence — `format(format(x)) == format(x)` — and this repo's own parsing survey spent a
whole finding on formatter idempotence, splitting the `format`-prefix veto to admit it. Yet
swift-format mentions idempotence **3 times** across 114 recognisable tests, and has no
round-trip vocabulary at all.

Either it verifies the law structurally without naming it, or **it does not test its own
central property** — and the second is a Q2 "their precision" candidate of exactly the kind
that produced `swiftlang/swift#91083`. Cheap to check, and worth checking before excluding it
for good: it is a one-repo answer to "does the catalog know a law its author forgot?", which
is the strongest form this project's thesis can take.

### This re-orders Q4, and that is the useful part

Q4 is blocked on `TestSuiteParser` not recognising `TestSuite.test("…") { }` closures —
`validation-test/stdlib` scores **0** `XCTestCase` and **0** `@Test`. But the expansion repos
are the opposite: swift-nio 288 `@Test`, swift-collections 13, swift-testing 1,071.

**So Q4 can be attempted on Tier 1/2 *before* the parser work lands**, on the recognisable
subset, and the parser extension can be prioritised by what that attempt actually needs
rather than by what the pinned corpus implies. That inverts the dependency in §7 for the
expansion, and it is the cheapest route to a Q4 result.

### Sequencing, and why not now

**Do not expand before pass 1 concludes on the pinned three.** Pass 1's output is a
definition, a classifier, and its error rate; expanding first means scaling an unvalidated
method across six more repos and re-adjudicating when the definition moves. The classifier is
the thing that makes a census affordable, and it does not exist yet.

The one exception worth taking early: **run the Tier-1 population count** (a `check*` census
on `swift-collections`) as soon as pass 1 has a definition, because if that battery does not
match `StdlibUnittest`'s shape, §2's conclusion needs rewriting before Q2 is built on it.

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

**The headline number is the as-shipped success rate, WITH every channel enabled.**

The channels below were first written up here as "leakage to control for", as though they
were contamination to subtract. That framing is wrong, and stripping them out would produce
a number that answers an academic question instead of the product one. If `discover` finds a
law because the docstring says "idempotent", **the tool found the law** — the reader gets it,
and prose is a legitimate evidence channel we deliberately built.

So report both, and in this order:

1. **As-shipped recall** — fraction of the frozen key that `discover` reaches with everything
   on. This is what a user experiences and it is the headline.
2. **Additive decomposition** of that same number by channel — what tells us what to build.

The second is a decomposition *of* the first, not a competing figure. Neither subsumes the
other and reporting only one is how this gets misread.

**Channels overlap, so "buckets" is the wrong data model.** A law can be reached by shape
*and* name *and* docstring at once. Record a channel **set** per key entry, then report:

| measure | definition | answers |
|---|---|---|
| **as-shipped recall** | reached by any channel | what does the tool do today |
| **unique contribution** | reached by *only* channel X | what would break if X were deleted |
| **marginal contribution** | reached, but would fall below the tier cut without X's weight | what is X actually worth |

Marginal contribution is computable **without new flags**: every signal and its weight is in
the rendered explainability, so subtract X's weight from the score and re-apply
`Tier(score:)`. No instrumentation, and it cannot drift from the shipped arithmetic.

**The channels:**

- **Docstrings.** `DocstringPropertyCorroborator` reads prose. If a source docstring says
  "idempotent", the source did tell us — that is legitimate inference, but it must be
  *attributed* separately from shape/name inference, or Q3's answer is inflated by the very
  thing Q3 is asking about. Report three buckets: shape-only, name-only, docstring-assisted.
- **Curated vocabulary.** A law found because `encode`/`decode` is in `curatedInversePairs`
  is found by *our* prior knowledge, not by the source. Also its own bucket.
- **Protocol conformance.** `checkEquatable` fires on `Equatable` types, and conformance is in
  the source, so a law *role-entailed by conformance* is trivially available and belongs in
  its own channel. (Measured separately already: conformance does not predict refutability —
  `fixtures/equatable-signal/README.md`.) But see Q3d: on this corpus conformance mostly does
  not *add* recall, it **removes** it, deliberately.

#### Q3d — a third outcome that is not a miss: declined as another tool's job

`ProtocolCoverageMap` treats a law covered by a conformance as **redundant, full veto** —
*"the kit's `check<Protocol>PropertyLaws` is authoritative … re-reporting another tool's
finding teaches people the tools disagree."* And independently, both templates that could
state the `check*` batteries' laws **exclude operators by design**:
`EquivalenceRelationTemplate` (*"`==` is `Equatable`'s and the kit already runs its law"*) and
`ComparatorTemplate` (*"`==` is `Equatable`'s, `<` is `Comparable`'s"*).

The `check*` batteries test exactly those operators. So on that population `discover` will
propose **nothing**, and that is neither cause (a) nor (b) from Q3a:

| | |
|---|---|
| **(c) declined** | we understand the shape perfectly and decline it because PropertyLawKit runs the law |

**From a toolchain perspective (c) is a success, not a miss** — the law *is* executed, by
`checkEquatablePropertyLaws` rather than by a generated stub. Which means the study needs
success measured at two levels, and must not report the narrower one as "our recall":

| level | question | expected on `check*` |
|---|---|---|
| **toolchain coverage** | is this law runnable by anything we ship — a `discover` stub **or** a kit conformance check? | **high** |
| **discover recall** | does `discover` itself propose it? | **near zero, by design** |

Level 1 is the number that matters to a user. Level 2 is the number that matters to the
catalog. A study reporting only level 2 would conclude the tool fails on the corpus's largest
uniform population, when in fact the toolchain covers it and the catalog is deliberately
staying out of the way.

**Correcting my own registered prediction, rather than editing it away.** Q3b below predicts
"`check*` batteries → recall should be HIGH, and trivially so, because those laws are
role-entailed by conformance." That is **wrong**, and wrong in the interesting direction:
role-entailment by conformance is precisely why `discover` *declines* them. The prediction is
kept as written in Q3b with this pointer, because a pre-registered prediction that gets
quietly corrected was never pre-registered.

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

  > **Retracted before the study ran — see Q3d.** This is wrong. Role-entailment by
  > conformance is exactly why `discover` **declines** these, and both candidate templates
  > exclude operators by design. Expect near-zero `discover` recall here with high *toolchain*
  > coverage. Left standing rather than edited, because a pre-registered prediction that gets
  > quietly corrected was never pre-registered. Predicting the sign wrong on the largest
  > uniform population, from reading the code, is itself a result worth keeping visible.
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
