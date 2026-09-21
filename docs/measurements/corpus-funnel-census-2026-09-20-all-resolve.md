# Every repository resolves — the funnel, re-run a third time

> **Status:** `measured` · **As of:** 2026-09-20
>
> The **third** run of 20 September, and the sixth of the walk. Its predecessors that day are
> [`corpus-funnel-census-2026-09-20.md`](corpus-funnel-census-2026-09-20.md) and
> [`-after-widening`](corpus-funnel-census-2026-09-20-after-widening.md).

Same 19 repositories, same harness, same binary as the run before it —
SwiftInferProperties `bf389d65` — 51 minutes, no errors. **Nothing in the toolchain changed.**
What changed is four *subjects*, which were holding dependency pins the kit's graph excludes.

> **Answer: compiles 597 → 634 and passes 515 → 547, on the same 905 stubs. For the first time,
> every repository with a SwiftPM manifest resolves and every emitted stub is attempted.**

## The funnel

| stage | 20 Sep | after widening | **all resolve** | vs prev |
|---|---:|---:|---:|---:|
| named seeds | 2,738 | 2,738 | **2,738** | ±0 |
| any law proposed | 1,921 | 1,921 | **1,921** | ±0 |
| refutable law proposed | 939 | 939 | **939** | ±0 |
| stub file written | 915 | 905 | **905** | ±0 |
| **stub compiles** | 553 | 597 | **634** | **+37** |
| **law passes** | 471 | 515 | **547** | **+32** |

✅ **The three upstream stages are identical to the digit for a second consecutive run.** A
dependency pin decides whether a stub can be *built*; it was never going to move what discovery
sees, and the funnel says so rather than being asserted to.

## Exactly the four that changed moved

| repo | stubs | compiles | passes |
|---|---:|---:|---:|
| **SwiftUMLStudio** | 43 | 0 → **13** | 0 → **11** |
| **pbt-workbook-corpus** | 20 | 0 → **19** | 0 → **18** |
| **pbt-workbook-sampler** | 4 | 0 → **4** | 0 → **3** |
| **pbt-workbook** | 1 | 0 → **1** | 0 → 0 |
| every other repository | — | unchanged | unchanged |

**Fifteen repositories are identical on all three bars.** Two of them (MacCloud_client_MacOS,
SwiftLintRuleStudioTeam) emit no stubs at all — an Xcode project and a Tuist project, neither with
a SwiftPM manifest, and that limit is unchanged.

## What was fixed, and in whose code

68 stubs had been emitted and compiled nowhere **for four runs**. Two distinct pins:

- **SwiftUMLBridge** pinned swift-syntax `from: "600.0.0"`, which resolves to
  `600.0.0..<601.0.0` and excludes the kit's `602..<603`.
- **pbt-workbook-grader** pinned `swift-property-based` `.upToNextMinor(from: "1.2.0")` — 1.2.x
  against the kit's 2.x — and its manifest said so: *"Engine pinned to 1.2.x, inherited by every
  consumer."* The corpus, sampler and workbook inherit it.

`PropertyLawKit` imports neither library. SwiftPM resolves the whole graph regardless.

**Five pull requests across four repositories, and no source changed anywhere.** Every package
built and passed its existing tests on the new pins: SwiftUMLBridge **950**, grader **17**, corpus
**119**, sampler **16**, workbook **109** — **1,211 green**. The chain needed two releases: grader
→ engine 2.x tagged **0.4.0**, corpus → grader 0.4.x tagged **0.6.0**.

⚠ **68 became compilable and produced 37 compiles, not 68 — and the two halves converted very
differently.** The three workbook packages went **25 → 24**, nearly everything. SwiftUMLStudio went
**43 → 13**, and its remaining 30 were never about the pin: **16 a `private` subject, 11 no
generator**, 3 assorted. **A stub that has never been *attempted* is not a law waiting**, and this
is the cleanest measurement of that distinction the walk has produced.

✅ **Those 16 are a second subject for the widening rule** — the first time this cycle it has had
anywhere to point but SwiftProjectLint.

⚠ **A deliberate pin was loosened, and that is a cost.** `.upToNextMinor` was a reproducibility
guarantee for a book's lab exercises; `from: "2.0.0"` is not. Flagged in each pull request: if
readers' runs must stay reproducible across the 2.x line, all three want
`.upToNextMinor(from: "2.0.0")` instead. **Left as the subject owner's decision, not taken here.**

## The last stage adds up, live

[The run before this](corpus-funnel-census-2026-09-20-after-widening.md) found
`compiled − (passed + failed)` reading 29 with nothing printing it. The columns shipped for that
ran live here for the first time:

| | stubs |
|---|---:|
| passed | 547 |
| failed | 58 |
| trapped | 23 |
| unaccounted | 6 |
| **compiled** | **634** |

**547 + 58 + 23 + 6 = 634.** And the per-repository figures reproduce the retro-analysis exactly —
pbt-book `crashed 21 unaccounted 5`, SwiftLintRuleStudio `unaccounted 1`, SwiftAssist and
SwiftEffectInference 1 crash each.

## ⚠ Yield rose again and bug-finding did not

Failures **53 → 58**, and **all five new ones are in the four repositories that could not build
before** — the only place a new failure could come from. By shape:

| template | failures |
|---|---:|
| `idempotence` | **33** |
| `state-machine` · `guard-domain` · `round-trip` | 15 |
| `commutativity` · `monotonicity` · `associativity` | 9 |
| `filter-subset` | 1 |

`idempotence` still dominates, and it is still the arm measured at **18 of 18 hand-checked false of
correct code**. Across the whole day — 553 → 634 compiles, 471 → 547 passes — **not one new real
defect was found.** A pass remains *no counterexample in 100 draws*; no planted violator was run,
in this census or its five predecessors.

## By repository

| repo | seeds | named | stubs | compiles | passes |
|---|---:|---:|---:|---:|---:|
| SwiftProjectLint | 1,029 | 746 | 424 | 295 | 292 |
| SwiftAssist | 438 | 326 | 76 | 48 | 38 |
| SwiftPropertyLaws | 338 | 294 | 45 | 38 | 33 |
| SwiftLintRuleStudio | 292 | 234 | 41 | 19 | 16 |
| SwiftUMLStudio | 284 | 238 | 43 | 13 | 11 |
| pbt-workbook-corpus | 194 | 186 | 20 | 19 | 18 |
| pbt-book | 152 | 144 | 127 | 104 | 57 |
| SwiftFormatRuleStudio | 147 | 113 | 19 | 17 | 16 |
| SwiftEffectInference | 114 | 103 | 33 | 26 | 24 |
| SwiftMarkdownWiki | 103 | 84 | 35 | 28 | 24 |
| SwiftLintRuleStudioTeam | 102 | 80 | 0 | 0 | 0 |
| SwiftCloneDetector | 74 | 50 | 14 | 6 | 6 |
| MacCloud_client_MacOS | 44 | 43 | 0 | 0 | 0 |
| pbt-workbook-sampler | 26 | 25 | 4 | 4 | 3 |
| LintStudioUI | 24 | 24 | 5 | 5 | 3 |
| MacCloud_server | 22 | 21 | 13 | 8 | 6 |
| SwiftIdempotency | 16 | 12 | 4 | 2 | 0 |
| pbt-workbook | 12 | 8 | 1 | 1 | 0 |
| pbt-workbook-grader | 8 | 7 | 1 | 1 | 0 |

## Adjustments, stated

The seed binary is the one the previous two runs used, deliberately. `SwiftPropertyLaws/Package.swift`
carries the same uncommitted test-target removal. Subject SHAs: SwiftProjectLint `fbf82dc9`,
SwiftUMLStudio `764ce9f`, pbt-workbook-corpus `0ea4b22`, pbt-workbook-sampler `0e07795`,
pbt-workbook `959937e`, pbt-workbook-grader `79e6c81`.

⚠ **The set-aside classification was NOT re-taken.** The *what is stopping the rest* figures still
quoted are the previous run's, and 271 stubs are now set aside against that run's 240 — the
difference being SwiftUMLStudio's 30, which this page classifies but the corpus-wide table does
not.

## Reproducing

```
python3 scripts/corpus_funnel.py <out-dir> <swift-infer> <SwiftProjectLint CLI> <repo>...
```
